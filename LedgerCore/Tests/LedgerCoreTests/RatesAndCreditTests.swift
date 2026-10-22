import XCTest
@testable import LedgerCore

final class RatesAndCreditTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: 12))! }
    func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    // MARK: Курсы
    func testFractionDigits() {
        XCTAssertEqual(Money.fractionDigits("BYN"), 2)
        XCTAssertEqual(Money.fractionDigits("USD"), 2)
        XCTAssertEqual(Money.fractionDigits("JPY"), 0)
    }
    func testCrossRate() {
        let t = RateTable(perUSD: ["USD": 1, "BYN": dec("3"), "RUB": dec("90")])
        XCTAssertEqual(t.rate(from: "BYN", to: "RUB"), 30)
        XCTAssertEqual(t.rate(from: "USD", to: "BYN"), 3)
        XCTAssertEqual(t.rate(from: "RUB", to: "RUB"), 1)
        XCTAssertNil(t.rate(from: "EUR", to: "RUB"))
        XCTAssertEqual(t.convert(100, from: "USD", to: "BYN"), 300)
    }
    func testConvertRoundsToTargetCurrencyDigits() {
        let t = RateTable(perUSD: ["USD": 1, "JPY": dec("150.5")])
        XCTAssertEqual(t.convert(dec("1.01"), from: "USD", to: "JPY"), 152)
    }
    func testParseFawaz() {
        let json = #"{"date":"2026-10-18","usd":{"rub":84.12110886,"byn":3.01539232,"usd":1}}"#.data(using: .utf8)!
        let t = RateTable.parseFawaz(json)
        XCTAssertEqual(t?.perUSD["RUB"], dec("84.12110886"))
        XCTAssertEqual(t?.perUSD["BYN"], dec("3.01539232"))
        XCTAssertNotNil(t?.date)
        XCTAssertNil(RateTable.parseFawaz(Data("{}".utf8)))
    }
    func testParseERAPI() {
        let json = #"{"result":"success","time_last_update_unix":1792368000,"rates":{"RUB":83.208148,"USD":1}}"#.data(using: .utf8)!
        XCTAssertEqual(RateTable.parseERAPI(json)?.perUSD["RUB"], dec("83.208148"))
        XCTAssertNil(RateTable.parseERAPI(#"{"result":"error"}"#.data(using: .utf8)!))
    }

    // MARK: Кредитная линия
    func testStatementDateClampsToMonthLength() {
        XCTAssertEqual(CreditLine.statementDate(year: 2025, month: 2, statementDay: 31, calendar: cal),
                       cal.date(from: DateComponents(year: 2025, month: 2, day: 28))!)
    }
    func testPeriodContaining() {
        let p = CreditLine.period(containing: d(2025, 3, 20), statementDay: 15, calendar: cal)
        XCTAssertEqual(p.start, cal.date(from: DateComponents(year: 2025, month: 3, day: 15)))
        XCTAssertEqual(p.end, cal.date(from: DateComponents(year: 2025, month: 4, day: 15)))
        let q = CreditLine.period(containing: d(2025, 3, 10), statementDay: 15, calendar: cal)
        XCTAssertEqual(q.start, cal.date(from: DateComponents(year: 2025, month: 2, day: 15)))
    }
    func testMinimumPayment() {
        XCTAssertEqual(CreditLine.minimumPayment(debt: 1000, percent: 5, floor: 50), 50)
        XCTAssertEqual(CreditLine.minimumPayment(debt: 2000, percent: 5, floor: 50), 100)
        XCTAssertEqual(CreditLine.minimumPayment(debt: 30, percent: 5, floor: 50), 30)
        XCTAssertEqual(CreditLine.minimumPayment(debt: 0, percent: 5, floor: 50), 0)
    }
    func testUtilization() {
        XCTAssertEqual(CreditLine.utilization(debt: 250, limit: 1000), dec("0.25"))
        XCTAssertEqual(CreditLine.utilization(debt: 250, limit: 0), 0)
    }
    func testGraceFromStatement() {
        let terms = CreditTerms(limit: 1000, statementDay: 1, graceDays: 20, graceFromStatement: true)
        let entries = [LedgerEntry(amount: -100, date: d(2025, 1, 10))]
        let s = CreditLine.graceStatus(entries: entries, today: d(2025, 2, 5), terms: terms, calendar: cal)
        XCTAssertEqual(s.amountDue, 100)
        XCTAssertEqual(s.nextDeadline, cal.date(from: DateComponents(year: 2025, month: 2, day: 21)))
        XCTAssertEqual(s.interestBearing, 0)
    }
    func testRepaymentClosesOldestPurchaseFirst() {
        let terms = CreditTerms(limit: 1000, statementDay: 1, graceDays: 20, graceFromStatement: true)
        let entries = [LedgerEntry(amount: -100, date: d(2025, 1, 5)),
                       LedgerEntry(amount: -200, date: d(2025, 1, 20)),
                       LedgerEntry(amount: 150, date: d(2025, 2, 3))]
        XCTAssertEqual(CreditLine.graceStatus(entries: entries, today: d(2025, 2, 5), terms: terms, calendar: cal).amountDue, 150)
    }
    func testGraceFromPurchaseWithExpiredLot() {
        let terms = CreditTerms(limit: 1000, graceDays: 30, graceFromStatement: false)
        let entries = [LedgerEntry(amount: -100, date: d(2025, 1, 10)), LedgerEntry(amount: -50, date: d(2025, 2, 1))]
        let s = CreditLine.graceStatus(entries: entries, today: d(2025, 2, 15), terms: terms, calendar: cal)
        XCTAssertEqual(s.interestBearing, 100)
        XCTAssertEqual(s.amountDue, 50)
        XCTAssertEqual(s.nextDeadline, cal.date(from: DateComponents(year: 2025, month: 3, day: 3)))
    }
    func testFullRepaymentLeavesNothingDue() {
        let terms = CreditTerms(limit: 1000, statementDay: 1, graceDays: 20)
        let entries = [LedgerEntry(amount: -100, date: d(2025, 1, 10)), LedgerEntry(amount: 100, date: d(2025, 1, 25))]
        let s = CreditLine.graceStatus(entries: entries, today: d(2025, 2, 5), terms: terms, calendar: cal)
        XCTAssertEqual(s.amountDue, 0)
        XCTAssertNil(s.nextDeadline)
    }
    func testInterestEstimateOnlyAfterGrace() {
        let terms = CreditTerms(limit: 5000, aprPercent: 10, graceDays: 30, graceFromStatement: false)
        let entries = [LedgerEntry(amount: -3650, date: d(2025, 1, 1))]
        // Срок до 31 января, проценты с 1 февраля: 10 дней по 3650 * 10 / 36500 = 1.00
        XCTAssertEqual(CreditLine.interestEstimate(entries: entries, from: d(2025, 2, 1), through: d(2025, 2, 10), terms: terms, calendar: cal), 10)
        XCTAssertEqual(CreditLine.interestEstimate(entries: entries, from: d(2025, 1, 1), through: d(2025, 1, 31), terms: terms, calendar: cal), 0)
    }
    func testNoGraceMeansInterestFromNextDay() {
        let terms = CreditTerms(limit: 5000, aprPercent: 10, graceDays: 0, graceFromStatement: false)
        let entries = [LedgerEntry(amount: -3650, date: d(2025, 1, 1))]
        XCTAssertEqual(CreditLine.interestEstimate(entries: entries, from: d(2025, 1, 1), through: d(2025, 1, 3), terms: terms, calendar: cal), 2)
    }
    func testStatementsHistory() {
        let terms = CreditTerms(limit: 1000, statementDay: 1)
        let entries = [LedgerEntry(amount: -100, date: d(2025, 1, 10)), LedgerEntry(amount: -50, date: d(2025, 1, 20)),
                       LedgerEntry(amount: 60, date: d(2025, 2, 3))]
        let s = CreditLine.statements(entries: entries, terms: terms, count: 2, asOf: d(2025, 2, 15), calendar: cal)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].purchases, 150)
        XCTAssertEqual(s[0].payments, 0)
        XCTAssertEqual(s[0].closingDebt, 150)
        XCTAssertEqual(s[1].purchases, 0)
    }
}
