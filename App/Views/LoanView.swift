import SwiftUI
import SwiftData
import LedgerCore

/// Экран банковского кредита: сколько осталось отдать, ежемесячный платёж, сколько платежей осталось и когда последний.
struct LoanView: View {
    let account: Account
    @Environment(\.modelContext) private var ctx
    @Query(sort: \RecurringTransaction.nextDate) private var recurring: [RecurringTransaction]
    @Query private var categories: [Category]
    @State private var showPay = false
    @State private var showEdit = false
    @State private var showSchedule = false
    @State private var showFix = false

    /// Расписание платежей на этот кредит: перевод по расписанию на этот счёт.
    private var schedule: RecurringTransaction? {
        recurring.first { $0.active && $0.toAccount?.persistentModelID == account.persistentModelID }
    }

    var body: some View {
        let remaining = max(-balance(of: account), 0)
        let principal = max(account.debtPrincipal ?? remaining, remaining)
        let paid = principal - remaining
        let closed = !account.transactions.isEmpty && remaining == 0
        let cur = account.currency
        let s = schedule
        let payment = s.map { abs($0.amount) }
        // Число платежей: по дате окончания расписания, а если её нет, по остатку долга.
        let left = s?.paymentsLeft ?? payment.flatMap { Loans.paymentsLeft(debt: remaining, payment: $0) }
        let category = account.loanCategoryID.flatMap { id in categories.first { $0.uuid == id } }

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(closed ? "loan.closed" : "loan.remaining").font(.app(.subheadline)).foregroundStyle(.secondary)
                    MoneyText(amount: remaining, code: cur, color: closed ? .green : Theme.expense).font(.app(.largeTitle, .bold))
                }
                ProgressView(value: Loans.paidRatio(principal: principal, remaining: remaining)).progressViewStyle(CapsuleBar(tint: Theme.accent))
                LabeledMoney(label: "loan.principal", amount: principal, code: cur)
                LabeledMoney(label: "loan.paid", amount: paid, code: cur)
                if let rate = account.interestRate, rate > 0 {
                    LabeledContent("loan.rate") { Text(verbatim: "\(rate)%") }
                }
            }

            Section {
                if let s, let payment {
                    LabeledMoney(label: "loan.payment", amount: payment, code: s.account?.currency ?? cur)
                    LabeledContent("loan.nextPayment") { Text(s.nextDate.shortDay) }
                    if let from = s.account { LabeledContent("loan.fromAccount") { Text(from.name) } }
                    if let left { LabeledContent("loan.paymentsLeft") { Text(verbatim: "\(left)") } }
                    if let last = lastPayment(s, count: left) { LabeledContent("loan.lastPayment") { Text(last.shortDay) } }
                } else if !closed {
                    Button { showSchedule = true } label: { Label("loan.setupPayment", systemImage: "calendar.badge.plus") }
                }
                LabeledContent("loan.budgetCategory") {
                    Text(category?.name ?? String(localized: "loan.noCategory")).foregroundStyle(.secondary)
                }
            } header: { Text("loan.schedule") } footer: { Text("loan.budgetFooter") }

            Section {
                if !closed {
                    Button { showPay = true } label: { Label("loan.pay", systemImage: "arrow.left.arrow.right.circle") }
                }
                Button { showFix = true } label: { Label("loan.fixBalance", systemImage: "pencil.and.list.clipboard") }
                NavigationLink { ActivityView(account: account) } label: { Label("credit.operations", systemImage: "list.bullet") }
            }
        }
        .contentMargins(.bottom, 90, for: .scrollContent)
        .themedScreen()
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("common.edit") { showEdit = true } }
        .sheet(isPresented: $showPay) {
            AddTransactionView(type: .transfer, toAccount: account, fromAccount: schedule?.account, amount: schedule.map { abs($0.amount) })
        }
        .sheet(isPresented: $showEdit) { AccountFormView(account: account, nextSort: account.sortID) }
        .sheet(isPresented: $showSchedule) { NewRecurringView(toAccount: account) }
        .sheet(isPresented: $showFix) { LoanBalanceSheet(account: account) }
    }

    /// Дата последнего платежа: окончание расписания или ближайший платёж плюс оставшиеся шаги.
    private func lastPayment(_ s: RecurringTransaction, count: Int?) -> Date? {
        guard let count, count > 0 else { return nil }
        var date = s.nextDate
        for _ in 1 ..< count {
            guard let next = Recurrence.nextDate(type: s.repeatType, duration: s.duration, from: date, after: date) else { return nil }
            date = next
        }
        return date
    }
}

