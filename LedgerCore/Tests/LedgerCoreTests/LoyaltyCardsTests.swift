import XCTest
@testable import LedgerCore

final class LoyaltyCardsTests: XCTestCase {
    // MARK: EAN

    func testCheckDigit() {
        XCTAssertEqual(EAN.checkDigit("590123412345"), 7)
        XCTAssertEqual(EAN.checkDigit("400638133393"), 1)
        XCTAssertEqual(EAN.checkDigit("9638507"), 4)
    }

    func testValidation() {
        XCTAssertTrue(EAN.isValid("5901234123457"))
        XCTAssertFalse(EAN.isValid("5901234123458"))
        XCTAssertTrue(EAN.isValid("96385074"))
        XCTAssertFalse(EAN.isValid("123"))
    }

    func testNormalizedAppendsCheckDigit() {
        XCTAssertEqual(EAN.normalized("590123412345"), "5901234123457")
        XCTAssertNil(EAN.normalized("5901234123458"))
        XCTAssertNil(EAN.normalized("59012341234A"))
    }

    func testEAN13Modules() throws {
        let m = try XCTUnwrap(EAN.modules("5901234123457"))
        XCTAssertEqual(m.count, 95)
        let s = String(m.map { $0 ? "1" : "0" })
        // Начало, затем «9» набором L (первая цифра 5 даёт LGGLLG), центр и конец.
        XCTAssertTrue(s.hasPrefix("101" + "0001011"))
        XCTAssertEqual(String(Array(s)[45..<50]), "01010")
        XCTAssertTrue(s.hasSuffix("1000100" + "101"))  // последняя «7» набором R
    }

    func testEAN8Modules() throws {
        XCTAssertEqual(try XCTUnwrap(EAN.modules("96385074")).count, 67)
        XCTAssertNil(EAN.modules("96385075"))
    }

    // MARK: Формат

    func testGuessFormat() {
        XCTAssertEqual(BarcodeFormat.guess(for: "5901234123457"), .ean13)
        XCTAssertEqual(BarcodeFormat.guess(for: "96385074"), .ean8)
        XCTAssertEqual(BarcodeFormat.guess(for: "9482000010892"), .code128)  // 13 цифр, но контрольная не сходится
        XCTAssertEqual(BarcodeFormat.guess(for: "AB-123"), .code128)
    }

    func testAccepts() {
        XCTAssertTrue(BarcodeFormat.ean13.accepts("590123412345"))
        XCTAssertFalse(BarcodeFormat.ean13.accepts("5901234123458"))
        XCTAssertFalse(BarcodeFormat.code128.accepts("Карта"))
        XCTAssertTrue(BarcodeFormat.qr.accepts("Карта"))
        XCTAssertFalse(BarcodeFormat.qr.accepts(""))
    }

    func testSymbologyMapping() {
        XCTAssertEqual(BarcodeFormat.fromSymbology("VNBarcodeSymbologyEAN13"), .ean13)
        XCTAssertEqual(BarcodeFormat.fromSymbology("VNBarcodeSymbologyQR"), .qr)
        XCTAssertEqual(BarcodeFormat.fromSymbology("VNBarcodeSymbologyDataMatrix"), .qr)
        XCTAssertEqual(BarcodeFormat.fromSymbology("VNBarcodeSymbologyCode39"), .code128)
    }

    // MARK: Цвета

    let gray = RGB(0.35, 0.36, 0.38)
    let green = RGB(0.45, 0.75, 0.1)

    func testDominantFindsMainColors() {
        let pixels = Array(repeating: gray, count: 70) + Array(repeating: green, count: 20)
            + Array(repeating: RGB.white, count: 10)
        let d = CardColors.dominant(pixels, k: 3)
        XCTAssertEqual(d.count, 3)
        XCTAssertEqual(d[0].color.hex, gray.hex)
        XCTAssertEqual(d[0].share, 0.7, accuracy: 0.001)
        XCTAssertEqual(d[1].color.hex, green.hex)
    }

    func testGrayCardGetsGreenTitle() {
        // Серая карта с зелёным логотипом и белыми мелкими надписями: название зелёное, а не белое.
        let sw: [(color: RGB, share: Double)] = [(RGB(0.25, 0.25, 0.27), 0.7), (green, 0.15), (.white, 0.15)]
        let p = CardColors.palettes(from: sw)
        XCTAssertEqual(p.first?.background, RGB(0.25, 0.25, 0.27))
        XCTAssertEqual(p.first?.title, green)
    }

    func testFallsBackToWhiteOrBlack() {
        // Ярко-синий как у «Санты»: белый, как на самой карте.
        let blue = RGB(0.02, 0.64, 0.88)
        XCTAssertEqual(CardColors.title(on: blue, from: [(blue, 1)]), .white)
        let yellow = RGB(1, 0.85, 0.1)
        XCTAssertEqual(CardColors.title(on: yellow, from: [(yellow, 1)]), .black)
        let navy = RGB(0.05, 0.1, 0.3)
        XCTAssertEqual(CardColors.title(on: navy, from: [(navy, 1)]), .white)
    }

    func testLowContrastAccentIsSkipped() {
        // Светло-серый текст на сером фоне не читается: берём белый или чёрный.
        let bg = RGB(0.5, 0.5, 0.5)
        let t = CardColors.title(on: bg, from: [(bg, 0.8), (RGB(0.6, 0.6, 0.6), 0.2)])
        XCTAssertTrue(t == .white || t == .black)
    }

    func testAlternativePalettes() {
        let sw: [(color: RGB, share: Double)] = [(gray, 0.6), (green, 0.3), (.white, 0.1)]
        let p = CardColors.palettes(from: sw)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p[1].background, green)
    }

    func testHexRoundTrip() {
        XCTAssertEqual(RGB(hex: "#FF8000")?.hex, "FF8000")
        XCTAssertNil(RGB(hex: "XYZ"))
    }

    // MARK: Название

    func testTitlePicksLargestMeaningfulLine() {
        let lines = [CardTextLine(text: "КАРТА КЛИЕНТА", height: 0.2),
                     CardTextLine(text: "ЕВРООПТ", height: 0.15),
                     CardTextLine(text: "9482 0000 1089 221", height: 0.3),
                     CardTextLine(text: "www.evroopt.by", height: 0.05)]
        XCTAssertEqual(CardTitle.guess(lines), "Евроопт")
    }

    func testTitleCapitalizesLowercase() {
        XCTAssertEqual(CardTitle.guess([CardTextLine(text: "хамелеон", height: 0.2)]), "Хамелеон")
        XCTAssertEqual(CardTitle.guess([CardTextLine(text: "ProStore", height: 0.2)]), "ProStore")
    }

    func testTitleNilWhenNothingFits() {
        XCTAssertNil(CardTitle.guess([CardTextLine(text: "123456", height: 0.3)]))
    }
}
