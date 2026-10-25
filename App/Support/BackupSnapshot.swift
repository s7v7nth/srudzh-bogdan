import Foundation
import SwiftData

/// Всё содержимое приложения в одном файле. Счета ссылаются друг на друга по номеру, категории по UUID.
/// Суммы хранятся строками, чтобы при чтении JSON не терялись копейки.
struct BackupSnapshot: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var created = Date()
    var settings: Settings
    var accounts: [AccountDTO] = []
    var categories: [CategoryDTO] = []
    var transactions: [TransactionDTO] = []
    var budgets: [BudgetDTO] = []
    var recurring: [RecurringDTO] = []
    var plan: [PlanDTO] = []
    var cardAliases: [CardAliasDTO] = []
    var payeeAliases: [PayeeAliasDTO] = []

    struct Settings: Codable {
        var baseCurrency: String
        var chaos: Bool?
        var scheduleWindowDays: Int?
        var reportsPeriod: Int?
        var digestEnabled: Bool?
        var digestMinutes: Int?
    }

    struct AccountDTO: Codable {
        var id: Int
        var name, currency: String
        var kind: AccountKind
        var excluded, isPrimary, hiddenOnHome, graceFromStatement: Bool
        var sortID: Int
        var creditLimit, interestRate, minPercent, minFloor: String?
        var statementDay, graceDays, dueDays: Int?
    }

    struct CategoryDTO: Codable {
        var uuid: UUID
        var name, icon, color: String
        var isIncome, archived, hiddenOnHome: Bool
        var sortID: Int
        var lastUsed: Date?
        var parent: UUID?
    }

    struct TransactionDTO: Codable {
        var amount: String
        var type: TxType
        var date: Date
        var payee, notes: String
        var pending: Bool
        var transferID: UUID?
        var rateToBase, baseCode: String
        var account: Int?
        var category: UUID?
        var smsReview: Int
        var smsKey, smsCard, smsCurrency: String
        var smsBalance: String?
    }

    struct BudgetDTO: Codable {
        var name, amount, currency: String
        var startDate: Date
        var repeatType: Int
        var carryOver: Bool
        var categories: [UUID]
    }

    struct RecurringDTO: Codable {
        var amount: String
        var type: TxType
        var payee: String
        var nextDate: Date
        var repeatType, duration: Int
        var endDate: Date?
        var active: Bool
        var account: Int?
        var category: UUID?
    }

    struct PlanDTO: Codable {
        var name: String
        var isIncome: Bool
        var annualAmount: String
        var repeatMonths: Int
        var paymentDate: Date
        var category: UUID?
    }

    struct CardAliasDTO: Codable { var last4: String; var account: Int? }
    struct PayeeAliasDTO: Codable { var key, original, name: String }
}

private func str(_ d: Decimal) -> String { "\(d)" }
private func str(_ d: Decimal?) -> String? { d.map { "\($0)" } }
private func dec(_ s: String) -> Decimal { Decimal(string: s) ?? 0 }
private func dec(_ s: String?) -> Decimal? { s.flatMap { Decimal(string: $0) } }

extension BackupSnapshot {
    enum Failure: Error { case newerVersion }

    // MARK: Снимок

