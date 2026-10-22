import XCTest
@testable import LedgerCore

final class ReportsTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: 12))! }
    let food = UUID(), fun = UUID()

    func testMonthlyTotalsFillsEmptyMonths() {
        let txs = [ReportTx(amount: 1000, date: d(2026, 1, 5)), ReportTx(amount: -300, date: d(2026, 1, 9)),
                   ReportTx(amount: -50, date: d(2026, 3, 2))]
        let r = DateInterval(start: d(2026, 1, 1), end: d(2026, 3, 31))
        let m = Reports.monthlyTotals(txs, range: r, calendar: cal)
        XCTAssertEqual(m.count, 3)
        XCTAssertEqual(m[0].income, 1000); XCTAssertEqual(m[0].expense, 300); XCTAssertEqual(m[0].net, 700)
        XCTAssertEqual(m[1].income, 0); XCTAssertEqual(m[1].expense, 0)
        XCTAssertEqual(m[2].expense, 50)
    }

    func testRangeIsHalfOpen() {
        let r = DateInterval(start: d(2026, 1, 1), end: d(2026, 2, 1))
        let txs = [ReportTx(amount: -1, date: d(2026, 1, 1)), ReportTx(amount: -2, date: d(2026, 2, 1))]
        XCTAssertEqual(Reports.filter(txs, in: r).count, 1)
    }

    func testSavingsRate() {
        XCTAssertEqual(Reports.savingsRate(income: 1000, expense: 750), 0.25)
        XCTAssertEqual(Reports.savingsRate(income: 1000, expense: 1200), -0.2)
        XCTAssertNil(Reports.savingsRate(income: 0, expense: 10))
    }

    func testBreakdownSortsAndShares() {
        let txs = [ReportTx(amount: -300, date: d(2026, 1, 1), categoryID: food),
                   ReportTx(amount: -100, date: d(2026, 1, 2), categoryID: fun),
                   ReportTx(amount: -100, date: d(2026, 1, 3), categoryID: food),
                   ReportTx(amount: 999, date: d(2026, 1, 4), categoryID: food)]
        let s = Reports.breakdown(txs, sign: -1) { $0.categoryID?.uuidString ?? "-" }
        XCTAssertEqual(s.map(\.amount), [400, 100])
        XCTAssertEqual(s[0].share, 0.8, accuracy: 0.0001)
        XCTAssertTrue(Reports.breakdown([], sign: -1) { _ in "" }.isEmpty)
    }

    func testCompareHandlesNewAndGoneAndZeroBase() {
        let cur = [Slice(key: "a", amount: 120, share: 0), Slice(key: "new", amount: 30, share: 0)]
        let prev = [Slice(key: "a", amount: 100, share: 0), Slice(key: "gone", amount: 40, share: 0)]
        let c = Reports.compare(current: cur, previous: prev)
        XCTAssertEqual(c.map(\.key), ["new", "a", "gone"])
        XCTAssertEqual(c[1].percent!, 0.2, accuracy: 0.0001)
        XCTAssertNil(c[0].percent)
        XCTAssertEqual(c[2].percent!, -1, accuracy: 0.0001)
    }

    func testPreviousRangeSameLength() {
        let r = DateInterval(start: d(2026, 2, 1), end: d(2026, 3, 1))
        let p = Reports.previous(of: r)
        XCTAssertEqual(p.end, r.start); XCTAssertEqual(p.duration, r.duration)
    }

    func testCumulativeAtPoints() {
        let e: [(date: Date, amount: Decimal)] = [(d(2026, 1, 10), 100), (d(2026, 2, 10), -30), (d(2026, 3, 10), 5)]
        let v = Reports.cumulative(e, at: [d(2026, 1, 31), d(2026, 2, 28), d(2026, 3, 31)])
        XCTAssertEqual(v, [100, 70, 75])
        XCTAssertEqual(Reports.cumulative(e, at: [d(2025, 12, 31)]), [0])
    }

    func testLargestAndWeekday() {
        let txs = [ReportTx(amount: -10, date: d(2026, 10, 19)), ReportTx(amount: -90, date: d(2026, 10, 20)),
                   ReportTx(amount: 500, date: d(2026, 10, 21))]
        XCTAssertEqual(Reports.largestExpenses(txs, limit: 1).first?.amount, -90)
        let w = Reports.expenseByWeekday(txs, calendar: cal)   // 19.10.2026 это понедельник (weekday 2)
        XCTAssertEqual(w[2], 10); XCTAssertEqual(w[3], 90); XCTAssertNil(w[4])
    }

    func testForecastScheduledAndHabit() {
        // Зарплата 1000 раз в месяц, аренда -400 раз в месяц. Привычный темп равен расписанию, значит «остальное» = 0.
        let today = d(2026, 1, 1)
        let sched = [ScheduledItem(amount: 1000, nextDate: d(2026, 1, 10), repeatType: 3),
                     ScheduledItem(amount: -400, nextDate: d(2026, 1, 20), repeatType: 3)]
        let p = Reports.forecast(startBalance: 100, today: today, weeks: 9, scheduled: sched, dailyNet: 20, calendar: cal)
        XCTAssertEqual(p.count, 10)
        XCTAssertEqual(p[0].scheduled, 100)
        // Через 3 недели (22 января) прошли оба платежа: 100 + 1000 - 400.
        XCTAssertEqual(p[3].scheduled, 700)
        // Через 9 недель (5 марта): ещё и февральские платежи, и мартовские не наступили (10 и 20 марта).
        XCTAssertEqual(p[9].scheduled, 100 + 2 * 600)
    }

    func testForecastEndDateStopsPayments() {
        let today = d(2026, 1, 1)
        let s = [ScheduledItem(amount: -100, nextDate: d(2026, 1, 5), repeatType: 3, endDate: d(2026, 2, 10))]
        let p = Reports.forecast(startBalance: 0, today: today, weeks: 12, scheduled: s, dailyNet: 0, calendar: cal)
        XCTAssertEqual(p.last?.scheduled, -200)   // январь и февраль, март уже после конца
    }

    func testHabitOnlyForecastIsLinear() {
        let p = Reports.forecast(startBalance: 100, today: d(2026, 1, 1), weeks: 2, scheduled: [], dailyNet: 10, calendar: cal)
        XCTAssertEqual(p.last?.habit, 240)
        XCTAssertEqual(p.last?.scheduled, 100)
    }

    func testHabitDoesNotDoubleCountScheduled() {
        // Платёж -300 раз в 30 дней уже входит в привычный темп -10 в день, значит «остальное» = 0.
        let s = [ScheduledItem(amount: -300, nextDate: d(2026, 1, 10), repeatType: 3)]
        let p = Reports.forecast(startBalance: 1000, today: d(2026, 1, 1), weeks: 4, scheduled: s, dailyNet: -10, calendar: cal)
        XCTAssertEqual(p.last?.habit, 700)
    }

    func testHabitualDailyNetUsesWindow() {
        let today = d(2026, 3, 31)
        let txs = [ReportTx(amount: 300, date: d(2026, 3, 20)), ReportTx(amount: -100, date: d(2026, 3, 25)),
                   ReportTx(amount: 9999, date: d(2025, 1, 1))]
        XCTAssertEqual(Reports.habitualDailyNet(txs, today: today, days: 20), 10)
        XCTAssertEqual(Reports.habitualDailyNet([], today: today, days: 20), 0)
    }

    func testLowPoint() {
        let pts = [ForecastPoint(date: d(2026, 1, 1), scheduled: 50, habit: 50),
                   ForecastPoint(date: d(2026, 1, 8), scheduled: -10, habit: 40),
                   ForecastPoint(date: d(2026, 1, 15), scheduled: 20, habit: -5)]
        XCTAssertEqual(Reports.lowPoint(pts, habit: false)?.firstNegative, d(2026, 1, 8))
        XCTAssertEqual(Reports.lowPoint(pts, habit: true)?.lowest.habit, -5)
        XCTAssertNil(Reports.lowPoint([], habit: true))
    }

    func testMonthlyCost() {
        XCTAssertEqual(Reports.monthlyCost(amount: -12, type: 3, duration: 1), 12)
        XCTAssertEqual(NSDecimalNumber(decimal: Reports.monthlyCost(amount: -120, type: 4, duration: 1)).doubleValue, 120.0 * 30 / 365, accuracy: 0.001)
        XCTAssertEqual(Reports.monthlyCost(amount: -7, type: 2, duration: 1), 30)
    }

    func testRecentPeriodsStopAtBudgetStart() {
        let p = Reports.recentPeriods(start: d(2026, 8, 1), type: 3, count: 6, today: d(2026, 10, 22), calendar: cal)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p.first?.start, d(2026, 8, 1)); XCTAssertEqual(p.last?.end, d(2026, 11, 1))
        XCTAssertEqual(Reports.recentPeriods(start: d(2025, 1, 1), type: 3, count: 4, today: d(2026, 10, 22), calendar: cal).count, 4)
        XCTAssertTrue(Reports.recentPeriods(start: d(2027, 1, 1), type: 3, count: 4, today: d(2026, 10, 22), calendar: cal).isEmpty)
    }

    func testBudgetScore() {
        func r(_ spent: Decimal, _ m: Int) -> BudgetPeriodResult {
            BudgetPeriodResult(period: DateInterval(start: d(2026, m, 1), end: d(2026, m + 1, 1)), limit: 100, spent: spent)
        }
        let s = Reports.budgetScore([r(80, 1), r(130, 2), r(150, 3), r(90, 4), r(100, 5)])
        XCTAssertEqual(s.kept, 3); XCTAssertEqual(s.total, 5)
        XCTAssertEqual(s.streak, 2)               // ровно в лимит считается «уложился»
        XCTAssertEqual(s.averageOverrun, 40)
        XCTAssertEqual(Reports.budgetScore([]).keptShare, 0)
    }
}
