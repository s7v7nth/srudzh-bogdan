import Foundation

/// Операция для отчётов. Сумма уже переведена в основную валюту: расход отрицательный, доход положительный.
/// Переводы между счетами и начальные остатки в отчёты о доходах и расходах не передаются.
public struct ReportTx: Equatable {
    public var amount: Decimal
    public var date: Date
    public var categoryID: UUID?
    public var payee: String
    public var account: String
    public init(amount: Decimal, date: Date, categoryID: UUID? = nil, payee: String = "", account: String = "") {
        self.amount = amount; self.date = date; self.categoryID = categoryID; self.payee = payee; self.account = account
    }
}

/// Один месяц: сколько пришло и сколько ушло.
public struct MonthTotal: Equatable {
    public var month: Date
    public var income: Decimal
    public var expense: Decimal      // положительное число
    public var net: Decimal { income - expense }
}

/// Доля одной статьи (категории, получателя) в сумме.
public struct Slice: Equatable {
    public var key: String
    public var amount: Decimal       // положительное число
    public var share: Double         // 0...1
}

/// Изменение статьи между двумя периодами.
public struct Change: Equatable {
    public var key: String
    public var current: Decimal
    public var previous: Decimal
    public var delta: Decimal { current - previous }
    /// nil, если раньше было 0: процент от нуля ничего не значит.
    public var percent: Double? {
        previous == 0 ? nil : NSDecimalNumber(decimal: (current - previous) / previous).doubleValue
    }
}

/// Точка прогноза остатка.
public struct ForecastPoint: Equatable {
    public var date: Date
    /// Только платежи по расписанию.
    public var scheduled: Decimal
    /// Платежи по расписанию плюс привычный темп остальных трат и доходов.
    public var habit: Decimal
}

/// Платёж по расписанию для прогноза (сумма в основной валюте, со знаком).
public struct ScheduledItem: Equatable {
    public var amount: Decimal
    public var nextDate: Date
    public var repeatType: Int
    public var duration: Int
    public var endDate: Date?
    public init(amount: Decimal, nextDate: Date, repeatType: Int, duration: Int = 1, endDate: Date? = nil) {
        self.amount = amount; self.nextDate = nextDate; self.repeatType = repeatType
        self.duration = duration; self.endDate = endDate
    }
}

/// Итог бюджета за один период: лимит, потрачено.
public struct BudgetPeriodResult: Equatable {
    public var period: DateInterval
    public var limit: Decimal
    public var spent: Decimal
    public var over: Bool { spent > limit }
    public var ratio: Double { limit > 0 ? NSDecimalNumber(decimal: spent / limit).doubleValue : 0 }
    public init(period: DateInterval, limit: Decimal, spent: Decimal) { self.period = period; self.limit = limit; self.spent = spent }
}

/// Сводка «получается ли вести бюджет».
public struct BudgetScore: Equatable {
    public var kept: Int              // сколько периодов уложился
    public var total: Int
    public var streak: Int            // сколько последних периодов подряд уложился
    public var averageOverrun: Decimal   // средний перерасход по тем периодам, где вышел за лимит (0, если таких нет)
    public var keptShare: Double { total == 0 ? 0 : Double(kept) / Double(total) }
}

public enum Reports {

    // MARK: Периоды

