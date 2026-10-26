import SwiftUI
import SwiftData
import Charts
import LedgerCore

/// Вкладка «Отчёты»: выбор периода, короткие выводы и карточки отчётов с мини-превью.
struct ReportsView: View {
    @Environment(RatesStore.self) private var rates
    @Query private var transactions: [LedgerTransaction]
    @Query private var categories: [Category]
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<RecurringTransaction> { $0.active }) private var recurring: [RecurringTransaction]
    @AppStorage("reportsPeriod") private var periodRaw = ReportPeriod.quarter.rawValue

    private var period: ReportPeriod { ReportPeriod(rawValue: periodRaw) ?? .quarter }

    var body: some View {
        let data = ReportBuilder.build(period: period, transactions: transactions, categories: categories, rates: rates)
        // Для капитала нужна история подлиннее, чем один месяц.
        let nwRange = period.range(now: .now, earliest: transactions.map(\.date).min(), minMonths: 6)
        let nw = NetWorthSeries.make(range: nwRange, transactions: transactions, rates: rates)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("rep.period", selection: $periodRaw) {
                        ForEach(ReportPeriod.allCases) { Text($0.short).tag($0.rawValue) }
                    }.pickerStyle(.segmented)

                    if data.flows.isEmpty && transactions.isEmpty {
                        ContentUnavailableView("rep.empty", systemImage: "chart.xyaxis.line", description: Text("rep.emptyHint")).padding(.top, 40)
                    } else {
                        insights(data)
                        link(NetWorthReport(series: nw, base: data.base)) { netWorthCard(nw, data.base) }
                        link(IncomeExpenseReport(data: data)) { incomeExpenseCard(data) }
                        link(BreakdownReport(data: data, sign: -1)) { spendingCard(data) }
                        link(ForecastReport(base: data.base, flows: data.flows)) { forecastCard(data) }
                        moreReports(data)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 100)
            }
            .buttonStyle(.plain)
            .themedScreen()
            .navigationTitle("tab.reports")
        }
    }

    private func link<D: View, L: View>(_ dest: D, @ViewBuilder label: () -> L) -> some View {
        NavigationLink { dest } label: { label() }
    }

    // MARK: Выводы

    private struct Insight: Identifiable { let id = UUID(); let icon: String; let tint: Color; let text: String }

    @ViewBuilder private func insights(_ d: ReportData) -> some View {
        let list = makeInsights(d)
        if !list.isEmpty {
            ReportCard {
                ForEach(list) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: i.icon).foregroundStyle(i.tint).frame(width: 22)
                        Text(i.text).font(.app(.subheadline, .medium)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func makeInsights(_ d: ReportData) -> [Insight] {
        var out: [Insight] = []
        if d.income > 0 || d.expense > 0 {
            if d.net >= 0, let r = d.savingsRate, d.income > 0 {
                out.append(Insight(icon: "leaf.fill", tint: Theme.income,
                                   text: fmt("rep.in.saved", Int((r * 100).rounded()), MoneyText.plain(d.net, code: d.base))))
            } else if d.net < 0 {
                out.append(Insight(icon: "exclamationmark.triangle.fill", tint: Theme.expense,
                                   text: fmt("rep.in.deficit", MoneyText.plain(-d.net, code: d.base))))
            }
        }
        if d.prevExpense > 0, d.expense > 0 {
            let p = ((d.expense - d.prevExpense) / d.prevExpense).asDouble
            if abs(p) >= 0.05 {
                out.append(Insight(icon: p > 0 ? "arrow.up.right" : "arrow.down.right", tint: p > 0 ? Theme.expense : Theme.income,
                                   text: fmt(p > 0 ? "rep.in.spendUp" : "rep.in.spendDown", Int((abs(p) * 100).rounded()))))
            }
        }
        if let top = d.slices(.category, sign: -1).first, d.expense > 0 {
            out.append(Insight(icon: "chart.pie.fill", tint: Theme.warn,
                               text: fmt("rep.in.top", d.catName(top.key), Int((top.share * 100).rounded()))))
        }
        return out
    }

    // MARK: Остальные отчёты

    private func moreReports(_ d: ReportData) -> some View {
        ReportCard(title: "rep.more") {
            moreRow(CompareReport(data: d), "rep.cmp.title", "arrow.left.arrow.right", Theme.transfer)
            moreRow(BudgetsReport(), "rep.bud.title", "gauge.with.dots.needle.67percent", Theme.income)
            moreRow(LargeExpensesReport(data: d), "rep.big.title", "arrow.up.right.circle", Theme.expense)
            moreRow(SubscriptionsReport(data: d), "rep.sub.title", "repeat", Theme.warn)
            moreRow(CreditsReport(base: d.base), "rep.cr.title", "creditcard.and.123", Theme.expense)
            moreRow(WeekdayReport(data: d), "rep.wd.title", "calendar", Theme.transfer, last: true)
        }
    }

    private func moreRow<D: View>(_ dest: D, _ title: LocalizedStringKey, _ icon: String, _ tint: Color, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            NavigationLink { dest } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                        .frame(width: 32, height: 32).background(tint.opacity(0.16), in: Circle())
                    Text(title).font(.app(.body, .medium))
                    Spacer()
                    Image(systemName: "chevron.right").font(.app(.footnote, .semibold)).foregroundStyle(.tertiary)
                }.padding(.vertical, 8).contentShape(Rectangle())
            }
            if !last { Divider().overlay(.white.opacity(0.06)) }
        }
    }

    // MARK: Карточки

    private func header(_ title: LocalizedStringKey, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.app(.subheadline, .semibold)).foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right").font(.app(.footnote, .semibold)).foregroundStyle(.tertiary)
        }
    }

    private func netWorthCard(_ s: NetWorthSeries, _ base: String) -> some View {
        ReportCard {
            header("rep.nw.title", "banknote")
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    MoneyText(amount: s.now, code: base, tabular: false, weight: .heavy).font(.app(.title2, .heavy))
                    HStack(spacing: 6) {
                        MoneyText(amount: s.change, code: base, colored: true, signed: true).font(.app(.footnote, .semibold))
                        DeltaChip(percent: s.changePercent)
                    }
                }
                Spacer()
                Chart(Array(zip(s.dates, s.total).enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("d", p.0), y: .value("v", p.1.asDouble)).foregroundStyle(Theme.brand)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)).interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: false))
                .frame(width: 120, height: 50)
                .chartReveal(trigger: periodRaw)
            }
        }
    }

    private func incomeExpenseCard(_ d: ReportData) -> some View {
        ReportCard {
            header("rep.ie.title", "arrow.up.arrow.down")
            HStack {
                ReportStat(label: "rep.ie.income", amount: d.income, code: d.base, color: Theme.income)
                ReportStat(label: "rep.ie.expense", amount: d.expense, code: d.base, color: Theme.expense)
                ReportStat(label: "rep.ie.net", amount: d.net, code: d.base, color: d.net < 0 ? Theme.expense : nil, signed: true)
            }
        }
    }

    private func spendingCard(_ d: ReportData) -> some View {
        let top = Array(d.slices(.category, sign: -1).prefix(6))
        return ReportCard {
            header("rep.bd.titleExpense", "chart.pie")
            HStack(spacing: 8) {
                MoneyText(amount: d.expense, code: d.base, tabular: false, weight: .heavy).font(.app(.title2, .heavy))
                DeltaChip(percent: d.prevExpense > 0 ? ((d.expense - d.prevExpense) / d.prevExpense).asDouble : nil, goodWhenDown: true)
            }
            if !top.isEmpty {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(top, id: \.key) { s in
                            Capsule().fill(d.categories[s.key].map { Color.category($0.colorName) } ?? .gray)
                                .frame(width: max(6, g.size.width * s.share - 2))
                        }
                        Spacer(minLength: 0)
                    }
                }.frame(height: 10)
                Text(top.prefix(3).map { d.catName($0.key) }.joined(separator: " · ")).font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func forecastCard(_ d: ReportData) -> some View {
        let pts = ReportBuilder.forecast(accounts: accounts, recurring: recurring, flows: d.flows, rates: rates, weeks: 13)
        let low = Reports.lowPoint(pts, habit: true)
        return ReportCard {
            header("rep.fc.title", "sparkles")
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("rep.fc.in3").font(.app(.caption, .medium)).foregroundStyle(.secondary)
                    MoneyText(amount: pts.last?.habit ?? 0, code: d.base, colored: (pts.last?.habit ?? 0) < 0, tabular: false, weight: .heavy)
                        .font(.app(.title2, .heavy))
                }
                Spacer()
                if let neg = low?.firstNegative {
                    Label(neg.shortDay, systemImage: "exclamationmark.triangle.fill").font(.app(.caption, .semibold)).foregroundStyle(Theme.expense)
                }
            }
        }
    }
}
