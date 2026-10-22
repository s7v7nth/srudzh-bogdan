import SwiftUI
import SwiftData
import LedgerCore

/// Период отчётов в целых календарных месяцах: «1 мес.» это текущий месяц.
enum ReportPeriod: Int, CaseIterable, Identifiable {
    case month = 1, quarter = 3, half = 6, year = 12, all = 0
    var id: Int { rawValue }
    var short: LocalizedStringKey {
        switch self { case .month: "rep.p.month"; case .quarter: "rep.p.quarter"; case .half: "rep.p.half"; case .year: "rep.p.year"; case .all: "rep.p.all" }
    }

    /// Период от начала нужного месяца до конца текущего. `earliest` нужен для «всё время».
    func range(now: Date, earliest: Date?, minMonths: Int = 1) -> DateInterval {
        let cal = Calendar.current
        let thisMonth = Reports.monthStart(now)
        let end = cal.date(byAdding: .month, value: 1, to: thisMonth)!
        var n = max(rawValue, minMonths)
        if self == .all {
            let first = Reports.monthStart(earliest ?? now)
            n = max((cal.dateComponents([.month], from: first, to: thisMonth).month ?? 0) + 1, minMonths)
        }
        let start = cal.date(byAdding: .month, value: -(n - 1), to: thisMonth)!
        return DateInterval(start: min(start, thisMonth), end: end)
    }

    /// Предыдущий период той же длины в месяцах. Для «всё время» сравнивать не с чем.
    func previous(of r: DateInterval) -> DateInterval? {
        guard self != .all else { return nil }
        let cal = Calendar.current
        let n = cal.dateComponents([.month], from: r.start, to: r.end).month ?? rawValue
        guard let s = cal.date(byAdding: .month, value: -n, to: r.start) else { return nil }
        return DateInterval(start: s, end: r.start)
    }
}

/// Одна операция для отчёта вместе с данными для подписей.
struct ReportRow {
    var tx: ReportTx
    var catKey: String
}

/// Всё, что нужно экранам отчётов: операции в основной валюте и справочники. Строится один раз на показ.
struct ReportData {
    let base: String
    let period: ReportPeriod
    let range: DateInterval
    let previousRange: DateInterval?
    /// Доходы и расходы без переводов и начальных остатков.
    let flows: [ReportTx]
    let current: [ReportTx]
    let previous: [ReportTx]
    let categories: [String: Category]      // по uuid верхней категории
    let uncategorized: String
    let noPayee: String

    var income: Decimal { current.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount } }
    var expense: Decimal { current.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount } }
    var prevExpense: Decimal { previous.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount } }
    var prevIncome: Decimal { previous.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount } }
    var net: Decimal { income - expense }
    var savingsRate: Double? { Reports.savingsRate(income: income, expense: expense) }

    func catKey(_ t: ReportTx) -> String { t.categoryID?.uuidString ?? "none" }
    func catName(_ key: String) -> String { categories[key]?.name ?? uncategorized }

    enum Dim: Int, CaseIterable, Identifiable {
        case category, payee, account
        var id: Int { rawValue }
        var title: LocalizedStringKey { switch self { case .category: "rep.dim.category"; case .payee: "rep.dim.payee"; case .account: "rep.dim.account" } }
    }

    func slices(_ dim: Dim, sign: Int, previous prev: Bool = false) -> [Slice] {
        let list = prev ? previous : current
        return Reports.breakdown(list, sign: sign) { t in
            switch dim {
            case .category: catKey(t)
            case .payee: t.payee.trimmingCharacters(in: .whitespaces).isEmpty ? noPayee : t.payee
            case .account: t.account
            }
        }
    }

    func label(_ dim: Dim, _ key: String) -> String { dim == .category ? catName(key) : key }
}

