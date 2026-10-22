import Foundation

public struct LedgerEntry: Equatable {
    public var amount: Decimal
    public var date: Date
    public var pending: Bool
    public init(amount: Decimal, date: Date, pending: Bool = false) {
        self.amount = amount; self.date = date; self.pending = pending
    }
}

public enum Balances {
    /// Баланс счёта = сумма операций со знаком. `asOf` отсекает будущие операции.
    public static func balance(_ entries: [LedgerEntry], includePending: Bool = true, asOf: Date? = nil) -> Decimal {
        entries
            .filter { includePending || !$0.pending }
            .filter { asOf == nil || $0.date <= asOf! }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Доступный кредит = лимит + баланс (баланс отрицательный, когда должен).
    public static func availableCredit(limit: Decimal, balance: Decimal) -> Decimal { limit + balance }

    /// Итог по папке или чистый капитал: каждый счёт переводится по своему курсу.
    public static func total(_ accounts: [(balance: Decimal, rate: Decimal, excluded: Bool)], scale: Int = 2) -> Decimal {
        accounts.filter { !$0.excluded }
            .reduce(Decimal(0)) { $0 + Money.convert($1.balance, rate: $1.rate, scale: scale) }
    }
}
