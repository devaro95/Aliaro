import Foundation
import SwiftData

/// A shared event on the family calendar (birthday, vacation,
/// plans...) with a start and an end date/time — it can last a few
/// hours or several days.
@Model
final class FamilyEvent {
    var id: UUID
    var title: String
    var note: String?
    var startDate: Date
    var endDate: Date
    var emoji: String
    var createdAt: Date
    /// Who created the event (reference to `FamilyMember`, not a
    /// SwiftData relationship). `createdByName` is copied so it stays
    /// readable even if that person leaves the group.
    var createdByID: UUID?
    var createdByName: String?
    /// Who the event is for: the whole family (`forEveryone`) or just
    /// `memberIDs` (reference `FamilyMember`, not a SwiftData relationship).
    var forEveryone: Bool = true
    var memberIDs: [UUID] = []
    /// All-day event (birthday, holiday…): no time shown. Stored as
    /// `startDate` = start of the first day, `endDate` = 23:59:59 of the
    /// last day (local time), so every existing day-range check still works.
    var isAllDay: Bool = false
    /// Repeats every `repeatInterval` × `repeatUnit` (0 = doesn't repeat).
    /// The stored dates are the first occurrence; the rest are computed.
    var repeatInterval: Int = 0
    /// Raw value of `FamilyEventRepeatUnit` ("day", "week", "month", "year").
    var repeatUnit: String = FamilyEventRepeatUnit.week.rawValue
    /// Tag color ("RRGGBB" from `ALIItemColors`); nil = default accent.
    var color: String?
    /// Last day a repeating event happens (nil = forever).
    var repeatUntil: Date?
    /// Occurrences deleted on their own ("yyyy-MM-dd", local day of their start).
    var excludedDates: [String] = []

    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        startDate: Date,
        endDate: Date,
        emoji: String = ALIIcon.party,
        createdAt: Date = .now,
        createdByID: UUID? = nil,
        createdByName: String? = nil,
        forEveryone: Bool = true,
        memberIDs: [UUID] = [],
        isAllDay: Bool = false,
        repeatInterval: Int = 0,
        repeatUnit: String = FamilyEventRepeatUnit.week.rawValue,
        color: String? = nil,
        repeatUntil: Date? = nil,
        excludedDates: [String] = []
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.startDate = startDate
        self.endDate = endDate
        self.emoji = emoji
        self.createdAt = createdAt
        self.createdByID = createdByID
        self.createdByName = createdByName
        self.forEveryone = forEveryone
        self.memberIDs = memberIDs
        self.isAllDay = isAllDay
        self.repeatInterval = repeatInterval
        self.repeatUnit = repeatUnit
        self.color = color
        self.repeatUntil = repeatUntil
        self.excludedDates = excludedDates
    }

    /// "Everyone" or the names of the people the event is for.
    func attendeesLabel(members: [FamilyMember]) -> String {
        if forEveryone { return String(localized: "Everyone") }
        let names = members.filter { memberIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? String(localized: "Everyone") : names.joined(separator: ", ")
    }

    // MARK: - Repetition

    var isRepeating: Bool { repeatInterval > 0 }

    var repeatUnitValue: FamilyEventRepeatUnit { FamilyEventRepeatUnit(rawValue: repeatUnit) ?? .week }

    /// "Every 2 weeks", "Every day"… or nil if it doesn't repeat.
    var repeatLabel: String? {
        guard isRepeating else { return nil }
        return repeatUnitValue.everyLabel(repeatInterval)
    }

    /// Start of the k-th occurrence (k = 0 is the stored one).
    private func occurrenceStart(_ k: Int) -> Date? {
        guard k > 0 else { return startDate }
        return Calendar.current.date(byAdding: repeatUnitValue.component, value: k * repeatInterval, to: startDate)
    }

    /// How long each repetition lasts: from the start time to the end time
    /// of that same day (the whole day for all-day events). Repetitions
    /// never span several days, so they don't paint long bands.
    private var occurrenceDuration: TimeInterval {
        let calendar = Calendar.current
        if isAllDay { return 86_399 }
        let endTime = calendar.dateComponents([.hour, .minute, .second], from: endDate)
        let sameDayEnd = calendar.date(bySettingHour: endTime.hour ?? 0, minute: endTime.minute ?? 0, second: endTime.second ?? 0, of: startDate) ?? endDate
        let duration = sameDayEnd.timeIntervalSince(startDate)
        return duration > 0 ? duration : 3600
    }

    /// "yyyy-MM-dd" (local) — key used in `excludedDates`.
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// (start, end) of every occurrence overlapping `interval` (the event
    /// itself if it doesn't repeat), skipping deleted ones and stopping at
    /// `repeatUntil`.
    func occurrences(in interval: DateInterval) -> [(start: Date, end: Date)] {
        guard isRepeating else {
            return startDate < interval.end && endDate >= interval.start ? [(startDate, endDate)] : []
        }
        let calendar = Calendar.current
        let unit = repeatUnitValue
        let duration = occurrenceDuration
        let lastDay = repeatUntil.map { calendar.startOfDay(for: $0) }
        let excluded = Set(excludedDates)
        // Jump close to the interval (one step back is enough: a repetition lasts at most a day).
        var k = 0
        if interval.start > startDate, let elapsed = calendar.dateComponents([unit.component], from: startDate, to: interval.start).value(for: unit.component) {
            k = max(0, elapsed / repeatInterval - 1)
        }
        var result: [(start: Date, end: Date)] = []
        var guardCount = 0
        while guardCount < 1000, let start = occurrenceStart(k), start < interval.end {
            if let lastDay, calendar.startOfDay(for: start) > lastDay { break }
            let end = start.addingTimeInterval(duration)
            if end >= interval.start && !excluded.contains(Self.dayKey(start)) { result.append((start, end)) }
            k += 1
            guardCount += 1
        }
        return result
    }

    /// First occurrence that hasn't ended yet at `date`.
    func nextOccurrence(from date: Date = .now) -> (start: Date, end: Date)? {
        guard isRepeating else { return endDate >= date ? (startDate, endDate) : nil }
        let steps = Double(excludedDates.count + 2)
        let window = DateInterval(start: date, duration: repeatUnitValue.approxSeconds * Double(repeatInterval) * steps + 2 * 86_400)
        return occurrences(in: window).first { $0.end >= date }
    }

    /// Display copy of this event moved to one occurrence (same id, not
    /// inserted in any context). Taps must resolve back to the real event.
    func occurrenceCopy(start: Date, end: Date) -> FamilyEvent {
        guard isRepeating else { return self }
        return FamilyEvent(
            id: id, title: title, note: note, startDate: start, endDate: end, emoji: emoji,
            createdAt: createdAt, createdByID: createdByID, createdByName: createdByName,
            forEveryone: forEveryone, memberIDs: memberIDs, isAllDay: isAllDay,
            repeatInterval: repeatInterval, repeatUnit: repeatUnit, color: color,
            repeatUntil: repeatUntil, excludedDates: excludedDates
        )
    }
}

