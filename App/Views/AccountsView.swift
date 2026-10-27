import SwiftUI
import SwiftData
import LedgerCore

struct AccountsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @Query(sort: \Account.sortID) private var accounts: [Account]
    @State private var showNew = false
    @State private var showSettings = false
    @State private var includePending = true
    @State private var editing: Account?
    @State private var toDelete: Account?
    /// Пока зажата кнопка в углу виджета «Всего», считаются все счета, а не только основные.
    @State private var showAll = false

    /// Общий капитал в основной валюте и коды валют, для которых нет курса.
    private var net: (total: Decimal, missing: Set<String>) {
        var total: Decimal = 0
        var missing = Set<String>()
        for a in accounts where showAll || a.isPrimary {
            let b = balance(of: a, includePending: includePending)
            if let v = rates.convert(b, from: a.currency, to: rates.base) { total += v } else { missing.insert(a.currency) }
        }
        return (total, missing)
    }

    private var byCurrency: [(code: String, sum: Decimal)] {
        Dictionary(grouping: accounts.filter { showAll || $0.isPrimary }, by: \.currency)
            .map { ($0.key, $0.value.reduce(Decimal(0)) { $0 + balance(of: $1, includePending: includePending) }) }
            .sorted { $0.0 < $1.0 }
    }

    /// Кнопка-модификатор: пока держишь, «Всего» показывает все счета.
    private var showAllButton: some View {
        Image(systemName: showAll ? "eye.fill" : "eye")
            .font(.app(.subheadline)).foregroundStyle(showAll ? Color.black : Color.secondary)
            .frame(width: 36, height: 36)
            .background(showAll ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !showAll { withAnimation(.snappy(duration: 0.2)) { showAll = true } } }
                .onEnded { _ in withAnimation(.snappy(duration: 0.2)) { showAll = false } })
            .accessibilityLabel(Text("chaos.balance.showAll"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { withAnimation { showAll.toggle() } }
            .sensoryFeedback(.selection, trigger: showAll)
    }

    var body: some View {
        NavigationStack {
            List {
                if AutoBackup.shared.needsAttention { Section { BackupBanner() } }
                Section {
                    let n = net
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(showAll ? "accounts.totalAll" : "accounts.total").font(.app(.caption, .bold)).tracking(1.2).textCase(.uppercase).foregroundStyle(.secondary)
                            MoneyText(amount: n.total, code: rates.base, colored: true, tabular: false, weight: .heavy).font(.manrope(40, .heavy, relativeTo: .largeTitle))
                                .contentTransition(.numericText())
                        }
                        Spacer(minLength: 8)
                        showAllButton
                    }
                    if !n.missing.isEmpty {
                        Label(fmt("rates.missing", n.missing.sorted().joined(separator: ", ")), systemImage: "exclamationmark.triangle")
                            .font(.app(.caption)).foregroundStyle(.orange)
                    }
                    if byCurrency.count > 1 {
                        DisclosureGroup("accounts.byCurrency") {
                            ForEach(byCurrency, id: \.code) { item in
                                HStack { Text(item.code).foregroundStyle(.secondary); Spacer(); MoneyText(amount: item.sum, code: item.code) }
                            }
                        }
                    }
                    Toggle("accounts.includePending", isOn: $includePending)
                }
                Section("accounts.header") {
                    if accounts.isEmpty {
                        ContentUnavailableView("accounts.empty", systemImage: "creditcard", description: Text("accounts.emptyHint"))
                    }
                    ForEach(accounts.filter { !$0.isDebt }) { a in accountLink(a) }
                }
                if !openDebts.isEmpty {
                    Section("accounts.debts") { ForEach(openDebts) { a in accountLink(a) } }
                }
                if !closedDebts.isEmpty {
                    Section("debt.closed") { ForEach(closedDebts) { a in accountLink(a) } }
                }
            }
            .contentMargins(.bottom, 90, for: .scrollContent)
            .navigationTitle("tab.accounts")
            .themedScreen()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("settings.title", systemImage: "gearshape") { showSettings = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("accounts.add", systemImage: "plus.circle") { showNew = true } }
            }
            .sheet(isPresented: $showNew) { AccountFormView(nextSort: accounts.count) }
            .sheet(item: $editing) { AccountFormView(account: $0, nextSort: $0.sortID) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .confirmationDialog("account.deleteTitle", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("common.delete", role: .destructive) { if let a = toDelete { ctx.delete(a); Haptics.delete() }; toDelete = nil }
            } message: { Text("account.deleteMessage") }
        }
    }

    private var openDebts: [Account] {
        accounts.filter { $0.isDebt && !isClosed($0) }
            .sorted { ($0.debtDue ?? .distantFuture) < ($1.debtDue ?? .distantFuture) }
    }
    private var closedDebts: [Account] { accounts.filter { $0.isDebt && isClosed($0) } }
    private func isClosed(_ a: Account) -> Bool { !a.transactions.isEmpty && balance(of: a) == 0 }

    @ViewBuilder private func accountLink(_ a: Account) -> some View {
        NavigationLink {
            if a.isCredit { CreditLineView(account: a) } else if a.isDebt { DebtView(account: a) } else { ActivityView(account: a) }
        } label: { row(a) }
        .contextMenu { Button("common.edit", systemImage: "pencil") { editing = a } }
        .swipeActions {
            Button("common.delete", role: .destructive) { toDelete = a }
            Button("common.edit") { editing = a }.tint(.blue)
        }
    }

    @ViewBuilder private func row(_ a: Account) -> some View {
        let b = balance(of: a, includePending: includePending)
        HStack(spacing: 12) {
            let usage: Double = a.isCredit && (a.creditLimit ?? 0) > 0
                ? NSDecimalNumber(decimal: max(-b, 0) / (a.creditLimit ?? 1)).doubleValue : 0
            let tint: Color = a.isCredit ? BudgetState(ratio: usage).tint : Color.accentColor
            Image(systemName: a.kind.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 34, height: 34).background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name)
                if a.isCredit {
                    HStack(spacing: 4) {
                        Text("credit.available").font(.app(.caption)).foregroundStyle(.secondary)
                        MoneyText(amount: Balances.availableCredit(limit: a.creditLimit ?? 0, balance: b), code: a.currency)
                            .font(.app(.caption)).foregroundStyle(.secondary)
                    }
                } else if a.isDebt {
                    DebtDueLabel(account: a, closed: isClosed(a))
                } else {
                    Text(a.kind.label).font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(amount: b, code: a.currency, colored: true, weight: .semibold).font(.app(.body, .semibold))
                if a.currency != rates.base, let v = rates.convert(b, from: a.currency, to: rates.base) {
                    HStack(spacing: 2) { Text("≈"); MoneyText(amount: v, code: rates.base) }
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AccountFormView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(RatesStore.self) private var rates
    var account: Account? = nil
    let nextSort: Int

    @State private var name = ""
    @State private var kind: AccountKind = .card
    @State private var currency = ""
    @State private var opening = ""
    @State private var excluded = false
    @State private var primary = true
    @State private var limit = ""
    @State private var apr = ""
    @State private var statementDay = 1
    @State private var hasGrace = false
    @State private var graceDays = 30
    @State private var graceFromStatement = true
    @State private var minPercent = ""
    @State private var minFloor = ""
    @State private var dueDays = 20
    @State private var owedToMe = true
    @State private var hasDue = false
    @State private var dueDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var counter: Account?
    @Query(sort: \Account.sortID) private var allAccounts: [Account]
    @State private var submitted = false
    @State private var errorTick = 0
    @State private var loaded = false

    private var isEditing: Bool { account != nil }
    private var hasTransactions: Bool { !(account?.transactions.isEmpty ?? true) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("field.name", text: $name)
                    Picker("account.kind", selection: $kind) { ForEach(AccountKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                    CurrencyPicker(title: "account.currency", code: $currency).disabled(hasTransactions)
                    if !isEditing {
                        AmountField(title: kind == .creditLine ? "account.openingDebt" : (kind == .debt ? "debt.amount" : "account.opening"), text: $opening, code: currency)
                    }
                    Toggle("account.primary", isOn: $primary)
                    Toggle("account.excluded", isOn: $excluded)
                } footer: { if hasTransactions { Text("account.currencyLocked") } }
                if submitted && name.trimmingCharacters(in: .whitespaces).isEmpty { FormError("error.name", tick: errorTick) }

                if kind == .debt {
                    Section {
                        Picker("debt.direction", selection: $owedToMe) {
                            Text("debt.owedToMe").tag(true); Text("debt.iOwe").tag(false)
                        }.pickerStyle(.segmented).disabled(hasTransactions)
                        Toggle("debt.hasDue", isOn: $hasDue)
                        if hasDue { DatePicker("debt.dueDate", selection: $dueDate, displayedComponents: .date) }
                        if !isEditing {
                            Picker(owedToMe ? "debt.fromAccount" : "debt.toAccount", selection: $counter) {
                                Text("debt.noAccount").tag(Account?.none)
                                ForEach(allAccounts.filter { !$0.isDebt && $0.currency == currency }) { Text($0.name).tag(Account?.some($0)) }
                            }
                        }
                    } footer: { if !isEditing { Text("debt.footer") } }
                }

                if kind == .creditLine {
                    Section {
                        AmountField(title: "credit.limit", text: $limit, code: currency)
                        if submitted && (Decimal.parse(limit) ?? 0) <= 0 { FormError("error.limit", tick: errorTick) }
                        HStack { TextField("credit.apr", text: $apr).keyboardType(.decimalPad); Text("%").foregroundStyle(.secondary) }
                        Stepper(fmt("credit.statementDay", statementDay), value: $statementDay, in: 1...31)
                        Stepper(fmt("credit.dueDays", dueDays), value: $dueDays, in: 0...60)
                    } header: { Text("credit.terms") }
                    Section {
                        Toggle("credit.hasGrace", isOn: $hasGrace)
                        if hasGrace {
                            Stepper(fmt("credit.graceDays", graceDays), value: $graceDays, in: 1...180)
                            Toggle("credit.graceFromStatement", isOn: $graceFromStatement)
                        }
                    } header: { Text("credit.grace") } footer: { Text(hasGrace ? "credit.graceFooter" : "credit.noGraceFooter") }
                    Section {
                        HStack { TextField("credit.minPercent", text: $minPercent).keyboardType(.decimalPad); Text("%").foregroundStyle(.secondary) }
                        AmountField(title: "credit.minFloor", text: $minFloor, code: currency)
                    } header: { Text("credit.minPayment") } footer: { Text("credit.minFooter") }
                }
            }
            .themedScreen()
            .navigationTitle(isEditing ? "account.editTitle" : "account.newTitle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save", action: save) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let a = account else { currency = rates.base; return }
        owedToMe = a.debtOwedToMe; hasDue = a.debtDue != nil; dueDate = a.debtDue ?? dueDate
        name = a.name; kind = a.kind; currency = a.currency; excluded = a.excludedFromNetWorth; primary = a.isPrimary
        limit = a.creditLimit.map { "\($0)" } ?? ""; apr = a.interestRate.map { "\($0)" } ?? ""
        statementDay = a.statementDay ?? 1; dueDays = a.dueDays ?? 20
        hasGrace = a.graceDays != nil; graceDays = a.graceDays ?? 30; graceFromStatement = a.graceFromStatement
        minPercent = a.minPercent.map { "\($0)" } ?? ""; minFloor = a.minFloor.map { "\($0)" } ?? ""
    }

    private func save() {
        submitted = true
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { fail(); return }
        if kind == .creditLine, (Decimal.parse(limit) ?? 0) <= 0 { fail(); return }
        if kind == .debt, account == nil, (Decimal.parse(opening) ?? 0) == 0 { fail(); return }
        let a = account ?? Account(name: name, currency: currency, kind: kind, sortID: nextSort)
        a.name = name; a.kind = kind; a.excludedFromNetWorth = excluded; a.isPrimary = primary
        if !hasTransactions { a.currency = currency }
        if kind == .creditLine {
            a.creditLimit = Decimal.parse(limit); a.interestRate = Decimal.parse(apr)
            a.statementDay = statementDay; a.dueDays = dueDays
            a.graceDays = hasGrace ? graceDays : nil; a.graceFromStatement = graceFromStatement
            a.minPercent = Decimal.parse(minPercent); a.minFloor = Decimal.parse(minFloor)
        }
        if kind == .debt {
            a.debtOwedToMe = owedToMe; a.debtDue = hasDue ? dueDate : nil
        }
        if account == nil {
            ctx.insert(a)
            if kind == .debt, let o = Decimal.parse(opening), o != 0 {
                let signed = owedToMe ? abs(o) : -abs(o)
                a.debtPrincipal = abs(o)
                if let counter {
                    let id = UUID()
                    let inTx = LedgerTransaction(amount: signed, type: .transfer, transferID: id, account: a)
                    let outTx = LedgerTransaction(amount: -signed, type: .transfer, transferID: id, account: counter)
                    ctx.insert(inTx); ctx.insert(outTx); rates.stamp(inTx); rates.stamp(outTx)
                } else {
                    let tx = LedgerTransaction(amount: signed, type: signed > 0 ? .income : .expense, payee: String(localized: "account.openingPayee"), account: a)
                    ctx.insert(tx); rates.stamp(tx)
                }
            } else if let o = Decimal.parse(opening), o != 0 {
                let signed = kind == .creditLine ? -abs(o) : o
                let tx = LedgerTransaction(amount: signed, type: signed > 0 ? .income : .expense, payee: String(localized: "account.openingPayee"), account: a)
                ctx.insert(tx); rates.stamp(tx)
            }
        }
        Haptics.success()
        dismiss()
    }

    private func fail() { errorTick += 1; Haptics.error() }
}
