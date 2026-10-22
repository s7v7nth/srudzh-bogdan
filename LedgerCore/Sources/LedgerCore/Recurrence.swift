import Foundation

/// Следующая дата для платежей по расписанию.
/// type: 1 день, 2 неделя, 3 месяц, 4 год, 5...11 «n-й день недели месяца»
/// (5 = воскресенье ... 11 = суббота; duration = порядковый номер, 2 = второй).
public enum Recurrence {
    public static func nextDate(
        type: Int,
        duration: Int,
        from: Date,
        after: Date? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        guard (1...11).contains(type), duration >= 1 else { return nil }

        if type >= 5 {
            guard let after, from <= after else { return from }
            return nthWeekday(weekday: type - 5 + 1, ordinal: duration, from: from, after: after, calendar: calendar)
        }

        let component: Calendar.Component = [.day, .weekOfYear, .month, .year][type - 1]
        guard let after, from <= after else {
            return calendar.date(byAdding: component, value: duration, to: from)
        }
        // Всегда отсчитываем от исходной даты, чтобы 31 января не съезжало на 28 число навсегда.
        var i = 1
        while let candidate = calendar.date(byAdding: component, value: i * duration, to: from) {
            if candidate > after { return candidate }
            i += 1
        }
        return nil
    }

    private static func nthWeekday(weekday: Int, ordinal: Int, from: Date, after: Date, calendar: Calendar) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second], from: from)
        var current = from
        let match = DateComponents(hour: time.hour, minute: time.minute, second: time.second,
                                   weekday: weekday, weekdayOrdinal: ordinal)
        for _ in 0..<2000 {
            guard let next = calendar.nextDate(after: current, matching: match, matchingPolicy: .nextTime) else { return nil }
            if next > after { return next }
            current = next
        }
        return nil
    }
}
