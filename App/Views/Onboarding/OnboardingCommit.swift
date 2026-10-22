import Foundation
import SwiftData
import LedgerCore

/// Переносит ответы онбординга в базу одним махом.
/// Категории заменяются выбранным набором. При повторном прохождении (`replaceAll`) сначала стирается всё прежнее.
enum OnboardingCommit {
    struct Counts { var accounts = 0, categories = 0, budgets = 0, payments = 0 }

    @MainActor @discardableResult
    static func run(_ d: OnboardingDraft, ctx: ModelContext, rates: RatesStore, replaceAll: Bool = false) -> Counts {
        var counts = Counts()
        let cal = Calendar.current
        if replaceAll {
            try? ctx.delete(model: LedgerTransaction.self)
            try? ctx.delete(model: RecurringTransaction.self)
            try? ctx.delete(model: Budget.self)
            try? ctx.delete(model: PlanItem.self)
            try? ctx.delete(model: CardAlias.self)
            try? ctx.delete(model: PayeeAlias.self)
            try? ctx.delete(model: Account.self)
            try? ctx.delete(model: Category.self)
            try? ctx.save()
        }
        let firstRun = ((try? ctx.fetchCount(FetchDescriptor<Account>())) ?? 0) == 0
            && ((try? ctx.fetchCount(FetchDescriptor<LedgerTransaction>())) ?? 0) == 0
        rates.base = d.currency

        // Категории
        var existing = (try? ctx.fetch(FetchDescriptor<Category>())) ?? []
        if firstRun { existing.forEach(ctx.delete); existing = [] }
        func category(name: String, income: Bool, icon: String, color: String, sort: Int) -> Category {
            if let found = existing.first(where: { $0.isIncome == income && $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return found }
            let c = Category(name: name, isIncome: income, icon: icon, colorName: color, sortID: sort)
            ctx.insert(c); existing.append(c); counts.categories += 1
            return c
        }
        func localized(_ key: String) -> String { String(localized: String.LocalizationValue(key)) }

        var expenseByKey: [String: Category] = [:]
        for (i, c) in d.expenseCategories.enumerated() {
            expenseByKey[c.key] = category(name: c.name, income: false, icon: c.icon, color: c.color, sort: i)
        }
        let usedIncome = Set(d.incomes.filter(\.enabled).map(\.categoryKey)).union(OnbCatalog.alwaysIncome)
        var incomeByKey: [String: Category] = [:]
        for (i, c) in OnbCatalog.incomeCategories.enumerated() where usedIncome.contains(c.key) {
            incomeByKey[c.key] = category(name: localized(c.key), income: true, icon: c.icon, color: c.color, sort: i)
        }

        // Счета
        let accountCount = (try? ctx.fetchCount(FetchDescriptor<Account>())) ?? 0
        var accountByDraft: [UUID: Account] = [:]
        let opening = localized("onb.openingBalance")
        func addOpening(_ amount: Decimal, to account: Account) {
            guard amount != 0 else { return }
            let tx = LedgerTransaction(amount: amount, type: amount > 0 ? .income : .expense, date: .now, payee: opening, account: account)
            ctx.insert(tx); rates.stamp(tx)
        }
        for a in d.enabledAccounts {
            let acc = Account(name: a.name, currency: a.currency, kind: a.kind, sortID: accountCount + counts.accounts)
            ctx.insert(acc); accountByDraft[a.id] = acc; counts.accounts += 1
            addOpening(a.balance, to: acc)
        }
        for c in d.credits where !c.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let acc = Account(name: c.name, currency: d.currency, kind: .creditLine, sortID: accountCount + counts.accounts)
            acc.creditLimit = Decimal.parse(c.limitText)
            acc.interestRate = Decimal.parse(c.aprText)
            acc.statementDay = c.statementDay
            acc.dueDays = c.dueDays
            ctx.insert(acc); counts.accounts += 1
            addOpening(-(Decimal.parse(c.debtText) ?? 0), to: acc)
        }
        let defaultAccount = d.enabledAccounts.first.flatMap { accountByDraft[$0.id] }

        // Регулярные платежи и доходы
        func schedule(_ p: PaymentDraft, income: Bool, category: Category?) {
            guard p.isActive else { return }
            let account = p.accountID.flatMap { accountByDraft[$0] } ?? defaultAccount
            var dates: [Date]
            switch p.cadence {
            case .monthly: dates = [FirstPayment.monthly(day: p.day)]
            case .twiceMonthly: dates = [FirstPayment.monthly(day: p.day), FirstPayment.monthly(day: p.day2)]
            case .weekly, .biweekly: dates = [FirstPayment.weekly(weekday: p.weekday)]
            case .yearly: dates = [FirstPayment.yearly(date: p.date)]
            }
            // У кредита известно, сколько платежей осталось (прямо или по остатку долга): после последнего расписание завершится.
            var end: Date?
            if let left = p.remainingPayments, p.cadence == .monthly {
                end = cal.date(byAdding: .month, value: left - 1, to: dates[0])
            }
            let name = p.name.trimmingCharacters(in: .whitespaces)
            for date in dates {
                ctx.insert(RecurringTransaction(amount: income ? p.amount : -p.amount, type: income ? .income : .expense,
                                                payee: name, nextDate: date, repeatType: p.cadence.repeatType,
                                                duration: p.cadence.duration, endDate: end, account: account, category: category))
                counts.payments += 1
            }
        }
        for p in d.incomes { schedule(p, income: true, category: incomeByKey[p.categoryKey]) }
        for p in d.bills + d.subscriptions { schedule(p, income: false, category: expenseByKey[p.categoryKey]) }
        // Кредит без числа оставшихся платежей (и без остатка долга) не создаём: он тянулся бы бесконечно и портил отчёты.
        for p in d.loans where p.remainingPayments != nil { schedule(p, income: false, category: expenseByKey[p.categoryKey]) }

        // Бюджеты: по одному на категорию, на месяц.
        let monthStart = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        for c in d.expenseCategories {
            guard let amount = d.amounts[c.id], amount > 0, let cat = expenseByKey[c.key] else { continue }
            let b = Budget(name: cat.name, amount: amount, currency: d.currency, startDate: monthStart, repeatType: 3)
            b.categories = [cat]
            ctx.insert(b); counts.budgets += 1
        }

        try? ctx.save()
        return counts
    }
}
