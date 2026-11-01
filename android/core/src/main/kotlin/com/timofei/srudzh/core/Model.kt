package com.timofei.srudzh.core

import kotlinx.serialization.json.JsonObject
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

/** `raw` совпадает с iPhone-версией: так типы записываются в файл копии. */
enum class TxType(val raw: String) {
    EXPENSE("expense"), INCOME("income"), TRANSFER("transfer");

    companion object {
        fun of(raw: String): TxType = entries.firstOrNull { it.raw == raw } ?: EXPENSE
    }
}

enum class AccountKind(val raw: String) {
    CARD("card"), CASH("cash"), SAVINGS("savings"), CREDIT_LINE("creditLine"), DEBT("debt");

    companion object {
        fun of(raw: String): AccountKind = entries.firstOrNull { it.raw == raw } ?: CARD
    }
}

/** Что операции из СМС ещё нужно от пользователя. Числа те же, что в iPhone-версии. */
enum class SmsReview(val raw: Int) {
    DONE(0),

    /** Нужен квиз: в какую категорию трата. */
    QUIZ(1),

    /** Категория подставлена или не нужна, показываем в дайджесте. */
    DIGEST(2),

    /** Неизвестна карта или банк не назвал карту: на какой счёт операция? */
    ACCOUNT(3);

    companion object {
        fun of(raw: Int): SmsReview = entries.firstOrNull { it.raw == raw } ?: DONE
    }
}

data class Account(
    /** Номер счёта; в копии на него ссылаются операции и привязки карт. */
    val id: Int,
    val name: String,
    val currency: String,
    val kind: AccountKind = AccountKind.CARD,
    val excluded: Boolean = false,
    /** Основной счёт: входит в сумму «Баланс» на главном экране. */
    val isPrimary: Boolean = true,
    /** Скрыт с главного экрана с кружками (счёт остаётся в приложении). */
    val hiddenOnHome: Boolean = false,
    val sortId: Int = 0,
    // Условия кредитной линии: на Android пока не показываются, но хранятся, чтобы не потерять при переносе.
    val graceFromStatement: Boolean = true,
    val creditLimit: BigDecimal? = null,
    val interestRate: BigDecimal? = null,
    val minPercent: BigDecimal? = null,
    val minFloor: BigDecimal? = null,
    val statementDay: Int? = null,
    val graceDays: Int? = null,
    val dueDays: Int? = null,
) {
    val isCredit: Boolean get() = kind == AccountKind.CREDIT_LINE
}

data class Category(
    val uuid: String,
    val name: String,
    val isIncome: Boolean,
    /** Имя значка из iPhone-версии (SF Symbols); Android сам подбирает похожий. */
    val icon: String = "tag",
    val color: String = "blue",
    val sortId: Int = 0,
    val archived: Boolean = false,
    /** Скрыта с главного экрана с кружками. */
    val hiddenOnHome: Boolean = false,
    val lastUsed: Instant? = null,
    val parent: String? = null,
)

/**
 * Расход хранится отрицательным, доход положительным. Сумма в валюте счёта.
 * Перевод это две связанные операции (одинаковый transferId), у каждой своя сумма и валюта.
 */
data class Transaction(
    val id: String = newId(),
    val amount: BigDecimal,
    val type: TxType,
    val date: Instant,
    val payee: String = "",
    val notes: String = "",
    val pending: Boolean = false,
    val transferId: String? = null,
    /** Курс валюты счёта к основной валюте на момент операции и код основной валюты, для которой он записан. */
    val rateToBase: BigDecimal = BigDecimal.ONE,
    val baseCode: String = "",
    val accountId: Int? = null,
    val categoryId: String? = null,
    val smsReview: SmsReview = SmsReview.DONE,
    /** Защита от дублей: одно и то же СМС дважды не добавляется. */
    val smsKey: String = "",
    /** Последние 4 цифры карты из СМС (пусто, если банк их не указал). */
    val smsCard: String = "",
    /** Валюта из СМС (нужна, чтобы создать счёт нужной валюты и пересчитать сумму). */
    val smsCurrency: String = "",
    /** Остаток по карте после операции, как его написал банк. null, если банк прислал только «доступную сумму». */
    val smsBalance: BigDecimal? = null,
)

