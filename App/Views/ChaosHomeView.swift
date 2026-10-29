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
    @Query private var transactions: [LedgerTransaction]
    @Query(sort: \RecurringTransaction.nextDate) private var recurring: [RecurringTransaction]
    @AppStorage(scheduleWindowKey) private var windowDays = 7
    @AppStorage(goldRainKey) private var goldRain = true

    @State private var frames: [NodeID: CGRect] = [:]
    /// Что тащим и над чем держим. Сама точка пальца живёт в `finger`: её читает только кружок-призрак,
    /// поэтому движение пальца не пересчитывает весь экран.
    @State private var dragID: NodeID?
    @State private var hovered: NodeID?
    @State private var finger = FingerPoint()
    @State private var request: AddRequest?
    @State private var showSettings = false
    @State private var showNewAccount = false
    @State private var newCategory: NewCategory?
    @State private var editing = false
    @State private var isVisible = false
    @State private var showAll = false
    @State private var editingAccount: Account?
    @State private var editingCategory: Category?
    /// Перетаскивание, которое открыло окно операции: после сохранения из источника в получателя летят монетки.
    @State private var pendingDrop: (source: NodeID, target: NodeID)?
    @State private var dropSaved = false
    @State private var flight: CoinFlight?
    /// Кольцо бюджета, пока летят монетки: держит старое значение и растёт с каждой упавшей монеткой.
    @State private var ringHold: [UUID: Double] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let circle: CGFloat = 50
    private let nodeHeight: CGFloat = 98
    private let zoneTitleHeight: CGFloat = 26
    private let widgetHeight: CGFloat = 140
    private let space = "chaos"

    enum NodeID: Hashable { case account(PersistentIdentifier), category(UUID) }

    struct AddRequest: Identifiable {
        let id = UUID()
        let type: TxType
        var from: Account? = nil
        var to: Account? = nil
        var category: Category? = nil
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

    /// Суммы за текущий месяц по категориям (с подкатегориями), в основной валюте.
    private var monthTotals: [UUID: Decimal] {
        guard let month = Calendar.current.dateInterval(of: .month, for: .now) else { return [:] }
        var own: [UUID: Decimal] = [:]
        for t in transactions where t.type != .transfer && month.contains(t.date) {
            guard let c = t.category, let v = rates.value(of: t, in: rates.base) else { continue }
            own[c.uuid, default: 0] += abs(v)
        }
        var result: [UUID: Decimal] = [:]
        for c in categories where c.parent == nil {
            result[c.uuid] = own[c.uuid, default: 0] + c.children.reduce(Decimal(0)) { $0 + own[$1.uuid, default: 0] }
        }
        return result
    }

    private var monthExpenses: Decimal {
        guard let month = Calendar.current.dateInterval(of: .month, for: .now) else { return 0 }
        return transactions.filter { $0.type == .expense && month.contains($0.date) }
            .reduce(Decimal(0)) { $0 + abs(rates.value(of: $1, in: rates.base) ?? 0) }
    }

    /// Обычно сумма основных счетов; пока зажата кнопка в углу виджета, сумма всех счетов.
    private var netWorth: Decimal {
        accounts.filter { showAll || $0.isPrimary }.reduce(Decimal(0)) {
            $0 + (rates.convert(balance(of: $1), from: $1.currency, to: rates.base) ?? 0)
        }
    }

    /// Остатки всех счетов по валютам, без пересчёта по курсу.
    private var perCurrency: [(code: String, amount: Decimal)] {
        Dictionary(grouping: accounts, by: \.currency)
            .map { ($0.key, $0.value.reduce(Decimal(0)) { $0 + balance(of: $1) }) }
            .sorted { $0.0 < $1.0 }
    }

    private func budget(for c: Category) -> Budget? {
        budgets.first(where: { $0.categories.contains { $0.uuid == c.uuid || $0.familyIDs.contains(c.uuid) } })
    }

    private func progress(for c: Category, in cache: [PersistentIdentifier: BudgetProgress]) -> BudgetProgress? {
        budget(for: c).flatMap { cache[$0.persistentModelID] }
    }

    private func budgetRatio(of c: Category) -> Double? {
        budget(for: c).flatMap { BudgetProgress.make($0, transactions: transactions, rates: rates)?.ratio }
    }

    /// Платежи по расписанию, которые пора провести: просроченные и те, что попадают в выбранный период.
    private var dueItems: [RecurringTransaction] {
        let cal = Calendar.current
        let limit = cal.date(byAdding: .day, value: windowDays, to: cal.startOfDay(for: .now)) ?? .now
        return recurring.filter { $0.active && $0.nextDate < limit }
    }

    // MARK: Экран

    var body: some View {
        let totals = monthTotals
        let cache = Dictionary(uniqueKeysWithValues: budgets.compactMap { b in
            BudgetProgress.make(b, transactions: transactions, rates: rates).map { (b.persistentModelID, $0) }
        })
        NavigationStack {
            VStack(spacing: 6) {
                header
                PagedStrip(count: 3) { i in
                    switch i {
                    case 0: balanceWidget(cache)
                    case 1: scheduledWidget
                    default: budgetsWidget(cache)
                    }
                }
                .frame(height: 152)

                ribbon("chaos.zone.income", tint: ChaosPalette.income) {
                    ForEach(incomeList) { c in incomeNode(c, totals) }
                    addCell(color: ChaosPalette.incomeText) { newCategory = NewCategory(isIncome: true) }
                }
                ribbon("chaos.zone.accounts", tint: ChaosPalette.account) {
                    ForEach(accountList) { a in accountNode(a) }
                    addCell(color: ChaosPalette.accountText) { showNewAccount = true }
                }
                categoryPages(totals, cache)
                Spacer(minLength: 0)
            }
            .coordinateSpace(name: space)
            .onPreferenceChange(FramesKey.self) { frames = $0 }
            .overlay(alignment: .topLeading) { ghost }
            .overlay(alignment: .topLeading) {
                if let f = flight {
                    CoinShower(flight: f, onLand: coinLanded).id(f.id).allowsHitTesting(false)
                }
            }
            .background(LongPressDragHost(
                enabled: isVisible && request == nil && !showSettings && !showNewAccount && newCategory == nil
                    && editingAccount == nil && editingCategory == nil,
                onBegan: { p in
                    guard let id = frames.first(where: { $0.value.contains(p) })?.key else { return false }
                    finger.point = p; hovered = nil; dragID = id; return true
                },
                onMoved: { p in
                    guard let id = dragID else { return }
                    finger.point = p
                    let h = target(at: p, excluding: id)
                    if h != hovered { hovered = h }
                },
                onEnded: { p in if let id = dragID { drop(id, at: p) }; dragID = nil; hovered = nil },
                onCancelled: { dragID = nil; hovered = nil }
            ))
            .background(Color(.systemGroupedBackground))
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .navigationBarHidden(true)
            .sheet(item: $request, onDismiss: launchCoins) { r in
                AddTransactionView(type: r.type, toAccount: r.to, fromAccount: r.from, category: r.category) { dropSaved = true }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showNewAccount) { AccountFormView(nextSort: accounts.count) }
            .sheet(item: $newCategory) { CategoryFormView(isIncome: $0.isIncome) }
            .sheet(item: $editingAccount) { AccountFormView(account: $0, nextSort: $0.sortID) }
            .sheet(item: $editingCategory) { CategoryFormView(category: $0, isIncome: $0.isIncome) }
            .sensoryFeedback(.impact(weight: .medium), trigger: hovered)
            .sensoryFeedback(.selection, trigger: dragID)
        }
    }

    private var header: some View {
        HStack {
            Button { showSettings = true } label: { Image(systemName: "gearshape").font(.app(.title3)).frame(width: 44, height: 44, alignment: .leading) }
                .accessibilityLabel(Text("settings.title"))
            Spacer(minLength: 8)
            // Полный баннер не помещается: экран рассчитан ровно на высоту телефона и вылезал под часы и панель вкладок.
            BackupBanner(compact: true)
            Spacer(minLength: 8)
            Button {
                withAnimation(.spring(duration: 0.25)) { editing.toggle() }
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

    private func balanceWidget(_ cache: [PersistentIdentifier: BudgetProgress]) -> some View {
        let left = cache.values.reduce(Decimal(0)) { $0 + (rates.convert($1.remaining, from: $1.currency, to: rates.base) ?? 0) }
        return card {
            VStack(alignment: .leading, spacing: 10) {
                Text(showAll ? "chaos.balance.all" : "chaos.balance").font(.app(.caption)).foregroundStyle(.secondary)
                MoneyText(amount: netWorth, code: rates.base).font(.system(size: 34, weight: .bold))
                    .foregroundStyle(netWorth < 0 ? TxType.expense.tint : Color.primary)
                    .contentTransition(.numericText())
                if showAll {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(perCurrency, id: \.code) { MoneyText(amount: $0.amount, code: $0.code).font(.app(.caption, .semibold)).foregroundStyle(.secondary) }
                        }
                    }
                    .frame(height: 16)
                } else {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label { Text("chaos.expenses") + Text(verbatim: " · " + Date.now.formatted(.dateTime.month(.wide))) }
                            icon: { Image(systemName: TxType.expense.glyph) }
                            .font(.app(.caption)).foregroundStyle(TxType.expense.tint)
                        MoneyText(amount: monthExpenses, code: rates.base).font(.app(.subheadline, .semibold))
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
            .overlay(HoldCatcher { pressed in withAnimation(.snappy(duration: 0.2)) { showAll = pressed } })
            .accessibilityLabel(Text("chaos.balance.showAll"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { withAnimation { showAll.toggle() } }
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

    private func budgetsWidget(_ cache: [PersistentIdentifier: BudgetProgress]) -> some View {
        let rows = budgets.compactMap { b in cache[b.persistentModelID].map { (b, $0) } }
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

    private func ribbon<C: View>(_ title: LocalizedStringKey, tint: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            zoneTitle(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) { content() }
                    .scrollTargetLayout().padding(.horizontal, 8)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .scrollDisabled(dragID != nil)
            .frame(height: nodeHeight)
        }
        .background(ChaosPalette.zone(tint))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
    }

    private enum Slot { case category(Category), add }

    private func categoryPages(_ totals: [UUID: Decimal], _ cache: [PersistentIdentifier: BudgetProgress]) -> some View {
        let slots = expenseList.map(Slot.category) + [.add]
        let pages = stride(from: 0, to: slots.count, by: 8).map { Array(slots[$0 ..< min($0 + 8, slots.count)]) }
        return VStack(alignment: .leading, spacing: 0) {
            zoneTitle("chaos.zone.expenses")
            PagedStrip(count: pages.count, lockScroll: dragID != nil) { i in
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: 4), spacing: 4) {
                    ForEach(Array(pages[i].enumerated()), id: \.offset) { _, slot in
                        switch slot {
                        case .category(let c): expenseNode(c, totals, cache)
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
        .buttonStyle(.plain).opacity(dragID == nil ? 1 : 0.3)
        .accessibilityLabel(Text("chaos.add"))
    }

    // MARK: Кружки

    private func incomeNode(_ c: Category, _ totals: [UUID: Decimal]) -> some View {
        node(.category(c.uuid), title: c.name, icon: c.icon, color: ChaosPalette.income, text: ChaosPalette.incomeText,
             amount: totals[c.uuid] ?? 0, code: rates.base, hidden: c.hiddenOnHome)
    }

    private func accountNode(_ a: Account) -> some View {
        node(.account(a.persistentModelID), title: a.name, icon: a.kind.icon, color: ChaosPalette.account, text: ChaosPalette.accountText,
             amount: balance(of: a), code: a.currency, hidden: a.hiddenOnHome)
    }

    private func expenseNode(_ c: Category, _ totals: [UUID: Decimal], _ cache: [PersistentIdentifier: BudgetProgress]) -> some View {
        let p = progress(for: c, in: cache)
        return node(.category(c.uuid), title: c.name, icon: c.icon, color: ChaosPalette.expense, text: ChaosPalette.expenseText,
                    amount: totals[c.uuid] ?? 0, code: rates.base, progress: p, ring: ringHold[c.uuid], hidden: c.hiddenOnHome)
    }

    @ViewBuilder
    private func node(_ id: NodeID, title: String, icon: String, color: Color, text: Color,
                      amount: Decimal, code: String, progress: BudgetProgress? = nil, ring: Double? = nil, hidden: Bool) -> some View {
        let zero = amount == 0
        let alert = progress.map { $0.state != .ok } ?? false
        let valueColor: Color = amount < 0 ? TxType.expense.tint : (alert ? progress!.state.tint : text)
        let isHover = hovered == id
        let isSource = dragID == id
        let dimmed = dragID.map { $0 != id && !canDrop($0, onto: id) } ?? false
        VStack(spacing: 3) {
            Text(title).font(.app(.caption)).foregroundStyle(ChaosPalette.label).lineLimit(1).minimumScaleFactor(0.8)
                .frame(height: 15)
            bubble(icon: icon, color: color, progress: progress, ring: ring)
                .opacity(zero && progress == nil ? 0.7 : 1)
                .scaleEffect(isHover ? 1.2 : (isSource ? 0.9 : 1))
                .overlay { if isHover { Circle().stroke(color, lineWidth: 3).frame(width: circle + 12, height: circle + 12).scaleEffect(1.2).blur(radius: 1) } }
                .overlay(alignment: .topLeading) { if editing { hideBadge(id, hidden: hidden) } }
                .animation(.spring(duration: 0.25), value: isHover)
            // Пустая категория: прочерк вместо ряда «0,00», чтобы взгляд цеплялся только за реальные траты.
            if zero, case .category = id {
                Text(verbatim: "—").font(.app(.caption, .bold)).foregroundStyle(text).opacity(0.4)
                    .accessibilityLabel(Text(verbatim: MoneyText.plain(0, code: code)))
            } else {
                MoneyText(amount: amount, code: code).font(.app(.caption, .bold)).foregroundStyle(valueColor)
                    .brightness(amount < 0 || alert ? -0.15 : 0).opacity(zero ? 0.5 : 1).lineLimit(1).minimumScaleFactor(0.85)
            }
        }
        .frame(height: nodeHeight, alignment: .top)
        .containerRelativeFrame(.horizontal) { w, _ in (w - 16) / 4 }
        .opacity(isSource ? 0.35 : (dimmed ? 0.4 : (hidden ? 0.45 : 1)))
        .background(GeometryReader { g in
            Color.clear.preference(key: FramesKey.self, value: [id: g.frame(in: .named(space))])
        })
        .modifier(JiggleEffect(active: editing, seed: id.hashValue))
        .contentShape(Rectangle())
        .onTapGesture { tap(id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func hideBadge(_ id: NodeID, hidden: Bool) -> some View {
        Button { toggleHidden(id) } label: {
            Image(systemName: hidden ? "plus.circle.fill" : "minus.circle.fill")
                .font(.system(size: 20)).symbolRenderingMode(.palette)
                .foregroundStyle(.white, hidden ? BudgetState.ok.tint : BudgetState.over.tint)
        }
        .buttonStyle(.plain).offset(x: -2, y: -2)
    }

    /// `held` подменяет долю бюджета, пока в кружок летят монетки.
    private func bubble(icon: String, color: Color, progress: BudgetProgress?, ring held: Double? = nil) -> some View {
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

    /// Кружок, который едет за пальцем (чуть выше, чтобы палец его не закрывал).
    @ViewBuilder private var ghost: some View {
        if let id = dragID, let color = color(of: id) {
            DragGhost(finger: finger, icon: icon(of: id), color: color, size: circle)
        }
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
        if let a = account(source), let b = account(target), a !== b { return AddRequest(type: .transfer, from: a, to: b) }
        if let a = account(source), let c = category(target), !c.isIncome { return AddRequest(type: .expense, from: a, category: c) }
        if let c = category(source), c.isIncome, let a = account(target) { return AddRequest(type: .income, from: a, category: c) }
        return nil
    }

    private func canDrop(_ source: NodeID, onto target: NodeID) -> Bool {
        editing ? (group(source) != nil && group(source) == group(target)) : request(from: source, to: target) != nil
    }

    private func target(at finger: CGPoint, excluding source: NodeID) -> NodeID? {
        let p = center(finger)
        return frames.first { $0.key != source && $0.value.insetBy(dx: -4, dy: -4).contains(p) && canDrop(source, onto: $0.key) }?.key
    }

    private func drop(_ source: NodeID, at finger: CGPoint) {
        guard let t = target(at: finger, excluding: source) else { return }
        if editing { reorder(source, onto: t); return }
        request = self.request(from: source, to: t)
        guard request != nil else { return }
        pendingDrop = (source, t)
        dropSaved = false
        if let c = category(t), let r = budgetRatio(of: c) { ringHold[c.uuid] = r }
    }

    // MARK: Монетки

    /// Центр кружка внутри ячейки: под подписью высотой 15 и отступом 3.
    private func bubbleCenter(_ id: NodeID) -> CGPoint? {
        frames[id].map { CGPoint(x: $0.midX, y: $0.minY + 18 + (circle + 12) / 2) }
    }

    /// Окно операции закрылось: если сохранили, запускаем монетки, если отменили, возвращаем кольцо как было.
    private func launchCoins() {
        guard let d = pendingDrop else { return }
        pendingDrop = nil
        let saved = dropSaved
        dropSaved = false
        let held = category(d.target).flatMap { c in ringHold[c.uuid].map { (c, $0) } }
        guard saved, let from = bubbleCenter(d.source), let to = bubbleCenter(d.target) else {
            if let (c, _) = held { ringHold[c.uuid] = nil }
            return
        }
        let end = held.flatMap { budgetRatio(of: $0.0) }
        if reduceMotion || !goldRain {
            if let (c, _) = held { withAnimation(.snappy) { ringHold[c.uuid] = nil } }
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
            withAnimation(.snappy(duration: 0.2)) { ringHold[u] = f.start + (f.end - f.start) * k }
        }
        if index == f.count - 1 {
            if let u = f.category { ringHold[u] = nil }
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
        withAnimation(.spring(duration: 0.3)) {
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
        if let a = account(id) { request = AddRequest(type: .expense, from: a) }
        else if let c = category(id) {
            request = c.isIncome ? AddRequest(type: .income, from: accounts.first, category: c)
                                 : AddRequest(type: .expense, from: accounts.first, category: c)
        }
    }

    private struct FramesKey: PreferenceKey {
        static let defaultValue: [NodeID: CGRect] = [:]
        static func reduce(value: inout [NodeID: CGRect], nextValue: () -> [NodeID: CGRect]) { value.merge(nextValue()) { $1 } }
    }
}

/// Горизонтальные страницы с точками внизу.
/// Точка пальца при перетаскивании. Отдельный объект, чтобы её изменения перерисовывали только призрак.
@Observable final class FingerPoint {
    var point: CGPoint = .zero
}

private struct DragGhost: View {
    let finger: FingerPoint
    let icon: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Color.clear.frame(width: size, height: size)
            .overlay { Image(systemName: icon).font(.system(size: 22, weight: .medium)).foregroundStyle(.white) }
            .liquidGlass(tint: color)
            .shadow(color: color.opacity(0.4), radius: 12, y: 8)
            .scaleEffect(1.1)
            .position(ChaosHomeView.center(finger.point))
            .allowsHitTesting(false)
    }
}

struct PagedStrip<Content: View>: View {
    let count: Int
    var lockScroll = false
    @ViewBuilder let content: (Int) -> Content
    @State private var page: Int? = 0

    var body: some View {
        VStack(spacing: 6) {
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


/// Покачивание кружков в режиме правки, как у иконок на рабочем столе iOS:
/// быстрый лёгкий наклон до 1,8° с микросмещением; у каждого кружка свой момент старта.
private struct JiggleEffect: ViewModifier {
    let active: Bool
    let seed: Int
    @State private var swing = false

    private var delay: Double { Double(UInt(bitPattern: seed) % 1000) / 1000 * 0.15 }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active && swing ? 1.8 : 0))
            .offset(x: active && swing ? 0.5 : 0, y: active && swing ? -1.0 : 0)
            .animation(
                active ? .linear(duration: 0.12).repeatForever(autoreverses: true).delay(delay) : .default,
                value: swing
            )
            .onChange(of: active, initial: true) { _, on in swing = on }
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

/// Горсть монеток: вылетают из кружка-источника по очереди и дугой падают в получателя.
private struct CoinShower: View {
    let flight: CoinFlight
    let onLand: (Int) -> Void

    var body: some View {
        ZStack {
            ForEach(0..<flight.count, id: \.self) { i in
                Coin(from: flight.from, to: flight.to,
                     bend: CGFloat.random(in: -40...40), lift: CGFloat.random(in: 70...120),
                     delay: Double(i) * 0.07, spin: Double.random(in: 360...720)) { onLand(i) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Coin: View {
    let from: CGPoint
    let to: CGPoint
    let bend: CGFloat
    let lift: CGFloat
    let delay: Double
    let spin: Double
    let onLand: () -> Void
    @State private var t: CGFloat = 0

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [ChaosPalette.coinLight, ChaosPalette.coinDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(ChaosPalette.coinRim, lineWidth: 1.5).padding(3))
            .frame(width: 18, height: 18)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .modifier(ArcFlight(t: t, from: from, to: to, bend: bend, lift: lift, spin: spin))
            .onAppear {
                withAnimation(.timingCurve(0.35, 0, 0.75, 1, duration: 0.6).delay(delay)) { t = 1 } completion: { onLand() }
            }
    }
}

/// Положение монетки на дуге (квадратичная кривая через точку над серединой пути), с переворотом и уменьшением в конце.
private struct ArcFlight: ViewModifier, Animatable {
    var t: CGFloat
    let from: CGPoint
    let to: CGPoint
    let bend: CGFloat
    let lift: CGFloat
    let spin: Double

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let c = CGPoint(x: (from.x + to.x) / 2 + bend, y: min(from.y, to.y) - lift)
        let u = 1 - t
        let p = CGPoint(x: u * u * from.x + 2 * u * t * c.x + t * t * to.x,
                        y: u * u * from.y + 2 * u * t * c.y + t * t * to.y)
        let scale = t < 0.15 ? 0.5 + t / 0.15 * 0.5 : (t > 0.8 ? 1 - (t - 0.8) / 0.2 * 0.5 : 1)
        content
            .rotation3DEffect(.degrees(spin * Double(t)), axis: (x: 0, y: 1, z: 0))
            .scaleEffect(scale)
            .opacity(t <= 0 || t >= 1 ? 0 : 1)
            .position(p)
    }
}