/// Сборка данных отчётов из базы.
@MainActor enum ReportBuilder {
    /// Названия начального остатка на всех языках приложения: запись могли создать до смены языка.
    static func openingPayees() -> Set<String> {
        var out: Set<String> = ["Opening balance"]
        for lang in ["en", "ru"] {
            guard let path = Bundle.main.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: path) else { continue }
            for key in ["account.openingPayee", "onb.openingBalance"] { out.insert(b.localizedString(forKey: key, value: nil, table: nil)) }
        }
        out.insert(String(localized: "account.openingPayee")); out.insert(String(localized: "onb.openingBalance"))
        return out
    }

    static func build(period: ReportPeriod, transactions: [LedgerTransaction], categories: [Category], rates: RatesStore,
                      minMonths: Int = 1, now: Date = .now) -> ReportData {
        let base = rates.base
        let opening = openingPayees()
        let counted = transactions.filter { ($0.account?.excludedFromNetWorth ?? true) == false }
        let earliest = counted.map(\.date).min()
        let range = period.range(now: now, earliest: earliest, minMonths: minMonths)
        let prevRange = period.previous(of: range)
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.uuid.uuidString, $0) })

        var flows: [ReportTx] = []
        for t in counted where t.type != .transfer {
            if t.category == nil, opening.contains(t.payee) { continue }
            guard let v = rates.value(of: t, in: base) else { continue }
            let top = t.category.map { $0.parent ?? $0 }
            flows.append(ReportTx(amount: v, date: t.date, categoryID: top?.uuid, payee: t.payee, account: t.account?.name ?? ""))
        }
        return ReportData(base: base, period: period, range: range, previousRange: prevRange, flows: flows,
                          current: Reports.filter(flows, in: range),
                          previous: prevRange.map { Reports.filter(flows, in: $0) } ?? [],
                          categories: byID, uncategorized: String(localized: "rep.uncategorized"),
                          noPayee: String(localized: "rep.noPayee"))
    }

    /// Активы и долги на каждую дату. Прошлые точки считаются по курсам операций, а последняя (сегодня)
    /// по текущим курсам, чтобы совпадать с «Всего» на экране счетов.
    static func accountSeries(transactions: [LedgerTransaction], rates: RatesStore, at points: [Date]) -> (assets: [Decimal], debts: [Decimal]) {
        let base = rates.base
        var byAccount: [PersistentIdentifier: (code: String, base: [(date: Date, amount: Decimal)], native: [(date: Date, amount: Decimal)])] = [:]
        for t in transactions {
            guard let a = t.account, !a.excludedFromNetWorth, let v = rates.value(of: t, in: base) else { continue }
            var e = byAccount[a.persistentModelID] ?? (a.currency, [], [])
            e.base.append((t.date, v)); e.native.append((t.date, t.amount))
            byAccount[a.persistentModelID] = e
        }
        var assets = Array(repeating: Decimal(0), count: points.count)
        var debts = assets
        for (_, e) in byAccount {
            var c = Reports.cumulative(e.base, at: points)
            if let last = points.indices.last, let nativeNow = Reports.cumulative(e.native, at: [points[last]]).first,
               let v = rates.convert(nativeNow, from: e.code, to: base) { c[last] = v }
            for i in c.indices { if c[i] >= 0 { assets[i] += c[i] } else { debts[i] += c[i] } }
        }
        return (assets, debts)
    }
}

// MARK: - Общие элементы оформления отчётов

/// Карточка отчёта: тот же «тёмный премиум», что и в остальном приложении.
struct ReportCard<Content: View>: View {
    var title: LocalizedStringKey? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.app(.subheadline, .semibold)).foregroundStyle(.secondary) }
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

/// Плитка «подпись и сумма» в шапке отчёта.
struct ReportStat: View {
    let label: LocalizedStringKey
    let amount: Decimal
    let code: String
    var color: Color? = nil
    var signed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.app(.caption, .medium)).foregroundStyle(.secondary)
            MoneyText(amount: amount, code: code, signed: signed, color: color, tabular: false, weight: .bold)
                .font(.app(.headline, .bold)).minimumScaleFactor(0.7).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Рост или падение в процентах. `goodWhenDown` меняет цвет для расходов.
struct DeltaChip: View {
    let percent: Double?
    var goodWhenDown = false
    var body: some View {
        if let p = percent {
            let up = p >= 0
            let good = up != goodWhenDown
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.system(size: 10, weight: .bold))
                Text(abs(p).formatted(.percent.precision(.fractionLength(0)))).font(.app(.caption, .semibold))
            }
            .foregroundStyle(good ? Theme.income : Theme.expense)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((good ? Theme.income : Theme.expense).opacity(0.14), in: Capsule())
        }
    }
}

extension Decimal {
    var asDouble: Double { NSDecimalNumber(decimal: self).doubleValue }
    /// Короткая запись для подписей осей: 12 400 → «12,4 тыс.».
    var compact: String { asDouble.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) }
}

extension Date {
    var monthShort: String { formatted(.dateTime.month(.abbreviated)) }
}
