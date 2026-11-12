import SwiftUI
import SwiftData
import LedgerCore

/// Цифры, которые показывают сразу несколько экранов: остатки счетов, траты месяца, состояние бюджетов.
/// Считаются в одном месте и только когда меняются данные, а не на каждое касание на каждом экране.
struct LedgerStats: Equatable {
    /// Суммы за текущий месяц по категориям (с подкатегориями), в основной валюте.
    var totals: [UUID: Decimal] = [:]
    var monthExpenses: Decimal = 0
    /// Ключ здесь сам объект счёта или бюджета: его номер в базе меняется при первом сохранении.
    var balances: [ObjectIdentifier: Decimal] = [:]
    /// Остатки без ожидающих операций.
    var cleared: [ObjectIdentifier: Decimal] = [:]
    var progress: [ObjectIdentifier: BudgetProgress] = [:]
    /// Категория (и её подкатегории) → первый бюджет, который за ней следит.
    var budgetOf: [UUID: ObjectIdentifier] = [:]

    func progress(for c: Category) -> BudgetProgress? { budgetOf[c.uuid].flatMap { progress[$0] } }
    func progress(of b: Budget) -> BudgetProgress? { progress[ObjectIdentifier(b)] }

    /// Счёт, которого в расчёте ещё нет (только что создан), считается напрямую.
    func balance(_ a: Account, includePending: Bool = true) -> Decimal {
        (includePending ? balances : cleared)[ObjectIdentifier(a)] ?? Balances.balance(a.entries, includePending: includePending)
    }

    @MainActor static func make(accounts: [Account], categories: [Category], budgets: [Budget],
                                transactions: [LedgerTransaction], rates: RatesStore) -> LedgerStats {
        var s = LedgerStats()
        if let month = Calendar.current.dateInterval(of: .month, for: .now) {
            // Один проход по операциям; дата проверяется первой, она дешевле связей.
            var own: [UUID: Decimal] = [:]
            // Платёж по кредиту (перевод на счёт-кредит) трата в категории кредита, как и в бюджете.
            // Начальный долг и поправки на самом счёте-кредите тратами не считаются.
            for t in transactions where month.contains(t.date) {
                let loanCategory = t.loanPaymentCategory
                if t.account?.isLoan == true ? loanCategory == nil : t.type == .transfer { continue }
                let v = rates.value(of: t, in: rates.base)
                if t.type == .expense || loanCategory != nil { s.monthExpenses += abs(v ?? 0) }
                if let v, let id = loanCategory ?? t.category?.uuid { own[id, default: 0] += abs(v) }
            }
            for c in categories where c.parent == nil {
                s.totals[c.uuid] = own[c.uuid, default: 0] + c.children.reduce(Decimal(0)) { $0 + own[$1.uuid, default: 0] }
            }
        }
        for a in accounts {
            let entries = a.entries
            s.balances[ObjectIdentifier(a)] = Balances.balance(entries, includePending: true)
            s.cleared[ObjectIdentifier(a)] = Balances.balance(entries, includePending: false)
        }
        for b in budgets {
            if let p = BudgetProgress.make(b, transactions: transactions, rates: rates) { s.progress[ObjectIdentifier(b)] = p }
            for c in b.categories { for u in c.familyIDs where s.budgetOf[u] == nil { s.budgetOf[u] = ObjectIdentifier(b) } }
        }
        return s
    }
}

/// Готовый расчёт, который читают экраны. Обновляет его только `StatsHost`.
@MainActor @Observable final class StatsStore {
    static let shared = StatsStore()
    private(set) var value = LedgerStats()

    func set(_ v: LedgerStats) { if v != value { value = v } }

    /// Первый расчёт до показа первого экрана, чтобы баланс не мигал нулём при запуске.
    func prime(_ ctx: ModelContext, rates: RatesStore) {
        set(LedgerStats.make(accounts: (try? ctx.fetch(FetchDescriptor<Account>())) ?? [],
                             categories: (try? ctx.fetch(FetchDescriptor<Category>())) ?? [],
                             budgets: (try? ctx.fetch(FetchDescriptor<Budget>())) ?? [],
                             transactions: (try? ctx.fetch(FetchDescriptor<LedgerTransaction>())) ?? [],
                             rates: rates))
    }
}

/// Невидимый слой под приложением: следит за данными и пересчитывает общие цифры, когда они изменились.
/// У него нет своего состояния от касаний, поэтому нажатия на экранах расчёт не запускают.
struct StatsHost: View {
    @Environment(RatesStore.self) private var rates
    @Environment(\.scenePhase) private var phase
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var budgets: [Budget]
    @Query private var transactions: [LedgerTransaction]
    /// Меняется при возврате в приложение на другой день: месяц и периоды бюджетов могли смениться.
    @State private var day = Calendar.current.startOfDay(for: .now)

    var body: some View {
        let _ = day
        let stats = perf("stats") { LedgerStats.make(accounts: accounts, categories: categories, budgets: budgets, transactions: transactions, rates: rates) }
        Color.clear
            .onChange(of: stats, initial: true) { _, new in StatsStore.shared.set(new) }
            .onChange(of: phase) { if phase == .active { day = Calendar.current.startOfDay(for: .now) } }
    }
}
