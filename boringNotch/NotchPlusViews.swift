import AppKit
import Defaults
import SwiftUI

private let plusAccent = Color.mint

struct PlusEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(plusAccent)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(detail).font(.caption).foregroundStyle(.gray).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardHistoryView: View {
    @StateObject private var history = ClipboardHistory.shared
    @State private var query = ""
    @State private var pinnedOnly = false
    @State private var copiedID: UUID?
    @State private var showClear = false
    @FocusState private var searching: Bool

    private var filtered: [ClipRecord] {
        history.records.filter {
            (!pinnedOnly || $0.pinned) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.source.localizedCaseInsensitiveContains(query)
                || ($0.kind == .text && String(decoding: $0.payload, as: UTF8.self).localizedCaseInsensitiveContains(query)))
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.gray)
                    TextField("Поиск в истории", text: $query)
                        .textFieldStyle(.plain).focused($searching)
                }
                .padding(8).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                Button { pinnedOnly.toggle() } label: {
                    Image(systemName: pinnedOnly ? "pin.fill" : "pin")
                        .foregroundStyle(pinnedOnly ? plusAccent : .gray)
                }.help("Только закреплённые")
                Button { history.enabled.toggle() } label: {
                    Image(systemName: history.enabled ? "pause.circle" : "play.circle")
                }.help(history.enabled ? "Приостановить запись истории" : "Включить запись истории")
                Button { showClear = true } label: { Image(systemName: "trash") }
                    .help("Очистить историю")
                    .popover(isPresented: $showClear) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Очистить историю?").font(.headline)
                            Button("Очистить, сохранив закреплённые") { history.clear(); showClear = false }
                            Button("Удалить всё, включая закреплённые", role: .destructive) {
                                history.clear(includingPinned: true); showClear = false
                            }
                            Button("Отмена") { showClear = false }
                        }.padding()
                    }
            }
            if filtered.isEmpty {
                PlusEmptyState(icon: "doc.on.clipboard", title: query.isEmpty ? "История буфера обмена" : "Ничего не найдено",
                    detail: query.isEmpty ? "Скопируй текст, ссылку, файл или небольшую картинку.\nНажми на запись, чтобы скопировать её снова." : "Попробуй другое слово или отключи фильтр закреплений.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(filtered) { record in
                            HStack(spacing: 8) {
                                Button {
                                    history.copy(record)
                                    copiedID = record.id
                                    searching = false
                                } label: {
                                    HStack(spacing: 10) {
                                        thumbnail(record)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(record.title.replacingOccurrences(of: "\n", with: " "))
                                                .lineLimit(1).foregroundStyle(.white)
                                            Text("\(record.source) · \(record.date.formatted(date: .omitted, time: .shortened))")
                                                .font(.caption2).foregroundStyle(.gray)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: copiedID == record.id ? "checkmark" : "doc.on.doc")
                                            .foregroundStyle(copiedID == record.id ? plusAccent : .gray)
                                    }.contentShape(Rectangle())
                                }
                                .help("Скопировать. Затем нажми ⌘V в нужном приложении.")
                                Button { history.pin(record) } label: {
                                    Image(systemName: record.pinned ? "pin.fill" : "pin")
                                        .foregroundStyle(record.pinned ? plusAccent : .gray)
                                }.help(record.pinned ? "Открепить" : "Закрепить")
                                Button { history.delete(record) } label: {
                                    Image(systemName: "xmark").font(.caption2).foregroundStyle(.gray)
                                }.help("Удалить запись")
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }.scrollIndicators(.never)
            }
            HStack {
                Circle().fill(history.enabled ? plusAccent : .orange).frame(width: 5, height: 5)
                Text(history.enabled ? "Локально · \(history.records.count)/120 · до 16 МБ" : "Запись приостановлена")
                Spacer()
                Text(history.error ?? "Пароли с защитной меткой не сохраняются")
                    .foregroundStyle(history.error == nil ? Color.gray : Color.orange)
            }.font(.system(size: 10)).foregroundStyle(.gray)
        }
        .buttonStyle(.plain)
        .onChange(of: query) { copiedID = nil }
    }

    @ViewBuilder private func thumbnail(_ record: ClipRecord) -> some View {
        if record.kind == .image, let image = history.thumbnail(for: record) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 32)
        } else {
            Image(systemName: record.kind == .file ? "doc.fill" : "text.alignleft")
                .foregroundStyle(plusAccent).frame(width: 32, height: 32)
                .background(plusAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

struct PlusCalendarView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var manager = CalendarManager.shared
    @Default(.showCalendar) private var enabled

    var body: some View {
        Group {
            if !enabled {
                VStack(spacing: 10) {
                    PlusEmptyState(icon: "calendar", title: "Календарь отдельно", detail: "События и напоминания — в своей вкладке.")
                    Button("Включить календарь") {
                        enabled = true
                        Task { await manager.checkCalendarAuthorization(); await manager.checkReminderAuthorization() }
                    }.buttonStyle(.bordered)
                }
            } else if manager.calendarAuthorizationStatus == .denied || manager.calendarAuthorizationStatus == .restricted {
                VStack(spacing: 10) {
                    PlusEmptyState(icon: "calendar.badge.exclamationmark", title: "Нужен доступ к календарю",
                        detail: "Разреши Notch Plus показывать события в настройках macOS.")
                    Button("Открыть настройки доступа") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }.buttonStyle(.bordered)
                }
            } else {
                CalendarView(contentHeight: 205)
                    .onHover { vm.isHoveringCalendar = $0 }
                    .onDisappear { vm.isHoveringCalendar = false }
            }
        }
        .task {
            if enabled { await manager.checkCalendarAuthorization(); await manager.checkReminderAuthorization() }
        }
    }
}

