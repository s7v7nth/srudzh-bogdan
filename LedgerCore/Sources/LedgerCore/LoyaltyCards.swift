import Foundation

// MARK: - Формат штрихкода

/// Какой код показывать на кассе. Набор ограничен тем, что приложение умеет нарисовать само.
/// Решение: если со снимка прочитан код, который мы не рисуем (Code 39, ITF, UPC-E, DataMatrix и др.),
/// показываем то же содержимое ближайшим по типу кодом (линейные как Code 128, двумерные как QR).
/// Кассовые сканеры читают все эти форматы, а магазину важно только содержимое.
public enum BarcodeFormat: String, Codable, CaseIterable, Sendable {
    case qr, ean13, ean8, code128, pdf417, aztec

    public var isLinear: Bool { self == .ean13 || self == .ean8 || self == .code128 }

    /// Формат по названию типа кода из распознавания iPhone (`VNBarcodeSymbology.rawValue`).
    public static func fromSymbology(_ raw: String) -> BarcodeFormat {
        let s = raw.lowercased()
        if s.contains("qr") { return .qr }
        if s.contains("ean13") || s.contains("ean-13") { return .ean13 }
        if s.contains("ean8") || s.contains("ean-8") { return .ean8 }
        if s.contains("pdf417") { return .pdf417 }
        if s.contains("aztec") { return .aztec }
        if s.contains("datamatrix") || s.contains("microqr") { return .qr }
        return .code128
    }

    /// Догадка по самому номеру, когда его ввели руками.
    public static func guess(for number: String) -> BarcodeFormat {
        let digits = number.filter(\.isNumber)
        guard digits.count == number.count else { return .code128 }
        if digits.count == 13, EAN.isValid(digits) { return .ean13 }
        if digits.count == 8, EAN.isValid(digits) { return .ean8 }
        return .code128
    }

