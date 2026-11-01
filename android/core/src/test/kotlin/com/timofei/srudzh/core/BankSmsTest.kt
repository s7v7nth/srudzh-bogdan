package com.timofei.srudzh.core

import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Те же СМС и решения, что в BankSMSTests iPhone-версии. */
class BankSmsTest {
    private val utc = ZoneOffset.UTC
    private fun date(y: Int, m: Int, d: Int, h: Int, min: Int, s: Int = 0): Instant =
        LocalDateTime.of(y, m, d, h, min, s).toInstant(utc)
    private fun dec(s: String) = BigDecimal(s)
    private fun assertDec(expected: String, actual: BigDecimal?) =
        assertTrue(actual != null && actual sameAs dec(expected), "ожидали $expected, получили $actual")

    // Настоящие СМС Приорбанка

    @Test fun purchase() {
        val t = "Karta 4***8780 19-10-26 14:51:23. Oplata 10.08 BYN. BLR SHOP KOPEECHKA. Balance: 103.82 BYN Tel. 7299090"
        val s = PriorbankSms.parse(t, date(2026, 10, 19, 15, 0), utc)!!
        assertEquals(BankSms.Kind.PURCHASE, s.kind)
        assertEquals("8780", s.cardLast4)
        assertEquals(date(2026, 10, 19, 14, 51, 23), s.date)
        assertDec("10.08", s.amount)
        assertEquals("BYN", s.currency)
        assertEquals("SHOP KOPEECHKA", s.merchant)
        assertDec("103.82", s.balance)
        assertEquals(false, s.balanceIsAvailable)
    }

    @Test fun cashDepositAtAtm() {
        val t = "Karta 4***8780 11-10-26 17:44:14. Zachislenie perevoda 1200.00 BYN. BLR Money Transfer Visa. Balance: 1200.16 BYN Tel. 7299090"
        val s = PriorbankSms.parse(t, date(2026, 10, 19, 9, 0), utc)!!
        assertEquals(BankSms.Kind.CASH_DEPOSIT, s.kind)
        assertDec("1200.00", s.amount)
        assertEquals("8780", s.cardLast4)
        assertEquals("", s.merchant)
        assertDec("1200.16", s.balance)
        assertEquals(false, s.balanceIsAvailable)
    }

    @Test fun incomingTransferWithoutCard() {
        val t = "08/10 16:49. Na vashu kartu zachisleno 50.00 BYN. Dostupnaja summa: 63.12 BYN. Tel. 7299090"
        val s = PriorbankSms.parse(t, date(2026, 10, 19, 9, 0), utc)!!
        assertEquals(BankSms.Kind.INCOMING_TRANSFER, s.kind)
        assertNull(s.cardLast4)
        assertEquals(date(2026, 10, 8, 16, 49), s.date)
        assertDec("50.00", s.amount)
        assertEquals("BYN", s.currency)
        assertEquals("", s.merchant)
        assertDec("63.12", s.balance)
        assertEquals(true, s.balanceIsAvailable)
    }

    @Test fun incomingTransferFromUserReport() {
        val t = "20/10 17:39. Na vashu kartu zachisleno 193.50 BYN. Dostupnaja summa: 272.71 BYN. Tel. 7299090"
        val s = PriorbankSms.parse(t, date(2026, 10, 22, 9, 0), utc)!!
        assertEquals(BankSms.Kind.INCOMING_TRANSFER, s.kind)
        assertDec("193.50", s.amount)
        assertEquals(date(2026, 10, 20, 17, 39), s.date)
    }

    // Решения по неизвестному

    @Test fun yearRollsBackAcrossNewYear() {
        val t = "30/12 10:00. Na vashu kartu zachisleno 5.00 BYN. Dostupnaja summa: 5.00 BYN."
        val s = PriorbankSms.parse(t, date(2027, 1, 2, 9, 0), utc)!!
        assertEquals(date(2026, 12, 30, 10, 0), s.date)
    }

    @Test fun thousandsSeparatorAndComma() {
        val t = "Karta 4***8780 01-11-26 10:00:00. Oplata 1 234,50 BYN. BLR MAGAZIN. Balance: 2 000,00 BYN"
        val s = PriorbankSms.parse(t, date(2026, 11, 1, 11, 0), utc)!!
        assertDec("1234.50", s.amount)
        assertDec("2000.00", s.balance)
    }

    @Test fun unknownFormatsAreNotGuessed() {
        assertNull(PriorbankSms.parse("Vash kod 123456"))
        assertNull(PriorbankSms.parse("Karta 4***8780 19-10-26 14:51:23. Vozvrat 10.08 BYN. BLR SHOP. Balance: 1.00 BYN"))
        assertNull(PriorbankSms.parse(""))
    }

    /** Ключ дублей должен совпадать с iPhone: «карта|секунды|сумма без нулей|тип». */
    @Test fun duplicateKeyMatchesIphone() {
        val t = "Karta 4***8780 11-10-26 17:44:14. Zachislenie perevoda 1200.00 BYN. BLR Money Transfer Visa. Balance: 1200.16 BYN"
        val s = PriorbankSms.parse(t, date(2026, 10, 19, 9, 0), utc)!!
        assertEquals("8780|${s.date.epochSecond}|1200|cashDeposit", SmsImporter.key(s))
    }

    // Память о магазинах

    @Test fun merchantKeyIgnoresCountryBranchAndPunctuation() {
        assertEquals("SHOP KOPEECHKA", MerchantMemory.key("BLR SHOP KOPEECHKA"))
        assertEquals("SHOP KOPEECHKA", MerchantMemory.key("shop  kopeechka #12"))
        assertEquals(MerchantMemory.key("SHOP KOPEECHKA"), MerchantMemory.key("BLR SHOP-KOPEECHKA 7"))
        assertEquals("12", MerchantMemory.key("12"))
    }

    @Test fun newMerchantIsUnknown() {
        assertEquals(CategorySuggestion.Unknown, MerchantMemory.suggest(emptyList<Pair<String, Int>>()))
    }

    @Test fun singleCategoryIsConfident() {
        assertEquals(CategorySuggestion.Confident("cigs"), MerchantMemory.suggest(listOf("cigs" to 1)))
        assertEquals(CategorySuggestion.Confident("cigs"), MerchantMemory.suggest(listOf("cigs" to 3, "food" to 0)))
    }

    @Test fun twoCategoriesAskMostFrequentFirst() {
        assertEquals(CategorySuggestion.Ask(listOf("food", "cigs")), MerchantMemory.suggest(listOf("cigs" to 1, "food" to 2)))
        // при равенстве сохраняется порядок: сначала та, что в списке раньше
        assertEquals(CategorySuggestion.Ask(listOf("cigs", "food")), MerchantMemory.suggest(listOf("cigs" to 1, "food" to 1)))
    }

    @Test fun dominantCategoryWinsWithEnoughHistory() {
        assertEquals(CategorySuggestion.Confident("food"), MerchantMemory.suggest(listOf("food" to 8, "cigs" to 1)))
        assertEquals(CategorySuggestion.Ask(listOf("food", "cigs")), MerchantMemory.suggest(listOf("food" to 3, "cigs" to 1)))
    }

    @Test fun atMostThreeOptions() {
        val r = MerchantMemory.suggest(listOf("a" to 4, "b" to 3, "c" to 2, "d" to 1))
        assertEquals(CategorySuggestion.Ask(listOf("a", "b", "c")), r)
    }
}
