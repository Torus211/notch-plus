import Foundation

@main
struct CoreChecks {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            count += 1
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = FocusClock()
        clock.start(at: now)
        check(clock.deadline == now.addingTimeInterval(1500), "start sets deadline")
        clock.pause(at: now.addingTimeInterval(123))
        check(clock.remaining == 1377 && clock.deadline == nil, "pause preserves elapsed time")
        clock.start(at: now.addingTimeInterval(1000))
        check(!clock.tick(at: now.addingTimeInterval(1100)) && clock.remaining == 1277, "resume keeps remaining duration")
        check(clock.tick(at: now.addingTimeInterval(9000)) && clock.finished && clock.remaining == 0,
            "sleep/late delivery completes exactly once")
        check(!clock.tick(at: now.addingTimeInterval(9001)), "no duplicate completion")
        clock.start(at: now)
        check(clock.remaining == 1500 && !clock.finished, "restart completed session")
        clock.reset(minutes: 5, isBreak: true)
        check(clock.remaining == 300 && clock.isBreak && clock.deadline == nil, "break resets running session")
        clock.reset(minutes: 0)
        check(clock.duration == 60, "duration cannot be zero")
        let restored = try JSONDecoder().decode(FocusClock.self, from: JSONEncoder().encode(clock))
        check(restored.duration == clock.duration, "focus state persists")

        func entry(_ index: Int, bytes: Int = 8, pinned: Bool = false) -> ClipRecord {
            var record = ClipRecord(kind: .text, payload: Data(repeating: 65, count: bytes),
                title: "Record \(index)", source: "Test")
            record.date = now.addingTimeInterval(Double(index))
            record.pinned = pinned
            return record
        }
        let many = (0..<150).map { entry($0) }
        let bounded = ClipRecord.bounded(many)
        check(bounded.count == 120, "history count cap")
        check(bounded.first?.title == "Record 149" && bounded.last?.title == "Record 30", "newest first with old eviction")
        let pinned = entry(-1, pinned: true)
        check(ClipRecord.bounded(many + [pinned]).first?.id == pinned.id, "old pins survive eviction")
        let large = (0..<12).map { entry($0, bytes: 2 * 1024 * 1024, pinned: true) }
        check(ClipRecord.bounded(large).reduce(0) { $0 + $1.payload.count } <= ClipRecord.byteLimit,
            "pins cannot exceed byte cap")
        check(ClipRecord.bounded([entry(1, bytes: ClipRecord.payloadLimit + 1)]).isEmpty, "oversized item rejected on restore")
        let roundTrip = try JSONDecoder().decode([ClipRecord].self, from: JSONEncoder().encode([pinned]))
        check(roundTrip == [pinned], "clipboard identity/data/pin survive restart")
        print("Passed \(count) core checks")
    }
}
