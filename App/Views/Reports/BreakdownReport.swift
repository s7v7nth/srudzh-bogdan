import SwiftUI
import Charts
import LedgerCore

/// Куда уходят деньги (sign = -1) или откуда приходят (sign = 1): кольцо и список с долями и сравнением с прошлым периодом.
struct BreakdownReport: View {
    let data: ReportData
    let sign: Int
    @State private var dim: ReportData.Dim = .category

    private static let palette: [Color] = [
        Theme.hex(0xc5f56b), Theme.hex(0x7aa7ff), Theme.hex(0xffc15a), Theme.hex(0xff7a70),
        Theme.hex(0xb48cff), Theme.hex(0x4ade9a), Theme.hex(0xff8fc7), Theme.hex(0x5fd3e0)]

    private var slices: [Slice] { data.slices(dim, sign: sign) }
    private var total: Decimal { slices.reduce(0) { $0 + $1.amount } }
    private var changes: [String: Change] {
        Dictionary(uniqueKeysWithValues: Reports.compare(current: slices, previous: data.slices(dim, sign: sign, previous: true)).map { ($0.key, $0) })
    }

    private func color(_ i: Int, _ s: Slice) -> Color {
        if dim == .category, let c = data.categories[s.key] { return Color.category(c.colorName) }
        return Self.palette[i % Self.palette.count]
    }

    var body: some View {
        let list = slices
        let ch = changes
        ScrollView {
            VStack(spacing: 14) {
                Picker("rep.dim", selection: $dim) { ForEach(ReportData.Dim.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                if list.isEmpty {
                    ContentUnavailableView("rep.empty", systemImage: "chart.pie", description: Text("rep.emptyHint")).padding(.top, 30)
                } else {
                    ReportCard {
                        ZStack {
                            Chart(Array(list.prefix(8).enumerated()), id: \.offset) { i, s in
                                SectorMark(angle: .value("v", s.amount.asDouble), innerRadius: .ratio(0.64), angularInset: 1.5)
                                    .cornerRadius(4).foregroundStyle(color(i, s))
                            }
                            .donutReveal(trigger: dim)
                            VStack(spacing: 2) {
                                Text(sign < 0 ? "rep.bd.spent" : "rep.bd.earned").font(.app(.caption)).foregroundStyle(.secondary)
                                MoneyText(amount: total, code: data.base, tabular: false, weight: .heavy).font(.app(.title3, .heavy))
                            }
                        }.frame(height: 230)
                    }
                    ReportCard {
                        ForEach(Array(list.enumerated()), id: \.element.key) { i, s in
                            HStack(spacing: 10) {
                                if dim == .category { CategoryBadge(category: data.categories[s.key], size: 32) }
                                else { Circle().fill(color(i, s)).frame(width: 12, height: 12).padding(.horizontal, 10) }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(data.label(dim, s.key)).font(.app(.body, .medium)).lineLimit(1)
                                        DeltaChip(percent: ch[s.key]?.percent, goodWhenDown: sign < 0)
                                    }
                                    ProgressView(value: s.share).progressViewStyle(CapsuleBar(tint: color(i, s)))
                                }
                                VStack(alignment: .trailing, spacing: 2) {
                                    MoneyText(amount: s.amount, code: data.base).font(.app(.body, .semibold))
                                    Text(s.share.formatted(.percent.precision(.fractionLength(0)))).font(.app(.caption)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .themedScreen()
        .navigationTitle(sign < 0 ? "rep.bd.titleExpense" : "rep.bd.titleIncome").navigationBarTitleDisplayMode(.inline)
    }
}
