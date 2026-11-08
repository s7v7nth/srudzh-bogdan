import SwiftUI
import SwiftData
import Charts
import LedgerCore

/// Получается ли вести бюджет: в скольких из последних периодов ты уложился, по каждому бюджету.
struct BudgetsReport: View {
    @Environment(RatesStore.self) private var rates
    @Query private var budgets: [Budget]
    @Query private var transactions: [LedgerTransaction]

    private struct Row: Identifiable {
        let id: PersistentIdentifier
        let name: String
        let currency: String
        let results: [BudgetPeriodResult]
        var score: BudgetScore { Reports.budgetScore(results) }
    }

    private var rows: [Row] {
        budgets.compactMap { b in
            let cur = b.currency.isEmpty ? rates.base : b.currency
            let periods = Reports.recentPeriods(start: b.startDate, type: b.repeatType, count: 6, today: .now)
            guard !periods.isEmpty else { return nil }
            let monitored: Set<UUID>? = b.categories.isEmpty ? nil : Set(b.categories.flatMap { $0.familyIDs })
            let txs = transactions.filter { $0.type != .transfer && $0.account != nil }.map {
                BudgetTransaction(amount: $0.amount, date: $0.date, categoryID: $0.category?.uuid, pending: $0.pending, rate: rates.rate(of: $0, to: cur) ?? 1)
            }
            let results = periods.map { p in
                BudgetPeriodResult(period: p, limit: b.amount,
                                   spent: Budgets.evaluate(limit: b.amount, period: p, transactions: txs, rules: BudgetRules(monitoredCategories: monitored)).spent)
            }
            return Row(id: b.persistentModelID, name: b.name, currency: cur, results: results)
        }
    }

    var body: some View {
        let list = rows
        let kept = list.reduce(0) { $0 + $1.score.kept }, total = list.reduce(0) { $0 + $1.score.total }
        let worst = list.filter { $0.score.kept < $0.score.total }.min { $0.score.keptShare < $1.score.keptShare }
        ScrollView {
            VStack(spacing: 14) {
                if list.isEmpty {
                    ContentUnavailableView("rep.bud.none", systemImage: "chart.pie", description: Text("rep.bud.noneHint")).padding(.top, 30)
                } else {
                    ReportCard {
                        Text("rep.bud.overall").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary)
                        Text(fmt("rep.bud.keptOf", kept, total)).font(.app(.title2, .heavy))
                        ProgressView(value: total == 0 ? 0 : Double(kept) / Double(total))
                            .progressViewStyle(CapsuleBar(tint: BudgetState(ratio: total == 0 ? 0 : 1 - Double(kept) / Double(total)).tint))
                        if let worst {
                            Text(fmt("rep.bud.worst", worst.name)).font(.app(.subheadline))
                        } else if total > 0 {
                            Text("rep.bud.allKept").font(.app(.subheadline))
                        }
                    }
                    ForEach(list) { r in card(r) }
                }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .themedScreen()
        .navigationTitle("rep.bud.title").navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ r: Row) -> some View {
        let s = r.score
        return ReportCard {
            HStack {
                Text(r.name).font(.app(.headline))
                Spacer()
                Text(fmt("rep.bud.kept", s.kept, s.total)).font(.app(.subheadline, .semibold))
                    .foregroundStyle(s.kept == s.total ? Theme.income : (s.keptShare >= 0.5 ? Theme.warn : Theme.expense))
            }
            if r.results.count > 1 {
                Chart {
                    ForEach(r.results, id: \.period.start) { p in
                        BarMark(x: .value("m", p.period.start, unit: .month), y: .value("v", min(p.ratio, 2)), width: .ratio(0.6))
                            .foregroundStyle(p.over ? Theme.expense : Theme.income).cornerRadius(4)
                    }
                    RuleMark(y: .value("limit", 1)).foregroundStyle(.white.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: 0...max(1.2, min(2, (r.results.map(\.ratio).max() ?? 1) * 1.1)))
                .chartYAxis { AxisMarks(position: .trailing, values: [0, 1]) { v in AxisValueLabel { if let d = v.as(Double.self) { Text(d == 0 ? "0" : "100%").font(.app(.caption2)) } } } }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.app(.caption2)) } }
                .frame(height: 110)
            } else if let only = r.results.first {
                ProgressView(value: min(only.ratio, 1)).progressViewStyle(CapsuleBar(tint: only.over ? Theme.expense : Theme.income))
                HStack(spacing: 4) { MoneyText(amount: only.spent, code: r.currency); Text("budgets.of"); MoneyText(amount: only.limit, code: r.currency) }
                    .font(.app(.caption)).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                if s.streak > 0 { Label(fmt("rep.bud.streak", s.streak), systemImage: "flame.fill").foregroundStyle(Theme.warn) }
                if s.averageOverrun > 0 {
                    Text(fmt("rep.bud.overrun", MoneyText.plain(s.averageOverrun, code: r.currency))).foregroundStyle(.secondary)
                }
            }.font(.app(.caption, .medium))
        }
    }
}
