package com.timofei.srudzh.core

import java.math.BigDecimal
import java.time.DateTimeException
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/** Разобранное СМС банка. Сумма всегда положительная, знак определяет `kind`. */
data class BankSms(
    val kind: Kind,
    val cardLast4: String?,
    val date: Instant,
    val amount: BigDecimal,
    val currency: String,
    /** Название точки без кода страны. Для переводов пусто. */
    val merchant: String,
    val balance: BigDecimal?,
    /** true, если банк прислал «доступную сумму» (она может включать лимит или блокировки), а не остаток. */
    val balanceIsAvailable: Boolean,
) {
    /** `key` совпадает с iPhone-версией: из него собирается защита от дублей. */
    enum class Kind(val key: String) {
        /** «Oplata»: трата по карте. */
        PURCHASE("purchase"),

        /** «Zachislenie perevoda» по карте: банк так подписывает внесение наличных через банкомат. */
        CASH_DEPOSIT("cashDeposit"),

        /** «Na vashu kartu zachisleno»: входящий перевод, номер карты в таком СМС не указан. */
        INCOMING_TRANSFER("incomingTransfer"),
    }
}

/**
 * Разбор СМС Приорбанка (латиницей). Форматы подтверждены настоящими СМС (см. тесты);
 * всё остальное возвращает null, чтобы не записывать в учёт угаданное.
 */
object PriorbankSms {
    private const val AMOUNT = """(\d[\d ]*(?:[.,]\d+)?)"""
    private val options = setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)

    // Karta 4***8780 19-10-26 14:51:23. Oplata 10.08 BYN. BLR SHOP KOPEECHKA. Balance: 103.82 BYN Tel. 7299090
    private val cardRegex = Regex(
        """Karta\s+[\d*]*?(\d{4})\s+(\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\.\s*(Oplata|Zachislenie\s+perevoda)\s+""" +
            AMOUNT + """\s+([A-Z]{3})\.\s*(.*?)\.\s*Balance:\s*""" + AMOUNT + """\s+[A-Z]{3}""",
        options,
    )

    // 08/10 16:49. Na vashu kartu zachisleno 50.00 BYN. Dostupnaja summa: 63.12 BYN. Tel. 7299090
    private val transferRegex = Regex(
        """(\d{2})/(\d{2})\s+(\d{2}):(\d{2})\.\s*Na\s+vashu\s+kartu\s+zachisleno\s+""" +
            AMOUNT + """\s+([A-Z]{3})\.\s*Dostupnaja\s+summa:\s*""" + AMOUNT + """\s+[A-Z]{3}""",
        options,
    )

    /** `receivedAt` нужен, чтобы достроить год там, где банк его не пишет. */
    fun parse(text: String, receivedAt: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): BankSms? {
        cardRegex.find(text)?.let { m ->
            val g = m.groupValues
            val n = (2..7).map { g[it].toInt() }
            val date = localDate(2000 + n[2], n[1], n[0], n[3], n[4], n[5], zone) ?: return null
            val amount = decimal(g[9]) ?: return null
            val balance = decimal(g[12]) ?: return null
            val kind = if (g[8].equals("oplata", ignoreCase = true)) BankSms.Kind.PURCHASE else BankSms.Kind.CASH_DEPOSIT
            val merchant = if (kind == BankSms.Kind.PURCHASE) displayName(g[11]) else ""
            return BankSms(kind, g[1], date, amount, g[10].uppercase(), merchant, balance, balanceIsAvailable = false)
        }

        transferRegex.find(text)?.let { m ->
            val g = m.groupValues
            val n = (1..4).map { g[it].toInt() }
            val year = receivedAt.atZone(zone).year
            fun make(y: Int) = localDate(y, n[1], n[0], n[2], n[3], 0, zone)
            var date = make(year) ?: return null
            val amount = decimal(g[5]) ?: return null
            val available = decimal(g[7]) ?: return null
            // СМС про декабрь, полученное в январе: год прошлый.
            if (date > receivedAt.plus(Duration.ofDays(1))) make(year - 1)?.let { date = it }
            return BankSms(BankSms.Kind.INCOMING_TRANSFER, null, date, amount, g[6].uppercase(), "", available, balanceIsAvailable = true)
        }
        return null
    }

    private fun localDate(y: Int, mo: Int, d: Int, h: Int, mi: Int, s: Int, zone: ZoneId): Instant? = try {
        LocalDateTime.of(y, mo, d, h, mi, s).atZone(zone).toInstant()
    } catch (_: DateTimeException) {
        null
    }

    private fun decimal(s: String): BigDecimal? = s.replace(" ", "").replace(",", ".").toBigDecimalOrNull()

    /** «BLR SHOP KOPEECHKA» → «SHOP KOPEECHKA»: убираем трёхбуквенный код страны в начале. */
    fun displayName(raw: String): String {
        val name = raw.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        val parts = name.split(" ", limit = 2)
        if (parts.size == 2 && parts[0].length == 3 && parts[0].all { it in 'A'..'Z' }) return parts[1]
        return name
    }
}
