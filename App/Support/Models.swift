import Foundation
import SwiftUI
import SwiftData
import LedgerCore

enum TxType: String, Codable, CaseIterable {
    case expense, income, transfer
    var label: LocalizedStringKey {
        switch self { case .expense: "tx.expense"; case .income: "tx.income"; case .transfer: "tx.transfer" }
    }
}

enum AccountKind: String, Codable, CaseIterable {
    case card, cash, savings, creditLine
    var label: LocalizedStringKey {
        switch self {
        case .card: "kind.card"; case .cash: "kind.cash"; case .savings: "kind.savings"; case .creditLine: "kind.creditLine"
        }
    }
    var icon: String {
        switch self { case .card: "creditcard"; case .cash: "banknote"; case .savings: "building.columns"; case .creditLine: "creditcard.and.123" }
    }
}

@Model final class Account {
    var name: String
    var currency: String
    var kind: AccountKind = AccountKind.card
    var excludedFromNetWorth: Bool
    /// Основной счёт: входит в сумму «Баланс» на главном экране (удержание кнопки показывает все счета).
    var isPrimary: Bool = true
    var sortID: Int
    /// Скрыт с главного экрана с кружками (счёт остаётся в приложении).
    var hiddenOnHome: Bool = false
    // Кредитная линия
    var creditLimit: Decimal?
    var interestRate: Decimal?
    var statementDay: Int?
    var graceDays: Int?
    var graceFromStatement: Bool = true
    var minPercent: Decimal?
    var minFloor: Decimal?
    var dueDays: Int?
    @Relationship(deleteRule: .cascade, inverse: \LedgerTransaction.account)
    var transactions: [LedgerTransaction] = []

    init(name: String, currency: String, kind: AccountKind = .card, excluded: Bool = false, sortID: Int = 0) {
        self.name = name; self.currency = currency; self.kind = kind
        self.excludedFromNetWorth = excluded; self.sortID = sortID
    }

    var isCredit: Bool { kind == .creditLine }

    var terms: CreditTerms {
        CreditTerms(limit: creditLimit ?? 0, aprPercent: interestRate ?? 0, statementDay: statementDay ?? 1,
                    graceDays: graceDays ?? 0, graceFromStatement: graceDays == nil ? false : graceFromStatement,
                    minPercent: minPercent ?? 0, minFloor: minFloor ?? 0, dueDays: dueDays ?? 0)
    }

    var entries: [LedgerEntry] { transactions.map { LedgerEntry(amount: $0.amount, date: $0.date, pending: $0.pending) } }
}

@Model final class Category {
    var uuid: UUID = UUID()
    var name: String
    var isIncome: Bool
    var icon: String = "tag"
    var colorName: String = "blue"
    var sortID: Int = 0
    var archived: Bool = false
    /// Скрыта с главного экрана с кружками.
    var hiddenOnHome: Bool = false
    var lastUsed: Date?
    var parent: Category?
    @Relationship(deleteRule: .nullify, inverse: \Category.parent) var children: [Category] = []

    init(name: String, isIncome: Bool, icon: String = "tag", colorName: String = "blue", sortID: Int = 0, parent: Category? = nil) {
        self.name = name; self.isIncome = isIncome; self.icon = icon; self.colorName = colorName
        self.sortID = sortID; self.parent = parent
    }

    /// Сама категория и все её подкатегории (для бюджетов и планов).
    var familyIDs: Set<UUID> { Set([uuid] + children.map(\.uuid)) }
}

/// Расход хранится отрицательным, доход положительным. Сумма в валюте счёта.
/// Перевод это две связанные операции (одинаковый transferID), у каждой своя сумма и валюта.
@Model final class LedgerTransaction {
    var amount: Decimal
    var type: TxType
    var date: Date
    var payee: String
    var notes: String
    var pending: Bool
    var transferID: UUID?
    /// Курс валюты счёта к основной валюте на момент операции и код основной валюты, для которой он записан.
    var rateToBase: Decimal = 1
    var baseCode: String = ""
    var account: Account?
    var category: Category?
    /// Операция пришла из СМС банка. 0 разобрана, иначе ждёт пользователя (см. SMSReviewState).
    var smsReview: Int = 0
    /// Защита от дублей: одно и то же СМС дважды не добавляется.
    var smsKey: String = ""
    /// Последние 4 цифры карты из СМС (пусто, если банк их не указал).
    var smsCard: String = ""
    /// Остаток по карте после операции, как его написал банк. nil, если банк прислал только «доступную сумму».
    var smsBalance: Decimal?
    /// Валюта из СМС (нужна, чтобы создать счёт нужной валюты).
    var smsCurrency: String = ""

    init(amount: Decimal, type: TxType, date: Date = .now, payee: String = "", notes: String = "",
         pending: Bool = false, transferID: UUID? = nil, rateToBase: Decimal = 1, baseCode: String = "",
         account: Account?, category: Category? = nil) {
        self.amount = amount; self.type = type; self.date = date; self.payee = payee; self.notes = notes
        self.pending = pending; self.transferID = transferID; self.rateToBase = rateToBase; self.baseCode = baseCode
        self.account = account; self.category = category
    }

