import Foundation
import RavonCore

/// "Is the restaurant open right now?", computed from the stored weekly schedule.
///
/// TODO: delete this file in favour of `[RestaurantHours].isOpen(at:)` once RavonCore
/// ships it. Core owns hours and already has `nextOpenAt(from:lookaheadDays:)`, but it
/// exposes no boolean: `nextOpenAt` signals "open right now" by returning the *reference
/// date itself*, and comparing a returned `Date` to `now` for equality is not an obvious
/// calling convention — which is how the app came to roll its own in the first place.
/// Requested as `isOpen(at:) -> Bool` in `.context/STATE-REPORT.md` §5a.
///
/// The local copy this replaces compared `openingTime <= now < closingTime` as strings.
/// For a restaurant open 18:00–02:00 the closing string `"02:00:00"` sorts *below* the
/// opening string `"18:00:00"`, so the comparison was false at every instant of every day
/// and the dashboard told a busy late-night kitchen "Сейчас закрыто по расписанию" around
/// the clock. Late hours are normal in Dushanbe, so this was not an edge case.
///
/// Hours are "HH:mm:ss" strings interpreted in Asia/Dushanbe (per `RestaurantHours`), and
/// `dayOfWeek` is 0=Sunday…6=Saturday to match the database.
extension Array where Element == RestaurantHours {

    /// Weekday (0=Sun…6=Sat) and "HH:mm:ss", both in Asia/Dushanbe.
    nonisolated static func dushanbeComponents(of reference: Date) -> (weekday: Int, hms: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Dushanbe") ?? .current
        let parts = calendar.dateComponents([.weekday, .hour, .minute, .second], from: reference)
        // Swift weekday is 1=Sun…7=Sat; the database column is 0=Sun…6=Sat.
        let weekday = ((parts.weekday ?? 1) - 1) % 7
        let hms = String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        return (weekday, hms)
    }

    /// True when `reference` falls inside the schedule. An empty schedule means "always
    /// open", matching the server's `restaurant_within_hours()` policy for a restaurant
    /// with no rows.
    nonisolated func isOpen(at reference: Date = Date()) -> Bool {
        guard !isEmpty else { return true }
        let now = Self.dushanbeComponents(of: reference)

        // Today's window. If it wraps past midnight, only its evening half lands today.
        if let today = row(for: now.weekday), !today.isClosed {
            if today.wrapsPastMidnight {
                if now.hms >= today.openingTime { return true }
            } else if now.hms >= today.openingTime && now.hms < today.closingTime {
                return true
            }
        }

        // Yesterday's window, if it wrapped past midnight and is still running. This is
        // the half the old string comparison could never see.
        let yesterday = (now.weekday + 6) % 7
        if let row = row(for: yesterday), !row.isClosed, row.wrapsPastMidnight,
           now.hms < row.closingTime {
            return true
        }

        return false
    }

    /// The next opening time as "HH:mm" in Dushanbe within the next `lookaheadDays`, or nil
    /// if the schedule is blank or never opens again in the window. Only meaningful when
    /// `isOpen(at:)` is false.
    nonisolated func nextOpening(at reference: Date = Date(), lookaheadDays: Int = 7) -> String? {
        guard !isEmpty else { return nil }
        let now = Self.dushanbeComponents(of: reference)

        if let today = row(for: now.weekday), !today.isClosed, now.hms < today.openingTime {
            return String(today.openingTime.prefix(5))
        }
        for offset in 1...lookaheadDays {
            let weekday = (now.weekday + offset) % 7
            if let row = row(for: weekday), !row.isClosed {
                return String(row.openingTime.prefix(5))
            }
        }
        return nil
    }

    nonisolated private func row(for weekday: Int) -> RestaurantHours? {
        first { $0.dayOfWeek == weekday }
    }
}

extension RestaurantHours {
    /// A window whose closing time is not after its opening time runs into the next day.
    /// `closing == opening` is read as open around the clock rather than as a zero-length
    /// window — a merchant who wants a day off sets `isClosed`.
    nonisolated var wrapsPastMidnight: Bool {
        closingTime <= openingTime
    }
}
