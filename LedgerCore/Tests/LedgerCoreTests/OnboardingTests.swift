import XCTest
@testable import LedgerCore

final class OnboardingTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func d(_ y: Int, _ m: Int, _ day: Int, hour: Int = 9) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: hour))! }

    // MARK: Шаг округления
    func testStepGrowsWithIncome() {
        XCTAssertEqual(BudgetSplit.step(for: 800), 5)
        XCTAssertEqual(BudgetSplit.step(for: 3000), 10)
        XCTAssertEqual(BudgetSplit.step(for: 12000), 50)
        XCTAssertEqual(BudgetSplit.step(for: 60000), 100)
        XCTAssertEqual(BudgetSplit.step(for: 250000), 1000)
        XCTAssertEqual(BudgetSplit.step(for: 3_000_000), 10000)
    }

    func testRoundingModes() {
        XCTAssertEqual(BudgetSplit.floorToStep(1347, step: 10), 1340)
        XCTAssertEqual(BudgetSplit.ceilToStep(1341, step: 10), 1350)
        XCTAssertEqual(BudgetSplit.nearestToStep(1345, step: 10), 1350)
        XCTAssertEqual(BudgetSplit.nearestToStep(1344, step: 10), 1340)
    }

    // MARK: Шаблоны
    func testTemplatesSumTo100() {
        for t in BudgetSplit.templates { XCTAssertEqual(t.needs + t.wants + t.savings, 100, t.id) }
    }

    func testGroupTotalsAreRoundAndSumToBase() {
        let t = BudgetSplit.groupTotals(income: 3347, template: BudgetTemplate(50, 30, 20))
        XCTAssertEqual(t.base, 3340)
        XCTAssertEqual(t.needs, 1670)
        XCTAssertEqual(t.wants, 1000)
        XCTAssertEqual(t.savings, 670)
        XCTAssertEqual(t.needs + t.wants + t.savings, t.base)
    }

    func testGroupTotalsForEveryTemplateAndIncome() {
        for income in [Decimal(0), 137, 999, 2500, 4999, 18_250, 77_777, 640_000, 5_000_000] {
            for tpl in BudgetSplit.templates {
                let t = BudgetSplit.groupTotals(income: income, template: tpl)
                XCTAssertEqual(t.needs + t.wants + t.savings, t.base, "\(income) \(tpl.id)")
                XCTAssertTrue(t.needs >= 0 && t.wants >= 0 && t.savings >= 0, "\(income) \(tpl.id)")
                let step = BudgetSplit.step(for: income)
                XCTAssertEqual(t.needs, BudgetSplit.floorToStep(t.needs, step: step))
            }
        }
    }

    // MARK: Раскладка по категориям
    func testDistributeByWeightsSumsToTotal() {
        let r = BudgetSplit.distribute(total: 1000, floors: [0, 0, 0], weights: [1, 1, 1], step: 10)
        XCTAssertEqual(r.reduce(0, +), 1000)
        XCTAssertTrue(r.allSatisfy { BudgetSplit.floorToStep($0, step: 10) == $0 })
        XCTAssertEqual(r, [340, 330, 330])
    }

    func testDistributeRespectsFloors() {
        // Аренда 800 внутри группы на 1000: остальные делят оставшиеся 200.
        let r = BudgetSplit.distribute(total: 1000, floors: [800, 0, 0], weights: [10, 1, 1], step: 10)
        XCTAssertEqual(r.reduce(0, +), 1000)
        XCTAssertGreaterThanOrEqual(r[0], 800)
    }

    func testDistributeFloorsExceedTotal() {
        let r = BudgetSplit.distribute(total: 500, floors: [800, 0], weights: [1, 1], step: 10)
        XCTAssertEqual(r, [800, 0])
    }

    func testDistributeRoundsFloorUpToStep() {
        let r = BudgetSplit.distribute(total: 100, floors: [42], weights: [1], step: 10)
        XCTAssertEqual(r, [100])
    }

    func testDistributeZeroWeightGetsOnlyFloor() {
        let r = BudgetSplit.distribute(total: 300, floors: [0, 100], weights: [1, 0], step: 10)
        XCTAssertEqual(r, [200, 100])
    }

    // MARK: Периодичность
    func testCadenceMapping() {
        XCTAssertEqual(PaymentCadence.monthly.repeatType, 3)
        XCTAssertEqual(PaymentCadence.twiceMonthly.repeatType, 3)
        XCTAssertEqual(PaymentCadence.biweekly.repeatType, 2)
        XCTAssertEqual(PaymentCadence.biweekly.duration, 2)
        XCTAssertEqual(PaymentCadence.yearly.repeatType, 4)
        XCTAssertEqual(PaymentCadence.twiceMonthly.perMonth, 2)
        // 1/12 не точна в десятичной дроби, поэтому суммы за месяц всегда округляются до копеек.
        XCTAssertEqual(Money.round(1200 * PaymentCadence.yearly.perMonth), 100)
        XCTAssertEqual(Money.round(100 * PaymentCadence.weekly.perMonth), Decimal(string: "433.33")!)
    }

    // MARK: Первая дата
    func testMonthlyDayLaterThisMonth() {
        XCTAssertEqual(FirstPayment.monthly(day: 20, from: d(2026, 10, 22, hour: 9), calendar: cal), d(2026, 11, 20, hour: 12))
        XCTAssertEqual(FirstPayment.monthly(day: 25, from: d(2026, 10, 22), calendar: cal), d(2026, 10, 25, hour: 12))
    }

    func testMonthlyTodayCountsAsToday() {
        XCTAssertEqual(FirstPayment.monthly(day: 22, from: d(2026, 10, 22, hour: 18), calendar: cal), d(2026, 10, 22, hour: 12))
    }

    func testMonthlyDayIsCappedAt28() {
        XCTAssertEqual(FirstPayment.monthly(day: 31, from: d(2026, 2, 1), calendar: cal), d(2026, 2, 28, hour: 12))
    }

    func testMonthlyWrapsToNextYear() {
        XCTAssertEqual(FirstPayment.monthly(day: 5, from: d(2026, 12, 20), calendar: cal), d(2027, 1, 5, hour: 12))
    }

    func testWeeklyPicksNearestWeekday() {
        // 22 октября 2026 это четверг; пятница (6) завтра, четверг (5) сегодня, среда (4) через шесть дней.
        XCTAssertEqual(FirstPayment.weekly(weekday: 6, from: d(2026, 10, 22), calendar: cal), d(2026, 10, 23, hour: 12))
        XCTAssertEqual(FirstPayment.weekly(weekday: 5, from: d(2026, 10, 22), calendar: cal), d(2026, 10, 22, hour: 12))
        XCTAssertEqual(FirstPayment.weekly(weekday: 4, from: d(2026, 10, 22), calendar: cal), d(2026, 10, 28, hour: 12))
    }

    func testYearlyMovesPastDateForward() {
        XCTAssertEqual(FirstPayment.yearly(date: d(2026, 3, 10), from: d(2026, 10, 22), calendar: cal), d(2027, 3, 10, hour: 12))
        XCTAssertEqual(FirstPayment.yearly(date: d(2026, 12, 1), from: d(2026, 10, 22), calendar: cal), d(2026, 12, 1, hour: 12))
    }
}
