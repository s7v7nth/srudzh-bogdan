import SwiftUI
import SwiftData
import LedgerCore

struct BudgetsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @Query private var budgets: [Budget]
    @Query private var transactions: [LedgerTransaction]
    @State private var showNew = false
    @State private var editing: Budget?

    var body: some View {
        NavigationStack {
            List {
                if budgets.isEmpty {
                    ContentUnavailableView("budgets.empty", systemImage: "chart.pie", description: Text("budgets.emptyHint"))
                }
                ForEach(budgets) { b in row(b).contentShape(Rectangle()).onTapGesture { editing = b } }.onDelete { for i in $0 { ctx.delete(budgets[i]) }; Haptics.delete() }
            }
            .contentMargins(.bottom, 90, for: .scrollContent)
            .navigationTitle("tab.budgets")
            .themedScreen()
            .toolbar { Button("budgets.add", systemImage: "plus.circle") { showNew = true } }
            .sheet(isPresented: $showNew) { NewBudgetView() }
            .sheet(item: $editing) { NewBudgetView(budget: $0) }
        }
    }

    @ViewBuilder private func row(_ b: Budget) -> some View {
        if let r = BudgetProgress.make(b, transactions: transactions, rates: rates) {
            let state = r.state
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: state.icon).foregroundStyle(state.tint)
                    Text(b.name).font(.app(.headline)); Spacer()
                    MoneyText(amount: r.remaining, code: r.currency, color: state == .ok ? nil : state.tint).fontWeight(.semibold)
                }
                ProgressView(value: min(r.ratio, 1)).progressViewStyle(CapsuleBar(tint: state.tint))
                HStack(spacing: 4) {
                    Text("budgets.spent"); MoneyText(amount: r.spent, code: r.currency)
                    Text("budgets.of"); MoneyText(amount: r.limit, code: r.currency)
                    Text("· " + fmt("budgets.until", r.periodEnd.shortDay))
                }.font(.app(.caption)).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }
    }
}

struct NewBudgetView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(RatesStore.self) private var rates
    @Query(sort: \Category.sortID) private var categories: [Category]
    @State private var name = ""
    @State private var amountText = ""
    @State private var currency = ""
    @State private var repeatType = 3
    @State private var picked: Set<UUID> = []
    @State private var submitted = false
    @State private var errorTick = 0
    private let budget: Budget?

    init(budget: Budget? = nil) {
        self.budget = budget
        guard let b = budget else { return }
        _name = State(initialValue: b.name)
        _amountText = State(initialValue: "\(b.amount)")
        _currency = State(initialValue: b.currency)
        _repeatType = State(initialValue: b.repeatType)
        _picked = State(initialValue: Set(b.categories.map(\.uuid)))
    }

    private var pool: [(Category, Int)] {
        categories.filter { $0.parent == nil && !$0.isIncome && !$0.archived }.flatMap { p in
            [(p, 0)] + p.children.filter { !$0.archived }.sorted { $0.sortID < $1.sortID }.map { ($0, 1) }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("field.name", text: $name)
                    if submitted && name.isEmpty { FormError("error.name", tick: errorTick) }
                    CurrencyPicker(title: "budgets.currency", code: $currency)
                    AmountField(title: "budgets.amount", text: $amountText, code: currency)
                    if submitted && (Decimal.parse(amountText) ?? 0) <= 0 { FormError("error.amount", tick: errorTick) }
                    Picker("budgets.period", selection: $repeatType) {
                        Text("period.day").tag(1); Text("period.week").tag(2); Text("period.month").tag(3); Text("period.year").tag(4)
                    }
                }
                Section {
                    ForEach(pool, id: \.0.uuid) { c, level in
                        Button {
                            if picked.contains(c.uuid) { picked.remove(c.uuid) } else { picked.insert(c.uuid) }
                        } label: {
                            HStack {
                                CategoryBadge(category: c, size: 26)
                                Text(c.name).foregroundStyle(.primary)
                                Spacer()
                                if picked.contains(c.uuid) { Image(systemName: "checkmark") }
                            }.padding(.leading, CGFloat(level) * 24)
                        }
                    }
                } header: { Text("budgets.categories") } footer: { Text("budgets.categoriesFooter") }
            }
            .themedScreen()
            .navigationTitle(budget == nil ? "budgets.newTitle" : "budgets.editTitle")
            .onAppear { if currency.isEmpty { currency = rates.base } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save", action: save) }
            }
        }
    }

    private func save() {
        submitted = true
        guard let amount = Decimal.parse(amountText), amount > 0, !name.isEmpty else { errorTick += 1; Haptics.error(); return }
        if let budget {
            budget.name = name; budget.amount = amount; budget.currency = currency
            if budget.repeatType != repeatType {
                let u: Calendar.Component = repeatType == 4 ? .year : repeatType == 3 ? .month : repeatType == 2 ? .weekOfYear : .day
                budget.startDate = Calendar.current.dateInterval(of: u, for: .now)!.start
                budget.repeatType = repeatType
            }
            budget.categories = categories.filter { picked.contains($0.uuid) }
            Haptics.success(); dismiss(); return
        }
        let unit: Calendar.Component = repeatType == 4 ? .year : repeatType == 3 ? .month : repeatType == 2 ? .weekOfYear : .day
        let start = Calendar.current.dateInterval(of: unit, for: .now)!.start
        let b = Budget(name: name, amount: amount, currency: currency, startDate: start, repeatType: repeatType)
        b.categories = categories.filter { picked.contains($0.uuid) }
        ctx.insert(b); Haptics.success(); dismiss()
    }
}
