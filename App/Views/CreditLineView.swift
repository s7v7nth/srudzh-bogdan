import SwiftUI
import SwiftData
import LedgerCore

/// Экран возобновляемой кредитной линии: долг, доступный лимит, ближайший платёж, льготный период, выписки.
struct CreditLineView: View {
    let account: Account
    @State private var showRepay = false
    @State private var showEdit = false

    var body: some View {
        let terms = account.terms
        let b = balance(of: account)
        let debt = max(-b, 0)
        let available = Balances.availableCredit(limit: terms.limit, balance: b)
        let util = CreditLine.utilization(debt: debt, limit: terms.limit)
        let period = CreditLine.period(containing: .now, statementDay: terms.statementDay)
        let dueDate = CreditLine.dueDate(statement: period.end, dueDays: terms.dueDays)
        let grace = CreditLine.graceStatus(entries: account.entries, today: .now, terms: terms)
        let interest = CreditLine.interestEstimate(entries: account.entries, from: period.start, through: .now, terms: terms)
        let history = CreditLine.statements(entries: account.entries, terms: terms, count: 12, asOf: .now)
            .filter { $0.purchases != 0 || $0.payments != 0 || $0.closingDebt != 0 }.prefix(6)
        let cur = account.currency

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("credit.debt").font(.app(.subheadline)).foregroundStyle(.secondary)
                    MoneyText(amount: debt, code: cur, color: debt > 0 ? .red : nil).font(.app(.largeTitle, .bold))
                }
                ProgressView(value: min(NSDecimalNumber(decimal: util).doubleValue, 1))
                    .progressViewStyle(CapsuleBar(tint: util > 1 ? Theme.expense : (util >= 0.8 ? Theme.warn : Theme.accent)))
                HStack {
                    Text(fmt("credit.used", NSDecimalNumber(decimal: util * 100).intValue)).font(.app(.caption)).foregroundStyle(.secondary)
                    Spacer()
                }
                LabeledMoney(label: "credit.available", amount: available, code: cur, colored: available < 0)
                LabeledMoney(label: "credit.limit", amount: terms.limit, code: cur)
                if debt > terms.limit {
                    Label("credit.overlimit", systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red)
                }
            }

            Section("credit.nextPayment") {
                LabeledContent("credit.nextStatement") { Text(period.end.shortDay) }
                if terms.dueDays > 0 { LabeledContent("credit.payBy") { Text(dueDate.shortDay) } }
                LabeledMoney(label: "credit.minPayment", amount: CreditLine.minimumPayment(debt: debt, percent: terms.minPercent, floor: terms.minFloor), code: cur)
            }

            if terms.graceDays > 0 || terms.aprPercent > 0 {
                Section {
                    if let deadline = grace.nextDeadline, grace.amountDue > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("credit.avoidInterest").font(.app(.subheadline))
                            HStack { MoneyText(amount: grace.amountDue, code: cur).font(.app(.title3, .bold)); Text(fmt("credit.byDate", deadline.shortDay)) }
                        }
                    } else if grace.interestBearing == 0 {
                        Label("credit.nothingDue", systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                    if grace.interestBearing > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("credit.interestBearing", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                            MoneyText(amount: grace.interestBearing, code: cur).font(.app(.subheadline))
                        }
                    }
                    if terms.aprPercent > 0 {
                        LabeledMoney(label: "credit.interestEstimate", amount: interest, code: cur)
                    }
                } header: { Text("credit.graceSection") } footer: { Text("credit.estimateFooter") }
            }

            Section {
                Button { showRepay = true } label: { Label("credit.repay", systemImage: "arrow.down.circle") }
                NavigationLink { ActivityView(account: account) } label: { Label("credit.operations", systemImage: "list.bullet") }
            }

            if !history.isEmpty {
                Section("credit.statements") {
                    ForEach(Array(history), id: \.period.start) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(s.period.start.shortDay) – \(s.period.end.addingTimeInterval(-86400).shortDay)").font(.app(.subheadline, .bold))
                            LabeledMoney(label: "credit.purchases", amount: s.purchases, code: cur)
                            LabeledMoney(label: "credit.payments", amount: s.payments, code: cur)
                            LabeledMoney(label: "credit.closingDebt", amount: s.closingDebt, code: cur, color: s.closingDebt > 0 ? .red : nil)
                        }.font(.app(.caption))
                    }
                }
            }
        }
        .contentMargins(.bottom, 90, for: .scrollContent)
        .themedScreen()
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("common.edit") { showEdit = true } }
        .sheet(isPresented: $showRepay) { AddTransactionView(type: .transfer, toAccount: account) }
        .sheet(isPresented: $showEdit) { AccountFormView(account: account, nextSort: account.sortID) }
    }
}
