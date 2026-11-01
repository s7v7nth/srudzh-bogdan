package com.timofei.srudzh.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** Таблица курсов: сколько единиц валюты приходится на 1 доллар США. Коды в верхнем регистре. */
data class RateTable(val perUsd: Map<String, BigDecimal> = emptyMap(), val date: Instant? = null) {

    /** Курс «1 единица from = X единиц to». null, если какой-то из валют нет в таблице. */
    fun rate(from: String, to: String): BigDecimal? {
        if (from == to) return BigDecimal.ONE
        val f = perUsd[from] ?: return null
        val t = perUsd[to] ?: return null
        if (f.signum() <= 0) return null
        return t.divide(f, Money.context)
    }

    fun convert(amount: BigDecimal, from: String, to: String): BigDecimal? =
        rate(from, to)?.let { Money.convert(amount, it, Money.fractionDigits(to)) }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** fawazahmed0/currency-api: {"date":"2026-10-18","usd":{"rub":84.12,...}} */
        fun parseFawaz(text: String): RateTable? = runCatching {
            val root = json.parseToJsonElement(text).jsonObject
            val rates = root["usd"] as? JsonObject ?: return null
            val date = (root["date"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                ?.let { runCatching { LocalDate.parse(it).atStartOfDay().toInstant(ZoneOffset.UTC) }.getOrNull() }
            RateTable(clean(rates), date).takeIf { it.perUsd.isNotEmpty() }
        }.getOrNull()

        /** open.er-api.com: {"result":"success","time_last_update_unix":...,"rates":{"RUB":83.2,...}} */
        fun parseErApi(text: String): RateTable? = runCatching {
            val root = json.parseToJsonElement(text).jsonObject
            if (root["result"]?.jsonPrimitive?.content != "success") return null
            val rates = root["rates"] as? JsonObject ?: return null
            val date = (root["time_last_update_unix"] as? JsonPrimitive)?.content?.toBigDecimalOrNull()
                ?.let { Instant.ofEpochSecond(it.toLong()) }
            RateTable(clean(rates), date).takeIf { it.perUsd.isNotEmpty() }
        }.getOrNull()

        /** Число читается сразу как BigDecimal, без промежуточного Double (иначе появляются хвосты вроде ...01). */
        private fun clean(raw: JsonObject): Map<String, BigDecimal> = buildMap {
            for ((k, v) in raw) {
                val p = v as? JsonPrimitive ?: continue
                if (p.isString) continue
                val d = p.content.toBigDecimalOrNull() ?: continue
                if (d.signum() > 0) put(k.uppercase(), d)
            }
        }
    }
}

/** Курсы плюс основная валюта: всё, что нужно для пересчёта сумм операций. */
class Rates(val table: RateTable, val base: String) {
    fun rate(from: String, to: String): BigDecimal? = table.rate(from, to)

    fun convert(amount: BigDecimal, from: String, to: String): BigDecimal? = table.convert(amount, from, to)

    /** Курс операции в валюту `code`: сохранённый на момент операции, если он записан для этой валюты, иначе текущий. */
    fun rateOf(tx: Transaction, currency: String, code: String): BigDecimal? {
        if (tx.baseCode.isNotEmpty() && tx.baseCode == code) return tx.rateToBase
        rate(currency, code)?.let { return it }
        // Валюты операции нет в таблице курсов: идём через сохранённый в операции курс к прежней основной валюте.
        if (tx.baseCode.isEmpty()) return null
        val hop = rate(tx.baseCode, code) ?: return null
        return tx.rateToBase.multiply(hop, Money.context)
    }

    /** Сумма операции в валюте `code` по курсу операции. null, если курса нет. */
    fun valueOf(tx: Transaction, currency: String, code: String): BigDecimal? =
        rateOf(tx, currency, code)?.let { Money.convert(tx.amount, it, Money.fractionDigits(code)) }

    /** Записывает в операцию текущий курс её валюты к основной. */
    fun stamp(tx: Transaction, currency: String, table: RateTable = this.table): Transaction {
        if (base.isEmpty()) return tx
        val r = table.rate(currency, base) ?: return tx
        return tx.copy(rateToBase = r, baseCode = base)
    }
}
