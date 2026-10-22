import XCTest
@testable import LedgerCore

final class BankSMSTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }
    func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    // MARK: Настоящие СМС Приорбанка

    func testPurchase() {
        let t = "Karta 4***8780 19-10-26 14:51:23. Oplata 10.08 BYN. BLR SHOP KOPEECHKA. Balance: 103.82 BYN Tel. 7299090"
        let s = PriorbankSMS.parse(t, receivedAt: date(2026, 10, 19, 15, 0), calendar: cal)
        XCTAssertEqual(s, BankSMS(kind: .purchase, cardLast4: "8780", date: date(2026, 10, 19, 14, 51, 23), amount: dec("10.08"),
                                  currency: "BYN", merchant: "SHOP KOPEECHKA", balance: dec("103.82"), balanceIsAvailable: false))
    }

    func testCashDepositAtAtm() {
        let t = "Karta 4***8780 11-10-26 17:44:14. Zachislenie perevoda 1200.00 BYN. BLR Money Transfer Visa. Balance: 1200.16 BYN Tel. 7299090"
        let s = PriorbankSMS.parse(t, receivedAt: date(2026, 10, 19, 9, 0), calendar: cal)
        XCTAssertEqual(s?.kind, .cashDeposit)
        XCTAssertEqual(s?.amount, dec("1200.00"))
        XCTAssertEqual(s?.cardLast4, "8780")
        XCTAssertEqual(s?.merchant, "")
        XCTAssertEqual(s?.balance, dec("1200.16"))
        XCTAssertEqual(s?.balanceIsAvailable, false)
    }

    func testIncomingTransferWithoutCard() {
        let t = "08/10 16:49. Na vashu kartu zachisleno 50.00 BYN. Dostupnaja summa: 63.12 BYN. Tel. 7299090"
        let s = PriorbankSMS.parse(t, receivedAt: date(2026, 10, 19, 9, 0), calendar: cal)
        XCTAssertEqual(s, BankSMS(kind: .incomingTransfer, cardLast4: nil, date: date(2026, 10, 8, 16, 49), amount: dec("50.00"),
                                  currency: "BYN", merchant: "", balance: dec("63.12"), balanceIsAvailable: true))
    }

    func testIncomingTransferFromUserReport() {
        let t = "20/10 17:39. Na vashu kartu zachisleno 193.50 BYN. Dostupnaja summa: 272.71 BYN. Tel. 7299090"
        let s = PriorbankSMS.parse(t, receivedAt: date(2026, 10, 22, 9, 0), calendar: cal)
        XCTAssertEqual(s?.kind, .incomingTransfer)
        XCTAssertEqual(s?.amount, dec("193.50"))
        XCTAssertEqual(s?.date, date(2026, 10, 20, 17, 39))
    }

    // MARK: Решения по неизвестному

    func testYearRollsBackAcrossNewYear() {
        let t = "30/12 10:00. Na vashu kartu zachisleno 5.00 BYN. Dostupnaja summa: 5.00 BYN."
        let s = PriorbankSMS.parse(t, receivedAt: date(2027, 1, 2, 9, 0), calendar: cal)
        XCTAssertEqual(s?.date, date(2026, 12, 30, 10, 0))
    }

    func testThousandsSeparatorAndComma() {
        let t = "Karta 4***8780 01-11-26 10:00:00. Oplata 1 234,50 BYN. BLR MAGAZIN. Balance: 2 000,00 BYN"
        let s = PriorbankSMS.parse(t, receivedAt: date(2026, 11, 1, 11, 0), calendar: cal)
        XCTAssertEqual(s?.amount, dec("1234.50"))
        XCTAssertEqual(s?.balance, dec("2000.00"))
    }

    func testUnknownFormatsAreNotGuessed() {
        XCTAssertNil(PriorbankSMS.parse("Vash kod 123456"))
        XCTAssertNil(PriorbankSMS.parse("Karta 4***8780 19-10-26 14:51:23. Vozvrat 10.08 BYN. BLR SHOP. Balance: 1.00 BYN"))
        XCTAssertNil(PriorbankSMS.parse(""))
    }

    // MARK: Память о магазинах

    func testMerchantKeyIgnoresCountryBranchAndPunctuation() {
        XCTAssertEqual(MerchantMemory.key("BLR SHOP KOPEECHKA"), "SHOP KOPEECHKA")
        XCTAssertEqual(MerchantMemory.key("shop  kopeechka #12"), "SHOP KOPEECHKA")
        XCTAssertEqual(MerchantMemory.key("SHOP KOPEECHKA"), MerchantMemory.key("BLR SHOP-KOPEECHKA 7"))
        XCTAssertEqual(MerchantMemory.key("12"), "12")
    }

    func testNewMerchantIsUnknown() {
        XCTAssertEqual(MerchantMemory.suggest(counts: [(String, Int)]()), .unknown)
    }

    func testSingleCategoryIsConfident() {
        XCTAssertEqual(MerchantMemory.suggest(counts: [("cigs", 1)]), .confident("cigs"))
        XCTAssertEqual(MerchantMemory.suggest(counts: [("cigs", 3), ("food", 0)]), .confident("cigs"))
    }

    func testTwoCategoriesAskMostFrequentFirst() {
        XCTAssertEqual(MerchantMemory.suggest(counts: [("cigs", 1), ("food", 2)]), .ask(["food", "cigs"]))
        // при равенстве сохраняется порядок: сначала та, что в списке раньше
        XCTAssertEqual(MerchantMemory.suggest(counts: [("cigs", 1), ("food", 1)]), .ask(["cigs", "food"]))
    }

    func testDominantCategoryWinsWithEnoughHistory() {
        XCTAssertEqual(MerchantMemory.suggest(counts: [("food", 8), ("cigs", 1)]), .confident("food"))
        XCTAssertEqual(MerchantMemory.suggest(counts: [("food", 3), ("cigs", 1)]), .ask(["food", "cigs"]))
    }

    func testAtMostThreeOptions() {
        let r = MerchantMemory.suggest(counts: [("a", 4), ("b", 3), ("c", 2), ("d", 1)])
        XCTAssertEqual(r, .ask(["a", "b", "c"]))
    }
}
