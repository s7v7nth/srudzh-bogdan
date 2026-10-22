import Foundation

/// Условия возобновляемой кредитной линии. Банки считают по-разному, поэтому всё настраивается.
public struct CreditTerms: Equatable {
    public var limit: Decimal
    public var aprPercent: Decimal          // годовая ставка в процентах
    public var statementDay: Int            // день выписки 1...31 (в коротких месяцах берётся последний день)
    public var graceDays: Int               // беспроцентный срок в днях, 0 = льготы нет
    public var graceFromStatement: Bool     // true: срок идёт от даты выписки, false: от даты покупки
    public var minPercent: Decimal          // минимальный платёж: процент от долга
    public var minFloor: Decimal            // минимальный платёж: не меньше этой суммы
    public var dueDays: Int                 // сколько дней после выписки до обязательного платежа

    public init(limit: Decimal, aprPercent: Decimal = 0, statementDay: Int = 1, graceDays: Int = 0,
                graceFromStatement: Bool = true, minPercent: Decimal = 0, minFloor: Decimal = 0, dueDays: Int = 0) {
        self.limit = limit; self.aprPercent = aprPercent; self.statementDay = statementDay
        self.graceDays = graceDays; self.graceFromStatement = graceFromStatement
        self.minPercent = minPercent; self.minFloor = minFloor; self.dueDays = dueDays
    }
}

public struct GraceStatus: Equatable {
    /// Долг, на который уже начисляются проценты (беспроцентный срок вышел).
    public var interestBearing: Decimal
    /// Сколько нужно внести к ближайшему сроку, чтобы не платить проценты.
    public var amountDue: Decimal
    public var nextDeadline: Date?
}

public struct StatementSummary: Equatable {
    public var period: DateInterval
    public var purchases: Decimal   // положительное число
    public var payments: Decimal
    public var closingDebt: Decimal
}

public enum CreditLine {
    // MARK: Даты

    /// Дата выписки в указанном месяце, день ограничен длиной месяца.
    public static func statementDate(year: Int, month: Int, statementDay: Int, calendar: Calendar = .current) -> Date {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let days = calendar.range(of: .day, in: .month, for: first)!.count
        return calendar.date(from: DateComponents(year: year, month: month, day: min(max(statementDay, 1), days)))!
    }

    /// Расчётный период, в который попадает дата: от одной выписки (включительно) до следующей.
    public static func period(containing date: Date, statementDay: Int, calendar: Calendar = .current) -> DateInterval {
        let c = calendar.dateComponents([.year, .month], from: date)
        let thisStatement = statementDate(year: c.year!, month: c.month!, statementDay: statementDay, calendar: calendar)
        func shifted(_ delta: Int) -> Date {
            let m = calendar.date(byAdding: .month, value: delta, to: calendar.date(from: DateComponents(year: c.year!, month: c.month!, day: 1))!)!
            let mc = calendar.dateComponents([.year, .month], from: m)
            return statementDate(year: mc.year!, month: mc.month!, statementDay: statementDay, calendar: calendar)
        }
        let day = calendar.startOfDay(for: date)
        if day >= thisStatement { return DateInterval(start: thisStatement, end: shifted(1)) }
        return DateInterval(start: shifted(-1), end: thisStatement)
    }

