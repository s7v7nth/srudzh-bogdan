import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var all: [LedgerTransaction]
    var account: Account? = nil
    @State private var search = ""
    @State private var typeFilter: TxType?
    @State private var editing: LedgerTransaction?
    @State private var editingAccount: Account?

    private var filtered: [LedgerTransaction] {
        all.filter { account == nil || $0.account === account }
           .filter { typeFilter == nil || $0.type == typeFilter }
           .filter { search.isEmpty || $0.payee.localizedCaseInsensitiveContains(search)
                     || ($0.category?.name.localizedCaseInsensitiveContains(search) ?? false) }
    }
    private var days: [(Date, [LedgerTransaction])] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
    }

    var body: some View {
        let content = List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(nil)
                        ForEach(TxType.allCases, id: \.self) { chip($0) }
                    }.padding(.horizontal, 16)
                }
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if filtered.isEmpty {
                ContentUnavailableView("activity.empty", systemImage: "list.bullet", description: Text("activity.emptyHint"))
            }
            ForEach(days, id: \.0) { day, items in
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(items) { t in row(t).contentShape(Rectangle()).onTapGesture { editing = t }.swipeActions { Button("common.delete", role: .destructive) { remove(t) } } }
                }
            }
        }
        .contentMargins(.bottom, 90, for: .scrollContent)
        .animation(.snappy, value: filtered.map(\.persistentModelID))
        .searchable(text: $search, prompt: Text("activity.search"))
        .themedScreen()
        .navigationTitle(account?.name ?? String(localized: "tab.activity"))
        .toolbar {
            if let account { Button("common.edit") { editingAccount = account } }
        }
        .sheet(item: $editingAccount) { AccountFormView(account: $0, nextSort: $0.sortID) }
        .sheet(item: $editing) { t in
            AddTransactionView(editing: t, partner: t.transferID.flatMap { id in all.first { $0.transferID == id && $0 !== t } })
        }

        if account == nil { NavigationStack { content } } else { content }
    }

    private func chip(_ type: TxType?) -> some View {
        let on = typeFilter == type
        let tint = type?.tint ?? Theme.accent
        return Button { typeFilter = on && type != nil ? nil : type } label: {
            HStack(spacing: 5) {
                if let type { Image(systemName: type.glyph).font(.app(.caption, .bold)).symbolEffect(.bounce, value: on) }
                if let type { Text(type.label) } else { Text("filter.all") }
            }
            .font(.app(.subheadline, .semibold)).padding(.horizontal, 12).frame(height: 34)
            .foregroundStyle(on ? Theme.onBrand : tint)
            .background(on ? Theme.brand : Theme.raised, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func title(_ t: LedgerTransaction) -> LocalizedStringKey? { t.isRepayment ? "activity.repayment" : nil }

    @ViewBuilder private func row(_ t: LedgerTransaction) -> some View {
        HStack(spacing: 12) {
            if t.type == .transfer {
                TxTypeBadge(type: .transfer)
            } else {
                TxCategoryBadge(category: t.category, type: t.type)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let key = title(t), t.payee.isEmpty { Text(key) }
                else { Text(t.payee.isEmpty ? (t.category?.name ?? String(localized: t.type == .transfer ? "tx.transfer" : "category.none")) : t.payee) }
                let sub = [t.type == .transfer && t.payee.isEmpty ? nil : t.category?.name, account == nil ? t.account?.name : nil]
                    .compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.app(.caption)).foregroundStyle(.secondary) }
            }
            Spacer()
            if t.pending { Image(systemName: "clock").foregroundStyle(.secondary) }
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(amount: t.amount, code: t.currency.isEmpty ? rates.base : t.currency, colored: true, weight: .semibold).font(.app(.body, .semibold))
                if !t.currency.isEmpty, t.currency != rates.base, let v = rates.value(of: t, in: rates.base) {
                    HStack(spacing: 2) { Text("≈"); MoneyText(amount: v, code: rates.base) }.font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// У перевода две половинки, удаляем обе.
    private func remove(_ t: LedgerTransaction) {
        if let id = t.transferID { all.filter { $0.transferID == id }.forEach(ctx.delete) } else { ctx.delete(t) }
        Haptics.delete()
    }
}
