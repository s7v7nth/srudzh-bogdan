import SwiftUI
import Observation
import LedgerCore

struct AccountDraft: Identifiable {
    var id = UUID()
    var kind: AccountKind
    var name: String
    var currency: String
    var balanceText = ""
    var enabled: Bool
    var isCustom = false
    var balance: Decimal { Decimal.parse(balanceText) ?? 0 }
}

struct PaymentDraft: Identifiable {
    var id = UUID()
    var icon: String
    var categoryKey: String
    var name: String
    var enabled = false
    var isCustom = false
    var amountText = ""
    var cadence: PaymentCadence = .monthly
    /// Число месяца (1...28) для месячных платежей, второе число для «дважды в месяц», день недели (1 вс ... 7 сб) для недельных.
    var day = 1
    var day2 = 15
    var weekday = 6
    var date = Date()
    var remainingText = ""
    /// Остаток долга по кредиту: если число платежей неизвестно, оно считается как остаток ÷ ежемесячный платёж.
    var debtText = ""
    var accountID: UUID?
    var amount: Decimal { Decimal.parse(amountText) ?? 0 }
    /// Сколько платежей осталось: введено напрямую или посчитано по остатку долга. Нет данных: nil.
    var remainingPayments: Int? {
        if let n = Int(remainingText), n > 0 { return n }
        guard amount > 0, let debt = Decimal.parse(debtText), debt > 0 else { return nil }
        let n = NSDecimalNumber(decimal: debt / amount).doubleValue.rounded(.up)
        return n >= 1 ? Int(min(n, 1200)) : nil
    }
    /// Попадёт в приложение, только если включён и сумма задана.
    var isActive: Bool { enabled && amount > 0 }
    /// Сумма за средний месяц.
    var perMonth: Decimal { Money.round(amount * cadence.perMonth) }

    init(preset: PaymentPreset, calendar: Calendar = .current) {
        icon = preset.icon; categoryKey = preset.categoryKey
        name = String(localized: String.LocalizationValue(preset.key))
        cadence = preset.cadence; day = preset.day
        date = FirstPayment.monthly(day: preset.day, calendar: calendar)
    }

    init(custom categoryKey: String, icon: String) {
        self.icon = icon; self.categoryKey = categoryKey; name = ""; enabled = true; isCustom = true
    }
}

struct CreditDraft: Identifiable {
    var id = UUID()
    var name = ""
    var limitText = ""
    var aprText = ""
    var statementDay = 1
    var dueDays = 20
    var debtText = ""
}

struct CategoryDraft: Identifiable {
    var id = UUID()
    /// Для готовой категории ключ названия, для своей случайный идентификатор.
    var key: String
    var name: String
    var icon: String
    var color: String
    var group: BudgetGroup
    var weight: Int
    var level: Int
    var enabled: Bool
    var isCustom = false
}

/// Всё, что человек ответил в онбординге. В базу ничего не пишется, пока он не нажмёт «Начать» (см. OnboardingCommit).
@Observable final class OnboardingDraft {
    var currency: String
    var accounts: [AccountDraft]
    var incomes: [PaymentDraft]
    var bills: [PaymentDraft]
    var loans: [PaymentDraft]
    var subscriptions: [PaymentDraft]
    var credits: [CreditDraft] = []
    var categories: [CategoryDraft]
    /// 1 минимум, 2 стандарт, 3 подробный набор категорий.
    var level = 2

    /// Выбранный шаблон бюджета; nil, если суммы правили руками («свой»).
    var template: String? = BudgetSplit.templates[0].id
    var amounts: [UUID: Decimal] = [:]
    var savings: Decimal = 0
    var incomeOverride: Decimal?
    private var budgetsReady = false

    init(currency: String) {
        self.currency = currency
        accounts = [
            AccountDraft(kind: .card, name: String(localized: "onb.acc.card"), currency: currency, enabled: true),
            AccountDraft(kind: .cash, name: String(localized: "onb.acc.cash"), currency: currency, enabled: true),
            AccountDraft(kind: .savings, name: String(localized: "onb.acc.savings"), currency: currency, enabled: false),
        ]
        incomes = OnbCatalog.incomes.map { PaymentDraft(preset: $0) }
        bills = OnbCatalog.bills.map { PaymentDraft(preset: $0) }
        loans = OnbCatalog.loans.map { PaymentDraft(preset: $0) }
        subscriptions = OnbCatalog.subscriptions.map { PaymentDraft(preset: $0) }
        categories = OnbCatalog.expenseCategories.map {
            CategoryDraft(key: $0.key, name: String(localized: String.LocalizationValue($0.key)), icon: $0.icon, color: $0.color,
                          group: $0.group, weight: $0.weight, level: $0.level, enabled: $0.level <= 2)
        }
    }

