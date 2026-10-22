import SwiftUI
import LedgerCore

/// Готовые наборы для онбординга. Названия берутся из Localizable.xcstrings по ключам.
struct CategoryPreset {
    let key: String          // он же ключ названия
    let icon: String
    let color: String
    let group: BudgetGroup
    let weight: Int          // доля внутри корзины при раскладке бюджета
    let level: Int           // с какого набора включена: 1 минимум, 2 стандарт, 3 подробный
}

struct PaymentPreset {
    let key: String          // ключ названия
    let icon: String
    let categoryKey: String
    let cadence: PaymentCadence
    let day: Int
}

enum OnbCatalog {
    static let expenseCategories: [CategoryPreset] = [
        CategoryPreset(key: "cat.food", icon: "cart", color: "green", group: .needs, weight: 25, level: 1),
        CategoryPreset(key: "cat.housing", icon: "house", color: "indigo", group: .needs, weight: 35, level: 1),
        CategoryPreset(key: "cat.transport", icon: "bus", color: "blue", group: .needs, weight: 10, level: 1),
        CategoryPreset(key: "cat.health", icon: "cross.case", color: "red", group: .needs, weight: 6, level: 1),
        CategoryPreset(key: "cat.utilities", icon: "bolt", color: "yellow", group: .needs, weight: 8, level: 2),
        CategoryPreset(key: "cat.connectivity", icon: "wifi", color: "teal", group: .needs, weight: 5, level: 2),
        CategoryPreset(key: "cat.fees", icon: "percent", color: "brown", group: .needs, weight: 2, level: 2),
        CategoryPreset(key: "cat.loans", icon: "creditcard", color: "orange", group: .needs, weight: 0, level: 2),
        CategoryPreset(key: "cat.insurance", icon: "umbrella", color: "mint", group: .needs, weight: 4, level: 3),
        CategoryPreset(key: "cat.education", icon: "book", color: "indigo", group: .needs, weight: 5, level: 3),
        CategoryPreset(key: "cat.kids", icon: "teddybear", color: "pink", group: .needs, weight: 8, level: 3),
        CategoryPreset(key: "cat.car", icon: "car", color: "blue", group: .needs, weight: 6, level: 3),

        CategoryPreset(key: "cat.fun", icon: "gamecontroller", color: "purple", group: .wants, weight: 20, level: 1),
        CategoryPreset(key: "cat.clothes", icon: "tshirt", color: "pink", group: .wants, weight: 15, level: 1),
        CategoryPreset(key: "cat.other", icon: "ellipsis.circle", color: "gray", group: .wants, weight: 10, level: 1),
        CategoryPreset(key: "cat.cafe", icon: "cup.and.saucer", color: "orange", group: .wants, weight: 20, level: 2),
        CategoryPreset(key: "cat.subscriptions", icon: "play.rectangle", color: "red", group: .wants, weight: 10, level: 2),
        CategoryPreset(key: "cat.beauty", icon: "scissors", color: "pink", group: .wants, weight: 8, level: 3),
        CategoryPreset(key: "cat.sport", icon: "figure.run", color: "green", group: .wants, weight: 8, level: 3),
        CategoryPreset(key: "cat.travel", icon: "airplane", color: "blue", group: .wants, weight: 15, level: 3),
        CategoryPreset(key: "cat.gifts", icon: "gift", color: "pink", group: .wants, weight: 6, level: 3),
        CategoryPreset(key: "cat.pets", icon: "pawprint", color: "brown", group: .wants, weight: 5, level: 3),
    ]

    /// Категории дохода: ключ, иконка, цвет. Зарплата, подарки и «прочее» создаются всегда, остальные только если выбран такой источник.
    static let incomeCategories: [(key: String, icon: String, color: String)] = [
        ("cat.salary", "banknote", "green"), ("cat.sideIncome", "laptopcomputer", "teal"),
        ("cat.scholarship", "graduationcap", "indigo"), ("cat.rentIncome", "building.2", "orange"),
        ("cat.business", "storefront", "purple"), ("cat.gifts", "gift", "pink"), ("cat.otherIncome", "plus.circle", "teal"),
    ]
    static let alwaysIncome: Set<String> = ["cat.salary", "cat.gifts", "cat.otherIncome"]

