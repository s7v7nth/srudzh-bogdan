package com.timofei.srudzh.core

import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MoneyAndRatesTest {
    private fun dec(s: String) = BigDecimal(s)
    private fun assertDec(expected: String, actual: BigDecimal?) =
        assertTrue(actual != null && actual sameAs dec(expected), "ожидали $expected, получили $actual")
    private fun day(y: Int, m: Int, d: Int): Instant = LocalDate.of(y, m, d).atTime(12, 0).toInstant(ZoneOffset.UTC)

    // Деньги

    @Test fun roundingHalfUpAwayFromZero() {
        assertDec("2.35", Money.round(dec("2.345")))
        assertDec("-2.35", Money.round(dec("-2.345")))
    }

    @Test fun parseAcceptsCommaAndSpaces() {
        assertDec("1234.5", Money.parse("1 234,5"))
        assertNull(Money.parse("abc"))
    }

    @Test fun plainDropsTrailingZeros() {
        assertEquals("1200", dec("1200.00").plain())
        assertEquals("10.08", dec("10.08").plain())
        assertEquals("-0.5", dec("-0.50").plain())
        assertEquals("0", dec("0.00").plain())
    }

    @Test fun balanceWithAndWithoutPending() {
        val txs = listOf(
            Transaction(amount = dec("100"), type = TxType.INCOME, date = day(2025, 1, 1)),
            Transaction(amount = dec("-30"), type = TxType.EXPENSE, date = day(2025, 1, 2), pending = true),
            Transaction(amount = dec("-20"), type = TxType.EXPENSE, date = day(2025, 2, 1)),
        )
        assertDec("50", Balances.balance(txs))
        assertDec("80", Balances.balance(txs, includePending = false))
        assertDec("70", Balances.balance(txs, asOf = day(2025, 1, 15)))
    }

    @Test fun creditAvailable() {
        assertDec("700", Balances.availableCredit(dec("1000"), dec("-300")))
    }

    // Курсы

    @Test fun fractionDigits() {
        assertEquals(2, Money.fractionDigits("BYN"))
        assertEquals(2, Money.fractionDigits("USD"))
        assertEquals(0, Money.fractionDigits("JPY"))
    }

    @Test fun crossRate() {
        val t = RateTable(mapOf("USD" to dec("1"), "BYN" to dec("3"), "RUB" to dec("90")))
        assertDec("30", t.rate("BYN", "RUB"))
        assertDec("3", t.rate("USD", "BYN"))
        assertDec("1", t.rate("RUB", "RUB"))
        assertNull(t.rate("EUR", "RUB"))
        assertDec("300", t.convert(dec("100"), "USD", "BYN"))
    }

    @Test fun convertRoundsToTargetCurrencyDigits() {
        val t = RateTable(mapOf("USD" to dec("1"), "JPY" to dec("150.5")))
        assertDec("152", t.convert(dec("1.01"), "USD", "JPY"))
    }

    @Test fun parseFawaz() {
        val t = RateTable.parseFawaz("""{"date":"2026-10-18","usd":{"rub":84.12110886,"byn":3.01539232,"usd":1}}""")!!
        assertEquals("84.12110886", t.perUsd["RUB"]!!.toPlainString())
        assertEquals("3.01539232", t.perUsd["BYN"]!!.toPlainString())
        assertEquals(LocalDate.of(2026, 10, 18).atStartOfDay().toInstant(ZoneOffset.UTC), t.date)
    }

    @Test fun parseErApi() {
        val t = RateTable.parseErApi("""{"result":"success","time_last_update_unix":1760745600,"rates":{"RUB":83.2,"BYN":3.02}}""")!!
        assertDec("83.2", t.perUsd["RUB"])
        assertEquals(Instant.ofEpochSecond(1760745600), t.date)
        assertNull(RateTable.parseErApi("""{"result":"error"}"""))
    }

    @Test fun transactionValueUsesStoredRateForSameBase() {
        val rates = Rates(RateTable(mapOf("USD" to dec("1"), "BYN" to dec("3"))), base = "BYN")
        val tx = Transaction(amount = dec("-10"), type = TxType.EXPENSE, date = day(2026, 1, 1), rateToBase = dec("2.9"), baseCode = "BYN")
        // курс на момент операции важнее сегодняшнего
        assertDec("-29", rates.valueOf(tx, "USD", "BYN"))
        // для другой валюты берём сегодняшний курс
        assertDec("-10", rates.valueOf(tx, "USD", "USD"))
    }
}
