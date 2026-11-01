package com.timofei.srudzh.core

import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Путь СМС от текста до разобранной операции: счёт, квиз, дайджест. */
class SmsImporterTest {
    private val utc = ZoneOffset.UTC
    private val names = SmsNames(cashDeposit = "Cash", incomingTransfer = "Transfer")
    private val rates = Rates(RateTable(mapOf("USD" to BigDecimal("1"), "BYN" to BigDecimal("3"))), base = "BYN")
    private val food = Category(uuid = "F", name = "Food", isIncome = false)
    private val cigs = Category(uuid = "C", name = "Cigs", isIncome = false)
    private val main = Account(id = 0, name = "Main", currency = "BYN")
    private val start = Ledger(settings = Settings(baseCurrency = "BYN"), accounts = listOf(main), categories = listOf(food, cigs))
    private val received: Instant = LocalDateTime.of(2026, 10, 25, 12, 0).toInstant(utc)

    private fun purchase(time: String, amount: String = "10.08", merchant: String = "BLR SHOP KOPEECHKA", card: String = "8780") =
        "Karta 4***$card 19-10-26 $time. Oplata $amount BYN. $merchant. Balance: 103.82 BYN Tel. 7299090"

    private fun Ledger.add(text: String): Pair<Ledger, SmsOutcome> = SmsImporter.import(this, text, rates, names, received, utc)
    private fun assertDec(expected: String, actual: BigDecimal?) =
        assertTrue(actual != null && actual sameAs BigDecimal(expected), "ожидали $expected, получили $actual")

    @Test fun firstSmsAsksForAccountThenCategory() {
        val (l1, out) = start.add(purchase("14:51:23"))
        val added = assertIs<SmsOutcome.Added>(out)
        val tx = l1.transaction(added.txId)!!
        assertEquals(SmsReview.ACCOUNT, tx.smsReview)
        assertNull(tx.accountId)
        assertDec("-10.08", tx.amount)
        assertEquals("SHOP KOPEECHKA", tx.payee)
        assertEquals("8780", tx.smsCard)
        assertDec("103.82", tx.smsBalance)

        val l2 = SmsImporter.bindCard(l1, "8780", main, rates)
        val bound = l2.transaction(tx.id)!!
        assertEquals(0, bound.accountId)
        assertEquals(SmsReview.QUIZ, bound.smsReview)
        assertEquals("BYN", bound.baseCode)
        assertEquals(listOf(CardAlias("8780", 0)), l2.cardAliases)

        val l3 = SmsImporter.answer(l2, tx.id, "F", received)
        assertEquals(SmsReview.DONE, l3.transaction(tx.id)!!.smsReview)
        assertEquals("F", l3.transaction(tx.id)!!.categoryId)
        assertEquals(received, l3.category("F")!!.lastUsed)
    }

    @Test fun knownCardAndMerchantGoStraightToDigest() {
        var l = start.add(purchase("14:51:23")).first
        val first = l.transactions.single()
        l = SmsImporter.bindCard(l, "8780", main, rates)
        l = SmsImporter.answer(l, first.id, "F", received)

        val (l2, out) = l.add(purchase("18:00:00", merchant = "BLR SHOP-KOPEECHKA 7"))
        val tx = l2.transaction(assertIs<SmsOutcome.Added>(out).txId)!!
        assertEquals(0, tx.accountId)
        assertEquals(SmsReview.DIGEST, tx.smsReview)
        assertEquals("F", tx.categoryId)

        val done = SmsImporter.finishDigest(l2)
        assertTrue(done.transactions.all { it.smsReview == SmsReview.DONE })
    }

    @Test fun sameSmsTwiceIsDuplicate() {
        val l = start.add(purchase("14:51:23")).first
        assertEquals(SmsOutcome.Duplicate, l.add(purchase("14:51:23")).second)
        assertEquals(SmsOutcome.Unrecognized, l.add("Vash kod 1234").second)
        assertEquals(1, l.transactions.size)
    }

    @Test fun incomingTransferNeedsAccountAndSkipsQuiz() {
        val (l, out) = start.add("20/10 17:39. Na vashu kartu zachisleno 193.50 BYN. Dostupnaja summa: 272.71 BYN. Tel. 7299090")
        val tx = l.transaction(assertIs<SmsOutcome.Added>(out).txId)!!
        assertEquals(TxType.INCOME, tx.type)
        assertEquals("Transfer", tx.payee)
        assertNull(tx.smsBalance)
        val l2 = SmsImporter.assign(l, tx.id, main, rates)
        assertEquals(SmsReview.DIGEST, l2.transaction(tx.id)!!.smsReview)
    }

    @Test fun foreignCurrencyIsConvertedAndOriginalKeptInNotes() {
        val usd = Account(id = 1, name = "Dollar card", currency = "USD")
        val l = start.copy(accounts = listOf(main, usd)).add(purchase("14:51:23", card = "1111")).first
        val l2 = SmsImporter.bindCard(l, "1111", usd, rates)
        val tx = l2.transactions.single()
        assertDec("-3.36", tx.amount)
        assertEquals("SMS: 10.08 BYN", tx.notes)
        assertEquals("BYN", tx.baseCode)
        assertDec("3", tx.rateToBase)
    }

    @Test fun renamedMerchantKeepsNewNameForFutureSms() {
        var l = start.add(purchase("14:51:23")).first
        l = SmsImporter.rename(l, "SHOP KOPEECHKA", "Kopeyka")
        assertEquals("Kopeyka", l.transactions.single().payee)
        assertEquals(listOf(PayeeAlias("SHOP KOPEECHKA", "SHOP KOPEECHKA", "Kopeyka")), l.payeeAliases)

        val (l2, out) = l.add(purchase("19:00:00"))
        assertEquals("Kopeyka", l2.transaction(assertIs<SmsOutcome.Added>(out).txId)!!.payee)

        // повторное переименование меняет то же правило, а не заводит второе
        val l3 = SmsImporter.rename(l2, "Kopeyka", "Копейка")
        assertEquals(1, l3.payeeAliases.size)
        assertTrue(l3.transactions.all { it.payee == "Копейка" })
    }

    @Test fun balanceGapComparesBankBalanceWithApp() {
        var l = start.add(purchase("14:51:23")).first
        l = SmsImporter.bindCard(l, "8780", main, rates)
        val tx = l.transactions.single()
        // в приложении на счёте только эта трата (-10.08), банк говорит 103.82
        assertDec("113.90", SmsImporter.balanceGap(l, tx))

        val opening = Transaction(amount = BigDecimal("113.90"), type = TxType.INCOME, date = Instant.EPOCH, accountId = 0)
        assertNull(SmsImporter.balanceGap(l.copy(transactions = l.transactions + opening), tx))
    }

    @Test fun askSuggestsPreviouslyUsedCategories() {
        var l = start
        for ((i, cat) in listOf("F", "C").withIndex()) {
            val (next, out) = l.add(purchase("1$i:00:00"))
            l = SmsImporter.bindCard(next, "8780", main, rates)
            l = SmsImporter.answer(l, assertIs<SmsOutcome.Added>(out).txId, cat, received)
        }
        val (l2, out) = l.add(purchase("20:00:00"))
        val tx = l2.transaction(assertIs<SmsOutcome.Added>(out).txId)!!
        assertEquals(SmsReview.QUIZ, tx.smsReview)
        val s = assertIs<CategorySuggestion.Ask<String>>(SmsImporter.suggestion(l2, tx))
        assertNotNull(s.ids.firstOrNull())
        assertEquals(setOf("F", "C"), s.ids.toSet())
    }
}
