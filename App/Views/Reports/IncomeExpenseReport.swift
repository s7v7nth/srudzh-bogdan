import SwiftUI
import Charts
import LedgerCore

/// Сколько приходит и сколько уходит по месяцам, и какую часть дохода удаётся оставить.
struct IncomeExpenseReport: View {
    let data: ReportData

    private var months: [MonthTotal] { Reports.monthlyTotals(data.flows, range: data.range) }

    var body: some View {
        let ms = months
        let count = Decimal(max(ms.count, 1))
        ScrollView {
            VStack(spacing: 14) {
                ReportCard {
                    HStack {
                        ReportStat(label: "rep.ie.income", amount: data.income, code: data.base, color: Theme.income)
                        ReportStat(label: "rep.ie.expense", amount: data.expense, code: data.base, color: Theme.expense)
                        ReportStat(label: "rep.ie.net", amount: data.net, code: data.base, color: data.net < 0 ? Theme.expense : nil, signed: true)
                    }
                    if let r = data.savingsRate {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("rep.ie.savings").font(.app(.subheadline, .semibold))
                                Spacer()
                                Text(r.formatted(.percent.precision(.fractionLength(0)))).font(.app(.subheadline, .bold))
                                    .foregroundStyle(r >= 0.1 ? Theme.income : (r >= 0 ? Theme.warn : Theme.expense))
                            }
                            ProgressView(value: min(max(r, 0), 1)).progressViewStyle(CapsuleBar(tint: r >= 0.1 ? Theme.income : (r >= 0 ? Theme.warn : Theme.expense)))
                            Text(r >= 0 ? "rep.ie.savingsHint" : "rep.ie.deficitHint").font(.app(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
                ReportCard(title: "rep.ie.byMonth") {
                    Chart {
                        ForEach(ms, id: \.month) { m in
                            BarMark(x: .value("m", m.month, unit: .month), y: .value("v", m.income.asDouble), width: .ratio(0.7))
                                .foregroundStyle(Theme.income).position(by: .value("k", "i")).cornerRadius(4)
                            BarMark(x: .value("m", m.month, unit: .month), y: .value("v", m.expense.asDouble), width: .ratio(0.7))
                                .foregroundStyle(Theme.expense).position(by: .value("k", "e")).cornerRadius(4)
                        }
                    }
                    .frame(height: 200)
                    .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine().foregroundStyle(.white.opacity(0.06)); AxisValueLabel { if let d = v.as(Double.self) { Text(Decimal(d).compact).font(.app(.caption2)) } } } }
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: ms.count <= 6 ? .dateTime.month(.abbreviated) : .dateTime.month(.narrow)).font(.app(.caption2)) } }
                }
                if ms.count > 1 {
                    ReportCard(title: "rep.ie.average") {
                        HStack {
                            ReportStat(label: "rep.ie.income", amount: data.income / count, code: data.base)
                            ReportStat(label: "rep.ie.expense", amount: data.expense / count, code: data.base)
                            ReportStat(label: "rep.ie.net", amount: data.net / count, code: data.base, color: data.net < 0 ? Theme.expense : nil, signed: true)
                        }
                    }
                }
                NavigationLink { BreakdownReport(data: data, sign: 1) } label: { linkRow("rep.ie.sources", "arrow.up.circle.fill", Theme.income) }
                NavigationLink { BreakdownReport(data: data, sign: -1) } label: { linkRow("rep.ie.whereSpent", "arrow.down.circle.fill", Theme.expense) }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .buttonStyle(.plain)
        .themedScreen()
        .navigationTitle("rep.ie.title").navigationBarTitleDisplayMode(.inline)
    }

    private func linkRow(_ key: LocalizedStringKey, _ icon: String, _ tint: Color) -> some View {
        ReportCard {
            HStack {
                Image(systemName: icon).font(.title3).foregroundStyle(tint)
                Text(key).font(.app(.body, .semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.app(.footnote, .semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}
