import SwiftUI
import SwiftData
import Charts
import LedgerCore

/// Самые крупные траты периода.
struct LargeExpensesReport: View {
    let data: ReportData

    var body: some View {
        let top = Reports.largestExpenses(data.current, limit: 10)
        let sum = top.reduce(Decimal(0)) { $0 - $1.amount }
        ScrollView {
            VStack(spacing: 14) {
                if top.isEmpty {
                    ContentUnavailableView("rep.empty", systemImage: "chart.bar", description: Text("rep.emptyHint")).padding(.top, 30)
                } else {
                    ReportCard {
                        Text("rep.big.share").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary)
                        Text((data.expense > 0 ? (sum / data.expense).asDouble : 0).formatted(.percent.precision(.fractionLength(0))))
                            .font(.app(.title2, .heavy))
                        Text(fmt("rep.big.hint", top.count, MoneyText.plain(sum, code: data.base))).font(.app(.footnote)).foregroundStyle(.secondary)
                    }
                    ReportCard {
                        ForEach(Array(top.enumerated()), id: \.offset) { _, t in
                            HStack(spacing: 10) {
                                CategoryBadge(category: data.categories[data.catKey(t)], size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.payee.trimmingCharacters(in: .whitespaces).isEmpty ? data.noPayee : t.payee).font(.app(.body, .medium)).lineLimit(1)
                                    Text(t.date.shortDay).font(.app(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                MoneyText(amount: t.amount, code: data.base).font(.app(.body, .semibold))
                            }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .themedScreen()
        .navigationTitle("rep.big.title").navigationBarTitleDisplayMode(.inline)
    }
}

/// Когда ты тратишь больше всего: по дням недели.
struct WeekdayReport: View {
    let data: ReportData

    var body: some View {
        let cal = Calendar.current
        let by = Reports.expenseByWeekday(data.current)
        // Дни по порядку недели в текущей локали (в России с понедельника).
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        let top = by.max { $0.value < $1.value }
        ScrollView {
            VStack(spacing: 14) {
                if by.isEmpty {
                    ContentUnavailableView("rep.empty", systemImage: "calendar", description: Text("rep.emptyHint")).padding(.top, 30)
                } else {
                    if let top, data.expense > 0 {
                        ReportCard {
                            Text("rep.wd.top").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary)
                            Text(cal.weekdaySymbols[top.key - 1].capitalized).font(.app(.title2, .heavy))
                            Text(fmt("rep.wd.hint", Int(((top.value / data.expense).asDouble * 100).rounded()), MoneyText.plain(top.value, code: data.base)))
                                .font(.app(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                    ReportCard(title: "rep.wd.chart") {
                        Chart(order, id: \.self) { w in
                            BarMark(x: .value("d", cal.shortWeekdaySymbols[w - 1]), y: .value("v", (by[w] ?? 0).asDouble), width: .ratio(0.65))
                                .foregroundStyle(w == top?.key ? Theme.expense : Theme.expense.opacity(0.4)).cornerRadius(5)
                        }
                        .chartXScale(domain: order.map { cal.shortWeekdaySymbols[$0 - 1] })
                        .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.app(.caption2)) } }
                        .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine().foregroundStyle(.white.opacity(0.06)); AxisValueLabel { if let d = v.as(Double.self) { Text(Decimal(d).compact).font(.app(.caption2)) } } } }
                        .frame(height: 200)
                        .chartReveal()
                    }
                }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .themedScreen()
        .navigationTitle("rep.wd.title").navigationBarTitleDisplayMode(.inline)
    }
}

/// Регулярные платежи и подписки: сколько они стоят в месяц и в год.
struct SubscriptionsReport: View {
    let data: ReportData
    @Environment(RatesStore.self) private var rates
    @Query(filter: #Predicate<RecurringTransaction> { $0.active }) private var recurring: [RecurringTransaction]

    private struct Item: Identifiable {
        let id: PersistentIdentifier
        let name: String
        let category: Category?
        let monthly: Decimal
        let repeatType: Int
    }

    private var items: [Item] {
        recurring.filter { $0.type == .expense }.compactMap { r in
            guard let acc = r.account, let v = rates.convert(r.amount, from: acc.currency, to: data.base) else { return nil }
            let name = r.payee.isEmpty ? (r.category?.name ?? data.noPayee) : r.payee
            return Item(id: r.persistentModelID, name: name, category: r.category,
                        monthly: Reports.monthlyCost(amount: v, type: r.repeatType, duration: r.duration), repeatType: r.repeatType)
        }.sorted { $0.monthly > $1.monthly }
    }

    var body: some View {
        let list = items
        let month = list.reduce(Decimal(0)) { $0 + $1.monthly }
        let months = Decimal(max(1, Reports.months(from: data.range.start, to: data.range.end.addingTimeInterval(-1)).count))
        let avgIncome = data.income / months
        ScrollView {
            VStack(spacing: 14) {
                if list.isEmpty {
                    ContentUnavailableView("rep.sub.none", systemImage: "repeat", description: Text("rep.sub.noneHint")).padding(.top, 30)
                } else {
                    ReportCard {
                        HStack {
                            ReportStat(label: "rep.sub.perMonth", amount: month, code: data.base, color: Theme.expense)
                            ReportStat(label: "rep.sub.perYear", amount: month * 12, code: data.base, color: Theme.expense)
                        }
                        if avgIncome > 0 {
                            Text(fmt("rep.sub.ofIncome", Int(((month / avgIncome).asDouble * 100).rounded()))).font(.app(.subheadline))
                        }
                    }
                    ReportCard {
                        ForEach(list) { i in
                            HStack(spacing: 10) {
                                CategoryBadge(category: i.category, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(i.name).font(.app(.body, .medium)).lineLimit(1)
                                    HStack(spacing: 4) {
                                        MoneyText(amount: i.monthly * 12, code: data.base); Text("rep.sub.yearShort")
                                    }.font(.app(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 3) { MoneyText(amount: i.monthly, code: data.base).font(.app(.body, .semibold)); Text("rep.sub.monthShort").font(.app(.caption)).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .themedScreen()
        .navigationTitle("rep.sub.title").navigationBarTitleDisplayMode(.inline)
    }
}

/// Кредитные линии: долг, загрузка лимита, проценты за год и ближайший срок без процентов.
struct CreditsReport: View {
    let base: String
    @Environment(RatesStore.self) private var rates
    @Query(sort: \Account.sortID) private var accounts: [Account]

    var body: some View {
        let credits = accounts.filter(\.isCredit)
        let debtBase = credits.reduce(Decimal(0)) { $0 + (rates.convert(max(-balance(of: $1), 0), from: $1.currency, to: base) ?? 0) }
        ScrollView {
            VStack(spacing: 14) {
                if credits.isEmpty {
                    ContentUnavailableView("rep.cr.none", systemImage: "creditcard", description: Text("rep.cr.noneHint")).padding(.top, 30)
                } else {
                    ReportCard {
                        Text("rep.cr.totalDebt").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary)
                        MoneyText(amount: debtBase, code: base, color: debtBase > 0 ? Theme.expense : nil, tabular: false, weight: .heavy).font(.app(.title, .heavy))
                    }
                    ForEach(credits) { card($0) }
                }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .themedScreen()
        .navigationTitle("rep.cr.title").navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ a: Account) -> some View {
        let debt = max(-balance(of: a), 0)
        let terms = a.terms
        let util = CreditLine.utilization(debt: debt, limit: terms.limit).asDouble
        let grace = CreditLine.graceStatus(entries: a.entries, today: .now, terms: terms)
        let from = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        let interest = CreditLine.interestEstimate(entries: a.entries, from: from, through: .now, terms: terms)
        let minPay = CreditLine.minimumPayment(debt: debt, percent: terms.minPercent, floor: terms.minFloor)
        return ReportCard {
            HStack {
                Text(a.name).font(.app(.headline)); Spacer()
                MoneyText(amount: debt, code: a.currency, color: debt > 0 ? Theme.expense : nil).font(.app(.headline, .bold))
            }
            if terms.limit > 0 {
                ProgressView(value: min(util, 1)).progressViewStyle(CapsuleBar(tint: BudgetState(ratio: util / 0.9).tint))
                HStack(spacing: 4) {
                    Text(util.formatted(.percent.precision(.fractionLength(0)))); Text("rep.cr.ofLimit"); MoneyText(amount: terms.limit, code: a.currency)
                }.font(.app(.caption)).foregroundStyle(.secondary)
            }
            Divider().overlay(.white.opacity(0.06))
            line("rep.cr.interest", interest, a.currency, tint: interest > 0 ? Theme.expense : nil)
            if grace.interestBearing > 0 { line("rep.cr.bearing", grace.interestBearing, a.currency, tint: Theme.expense) }
            if let d = grace.nextDeadline, grace.amountDue > 0 {
                HStack { Text(fmt("rep.cr.free", d.shortDay)).font(.app(.subheadline)); Spacer(); MoneyText(amount: grace.amountDue, code: a.currency).font(.app(.subheadline, .semibold)) }
            }
            if minPay > 0 { line("rep.cr.minPay", minPay, a.currency, tint: nil) }
        }
    }

    private func line(_ key: LocalizedStringKey, _ v: Decimal, _ code: String, tint: Color?) -> some View {
        HStack { Text(key).font(.app(.subheadline)); Spacer(); MoneyText(amount: v, code: code, color: tint).font(.app(.subheadline, .semibold)) }
    }
}