enum FamilyEventRepeatUnit: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    var approxSeconds: Double {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 28 * 86_400
        case .year: 365 * 86_400
        }
    }

    /// Plural label for the picker ("days", "weeks"…).
    var pickerLabel: String {
        switch self {
        case .day: String(localized: "days")
        case .week: String(localized: "weeks")
        case .month: String(localized: "months")
        case .year: String(localized: "years")
        }
    }

    func everyLabel(_ n: Int) -> String {
        switch self {
        case .day: n == 1 ? String(localized: "Every day") : String(localized: "Every \(n) days")
        case .week: n == 1 ? String(localized: "Every week") : String(localized: "Every \(n) weeks")
        case .month: n == 1 ? String(localized: "Every month") : String(localized: "Every \(n) months")
        case .year: n == 1 ? String(localized: "Every year") : String(localized: "Every \(n) years")
        }
    }
}

extension Array where Element == FamilyEvent {
    /// Every occurrence overlapping `interval`, as display copies
    /// (see `FamilyEvent.occurrenceCopy`).
    func expanded(in interval: DateInterval) -> [FamilyEvent] {
        flatMap { event in event.occurrences(in: interval).map { event.occurrenceCopy(start: $0.start, end: $0.end) } }
            .sorted { $0.startDate < $1.startDate }
    }
}