    /// Дата обязательного платежа по выписке, закрытой в `statement`.
    public static func dueDate(statement: Date, dueDays: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: dueDays, to: statement)!
    }

    /// До какой даты покупка остаётся беспроцентной.
    public static func interestFreeDeadline(purchase: Date, terms: CreditTerms, calendar: Calendar = .current) -> Date {
        let base = terms.graceFromStatement
            ? period(containing: purchase, statementDay: terms.statementDay, calendar: calendar).end
            : calendar.startOfDay(for: purchase)
        return calendar.date(byAdding: .day, value: terms.graceDays, to: base)!
    }

    // MARK: Суммы

    /// Минимальный платёж: большее из «процент от долга» и «минимальная сумма», но не больше долга.
    public static func minimumPayment(debt: Decimal, percent: Decimal, floor: Decimal) -> Decimal {
        guard debt > 0 else { return 0 }
        return min(debt, max(Money.round(debt * percent / 100), floor))
    }

    public static func utilization(debt: Decimal, limit: Decimal) -> Decimal {
        limit > 0 ? max(debt, 0) / limit : 0
    }

    // MARK: Льготный период и проценты

    private struct Lot { var date: Date; var remaining: Decimal }

    /// Покупки «партиями»: погашения закрывают самые старые покупки первыми.
    private static func apply(_ e: LedgerEntry, to lots: inout [Lot]) {
        if e.amount < 0 {
            lots.append(Lot(date: e.date, remaining: -e.amount))
        } else {
            var left = e.amount
            for i in lots.indices where left > 0 && lots[i].remaining > 0 {
                let used = min(left, lots[i].remaining)
                lots[i].remaining -= used; left -= used
            }
        }
    }

    public static func graceStatus(entries: [LedgerEntry], today: Date, terms: CreditTerms, calendar: Calendar = .current) -> GraceStatus {
        let todayStart = calendar.startOfDay(for: today)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        var lots: [Lot] = []
        for e in entries.sorted(by: { $0.date < $1.date }) where e.date < dayEnd { apply(e, to: &lots) }
        lots.removeAll { $0.remaining <= 0 }

        var bearing: Decimal = 0
        var upcoming: [(Date, Decimal)] = []
        for lot in lots {
            let deadline = interestFreeDeadline(purchase: lot.date, terms: terms, calendar: calendar)
            if deadline < todayStart { bearing += lot.remaining } else { upcoming.append((deadline, lot.remaining)) }
        }
        let next = upcoming.map(\.0).min()
        let due = next.map { n in upcoming.filter { $0.0 <= n }.reduce(Decimal(0)) { $0 + $1.1 } } ?? 0
        return GraceStatus(interestBearing: bearing, amountDue: due, nextDeadline: next)
    }

    /// Оценка процентов за период [from, through] включительно: каждый день долг, срок которого вышел, умножается на ставку/365.
    public static func interestEstimate(entries: [LedgerEntry], from: Date, through: Date, terms: CreditTerms, calendar: Calendar = .current) -> Decimal {
        guard terms.aprPercent > 0 else { return 0 }
        let sorted = entries.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return 0 }
        var lots: [Lot] = []
        var idx = 0
        var day = calendar.startOfDay(for: first.date)
        let fromDay = calendar.startOfDay(for: from)
        let lastDay = calendar.startOfDay(for: through)
        var total: Decimal = 0
        var guardCount = 0
        while day <= lastDay, guardCount < 4000 {
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            while idx < sorted.count, sorted[idx].date < next { apply(sorted[idx], to: &lots); idx += 1 }
            if day >= fromDay {
                var bearing: Decimal = 0
                for lot in lots where lot.remaining > 0 {
                    if interestFreeDeadline(purchase: lot.date, terms: terms, calendar: calendar) < day { bearing += lot.remaining }
                }
                total += bearing * terms.aprPercent / 36500
            }
            day = next; guardCount += 1
        }
        return Money.round(total)
    }

    // MARK: Выписки

    /// Закрытые расчётные периоды, от самого свежего. Текущий (ещё открытый) не включается.
    public static func statements(entries: [LedgerEntry], terms: CreditTerms, count: Int, asOf: Date, calendar: Calendar = .current) -> [StatementSummary] {
        var result: [StatementSummary] = []
        var cursor = period(containing: asOf, statementDay: terms.statementDay, calendar: calendar)
        for _ in 0..<count {
            let prevDay = calendar.date(byAdding: .day, value: -1, to: cursor.start)!
            cursor = period(containing: prevDay, statementDay: terms.statementDay, calendar: calendar)
            let inPeriod = entries.filter { $0.date >= cursor.start && $0.date < cursor.end }
            let purchases = inPeriod.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 - $1.amount }
            let payments = inPeriod.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
            let closing = max(-entries.filter { $0.date < cursor.end }.reduce(Decimal(0)) { $0 + $1.amount }, 0)
            result.append(StatementSummary(period: cursor, purchases: purchases, payments: payments, closingDebt: closing))
        }
        return result
    }
}
