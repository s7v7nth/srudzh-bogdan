package com.timofei.srudzh.core

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.util.Currency
import java.util.concurrent.ConcurrentHashMap

/**
 * Деньги везде считаем в BigDecimal. Расходы хранятся отрицательными, доходы положительными.
 * Округление «половина от нуля» до знаков валюты, как в iPhone-версии.
 */
object Money {
    /** Точность промежуточных вычислений (деление курсов), с запасом как у Decimal в Swift. */
    val context: MathContext = MathContext.DECIMAL128

    fun round(value: BigDecimal, scale: Int = 2): BigDecimal = value.setScale(scale, RoundingMode.HALF_UP)

    /** Перевод суммы в другую валюту по курсу (сколько единиц целевой валюты в одной исходной). */
    fun convert(amount: BigDecimal, rate: BigDecimal, scale: Int = 2): BigDecimal =
        round(amount.multiply(rate, context), scale)

    private val digitsCache = ConcurrentHashMap<String, Int>()

    /** Сколько знаков после запятой у валюты (BYN 2, JPY 0). */
    fun fractionDigits(code: String): Int = digitsCache.getOrPut(code) {
        runCatching { Currency.getInstance(code).defaultFractionDigits }.getOrNull()?.takeIf { it >= 0 } ?: 2
    }

    /** Разбор введённого числа с запятой или точкой, пробелы внутри не мешают. */
    fun parse(text: String): BigDecimal? =
        text.replace(" ", "").replace(" ", "").replace(" ", "").replace(",", ".").trim().toBigDecimalOrNull()
}

/** Запись числа без лишних нулей, как её пишет iPhone-версия: 1200.00 → «1200», 10.80 → «10.8». */
fun BigDecimal.plain(): String = if (signum() == 0) "0" else stripTrailingZeros().toPlainString()

/** Сравнение сумм без учёта числа знаков: 1200 и 1200.00 равны. */
infix fun BigDecimal.sameAs(other: BigDecimal): Boolean = compareTo(other) == 0
