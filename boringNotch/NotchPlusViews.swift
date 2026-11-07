import AppKit
import Defaults
import SwiftUI

struct PlusEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(Color.accentColor)
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
                        .foregroundStyle(pinnedOnly ? Color.accentColor : .gray)
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
                                            .foregroundStyle(copiedID == record.id ? Color.accentColor : .gray)
                                    }.contentShape(Rectangle())
                                }
                                .help("Скопировать. Затем нажми ⌘V в нужном приложении.")
                                Button { history.pin(record) } label: {
                                    Image(systemName: record.pinned ? "pin.fill" : "pin")
                                        .foregroundStyle(record.pinned ? Color.accentColor : .gray)
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
                Circle().fill(history.enabled ? Color.accentColor : .orange).frame(width: 5, height: 5)
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
                .foregroundStyle(Color.accentColor).frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
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
