package com.timofei.srudzhbogdan.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timofei.srudzh.core.Money
import java.math.BigDecimal
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Currency
import java.util.Locale

/** Валюты, доступные для счетов. У BYN собственный знак, он рисуется отдельно (CurrencySymbol). */
object Currencies {
    val all: List<Pair<String, String>> = listOf(
        "BYN" to "Br", "RUB" to "₽", "USD" to "$", "EUR" to "€", "GBP" to "£", "UAH" to "₴", "KZT" to "₸",
        "PLN" to "zł", "CNY" to "¥", "JPY" to "¥", "TRY" to "₺", "GEL" to "₾", "AMD" to "֏", "UZS" to "UZS",
        "KGS" to "KGS", "AZN" to "₼", "MDL" to "MDL", "CHF" to "CHF", "CZK" to "Kč", "CAD" to "C$",
        "AUD" to "A$", "AED" to "AED", "KRW" to "₩", "INR" to "₹",
    )
    val codes = all.map { it.first }

    fun symbol(code: String): String = all.firstOrNull { it.first == code }?.second ?: code

    /** Название на языке интерфейса, с большой буквы. */
    fun name(code: String): String = runCatching { Currency.getInstance(code).getDisplayName(Locale.getDefault()) }
        .getOrDefault(code).replaceFirstChar { it.titlecase(Locale.getDefault()) }

    /** Основная валюта по региону телефона, если она есть в списке. */
    val deviceDefault: String
        get() = runCatching { Currency.getInstance(Locale.getDefault()).currencyCode }.getOrNull()
            ?.takeIf { it in codes } ?: "BYN"
}

object Fmt {
    /** Число с разделителями разрядов и знаками валюты: «1 234,50». */
    fun number(amount: BigDecimal, code: String, signed: Boolean = false): String {
        val d = Money.fractionDigits(code)
        val f = NumberFormat.getNumberInstance(Locale.getDefault()).apply {
            minimumFractionDigits = d
            maximumFractionDigits = d
        }
        val s = f.format(Money.round(amount, d))
        return if (signed && amount.signum() > 0) "+$s" else s
    }

    /** Строка для мест, где знак не нарисовать (уведомления, предложения). У BYN вместо знака код. */
    fun plain(amount: BigDecimal, code: String): String =
        "${number(amount, code)} ${if (code == "BYN") "BYN" else Currencies.symbol(code)}"

    /** Курс с точностью до 4 знаков, с запятой или точкой по языку. */
    fun rate(value: BigDecimal): String = NumberFormat.getNumberInstance(Locale.getDefault()).apply {
        maximumFractionDigits = 4
        isGroupingUsed = false
    }.format(value)

    /** Число для поля ввода: без разделителей разрядов, с запятой или точкой по языку. */
    fun input(amount: BigDecimal): String {
        val sep = java.text.DecimalFormatSymbols.getInstance(Locale.getDefault()).decimalSeparator
        return amount.abs().stripTrailingZeros().toPlainString().replace('.', sep)
    }

    private fun zone() = ZoneId.systemDefault()
    fun day(i: Instant): String = DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).format(i.atZone(zone()))
    fun short(i: Instant): String = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(i.atZone(zone()))
    fun shortTime(i: Instant): String =
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).format(i.atZone(zone()))
    fun time(i: Instant): String = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).format(i.atZone(zone()))
    fun month(i: Instant): String = DateTimeFormatter.ofPattern("LLLL", Locale.getDefault()).format(i.atZone(zone()))
}

/** Сумма с символом валюты. Минус впереди, цифры одной ширины. */
@Composable
fun MoneyText(
    amount: BigDecimal,
    code: String,
    modifier: Modifier = Modifier,
    colored: Boolean = false,
    signed: Boolean = false,
    color: Color? = null,
    weight: FontWeight? = null,
) {
    val tint = color ?: if (colored) {
        when {
            amount.signum() < 0 -> Palette.expense
            amount.signum() > 0 -> Palette.income
            else -> LocalContentColor.current
        }
    } else LocalContentColor.current
    val style = LocalTextStyle.current.let { if (weight != null) it.copy(fontWeight = weight) else it }
        .copy(fontFeatureSettings = "tnum")
    // Зазор между числом и знаком растёт вместе с размером шрифта, иначе в крупной сумме знак прилипает к цифрам.
    val gap = with(LocalDensity.current) { (style.fontSize.toPx() * 0.18f).toDp() }.coerceAtLeast(3.dp)
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(gap), verticalAlignment = Alignment.CenterVertically) {
        Text(Fmt.number(amount, code, signed), color = tint, style = style, maxLines = 1, overflow = TextOverflow.Clip)
        CurrencySymbol(code, color = tint, weight = style.fontWeight ?: FontWeight.Normal)
    }
}

/**
 * Символ валюты. Для BYN буква «Б» шрифта приложения с чертой поверх (знака в Unicode нет), для остальных текст.
 * Черта той же толщины, что и цифры рядом.
 */
@Composable
fun CurrencySymbol(code: String, color: Color = LocalContentColor.current, weight: FontWeight = FontWeight.Normal) {
    val style = LocalTextStyle.current.copy(fontWeight = weight)
    if (code != "BYN") {
        Text(Currencies.symbol(code), color = color, style = style, maxLines = 1)
        return
    }
    val bar = when {
        weight >= FontWeight.ExtraBold -> 0.105f
        weight >= FontWeight.Bold -> 0.095f
        weight >= FontWeight.SemiBold -> 0.084f
        weight >= FontWeight.Medium -> 0.072f
        else -> 0.063f
    }
    var baseline by remember { mutableFloatStateOf(0f) }
    Text(
        "Б", color = color, style = style, maxLines = 1,
        onTextLayout = { baseline = it.firstBaseline },
        modifier = Modifier.drawWithContent {
            drawContent()
            // Пропорции сняты с метрик Manrope: высота заглавных 0,72 em; черта на 71% высоты буквы.
            val em = style.fontSize.toPx()
            val capTop = baseline - 0.72f * em
            val y = capTop + 0.72f * em * 0.71f
            drawRect(color, topLeft = Offset(0f, y - bar * em / 2), size = Size(0.33f * em, bar * em))
        },
    )
}
