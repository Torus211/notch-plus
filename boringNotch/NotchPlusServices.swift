import AppKit
import Combine
import ImageIO

/// Serial, atomic writes keep disk work away from animations and text input.
final class NotchPlusStorage {
    static let shared = NotchPlusStorage()
    private let queue = DispatchQueue(label: "local.torus.notchplus.storage", qos: .utility)
    private var pending: [String: DispatchWorkItem] = [:] // main-thread access only
    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchPlus", isDirectory: true)

    func read(_ name: String, limit: Int) -> Data? {
        let url = root.appendingPathComponent(name)
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= limit else { return nil }
        return try? Data(contentsOf: url)
    }

    func write(_ data: Data, name: String, report: @escaping (String?) -> Void) {
        schedule({ data }, name: name, report: report)
    }

    func writeJSON<T: Encodable>(_ value: T, name: String, report: @escaping (String?) -> Void) {
        schedule({ try JSONEncoder().encode(value) }, name: name, report: report)
    }

    private func schedule(_ data: @escaping () throws -> Data, name: String, report: @escaping (String?) -> Void) {
        pending[name]?.cancel()
        let url = root.appendingPathComponent(name)
        let root = root
        let work = DispatchWorkItem {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                try data().write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                DispatchQueue.main.async { report(nil) }
            } catch {
                DispatchQueue.main.async { report("Не удалось сохранить данные на диск.") }
            }
        }
        pending[name] = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func flush() {
        for work in pending.values { work.cancel() }
        // Submit current snapshots without debounce before normal application termination.
        pending.removeAll()
        queue.sync { }
    }

    func writeImmediately(_ data: Data, name: String) {
        let root = root
        queue.sync {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let url = root.appendingPathComponent(name)
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

@MainActor
final class ClipboardHistory: ObservableObject {
    static let shared = ClipboardHistory()
    @Published private(set) var records: [ClipRecord] = []
    @Published var error: String?
    @Published var enabled: Bool = !UserDefaults.standard.bool(forKey: "np.clipboardPaused") {
        didSet {
            UserDefaults.standard.set(!enabled, forKey: "np.clipboardPaused")
            updateMonitoring()
        }
    }
    private let pasteboard: NSPasteboard
    private var changeCount: Int
    private var timer: Timer?
    private var sleeping = false
    private var locked = false
    private var observers: [NSObjectProtocol] = []
    private let thumbnails = NSCache<NSString, NSImage>()

    private init() {
        pasteboard = .general
        changeCount = NSPasteboard.general.changeCount
        if let data = NotchPlusStorage.shared.read("clipboard.json", limit: 24 * 1024 * 1024),
           let saved = try? JSONDecoder().decode([ClipRecord].self, from: data) {
            records = ClipRecord.bounded(saved)
        }
        thumbnails.countLimit = 24
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleeping = true; self?.updateMonitoring() }
            })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleeping = false; self?.updateMonitoring() }
            })
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.locked = value; self?.updateMonitoring() }
                })
        }
        updateMonitoring()
        // macOS exposes the current pasteboard item even before this app starts.
        // Earlier history belongs to other clipboard managers and is not an OS API.
        if enabled {
            changeCount = -1
            captureIfChanged()
        }
    }

    private func updateMonitoring() {
        timer?.invalidate()
        timer = nil
        changeCount = pasteboard.changeCount
        guard enabled, !sleeping, !locked else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureIfChanged() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func captureIfChanged() {
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType"])
        else { return }

        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Mac"
        let record: ClipRecord
        if let path = pasteboard.string(forType: .fileURL), let url = URL(string: path), url.isFileURL {
            record = ClipRecord(kind: .file, payload: Data(path.utf8), title: url.lastPathComponent, source: source)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty,
                  text.utf8.count <= 64 * 1024 {
            record = ClipRecord(kind: .text, payload: Data(text.utf8),
                title: String(text.prefix(250)), source: source)
        } else if let data = pasteboard.data(forType: .png), data.count <= ClipRecord.payloadLimit, safeImage(data) {
            record = ClipRecord(kind: .image, payload: data, title: "Изображение", source: source)
        } else if let data = pasteboard.data(forType: .tiff), data.count <= ClipRecord.payloadLimit, safeImage(data),
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]), png.count <= ClipRecord.payloadLimit {
            record = ClipRecord(kind: .image, payload: png, title: "Изображение", source: source)
        } else { return }

        var incoming = record
        if let existing = records.first(where: { $0.kind == record.kind && $0.payload == record.payload }) {
            incoming.id = existing.id
            incoming.pinned = existing.pinned
            records.removeAll { $0.id == existing.id }
        }
        records = ClipRecord.bounded([incoming] + records)
        save()
    }

    func copy(_ record: ClipRecord) {
        pasteboard.clearContents()
        switch record.kind {
        case .text: pasteboard.setString(String(decoding: record.payload, as: UTF8.self), forType: .string)
        case .file:
            if let url = URL(string: String(decoding: record.payload, as: UTF8.self)) {
                pasteboard.writeObjects([url as NSURL])
            }
        case .image: pasteboard.setData(record.payload, forType: .png)
        }
        changeCount = pasteboard.changeCount
    }

    func thumbnail(for record: ClipRecord) -> NSImage? {
        let key = record.id.uuidString as NSString
        if let image = thumbnails.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithData(record.payload as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 80,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: 40, height: 40))
        thumbnails.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    func pin(_ record: ClipRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].pinned.toggle()
        records = ClipRecord.bounded(records)
        save()
    }

    func delete(_ record: ClipRecord) {
        records.removeAll { $0.id == record.id }
        thumbnails.removeObject(forKey: record.id.uuidString as NSString)
        save()
    }

    func clear(includingPinned: Bool = false) {
        records = includingPinned ? [] : records.filter(\.pinned)
        thumbnails.removeAllObjects()
        save()
    }

    private func save() {
        NotchPlusStorage.shared.writeJSON(records, name: "clipboard.json") { [weak self] in self?.error = $0 }
    }

    private func safeImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int,
              let height = info[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width > 0 && height > 0 && width <= 4096 && height <= 4096 && width * height <= 4_000_000
    }

    func flush() {
        if let data = try? JSONEncoder().encode(records) {
            NotchPlusStorage.shared.writeImmediately(data, name: "clipboard.json")
        }
    }
}

