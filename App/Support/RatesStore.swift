import Foundation
import Observation
import LedgerCore

/// Основная валюта и курсы. Курсы берутся из интернета раз в сутки; без сети работают последние сохранённые.
/// В сеть уходят только коды валют и дата, суммы и операции не отправляются.
@MainActor @Observable final class RatesStore {
    private(set) var table: RateTable
    private(set) var lastUpdated: Date?
    var isRefreshing = false
    var lastError = false

    var base: String {
        didSet { UserDefaults.standard.set(base, forKey: Keys.base) }
    }

    private enum Keys {
        static let base = "baseCurrency", table = "rates.table", date = "rates.date", updated = "rates.updated"
    }

    private static let primary = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@%@/v1/currencies/usd.json"
    private static let fallback = "https://open.er-api.com/v6/latest/USD"
    private var datedCache: [String: RateTable] = [:]

    init() {
        let ud = UserDefaults.standard
        base = ud.string(forKey: Keys.base) ?? ""
        if let saved = ud.dictionary(forKey: Keys.table) as? [String: String], !saved.isEmpty {
            table = RateTable(perUSD: saved.compactMapValues { Decimal(string: $0) },
                              date: ud.object(forKey: Keys.date) as? Date)
        } else if let url = Bundle.main.url(forResource: "rates-seed", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let seed = RateTable.parseFawaz(data) {
            table = seed
        } else {
            table = RateTable()
        }
        lastUpdated = ud.object(forKey: Keys.updated) as? Date
    }

    // MARK: Пересчёт

    func rate(_ from: String, _ to: String) -> Decimal? { table.rate(from: from, to: to) }

    func convert(_ amount: Decimal, from: String, to: String) -> Decimal? { table.convert(amount, from: from, to: to) }

    /// Курс операции в валюту `code`: сохранённый на момент операции, если он записан для этой валюты, иначе текущий.
    func rate(of tx: LedgerTransaction, to code: String) -> Decimal? {
        if !tx.baseCode.isEmpty, tx.baseCode == code { return tx.rateToBase }
        return rate(tx.currency, code)
    }

    /// Сумма операции в валюте `code` по курсу операции. nil, если курса нет.
    func value(of tx: LedgerTransaction, in code: String) -> Decimal? {
        rate(of: tx, to: code).map { Money.convert(tx.amount, rate: $0, scale: Money.fractionDigits(code)) }
    }

    /// Записывает в операцию текущий курс её валюты к основной.
    func stamp(_ tx: LedgerTransaction) {
        guard !base.isEmpty, let r = rate(tx.currency, base) else { return }
        tx.rateToBase = r; tx.baseCode = base
    }

    /// Для операций задним числом подтягивает курс на их дату. Без сети остаётся текущий курс.
    func stampHistorical(_ txs: [LedgerTransaction], on date: Date) async {
        guard !base.isEmpty, date < .now, !Calendar.current.isDateInToday(date), let t = await table(on: date) else { return }
        for tx in txs { if let r = t.rate(from: tx.currency, to: base) { tx.rateToBase = r; tx.baseCode = base } }
    }

    // MARK: Загрузка

    /// Обновляет курсы, если они старше 12 часов.
    func refreshIfNeeded() async {
        if let last = lastUpdated, Date.now.timeIntervalSince(last) < 12 * 3600 { return }
        await refresh()
    }

    func refresh() async {
        isRefreshing = true; defer { isRefreshing = false }
        var loaded = await load(String(format: Self.primary, "latest"), parse: RateTable.parseFawaz)
        if loaded == nil { loaded = await load(Self.fallback, parse: RateTable.parseERAPI) }
        if let t = loaded {
            table = t; lastUpdated = .now; lastError = false
            persist()
        } else {
            lastError = true
        }
    }

    /// Курсы на конкретную дату (для операций задним числом). nil, если сервис недоступен или даты нет.
    func table(on date: Date) async -> RateTable? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let key = f.string(from: date)
        if let cached = datedCache[key] { return cached }
        guard let t = await load(String(format: Self.primary, key), parse: RateTable.parseFawaz) else { return nil }
        datedCache[key] = t
        return t
    }

    private func load(_ urlString: String, parse: (Data) -> RateTable?) async -> RateTable? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    private func persist() {
        let ud = UserDefaults.standard
        ud.set(table.perUSD.mapValues { "\($0)" }, forKey: Keys.table)
        ud.set(table.date, forKey: Keys.date)
        ud.set(lastUpdated, forKey: Keys.updated)
    }
}
