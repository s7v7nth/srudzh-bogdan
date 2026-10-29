import Foundation
import SwiftData
import LedgerCore

/// СМС банка → операции в приложении. Разбор текста живёт в LedgerCore, здесь только запись в базу и очередь на разбор.
@MainActor enum SMSImporter {
    enum Outcome {
        case added(BankSMS)
        case duplicate
        case unrecognized
    }

    static func importText(_ text: String, ctx: ModelContext, rates: RatesStore) -> Outcome {
        guard let sms = PriorbankSMS.parse(text) else { return .unrecognized }
        let key = [sms.cardLast4 ?? "-", String(Int(sms.date.timeIntervalSince1970)), "\(sms.amount)", "\(sms.kind)"]
            .joined(separator: "|")
        var dup = FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.smsKey == key })
        dup.fetchLimit = 1
        if ((try? ctx.fetchCount(dup)) ?? 0) > 0 { return .duplicate }

        let payee: String
        switch sms.kind {
        case .purchase: payee = alias(for: sms.merchant, ctx: ctx)?.name ?? sms.merchant
        case .cashDeposit: payee = String(localized: "sms.cashDeposit")
        case .incomingTransfer: payee = String(localized: "sms.incomingTransfer")
        }
        let tx = LedgerTransaction(amount: sms.kind == .purchase ? -sms.amount : sms.amount,
                                   type: sms.kind == .purchase ? .expense : .income,
                                   date: sms.date, payee: payee, account: nil)
        tx.smsKey = key
        tx.smsCard = sms.cardLast4 ?? ""
        tx.smsBalance = sms.balanceIsAvailable ? nil : sms.balance
        tx.smsCurrency = sms.currency
        tx.review = .account
        ctx.insert(tx)

        if let last4 = sms.cardLast4,
           let alias = (try? ctx.fetch(FetchDescriptor<CardAlias>(predicate: #Predicate { $0.last4 == last4 })))?.first,
           let account = alias.account {
            assign(tx, to: account, ctx: ctx, rates: rates)
        }
        try? ctx.save()
        return .added(sms)
    }

    // MARK: Счёт

    /// Привязывает карту к счёту и переносит на него все ждущие операции с этой картой.
    static func bind(card last4: String, to account: Account, ctx: ModelContext, rates: RatesStore) {
        let aliases = (try? ctx.fetch(FetchDescriptor<CardAlias>(predicate: #Predicate { $0.last4 == last4 }))) ?? []
        if let a = aliases.first { a.account = account } else { ctx.insert(CardAlias(last4: last4, account: account)) }
        let waiting = (try? ctx.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.smsReview == 3 && $0.smsCard == last4 }))) ?? []
        for tx in waiting { assign(tx, to: account, ctx: ctx, rates: rates) }
        try? ctx.save()
    }

    static func assign(_ tx: LedgerTransaction, to account: Account, ctx: ModelContext, rates: RatesStore) {
        // Сумма из СМС в валюте карты; если счёт в другой валюте, пересчитываем по курсу и оставляем оригинал в заметке.
        if tx.account == nil, !tx.smsCurrency.isEmpty, tx.smsCurrency != account.currency,
           let converted = rates.convert(tx.amount, from: tx.smsCurrency, to: account.currency) {
            let original = tx.amount.magnitude
            tx.amount = converted
            tx.notes = "SMS: \(original) \(tx.smsCurrency)"
        }
        tx.account = account
        rates.stamp(tx)
        let when = tx.date
        Task { await rates.stampHistorical([tx], on: when) }
        if tx.type == .expense { classify(tx, ctx: ctx) } else { tx.review = .digest }
    }

    // MARK: Имена контрагентов

    static func alias(for payee: String, ctx: ModelContext) -> PayeeAlias? {
        let key = MerchantMemory.key(payee)
        guard !key.isEmpty else { return nil }
        return (try? ctx.fetch(FetchDescriptor<PayeeAlias>(predicate: #Predicate { $0.key == key })))?.first
    }

    /// Переименовывает контрагента: запоминает правило для будущих СМС и меняет имя во всех прошлых операциях.
    static func rename(payee old: String, to new: String, ctx: ModelContext) {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldKey = MerchantMemory.key(old)
        guard !name.isEmpty, name != old, !oldKey.isEmpty else { return }
        let all = (try? ctx.fetch(FetchDescriptor<PayeeAlias>())) ?? []
        // Уже переименованный магазин переименовываем повторно: правило одно на магазин.
        if let a = all.first(where: { $0.key == oldKey || MerchantMemory.key($0.name) == oldKey }) {
            a.name = name
        } else {
            ctx.insert(PayeeAlias(key: oldKey, original: old, name: name))
        }
        let txs = (try? ctx.fetch(FetchDescriptor<LedgerTransaction>())) ?? []
        for t in txs where MerchantMemory.key(t.payee) == oldKey { t.payee = name }
        try? ctx.save()
    }

    // MARK: Категории

    static func suggestion(for tx: LedgerTransaction, ctx: ModelContext) -> CategorySuggestion<UUID> {
        let key = MerchantMemory.key(tx.payee)
        guard !key.isEmpty else { return .unknown }
        let history = (try? ctx.fetch(FetchDescriptor<LedgerTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        var order: [UUID] = [], counts: [UUID: Int] = [:]
        for t in history where t !== tx && t.type == .expense && MerchantMemory.key(t.payee) == key {
            guard let c = t.category, !c.archived else { continue }
            if counts[c.uuid] == nil { order.append(c.uuid) }
            counts[c.uuid, default: 0] += 1
        }
        return MerchantMemory.suggest(counts: order.map { ($0, counts[$0] ?? 0) })
    }

    static func category(_ id: UUID, ctx: ModelContext) -> Category? {
        (try? ctx.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.uuid == id })))?.first
    }

    /// Решает судьбу траты: категория известна → в дайджест, иначе в квиз.
    static func classify(_ tx: LedgerTransaction, ctx: ModelContext) {
        if case .confident(let id) = suggestion(for: tx, ctx: ctx), let c = category(id, ctx: ctx) {
            tx.category = c; tx.review = .digest
        } else {
            tx.review = .quiz
        }
    }

    /// Ответы на прошлые вопросы могли сделать ждущие траты понятными: переносим их в дайджест.
    static func reclassifyQuizItems(ctx: ModelContext) {
        let waiting = (try? ctx.fetch(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.smsReview == 1 }))) ?? []
        for tx in waiting { classify(tx, ctx: ctx) }
    }

    static func answer(_ tx: LedgerTransaction, with category: Category, ctx: ModelContext) {
        tx.category = category
        category.lastUsed = .now
        tx.review = .done
        try? ctx.save()
        reclassifyQuizItems(ctx: ctx)
    }

    // MARK: Сверка остатка

    /// На сколько остаток в СМС расходится с остатком счёта в приложении на момент операции. nil, если сходится или сверять нечем.
    static func balanceGap(_ tx: LedgerTransaction) -> Decimal? {
        guard let bank = tx.smsBalance, let account = tx.account, !account.isCredit else { return nil }
        let gap = bank - Balances.balance(account.entries, asOf: tx.date)
        return gap == 0 ? nil : gap
    }
}