    /// Можно ли этим форматом закодировать номер.
    public func accepts(_ number: String) -> Bool {
        guard !number.isEmpty else { return false }
        switch self {
        case .ean13, .ean8:
            let n = self == .ean13 ? 13 : 8
            guard number.allSatisfy(\.isASCIIDigit) else { return false }
            return number.count == n - 1 || (number.count == n && EAN.isValid(number))
        case .code128:
            return number.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value < 127 }
        case .qr, .pdf417, .aztec:
            return true
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

// MARK: - EAN-13 и EAN-8

/// Рисунок штрихкода EAN: последовательность модулей (true = чёрная полоса).
/// Системные средства iPhone EAN не рисуют, поэтому кодируем сами.
public enum EAN {
    /// Контрольная цифра для номера без неё (12 цифр для EAN-13, 7 для EAN-8).
    public static func checkDigit(_ body: String) -> Int? {
        let d = body.compactMap(\.wholeNumberValue)
        guard d.count == body.count, !d.isEmpty else { return nil }
        // Веса 3 и 1 чередуются справа налево, начиная с 3.
        var sum = 0
        for (i, v) in d.reversed().enumerated() { sum += v * (i % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10
    }

    public static func isValid(_ code: String) -> Bool {
        guard code.count == 13 || code.count == 8, let last = code.last?.wholeNumberValue,
              let c = checkDigit(String(code.dropLast())) else { return false }
        return c == last
    }

    /// Полный номер: дописывает контрольную цифру к 12 или 7 цифрам, проверяет 13 или 8.
    public static func normalized(_ code: String) -> String? {
        guard code.allSatisfy({ $0.wholeNumberValue != nil }) else { return nil }
        switch code.count {
        case 12, 7: return checkDigit(code).map { code + String($0) }
        case 13, 8: return isValid(code) ? code : nil
        default: return nil
        }
    }

    private static let l = ["0001101", "0011001", "0010011", "0111101", "0100011",
                            "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let g = ["0100111", "0110011", "0011011", "0100001", "0011101",
                            "0111001", "0000101", "0010001", "0001001", "0010111"]
    private static let r = ["1110010", "1100110", "1101100", "1000010", "1011100",
                            "1001110", "1010000", "1000100", "1001000", "1110100"]
    /// Какие цифры левой половины EAN-13 кодируются набором G, в зависимости от первой цифры.
    private static let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
                                 "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    /// Модули штрихкода без полей тишины: 95 для EAN-13, 67 для EAN-8.
    public static func modules(_ code: String) -> [Bool]? {
        guard let full = normalized(code) else { return nil }
        let d = full.compactMap(\.wholeNumberValue)
        var s = "101"
        if d.count == 13 {
            let p = Array(parity[d[0]])
            for i in 1...6 { s += p[i - 1] == "L" ? l[d[i]] : g[d[i]] }
            s += "01010"
            for i in 7...12 { s += r[d[i]] }
        } else {
            for i in 0...3 { s += l[d[i]] }
            s += "01010"
            for i in 4...7 { s += r[d[i]] }
        }
        s += "101"
        return s.map { $0 == "1" }
    }
}

// MARK: - Цвета карты

/// Цвет в долях от 0 до 1.
public struct RGB: Hashable, Sendable {
    public var r, g, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    public static let white = RGB(1, 1, 1)
    public static let black = RGB(0, 0, 0)

    public init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    public var hex: String {
        func c(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", c(r), c(g), c(b))
    }

    /// Яркость для расчёта контраста (как в правилах доступности WCAG).
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Насыщенность от 0 (серый) до 1 (чистый цвет).
    public var saturation: Double {
        let mx = max(r, g, b), mn = min(r, g, b)
        return mx == 0 ? 0 : (mx - mn) / mx
    }

    public func contrast(_ o: RGB) -> Double {
        let a = luminance, b = o.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func distance2(_ o: RGB) -> Double {
        let dr = r - o.r, dg = g - o.g, db = b - o.b
        return dr * dr + dg * dg + db * db
    }
}

/// Пара «фон карты и цвет названия».
public struct CardPalette: Hashable, Sendable {
    public var background: RGB
    public var title: RGB
    public init(background: RGB, title: RGB) { self.background = background; self.title = title }
}

public enum CardColors {
    /// Основные цвета снимка: группирует похожие точки и возвращает средний цвет каждой группы с её долей (0...1),
    /// от самой большой к самой маленькой. Результат одинаков при одинаковых данных.
    public static func dominant(_ pixels: [RGB], k: Int = 5, iterations: Int = 12) -> [(color: RGB, share: Double)] {
        guard !pixels.isEmpty, k > 0 else { return [] }
        // Начальные центры: первая точка, дальше каждый раз самая далёкая от уже выбранных.
        var centers = [pixels[0]]
        var nearest = pixels.map { $0.distance2(pixels[0]) }
        while centers.count < k {
            guard let i = nearest.indices.max(by: { nearest[$0] < nearest[$1] }), nearest[i] > 0.0004 else { break }
            centers.append(pixels[i])
            for j in pixels.indices { nearest[j] = min(nearest[j], pixels[j].distance2(pixels[i])) }
        }
        var assign = [Int](repeating: 0, count: pixels.count)
        for _ in 0..<iterations {
            for (j, p) in pixels.enumerated() {
                assign[j] = centers.indices.min(by: { p.distance2(centers[$0]) < p.distance2(centers[$1]) })!
            }
            var sum = [RGB](repeating: .black, count: centers.count)
            var count = [Int](repeating: 0, count: centers.count)
            for (j, p) in pixels.enumerated() {
                let c = assign[j]
                sum[c].r += p.r; sum[c].g += p.g; sum[c].b += p.b; count[c] += 1
            }
            for c in centers.indices where count[c] > 0 {
                let n = Double(count[c])
                centers[c] = RGB(sum[c].r / n, sum[c].g / n, sum[c].b / n)
            }
        }
        var count = [Int](repeating: 0, count: centers.count)
        for a in assign { count[a] += 1 }
        let total = Double(pixels.count)
        return centers.indices.filter { count[$0] > 0 }
            .map { (centers[$0], Double(count[$0]) / total) }
            .sorted { $0.1 > $1.1 }
    }

    /// Наименьший контраст названия. Решение: 2,4 вместо строгих 3:1, потому что название крупное и жирное,
    /// а магазины любят белый текст на ярко-синем и оранжевом, и чёрный там выглядит чужим.
    static let minContrast = 2.4

    /// Цвет названия для фона: самый заметный из остальных цветов карты, который хорошо читается;
    /// если такого нет, белый или чёрный.
    public static func title(on bg: RGB, from swatches: [(color: RGB, share: Double)]) -> RGB {
        let candidates = swatches.filter { $0.share >= 0.02 && $0.color.contrast(bg) >= minContrast }
        if let best = candidates.max(by: { score($0, bg) < score($1, bg) }) { return best.color }
        return RGB.white.contrast(bg) >= minContrast ? .white : .black
    }

    private static func score(_ s: (color: RGB, share: Double), _ bg: RGB) -> Double {
        // Цветной акцент (зелёное «Евроопт» на сером) важнее, чем просто белый текст; доля добавляет немного веса.
        s.color.contrast(bg) * (0.6 + s.color.saturation) * (1 + min(s.share, 0.3))
    }

    /// Варианты оформления: первый основной (фон = самый крупный цвет), дальше запасные с другими фонами.
    public static func palettes(from swatches: [(color: RGB, share: Double)], limit: Int = 4) -> [CardPalette] {
        var out: [CardPalette] = []
        for s in swatches where s.share >= 0.08 {
            let p = CardPalette(background: s.color, title: title(on: s.color, from: swatches))
            if !out.contains(where: { $0.background.distance2(p.background) < 0.01 && $0.title.distance2(p.title) < 0.01 }) {
                out.append(p)
            }
            if out.count == limit { break }
        }
        if out.isEmpty, let s = swatches.first {
            out.append(CardPalette(background: s.color, title: title(on: s.color, from: swatches)))
        }
        return out
    }
}

// MARK: - Название магазина

/// Строка текста, найденная на карте: высота в долях высоты карты.
public struct CardTextLine: Sendable {
    public var text: String
    public var height: Double
    public init(text: String, height: Double) { self.text = text; self.height = height }
}

public enum CardTitle {
    /// Служебные надписи, которые не бывают названием магазина.
    private static let noise = ["карта", "card", "клиента", "бонус", "bonus", "номер", "скидк", "discount",
                                "loyalty", "member", "www", "http", ".by", ".ru", ".com"]

    /// Название магазина: самая крупная осмысленная надпись (не номер и не «карта клиента»).
    public static func guess(_ lines: [CardTextLine]) -> String? {
        let good = lines.compactMap { l -> CardTextLine? in
            let t = l.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let letters = t.filter(\.isLetter).count
            guard letters >= 3, letters * 2 >= t.count else { return nil }
            let low = t.lowercased()
            guard !noise.contains(where: low.contains) else { return nil }
            return CardTextLine(text: t, height: l.height)
        }
        guard let best = good.max(by: { $0.height < $1.height }) else { return nil }
        return pretty(best.text)
    }

    /// «ЕВРООПТ» и «хамелеон» → «Евроопт», «Хамелеон»: на плитке название с одной заглавной.
    static func pretty(_ s: String) -> String {
        let letters = s.filter(\.isLetter)
        if letters == letters.uppercased(), letters.count > 3 {
            return s.lowercased().prefix(1).uppercased() + s.lowercased().dropFirst()
        }
        if letters == letters.lowercased() { return s.prefix(1).uppercased() + s.dropFirst() }
        return s
    }
}
