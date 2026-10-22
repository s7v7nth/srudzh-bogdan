import SwiftUI
import SwiftData
import LedgerCore

struct ScheduledView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @Query(sort: \RecurringTransaction.nextDate) private var items: [RecurringTransaction]
    @State private var showNew = false
    @State private var editing: RecurringTransaction?

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
            .toolbar { Button("sched.add", systemImage: "plus.circle") { showNew = true } }
            .sheet(isPresented: $showNew) { NewRecurringView() }
            .sheet(item: $editing) { EditAmountView(item: $0) }
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
            TxCategoryBadge(category: r.category, type: r.type)
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
            Button("common.delete", role: .destructive) { ctx.delete(r); Haptics.delete() }
            Button("sched.amount") { editing = r }.tint(.blue)
        }
    }

    private func subtitle(_ r: RecurringTransaction) -> String {
        guard r.active else { return String(localized: "sched.finished") }
        let unit = [String(localized: "period.day"), String(localized: "period.week"), String(localized: "period.month"), String(localized: "period.year")][r.repeatType - 1].lowercased()
        let every = fmt("sched.every", r.duration, unit)
        let prefix = String(localized: r.nextDate <= .now ? "sched.overdueSince" : "sched.next")
        return "\(prefix) \(r.nextDate.shortDay) · \(every)"
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
                        if let v = Decimal.parse(text), v > 0 { item.amount = item.type == .expense ? -v : v; Haptics.success(); dismiss() }
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
    @State private var income = false
    @State private var amountText = ""
    @State private var payee = ""
    @State private var account: Account?
    @State private var category: Category?
    @State private var start = Date()
    @State private var repeatType = 3
    @State private var every = 1
    @State private var hasEnd = false
    @State private var end = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
    @State private var submitted = false
    @State private var errorTick = 0

    var body: some View {
        NavigationStack {
            Form {
                Picker("field.type", selection: $income) { Text("tx.expense").tag(false); Text("tx.income").tag(true) }
                    .pickerStyle(.segmented).onChange(of: income) { category = nil }
                AmountField(title: "field.amount", text: $amountText, code: account?.currency ?? "")
                if submitted && (Decimal.parse(amountText) ?? 0) <= 0 { FormError("error.amount", tick: errorTick) }
                TextField("field.payee", text: $payee)
                Picker("field.account", selection: $account) {
                    Text("field.choose").tag(Account?.none)
                    ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                }
                if submitted && account == nil { FormError("error.account", tick: errorTick) }
                CategoryPickerRow(selection: $category, isIncome: income)
                DatePicker("sched.firstDate", selection: $start, displayedComponents: .date)
                Picker("sched.repeat", selection: $repeatType) {
                    Text("period.days").tag(1); Text("period.weeks").tag(2); Text("period.months").tag(3); Text("period.years").tag(4)
                }
                Stepper(fmt("sched.everyN", every), value: $every, in: 1...60)
                Toggle("sched.hasEnd", isOn: $hasEnd)
                if hasEnd { DatePicker("sched.end", selection: $end, displayedComponents: .date) }
            }
            .onAppear { account = account ?? accounts.first }
            .themedScreen()
            .navigationTitle("sched.newTitle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        submitted = true
                        guard let v = Decimal.parse(amountText), v > 0, let account else { errorTick += 1; Haptics.error(); return }
                        ctx.insert(RecurringTransaction(amount: income ? v : -v, type: income ? .income : .expense, payee: payee,
                                                        nextDate: start, repeatType: repeatType, duration: every,
                                                        endDate: hasEnd ? end : nil, account: account, category: category))
                        Haptics.success()
                        dismiss()
                    }
                }
            }
        }
    }
}
