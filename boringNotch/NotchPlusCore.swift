import Foundation

// Bounded local history; the same rules are used when capturing and restoring.
struct ClipRecord: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case text, image, file }
    var id = UUID()
    var date = Date()
    var pinned = false
    let kind: Kind
    let payload: Data
    let title: String
    let source: String

    static let itemLimit = 120
    static let byteLimit = 16 * 1024 * 1024
    static let payloadLimit = 2 * 1024 * 1024

    static func bounded(_ records: [ClipRecord]) -> [ClipRecord] {
        var bytes = 0
        var result: [ClipRecord] = []
        // Preserve pins first, then newest entries, within the hard memory limit.
        for record in records.sorted(by: {
            $0.pinned != $1.pinned ? $0.pinned : $0.date > $1.date
        }) {
            guard result.count < itemLimit, record.payload.count <= payloadLimit,
                  bytes + record.payload.count <= byteLimit else { continue }
            bytes += record.payload.count
            result.append(record)
        }
        return result
    }
}

struct FocusClock: Codable {
    var duration: TimeInterval = 25 * 60
    var remaining: TimeInterval = 25 * 60
    var deadline: Date?
    var finished = false
    var isBreak = false

    mutating func start(at now: Date) {
        if finished { remaining = duration; finished = false }
        deadline = now.addingTimeInterval(remaining)
    }

    mutating func pause(at now: Date) {
        _ = tick(at: now)
        deadline = nil
    }

    // Wall-clock deadlines stay accurate through sleep and delayed timer delivery.
    @discardableResult mutating func tick(at now: Date) -> Bool {
        guard let deadline else { return false }
        remaining = max(0, deadline.timeIntervalSince(now))
        if remaining == 0 {
            self.deadline = nil
            finished = true
            return true
        }
        return false
    }

    mutating func reset(minutes: Int, isBreak: Bool = false) {
        duration = Double(min(180, max(1, minutes))) * 60
        remaining = duration
        deadline = nil
        finished = false
        self.isBreak = isBreak
    }
}
