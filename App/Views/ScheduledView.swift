import SwiftUI
import SwiftData
import LedgerCore

struct ScheduledView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @Query(sort: \RecurringTransaction.nextDate) private var items: [RecurringTransaction]
    @Query private var categories: [Category]
    @State private var showNew = false
    @State private var editing: RecurringTransaction?
    @State private var converting: RecurringTransaction?

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView("sched.empty", systemImage: "repeat", description: Text("sched.emptyHint"))
                }
                ForEach(groups, id: \.icon) { g in
                    Section {
                        ForEach(g.items) { r in row(r) }
                    } header: {
                        Label(g.title, systemImage: g.icon).foregroundStyle(g.tint).font(.app(.subheadline, .semibold))
                    }
                }
            }
            .contentMargins(.bottom, 90, for: .scrollContent)
            .navigationTitle("tab.scheduled")
            .themedScreen()
            .toolbar { Button("sched.add") { showNew = true } }
            .sheet(isPresented: $showNew) { NewRecurringView() }
            .sheet(item: $editing) { EditAmountView(item: $0) }
            .sheet(item: $converting) { ConvertToLoanView(item: $0) }
        }
    }

    private struct Group { let title: LocalizedStringKey; let icon: String; let tint: Color; let items: [RecurringTransaction] }

    private var groups: [Group] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let soon = cal.date(byAdding: .day, value: 7, to: today) ?? today
        let active = items.filter(\.active)
        return [
            Group(title: "sched.group.overdue", icon: "exclamationmark.circle.fill", tint: BudgetState.over.tint, items: active.filter { $0.nextDate < today }),
            Group(title: "sched.group.soon", icon: "clock.fill", tint: BudgetState.warn.tint, items: active.filter { $0.nextDate >= today && $0.nextDate < soon }),
            Group(title: "sched.group.later", icon: "calendar", tint: .secondary, items: items.filter { !$0.active || $0.nextDate >= soon }),
        ].filter { !$0.items.isEmpty }
    }

    @ViewBuilder private func row(_ r: RecurringTransaction) -> some View {
        let due = r.active && r.nextDate <= .now
        HStack(spacing: 12) {
            // Платёж по кредиту показываем значком категории кредита.
            TxCategoryBadge(category: r.category ?? r.toAccount?.loanCategoryID.flatMap { id in categories.first { $0.uuid == id } }, type: r.type)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.payee.isEmpty ? (r.category?.name ?? String(localized: "category.none")) : r.payee)
                Text(subtitle(r)).font(.app(.caption)).foregroundStyle(due ? BudgetState.over.tint : Color.secondary)
            }
            Spacer()
            MoneyText(amount: r.amount, code: r.account?.currency ?? rates.base, colored: true)
        }
        .opacity(r.active ? 1 : 0.5)
        .swipeActions(edge: .leading) {
            if r.active {
                Button("sched.execute", systemImage: "checkmark") { execute(r) }.tint(BudgetState.ok.tint)
                Button("sched.skip", systemImage: "forward") { advance(r, from: r.nextDate) }.tint(BudgetState.warn.tint)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("common.delete", role: .destructive) { ctx.delete(r); Haptics.delete() }.tint(.red)
            Button("sched.amount") { editing = r }.tint(.blue)
            if r.type == .expense { Button("loan.convert") { converting = r }.tint(.orange) }
        }
        .contextMenu {
            Button("sched.amount", systemImage: "pencil") { editing = r }
            if r.type == .expense { Button("loan.convert", systemImage: "percent") { converting = r } }
            Button("common.delete", systemImage: "trash", role: .destructive) { ctx.delete(r); Haptics.delete() }
        }
    }

    /// «11 дек. · каждый месяц · → Кредит». Слово «следующий» не пишем: это и так ясно из группы.
    private func subtitle(_ r: RecurringTransaction) -> String {
        guard r.active else { return String(localized: "sched.finished") }
        let date = r.nextDate <= .now ? "\(String(localized: "sched.overdueSince")) \(r.nextDate.shortDay)" : r.nextDate.shortDay
        let target = r.toAccount.map { " · → \($0.name)" } ?? ""
        return "\(date) · \(Self.cadence(r))\(target)"
    }

    /// Как часто повторяется платёж, обычными словами.
    static func cadence(_ r: RecurringTransaction) -> String {
        let n = r.duration
        switch (r.repeatType, n == 1) {
        case (1, true): return String(localized: "sched.rep1.day")
        case (2, true): return String(localized: "sched.rep1.week")
        case (3, true): return String(localized: "sched.rep1.month")
        case (4, true): return String(localized: "sched.rep1.year")
        case (1, false): return fmt("sched.repN.day", n)
        case (2, false): return fmt("sched.repN.week", n)
        case (4, false): return fmt("sched.repN.year", n)
        default: return n == 1 ? String(localized: "sched.rep1.month") : fmt("sched.repN.month", n)
        }
    }

    private func execute(_ r: RecurringTransaction) { r.execute(in: ctx, rates: rates) }
    private func advance(_ r: RecurringTransaction, from recorded: Date) { r.skip() }
}

