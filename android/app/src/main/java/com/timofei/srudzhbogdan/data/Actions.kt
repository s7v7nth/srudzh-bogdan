package com.timofei.srudzhbogdan.data

import android.content.Context
import com.timofei.srudzh.core.Account
import com.timofei.srudzh.core.Category
import com.timofei.srudzh.core.Ledger
import com.timofei.srudzh.core.SmsImporter
import com.timofei.srudzh.core.SmsNames
import com.timofei.srudzh.core.SmsOutcome
import com.timofei.srudzh.core.Transaction
import com.timofei.srudzh.core.TxType
import com.timofei.srudzh.core.newId
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.SrudzhApp
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Действия пользователя над данными: каждое меняет LedgerStore и сразу сохраняется. */
object Actions {
    private val base get() = LedgerStore.value.base
    private fun rates() = RatesRepo.rates(base)

    // Операции

    /** Добавляет или заменяет операции (по id), ставит им текущий курс, а для прошлых дней подтягивает курс на их дату. */
    fun saveTransactions(txs: List<Transaction>, removeIds: Set<String> = emptySet()) {
        val r = rates()
        LedgerStore.update { l ->
            val stamped = txs.map { r.stamp(it, l.currency(it)) }
            val ids = stamped.map { it.id }.toSet() + removeIds
            l.copy(transactions = l.transactions.filter { it.id !in ids } + stamped)
        }
        stampHistorical(txs.map { it.id })
    }

    /** Для операций задним числом курс берётся на их дату. Без сети остаётся текущий. */
    fun stampHistorical(ids: List<String>) {
        val l = LedgerStore.value
        val txs = ids.mapNotNull { l.transaction(it) }
        val today = LocalDate.now()
        val past = txs.filter { it.date.atZone(ZoneId.systemDefault()).toLocalDate().isBefore(today) }
        if (past.isEmpty() || l.base.isEmpty()) return
        SrudzhApp.scope.launch {
            for (group in past.groupBy { it.date.atZone(ZoneId.systemDefault()).toLocalDate() }.values) {
                val table = RatesRepo.tableOn(group.first().date) ?: continue
                LedgerStore.update { cur ->
                    val r = RatesRepo.rates(cur.base)
                    group.fold(cur) { acc, t -> acc.updateTransaction(t.id) { r.stamp(it, cur.currency(it), table) } }
                }
            }
        }
    }

    /** У перевода две половинки, удаляем обе. */
    fun deleteTransaction(id: String) = LedgerStore.update { l ->
        val tx = l.transaction(id) ?: return@update l
        l.copy(transactions = l.transactions.filter { it.id != id && (tx.transferId == null || it.transferId != tx.transferId) })
    }

    fun touchCategory(uuid: String?) {
        if (uuid == null) return
        LedgerStore.update { it.updateCategory(uuid) { c -> c.copy(lastUsed = Instant.now()) } }
    }

    // Счета

    /** Новый счёт с начальным остатком (обычной операцией, как на iPhone). Возвращает его номер. */
    fun createAccount(context: Context, draft: Account, opening: BigDecimal?): Int {
        var id = 0
        LedgerStore.update { l ->
            id = l.nextAccountId
            val a = draft.copy(id = id, sortId = l.accounts.size)
            var next = l.copy(accounts = l.accounts + a)
            if (opening != null && opening.signum() != 0) {
                val signed = if (a.isCredit) opening.abs().negate() else opening
                val tx = Transaction(
                    amount = signed, type = if (signed.signum() > 0) TxType.INCOME else TxType.EXPENSE, date = Instant.now(),
                    payee = context.getString(R.string.account_openingPayee), accountId = id,
                )
                next = next.copy(transactions = next.transactions + rates().stamp(tx, a.currency))
            }
            next
        }
        return id
    }

    fun updateAccount(a: Account) = LedgerStore.update { it.updateAccount(a.id) { a } }

    /** Удаляет счёт вместе с его операциями. Привязки карт к нему снимаются: следующее СМС снова спросит счёт. */
    fun deleteAccount(id: Int) = LedgerStore.update { l ->
        l.copy(
            accounts = l.accounts.filter { it.id != id },
            transactions = l.transactions.filter { it.accountId != id },
            cardAliases = l.cardAliases.filter { it.accountId != id },
        )
    }

    // Категории

    fun saveCategory(c: Category) = LedgerStore.update { l ->
        if (l.category(c.uuid) != null) l.updateCategory(c.uuid) { c } else l.copy(categories = l.categories + c)
    }