/** Привязка «карта ••8780 → счёт в приложении». */
data class CardAlias(val last4: String, val accountId: Int?)

/** Своё имя для контрагента из СМС: «SHOP KOPEECHKA» → «Копейка». `key` это MerchantMemory.key исходного названия. */
data class PayeeAlias(val key: String, val original: String, val name: String)

data class Settings(
    val baseCurrency: String = "",
    val chaos: Boolean? = null,
    val scheduleWindowDays: Int? = null,
    val reportsPeriod: Int? = null,
    val digestEnabled: Boolean? = null,
    val digestMinutes: Int? = null,
)

/** Все данные приложения. Неизменяемые: каждое действие возвращает новую копию. */
data class Ledger(
    val settings: Settings = Settings(),
    val accounts: List<Account> = emptyList(),
    val categories: List<Category> = emptyList(),
    val transactions: List<Transaction> = emptyList(),
    val cardAliases: List<CardAlias> = emptyList(),
    val payeeAliases: List<PayeeAlias> = emptyList(),
    // Бюджеты, расписание и план появятся на Android позже; пока хранятся как есть, чтобы не потеряться при переносе.
    val budgets: List<JsonObject> = emptyList(),
    val recurring: List<JsonObject> = emptyList(),
    val plan: List<JsonObject> = emptyList(),
) {
    val base: String get() = settings.baseCurrency

    fun account(id: Int?): Account? = id?.let { i -> accounts.firstOrNull { it.id == i } }
    fun category(uuid: String?): Category? = uuid?.let { u -> categories.firstOrNull { it.uuid == u } }
    fun transaction(id: String): Transaction? = transactions.firstOrNull { it.id == id }
    fun children(of: Category): List<Category> = categories.filter { it.parent == of.uuid }

    /** Валюта операции = валюта её счёта (пусто, если счёта нет). */
    fun currency(tx: Transaction): String = account(tx.accountId)?.currency ?: ""

    /** Перевод на кредитную линию с другого счёта это погашение. */
    fun isRepayment(tx: Transaction): Boolean =
        tx.type == TxType.TRANSFER && tx.amount.signum() > 0 && account(tx.accountId)?.isCredit == true

    /** Баланс счёта = сумма операций со знаком. `asOf` отсекает будущие операции. */
    fun balance(accountId: Int, includePending: Boolean = true, asOf: Instant? = null): BigDecimal =
        Balances.balance(transactions.filter { it.accountId == accountId }, includePending, asOf)

    val nextAccountId: Int get() = (accounts.maxOfOrNull { it.id } ?: -1) + 1

    fun updateTransaction(id: String, change: (Transaction) -> Transaction): Ledger =
        copy(transactions = transactions.map { if (it.id == id) change(it) else it })

    fun updateAccount(id: Int, change: (Account) -> Account): Ledger =
        copy(accounts = accounts.map { if (it.id == id) change(it) else it })

    fun updateCategory(uuid: String, change: (Category) -> Category): Ledger =
        copy(categories = categories.map { if (it.uuid == uuid) change(it) else it })
}

object Balances {
    fun balance(txs: Iterable<Transaction>, includePending: Boolean = true, asOf: Instant? = null): BigDecimal =
        txs.filter { includePending || !it.pending }
            .filter { asOf == null || !it.date.isAfter(asOf) }
            .fold(BigDecimal.ZERO) { sum, t -> sum.add(t.amount) }

    /** Доступный кредит = лимит + баланс (баланс отрицательный, когда должен). */
    fun availableCredit(limit: BigDecimal, balance: BigDecimal): BigDecimal = limit.add(balance)
}

/** Идентификаторы в верхнем регистре, как их пишет iPhone. */
fun newId(): String = UUID.randomUUID().toString().uppercase()
