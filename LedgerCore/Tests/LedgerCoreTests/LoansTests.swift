import XCTest
@testable import LedgerCore

final class LoansTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func d(_ y: Int, _ m: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: 9))! }

    func testPaymentsLeftRoundsUp() {
        XCTAssertEqual(Loans.paymentsLeft(debt: 1000, payment: 300), 4)   // 300+300+300+100
        XCTAssertEqual(Loans.paymentsLeft(debt: 900, payment: 300), 3)
        XCTAssertEqual(Loans.paymentsLeft(debt: 0, payment: 300), 0)
        XCTAssertNil(Loans.paymentsLeft(debt: 900, payment: 0))
    }

    func testEstimatedDebt() {
        XCTAssertEqual(Loans.estimatedDebt(payments: 12, payment: 250), 3000)
        XCTAssertEqual(Loans.estimatedDebt(payments: 0, payment: 250), 0)
    }

    func testPaidRatio() {
        XCTAssertEqual(Loans.paidRatio(principal: 1000, remaining: 250), 0.75, accuracy: 0.0001)
        // Исходная сумма неизвестна: считаем, что ничего ещё не выплачено.
        XCTAssertEqual(Loans.paidRatio(principal: nil, remaining: 500), 0, accuracy: 0.0001)
        // Долг вырос выше исходной суммы (проценты): не уходим в минус.
        XCTAssertEqual(Loans.paidRatio(principal: 100, remaining: 150), 0, accuracy: 0.0001)
        XCTAssertEqual(Loans.paidRatio(principal: 100, remaining: 0), 1, accuracy: 0.0001)
    }

    func testScheduledPaymentsCountsUntilEnd() {
        // Ежемесячно 15-го, ближайший 15 ноября, последний 15 апреля: ноябрь...апрель = 6 платежей.
        XCTAssertEqual(Loans.scheduledPayments(next: d(2026, 11, 15), end: d(2027, 4, 15), repeatType: 3, duration: 1, calendar: cal), 6)
        XCTAssertEqual(Loans.scheduledPayments(next: d(2026, 11, 15), end: d(2026, 11, 15), repeatType: 3, duration: 1, calendar: cal), 1)
        XCTAssertEqual(Loans.scheduledPayments(next: d(2026, 11, 15), end: d(2026, 10, 15), repeatType: 3, duration: 1, calendar: cal), 0)
        XCTAssertNil(Loans.scheduledPayments(next: d(2026, 11, 15), end: nil, repeatType: 3, duration: 1, calendar: cal))
    }
}