    var currency: String { account?.currency ?? "" }
    /// Перевод на кредитную линию с другого счёта это погашение.
    var isRepayment: Bool { type == .transfer && amount > 0 && (account?.isCredit ?? false) }
}

/// Что операции из СМС ещё нужно от пользователя.
enum SMSReviewState: Int {
    case done = 0
    /// Нужен квиз: в какую категорию трата.
    case quiz = 1
    /// Категория подставлена или не нужна, показываем в дайджесте.
    case digest = 2
    /// Неизвестна карта или банк не назвал карту: на какой счёт операция?
    case account = 3
}

extension LedgerTransaction {
    var review: SMSReviewState {
        get { SMSReviewState(rawValue: smsReview) ?? .done }
        set { smsReview = newValue.rawValue }
    }
}

/// Привязка «карта ••8780 → счёт в приложении».
@Model final class CardAlias {
    var last4: String
    var account: Account?
    init(last4: String, account: Account?) { self.last4 = last4; self.account = account }
}

/// Своё имя для контрагента из СМС: «SHOP KOPEECHKA» → «Копейка». `key` это MerchantMemory.key исходного названия.
@Model final class PayeeAlias {
    var key: String = ""
    var original: String = ""
    var name: String = ""
    init(key: String, original: String, name: String) { self.key = key; self.original = original; self.name = name }
}

@Model final class Budget {
    var name: String
    var amount: Decimal
    var currency: String = ""
    var startDate: Date
    var repeatType: Int      // 1 день, 2 неделя, 3 месяц, 4 год
    var carryOver: Bool
    var categories: [Category] = []
    init(name: String, amount: Decimal, currency: String, startDate: Date, repeatType: Int = 3, carryOver: Bool = false) {
        self.name = name; self.amount = amount; self.currency = currency; self.startDate = startDate
        self.repeatType = repeatType; self.carryOver = carryOver
    }
}

/// Платёж по расписанию. repeatType: 1 день, 2 неделя, 3 месяц, 4 год.
@Model final class RecurringTransaction {
    var amount: Decimal
    var type: TxType
    var payee: String
    var nextDate: Date
    var repeatType: Int
    var duration: Int
    var endDate: Date?
    var active: Bool
    var account: Account?
    var category: Category?

    init(amount: Decimal, type: TxType, payee: String, nextDate: Date, repeatType: Int = 3, duration: Int = 1,
         endDate: Date? = nil, account: Account?, category: Category? = nil) {
        self.amount = amount; self.type = type; self.payee = payee; self.nextDate = nextDate
        self.repeatType = repeatType; self.duration = duration; self.endDate = endDate
        self.active = true; self.account = account; self.category = category
    }
}

/// Пункт плана (суммы в основной валюте). repeatMonths: 1, 3, 12 или 0 для разового платежа.
@Model final class PlanItem {
    var name: String
    var isIncome: Bool
    var annualAmount: Decimal
    var repeatMonths: Int
    var paymentDate: Date
    var category: Category?
    init(name: String, isIncome: Bool, annualAmount: Decimal, repeatMonths: Int, paymentDate: Date, category: Category?) {
        self.name = name; self.isIncome = isIncome; self.annualAmount = annualAmount
        self.repeatMonths = repeatMonths; self.paymentDate = paymentDate; self.category = category
    }
}

// MARK: - Первичное наполнение

enum Seed {
    static let schema = Schema([Account.self, Category.self, LedgerTransaction.self, Budget.self,
                                RecurringTransaction.self, PlanItem.self, CardAlias.self, PayeeAlias.self])

    /// Стандартный набор создаётся на языке интерфейса и дальше принадлежит пользователю.
    static func run(_ ctx: ModelContext) {
        guard (try? ctx.fetchCount(FetchDescriptor<Category>())) == 0 else { return }
        let expenses: [(String, String, String)] = [
            ("cat.food", "cart", "green"), ("cat.transport", "bus", "blue"), ("cat.housing", "house", "indigo"),
            ("cat.cafe", "cup.and.saucer", "orange"), ("cat.fun", "gamecontroller", "purple"),
            ("cat.health", "cross.case", "red"), ("cat.clothes", "tshirt", "pink"),
            ("cat.fees", "percent", "brown"), ("cat.other", "ellipsis.circle", "gray")]
        let income: [(String, String, String)] = [
            ("cat.salary", "banknote", "green"), ("cat.gifts", "gift", "pink"), ("cat.otherIncome", "plus.circle", "teal")]
        for (i, c) in expenses.enumerated() {
            ctx.insert(Category(name: String(localized: String.LocalizationValue(c.0)), isIncome: false, icon: c.1, colorName: c.2, sortID: i))
        }
        for (i, c) in income.enumerated() {
            ctx.insert(Category(name: String(localized: String.LocalizationValue(c.0)), isIncome: true, icon: c.1, colorName: c.2, sortID: i))
        }
        try? ctx.save()
    }
}
