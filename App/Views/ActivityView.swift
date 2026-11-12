import SwiftUI
import SwiftData

struct ActivityView: View {
    var account: Account? = nil
    /// Если задан, показываются только операции из категорий бюджета (как он их считает).
    var budget: Budget? = nil
    /// Текст в поле поиска и открытые окна лежат вне состояния экрана: набор букв и нажатие на строку
    /// не заставляют заново перебирать все операции. Список перестраивается, когда меняется `query`.
    @State private var ui = ActivityUI()
    @State private var typeFilter: TxType?
    /// Сколько последних операций показывать в общем списке без поиска и фильтра.
    @State private var limit = ActivityList.page

    var body: some View {
        // Общий список без поиска и фильтра берёт из базы только последние операции: он открыт всё время,
        // и после каждой правки перечитывать всю историю ради него слишком дорого.
        let limited = account == nil && budget == nil && ui.query.isEmpty && typeFilter == nil
        let content = ActivityList(account: account, budget: budget, search: ui.query, typeFilter: $typeFilter, ui: ui,
                                   limit: limited ? limit : nil) { limit += ActivityList.page }
            // Поле поиска всегда сверху под заголовком: на iOS 26 системное место внизу закрыто нашей панелью вкладок.
            .searchable(text: Binding(get: { ui.text }, set: { ui.type($0) }), placement: .navigationBarDrawer(displayMode: .always), prompt: Text("activity.search"))
            .themedScreen()
            .navigationTitle(budget?.name ?? account?.name ?? String(localized: "tab.activity"))
            .toolbar {
                if let account { Button("common.edit") { ui.editingAccount = account } }
                if let budget { Button("common.edit") { ui.editingBudget = budget } }
            }
            .modifier(ActivitySheets(ui: ui))

        if account == nil && budget == nil { NavigationStack { content } } else { content }
    }
}

/// Сам список операций. Запрос к базе строится по фильтрам экрана.
private struct ActivityList: View {
    static let page = 300

    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @Query private var all: [LedgerTransaction]
    let account: Account?
    let budget: Budget?
    let search: String
    @Binding var typeFilter: TxType?
    let ui: ActivityUI
    let limit: Int?
    let onMore: () -> Void

    init(account: Account?, budget: Budget?, search: String, typeFilter: Binding<TxType?>, ui: ActivityUI,
         limit: Int?, onMore: @escaping () -> Void) {
        var d = FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let limit { d.fetchLimit = limit }
        _all = Query(d)
        self.account = account; self.budget = budget; self.search = search
        _typeFilter = typeFilter; self.ui = ui; self.limit = limit; self.onMore = onMore
    }

