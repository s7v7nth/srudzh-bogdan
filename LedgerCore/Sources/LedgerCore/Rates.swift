import Foundation

public extension Money {
    /// Сколько знаков после запятой у валюты (BYN 2, JPY 0). Берётся из системных данных.
    /// Ответ запоминается: создавать NumberFormatter на каждую операцию дорого.
    static func fractionDigits(_ code: String) -> Int {
        digitsLock.lock(); defer { digitsLock.unlock() }
        if let d = digitsCache[code] { return d }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .currency
        f.currencyCode = code
        digitsCache[code] = f.maximumFractionDigits
        return f.maximumFractionDigits
    }
}

private let digitsLock = NSLock()
private nonisolated(unsafe) var digitsCache: [String: Int] = [:]

/// Таблица курсов: сколько единиц валюты приходится на 1 доллар США. Коды в верхнем регистре.
public struct RateTable: Equatable {
    public var perUSD: [String: Decimal]
    public var date: Date?

    public init(perUSD: [String: Decimal] = [:], date: Date? = nil) {
        self.perUSD = perUSD; self.date = date
    }

    /// Курс «1 единица from = X единиц to». nil, если какой-то из валют нет в таблице.
    public func rate(from: String, to: String) -> Decimal? {
        if from == to { return 1 }
        guard let f = perUSD[from], let t = perUSD[to], f > 0 else { return nil }
        return t / f
    }

    public func convert(_ amount: Decimal, from: String, to: String) -> Decimal? {
        rate(from: from, to: to).map { Money.convert(amount, rate: $0, scale: Money.fractionDigits(to)) }
    }

    // MARK: Разбор ответов сервисов

    /// fawazahmed0/currency-api: {"date":"2026-10-18","usd":{"rub":84.12,...}}
    public static func parseFawaz(_ data: Data) -> RateTable? {
        struct Payload: Decodable { var date: String?; var usd: [String: Lenient] }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let table = RateTable(perUSD: clean(p.usd), date: p.date.flatMap(isoDay))
        return table.perUSD.isEmpty ? nil : table
    }

    /// open.er-api.com: {"result":"success","time_last_update_unix":...,"rates":{"RUB":83.2,...}}
    public static func parseERAPI(_ data: Data) -> RateTable? {
        struct Payload: Decodable { var result: String?; var time_last_update_unix: Double?; var rates: [String: Lenient]? }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data), p.result == "success", let rates = p.rates else { return nil }
        let table = RateTable(perUSD: clean(rates), date: p.time_last_update_unix.map { Date(timeIntervalSince1970: $0) })
        return table.perUSD.isEmpty ? nil : table
    }

    /// Число читается сразу как Decimal, без промежуточного Double (иначе появляются хвосты вроде ...01).
    private struct Lenient: Decodable {
        var value: Decimal?
        init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(Decimal.self) }
    }

    private static func clean(_ raw: [String: Lenient]) -> [String: Decimal] {
        var out: [String: Decimal] = [:]
        for (k, v) in raw { if let d = v.value, d > 0 { out[k.uppercased()] = d } }
        return out
    }

    private static func isoDay(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
