import Foundation

/// Вечерняя сводка за день: что показать в уведомлении. Тексты собирает приложение, здесь только числа и вариант.
public struct EveningDigest: Equatable {
    public enum Kind: Equatable {
        /// Есть траты из СМС без разбора: зовём разобрать.
        case review
        /// Траты были, всё разобрано: итоги дня.
        case summary
        /// За день ни одной траты: спрашиваем, не забыл ли записать.
        case empty
    }

    public struct Payment: Equatable {
        public var name: String
        public var amount: Decimal
        public init(name: String, amount: Decimal) { self.name = name; self.amount = amount }
    }

    /// Бюджет, который подходит к лимиту или уже превышен.
    public struct BudgetAlert: Equatable {
        public var name: String
        public var currency: String
        public var limit: Decimal
        public var spent: Decimal
        public init(name: String, currency: String, limit: Decimal, spent: Decimal) {
            self.name = name; self.currency = currency; self.limit = limit; self.spent = spent
        }
        public var left: Decimal { limit - spent }
        public var isOver: Bool { spent > limit }
        var ratio: Decimal { limit > 0 ? spent / limit : (spent > 0 ? 1 : 0) }
    }

    public var kind: Kind
    /// Потрачено за день, положительное число.
    public var spent: Decimal
    /// Операций из СМС, которые ждут разбора.
    public var pending: Int
    /// Остаток бюджета на месяц; nil, если месячного бюджета нет. Отрицательный при перерасходе.
    public var budgetLeft: Decimal?
    /// Сколько можно тратить в день до конца месяца, округлено вниз до целого; nil в последний день месяца и при перерасходе.
    public var perDay: Decimal?
    /// Платежи по расписанию на завтра.
    public var tomorrow: [Payment]
    /// Бюджеты на исходе, самые горящие первыми.
    public var budgets: [BudgetAlert] = []

    /// - Parameters:
    ///   - date: день сводки.
    ///   - budgetLeft: остаток месячного бюджета на вечер этого дня.
    public static func make(date: Date, spent: Decimal, pending: Int, budgetLeft: Decimal?,
                            tomorrow: [Payment], budgets: [BudgetAlert] = [], calendar: Calendar = .current) -> EveningDigest {
        let kind: Kind = pending > 0 ? .review : (spent > 0 ? .summary : .empty)
        var perDay: Decimal?
        if let left = budgetLeft, left > 0, let days = daysLeftInMonth(after: date, calendar: calendar), days > 0 {
            var raw = left / Decimal(days), rounded = Decimal()
            NSDecimalRound(&rounded, &raw, 0, .down)
            perDay = rounded
        }
        return EveningDigest(kind: kind, spent: spent, pending: pending, budgetLeft: budgetLeft, perDay: perDay,
                             tomorrow: tomorrow, budgets: alerts(budgets))
    }

    /// Бюджеты, потраченные на `threshold` и больше (по умолчанию 80%, как жёлтый цвет в приложении), от самых горящих.
    public static func alerts(_ items: [BudgetAlert], threshold: Decimal = 0.8) -> [BudgetAlert] {
        items.filter { $0.spent > 0 && $0.ratio >= threshold }.sorted { $0.ratio > $1.ratio }
    }

    /// Сколько дней осталось в месяце после `date` (завтра и дальше). В последний день месяца 0.
    public static func daysLeftInMonth(after date: Date, calendar: Calendar = .current) -> Int? {
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return nil }
        return range.count - calendar.component(.day, from: date)
    }
}
