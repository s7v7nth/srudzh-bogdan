import SwiftUI
import SwiftData
import Charts
import LedgerCore

/// Капитал по месяцам: активы (плюс) и долги (минус) в основной валюте.
struct NetWorthSeries {
    let dates: [Date]
    let assets: [Decimal]
    let debts: [Decimal]
    var total: [Decimal] { zip(assets, debts).map { $0 + $1 } }
    var now: Decimal { total.last ?? 0 }
    var change: Decimal { now - (total.first ?? 0) }
    var changePercent: Double? {
        guard let f = total.first, f > 0 else { return nil }
        return (change / f).asDouble
    }

    /// Точки: начало периода и конец каждого месяца (последняя точка это «сейчас»).
    @MainActor static func make(range: DateInterval, transactions: [LedgerTransaction], rates: RatesStore, now: Date = .now) -> NetWorthSeries {
        let cal = Calendar.current
        var pts: [Date] = [range.start.addingTimeInterval(-1)]
        for m in Reports.months(from: range.start, to: range.end.addingTimeInterval(-1)) {
            let end = (cal.date(byAdding: .month, value: 1, to: m) ?? m).addingTimeInterval(-1)
            pts.append(min(end, now))
        }
        let s = ReportBuilder.accountSeries(transactions: transactions, rates: rates, at: pts)
        return NetWorthSeries(dates: pts, assets: s.assets, debts: s.debts)
    }
}

struct NetWorthReport: View {
    let series: NetWorthSeries
    let base: String
    @Environment(RatesStore.self) private var rates
    @Query(sort: \Account.sortID) private var accounts: [Account]

    private var rows: [(Account, Decimal)] {
        accounts.filter { !$0.excludedFromNetWorth }.compactMap { a in
            rates.convert(balance(of: a), from: a.currency, to: base).map { (a, $0) }
        }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ReportCard {
                    Text("rep.nw.now").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary)
                    MoneyText(amount: series.now, code: base, tabular: false, weight: .heavy).font(.app(.largeTitle, .heavy))
                    HStack(spacing: 8) {
                        MoneyText(amount: series.change, code: base, colored: true, signed: true).font(.app(.subheadline, .semibold))
                        DeltaChip(percent: series.changePercent)
                        Text("rep.nw.forPeriod").font(.app(.caption)).foregroundStyle(.secondary)
                    }
                    chart.frame(height: 180)
                }
                ReportCard(title: "rep.nw.split") {
                    HStack {
                        ReportStat(label: "rep.nw.assets", amount: series.assets.last ?? 0, code: base, color: Theme.income)
                        ReportStat(label: "rep.nw.debts", amount: series.debts.last ?? 0, code: base, color: (series.debts.last ?? 0) < 0 ? Theme.expense : nil)
                    }
                }
                ReportCard(title: "rep.nw.byAccount") {
                    ForEach(rows, id: \.0.persistentModelID) { a, v in
                        HStack {
                            Image(systemName: a.kind.icon).foregroundStyle(.secondary).frame(width: 24)
                            Text(a.name).font(.app(.body))
                            Spacer()
                            MoneyText(amount: v, code: base, colored: v < 0)
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .themedScreen()
        .navigationTitle("rep.nw.title").navigationBarTitleDisplayMode(.inline)
    }

    private var chart: some View {
        let pts = Array(zip(series.dates, series.total))
        return Chart {
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("d", p.0), y: .value("v", p.1.asDouble))
                    .foregroundStyle(LinearGradient(colors: [Theme.brand.opacity(0.35), Theme.brand.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("d", p.0), y: .value("v", p.1.asDouble))
                    .foregroundStyle(Theme.brand).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("d", p.0), y: .value("v", p.1.asDouble)).foregroundStyle(Theme.brand).symbolSize(24)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine().foregroundStyle(.white.opacity(0.06)); AxisValueLabel { if let d = v.as(Double.self) { Text(Decimal(d).compact).font(.app(.caption2)) } } } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.app(.caption2)) } }
        .chartReveal()
    }
}
