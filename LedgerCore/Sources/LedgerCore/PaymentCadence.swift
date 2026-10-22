import Foundation

/// Как часто повторяется платёж в настройке: перевод в параметры расписания (`Recurrence`) и пересчёт в «за месяц».
public enum PaymentCadence: String, CaseIterable, Sendable {
    case monthly, twiceMonthly, biweekly, weekly, yearly

    /// Тип повтора расписания: 2 неделя, 3 месяц, 4 год.
    public var repeatType: Int {
        switch self { case .monthly, .twiceMonthly: 3; case .biweekly, .weekly: 2; case .yearly: 4 }
    }
    public var duration: Int { self == .biweekly ? 2 : 1 }

    /// Сколько таких платежей приходится на средний месяц.
    public var perMonth: Decimal {
        switch self {
        case .monthly: 1
        case .twiceMonthly: 2
        case .biweekly: Decimal(26) / 12
        case .weekly: Decimal(52) / 12
        case .yearly: Decimal(1) / 12
        }
    }
}

/// Ближайшая дата первого платежа по выбранному дню.
public enum FirstPayment {
    private static func noon(_ date: Date, _ cal: Calendar) -> Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date }

    /// Ближайшее число месяца (1...28, дальше не предлагаем: в коротких месяцах платёж терялся бы), включая сегодня.
    public static func monthly(day: Int, from today: Date = .now, calendar cal: Calendar = .current) -> Date {
        let day = min(max(day, 1), 28)
        let start = cal.startOfDay(for: today)
        var c = cal.dateComponents([.year, .month], from: start)
        c.day = day; c.hour = 12
        let candidate = cal.date(from: c) ?? start
        return candidate < start ? (cal.date(byAdding: .month, value: 1, to: candidate) ?? candidate) : candidate
    }

    /// Ближайший день недели (1 воскресенье ... 7 суббота, как в `Calendar`), включая сегодня.
    public static func weekly(weekday: Int, from today: Date = .now, calendar cal: Calendar = .current) -> Date {
        let start = cal.startOfDay(for: today)
        for i in 0..<7 {
            if let d = cal.date(byAdding: .day, value: i, to: start), cal.component(.weekday, from: d) == weekday { return noon(d, cal) }
        }
        return noon(start, cal)
    }

    /// Если выбранная дата уже прошла, переносит её на тот же день следующего года.
    public static func yearly(date: Date, from today: Date = .now, calendar cal: Calendar = .current) -> Date {
        let start = cal.startOfDay(for: today)
        var d = noon(date, cal)
        var guardCount = 0
        while d < start, guardCount < 200, let next = cal.date(byAdding: .year, value: 1, to: d) { d = next; guardCount += 1 }
        return d
    }
}
