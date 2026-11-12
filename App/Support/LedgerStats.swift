import SwiftUI
import SwiftData
import LedgerCore

/// Цифры, которые показывают сразу несколько экранов: остатки счетов, траты месяца, состояние бюджетов.
/// Считаются в одном месте, в фоне и только когда данные сохранены, а не на каждое касание на каждом экране.
struct LedgerStats: Equatable, Sendable {
    /// Суммы за текущий месяц по категориям (с подкатегориями), в основной валюте.
    var totals: [UUID: Decimal] = [:]
    var monthExpenses: Decimal = 0
    var balances: [PersistentIdentifier: Decimal] = [:]
    /// Остатки без ожидающих операций.
    var cleared: [PersistentIdentifier: Decimal] = [:]
    var progress: [PersistentIdentifier: BudgetProgress] = [:]
    /// Категория (и её подкатегории) → первый бюджет, который за ней следит.
    var budgetOf: [UUID: PersistentIdentifier] = [:]

    func progress(for c: Category) -> BudgetProgress? { budgetOf[c.uuid].flatMap { progress[$0] } }
    func progress(of b: Budget) -> BudgetProgress? { progress[b.persistentModelID] }

    /// Счёт, которого в расчёте ещё нет (только что создан и не сохранён), считается напрямую.
    func balance(_ a: Account, includePending: Bool = true) -> Decimal {
        (includePending ? balances : cleared)[a.persistentModelID] ?? Balances.balance(a.entries, includePending: includePending)
    }

    /// Считает всё по базе. Работает с любым контекстом, в том числе фоновым.
    static func compute(in ctx: ModelContext, rates: RateSnapshot) -> LedgerStats {
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? ctx.fetch(FetchDescriptor<Category>())) ?? []
        let budgets = (try? ctx.fetch(FetchDescriptor<Budget>())) ?? []
        let transactions = (try? ctx.fetch(FetchDescriptor<LedgerTransaction>())) ?? []
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
            s.balances[a.persistentModelID] = Balances.balance(entries, includePending: true)
            s.cleared[a.persistentModelID] = Balances.balance(entries, includePending: false)
        }
        for b in budgets {
            if let p = BudgetProgress.make(b, transactions: transactions, rates: rates) { s.progress[b.persistentModelID] = p }
            for c in b.categories { for u in c.familyIDs where s.budgetOf[u] == nil { s.budgetOf[u] = b.persistentModelID } }
        }
        return s
    }
}

/// Готовый расчёт, который читают экраны. Пересчитывается в фоне после каждого сохранения базы,
/// при смене курсов и при возврате в приложение (мог смениться месяц).
@MainActor @Observable final class StatsStore {
    static let shared = StatsStore()
    private(set) var value = LedgerStats()
    /// Растёт после каждого пересчёта: экраны, которые считают сами (отчёты), по нему понимают, что данные менялись.
    private(set) var version = 0

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var rates: RateSnapshot?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false

    /// Первый расчёт сразу, до показа первого экрана, чтобы баланс не мигал нулём при запуске.
    func start(container: ModelContainer, rates: RateSnapshot) {
        guard self.container == nil else { return }
        self.container = container
        self.rates = rates
        value = perf("stats.first") { LedgerStats.compute(in: container.mainContext, rates: rates) }
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { StatsStore.shared.refresh() }
        }
    }

    func refresh(rates: RateSnapshot) {
        guard rates != self.rates else { return }
        self.rates = rates
        refresh()
    }

    /// Пересчёт в фоне. Если данные изменились, пока он шёл, сразу запускается ещё один.
    func refresh() {
        guard let container, let rates else { return }
        if running { again = true; return }
        running = true
        Task.detached(priority: .userInitiated) {
            let stats = perf("stats") { LedgerStats.compute(in: ModelContext(container), rates: rates) }
            await StatsStore.shared.finish(stats)
        }
    }

    private func finish(_ stats: LedgerStats) {
        if stats != value { value = stats }
        version += 1
        running = false
        if again { again = false; refresh() }
    }
}

/// Невидимый слой под приложением: передаёт расчёту свежие курсы и сообщает о возврате в приложение.
struct StatsHost: View {
    @Environment(RatesStore.self) private var rates
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Color.clear
            .onChange(of: rates.snapshot) { _, new in StatsStore.shared.refresh(rates: new) }
            .onChange(of: phase) { if phase == .active { StatsStore.shared.refresh() } }
    }
}
