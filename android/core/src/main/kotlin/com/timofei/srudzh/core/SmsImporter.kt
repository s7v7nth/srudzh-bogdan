package com.timofei.srudzh.core

import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId

sealed interface SmsOutcome {
    data class Added(val sms: BankSms, val txId: String) : SmsOutcome
    data object Duplicate : SmsOutcome
    data object Unrecognized : SmsOutcome
}

/** Подписи операций без магазина. Приходят из переводов интерфейса. */
data class SmsNames(val cashDeposit: String, val incomingTransfer: String)

/**
 * СМС банка → операции в учёте и очередь на разбор: сначала счёт, потом категория (квиз), в конце дайджест.
 * Все функции чистые: принимают данные и возвращают изменённую копию.
 */
object SmsImporter {
    /** Ключ защиты от дублей. Совпадает с iPhone-версией, чтобы перенесённые операции тоже узнавались. */
    fun key(sms: BankSms): String =
        listOf(sms.cardLast4 ?: "-", sms.date.epochSecond.toString(), sms.amount.plain(), sms.kind.key).joinToString("|")

    fun import(
        ledger: Ledger,
        text: String,
        rates: Rates,
        names: SmsNames,
        receivedAt: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): Pair<Ledger, SmsOutcome> {
        val sms = PriorbankSms.parse(text, receivedAt, zone) ?: return ledger to SmsOutcome.Unrecognized
        val key = key(sms)
        if (ledger.transactions.any { it.smsKey == key }) return ledger to SmsOutcome.Duplicate

        val purchase = sms.kind == BankSms.Kind.PURCHASE
        val payee = when (sms.kind) {
            BankSms.Kind.PURCHASE -> alias(ledger, sms.merchant)?.name ?: sms.merchant
            BankSms.Kind.CASH_DEPOSIT -> names.cashDeposit
            BankSms.Kind.INCOMING_TRANSFER -> names.incomingTransfer
        }
        val tx = Transaction(
            amount = if (purchase) sms.amount.negate() else sms.amount,
            type = if (purchase) TxType.EXPENSE else TxType.INCOME,
            date = sms.date,
            payee = payee,
            smsReview = SmsReview.ACCOUNT,
            smsKey = key,
            smsCard = sms.cardLast4 ?: "",
            smsCurrency = sms.currency,
            smsBalance = if (sms.balanceIsAvailable) null else sms.balance,
        )
        var next = ledger.copy(transactions = ledger.transactions + tx)
        val bound = sms.cardLast4?.let { last4 -> ledger.cardAliases.firstOrNull { it.last4 == last4 }?.accountId }
        ledger.account(bound)?.let { next = assign(next, tx.id, it, rates) }
        return next to SmsOutcome.Added(sms, tx.id)
    }

    // Счёт

    /** Привязывает карту к счёту и переносит на него все ждущие операции с этой картой. */
    fun bindCard(ledger: Ledger, last4: String, account: Account, rates: Rates): Ledger {
        val aliases = if (ledger.cardAliases.any { it.last4 == last4 }) {
            ledger.cardAliases.map { if (it.last4 == last4) it.copy(accountId = account.id) else it }
        } else {
            ledger.cardAliases + CardAlias(last4, account.id)
        }
        var next = ledger.copy(cardAliases = aliases)
        for (tx in ledger.transactions) {
            if (tx.smsReview == SmsReview.ACCOUNT && tx.smsCard == last4) next = assign(next, tx.id, account, rates)
        }
        return next
    }

    fun assign(ledger: Ledger, txId: String, account: Account, rates: Rates): Ledger {
        val tx = ledger.transaction(txId) ?: return ledger
        var t = tx
        // Сумма из СМС в валюте карты; если счёт в другой валюте, пересчитываем по курсу и оставляем оригинал в заметке.
        if (tx.accountId == null && tx.smsCurrency.isNotEmpty() && tx.smsCurrency != account.currency) {
            rates.convert(tx.amount, tx.smsCurrency, account.currency)?.let { converted ->
                t = t.copy(amount = converted, notes = "SMS: ${tx.amount.abs().plain()} ${tx.smsCurrency}")
            }
        }
        t = rates.stamp(t.copy(accountId = account.id), account.currency)
        val next = ledger.updateTransaction(txId) { t }
        return if (t.type == TxType.EXPENSE) classify(next, txId)
        else next.updateTransaction(txId) { it.copy(smsReview = SmsReview.DIGEST) }
    }

