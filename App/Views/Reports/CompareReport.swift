import SwiftUI
import LedgerCore

/// Как изменились расходы по категориям по сравнению с предыдущим периодом такой же длины.
struct CompareReport: View {
    let data: ReportData

    private var changes: [Change] {
        Reports.compare(current: data.slices(.category, sign: -1), previous: data.slices(.category, sign: -1, previous: true))
    }

    private func span(_ r: DateInterval) -> String {
        let f = Date.FormatStyle().month(.abbreviated).year()
        let last = r.end.addingTimeInterval(-1)
        return Reports.monthStart(r.start) == Reports.monthStart(last) ? r.start.formatted(f) : "\(r.start.formatted(f)) – \(last.formatted(f))"
    }

    var body: some View {
        let all = changes
        let up = all.filter { $0.delta > 0 }
        let down = all.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }
        ScrollView {
            VStack(spacing: 14) {
                if data.previousRange == nil || data.previous.isEmpty {
                    ContentUnavailableView("rep.cmp.none", systemImage: "arrow.left.arrow.right", description: Text("rep.cmp.noneHint")).padding(.top, 30)
                } else {
                    ReportCard {
                        HStack(spacing: 8) {
                            Text("rep.cmp.total").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary)
                            DeltaChip(percent: data.prevExpense > 0 ? ((data.expense - data.prevExpense) / data.prevExpense).asDouble : nil, goodWhenDown: true)
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(span(data.range)).font(.app(.caption)).foregroundStyle(.secondary)
                                MoneyText(amount: data.expense, code: data.base, tabular: false, weight: .bold).font(.app(.title3, .bold))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(data.previousRange.map(span) ?? "").font(.app(.caption)).foregroundStyle(.secondary)
                                MoneyText(amount: data.prevExpense, code: data.base, tabular: false, weight: .bold).font(.app(.title3, .bold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !up.isEmpty { section("rep.cmp.up", up, tint: Theme.expense) }
                    if !down.isEmpty { section("rep.cmp.down", down, tint: Theme.income) }
                }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .themedScreen()
        .navigationTitle("rep.cmp.title").navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: LocalizedStringKey, _ list: [Change], tint: Color) -> some View {
        ReportCard(title: title) {
            ForEach(list, id: \.key) { c in
                HStack(spacing: 10) {
                    CategoryBadge(category: data.categories[c.key], size: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(data.catName(c.key)).font(.app(.body, .medium)).lineLimit(1)
                            DeltaChip(percent: c.percent, goodWhenDown: true)
                        }
                        HStack(spacing: 4) {
                            MoneyText(amount: c.previous, code: data.base); Text("→"); MoneyText(amount: c.current, code: data.base)
                        }.font(.app(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    MoneyText(amount: c.delta, code: data.base, signed: true, color: tint).font(.app(.body, .semibold))
                }
            }
        }
    }
}
