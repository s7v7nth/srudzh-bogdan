import SwiftUI
import SwiftData
import Charts
import LedgerCore

extension ReportBuilder {
    /// Прогноз остатка: стартуем с капитала сегодня, добавляем платежи по расписанию и привычный темп.
    static func forecast(accounts: [Account], recurring: [RecurringTransaction], flows: [ReportTx],
                         rates: RatesStore, weeks: Int, now: Date = .now) -> [ForecastPoint] {
        let base = rates.base
        let start = accounts.filter { !$0.excludedFromNetWorth }
            .reduce(Decimal(0)) { $0 + (rates.convert(balance(of: $1), from: $1.currency, to: base) ?? 0) }
        let items: [ScheduledItem] = recurring.compactMap { r in
            guard r.active, r.type != .transfer, let acc = r.account,
                  let v = rates.convert(r.amount, from: acc.currency, to: base) else { return nil }
            return ScheduledItem(amount: v, nextDate: r.nextDate, repeatType: r.repeatType, duration: r.duration, endDate: r.endDate)
        }
        // Темп считаем по реальной длине истории (но не короче двух недель и не длиннее 90 дней).
        let first = flows.map(\.date).min() ?? now
        let span = min(90, max(14, Calendar.current.dateComponents([.day], from: first, to: now).day ?? 14))
        let daily = Reports.habitualDailyNet(flows, today: now, days: span)
        return Reports.forecast(startBalance: start, today: now, weeks: weeks, scheduled: items, dailyNet: daily)
    }
}

struct ForecastReport: View {
    let base: String
    let flows: [ReportTx]
    @Environment(RatesStore.self) private var rates
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<RecurringTransaction> { $0.active }) private var recurring: [RecurringTransaction]
    @State private var weeks = 26

    private var points: [ForecastPoint] {
        ReportBuilder.forecast(accounts: accounts, recurring: recurring, flows: flows, rates: rates, weeks: weeks)
    }

    var body: some View {
        let pts = points
        let low = Reports.lowPoint(pts, habit: true)
        ScrollView {
            VStack(spacing: 14) {
                Picker("rep.fc.horizon", selection: $weeks) {
                    Text("rep.fc.m3").tag(13); Text("rep.fc.m6").tag(26); Text("rep.fc.m12").tag(52)
                }.pickerStyle(.segmented)

                ReportCard {
                    Text("rep.fc.habit").font(.app(.subheadline, .semibold)).foregroundStyle(.secondary)
                    MoneyText(amount: pts.last?.habit ?? 0, code: base, colored: (pts.last?.habit ?? 0) < 0, tabular: false, weight: .heavy)
                        .font(.app(.title, .heavy))
                    chart(pts).frame(height: 200)
                    HStack(spacing: 14) {
                        legend(Theme.brand, "rep.fc.habitShort"); legend(Theme.transfer, "rep.fc.scheduledShort")
                    }
                }
                if let low, let neg = low.firstNegative {
                    ReportCard {
                        Label("rep.fc.warnTitle", systemImage: "exclamationmark.triangle.fill").font(.app(.headline)).foregroundStyle(Theme.expense)
                        Text(fmt("rep.fc.warnBody", neg.shortDay, MoneyText.plain(low.lowest.habit, code: base))).font(.app(.subheadline))
                    }
                } else if let low {
                    ReportCard {
                        Label("rep.fc.okTitle", systemImage: "checkmark.circle.fill").font(.app(.headline)).foregroundStyle(Theme.income)
                        if low.lowest.date == pts.first?.date {
                            Text(fmt("rep.fc.okFlat", MoneyText.plain(low.lowest.habit, code: base))).font(.app(.subheadline))
                        } else {
                            Text(fmt("rep.fc.okBody", MoneyText.plain(low.lowest.habit, code: base), low.lowest.date.shortDay)).font(.app(.subheadline))
                        }
                    }
                }
                ReportCard(title: "rep.fc.scheduledTitle") {
                    MoneyText(amount: pts.last?.scheduled ?? 0, code: base, colored: (pts.last?.scheduled ?? 0) < 0, tabular: false, weight: .bold)
                        .font(.app(.title3, .bold))
                    Text("rep.fc.explain").font(.app(.footnote)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .themedScreen()
        .navigationTitle("rep.fc.title").navigationBarTitleDisplayMode(.inline)
    }

    private func legend(_ c: Color, _ key: LocalizedStringKey) -> some View {
        HStack(spacing: 6) { Capsule().fill(c).frame(width: 14, height: 4); Text(key).font(.app(.caption)).foregroundStyle(.secondary) }
    }

    private func chart(_ pts: [ForecastPoint]) -> some View {
        Chart {
            ForEach(pts, id: \.date) { p in
                LineMark(x: .value("d", p.date), y: .value("v", p.habit.asDouble), series: .value("s", "habit"))
                    .foregroundStyle(Theme.brand).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round)).interpolationMethod(.monotone)
                LineMark(x: .value("d", p.date), y: .value("v", p.scheduled.asDouble), series: .value("s", "sched"))
                    .foregroundStyle(Theme.transfer).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4])).interpolationMethod(.monotone)
            }
            RuleMark(y: .value("zero", 0)).foregroundStyle(Theme.expense.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine().foregroundStyle(.white.opacity(0.06)); AxisValueLabel { if let d = v.as(Double.self) { Text(Decimal(d).compact).font(.app(.caption2)) } } } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.app(.caption2)) } }
    }
}