@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()
    @Published private(set) var clock: FocusClock
    private var timer: Timer?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "np.focus"),
           let saved = try? JSONDecoder().decode(FocusClock.self, from: data) {
            clock = saved
        } else { clock = FocusClock() }
        _ = clock.tick(at: Date())
        if clock.deadline != nil { schedule() }
    }

    var display: String {
        let seconds = Int(ceil(clock.remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func toggle() {
        if clock.deadline == nil { clock.start(at: Date()); schedule() }
        else { clock.pause(at: Date()); timer?.invalidate(); timer = nil }
        save()
    }

    func reset(minutes: Int? = nil, isBreak: Bool? = nil) {
        timer?.invalidate(); timer = nil
        clock.reset(minutes: minutes ?? Int(clock.duration / 60), isBreak: isBreak ?? clock.isBreak)
        save()
    }

    private func schedule() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.clock.tick(at: Date()) {
                    self.timer?.invalidate(); self.timer = nil
                    NSSound(named: "Glass")?.play()
                    self.save()
                }
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func save() {
        if let data = try? JSONEncoder().encode(clock) { UserDefaults.standard.set(data, forKey: "np.focus") }
    }
}

@MainActor
final class QuickNotes: ObservableObject {
    static let shared = QuickNotes()
    @Published var error: String?
    @Published var text: String {
        didSet {
            if text.count > 30000 { text = String(text.prefix(30000)) }
            NotchPlusStorage.shared.write(Data(text.utf8), name: "notes.txt") { [weak self] in self?.error = $0 }
        }
    }

    private init() {
        text = NotchPlusStorage.shared.read("notes.txt", limit: 256 * 1024)
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func flush() { NotchPlusStorage.shared.writeImmediately(Data(text.utf8), name: "notes.txt") }
}
