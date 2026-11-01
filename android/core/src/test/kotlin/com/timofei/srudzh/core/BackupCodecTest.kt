package com.timofei.srudzh.core

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.math.BigDecimal
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class BackupCodecTest {
    /** Так выглядит копия, которую пишет iPhone: даты числом секунд от 2001 года, у операций нет id. */
    private val iphoneFile = """
        {"accounts":[{"currency":"BYN","excluded":false,"graceFromStatement":true,"hiddenOnHome":false,"id":0,"isPrimary":true,"kind":"card","name":"Приорбанк","sortID":0},
                     {"creditLimit":"1500","currency":"USD","excluded":true,"graceFromStatement":false,"hiddenOnHome":true,"id":1,"isPrimary":false,"kind":"creditLine","name":"Кредитка","sortID":1,"statementDay":5}],
         "budgets":[{"amount":"300","carryOver":false,"categories":["0B5A2C1E-0000-4000-8000-000000000001"],"currency":"BYN","name":"Еда","repeatType":3,"startDate":783000000}],
         "cardAliases":[{"account":0,"last4":"8780"}],
         "categories":[{"color":"green","hiddenOnHome":false,"icon":"cart","isIncome":false,"name":"Продукты","sortID":0,"archived":false,"uuid":"0B5A2C1E-0000-4000-8000-000000000001","lastUsed":783436283.5},
                       {"color":"orange","hiddenOnHome":false,"icon":"cup.and.saucer","isIncome":false,"name":"Кофе","sortID":0,"archived":false,"uuid":"0B5A2C1E-0000-4000-8000-000000000002","parent":"0B5A2C1E-0000-4000-8000-000000000001"}],
         "created":783500000.25,
         "payeeAliases":[{"key":"SHOP KOPEECHKA","name":"Копейка","original":"SHOP KOPEECHKA"}],
         "plan":[],
         "recurring":[],
         "settings":{"baseCurrency":"BYN","chaos":true,"scheduleWindowDays":7},
         "transactions":[{"account":0,"amount":"-10.08","baseCode":"BYN","category":"0B5A2C1E-0000-4000-8000-000000000001","date":783436283,"notes":"","payee":"Копейка","pending":false,"rateToBase":"1","smsBalance":"103.82","smsCard":"8780","smsCurrency":"BYN","smsKey":"8780|1761743483|10.08|purchase","smsReview":0,"type":"expense"},
                         {"account":0,"amount":"-50","baseCode":"BYN","date":783440000,"notes":"","payee":"","pending":true,"rateToBase":"1","smsCard":"","smsCurrency":"","smsKey":"","smsReview":0,"transferID":"6C1D1D1D-0000-4000-8000-000000000009","type":"transfer"},
                         {"account":1,"amount":"16.67","baseCode":"BYN","date":783440000,"notes":"","payee":"","pending":true,"rateToBase":"3","smsCard":"","smsCurrency":"","smsKey":"","smsReview":0,"transferID":"6C1D1D1D-0000-4000-8000-000000000009","type":"transfer"}],
         "version":1}
    """.trimIndent()

    @Test fun readsIphoneBackup() {
        val l = BackupCodec.decode(iphoneFile)
        assertEquals("BYN", l.base)
        assertEquals(true, l.settings.chaos)
        assertEquals(7, l.settings.scheduleWindowDays)

        assertEquals(listOf("Приорбанк", "Кредитка"), l.accounts.map { it.name })
        val credit = l.account(1)!!
        assertEquals(AccountKind.CREDIT_LINE, credit.kind)
        assertEquals(true, credit.excluded)
        assertEquals(false, credit.isPrimary)
        assertEquals(BigDecimal("1500"), credit.creditLimit)
        assertEquals(5, credit.statementDay)

        val coffee = l.categories[1]
        assertEquals("0B5A2C1E-0000-4000-8000-000000000001", coffee.parent)
        assertEquals(Instant.ofEpochSecond(978_307_200L + 783_436_283L, 500_000_000), l.categories[0].lastUsed)

        val buy = l.transactions[0]
        assertEquals(Instant.ofEpochSecond(1_761_743_483L), buy.date)
        assertEquals(BigDecimal("-10.08"), buy.amount)
        assertEquals("0B5A2C1E-0000-4000-8000-000000000001", buy.categoryId)
        assertEquals(BigDecimal("103.82"), buy.smsBalance)
        assertTrue(buy.id.isNotEmpty())

        val transfer = l.transactions.filter { it.transferId != null }
        assertEquals(2, transfer.size)
        assertTrue(transfer.all { it.pending })
        assertEquals(listOf(CardAlias("8780", 0)), l.cardAliases)
        assertEquals("Копейка", l.payeeAliases.single().name)
        assertEquals(JsonPrimitive("Еда"), l.budgets.single()["name"])
        assertEquals(l.transactions.map { it.id }.toSet().size, 3)
    }

    @Test fun roundTripKeepsEverything() {
        val l = BackupCodec.decode(iphoneFile)
        val again = BackupCodec.decode(BackupCodec.encode(l))
        assertEquals(l, again)
    }

    @Test fun datesSurviveWithNanoseconds() {
        val t = Instant.ofEpochSecond(1_761_743_483L, 123_456_789)
        assertEquals(t, BackupCodec.dateFromJson(BackupCodec.dateToJson(t)))
        val old = Instant.parse("1999-05-01T10:00:00.25Z")
        assertEquals(old, BackupCodec.dateFromJson(BackupCodec.dateToJson(old)))
    }

    @Test fun newerOrBrokenFilesAreRejected() {
        assertFailsWith<BackupCodec.NewerVersionException> {
            BackupCodec.decode(buildJsonObject { put("version", JsonPrimitive(99)) }.toString())
        }
        assertFailsWith<BackupCodec.BrokenFileException> { BackupCodec.decode("не json") }
        assertFailsWith<BackupCodec.BrokenFileException> { BackupCodec.decode("{\"version\":1}") }
    }

    @Test fun fileNameMatchesIphoneAutoBackups() {
        assertEquals("srudzh-20261025-143210-n1240.json", BackupCodec.fileName(Instant.parse("2026-10-25T14:32:10Z"), 1240))
    }
}
