import SwiftUI
import SwiftData
import LedgerCore

/// Разбор накопившихся СМС: сначала счета, потом квиз по категориям, в конце дайджест.
struct SMSReviewView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<LedgerTransaction> { $0.smsReview != 0 }, sort: \LedgerTransaction.date)
    private var pending: [LedgerTransaction]
    @State private var skipped: Set<PersistentIdentifier> = []

    private var quiz: [LedgerTransaction] { pending.filter { $0.review == .quiz && !skipped.contains($0.persistentModelID) } }
    private var digest: [LedgerTransaction] { pending.filter { $0.review == .digest } }

    var body: some View {
        NavigationStack {
            Group {
                if let tx = pending.first(where: { $0.review == .account }) {
                    SMSAccountStep(tx: tx)
                } else if let tx = quiz.first {
                    SMSQuizStep(tx: tx, remaining: quiz.count) { skipped.insert(tx.persistentModelID) }
                } else if !digest.isEmpty {
                    SMSDigestStep(items: digest) {
                        digest.forEach { $0.review = .done }
                        try? ctx.save()
                        dismiss()
                    }
                } else {
                    ContentUnavailableView("sms.allDone", systemImage: "checkmark.circle", description: Text("sms.allDoneHint"))
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("sms.later") { dismiss() } } }
        }
        .onAppear { SMSImporter.reclassifyQuizItems(ctx: ctx) }
    }
}

// MARK: Какой это счёт

private struct SMSAccountStep: View {
    let tx: LedgerTransaction
    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @Query(sort: \Account.sortID) private var accounts: [Account]
    @State private var newName = ""

    private var forCard: Bool { !tx.smsCard.isEmpty }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if forCard {
                        Text(fmt("sms.account.card", tx.smsCard)).font(.app(.title2, .bold))
                        Text("sms.account.cardHint").font(.app(.callout)).foregroundStyle(.secondary)
                    } else {
                        Text("sms.account.transfer").font(.app(.title2, .bold))
                        MoneyText(amount: tx.amount, code: tx.smsCurrency, colored: true).font(.app(.title3))
                        Text(tx.date.formatted(date: .abbreviated, time: .shortened)).font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            Section("sms.account.pick") {
                ForEach(accounts) { a in
                    Button { choose(a) } label: {
                        HStack {
                            Text(a.name).foregroundStyle(.primary); Spacer()
                            Text(a.currency).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                TextField("sms.account.newName", text: $newName)
                Button("sms.account.create") { choose(create()) }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: { Text("sms.account.new") }
        }
        .themedScreen()
        .navigationTitle("sms.account.title")
    }

    private func create() -> Account {
        let a = Account(name: newName.trimmingCharacters(in: .whitespaces),
                        currency: tx.smsCurrency.isEmpty ? rates.base : tx.smsCurrency, sortID: accounts.count)
        ctx.insert(a)
        return a
    }

    private func choose(_ a: Account) {
        if forCard { SMSImporter.bind(card: tx.smsCard, to: a, ctx: ctx, rates: rates) }
        else { SMSImporter.assign(tx, to: a, ctx: ctx, rates: rates); try? ctx.save() }
    }
}

// MARK: Квиз

private struct SMSQuizStep: View {
    let tx: LedgerTransaction
    let remaining: Int
    let onSkip: () -> Void
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Category.sortID) private var cats: [Category]
    @State private var renaming = false
    @State private var newName = ""

    private var expenseCats: [Category] { cats.filter { !$0.isIncome && !$0.archived } }
    private var suggested: [Category] {
        guard case .ask(let ids) = SMSImporter.suggestion(for: tx, ctx: ctx) else { return [] }
        return ids.compactMap { id in expenseCats.first { $0.uuid == id } }
    }

    var body: some View {
        let maybe = suggested
        let restTitle: LocalizedStringKey = maybe.isEmpty ? "sms.quiz.pick" : "sms.quiz.other"
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tx.payee).font(.app(.title2, .bold))
                    MoneyText(amount: tx.amount, code: tx.currency, colored: true).font(.app(.title))
                    Text([tx.date.formatted(date: .abbreviated, time: .shortened), tx.account?.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
            } header: { Text(fmt("sms.quiz.left", remaining)) }
            if !maybe.isEmpty {
                Section("sms.quiz.maybe") { ForEach(maybe) { row($0) } }
            }
            Section { ForEach(expenseCats.filter { c in !maybe.contains { $0 === c } }) { row($0) } } header: { Text(restTitle) }
            Section { Button("sms.quiz.skip", action: onSkip) }
        }
        .themedScreen()
        .navigationTitle("sms.quiz.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { newName = tx.payee; renaming = true } label: { Label("alias.rename", systemImage: "pencil") }
            }
        }
        .alert("alias.rename.title", isPresented: $renaming) {
            TextField("field.payee", text: $newName)
            Button("common.save") { SMSImporter.rename(payee: tx.payee, to: newName, ctx: ctx) }
            Button("common.cancel", role: .cancel) {}
        } message: { Text("alias.rename.hint") }
    }

    private func row(_ c: Category) -> some View {
        Button { SMSImporter.answer(tx, with: c, ctx: ctx) } label: {
            HStack(spacing: 12) { CategoryBadge(category: c); Text(c.name).foregroundStyle(.primary); Spacer() }
        }
    }
}

// MARK: Дайджест