struct FocusTimerView: View {
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 7)
                Circle().trim(from: 0, to: min(1, max(0, timer.clock.remaining / timer.clock.duration)))
                    .stroke(plusAccent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(timer.display).font(.system(size: 36, weight: .light, design: .rounded)).monospacedDigit()
                    Text(timer.clock.finished ? "Готово!" : timer.clock.isBreak ? "ПЕРЕРЫВ" : "ФОКУС")
                        .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(plusAccent)
                }
            }.frame(width: 160, height: 160)
            VStack(alignment: .leading, spacing: 14) {
                Text(timer.clock.finished ? "Время переключиться" : "Время для одного дела").font(.headline)
                Text(timer.clock.finished ? "Сделай перерыв или начни новый сеанс." : "Выбери длительность и убери лишнее.")
                    .font(.caption).foregroundStyle(.gray)
                HStack(spacing: 6) {
                    ForEach([15, 25, 45], id: \.self) { minutes in
                        Button("\(minutes) мин") { timer.reset(minutes: minutes, isBreak: false) }
                            .tint(!timer.clock.isBreak && Int(timer.clock.duration / 60) == minutes ? plusAccent : .gray)
                    }
                }.buttonStyle(.bordered)
                HStack(spacing: 8) {
                    Button { timer.toggle() } label: {
                        Label(timer.clock.deadline == nil ? "Начать" : "Пауза",
                            systemImage: timer.clock.deadline == nil ? "play.fill" : "pause.fill")
                    }.buttonStyle(.borderedProminent).tint(plusAccent).foregroundStyle(.black)
                    Button { timer.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.bordered).help("Сбросить таймер")
                    Button("Перерыв 5 мин") { timer.reset(minutes: 5, isBreak: true) }.buttonStyle(.bordered)
                }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QuickNotesView: View {
    @StateObject private var notes = QuickNotes.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Быстрая заметка", systemImage: "square.and.pencil").font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(notes.text, forType: .string)
                    copied = true
                } label: { Label(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.plain).foregroundStyle(plusAccent).disabled(notes.text.isEmpty)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes.text)
                    .font(.system(size: 13)).scrollContentBackground(.hidden)
                    .padding(6)
                if notes.text.isEmpty {
                    Text("Мысль, задача или ссылка, которую хочется сохранить…")
                        .foregroundStyle(.gray).padding(11).allowsHitTesting(false)
                }
            }
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text(notes.error ?? "Автосохранение на этом Mac · Esc — закрыть")
                    .foregroundStyle(notes.error == nil ? Color.gray : Color.orange)
                Spacer()
                Text("\(notes.text.count)/30 000").foregroundStyle(.gray)
            }.font(.system(size: 10))
        }
        .onChange(of: notes.text) { copied = false }
    }
}