    /** Операции остаются без категории, подкатегории поднимаются на верхний уровень. */
    fun deleteCategory(uuid: String) = LedgerStore.update { l ->
        l.copy(
            categories = l.categories.filter { it.uuid != uuid }.map { if (it.parent == uuid) it.copy(parent = null) else it },
            transactions = l.transactions.map { if (it.categoryId == uuid) it.copy(categoryId = null) else it },
        )
    }

    /** Стандартный набор создаётся на языке интерфейса и дальше принадлежит пользователю. */
    fun seedCategories(context: Context) = LedgerStore.update { l ->
        if (l.categories.isNotEmpty()) return@update l
        val expenses = listOf(
            Triple(R.string.cat_food, "cart", "green"), Triple(R.string.cat_transport, "bus", "blue"),
            Triple(R.string.cat_housing, "house", "indigo"), Triple(R.string.cat_cafe, "cup.and.saucer", "orange"),
            Triple(R.string.cat_fun, "gamecontroller", "purple"), Triple(R.string.cat_health, "cross.case", "red"),
            Triple(R.string.cat_clothes, "tshirt", "pink"), Triple(R.string.cat_fees, "percent", "brown"),
            Triple(R.string.cat_other, "ellipsis.circle", "gray"),
        )
        val income = listOf(
            Triple(R.string.cat_salary, "banknote", "green"), Triple(R.string.cat_gifts, "gift", "pink"),
            Triple(R.string.cat_otherIncome, "plus.circle", "teal"),
        )
        fun make(list: List<Triple<Int, String, String>>, isIncome: Boolean) = list.mapIndexed { i, (name, icon, color) ->
            Category(uuid = newId(), name = context.getString(name), isIncome = isIncome, icon = icon, color = color, sortId = i)
        }
        l.copy(categories = make(expenses, false) + make(income, true))
    }

    // Настройки

    fun setBase(code: String) = LedgerStore.update { it.copy(settings = it.settings.copy(baseCurrency = code)) }

    fun setChaos(on: Boolean) = LedgerStore.update { it.copy(settings = it.settings.copy(chaos = on)) }

    fun restore(ledger: Ledger) = LedgerStore.update { ledger }

    // СМС

    fun smsNames(context: Context) = SmsNames(
        cashDeposit = context.getString(R.string.sms_cashDeposit),
        incomingTransfer = context.getString(R.string.sms_incomingTransfer),
    )

    fun importSms(context: Context, text: String, receivedAt: Instant = Instant.now()): SmsOutcome {
        var outcome: SmsOutcome = SmsOutcome.Unrecognized
        LedgerStore.update { l ->
            val (next, out) = SmsImporter.import(l, text, rates(), smsNames(context), receivedAt)
            outcome = out
            next
        }
        (outcome as? SmsOutcome.Added)?.let { stampHistorical(listOf(it.txId)) }
        return outcome
    }

    /** Много СМС за раз (из памяти телефона): одно изменение и одна запись на диск. Возвращает число новых операций. */
    fun importSmsBatch(context: Context, messages: List<Pair<String, Instant>>): Int {
        val added = mutableListOf<String>()
        val names = smsNames(context)
        LedgerStore.update { l ->
            messages.fold(l) { acc, (text, time) ->
                val (next, out) = SmsImporter.import(acc, text, rates(), names, time)
                if (out is SmsOutcome.Added) added += out.txId
                next
            }
        }
        stampHistorical(added)
        return added.size
    }

    fun bindCard(last4: String, account: Account) = LedgerStore.update { SmsImporter.bindCard(it, last4, account, rates()) }

    fun assignSms(txId: String, account: Account) = LedgerStore.update { SmsImporter.assign(it, txId, account, rates()) }

    fun answerQuiz(txId: String, categoryId: String) = LedgerStore.update { SmsImporter.answer(it, txId, categoryId) }

    fun reclassifyQuiz() = LedgerStore.update { SmsImporter.reclassifyQuiz(it) }

    fun finishDigest() = LedgerStore.update { SmsImporter.finishDigest(it) }

    fun renamePayee(old: String, new: String) = LedgerStore.update { SmsImporter.rename(it, old, new) }

    fun deletePayeeAlias(key: String) = LedgerStore.update { l -> l.copy(payeeAliases = l.payeeAliases.filter { it.key != key }) }

    fun setCardAccount(last4: String, accountId: Int) = LedgerStore.update { l ->
        l.copy(cardAliases = l.cardAliases.map { if (it.last4 == last4) it.copy(accountId = accountId) else it })
    }

    fun deleteCardAlias(last4: String) = LedgerStore.update { l -> l.copy(cardAliases = l.cardAliases.filter { it.last4 != last4 }) }
}
