import Foundation

public struct BudgetTransaction {
    public var amount: Decimal      // в валюте операции, расход отрицательный
    public var date: Date
    public var categoryID: UUID?
    public var tagIDs: Set<UUID>
    public var pending: Bool
    public var rate: Decimal        // курс в валюту бюджета
    public init(amount: Decimal, date: Date, categoryID: UUID? = nil, tagIDs: Set<UUID> = [], pending: Bool = false, rate: Decimal = 1) {
        self.amount = amount; self.date = date; self.categoryID = categoryID
        self.tagIDs = tagIDs; self.pending = pending; self.rate = rate
    }
}

public struct BudgetRules {
    public var monitoredCategories: Set<UUID>?   // nil = все категории
    public var filteredTags: Set<UUID> = []
    public var excludedTags: Set<UUID> = []
    public var includePending = false
    public init(monitoredCategories: Set<UUID>? = nil, filteredTags: Set<UUID> = [], excludedTags: Set<UUID> = [], includePending: Bool = false) {
        self.monitoredCategories = monitoredCategories; self.filteredTags = filteredTags
        self.excludedTags = excludedTags; self.includePending = includePending
    }
}

public struct BudgetResult: Equatable {
    public var spent: Decimal          // расходы минус возвраты, положительное число
    public var unusedRefunds: Decimal  // возвраты сверх расходов
    public var remaining: Decimal
}

public enum Budgets {
    /// Период бюджета, в который попадает `today`: шагаем от начала на `duration` единиц (1 день, 2 неделя, 3 месяц, 4 год).
    public static func period(start: Date, type: Int, duration: Int, containing today: Date, calendar: Calendar = .current) -> DateInterval? {
        guard (1...4).contains(type), duration >= 1, today >= start else { return nil }
        let unit: Calendar.Component = [.day, .weekOfYear, .month, .year][type - 1]
        var i = 0
        while let s = calendar.date(byAdding: unit, value: i * duration, to: start),
              let e = calendar.date(byAdding: unit, value: (i + 1) * duration, to: start) {
            if today < e { return DateInterval(start: s, end: e) }
            i += 1
        }
        return nil
    }

    public static func evaluate(
        limit: Decimal,
        carryOver: Decimal = 0,
        period: DateInterval,
        transactions: [BudgetTransaction],
        rules: BudgetRules
    ) -> BudgetResult {
        var expenses = Decimal(0), refunds = Decimal(0)
        for t in transactions {
            guard t.date >= period.start, t.date < period.end else { continue }
            if t.pending && !rules.includePending { continue }
            if let cats = rules.monitoredCategories, !(t.categoryID.map(cats.contains) ?? false) { continue }
            if !rules.filteredTags.isEmpty, t.tagIDs.isDisjoint(with: rules.filteredTags) { continue }
            if !t.tagIDs.isDisjoint(with: rules.excludedTags) { continue }
            let value = Money.convert(t.amount, rate: t.rate)
            if value < 0 { expenses += -value } else { refunds += value }
        }
        let net = expenses - refunds
        return BudgetResult(spent: max(net, 0), unusedRefunds: max(-net, 0), remaining: limit + carryOver - max(net, 0))
    }

    /// Сколько переносится в следующий период. Минус переносится только если разрешено.
    public static func carryOverAmount(remaining: Decimal, carryNegative: Bool) -> Decimal {
        remaining >= 0 || carryNegative ? remaining : 0
    }

    /// Лимит на период: последняя запись истории, начавшаяся не позже начала периода, иначе базовая сумма.
    public static func limit(base: Decimal, history: [(date: Date, limit: Decimal)], for period: DateInterval) -> Decimal {
        history.filter { $0.date <= period.start }.max { $0.date < $1.date }?.limit ?? base
    }
}
