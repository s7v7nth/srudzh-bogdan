import Foundation

/// Три корзины, на которые шаблон делит доход.
public enum BudgetGroup: String, CaseIterable, Sendable {
    case needs, wants, savings
}

/// Шаблон «обязательное / желания / накопления» в процентах от дохода (сумма 100).
public struct BudgetTemplate: Identifiable, Equatable, Sendable {
    public let needs: Int, wants: Int, savings: Int
    public var id: String { "\(needs)/\(wants)/\(savings)" }
    public init(_ needs: Int, _ wants: Int, _ savings: Int) { self.needs = needs; self.wants = wants; self.savings = savings }

    public func percent(_ group: BudgetGroup) -> Int {
        switch group { case .needs: needs; case .wants: wants; case .savings: savings }
    }
}

public struct BudgetGroupTotals: Equatable, Sendable {
    /// Доход, округлённый вниз до шага: именно его делим.
    public var base: Decimal
    public var needs: Decimal
    public var wants: Decimal
    public var savings: Decimal
}

/// Раскладка дохода по шаблону и «красивое» округление сумм.
public enum BudgetSplit {
    public static let templates: [BudgetTemplate] = [
        BudgetTemplate(50, 30, 20), BudgetTemplate(50, 45, 5), BudgetTemplate(60, 30, 10),
        BudgetTemplate(70, 20, 10), BudgetTemplate(80, 10, 10),
    ]

    /// Шаг округления зависит от размера дохода: чем больше доход, тем крупнее шаг.
    public static func step(for income: Decimal) -> Decimal {
        if income < 1_000 { return 5 }
        if income < 5_000 { return 10 }
        if income < 20_000 { return 50 }
        if income < 100_000 { return 100 }
        if income < 1_000_000 { return 1_000 }
        return 10_000
    }

    public static func floorToStep(_ v: Decimal, step: Decimal) -> Decimal { round(v, step: step, mode: .down) }
    public static func ceilToStep(_ v: Decimal, step: Decimal) -> Decimal { round(v, step: step, mode: .up) }
    public static func nearestToStep(_ v: Decimal, step: Decimal) -> Decimal { round(v, step: step, mode: .plain) }

    private static func round(_ v: Decimal, step: Decimal, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        guard step > 0 else { return v }
        var q = v / step, r = Decimal()
        NSDecimalRound(&r, &q, 0, mode)
        return r * step
    }

    /// Делит доход по шаблону. Накопления берут остаток, поэтому три части всегда дают ровно `base`.
    public static func groupTotals(income: Decimal, template: BudgetTemplate) -> BudgetGroupTotals {
        let step = step(for: income)
        let base = max(floorToStep(income, step: step), 0)
        let needs = min(nearestToStep(base * Decimal(template.needs) / 100, step: step), base)
        let wants = min(nearestToStep(base * Decimal(template.wants) / 100, step: step), base - needs)
        return BudgetGroupTotals(base: base, needs: needs, wants: wants, savings: base - needs - wants)
    }

    /// Раскладывает `total` по категориям. Сначала каждая получает свой минимум (`floors`, например аренда),
    /// остаток делится по весам кратно шагу. Если минимумов больше, чем `total`, каждая получает свой минимум.
    /// Сумма результата равна `total`, когда минимумы помещаются и есть хоть один положительный вес.
    public static func distribute(total: Decimal, floors: [Decimal], weights: [Decimal], step: Decimal) -> [Decimal] {
        precondition(floors.count == weights.count)
        var result = floors.map { ceilToStep($0, step: step) }
        let remaining = total - result.reduce(0, +)
        let weightSum = weights.reduce(0, +)
        guard remaining >= step, weightSum > 0, step > 0 else { return result }

        let units = NSDecimalNumber(decimal: floorToStep(remaining, step: step) / step).intValue
        var shares = weights.map { Decimal(units) * $0 / weightSum }
        var whole = shares.map { w -> Int in
            var s = w, r = Decimal()
            NSDecimalRound(&r, &s, 0, .down)
            return NSDecimalNumber(decimal: r).intValue
        }
        shares = zip(shares, whole).map { $0 - Decimal($1) }
        var left = units - whole.reduce(0, +)
        // Недостающие шаги отдаём тем, у кого дробная часть больше (при равенстве — первым по списку).
        let order = shares.indices.filter { weights[$0] > 0 }.sorted { shares[$0] != shares[$1] ? shares[$0] > shares[$1] : $0 < $1 }
        for i in order where left > 0 { whole[i] += 1; left -= 1 }
        for i in result.indices { result[i] += Decimal(whole[i]) * step }
        return result
    }
}
