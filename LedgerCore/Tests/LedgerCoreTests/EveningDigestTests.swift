import XCTest
@testable import LedgerCore

final class EveningDigestTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: 21))! }

    func testPendingSMSWinsOverSummary() {
        let g = EveningDigest.make(date: d(2026, 10, 26), spent: 47, pending: 3, budgetLeft: 820, tomorrow: [], calendar: cal)
        XCTAssertEqual(g.kind, .review)
        XCTAssertEqual(g.pending, 3)
    }

    func testSummaryWhenEverythingSorted() {
        let g = EveningDigest.make(date: d(2026, 10, 26), spent: 47, pending: 0, budgetLeft: 820, tomorrow: [], calendar: cal)
        XCTAssertEqual(g.kind, .summary)
    }

    func testEmptyDay() {
        let g = EveningDigest.make(date: d(2026, 10, 26), spent: 0, pending: 0, budgetLeft: nil, tomorrow: [], calendar: cal)
        XCTAssertEqual(g.kind, .empty)
        XCTAssertNil(g.perDay)
    }

    func testPerDaySplitsLeftoverOverRemainingDaysRoundedDown() {
        // 26 октября: впереди 27–31, это 5 дней. 820 / 5 = 164.
        let g = EveningDigest.make(date: d(2026, 10, 26), spent: 10, pending: 0, budgetLeft: 820, tomorrow: [], calendar: cal)
        XCTAssertEqual(g.perDay, 164)
        // 823 / 5 = 164.6, вниз до 164.
        let h = EveningDigest.make(date: d(2026, 10, 26), spent: 10, pending: 0, budgetLeft: 823, tomorrow: [], calendar: cal)
        XCTAssertEqual(h.perDay, 164)
    }

    func testNoPerDayOnLastDayOrWhenOverspent() {
        XCTAssertNil(EveningDigest.make(date: d(2026, 10, 31), spent: 1, pending: 0, budgetLeft: 100, tomorrow: [], calendar: cal).perDay)
        let over = EveningDigest.make(date: d(2026, 10, 20), spent: 1, pending: 0, budgetLeft: -50, tomorrow: [], calendar: cal)
        XCTAssertNil(over.perDay)
        XCTAssertEqual(over.budgetLeft, -50)
    }

    func testDaysLeftInFebruary() {
        XCTAssertEqual(EveningDigest.daysLeftInMonth(after: d(2026, 2, 1), calendar: cal), 27)
        XCTAssertEqual(EveningDigest.daysLeftInMonth(after: d(2028, 2, 28), calendar: cal), 1)
    }

    // MARK: Бюджеты на исходе
    func testAlertsPickBudgetsFromEightyPercentHottestFirst() {
        let items = [
            EveningDigest.BudgetAlert(name: "Еда", currency: "BYN", limit: 500, spent: 400),     // 80%
            EveningDigest.BudgetAlert(name: "Кафе", currency: "BYN", limit: 100, spent: 115),    // перебор
            EveningDigest.BudgetAlert(name: "Такси", currency: "BYN", limit: 100, spent: 79),    // 79%, рано
            EveningDigest.BudgetAlert(name: "Пусто", currency: "BYN", limit: 0, spent: 0),
        ]
        let picked = EveningDigest.alerts(items)
        XCTAssertEqual(picked.map(\.name), ["Кафе", "Еда"])
        XCTAssertTrue(picked[0].isOver)
        XCTAssertEqual(picked[0].left, -15)
        XCTAssertEqual(picked[1].left, 100)
    }

    func testDigestCarriesAlerts() {
        let g = EveningDigest.make(date: d(2026, 10, 26), spent: 10, pending: 0, budgetLeft: nil, tomorrow: [],
                                   budgets: [EveningDigest.BudgetAlert(name: "Еда", currency: "BYN", limit: 100, spent: 90)], calendar: cal)
        XCTAssertEqual(g.budgets.count, 1)
    }
}