struct EditAmountView: View {
    @Environment(\.dismiss) private var dismiss
    let item: RecurringTransaction
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                AmountField(title: "sched.newAmount", text: $text, code: item.account?.currency ?? "")
                Text("sched.amountHint").font(.app(.caption)).foregroundStyle(.secondary)
            }
            .themedScreen()
            .navigationTitle("sched.editAmount")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        if let v = Decimal.parse(text), v > 0 { item.amount = item.type == .income ? v : -v; Haptics.success(); dismiss() }
                    }.disabled((Decimal.parse(text) ?? 0) <= 0)
                }
            }
        }
    }
}

struct NewRecurringView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortID) private var accounts: [Account]
    @State private var type: TxType = .expense
    @State private var amountText = ""
    @State private var payee = ""
    @State private var account: Account?
    @State private var toAccount: Account?
    @State private var category: Category?
    @State private var start = Date()
    @State private var repeatType = 3
    @State private var every = 1
    @State private var hasEnd = false
    @State private var end = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
    @State private var submitted = false
    @State private var errorTick = 0

    init(toAccount: Account? = nil) {
        if let toAccount {
            _type = State(initialValue: .transfer); _toAccount = State(initialValue: toAccount)
            _payee = State(initialValue: toAccount.name)
            // Кредит: платёж до погашения, если остаток известен, окончание посчитаем при сохранении.
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("field.type", selection: $type) { ForEach(TxType.allCases, id: \.self) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).onChange(of: type) { category = nil }
                AmountField(title: "field.amount", text: $amountText, code: account?.currency ?? "")
                if submitted && (Decimal.parse(amountText) ?? 0) <= 0 { FormError("error.amount", tick: errorTick) }
                TextField("field.payee", text: $payee)
                Picker("field.account", selection: $account) {
                    Text("field.choose").tag(Account?.none)
                    ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                }
                if submitted && account == nil { FormError("error.account", tick: errorTick) }
                if type == .transfer {
                    Picker("field.toAccount", selection: $toAccount) {
                        Text("field.choose").tag(Account?.none)
                        ForEach(accounts.filter { $0 !== account }) { Text($0.name).tag(Account?.some($0)) }
                    }
                    if submitted && toAccount == nil { FormError("error.account", tick: errorTick) }
                } else {
                    CategoryPickerRow(selection: $category, isIncome: type == .income)
                }
                DatePicker("sched.firstDate", selection: $start, displayedComponents: .date)
                Picker("sched.repeat", selection: $repeatType) {
                    Text("period.days").tag(1); Text("period.weeks").tag(2); Text("period.months").tag(3); Text("period.years").tag(4)
                }
                Stepper(fmt("sched.everyN", every), value: $every, in: 1...60)
                Toggle("sched.hasEnd", isOn: $hasEnd)
                if hasEnd { DatePicker("sched.end", selection: $end, displayedComponents: .date) }
            }
            .onAppear {
                account = account ?? accounts.first { $0 !== toAccount && !$0.isLoan } ?? accounts.first
                // Платёж по кредиту: окончание там, где закончится долг.
                if let loan = toAccount, loan.isLoan, !hasEnd { suggestLoanEnd(loan) }
            }
            .onChange(of: amountText) { if let loan = toAccount, loan.isLoan { suggestLoanEnd(loan) } }
            .onChange(of: start) { if let loan = toAccount, loan.isLoan { suggestLoanEnd(loan) } }
            .themedScreen()
            .navigationTitle("sched.newTitle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        submitted = true
                        guard let v = Decimal.parse(amountText), v > 0, let account,
                              type != .transfer || toAccount != nil else { errorTick += 1; Haptics.error(); return }
                        ctx.insert(RecurringTransaction(amount: type == .income ? v : -v, type: type, payee: payee,
                                                        nextDate: start, repeatType: repeatType, duration: every,
                                                        endDate: hasEnd ? end : nil, account: account,
                                                        category: type == .transfer ? nil : category,
                                                        toAccount: type == .transfer ? toAccount : nil))
                        Haptics.success()
                        dismiss()
                    }
                }
            }
        }
    }

    /// Для кредита: дата последнего платежа по остатку долга (ежемесячно).
    private func suggestLoanEnd(_ loan: Account) {
        guard let v = Decimal.parse(amountText), v > 0,
              let n = Loans.paymentsLeft(debt: max(-balance(of: loan), 0), payment: v), n > 0,
              let last = Calendar.current.date(byAdding: .month, value: n - 1, to: start) else { return }
        repeatType = 3; every = 1; hasEnd = true; end = last
    }
}