    static let incomes: [PaymentPreset] = [
        PaymentPreset(key: "onb.inc.salary", icon: "banknote", categoryKey: "cat.salary", cadence: .monthly, day: 10),
        PaymentPreset(key: "onb.inc.side", icon: "laptopcomputer", categoryKey: "cat.sideIncome", cadence: .monthly, day: 15),
        PaymentPreset(key: "onb.inc.scholarship", icon: "graduationcap", categoryKey: "cat.scholarship", cadence: .monthly, day: 10),
        PaymentPreset(key: "onb.inc.rent", icon: "building.2", categoryKey: "cat.rentIncome", cadence: .monthly, day: 5),
        PaymentPreset(key: "onb.inc.business", icon: "storefront", categoryKey: "cat.business", cadence: .monthly, day: 20),
        PaymentPreset(key: "onb.inc.other", icon: "plus.circle", categoryKey: "cat.otherIncome", cadence: .monthly, day: 1),
    ]

    static let bills: [PaymentPreset] = [
        PaymentPreset(key: "onb.bill.rent", icon: "house", categoryKey: "cat.housing", cadence: .monthly, day: 1),
        PaymentPreset(key: "onb.bill.utilities", icon: "bolt", categoryKey: "cat.utilities", cadence: .monthly, day: 15),
        PaymentPreset(key: "onb.bill.internet", icon: "wifi", categoryKey: "cat.connectivity", cadence: .monthly, day: 10),
        PaymentPreset(key: "onb.bill.mobile", icon: "phone", categoryKey: "cat.connectivity", cadence: .monthly, day: 10),
        PaymentPreset(key: "onb.bill.transport", icon: "bus", categoryKey: "cat.transport", cadence: .monthly, day: 1),
        PaymentPreset(key: "onb.bill.insurance", icon: "umbrella", categoryKey: "cat.insurance", cadence: .yearly, day: 1),
        PaymentPreset(key: "onb.bill.education", icon: "book", categoryKey: "cat.education", cadence: .monthly, day: 5),
        PaymentPreset(key: "onb.bill.kids", icon: "teddybear", categoryKey: "cat.kids", cadence: .monthly, day: 5),
    ]

    static let loans: [PaymentPreset] = [
        PaymentPreset(key: "onb.loan.consumer", icon: "banknote", categoryKey: "cat.loans", cadence: .monthly, day: 15),
        PaymentPreset(key: "onb.loan.mortgage", icon: "house", categoryKey: "cat.loans", cadence: .monthly, day: 15),
        PaymentPreset(key: "onb.loan.car", icon: "car", categoryKey: "cat.loans", cadence: .monthly, day: 15),
        PaymentPreset(key: "onb.loan.installment", icon: "creditcard", categoryKey: "cat.loans", cadence: .monthly, day: 15),
    ]

    static let subscriptions: [PaymentPreset] = [
        PaymentPreset(key: "onb.sub.video", icon: "play.rectangle", categoryKey: "cat.subscriptions", cadence: .monthly, day: 1),
        PaymentPreset(key: "onb.sub.music", icon: "music.note", categoryKey: "cat.subscriptions", cadence: .monthly, day: 1),
        PaymentPreset(key: "onb.sub.cloud", icon: "icloud", categoryKey: "cat.subscriptions", cadence: .monthly, day: 1),
        PaymentPreset(key: "onb.sub.apps", icon: "square.grid.2x2", categoryKey: "cat.subscriptions", cadence: .monthly, day: 1),
        PaymentPreset(key: "onb.sub.ai", icon: "sparkles", categoryKey: "cat.subscriptions", cadence: .monthly, day: 1),
        PaymentPreset(key: "onb.sub.vpn", icon: "lock.shield", categoryKey: "cat.subscriptions", cadence: .yearly, day: 1),
        PaymentPreset(key: "onb.sub.news", icon: "newspaper", categoryKey: "cat.subscriptions", cadence: .monthly, day: 1),
        PaymentPreset(key: "onb.sub.fitness", icon: "figure.run", categoryKey: "cat.sport", cadence: .monthly, day: 1),
    ]
}

extension PaymentCadence {
    var title: LocalizedStringKey {
        switch self {
        case .monthly: "onb.cad.monthly"; case .twiceMonthly: "onb.cad.twice"; case .biweekly: "onb.cad.biweekly"
        case .weekly: "onb.cad.weekly"; case .yearly: "onb.cad.yearly"
        }
    }
}

extension BudgetGroup {
    var title: LocalizedStringKey {
        switch self { case .needs: "onb.group.needs"; case .wants: "onb.group.wants"; case .savings: "onb.group.savings" }
    }
    var tint: Color {
        switch self { case .needs: Theme.transfer; case .wants: Theme.warn; case .savings: Theme.income }
    }
}