    /// Один проход по всем операциям вместо трёх отдельных фильтров.
    private var filtered: [LedgerTransaction] {
        let budgetCategories: Set<UUID>? = budget.map { b in Set(b.categories.flatMap(\.familyIDs)) }
        return all.filter { t in
            (account == nil || t.account === account)
                && (budgetCategories.map { inBudget(t, $0) } ?? true)
                && (typeFilter == nil || t.type == typeFilter)
                && (search.isEmpty || t.payee.localizedCaseInsensitiveContains(search)
                    || (t.category?.name.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    /// Операции уже отсортированы по дате, поэтому дни собираются подряд, без словаря и пересортировки.
    private func days(_ list: [LedgerTransaction]) -> [(Date, [LedgerTransaction])] {
        let cal = Calendar.current
        var out: [(Date, [LedgerTransaction])] = []
        for t in list {
            let day = cal.startOfDay(for: t.date)
            if out.last?.0 == day { out[out.count - 1].1.append(t) } else { out.append((day, [t])) }
        }
        return out
    }

    var body: some View {
        let list = perf("activity") { filtered }
        // Если упёрлись в предел, последний день мог попасть не целиком: его прячем, чтобы итог дня был честным.
        let hasMore = limit.map { all.count >= $0 } ?? false
        var groups = days(list)
        if hasMore, groups.count > 1 { groups.removeLast() }
        return List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(nil)
                        ForEach(TxType.allCases, id: \.self) { chip($0) }
                    }
                }
                // Если фильтры всё же не влезли (крупный шрифт), они уезжают за край экрана, а не обрезаются посреди слова.
                .scrollClipDisabled()
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if list.isEmpty {
                ContentUnavailableView("activity.empty", systemImage: "list.bullet", description: Text("activity.emptyHint"))
            }
            ForEach(groups, id: \.0) { day, items in
                Section {
                    ForEach(items) { t in Button { ui.editing = t } label: { row(t) }.buttonStyle(RowPress())
                        // Без полного свайпа: широкий жест не должен молча стирать операцию, кнопку жмут отдельно.
                        .swipeActions(allowsFullSwipe: false) { Button("common.delete") { remove(t) }.tint(.red) } }
                } header: {
                    DayHeader(day: day, items: items)
                }
            }
            if hasMore {
                Section {
                    Button("activity.more", action: onMore).font(.app(.body, .semibold)).frame(maxWidth: .infinity)
                }
            }
        }
        .contentMargins(.bottom, 90, for: .scrollContent)
        // Список сам плавно убирает удалённую строку (и пустой день целиком), а при поиске строки не разъезжаются.
        .animation(search.isEmpty ? Motion.standard : nil, value: list.map(\.persistentModelID))
    }

    /// Та же логика, что у подсчёта бюджета: траты в его категориях (с подкатегориями) и платежи по кредиту
    /// в категорию кредита. Бюджет без категорий следит за всеми тратами.
    private func inBudget(_ t: LedgerTransaction, _ ids: Set<UUID>) -> Bool {
        guard let a = t.account else { return false }
        let loanCategory = t.loanPaymentCategory
        if a.isLoan ? loanCategory == nil : t.type == .transfer { return false }
        guard let id = loanCategory ?? t.category?.uuid else { return ids.isEmpty }
        return ids.isEmpty || ids.contains(id)
    }

    private func chip(_ type: TxType?) -> some View {
        let on = typeFilter == type
        let tint = type?.tint ?? Theme.accent
        return Button { typeFilter = on && type != nil ? nil : type } label: {
            HStack(spacing: 5) {
                if let type { Image(systemName: type.glyph).font(.app(.caption, .bold)) }
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
    /// Кнопка удаления без системной роли «удалить»: с ней список убирает строку сам, а пустой день
    /// исчезает отдельным рывком позже. Так строка и день уходят одним плавным движением.
    private func remove(_ t: LedgerTransaction) {
        if let id = t.transferID { LedgerTransaction.halves(of: id, in: ctx).forEach(ctx.delete) } else { ctx.delete(t) }
        Haptics.delete()
    }
}

/// Поиск и открытые окна экрана операций.
@MainActor @Observable final class ActivityUI {
    /// Что набрано в поле поиска прямо сейчас.
    private(set) var text = ""
    /// Что ищем: догоняет `text` после короткой паузы в наборе.
    private(set) var query = ""
    var editing: LedgerTransaction?
    var editingAccount: Account?
    var editingBudget: Budget?
    @ObservationIgnored private var pending: Task<Void, Never>?

    func type(_ new: String) {
        guard new != text else { return }
        text = new
        pending?.cancel()
        // Очистка поля срабатывает сразу, без паузы.
        if new.isEmpty { query = ""; return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.query = new
        }
    }
}

/// Окна правки операции, счёта и бюджета. Читает состояние сам, поэтому открытие окна не перерисовывает список.
private struct ActivitySheets: ViewModifier {
    @Bindable var ui: ActivityUI
    @Environment(\.modelContext) private var ctx

    func body(content: Content) -> some View {
        content
            .sheet(item: $ui.editingAccount) { AccountFormView(account: $0, nextSort: $0.sortID) }
            .sheet(item: $ui.editingBudget) { NewBudgetView(budget: $0) }
            .sheet(item: $ui.editing) { t in AddTransactionView(editing: t, partner: partner(of: t)) }
    }

    /// Вторая половинка перевода.
    private func partner(of t: LedgerTransaction) -> LedgerTransaction? {
        t.transferID.flatMap { id in LedgerTransaction.halves(of: id, in: ctx).first { $0 !== t } }
    }
}

/// Дата дня и итог за день в основной валюте. Переводы между своими счетами в сумме взаимно гасятся.
/// Отдельный экранный элемент, чтобы итог считался только для дней, которые сейчас на экране.
private struct DayHeader: View {
    let day: Date
    let items: [LedgerTransaction]
    @Environment(RatesStore.self) private var rates

    /// «четверг, 12 ноября»; год дописывается только для прошлых лет.
    private var title: String {
        let sameYear = Calendar.current.isDate(day, equalTo: .now, toGranularity: .year)
        let style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        return day.formatted(sameYear ? style : style.year())
    }

    var body: some View {
        let total = items.reduce(Decimal(0)) { $0 + (rates.value(of: $1, in: rates.base) ?? 0) }
        HStack {
            Text(title)
            Spacer()
            if total != 0 {
                MoneyText(amount: total, code: rates.base, colored: true, signed: true, weight: .semibold)
            }
        }
    }
}

extension LedgerTransaction {
    /// Обе половинки перевода с этим номером. Ищет в базе, а не в показанном списке: вторая половинка могла в него не попасть.
    static func halves(of id: UUID, in ctx: ModelContext) -> [LedgerTransaction] {
        (try? ctx.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.transferID == id }))) ?? []
    }
}