/// Поправить остаток долга, если банк считает иначе (проценты, досрочное погашение, неточная оценка).
/// Разница записывается отдельной операцией на счёт кредита: в бюджеты и расходы она не попадает.
struct LoanBalanceSheet: View {
    let account: Account
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(RatesStore.self) private var rates
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                AmountField(title: "loan.actualDebt", text: $text, code: account.currency)
                Text("loan.fixHint").font(.app(.caption)).foregroundStyle(.secondary)
            }
            .themedScreen()
            .navigationTitle("loan.fixBalance")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { text = "\(max(-balance(of: account), 0))" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        guard let debt = Decimal.parse(text), debt >= 0 else { Haptics.error(); return }
                        let diff = -debt - balance(of: account)
                        if diff != 0 {
                            let tx = LedgerTransaction(amount: diff, type: diff > 0 ? .income : .expense,
                                                       payee: String(localized: "loan.fixPayee"), account: account)
                            ctx.insert(tx); rates.stamp(tx)
                        }
                        if (account.debtPrincipal ?? 0) < debt { account.debtPrincipal = debt }
                        Haptics.success(); dismiss()
                    }.disabled(Decimal.parse(text) == nil)
                }
            }
        }
    }
}

/// Превращает регулярный платёж по кредиту (расход) в счёт «Кредит» и перевод на него по расписанию.
/// Остаток долга подставляется оценкой «оставшиеся платежи × платёж», его можно поправить.
struct ConvertToLoanView: View {
    let item: RecurringTransaction
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(RatesStore.self) private var rates
    @State private var name = ""
    @State private var debtText = ""
    @State private var apr = ""
    @State private var category: Category?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("field.name", text: $name)
                    AmountField(title: "loan.actualDebt", text: $debtText, code: item.account?.currency ?? rates.base)
                    HStack { TextField("loan.rateOptional", text: $apr).keyboardType(.decimalPad); Text("%").foregroundStyle(.secondary) }
                    CategoryPickerRow(selection: $category, isIncome: false)
                } footer: { Text("loan.convertFooter") }
            }
            .themedScreen()
            .navigationTitle("loan.convert")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: load)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (Decimal.parse(debtText) ?? 0) <= 0) }
            }
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        name = item.payee.isEmpty ? (item.category?.name ?? "") : item.payee
        category = item.category
        let estimate = Loans.estimatedDebt(payments: item.paymentsLeft ?? 0, payment: abs(item.amount))
        debtText = estimate > 0 ? "\(estimate)" : ""
    }

    private func save() {
        let debt = max(Decimal.parse(debtText) ?? 0, 0)
        let count = (try? ctx.fetchCount(FetchDescriptor<Account>())) ?? 0
        let loan = Account(name: name.trimmingCharacters(in: .whitespaces), currency: item.account?.currency ?? rates.base, kind: .loan, sortID: count)
        loan.isPrimary = false
        loan.interestRate = Decimal.parse(apr)
        loan.loanCategoryID = category?.uuid
        loan.debtPrincipal = debt
        ctx.insert(loan)
        if debt > 0 {
            let tx = LedgerTransaction(amount: -debt, type: .expense, payee: String(localized: "account.openingPayee"), account: loan)
            ctx.insert(tx); rates.stamp(tx)
        }
        // Дальше платёж переводит деньги на кредит и уменьшает долг. Если даты окончания не было, ставим по остатку.
        let payment = abs(item.amount)
        item.type = .transfer
        item.amount = -payment
        item.toAccount = loan
        item.category = nil
        if item.endDate == nil, item.repeatType == 3, let n = Loans.paymentsLeft(debt: debt, payment: payment), n > 0 {
            item.endDate = Calendar.current.date(byAdding: .month, value: (n - 1) * item.duration, to: item.nextDate)
        }
        Haptics.success()
        dismiss()
    }
}