private struct SMSDigestStep: View {
    let items: [LedgerTransaction]
    let finish: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(items) { t in
                    NavigationLink { SMSDigestEditView(tx: t) } label: { row(t) }
                }
            } header: { Text(fmt("sms.digest.count", items.count)) } footer: { Text("sms.digest.hint") }
        }
        .themedScreen()
        .navigationTitle("sms.digest.title")
        .safeAreaInset(edge: .bottom) {
            Button(action: finish) {
                Text("sms.digest.ok").font(.app(.headline)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(Theme.brand).foregroundStyle(Theme.onBrand).padding().background(.bar)
        }
    }

    private func row(_ t: LedgerTransaction) -> some View {
        HStack(spacing: 12) {
            CategoryBadge(category: t.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.payee)
                Text([t.category?.name ?? String(localized: "category.none"), t.account?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.app(.caption)).foregroundStyle(.secondary)
                if let gap = SMSImporter.balanceGap(t) {
                    Label(fmt("sms.gap", gap.formatted(.number.precision(.fractionLength(2))), t.currency), systemImage: "exclamationmark.triangle")
                        .font(.app(.caption)).foregroundStyle(.orange)
                }
            }
            Spacer()
            MoneyText(amount: t.amount, code: t.currency, colored: true)
        }
    }
}

private struct SMSDigestEditView: View {
    @Bindable var tx: LedgerTransaction
    @Environment(RatesStore.self) private var rates
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Account.sortID) private var accounts: [Account]
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                TextField("field.payee", text: $name)
                    .onSubmit(commitName)
                    .onAppear { name = tx.payee }
                    .onDisappear(perform: commitName)
                LabeledContent("field.amount") { MoneyText(amount: tx.amount, code: tx.currency, colored: true) }
                LabeledContent("field.date", value: tx.date.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                CategoryPickerRow(selection: Binding(get: { tx.category }, set: { tx.category = $0; $0?.lastUsed = .now }),
                                  isIncome: tx.type == .income)
                Picker("field.account", selection: Binding(get: { tx.account }, set: { tx.account = $0; rates.stamp(tx) })) {
                    ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                }
            } footer: { Text("sms.edit.hint") }
            if let gap = SMSImporter.balanceGap(tx) {
                Section {
                    Label(fmt("sms.gap", gap.formatted(.number.precision(.fractionLength(2))), tx.currency), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } footer: { Text("sms.gap.hint") }
            }
        }
        .themedScreen()
        .navigationTitle(tx.payee)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func commitName() {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { SMSImporter.rename(payee: tx.payee, to: name, ctx: ctx) }
    }
}

// MARK: Имена контрагентов

private struct PayeeAliasesView: View {
    @Environment(\.modelContext) private var ctx
    @State private var aliases: [PayeeAlias] = []

    var body: some View {
        List {
            Section {
                ForEach(aliases) { PayeeAliasRow(alias: $0) }
                    .onDelete { offsets in
                        offsets.map { aliases[$0] }.forEach(ctx.delete)
                        try? ctx.save()
                        load()
                    }
            } footer: { Text("alias.list.hint") }
        }
        .overlay { if aliases.isEmpty { ContentUnavailableView("alias.empty", systemImage: "pencil", description: Text("alias.empty.hint")) } }
        .themedScreen()
        .navigationTitle("alias.title")
        .onAppear(perform: load)
    }

    /// Правил мало, поэтому читаем их один раз при открытии экрана, без живого запроса.
    private func load() {
        aliases = (try? ctx.fetch(FetchDescriptor<PayeeAlias>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }
}

private struct PayeeAliasRow: View {
    let alias: PayeeAlias
    @Environment(\.modelContext) private var ctx
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("field.payee", text: $text).onSubmit(commit)
            Text(alias.original).font(.app(.caption)).foregroundStyle(.secondary)
        }
        .onAppear { text = alias.name }
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { text = alias.name; return }
        SMSImporter.rename(payee: alias.name, to: text, ctx: ctx)
    }
}

// MARK: Настройки СМС

struct SMSSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @Query(filter: #Predicate<LedgerTransaction> { $0.smsReview != 0 }) private var pending: [LedgerTransaction]
    @Query(sort: \CardAlias.last4) private var aliases: [CardAlias]
    @Query(sort: \Account.sortID) private var accounts: [Account]
    @State private var showReview = false
    @State private var pasted = ""
    @State private var result: LocalizedStringKey?

    var body: some View {
        Form {
            Section {
                Button { showReview = true } label: {
                    HStack { Text("sms.review"); Spacer(); if !pending.isEmpty { Text("\(pending.count)").foregroundStyle(.secondary) } }
                }
            }
            Section {
                ForEach(aliases) { alias in
                    Picker("••\(alias.last4)", selection: Binding(get: { alias.account }, set: { alias.account = $0 })) {
                        ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                    }
                }
                .onDelete { $0.map { aliases[$0] }.forEach(ctx.delete) }
            } header: { Text("sms.cards") } footer: { Text("sms.cards.hint") }
            Section {
                NavigationLink("alias.title") { PayeeAliasesView() }
            }
            Section {
                TextField("sms.paste.placeholder", text: $pasted, axis: .vertical).lineLimit(3...6)
                Button("sms.paste.add") {
                    switch SMSImporter.importText(pasted, ctx: ctx, rates: rates) {
                    case .added: result = "intent.addSMS.added"; pasted = ""
                    case .duplicate: result = "intent.addSMS.duplicate"
                    case .unrecognized: result = "intent.addSMS.unrecognized"
                    }
                }.disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let result { Text(result).font(.app(.footnote)).foregroundStyle(.secondary) }
            } header: { Text("sms.paste") }
            Section {
                Text("sms.setup.steps").font(.app(.footnote))
            } header: { Text("sms.setup") } footer: { Text("sms.setup.footer") }
        }
        .themedScreen()
        .navigationTitle("sms.title")
        .sheet(isPresented: $showReview) { SMSReviewView() }
    }
}