    // Имена контрагентов

    fun alias(ledger: Ledger, payee: String): PayeeAlias? {
        val key = MerchantMemory.key(payee)
        if (key.isEmpty()) return null
        return ledger.payeeAliases.firstOrNull { it.key == key }
    }

    /** Переименовывает контрагента: запоминает правило для будущих СМС и меняет имя во всех прошлых операциях. */
    fun rename(ledger: Ledger, old: String, new: String): Ledger {
        val name = new.trim()
        val oldKey = MerchantMemory.key(old)
        if (name.isEmpty() || name == old || oldKey.isEmpty()) return ledger
        // Уже переименованный магазин переименовываем повторно: правило одно на магазин.
        val existing = ledger.payeeAliases.indexOfFirst { it.key == oldKey || MerchantMemory.key(it.name) == oldKey }
        val aliases = if (existing >= 0) {
            ledger.payeeAliases.mapIndexed { i, a -> if (i == existing) a.copy(name = name) else a }
        } else {
            ledger.payeeAliases + PayeeAlias(oldKey, old, name)
        }
        val txs = ledger.transactions.map { if (MerchantMemory.key(it.payee) == oldKey) it.copy(payee = name) else it }
        return ledger.copy(payeeAliases = aliases, transactions = txs)
    }

    // Категории

    fun suggestion(ledger: Ledger, tx: Transaction): CategorySuggestion<String> {
        val key = MerchantMemory.key(tx.payee)
        if (key.isEmpty()) return CategorySuggestion.Unknown
        val categories = ledger.categories.associateBy { it.uuid }
        val order = mutableListOf<String>()
        val counts = mutableMapOf<String, Int>()
        for (t in ledger.transactions.sortedByDescending { it.date }) {
            if (t.id == tx.id || t.type != TxType.EXPENSE || MerchantMemory.key(t.payee) != key) continue
            val c = categories[t.categoryId] ?: continue
            if (c.archived) continue
            if (c.uuid !in counts) order += c.uuid
            counts[c.uuid] = (counts[c.uuid] ?: 0) + 1
        }
        return MerchantMemory.suggest(order.map { it to (counts[it] ?: 0) })
    }

    /** Решает судьбу траты: категория известна → в дайджест, иначе в квиз. */
    fun classify(ledger: Ledger, txId: String): Ledger {
        val tx = ledger.transaction(txId) ?: return ledger
        val s = suggestion(ledger, tx)
        return if (s is CategorySuggestion.Confident && ledger.category(s.id) != null) {
            ledger.updateTransaction(txId) { it.copy(categoryId = s.id, smsReview = SmsReview.DIGEST) }
        } else {
            ledger.updateTransaction(txId) { it.copy(smsReview = SmsReview.QUIZ) }
        }
    }

    /** Ответы на прошлые вопросы могли сделать ждущие траты понятными: переносим их в дайджест. */
    fun reclassifyQuiz(ledger: Ledger): Ledger =
        ledger.transactions.filter { it.smsReview == SmsReview.QUIZ }.fold(ledger) { l, t -> classify(l, t.id) }

    fun answer(ledger: Ledger, txId: String, categoryId: String, now: Instant = Instant.now()): Ledger {
        val next = ledger
            .updateTransaction(txId) { it.copy(categoryId = categoryId, smsReview = SmsReview.DONE) }
            .updateCategory(categoryId) { it.copy(lastUsed = now) }
        return reclassifyQuiz(next)
    }

    /** «Всё верно» в дайджесте: операции разобраны. */
    fun finishDigest(ledger: Ledger): Ledger =
        ledger.copy(transactions = ledger.transactions.map {
            if (it.smsReview == SmsReview.DIGEST) it.copy(smsReview = SmsReview.DONE) else it
        })

    // Сверка остатка

    /** На сколько остаток в СМС расходится с остатком счёта в приложении на момент операции. null, если сходится или сверять нечем. */
    fun balanceGap(ledger: Ledger, tx: Transaction): BigDecimal? {
        val bank = tx.smsBalance ?: return null
        val account = ledger.account(tx.accountId) ?: return null
        if (account.isCredit) return null
        val gap = bank.subtract(ledger.balance(account.id, asOf = tx.date))
        return gap.takeIf { it.signum() != 0 }
    }
}