    @MainActor static func make(ctx: ModelContext, base: String) throws -> BackupSnapshot {
        let ud = UserDefaults.standard
        var s = BackupSnapshot(settings: Settings(
            baseCurrency: base,
            chaos: ud.object(forKey: chaosModeKey) as? Bool,
            scheduleWindowDays: ud.object(forKey: scheduleWindowKey) as? Int,
            reportsPeriod: ud.object(forKey: "reportsPeriod") as? Int,
            digestEnabled: EveningNotifier.shared.enabled,
            digestMinutes: EveningNotifier.shared.minutes))

        let accounts = try ctx.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortID)]))
        var accountID: [PersistentIdentifier: Int] = [:]
        for (i, a) in accounts.enumerated() {
            accountID[a.persistentModelID] = i
            s.accounts.append(AccountDTO(
                id: i, name: a.name, currency: a.currency, kind: a.kind, excluded: a.excludedFromNetWorth,
                isPrimary: a.isPrimary, hiddenOnHome: a.hiddenOnHome, graceFromStatement: a.graceFromStatement,
                sortID: a.sortID, creditLimit: str(a.creditLimit), interestRate: str(a.interestRate),
                minPercent: str(a.minPercent), minFloor: str(a.minFloor),
                statementDay: a.statementDay, graceDays: a.graceDays, dueDays: a.dueDays))
        }
        func acc(_ a: Account?) -> Int? { a.flatMap { accountID[$0.persistentModelID] } }

        s.categories = try ctx.fetch(FetchDescriptor<Category>()).map {
            CategoryDTO(uuid: $0.uuid, name: $0.name, icon: $0.icon, color: $0.colorName, isIncome: $0.isIncome,
                        archived: $0.archived, hiddenOnHome: $0.hiddenOnHome, sortID: $0.sortID,
                        lastUsed: $0.lastUsed, parent: $0.parent?.uuid)
        }
        s.transactions = try ctx.fetch(FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date)])).map {
            TransactionDTO(amount: str($0.amount), type: $0.type, date: $0.date, payee: $0.payee, notes: $0.notes,
                           pending: $0.pending, transferID: $0.transferID, rateToBase: str($0.rateToBase),
                           baseCode: $0.baseCode, account: acc($0.account), category: $0.category?.uuid,
                           smsReview: $0.smsReview, smsKey: $0.smsKey, smsCard: $0.smsCard,
                           smsCurrency: $0.smsCurrency, smsBalance: str($0.smsBalance))
        }
        s.budgets = try ctx.fetch(FetchDescriptor<Budget>()).map {
            BudgetDTO(name: $0.name, amount: str($0.amount), currency: $0.currency, startDate: $0.startDate,
                      repeatType: $0.repeatType, carryOver: $0.carryOver, categories: $0.categories.map(\.uuid))
        }
        s.recurring = try ctx.fetch(FetchDescriptor<RecurringTransaction>()).map {
            RecurringDTO(amount: str($0.amount), type: $0.type, payee: $0.payee, nextDate: $0.nextDate,
                         repeatType: $0.repeatType, duration: $0.duration, endDate: $0.endDate, active: $0.active,
                         account: acc($0.account), category: $0.category?.uuid)
        }
        s.plan = try ctx.fetch(FetchDescriptor<PlanItem>()).map {
            PlanDTO(name: $0.name, isIncome: $0.isIncome, annualAmount: str($0.annualAmount),
                    repeatMonths: $0.repeatMonths, paymentDate: $0.paymentDate, category: $0.category?.uuid)
        }
        s.cardAliases = try ctx.fetch(FetchDescriptor<CardAlias>()).map { CardAliasDTO(last4: $0.last4, account: acc($0.account)) }
        s.payeeAliases = try ctx.fetch(FetchDescriptor<PayeeAlias>()).map { PayeeAliasDTO(key: $0.key, original: $0.original, name: $0.name) }
        return s
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupSnapshot {
        let s = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        guard s.version <= currentVersion else { throw Failure.newerVersion }
        return s
    }

    // MARK: Восстановление

    /// Стирает всё, что есть в базе, и заливает содержимое копии. Файл уже прочитан и разобран, так что упасть на полпути нечему.
    @MainActor func restore(into ctx: ModelContext, rates: RatesStore) throws {
        try ctx.delete(model: LedgerTransaction.self)
        try ctx.delete(model: RecurringTransaction.self)
        try ctx.delete(model: Budget.self)
        try ctx.delete(model: PlanItem.self)
        try ctx.delete(model: CardAlias.self)
        try ctx.delete(model: PayeeAlias.self)
        try ctx.delete(model: Account.self)
        try ctx.delete(model: Category.self)
        try ctx.save()

        var accountByID: [Int: Account] = [:]
        for a in accounts {
            let m = Account(name: a.name, currency: a.currency, kind: a.kind, excluded: a.excluded, sortID: a.sortID)
            m.isPrimary = a.isPrimary; m.hiddenOnHome = a.hiddenOnHome; m.graceFromStatement = a.graceFromStatement
            m.creditLimit = dec(a.creditLimit); m.interestRate = dec(a.interestRate)
            m.minPercent = dec(a.minPercent); m.minFloor = dec(a.minFloor)
            m.statementDay = a.statementDay; m.graceDays = a.graceDays; m.dueDays = a.dueDays
            ctx.insert(m)
            accountByID[a.id] = m
        }
        var categoryByID: [UUID: Category] = [:]
        for c in categories {
            let m = Category(name: c.name, isIncome: c.isIncome, icon: c.icon, colorName: c.color, sortID: c.sortID)
            m.uuid = c.uuid; m.archived = c.archived; m.hiddenOnHome = c.hiddenOnHome; m.lastUsed = c.lastUsed
            ctx.insert(m)
            categoryByID[c.uuid] = m
        }
        for c in categories { if let p = c.parent { categoryByID[c.uuid]?.parent = categoryByID[p] } }
        func acc(_ id: Int?) -> Account? { id.flatMap { accountByID[$0] } }
        func cat(_ id: UUID?) -> Category? { id.flatMap { categoryByID[$0] } }

        for t in transactions {
            let m = LedgerTransaction(amount: dec(t.amount), type: t.type, date: t.date, payee: t.payee, notes: t.notes,
                                      pending: t.pending, transferID: t.transferID, rateToBase: dec(t.rateToBase),
                                      baseCode: t.baseCode, account: acc(t.account), category: cat(t.category))
            m.smsReview = t.smsReview; m.smsKey = t.smsKey; m.smsCard = t.smsCard
            m.smsCurrency = t.smsCurrency; m.smsBalance = dec(t.smsBalance)
            ctx.insert(m)
        }
        for b in budgets {
            let m = Budget(name: b.name, amount: dec(b.amount), currency: b.currency, startDate: b.startDate,
                           repeatType: b.repeatType, carryOver: b.carryOver)
            ctx.insert(m)
            m.categories = b.categories.compactMap { categoryByID[$0] }
        }
        for r in recurring {
            let m = RecurringTransaction(amount: dec(r.amount), type: r.type, payee: r.payee, nextDate: r.nextDate,
                                         repeatType: r.repeatType, duration: r.duration, endDate: r.endDate,
                                         account: acc(r.account), category: cat(r.category))
            m.active = r.active
            ctx.insert(m)
        }
        for p in plan {
            ctx.insert(PlanItem(name: p.name, isIncome: p.isIncome, annualAmount: dec(p.annualAmount),
                                repeatMonths: p.repeatMonths, paymentDate: p.paymentDate, category: cat(p.category)))
        }
        for c in cardAliases { ctx.insert(CardAlias(last4: c.last4, account: acc(c.account))) }
        for p in payeeAliases { ctx.insert(PayeeAlias(key: p.key, original: p.original, name: p.name)) }
        try ctx.save()

        let ud = UserDefaults.standard
        if let v = settings.chaos { ud.set(v, forKey: chaosModeKey) }
        if let v = settings.scheduleWindowDays { ud.set(v, forKey: scheduleWindowKey) }
        if let v = settings.reportsPeriod { ud.set(v, forKey: "reportsPeriod") }
        ud.set(true, forKey: "onboardingDone")
        EveningNotifier.shared.apply(enabled: settings.digestEnabled, minutes: settings.digestMinutes)
        rates.base = settings.baseCurrency
    }
}
