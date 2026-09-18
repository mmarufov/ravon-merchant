import XCTest
import RavonCore
@testable import RavonMerchant

/// Regression tests for the past-midnight schedule bug.
///
/// The old implementation compared `"18:00:00" <= now < "02:00:00"` as strings, which is
/// false at every instant, so an 18:00–02:00 restaurant was reported closed 24 hours a day
/// and the dashboard showed "Сейчас закрыто по расписанию" to a kitchen taking orders.
final class RestaurantOpenStateTests: XCTestCase {

    private let restaurantId = UUID()

    // MARK: - Helpers

    private var dushanbe: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dushanbe")!
        return calendar
    }

    /// A Dushanbe wall-clock instant. 2026-09-18 is a Friday, so 19 is Saturday and 17 is
    /// Thursday — enough to cover a window that spills across the week boundary too.
    private func dushanbeDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        dushanbe.date(from: DateComponents(
            timeZone: TimeZone(identifier: "Asia/Dushanbe")!,
            year: 2026, month: 9, day: day, hour: hour, minute: minute
        ))!
    }

    private func hours(
        _ opening: String, _ closing: String, isClosed: Bool = false, days: Range<Int> = 0..<7
    ) -> [RestaurantHours] {
        days.map { day in
            RestaurantHours(
                id: UUID(), restaurantId: restaurantId, dayOfWeek: day,
                openingTime: opening, closingTime: closing, isClosed: isClosed
            )
        }
    }

    private func singleDay(
        _ dayOfWeek: Int, _ opening: String, _ closing: String
    ) -> [RestaurantHours] {
        [RestaurantHours(
            id: UUID(), restaurantId: restaurantId, dayOfWeek: dayOfWeek,
            openingTime: opening, closingTime: closing, isClosed: false
        )]
    }

    // MARK: - The past-midnight window, 18:00–02:00

    func test_pastMidnightWindow_isOpenAt2300() {
        let schedule = hours("18:00:00", "02:00:00")
        XCTAssertTrue(schedule.isOpen(at: dushanbeDate(day: 18, hour: 23)))
    }

    func test_pastMidnightWindow_isOpenAt0130() {
        let schedule = hours("18:00:00", "02:00:00")
        XCTAssertTrue(schedule.isOpen(at: dushanbeDate(day: 18, hour: 1, minute: 30)))
    }

    func test_pastMidnightWindow_isClosedAt1500() {
        let schedule = hours("18:00:00", "02:00:00")
        XCTAssertFalse(schedule.isOpen(at: dushanbeDate(day: 18, hour: 15)))
    }

    func test_pastMidnightWindow_closesExactlyAtClosingTime() {
        let schedule = hours("18:00:00", "02:00:00")
        XCTAssertTrue(schedule.isOpen(at: dushanbeDate(day: 18, hour: 1, minute: 59)))
        XCTAssertFalse(schedule.isOpen(at: dushanbeDate(day: 18, hour: 2)))
    }

    /// The small hours belong to the *previous* day's row. With only Friday scheduled,
    /// Saturday 01:30 is open (Friday's window still running) but Saturday 23:00 is not.
    func test_pastMidnightWindow_attributedToThePreviousDayRow() {
        let fridayOnly = singleDay(5, "18:00:00", "02:00:00") // 5 = Friday

        XCTAssertTrue(fridayOnly.isOpen(at: dushanbeDate(day: 18, hour: 23)),
                      "Friday 23:00 is inside Friday's window")
        XCTAssertTrue(fridayOnly.isOpen(at: dushanbeDate(day: 19, hour: 1, minute: 30)),
                      "Saturday 01:30 is Friday's window spilling over")
        XCTAssertFalse(fridayOnly.isOpen(at: dushanbeDate(day: 19, hour: 23)),
                       "Saturday has no row of its own")
        XCTAssertFalse(fridayOnly.isOpen(at: dushanbeDate(day: 18, hour: 15)),
                       "Friday 15:00 is before opening")
    }

    // MARK: - Ordinary windows still behave

    func test_sameDayWindow() {
        let schedule = hours("09:00:00", "22:00:00")
        XCTAssertFalse(schedule.isOpen(at: dushanbeDate(day: 18, hour: 8, minute: 59)))
        XCTAssertTrue(schedule.isOpen(at: dushanbeDate(day: 18, hour: 9)))
        XCTAssertTrue(schedule.isOpen(at: dushanbeDate(day: 18, hour: 21, minute: 59)))
        XCTAssertFalse(schedule.isOpen(at: dushanbeDate(day: 18, hour: 22)))
        XCTAssertFalse(schedule.isOpen(at: dushanbeDate(day: 18, hour: 1)))
    }

    func test_closedDayIsClosedEvenInsideTheWindow() {
        let schedule = hours("18:00:00", "02:00:00", isClosed: true)
        XCTAssertFalse(schedule.isOpen(at: dushanbeDate(day: 18, hour: 23)))
        XCTAssertFalse(schedule.isOpen(at: dushanbeDate(day: 18, hour: 1)))
    }

    /// No rows means "always open" — the same policy the server applies.
    func test_emptyScheduleIsAlwaysOpen() {
        XCTAssertTrue([RestaurantHours]().isOpen(at: dushanbeDate(day: 18, hour: 4)))
    }

    func test_timeZoneIsDushanbeNotTheDeviceLocale() {
        let schedule = hours("09:00:00", "17:00:00")
        // 2026-09-18 05:00 UTC is 10:00 in Dushanbe (UTC+5): open, despite being before
        // 09:00 in UTC. A device set to another zone must not change the answer.
        let utcMorning = Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC")!,
            year: 2026, month: 9, day: 18, hour: 5
        ))!
        XCTAssertTrue(schedule.isOpen(at: utcMorning))
    }

    // MARK: - Next opening

    func test_nextOpeningBeforeTheWindowOpensToday() {
        let schedule = hours("18:00:00", "02:00:00")
        XCTAssertEqual(schedule.nextOpening(at: dushanbeDate(day: 18, hour: 15)), "18:00")
    }

    func test_nextOpeningIsNilWithoutASchedule() {
        XCTAssertNil([RestaurantHours]().nextOpening(at: dushanbeDate(day: 18, hour: 15)))
    }

    func test_nextOpeningSkipsClosedDays() {
        // Only Monday (1) is open; asked on Friday evening, after Friday's (absent) window.
        let mondayOnly = singleDay(1, "10:00:00", "20:00:00")
        XCTAssertEqual(mondayOnly.nextOpening(at: dushanbeDate(day: 18, hour: 23)), "10:00")
    }
}
