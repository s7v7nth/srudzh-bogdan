import SwiftUI
import SwiftData
import LedgerCore

struct AddTransactionView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(RatesStore.self) private var rates
    @Query(sort: \Account.sortID) private var accounts: [Account]

    @State private var type: TxType
    @State private var amountText = ""
    @State private var receivedText = ""
    @State private var receivedEdited = false
    @State private var payee = ""
    @State private var account: Account?
    @State private var toAccount: Account?
    @State private var category: Category?
    @State private var date = Date()
    @State private var notes = ""
    @State private var pending = false
    @State private var submitted = false
    @State private var errorTick = 0
    @State private var saved = false

    /// Редактируемая операция (nil — создаём новую). У перевода две половинки: исходящая и входящая.
    private let outTx: LedgerTransaction?
    private let inTx: LedgerTransaction?
    private var isEditing: Bool { outTx != nil }
    /// Вызывается, когда операция сохранена (а не отменена): по нему «Хаос» запускает монетки.
    private let onSaved: (() -> Void)?

    /// Открывает существующую операцию. Для перевода partner — вторая половинка.
    init(editing t: LedgerTransaction, partner: LedgerTransaction?) {
        let out = (t.type == .transfer && t.amount > 0 ? partner : nil) ?? t
        let inc: LedgerTransaction? = t.type == .transfer ? (out === t ? partner : t) : nil
        outTx = out; inTx = inc; onSaved = nil
        _type = State(initialValue: t.type)
        _amountText = State(initialValue: "\(abs(out.amount))")
        _receivedText = State(initialValue: inc.map { "\($0.amount)" } ?? "")
        _receivedEdited = State(initialValue: true)
        _payee = State(initialValue: out.payee)
        _account = State(initialValue: out.account)
        _toAccount = State(initialValue: inc?.account)
        _category = State(initialValue: out.category)
        _date = State(initialValue: out.date)
        _notes = State(initialValue: out.notes)
        _pending = State(initialValue: out.pending)
    }

    init(type: TxType = .expense, toAccount: Account? = nil, fromAccount: Account? = nil, category: Category? = nil,
         onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        _type = State(initialValue: type)
        _toAccount = State(initialValue: toAccount)
        _account = State(initialValue: fromAccount)
        _category = State(initialValue: category)
        outTx = nil; inTx = nil
    }

    private var amount: Decimal? { Decimal.parse(amountText).flatMap { $0 > 0 ? $0 : nil } }
    private var received: Decimal? { Decimal.parse(receivedText).flatMap { $0 > 0 ? $0 : nil } }
    private var crossCurrency: Bool {
        type == .transfer && account != nil && toAccount != nil && account?.currency != toAccount?.currency
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("field.type", selection: $type) { ForEach(TxType.allCases, id: \.self) { Label($0.label, systemImage: $0.glyph).tag($0) } }
                    .pickerStyle(.segmented)
                    .disabled(isEditing)
                    .listRowBackground(type.tint.opacity(0.18))
                    .onChange(of: type) { if category?.isIncome != (type == .income) { category = nil } }

                Section {
                    AmountField(title: type == .transfer ? "transfer.sent" : "field.amount", text: $amountText, code: account?.currency ?? rates.base)
                        .foregroundStyle(type.tint)
                    if submitted && amount == nil { FormError("error.amount", tick: errorTick) }
                }

                Section {
                    Picker(type == .transfer ? "transfer.from" : "field.account", selection: $account) {
                        Text("field.choose").tag(Account?.none)
                        ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                    }
                    if submitted && account == nil { FormError("error.account", tick: errorTick) }
                    if type == .transfer {
                        Picker("transfer.to", selection: $toAccount) {
                            Text("field.choose").tag(Account?.none)
                            ForEach(accounts.filter { $0 !== account }) { Text($0.name).tag(Account?.some($0)) }
                        }
                        if submitted && toAccount == nil { FormError("error.toAccount", tick: errorTick) }
                    } else {
                        TextField("field.payee", text: $payee)
                        CategoryPickerRow(selection: $category, isIncome: type == .income)
                    }
                }

                if crossCurrency, let to = toAccount {
                    Section {
                        AmountField(title: "transfer.received", text: Binding(get: { receivedText }, set: { receivedText = $0; receivedEdited = true }), code: to.currency)
                        if submitted && received == nil { FormError("error.received", tick: errorTick) }
                        if let a = amount, let r = received, let from = account {
                            Text(fmt("transfer.rate", from.currency, (r / a).formatted(.number.precision(.fractionLength(0...4))), to.currency))
                                .font(.app(.caption)).foregroundStyle(.secondary)
                        }
                    } footer: { Text("transfer.rateFooter") }
                }

                Section {
                    DatePicker("field.date", selection: $date)
                    Toggle("field.pending", isOn: $pending)
                    TextField("field.notes", text: $notes)
                }
            }
            .themedScreen()
            .navigationTitle(isEditing ? "edit.title" : "add.title")
            .onAppear { if !isEditing { account = account ?? accounts.first(where: { $0 !== toAccount }) } }
            .onChange(of: amountText) { suggestReceived() }
            .onChange(of: account) { suggestReceived() }
            .onChange(of: toAccount) { suggestReceived() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save", action: save).disabled(saved) }
            }
            .overlay {
                if accounts.isEmpty {
                    ContentUnavailableView("add.needAccount", systemImage: "creditcard", description: Text("add.needAccountHint")).background(.background)
                }
            }
            .overlay {
                if saved { SavedBadge(tint: type.tint).transition(.scale(scale: 0.5).combined(with: .opacity)) }
            }
        }
    }

    /// Предлагает сумму зачисления по текущему курсу, пока пользователь не ввёл свою.
    private func suggestReceived() {
        guard crossCurrency, !receivedEdited, let a = amount, let from = account, let to = toAccount,
              let v = rates.convert(a, from: from.currency, to: to.currency) else { return }
        receivedText = "\(v)"
    }

    private func save() {
        // Пока показывается галочка, окно ещё открыто: повторное нажатие не должно создать вторую операцию.
        guard !saved else { return }
        submitted = true
        guard let amount, let account else { fail(); return }
        if let outTx { saveEdit(outTx, amount: amount, account: account); return }
        var created: [LedgerTransaction] = []
        if type == .transfer {
            guard let toAccount else { fail(); return }
            let incoming: Decimal
            if account.currency == toAccount.currency { incoming = amount }
            else if let received { incoming = received } else { fail(); return }
            let id = UUID()
            created = [
                LedgerTransaction(amount: -amount, type: .transfer, date: date, notes: notes, pending: pending, transferID: id, account: account),
                LedgerTransaction(amount: incoming, type: .transfer, date: date, notes: notes, pending: pending, transferID: id, account: toAccount),
            ]
        } else {
            created = [LedgerTransaction(amount: type == .expense ? -amount : amount, type: type, date: date, payee: payee,
                                         notes: notes, pending: pending, account: account, category: category)]
            category?.lastUsed = .now
        }
        for tx in created { ctx.insert(tx); rates.stamp(tx) }
        let day = date
        Task { await rates.stampHistorical(created, on: day) }
        finish()
    }

    private func fail() { errorTick += 1; Haptics.error() }

    /// Показывает галочку и закрывает окно, когда она успела подпрыгнуть.
    private func finish() {
        Haptics.success()
        onSaved?()
        withAnimation(.spring(duration: 0.3, bounce: 0.4)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
    }

    /// Правит операцию на месте; у перевода обновляются обе половинки.
    private func saveEdit(_ out: LedgerTransaction, amount: Decimal, account: Account) {
        var changed = [out]
        if type == .transfer {
            guard let toAccount else { fail(); return }
            let incoming: Decimal
            if account.currency == toAccount.currency { incoming = amount }
            else if let received { incoming = received } else { fail(); return }
            out.amount = -amount; out.account = account
            if let inTx { inTx.amount = incoming; inTx.account = toAccount; changed.append(inTx) }
        } else {
            out.amount = type == .expense ? -amount : amount
            out.account = account; out.payee = payee; out.category = category
            category?.lastUsed = .now
        }
        for tx in changed { tx.date = date; tx.notes = notes; tx.pending = pending; rates.stamp(tx) }
        let day = date
        Task { await rates.stampHistorical(changed, on: day) }
        finish()
    }
}
