import SwiftUI
import SwiftData
import LedgerCore

/// Подпись под именем долга: срок возврата («осталось N дн.», «просрочено») или «закрыт».
struct DebtDueLabel: View {
    let account: Account
    let closed: Bool

    var body: some View {
        if closed {
            Label("debt.closedLabel", systemImage: "checkmark.circle").font(.app(.caption)).foregroundStyle(.green)
        } else {
            HStack(spacing: 4) {
                Text(account.debtOwedToMe ? "debt.owedToMe" : "debt.iOwe")
                if let due = account.debtDue {
                    Text("·"); Text(DebtDueLabel.text(for: due))
                        .foregroundStyle(DebtDueLabel.days(to: due) < 0 ? Color.red : Color.secondary)
                }
            }.font(.app(.caption)).foregroundStyle(.secondary)
        }
    }

    static func days(to due: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: due)).day ?? 0
    }

    static func text(for due: Date) -> String {
        let d = days(to: due)
        if d < 0 { return fmt("debt.overdue", -d) }
        if d == 0 { return String(localized: "debt.today") }
        return fmt("debt.daysLeft", d)
    }
}

/// Экран долга: сколько осталось вернуть, срок, прогресс и кнопка возврата.
struct DebtView: View {
    let account: Account
    @State private var showRepay = false
    @State private var showEdit = false

    var body: some View {
        let b = balance(of: account)
        let remaining = abs(b)
        let principal = max(account.debtPrincipal ?? remaining, remaining)
        let returned = principal - remaining
        let progress = principal > 0 ? NSDecimalNumber(decimal: returned / principal).doubleValue : 1
        let closed = !account.transactions.isEmpty && b == 0
        let cur = account.currency
        let tint: Color = account.debtOwedToMe ? Theme.accent : Theme.expense

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(closed ? "debt.closedLabel" : "debt.remaining").font(.app(.subheadline)).foregroundStyle(.secondary)
                    MoneyText(amount: remaining, code: cur, color: closed ? .green : tint).font(.app(.largeTitle, .bold))
                    Text(account.debtOwedToMe ? "debt.owedToMe" : "debt.iOwe").font(.app(.caption)).foregroundStyle(.secondary)
                }
                ProgressView(value: min(max(progress, 0), 1)).progressViewStyle(CapsuleBar(tint: tint))
                LabeledMoney(label: "debt.principal", amount: principal, code: cur)
                LabeledMoney(label: "debt.returned", amount: returned, code: cur)
                if let due = account.debtDue {
                    LabeledContent("debt.dueDate") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(due.shortDay)
                            if !closed {
                                Text(DebtDueLabel.text(for: due)).font(.app(.caption))
                                    .foregroundStyle(DebtDueLabel.days(to: due) < 0 ? Color.red : Color.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                if !closed {
                    Button { showRepay = true } label: {
                        Label(account.debtOwedToMe ? "debt.repayTheirs" : "debt.repayMine", systemImage: "arrow.left.arrow.right.circle")
                    }
                }
                NavigationLink { ActivityView(account: account) } label: { Label("credit.operations", systemImage: "list.bullet") }
            }
        }
        .contentMargins(.bottom, 90, for: .scrollContent)
        .themedScreen()
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("common.edit") { showEdit = true } }
        .sheet(isPresented: $showRepay) {
            // Мне вернули: деньги идут с долгового счёта на мой. Я вернул: с моего на долговой.
            if account.debtOwedToMe { AddTransactionView(type: .transfer, fromAccount: account) }
            else { AddTransactionView(type: .transfer, toAccount: account) }
        }
        .sheet(isPresented: $showEdit) { AccountFormView(account: account, nextSort: account.sortID) }
    }
}
