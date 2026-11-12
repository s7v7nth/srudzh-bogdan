import SwiftUI
import SwiftData
import LedgerCore

/// Режим «уебанский интерфейс»: главный экран из кружков.
/// Сверху виджеты, ниже лента доходов, лента счетов и страницы категорий (по 2 ряда).
/// Кружок дохода тащим на счёт, счёт на категорию расхода, счёт на счёт (перевод).
/// Кольцо вокруг категории показывает, сколько израсходовано от бюджета.
struct ChaosHomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(RatesStore.self) private var rates
    @Query(sort: \Account.sortID) private var accounts: [Account]
    @Query(sort: \Category.sortID) private var categories: [Category]
    @Query private var budgets: [Budget]
    @Query(sort: \RecurringTransaction.nextDate) private var recurring: [RecurringTransaction]
    @AppStorage(scheduleWindowKey) private var windowDays = 7
    @AppStorage(goldRainKey) private var goldRain = true

    /// Перетаскивание, рамки кружков и кольца бюджета во время монеток. Экран их не читает,
    /// только кружки и мелкие модификаторы, поэтому прокрутка и движение пальца не пересчитывают суммы.
    @State private var live = ChaosLive()
    @State private var request: AddRequest?
    @State private var showSettings = false
    @State private var showWallet = false
    @State private var showNewAccount = false
    @State private var newCategory: NewCategory?
    @State private var editing = false
    @State private var isVisible = false
    @State private var showAll = false
    @State private var editingAccount: Account?
    @State private var editingCategory: Category?
    @State private var openLoan: Account?
    /// Перетаскивание, которое открыло окно операции: после сохранения из источника в получателя летят монетки.
    @State private var pendingDrop: (source: NodeID, target: NodeID)?
    @State private var dropSaved = false
    @State private var flight: CoinFlight?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let circle: CGFloat = 50
    private let nodeHeight: CGFloat = 98
    private let zoneTitleHeight: CGFloat = 26
    private let widgetHeight: CGFloat = 140
    private let space = "chaos"

    enum NodeID: Hashable { case account(PersistentIdentifier), category(UUID) }
    enum Zone: Hashable { case income, accounts, expenses }
    struct ScrollJump: Equatable { let target: PersistentIdentifier; let id = UUID() }

    struct AddRequest: Identifiable {
        let id = UUID()
        let type: TxType
        var from: Account? = nil
        var to: Account? = nil
        var category: Category? = nil
        var amount: Decimal? = nil
    }

    struct NewCategory: Identifiable { let id = UUID(); let isIncome: Bool }

    // MARK: Данные

    private var incomeList: [Category] {
        categories.filter { $0.parent == nil && $0.isIncome && !$0.archived && (editing || !$0.hiddenOnHome) }
    }
    private var expenseList: [Category] {
        categories.filter { $0.parent == nil && !$0.isIncome && !$0.archived && (editing || !$0.hiddenOnHome) }
    }
    private var accountList: [Account] { accounts.filter { editing || !$0.hiddenOnHome } }

    /// Всё, что экран показывает в цифрах, приходит из общего расчёта (`StatsStore`).
    private typealias Stats = LedgerStats

    /// Обычно сумма основных счетов; пока зажата кнопка в углу виджета, сумма всех счетов.
    private func netWorth(_ s: Stats) -> Decimal {
        accounts.filter { showAll || $0.isPrimary }.reduce(Decimal(0)) {
            $0 + (rates.convert(s.balance($1), from: $1.currency, to: rates.base) ?? 0)
        }
    }

    /// Остатки всех счетов по валютам, без пересчёта по курсу.
    private func perCurrency(_ s: Stats) -> [(code: String, amount: Decimal)] {
        Dictionary(grouping: accounts, by: \.currency)
            .map { ($0.key, $0.value.reduce(Decimal(0)) { $0 + s.balance($1) }) }
            .sorted { $0.0 < $1.0 }
    }

    private func budget(for c: Category) -> Budget? {
        budgets.first(where: { $0.categories.contains { $0.uuid == c.uuid || $0.familyIDs.contains(c.uuid) } })
    }

    /// Свежий расчёт прямо из базы: общий расчёт обновится только на следующем кадре,
    /// а монеткам цифра после сохранения нужна сразу. Вызывается один раз на перетаскивание.
    private func budgetRatio(of c: Category) -> Double? {
        guard let b = budget(for: c) else { return nil }
        let all = (try? ctx.fetch(FetchDescriptor<LedgerTransaction>())) ?? []
        return BudgetProgress.make(b, transactions: all, rates: rates)?.ratio
    }

    /// Платежи по расписанию, которые пора провести: просроченные и те, что попадают в выбранный период.
    private var dueItems: [RecurringTransaction] {
        let cal = Calendar.current
        let limit = cal.date(byAdding: .day, value: windowDays, to: cal.startOfDay(for: .now)) ?? .now
        return recurring.filter { $0.active && $0.nextDate < limit }
    }

    // MARK: Экран

    var body: some View {
        let stats = StatsStore.shared.value
        let live = live
        NavigationStack {
            // Экран рассчитан ровно на высоту телефона. Когда под окном операции поднимается клавиатура,
            // система урезает высоту, и навигация центрировала не влезающий экран: он уезжал вверх.
            // GeometryReader всегда кладёт содержимое от верхнего края, лишнее просто уходит вниз под окно.
            GeometryReader { _ in
            VStack(spacing: 6) {
                header
                PagedStrip(count: 3) { i in
                    switch i {
                    case 0: balanceWidget(stats)
                    case 1: scheduledWidget
                    default: budgetsWidget(stats)
                    }
                }
                .frame(height: 152)

                ribbon("chaos.zone.income", tint: ChaosPalette.income, zone: .income) {
                    ForEach(incomeList) { c in incomeNode(c, stats) }
                    addCell(color: ChaosPalette.incomeText) { newCategory = NewCategory(isIncome: true) }
                }
                ribbon("chaos.zone.accounts", tint: ChaosPalette.account, zone: .accounts) {
                    ForEach(accountList) { a in accountNode(a, stats) }
                    addCell(color: ChaosPalette.accountText) { showNewAccount = true }
                }
                categoryPages(stats)
                Spacer(minLength: 0)
            }
            }
            .modifier(DragScrollLock(live: live))
            .coordinateSpace(name: space)
            // Рамки нужны только жестам, поэтому лежат вне состояния экрана: прокрутка лент больше не перерисовывает экран.
            .onPreferenceChange(FramesKey.self) { live.frames = $0 }
            .onPreferenceChange(ZonesKey.self) { live.zones = $0 }
            .overlay(alignment: .topLeading) { DragGhost(live: live, size: circle) }
            .overlay(alignment: .topLeading) {
                if let f = flight {
                    CoinShower(flight: f, onLand: coinLanded).id(f.id).allowsHitTesting(false)
                }
            }
            .background(LongPressDragHost(
                enabled: isVisible && request == nil && !showSettings && !showWallet && !showNewAccount && newCategory == nil
                    && editingAccount == nil && editingCategory == nil && openLoan == nil,
                onBegan: { p in
                    guard let id = live.frames.first(where: { $0.value.contains(p) })?.key,
                          let color = color(of: id) else { return false }
                    live.groups = Dictionary(uniqueKeysWithValues: live.frames.keys.compactMap { k in group(k).map { (k, $0) } })
                    live.point = p; live.hovered = nil
                    live.ghostIcon = icon(of: id); live.ghostColor = color
                    live.source = id
                    startAutoScroll()
                    return true
                },
                onMoved: { p in
                    guard let id = live.source else { return }
                    live.point = p
                    let h = target(at: p, excluding: id)
                    if h != live.hovered { live.hovered = h }
                },
                onEnded: { p in if let id = live.source { drop(id, at: p) }; stopAutoScroll(); live.source = nil; live.hovered = nil },
                onCancelled: { stopAutoScroll(); live.source = nil; live.hovered = nil }
            ))
            .background(Color(.systemGroupedBackground))
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .navigationBarHidden(true)
            .sheet(item: $request, onDismiss: launchCoins) { r in
                AddTransactionView(type: r.type, toAccount: r.to, fromAccount: r.from, category: r.category, amount: r.amount) { dropSaved = true }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showWallet) { WalletView() }
            .sheet(isPresented: $showNewAccount) { AccountFormView(nextSort: accounts.count) }
            .sheet(item: $newCategory) { CategoryFormView(isIncome: $0.isIncome) }
            .sheet(item: $editingAccount) { AccountFormView(account: $0, nextSort: $0.sortID) }
            .sheet(item: $editingCategory) { CategoryFormView(category: $0, isIncome: $0.isIncome) }
            .sheet(item: $openLoan) { a in
                NavigationStack {
                    LoanView(account: a).toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("common.done") { openLoan = nil } }
                    }
                }
            }
            .modifier(DragFeedback(live: live))
        }
    }

    private var header: some View {
        HStack {
            Button { showSettings = true } label: { Image(systemName: "gearshape").font(.app(.title3)).frame(width: 44, height: 44, alignment: .leading) }
                .accessibilityLabel(Text("settings.title"))
            Button { showWallet = true } label: { Image(systemName: "wallet.pass").font(.app(.title3)).frame(width: 44, height: 44) }
                .accessibilityLabel(Text("wallet.title"))
            Spacer(minLength: 8)
            // Полный баннер не помещается: экран рассчитан ровно на высоту телефона и вылезал под часы и панель вкладок.
            BackupBanner(compact: true)
            Spacer(minLength: 8)
            Button {
                withAnimation(Motion.standard) { editing.toggle() }
            } label: {
                Text(editing ? "common.done" : "chaos.edit").font(.app(.subheadline, .semibold))
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(editing ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(editing ? Color.white : Color.primary)
            }
        }
        .padding(.horizontal, 12).frame(height: 36)
    }

    // MARK: Виджеты

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: widgetHeight)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            .padding(.horizontal, 12)
    }

    private func balanceWidget(_ stats: Stats) -> some View {
        let cache = stats.progress
        let left = cache.values.reduce(Decimal(0)) { $0 + (rates.convert($1.remaining, from: $1.currency, to: rates.base) ?? 0) }
        let worth = netWorth(stats)
        return card {
            VStack(alignment: .leading, spacing: 10) {
                Text(showAll ? "chaos.balance.all" : "chaos.balance").font(.app(.caption)).foregroundStyle(.secondary)
                MoneyText(amount: worth, code: rates.base, rolling: true).font(.system(size: 34, weight: .bold))
                    .foregroundStyle(worth < 0 ? TxType.expense.tint : Color.primary)
                if showAll {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(perCurrency(stats), id: \.code) { MoneyText(amount: $0.amount, code: $0.code).font(.app(.caption, .semibold)).foregroundStyle(.secondary) }
                        }
                    }
                    .frame(height: 16)
                } else {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label { Text("chaos.expenses") + Text(verbatim: " · " + Date.now.formatted(.dateTime.month(.wide))) }
                            icon: { Image(systemName: TxType.expense.glyph) }
                            .font(.app(.caption)).foregroundStyle(TxType.expense.tint)
                        MoneyText(amount: stats.monthExpenses, code: rates.base).font(.app(.subheadline, .semibold))
                    }
                    if !cache.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("widget.budgetsLeft").font(.app(.caption)).foregroundStyle(.secondary)
                            MoneyText(amount: left, code: rates.base).font(.app(.subheadline, .semibold))
                                .foregroundStyle(left < 0 ? BudgetState.over.tint : BudgetState.ok.tint)
                        }
                    }
                }
                }
            }
        }
        .overlay(alignment: .topTrailing) { showAllButton }
    }

    /// Кнопка-модификатор: пока держишь, виджет показывает все счета.
    private var showAllButton: some View {
        Image(systemName: showAll ? "eye.fill" : "eye")
            .font(.app(.subheadline)).foregroundStyle(showAll ? Color.white : Color.secondary)
            .frame(width: 34, height: 34)
            .background(showAll ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
            .padding(.top, 8).padding(.trailing, 20)
            .contentShape(Circle())
            .overlay(HoldCatcher { pressed in withAnimation(Motion.quick) { showAll = pressed } })
            .accessibilityLabel(Text("chaos.balance.showAll"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { withAnimation(Motion.quick) { showAll.toggle() } }
            .sensoryFeedback(.selection, trigger: showAll)
    }

    private var scheduledWidget: some View {
        let items = dueItems
        return card {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("widget.sched.title", systemImage: "repeat").font(.app(.caption, .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(fmt("widget.sched.next", windowDays)).font(.app(.caption)).foregroundStyle(.secondary)
                }
                if items.isEmpty {
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(BudgetState.ok.tint)
                        Text("widget.sched.empty").font(.app(.subheadline)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                } else {
                    ForEach(items.prefix(2)) { r in scheduledRow(r) }
                    if items.count > 2 {
                        Text(fmt("widget.sched.more", items.count - 2)).font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func scheduledRow(_ r: RecurringTransaction) -> some View {
        let overdue = r.nextDate < Calendar.current.startOfDay(for: .now)
        let today = Calendar.current.isDateInToday(r.nextDate)
        let tint: Color = overdue ? BudgetState.over.tint : (today ? BudgetState.warn.tint : .secondary)
        return HStack(spacing: 8) {
            TxTypeBadge(type: r.type, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(r.payee.isEmpty ? (r.category?.name ?? String(localized: "category.none")) : r.payee)
                    .font(.app(.subheadline)).lineLimit(1)
                Text((overdue ? String(localized: "widget.sched.overdue") + " · " : "") + r.nextDate.shortDay)
                    .font(.app(.caption2)).foregroundStyle(tint)
            }
            Spacer(minLength: 4)
            MoneyText(amount: r.amount, code: r.account?.currency ?? rates.base, colored: true).font(.app(.subheadline, .semibold))
            Button { r.skip() } label: { Image(systemName: "forward.circle").font(.app(.title3)).foregroundStyle(BudgetState.warn.tint) }
                .buttonStyle(.borderless).accessibilityLabel(Text("sched.skip"))
            Button { r.execute(in: ctx, rates: rates) } label: { Image(systemName: "checkmark.circle.fill").font(.app(.title3)).foregroundStyle(BudgetState.ok.tint) }
                .buttonStyle(.borderless).accessibilityLabel(Text("sched.execute"))
        }
    }

    private func budgetsWidget(_ stats: Stats) -> some View {
        let rows = budgets.compactMap { b in stats.progress(of: b).map { (b, $0) } }
            .sorted { $0.1.ratio > $1.1.ratio }.prefix(3)
        return card {
            VStack(alignment: .leading, spacing: 8) {
                Label("widget.risk.title", systemImage: "chart.pie.fill").font(.app(.caption, .semibold)).foregroundStyle(.secondary)
                if rows.isEmpty {
                    Spacer(minLength: 0)
                    Text("widget.risk.empty").font(.app(.subheadline)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(rows), id: \.0.persistentModelID) { b, p in
                        HStack(spacing: 8) {
                            Image(systemName: p.state.icon).foregroundStyle(p.state.tint)
                            Text(b.name).font(.app(.subheadline)).lineLimit(1).frame(width: 96, alignment: .leading)
                            ProgressView(value: min(p.ratio, 1)).tint(p.state.tint)
                            Text("\(Int(p.ratio * 100))%").font(.app(.caption).monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: Ленты и страницы

    /// Подпись зоны: цвет один и тот же слов не заменяет.
    private func zoneTitle(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.app(.caption2, .semibold)).textCase(.uppercase).tracking(0.6)
            .foregroundStyle(ChaosPalette.label)
            .padding(.leading, 20).padding(.top, 6).frame(height: zoneTitleHeight, alignment: .center)
    }

    private func ribbon<C: View>(_ title: LocalizedStringKey, tint: Color, zone: Zone, @ViewBuilder _ content: () -> C) -> some View {
        let row = HStack(alignment: .top, spacing: 0) { content() }
        return VStack(alignment: .leading, spacing: 0) {
            zoneTitle(title)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    row.scrollTargetLayout().padding(.horizontal, 8)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .modifier(RibbonJump(live: live, zone: zone, proxy: proxy))
            }
            .frame(height: nodeHeight)
        }
        .background(ChaosPalette.zone(tint))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(zoneFrame(zone))
        .padding(.horizontal, 12)
    }

    private func zoneFrame(_ zone: Zone) -> some View {
        GeometryReader { g in Color.clear.preference(key: ZonesKey.self, value: [zone: g.frame(in: .named(space))]) }
    }

    private enum Slot { case category(Category), add }

    private func categoryPages(_ stats: Stats) -> some View {
        let slots = expenseList.map(Slot.category) + [.add]
        let pages = stride(from: 0, to: slots.count, by: 8).map { Array(slots[$0 ..< min($0 + 8, slots.count)]) }
        return VStack(alignment: .leading, spacing: 0) {
            zoneTitle("chaos.zone.expenses")
            PagedStrip(count: pages.count, jump: { [live] in live.pageJump }) { i in
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: 4), spacing: 4) {
                    ForEach(Array(pages[i].enumerated()), id: \.offset) { _, slot in
                        switch slot {
                        case .category(let c): expenseNode(c, stats)
                        case .add: addCell(color: ChaosPalette.expenseText) { newCategory = NewCategory(isIncome: false) }
                        }
                    }
                }
                .padding(.horizontal, 8).frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(height: nodeHeight * 2 + 16)
        }
        .padding(.bottom, 8)
        .background(ChaosPalette.zone(ChaosPalette.expense))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(zoneFrame(.expenses))
        .padding(.horizontal, 12)
    }

    private func addCell(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(" ").font(.app(.caption))
                Color.clear.frame(width: circle, height: circle)
                    .overlay { Image(systemName: "plus").font(.app(.title3, .semibold)).foregroundStyle(color) }
                    .liquidGlass(tint: color.opacity(0.18))
                    .frame(width: circle + 12, height: circle + 12)
            }
            .frame(height: nodeHeight, alignment: .top)
            .containerRelativeFrame(.horizontal) { w, _ in (w - 16) / 4 }
        }
        .buttonStyle(.plain).modifier(DragDim(live: live))
        .accessibilityLabel(Text("chaos.add"))
    }

    // MARK: Кружки

    private func incomeNode(_ c: Category, _ stats: Stats) -> some View {
        node(.category(c.uuid), group: 1, title: c.name, icon: c.icon, color: ChaosPalette.income, text: ChaosPalette.incomeText,
             amount: stats.totals[c.uuid] ?? 0, code: rates.base, hidden: c.hiddenOnHome)
    }

    private func accountNode(_ a: Account, _ stats: Stats) -> some View {
        node(.account(a.persistentModelID), group: 0, title: a.name, icon: a.kind.icon, color: ChaosPalette.account, text: ChaosPalette.accountText,
             amount: stats.balance(a), code: a.currency, hidden: a.hiddenOnHome)
    }

    private func expenseNode(_ c: Category, _ stats: Stats) -> some View {
        node(.category(c.uuid), group: 2, title: c.name, icon: c.icon, color: ChaosPalette.expense, text: ChaosPalette.expenseText,
             amount: stats.totals[c.uuid] ?? 0, code: rates.base, progress: stats.progress(for: c), hidden: c.hiddenOnHome)
    }

    private func node(_ id: NodeID, group: Int, title: String, icon: String, color: Color, text: Color,
                      amount: Decimal, code: String, progress: BudgetProgress? = nil, hidden: Bool) -> some View {
        ChaosNode(id: id, group: group, title: title, icon: icon, color: color, text: text, amount: amount, code: code,
                  progress: progress, hidden: hidden, editing: editing, live: live, circle: circle, height: nodeHeight, space: space,
                  onTap: { tap(id) }, onToggleHidden: { toggleHidden(id) })
    }

    private func center(_ finger: CGPoint) -> CGPoint { Self.center(finger) }
    fileprivate static func center(_ finger: CGPoint) -> CGPoint { CGPoint(x: finger.x, y: finger.y - 36) }

    // MARK: Логика перетаскивания

    private func account(_ id: NodeID) -> Account? {
        if case .account(let pid) = id { accounts.first { $0.persistentModelID == pid } } else { nil }
    }
    private func category(_ id: NodeID) -> Category? {
        if case .category(let u) = id { categories.first { $0.uuid == u } } else { nil }
    }
    private func color(of id: NodeID) -> Color? {
        if account(id) != nil { return ChaosPalette.account }
        if let c = category(id) { return c.isIncome ? ChaosPalette.income : ChaosPalette.expense }
        return nil
    }
    private func icon(of id: NodeID) -> String { account(id)?.kind.icon ?? category(id)?.icon ?? "circle" }

    /// 0 счета, 1 доходы, 2 расходы: порядок меняется только внутри группы.
    private func group(_ id: NodeID) -> Int? {
        if account(id) != nil { return 0 }
        if let c = category(id) { return c.isIncome ? 1 : 2 }
        return nil
    }

    /// Что получится, если отпустить `source` над `target`. nil, если пара не имеет смысла.
    private func request(from source: NodeID, to target: NodeID) -> AddRequest? {
        if let a = account(source), let b = account(target), a !== b {
            // Перевод на кредит: подставляем сумму ежемесячного платежа.
            let payment = b.isLoan ? recurring.first { $0.active && $0.toAccount?.persistentModelID == b.persistentModelID }.map { abs($0.amount) } : nil
            return AddRequest(type: .transfer, from: a, to: b, amount: payment)
        }
        if let a = account(source), let c = category(target), !c.isIncome { return AddRequest(type: .expense, from: a, category: c) }
        if let c = category(source), c.isIncome, let a = account(target) { return AddRequest(type: .income, from: a, category: c) }
        return nil
    }

    /// Можно ли бросить кружок группы `s` на кружок группы `t` (0 счета, 1 доходы, 2 расходы).
    /// Совпадает с `request(from:to:)`: счёт на счёт или расход, доход на счёт; в правке только внутри группы.
    static func canDrop(_ s: Int?, onto t: Int?, editing: Bool) -> Bool {
        guard let s, let t else { return false }
        if editing { return s == t }
        return (s == 0 && (t == 0 || t == 2)) || (s == 1 && t == 0)
    }

    /// Вызывается на каждое движение пальца, поэтому группы берутся из готового словаря, без поиска по базе.
    private func target(at finger: CGPoint, excluding source: NodeID) -> NodeID? {
        let p = center(finger)
        // Кружки, уехавшие за край ленты, не видны, но их рамки остаются: попадание считаем только внутри зон.
        guard live.zones.values.contains(where: { $0.contains(p) }) else { return nil }
        let s = live.groups[source]
        return live.frames.first {
            $0.key != source && $0.value.insetBy(dx: -4, dy: -4).contains(p) && Self.canDrop(s, onto: live.groups[$0.key], editing: editing)
        }?.key
    }

    private func drop(_ source: NodeID, at finger: CGPoint) {
        guard let t = target(at: finger, excluding: source) else { return }
        if editing { reorder(source, onto: t); return }
        request = self.request(from: source, to: t)
        guard request != nil else { return }
        pendingDrop = (source, t)
        dropSaved = false
        if let c = category(t), let r = StatsStore.shared.value.progress(for: c)?.ratio { live.rings[c.uuid] = r }
    }

    // MARK: Прокрутка у края

    /// Ширина полосы у края ленты, где задержка кружка листает ленту.
    private let edgeWidth: CGFloat = 34

    /// Пока кружок держат у левого или правого края ленты, она сдвигается на один кружок (страницы расходов на страницу).
    private func startAutoScroll() {
        live.autoScroll?.cancel()
        live.autoScroll = Task { @MainActor in
            var held = 0
            var lastEdge: (Zone, Int)?
            while !Task.isCancelled, let id = live.source {
                try? await Task.sleep(for: .milliseconds(150))
                guard let edge = edge(at: center(live.point)) else { held = 0; lastEdge = nil; continue }
                if let l = lastEdge, l.0 == edge.0, l.1 == edge.1 { held += 1 } else { held = 1; lastEdge = edge }
                // Первая прокрутка через ~0,45 с, чтобы не листать, когда целятся в крайний кружок; дальше так же каждые 0,45 с.
                guard held >= 3 else { continue }
                held = 0
                // Блокировка прокрутки на время перетаскивания гасит и прокрутку из кода, поэтому на время сдвига её снимаем.
                // Палец уже не может подхватить ленту: её жест не начался, пока она была заблокирована.
                live.autoScrolling = true
                try? await Task.sleep(for: .milliseconds(30))
                let moved = scroll(edge.0, by: edge.1)
                if moved { try? await Task.sleep(for: .milliseconds(350)) }
                live.autoScrolling = false
                if moved {
                    UISelectionFeedbackGenerator().selectionChanged()
                    let h = target(at: live.point, excluding: id)
                    if h != live.hovered { live.hovered = h }
                }
            }
        }
    }

    private func stopAutoScroll() { live.autoScroll?.cancel(); live.autoScroll = nil; live.autoScrolling = false }

    private func edge(at p: CGPoint) -> (Zone, Int)? {
        for (zone, r) in live.zones where p.y >= r.minY && p.y <= r.maxY {
            if p.x < r.minX + edgeWidth { return (zone, -1) }
            if p.x > r.maxX - edgeWidth { return (zone, 1) }
        }
        return nil
    }

    /// Сдвигает зону на шаг. false, если дальше некуда.
    private func scroll(_ zone: Zone, by step: Int) -> Bool {
        switch zone {
        case .income: return shift(.income, items: incomeList.map { ($0.persistentModelID, NodeID.category($0.uuid)) }, by: step)
        case .accounts: return shift(.accounts, items: accountList.map { ($0.persistentModelID, NodeID.account($0.persistentModelID)) }, by: step)
        case .expenses:
            guard let left = live.zones[.expenses]?.minX else { return false }
            let pages = (expenseList.count + 1 + 7) / 8
            let first = expenseList.firstIndex { live.frames[.category($0.uuid)].map { $0.midX > left } ?? false } ?? 0
            let now = first / 8
            let next = min(max(now + step, 0), max(pages - 1, 0))
            guard next != now else { return false }
            live.pageJump = PageJump(page: next)
            return true
        }
    }

    /// В ленте видно 4 ячейки, последняя ячейка «плюс»: левым может стоять кружок не дальше `ids.count + 1 - 4`.
    /// Текущий левый кружок берём по рамкам на экране: так верно и после ручной прокрутки.
    private func shift(_ zone: Zone, items: [(id: PersistentIdentifier, node: NodeID)], by step: Int) -> Bool {
        guard let left = live.zones[zone]?.minX else { return false }
        let now = items.firstIndex { live.frames[$0.node].map { $0.midX > left } ?? false } ?? 0
        let next = min(max(now + step, 0), max(items.count + 1 - 4, 0))
        guard next != now, items.indices.contains(next) else { return false }
        live.jumps[zone] = ScrollJump(target: items[next].id)
        return true
    }

    // MARK: Монетки

    /// Центр кружка внутри ячейки: под подписью высотой 15 и отступом 3.
    private func bubbleCenter(_ id: NodeID) -> CGPoint? {
        live.frames[id].map { CGPoint(x: $0.midX, y: $0.minY + 18 + (circle + 12) / 2) }
    }

    /// Окно операции закрылось: если сохранили, запускаем монетки, если отменили, возвращаем кольцо как было.
    private func launchCoins() {
        guard let d = pendingDrop else { return }
        pendingDrop = nil
        let saved = dropSaved
        dropSaved = false
        let held = category(d.target).flatMap { c in live.rings[c.uuid].map { (c, $0) } }
        guard saved, let from = bubbleCenter(d.source), let to = bubbleCenter(d.target) else {
            if let (c, _) = held { live.rings[c.uuid] = nil }
            return
        }
        let end = held.flatMap { budgetRatio(of: $0.0) }
        if reduceMotion || !goldRain {
            if let (c, _) = held { withAnimation(Motion.standard) { live.rings[c.uuid] = nil } }
            return
        }
        flight = CoinFlight(from: from, to: to, count: 9, category: held?.0.uuid, start: held?.1 ?? 0, end: end ?? 0)
    }

    /// Монетка долетела: кольцо получателя подрастает на свою долю, последняя монетка отпускает кольцо.
    private func coinLanded(_ index: Int) {
        guard let f = flight else { return }
        Haptics.coin()
        if let u = f.category {
            let k = Double(index + 1) / Double(f.count)
            withAnimation(Motion.quick) { live.rings[u] = f.start + (f.end - f.start) * k }
        }
        if index == f.count - 1 {
            if let u = f.category { live.rings[u] = nil }
            flight = nil
        }
    }

    /// Ставит `source` на место `target`, остальные сдвигаются.
    private func reorder(_ source: NodeID, onto target: NodeID) {
        let ids: [NodeID]
        switch group(source) {
        case 0: ids = accountList.map { .account($0.persistentModelID) }
        case 1: ids = incomeList.map { .category($0.uuid) }
        default: ids = expenseList.map { .category($0.uuid) }
        }
        guard let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: target) else { return }
        var order = ids
        order.remove(at: from); order.insert(source, at: to)
        withAnimation(Motion.standard) {
            for (i, id) in order.enumerated() {
                if let a = account(id) { a.sortID = i } else if let c = category(id) { c.sortID = i }
            }
        }
    }

    private func toggleHidden(_ id: NodeID) {
        if let a = account(id) { a.hiddenOnHome.toggle() } else if let c = category(id) { c.hiddenOnHome.toggle() }
    }

    private func tap(_ id: NodeID) {
        if editing {
            if let a = account(id) { editingAccount = a } else if let c = category(id) { editingCategory = c }
            return
        }
        if let a = account(id) { if a.isLoan { openLoan = a } else { request = AddRequest(type: .expense, from: a) } }
        else if let c = category(id) {
            request = c.isIncome ? AddRequest(type: .income, from: accounts.first, category: c)
                                 : AddRequest(type: .expense, from: accounts.first, category: c)
        }
    }

    fileprivate struct ZonesKey: PreferenceKey {
        static let defaultValue: [Zone: CGRect] = [:]
        static func reduce(value: inout [Zone: CGRect], nextValue: () -> [Zone: CGRect]) { value.merge(nextValue()) { $1 } }
    }

    fileprivate struct FramesKey: PreferenceKey {
        static let defaultValue: [NodeID: CGRect] = [:]
        static func reduce(value: inout [NodeID: CGRect], nextValue: () -> [NodeID: CGRect]) { value.merge(nextValue()) { $1 } }
    }
}

/// Быстро меняющееся состояние главного экрана. Каждое свойство читают только те кусочки, которым оно нужно:
/// точку пальца только призрак, цель под пальцем только кружки. Сам экран с суммами при этом не пересчитывается.
@Observable final class ChaosLive {
    /// Что тащим и над чем держим.
    var source: ChaosHomeView.NodeID?
    var hovered: ChaosHomeView.NodeID?
    var point: CGPoint = .zero
    var ghostIcon = "circle"
    var ghostColor = Color.clear
    /// Кольцо бюджета, пока летят монетки: держит старое значение и растёт с каждой упавшей монеткой.
    var rings: [UUID: Double] = [:]
    /// Рамки кружков меняются на каждом кадре прокрутки, а нужны только жестам: их никто не отслеживает.
    @ObservationIgnored var frames: [ChaosHomeView.NodeID: CGRect] = [:]
    /// Группа каждого кружка на время перетаскивания (0 счета, 1 доходы, 2 расходы).
    @ObservationIgnored var groups: [ChaosHomeView.NodeID: Int] = [:]
    /// Рамки зон (лент и страниц расходов): у их краёв лента листается сама.
    @ObservationIgnored var zones: [ChaosHomeView.Zone: CGRect] = [:]
    @ObservationIgnored var autoScroll: Task<Void, Never>?
    /// Пока идёт сдвиг ленты из кода, блокировка прокрутки снята.
    var autoScrolling = false
    /// Куда докрутить ленту или страницы расходов. Запись в `scrollPosition` ленту не двигает, поэтому крутим через `ScrollViewReader`.
    var jumps: [ChaosHomeView.Zone: ChaosHomeView.ScrollJump] = [:]
    var pageJump: PageJump?
}

/// Докручивает ленту, когда перетаскивание просит сдвиг. Отдельный модификатор, чтобы сдвиг не перерисовывал весь экран.
private struct RibbonJump: ViewModifier {
    let live: ChaosLive
    let zone: ChaosHomeView.Zone
    let proxy: ScrollViewProxy
    func body(content: Content) -> some View {
        content.onChange(of: live.jumps[zone]) { _, jump in
            guard let jump else { return }
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(jump.target, anchor: .leading) }
        }
    }
}

/// Кружок, который едет за пальцем (чуть выше, чтобы палец его не закрывал).
private struct DragGhost: View {
    let live: ChaosLive
    let size: CGFloat

    var body: some View {
        if live.source != nil {
            Color.clear.frame(width: size, height: size)
                .overlay { Image(systemName: live.ghostIcon).font(.system(size: 22, weight: .medium)).foregroundStyle(.white) }
                .liquidGlass(tint: live.ghostColor)
                .shadow(color: live.ghostColor.opacity(0.4), radius: 12, y: 8)
                .scaleEffect(1.1)
                .position(ChaosHomeView.center(live.point))
                .allowsHitTesting(false)
        }
    }
}

/// Пока тащим кружок, ленты и страницы не прокручиваются.
private struct DragScrollLock: ViewModifier {
    let live: ChaosLive
    func body(content: Content) -> some View { content.scrollDisabled(live.source != nil && !live.autoScrolling) }
}

/// Кнопки «+» бледнеют, пока тащим кружок.
private struct DragDim: ViewModifier {
    let live: ChaosLive
    func body(content: Content) -> some View { content.opacity(live.source == nil ? 1 : 0.3) }
}

/// Отклик вибрацией: подхватили кружок, навели на цель.
private struct DragFeedback: ViewModifier {
    let live: ChaosLive
    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(weight: .medium), trigger: live.hovered)
            .sensoryFeedback(.selection, trigger: live.source)
    }
}

/// Один кружок: подпись, стеклянный шарик с кольцом бюджета и сумма.
/// Отдельный вид, чтобы наведение пальца перерисовывало только кружки, а не весь экран.
private struct ChaosNode: View {
    let id: ChaosHomeView.NodeID
    let group: Int
    let title: String
    let icon: String
    let color: Color
    let text: Color
    let amount: Decimal
    let code: String
    let progress: BudgetProgress?
    let hidden: Bool
    let editing: Bool
    let live: ChaosLive
    let circle: CGFloat
    let height: CGFloat
    let space: String
    let onTap: () -> Void
    let onToggleHidden: () -> Void

    var body: some View {
        let zero = amount == 0
        let alert = progress.map { $0.state != .ok } ?? false
        let valueColor: Color = amount < 0 ? TxType.expense.tint : (alert ? progress!.state.tint : text)
        let isHover = live.hovered == id
        let isSource = live.source == id
        let dimmed = live.source.map { $0 != id && !ChaosHomeView.canDrop(live.groups[$0], onto: group, editing: editing) } ?? false
        VStack(spacing: 3) {
            Text(title).font(.app(.caption)).foregroundStyle(ChaosPalette.label).lineLimit(1).minimumScaleFactor(0.8)
                .frame(height: 15)
            bubble(ring: progress == nil ? nil : uuid.flatMap { live.rings[$0] })
                .opacity(zero && progress == nil ? 0.7 : 1)
                .scaleEffect(isHover ? 1.08 : (isSource ? 0.94 : 1))
                .overlay { if isHover { Circle().stroke(color, lineWidth: 3).frame(width: circle + 20, height: circle + 20) } }
                .overlay(alignment: .topLeading) { if editing { hideBadge } }
                .animation(Motion.quick, value: isHover)
            // Пустая категория: прочерк вместо ряда «0,00», чтобы взгляд цеплялся только за реальные траты.
            if zero, case .category = id {
                Text(verbatim: "—").font(.app(.caption, .bold)).foregroundStyle(text).opacity(0.4)
                    .accessibilityLabel(Text(verbatim: MoneyText.plain(0, code: code)))
            } else {
                MoneyText(amount: amount, code: code).font(.app(.caption, .bold)).foregroundStyle(valueColor)
                    .brightness(amount < 0 || alert ? -0.15 : 0).opacity(zero ? 0.5 : 1).lineLimit(1).minimumScaleFactor(0.85)
            }
        }
        .frame(height: height, alignment: .top)
        .containerRelativeFrame(.horizontal) { w, _ in (w - 16) / 4 }
        .opacity(isSource ? 0.35 : (dimmed ? 0.4 : (hidden ? 0.45 : 1)))
        .background(GeometryReader { g in
            Color.clear.preference(key: ChaosHomeView.FramesKey.self, value: [id: g.frame(in: .named(space))])
        })
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var uuid: UUID? { if case .category(let u) = id { u } else { nil } }

    private var hideBadge: some View {
        Button(action: onToggleHidden) {
            Image(systemName: hidden ? "plus.circle.fill" : "minus.circle.fill")
                .font(.system(size: 20)).symbolRenderingMode(.palette)
                .foregroundStyle(.white, hidden ? BudgetState.ok.tint : BudgetState.over.tint)
        }
        .buttonStyle(.plain).offset(x: -2, y: -2)
    }

    /// `held` подменяет долю бюджета, пока в кружок летят монетки.
    private func bubble(ring held: Double?) -> some View {
        let ring = circle + 12
        return ZStack {
            if let p = progress {
                let ratio = held ?? p.ratio
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 4).frame(width: ring, height: ring)
                Circle().trim(from: 0, to: CGFloat(min(max(ratio, 0.02), 1)))
                    .stroke(BudgetState(ratio: ratio).tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: ring, height: ring)
            }
            Color.clear.frame(width: circle, height: circle)
                .overlay { Image(systemName: icon).font(.system(size: 22, weight: .medium)).foregroundStyle(.white).shadow(color: color.opacity(0.6), radius: 3, y: 1) }
                .liquidGlass(tint: color)
        }
        .frame(width: ring, height: ring)
    }
}

struct PageJump: Equatable {
    let page: Int
    let id = UUID()
}

/// Горизонтальные страницы с точками внизу.
struct PagedStrip<Content: View>: View {
    let count: Int
    var lockScroll = false
    /// Перелистывание снаружи (кружок держат у края страницы). Читается внутри, чтобы не перерисовывать родителя.
    var jump: (() -> PageJump?)? = nil
    @ViewBuilder let content: (Int) -> Content
    @State private var page: Int? = 0

    var body: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(0 ..< max(count, 1), id: \.self) { i in
                            content(i).containerRelativeFrame(.horizontal).id(i)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollClipDisabled()
                .scrollDisabled(lockScroll)
                // Запись в `scrollPosition` страницу не двигает, поэтому листаем через `ScrollViewReader`.
                .onChange(of: jump?()) { _, j in
                    guard let j else { return }
                    page = j.page
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(j.page, anchor: .leading) }
                }
            }
            if count > 1 {
                HStack(spacing: 6) {
                    ForEach(0 ..< count, id: \.self) { i in
                        Circle().fill(i == (page ?? 0) ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                    }
                }
            }
        }
    }
}

/// Мгновенное «зажато / отпущено» для кнопки внутри прокручиваемых страниц.
/// SwiftUI-жест внутри ScrollView срабатывает с задержкой около секунды, UIKit-распознаватель реагирует сразу.
struct HoldCatcher: UIViewRepresentable {
    var onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let r = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        r.minimumPressDuration = 0
        r.allowableMovement = .greatestFiniteMagnitude
        r.cancelsTouchesInView = false
        r.delegate = context.coordinator
        v.addGestureRecognizer(r)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.onChange = onChange }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChange: (Bool) -> Void
        init(_ onChange: @escaping (Bool) -> Void) { self.onChange = onChange }

        @objc func handle(_ r: UILongPressGestureRecognizer) {
            switch r.state {
            case .began: onChange(true)
            case .ended, .cancelled, .failed: onChange(false)
            default: break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Долгое нажатие на весь экран: подхватывает кружок под пальцем и ведёт его, не мешая прокрутке лент и страниц.
/// Обычный жест на каждом кружке перехватывал прокрутку, поэтому распознаватель повешен на окно.
struct LongPressDragHost: UIViewRepresentable {
    var enabled: Bool
    var onBegan: (CGPoint) -> Bool
    var onMoved: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onCancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.isUserInteractionEnabled = false
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ uiView: HostView, context: Context) { context.coordinator.parent = self }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) { coordinator.detach() }

    final class HostView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window, host: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: LongPressDragHost
        private let recognizer = UILongPressGestureRecognizer()
        private weak var host: UIView?
        private var grabbed = false

        init(_ parent: LongPressDragHost) {
            self.parent = parent
            super.init()
            recognizer.minimumPressDuration = 0.2
            recognizer.allowableMovement = 10
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handle(_:)))
        }

        func attach(to window: UIWindow?, host: UIView) {
            self.host = host
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        func detach() { recognizer.view?.removeGestureRecognizer(recognizer) }

        @objc private func handle(_ r: UILongPressGestureRecognizer) {
            guard let host else { return }
            let p = r.location(in: host)
            switch r.state {
            case .began: grabbed = parent.onBegan(p)
            case .changed: if grabbed { parent.onMoved(p) }
            case .ended: if grabbed { parent.onEnded(p) }; grabbed = false
            case .cancelled, .failed: if grabbed { parent.onCancelled() }; grabbed = false
            default: break
            }
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard parent.enabled, let host else { return false }
            return host.bounds.contains(g.location(in: host))
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}


// MARK: Монетки между кружками

struct CoinFlight: Identifiable {
    let id = UUID()
    let from: CGPoint
    let to: CGPoint
    let count: Int
    /// Категория с бюджетом, чьё кольцо растёт от `start` до `end` по мере падения монеток.
    let category: UUID?
    let start: Double
    let end: Double
}

/// Горсть монеток: вылетают из кружка-источника по очереди и одной ровной дугой падают в получателя.
private struct CoinShower: View {
    let flight: CoinFlight
    let onLand: (Int) -> Void

    var body: some View {
        ZStack {
            ForEach(0..<flight.count, id: \.self) { i in
                Coin(from: flight.from, to: flight.to,
                     lift: 80, delay: Double(i) * 0.05) { onLand(i) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Coin: View {
    let from: CGPoint
    let to: CGPoint
    let lift: CGFloat
    let delay: Double
    let onLand: () -> Void
    @State private var t: CGFloat = 0

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [ChaosPalette.coinLight, ChaosPalette.coinDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(ChaosPalette.coinRim, lineWidth: 1.5).padding(3))
            .frame(width: 18, height: 18)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .modifier(ArcFlight(t: t, from: from, to: to, lift: lift))
            .onAppear {
                withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 0.42).delay(delay)) { t = 1 } completion: { onLand() }
            }
    }
}

/// Положение монетки на дуге (квадратичная кривая через точку над серединой пути), с уменьшением в конце.
private struct ArcFlight: ViewModifier, Animatable {
    var t: CGFloat
    let from: CGPoint
    let to: CGPoint
    let lift: CGFloat

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let c = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - lift)
        let u = 1 - t
        let p = CGPoint(x: u * u * from.x + 2 * u * t * c.x + t * t * to.x,
                        y: u * u * from.y + 2 * u * t * c.y + t * t * to.y)
        let scale = t < 0.15 ? 0.5 + t / 0.15 * 0.5 : (t > 0.8 ? 1 - (t - 0.8) / 0.2 * 0.5 : 1)
        content
            .scaleEffect(scale)
            .opacity(t <= 0 || t >= 1 ? 0 : 1)
            .position(p)
    }
}