    // MARK: Счета

    var enabledAccounts: [AccountDraft] { accounts.filter { $0.enabled && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } }

    func setCurrency(_ code: String) {
        let old = currency
        currency = code
        for i in accounts.indices where accounts[i].currency == old { accounts[i].currency = code }
    }

    // MARK: Категории

    /// Выбирает набор категорий. Категории, которые нужны включённым платежам, остаются включёнными.
    func setLevel(_ newLevel: Int) {
        level = newLevel
        let needed = requiredCategoryKeys
        for i in categories.indices where !categories[i].isCustom {
            categories[i].enabled = categories[i].level <= newLevel || needed.contains(categories[i].key)
        }
    }

    var requiredCategoryKeys: Set<String> {
        Set((bills + countedLoans + subscriptions).filter(\.enabled).map(\.categoryKey))
    }

    func ensureCategory(_ key: String) {
        if let i = categories.firstIndex(where: { $0.key == key }) { categories[i].enabled = true }
    }

    var expenseCategories: [CategoryDraft] { categories.filter(\.enabled) }

    // MARK: Доход и бюджеты

    private var allPayments: [PaymentDraft] { incomes + bills + loans + subscriptions }

    /// Кредиты, которые попадут в приложение: нужно знать, сколько платежей осталось.
    var countedLoans: [PaymentDraft] { loans.filter { $0.remainingPayments != nil } }
    var autoMonthlyIncome: Decimal { incomes.filter(\.isActive).reduce(0) { $0 + $1.perMonth } }
    var monthlyIncome: Decimal { incomeOverride ?? autoMonthlyIncome }
    var monthlyFixedExpenses: Decimal { (bills + countedLoans + subscriptions).filter(\.isActive).reduce(0) { $0 + $1.perMonth } }

    /// Сколько уже запланировано регулярными платежами по каждой категории (в месяц).
    var fixedByCategory: [String: Decimal] {
        (bills + countedLoans + subscriptions).filter(\.isActive).reduce(into: [:]) { $0[$1.categoryKey, default: 0] += $1.perMonth }
    }

    var step: Decimal { BudgetSplit.step(for: monthlyIncome) }
    var base: Decimal { BudgetSplit.groupTotals(income: monthlyIncome, template: BudgetSplit.templates[0]).base }

    func amount(of group: BudgetGroup) -> Decimal {
        switch group {
        case .savings: savings
        default: categories.filter { $0.enabled && $0.group == group }.reduce(0) { $0 + (amounts[$1.id] ?? 0) }
        }
    }
    var allocated: Decimal { BudgetGroup.allCases.reduce(0) { $0 + amount(of: $1) } }

    func applyTemplate(_ t: BudgetTemplate) {
        template = t.id
        let totals = BudgetSplit.groupTotals(income: monthlyIncome, template: t)
        let fixed = fixedByCategory
        for group in [BudgetGroup.needs, .wants] {
            let cats = categories.filter { $0.enabled && $0.group == group }
            let parts = BudgetSplit.distribute(total: group == .needs ? totals.needs : totals.wants,
                                               floors: cats.map { fixed[$0.key] ?? 0 },
                                               weights: cats.map { Decimal($0.weight) }, step: step)
            for (c, v) in zip(cats, parts) { amounts[c.id] = v }
        }
        savings = totals.savings
    }

    /// Вызывается при входе на экран бюджетов: подтягивает изменения, сделанные на прошлых шагах.
    func syncBudgets() {
        let ids = Set(categories.filter(\.enabled).map(\.id))
        amounts = amounts.filter { ids.contains($0.key) }
        if let id = template, let t = BudgetSplit.templates.first(where: { $0.id == id }) {
            applyTemplate(t)
        } else if !budgetsReady {
            applyTemplate(BudgetSplit.templates[0])
        } else {
            for id in ids where amounts[id] == nil { amounts[id] = 0 }
        }
        budgetsReady = true
    }
}
