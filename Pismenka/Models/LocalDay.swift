//
//  LocalDay.swift
//  Pismenka
//
//  A calendar date in the user's *local* time, expressed as a (year, month,
//  day) triple. Designed as the single domain type for all day-level logic
//  in the app — streaks, focus practice days, and the "one new letter per
//  day" rule — replacing scattered uses of `Date` + `Calendar.isDate`.
//
//  Why a dedicated type instead of `Date` + `Calendar`:
//    * Day-level identity. Two `Date`s on the same calendar day compare
//      unequal; two `LocalDay`s on the same day are `==`. That removes a
//      whole class of "did I remember to call isDate(_:inSameDayAs:)?" bugs.
//    * Day arithmetic is a one-liner. `today.daysSince(last) == 1` is the
//      same predicate as the previous "yesterday" check, but it expresses
//      intent directly and handles backwards clock changes naturally
//      (negative deltas).
//    * Stable on-disk format. Encoded as the ISO-style string "yyyy-MM-dd",
//      identical to the legacy `Profile.localDayKey` string format. So
//      `Set<String>` collections that previously stored day keys can be
//      decoded as `Set<LocalDay>` with no payload migration.
//    * Trivially testable. Pure value semantics, no `Date` / `TimeZone`
//      surface area in callers.
//

import Foundation

struct LocalDay: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    // MARK: - Construction

    /// The local-calendar day that contains `date`.
    static func from(_ date: Date, calendar: Calendar = .current) -> LocalDay {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDay(year: c.year ?? 0, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Today, in the device's local calendar.
    static func today(calendar: Calendar = .current) -> LocalDay {
        from(Date(), calendar: calendar)
    }

    /// Parses an ISO-style "yyyy-MM-dd" string. Lenient about leading zeros
    /// but strict about the three-component shape so we don't silently
    /// accept arbitrary garbage from on-disk data.
    init?(iso8601: String) {
        let parts = iso8601.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    // MARK: - Conversion

    /// Canonical "yyyy-MM-dd" rendering. Used as the Codable representation
    /// and as a stable hash-friendly key in any UI that wants to dedupe by
    /// day.
    var iso8601: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Resolves to midnight at the start of this day in `calendar`. Useful
    /// when bridging to existing `Date`-based APIs (e.g. `firstSeenAt` /
    /// `lastTestedAt` on `LetterStat`) that genuinely care about a moment
    /// in time rather than a day.
    func startOfDay(in calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        return calendar.date(from: c) ?? Date()
    }

    // MARK: - Day arithmetic

    /// Signed number of calendar days between `other` and `self`
    /// (`self - other`). Returns 0 for the same day, +1 for the next day,
    /// -1 for the previous day, etc.
    ///
    /// Negative results signal a backward clock change (or restored backup
    /// from a past date) — callers should treat that as "weird state, reset
    /// streak" rather than "many days passed."
    func daysSince(_ other: LocalDay, calendar: Calendar = .current) -> Int {
        let lhs = startOfDay(in: calendar)
        let rhs = other.startOfDay(in: calendar)
        return calendar.dateComponents([.day], from: rhs, to: lhs).day ?? 0
    }

    /// `self` advanced by `days` days. Negative for backward.
    func adding(days: Int, calendar: Calendar = .current) -> LocalDay {
        let advanced = calendar.date(byAdding: .day, value: days, to: startOfDay(in: calendar)) ?? startOfDay(in: calendar)
        return LocalDay.from(advanced, calendar: calendar)
    }

    func isSunday(calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: startOfDay(in: calendar)) == 1
    }

    /// The next Sunday after this day. If `self` is Sunday, this returns the
    /// following Sunday so a new learning cycle never tests on its first day.
    func nextSunday(calendar: Calendar = .current) -> LocalDay {
        let weekday = calendar.component(.weekday, from: startOfDay(in: calendar))
        let daysUntilSunday = (8 - weekday) % 7
        return adding(days: daysUntilSunday == 0 ? 7 : daysUntilSunday, calendar: calendar)
    }

    // MARK: - Comparable

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    // MARK: - Codable (single-string representation)

    /// Encoded as a single ISO-style string. Picking this representation
    /// (instead of a 3-field object) means `Set<LocalDay>` serializes
    /// identically to the legacy `Set<String>` of "yyyy-MM-dd" keys, so
    /// existing on-disk profile payloads decode without a migration step.
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let parsed = LocalDay(iso8601: s) else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Invalid LocalDay string: \(s)"
            )
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso8601)
    }
}
