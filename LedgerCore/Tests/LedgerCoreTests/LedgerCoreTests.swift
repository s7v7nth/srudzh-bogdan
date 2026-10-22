import XCTest
@testable import LedgerCore

final class LedgerCoreTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: 12))! }

    // MARK: Money
    func testRoundingHalfUpAwayFromZero() {
        XCTAssertEqual(Money.round(Decimal(string: "2.345")!), Decimal(string: "2.35")!)
        XCTAssertEqual(Money.round(Decimal(string: "-2.345")!), Decimal(string: "-2.35")!)
    }
    func testNoFloatingPointDrift() {
        XCTAssertEqual(Decimal(string: "0.1")! + Decimal(string: "0.2")!, Decimal(string: "0.3")!)
    }

    // MARK: Recurrence
    func testMonthlyFromJan31NoDrift() {
        let jan31 = d(2025, 1, 31)
        XCTAssertEqual(Recurrence.nextDate(type: 3, duration: 1, from: jan31, after: d(2025, 1, 31), calendar: cal), d(2025, 2, 28))
        XCTAssertEqual(Recurrence.nextDate(type: 3, duration: 1, from: jan31, after: d(2025, 2, 28), calendar: cal), d(2025, 3, 31))
    }
    func testEveryTwoWeeks() {
        XCTAssertEqual(Recurrence.nextDate(type: 2, duration: 2, from: d(2025, 1, 1), calendar: cal), d(2025, 1, 15))
    }
    func testYearlyFromLeapDay() {
        XCTAssertEqual(Recurrence.nextDate(type: 4, duration: 1, from: d(2024, 2, 29), calendar: cal), d(2025, 2, 28))
    }
    func testFarFutureAfterDateLoops() {
        let r = Recurrence.nextDate(type: 1, duration: 7, from: d(2025, 1, 1), after: d(2025, 12, 31), calendar: cal)!
        XCTAssertGreaterThan(r, d(2025, 12, 31))
        XCTAssertEqual(cal.dateComponents([.day], from: d(2025, 1, 1), to: r).day! % 7, 0)
    }
    func testInvalidInputIsNil() {
        XCTAssertNil(Recurrence.nextDate(type: 0, duration: 1, from: d(2025, 1, 1), calendar: cal))
        XCTAssertNil(Recurrence.nextDate(type: 12, duration: 1, from: d(2025, 1, 1), calendar: cal))
        XCTAssertNil(Recurrence.nextDate(type: 3, duration: 0, from: d(2025, 1, 1), calendar: cal))
    }
    func testSecondTuesdayAcrossMonths() {
        // type 7 = вторник, ordinal 2. Второй вторник января 2025 = 14, февраля = 11.
        let r = Recurrence.nextDate(type: 7, duration: 2, from: d(2025, 1, 1), after: d(2025, 1, 14), calendar: cal)
        XCTAssertEqual(r, d(2025, 2, 11))
    }

    // MARK: Balances
    func testBalanceWithAndWithoutPending() {
        let e = [LedgerEntry(amount: 100, date: d(2025, 1, 1)),
                 LedgerEntry(amount: -30, date: d(2025, 1, 2), pending: true),
                 LedgerEntry(amount: -20, date: d(2025, 2, 1))]
        XCTAssertEqual(Balances.balance(e), 50)
        XCTAssertEqual(Balances.balance(e, includePending: false), 80)
        XCTAssertEqual(Balances.balance(e, asOf: d(2025, 1, 15)), 70)
    }
    func testCreditAvailable() {
        XCTAssertEqual(Balances.availableCredit(limit: 1000, balance: -300), 700)
    }
    func testMultiCurrencyTotalAndExcluded() {
        let t = Balances.total([(100, 1, false), (50, Decimal(string: "1.1")!, false), (999, 1, true)])
        XCTAssertEqual(t, 155)
    }

    // MARK: Budgets
    func testPeriodRollover() {
        let p = Budgets.period(start: d(2025, 1, 1), type: 3, duration: 1, containing: d(2025, 3, 15), calendar: cal)!
        XCTAssertEqual(p.start, d(2025, 3, 1))
        XCTAssertEqual(p.end, d(2025, 4, 1))
    }
    func testBudgetFiltersRefundsAndCarryOver() {
        let food = UUID(), fun = UUID(), skip = UUID()
        let p = DateInterval(start: d(2025, 1, 1), end: d(2025, 2, 1))
        let tx = [
            BudgetTransaction(amount: -100, date: d(2025, 1, 5), categoryID: food),
            BudgetTransaction(amount: -50, date: d(2025, 1, 6), categoryID: fun),
            BudgetTransaction(amount: -40, date: d(2025, 1, 7), categoryID: food, tagIDs: [skip]),
            BudgetTransaction(amount: -10, date: d(2025, 1, 8), categoryID: food, pending: true),
            BudgetTransaction(amount: 20, date: d(2025, 1, 9), categoryID: food),
            BudgetTransaction(amount: -999, date: d(2025, 2, 1), categoryID: food),
        ]
        let rules = BudgetRules(monitoredCategories: [food], excludedTags: [skip])
        let r = Budgets.evaluate(limit: 200, carryOver: 30, period: p, transactions: tx, rules: rules)
        XCTAssertEqual(r.spent, 80)
        XCTAssertEqual(r.remaining, 150)
        let big = [BudgetTransaction(amount: 70, date: d(2025, 1, 9), categoryID: food)]
        XCTAssertEqual(Budgets.evaluate(limit: 200, period: p, transactions: big, rules: rules).unusedRefunds, 70)
    }
    func testCarryOverNegativeOnlyWhenAllowed() {
        XCTAssertEqual(Budgets.carryOverAmount(remaining: -20, carryNegative: false), 0)
        XCTAssertEqual(Budgets.carryOverAmount(remaining: -20, carryNegative: true), -20)
        XCTAssertEqual(Budgets.carryOverAmount(remaining: 20, carryNegative: false), 20)
    }
    func testLimitHistoryOverride() {
        let p = DateInterval(start: d(2025, 3, 1), end: d(2025, 4, 1))
        let h = [(d(2025, 1, 1), Decimal(300)), (d(2025, 2, 1), Decimal(400)), (d(2025, 6, 1), Decimal(900))]
        XCTAssertEqual(Budgets.limit(base: 100, history: h, for: p), 400)
        XCTAssertEqual(Budgets.limit(base: 100, history: [], for: p), 100)
    }
    func testBudgetCurrencyConversion() {
        let p = DateInterval(start: d(2025, 1, 1), end: d(2025, 2, 1))
        let tx = [BudgetTransaction(amount: -10, date: d(2025, 1, 5), rate: Decimal(string: "1.5")!)]
        XCTAssertEqual(Budgets.evaluate(limit: 100, period: p, transactions: tx, rules: BudgetRules()).spent, 15)
    }

    // MARK: Plans
    func testPlanAnnualDividedByTwelve() {
        XCTAssertEqual(Plans.monthlyAmount(annualAmount: 1200, repeatMonths: 1, month: d(2025, 5, 1), calendar: cal), 100)
        XCTAssertEqual(Plans.monthlyAmount(annualAmount: 1200, repeatMonths: 12, paymentDate: d(2025, 5, 10), month: d(2025, 5, 1), calendar: cal), 1200)
    }
    func testPlanQuarterlyAndYearlyOnlyInDueMonths() {
        let first = d(2025, 2, 10)
        XCTAssertEqual(Plans.monthlyAmount(annualAmount: 1200, repeatMonths: 3, paymentDate: first, month: d(2025, 5, 1), calendar: cal), 300)
        XCTAssertEqual(Plans.monthlyAmount(annualAmount: 1200, repeatMonths: 3, paymentDate: first, month: d(2025, 4, 1), calendar: cal), 0)
        XCTAssertEqual(Plans.monthlyAmount(annualAmount: 1200, repeatMonths: 12, paymentDate: first, month: d(2026, 2, 1), calendar: cal), 1200)
        XCTAssertEqual(Plans.monthlyAmount(annualAmount: 1200, repeatMonths: 12, paymentDate: first, month: d(2025, 8, 1), calendar: cal), 0)
    }
    func testPlanOneOffOnlyInPaymentMonth() {
        XCTAssertEqual(Plans.monthlyAmount(annualAmount: 500, repeatMonths: nil, paymentDate: d(2025, 7, 10), month: d(2025, 7, 1), calendar: cal), 500)
        XCTAssertEqual(Plans.monthlyAmount(annualAmount: 500, repeatMonths: nil, paymentDate: d(2025, 7, 10), month: d(2025, 8, 1), calendar: cal), 0)
    }
}