    /// Начало месяца, в котором лежит дата.
    public static func monthStart(_ d: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: d)?.start ?? d
    }

    /// Список начал месяцев от `from` до `to` включительно.
    public static func months(from: Date, to: Date, calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        var cur = monthStart(from, calendar: calendar)
        let last = monthStart(to, calendar: calendar)
        while cur <= last, out.count < 600 {
            out.append(cur)
            guard let n = calendar.date(byAdding: .month, value: 1, to: cur) else { break }
            cur = n
        }
        return out
    }

    /// Предыдущий период той же длины, вплотную перед `range`.
    public static func previous(of range: DateInterval) -> DateInterval {
        DateInterval(start: range.start.addingTimeInterval(-range.duration), end: range.start)
    }

    public static func filter(_ txs: [ReportTx], in range: DateInterval) -> [ReportTx] {
        txs.filter { $0.date >= range.start && $0.date < range.end }
    }

    // MARK: Доходы и расходы

    /// Итоги по месяцам. Месяцы без операций тоже попадают в список (с нулями).
    public static func monthlyTotals(_ txs: [ReportTx], range: DateInterval, calendar: Calendar = .current) -> [MonthTotal] {
        let list = months(from: range.start, to: range.end.addingTimeInterval(-1), calendar: calendar)
        var map: [Date: (Decimal, Decimal)] = [:]
        for t in filter(txs, in: range) {
            let m = monthStart(t.date, calendar: calendar)
            var v = map[m] ?? (0, 0)
            if t.amount > 0 { v.0 += t.amount } else { v.1 += -t.amount }
            map[m] = v
        }
        return list.map { MonthTotal(month: $0, income: map[$0]?.0 ?? 0, expense: map[$0]?.1 ?? 0) }
    }

    /// Какую долю дохода удалось оставить. nil, если дохода не было.
    public static func savingsRate(income: Decimal, expense: Decimal) -> Double? {
        income <= 0 ? nil : NSDecimalNumber(decimal: (income - expense) / income).doubleValue
    }

    // MARK: Разрезы

    /// Суммы по ключу, от большей к меньшей. `sign` = -1 для расходов, 1 для доходов; операции другого знака не считаются.
    public static func breakdown(_ txs: [ReportTx], sign: Int, key: (ReportTx) -> String) -> [Slice] {
        var sums: [String: Decimal] = [:]
        for t in txs where (sign < 0 ? t.amount < 0 : t.amount > 0) { sums[key(t), default: 0] += abs(t.amount) }
        let total = sums.values.reduce(0, +)
        guard total > 0 else { return [] }
        return sums.map { Slice(key: $0.key, amount: $0.value, share: NSDecimalNumber(decimal: $0.value / total).doubleValue) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.key < $1.key }
    }

    /// Сравнение двух наборов сумм по ключам. Сортировка: самый большой рост сверху.
    public static func compare(current: [Slice], previous: [Slice]) -> [Change] {
        let cur = Dictionary(uniqueKeysWithValues: current.map { ($0.key, $0.amount) })
        let prev = Dictionary(uniqueKeysWithValues: previous.map { ($0.key, $0.amount) })
        return Set(cur.keys).union(prev.keys)
            .map { Change(key: $0, current: cur[$0] ?? 0, previous: prev[$0] ?? 0) }
            .sorted { $0.delta != $1.delta ? $0.delta > $1.delta : $0.key < $1.key }
    }

    /// Самые крупные траты (по модулю суммы).
    public static func largestExpenses(_ txs: [ReportTx], limit: Int) -> [ReportTx] {
        Array(txs.filter { $0.amount < 0 }.sorted { $0.amount != $1.amount ? $0.amount < $1.amount : $0.date < $1.date }.prefix(limit))
    }

    /// Траты по дням недели: ключ `Calendar.weekday` (1 = воскресенье).
    public static func expenseByWeekday(_ txs: [ReportTx], calendar: Calendar = .current) -> [Int: Decimal] {
        var out: [Int: Decimal] = [:]
        for t in txs where t.amount < 0 { out[calendar.component(.weekday, from: t.date), default: 0] += -t.amount }
        return out
    }

    // MARK: Капитал

    /// Значение накопленной суммы на конец каждой из дат `points`. Операции должны быть уже отфильтрованы по счетам.
    public static func cumulative(_ entries: [(date: Date, amount: Decimal)], at points: [Date]) -> [Decimal] {
        let sorted = entries.sorted { $0.date < $1.date }
        var i = 0, sum: Decimal = 0
        var out: [Decimal] = []
        for p in points.sorted() {
            while i < sorted.count, sorted[i].date <= p { sum += sorted[i].amount; i += 1 }
            out.append(sum)
        }
        return out
    }

    // MARK: Прогноз

    /// Средний чистый приток в день за последние `days` дней до `today` (доходы минус расходы). 0 при пустой истории.
    public static func habitualDailyNet(_ txs: [ReportTx], today: Date, days: Int) -> Decimal {
        guard days > 0, let from = Calendar.current.date(byAdding: .day, value: -days, to: today) else { return 0 }
        let sum = txs.filter { $0.date > from && $0.date <= today }.reduce(Decimal(0)) { $0 + $1.amount }
        return sum / Decimal(days)
    }

    /// Прогноз остатка по неделям на `weeks` недель вперёд.
    /// Две линии: только по расписанию и «по привычке» (расписание плюс средний дневной темп).
    /// Чтобы привычный темп не считал платежи по расписанию дважды, из него вычитается дневная стоимость расписания.
    public static func forecast(startBalance: Decimal, today: Date, weeks: Int, scheduled: [ScheduledItem],
                                dailyNet: Decimal, calendar: Calendar = .current) -> [ForecastPoint] {
        guard weeks > 0, let horizon = calendar.date(byAdding: .day, value: weeks * 7, to: today) else { return [] }
        var events: [(Date, Decimal)] = []
        var perDay: Decimal = 0
        for s in scheduled {
            var d = s.nextDate
            var n = 0
            while d <= horizon, n < 1000 {
                if let e = s.endDate, d > e { break }
                if d > today { events.append((d, s.amount)) }
                guard let nx = Recurrence.nextDate(type: s.repeatType, duration: s.duration, from: s.nextDate, after: d, calendar: calendar) else { break }
                d = nx; n += 1
            }
            perDay += s.amount * Decimal(1) / Decimal(max(1, approxDays(type: s.repeatType, duration: s.duration)))
        }
        let rest = dailyNet - perDay
        events.sort { $0.0 < $1.0 }
        var out: [ForecastPoint] = [ForecastPoint(date: today, scheduled: startBalance, habit: startBalance)]
        var sched = startBalance, habit = startBalance, idx = 0
        var prev = today
        for w in 1...weeks {
            guard let end = calendar.date(byAdding: .day, value: w * 7, to: today) else { break }
            while idx < events.count, events[idx].0 <= end { sched += events[idx].1; habit += events[idx].1; idx += 1 }
            habit += rest * Decimal(calendar.dateComponents([.day], from: prev, to: end).day ?? 7)
            out.append(ForecastPoint(date: end, scheduled: sched, habit: habit))
            prev = end
        }
        return out
    }

    /// Примерная длина периода повтора в днях (для пересчёта расписания в «в день»).
    public static func approxDays(type: Int, duration: Int) -> Int {
        let unit = [1, 7, 30, 365][max(0, min(3, (type <= 4 ? type : 3) - 1))]
        return unit * max(1, duration)
    }

    /// Во сколько обходится платёж в месяц и в год (сумма положительная).
    public static func monthlyCost(amount: Decimal, type: Int, duration: Int) -> Decimal {
        abs(amount) * Decimal(30) / Decimal(approxDays(type: type, duration: duration))
    }

    /// Первая точка, где остаток уходит ниже нуля, и самая низкая точка прогноза.
    public static func lowPoint(_ points: [ForecastPoint], habit: Bool) -> (lowest: ForecastPoint, firstNegative: Date?)? {
        let value: (ForecastPoint) -> Decimal = { habit ? $0.habit : $0.scheduled }
        guard let low = points.min(by: { value($0) < value($1) }) else { return nil }
        return (low, points.first { value($0) < 0 }?.date)
    }

    // MARK: Бюджеты

    /// Последние `count` периодов бюджета, заканчивая тем, что содержит `today` (от старых к новым).
    /// Периоды раньше `start` бюджета не берутся.
    public static func recentPeriods(start: Date, type: Int, count: Int, today: Date, calendar: Calendar = .current) -> [DateInterval] {
        guard count > 0, var cur = Budgets.period(start: start, type: type, duration: 1, containing: today, calendar: calendar) else { return [] }
        let unit: Calendar.Component = [.day, .weekOfYear, .month, .year][type - 1]
        var out = [cur]
        while out.count < count, let s = calendar.date(byAdding: unit, value: -1, to: cur.start), s >= start {
            cur = DateInterval(start: s, end: cur.start)
            out.insert(cur, at: 0)
        }
        return out
    }

    /// Оценка по списку периодов (от старых к новым). Текущий период, ещё не закончившийся, оценивается наравне с остальными.
    public static func budgetScore(_ results: [BudgetPeriodResult]) -> BudgetScore {
        let kept = results.filter { !$0.over }.count
        var streak = 0
        for r in results.reversed() { if r.over { break }; streak += 1 }
        let overs = results.filter(\.over)
        let avg = overs.isEmpty ? 0 : overs.reduce(Decimal(0)) { $0 + ($1.spent - $1.limit) } / Decimal(overs.count)
        return BudgetScore(kept: kept, total: results.count, streak: streak, averageOverrun: avg)
    }
}
