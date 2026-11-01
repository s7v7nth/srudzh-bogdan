package com.timofei.srudzhbogdan.ui

import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.timofei.srudzh.core.TxType
import com.timofei.srudzhbogdan.R

/**
 * Цвета дизайн-системы «тёмный премиум», те же, что у iPhone-версии. Приложение всегда тёмное.
 * У каждого типа операции свой цвет: расход красный, доход зелёный, перевод синий.
 */
object Palette {
    val bg = Color(0xFF0B0D12)
    val surface = Color(0xFF12151C)
    val raised = Color(0xFF1A1F2A)
    /** Фирменный лайм: заливки (главная кнопка, плюс). Текст на нём только onBrand. */
    val brand = Color(0xFFC5F56B)
    val onBrand = Color(0xFF0B0D12)
    val accent = Color(0xFFC5F56B)
    val expense = Color(0xFFFF7A70)
    val income = Color(0xFF4ADE9A)
    val transfer = Color(0xFF7AA7FF)
    val warn = Color(0xFFFFC15A)
    val text = Color(0xFFF2F3F5)
    val secondary = Color(0xFF9097A3)
    val divider = Color(0x14FFFFFF)

    // Кружки главного экрана: счета жёлтые, доходы голубые, расходы зелёные.
    val chaosIncome = Color(0xFF38B3FA)
    val chaosAccount = Color(0xFFFFBD0D)
    val chaosExpense = Color(0xFF1AC785)
    /** Светлые варианты для текста на цветной подложке: яркий цвет кружка на своём же фоне не читается. */
    val chaosIncomeText = Color(0xFF8CD1FF)
    val chaosAccountText = Color(0xFFFFD159)
    val chaosExpenseText = Color(0xFF73EBB8)
}

val TxType.tint: Color
    get() = when (this) {
        TxType.EXPENSE -> Palette.expense
        TxType.INCOME -> Palette.income
        TxType.TRANSFER -> Palette.transfer
    }

val Manrope = FontFamily(
    Font(R.font.manrope_regular, FontWeight.Normal),
    Font(R.font.manrope_medium, FontWeight.Medium),
    Font(R.font.manrope_semibold, FontWeight.SemiBold),
    Font(R.font.manrope_bold, FontWeight.Bold),
    Font(R.font.manrope_extrabold, FontWeight.ExtraBold),
)

private fun style(size: Int, weight: FontWeight = FontWeight.Normal, line: Int = (size * 1.3).toInt()) =
    TextStyle(fontFamily = Manrope, fontWeight = weight, fontSize = size.sp, lineHeight = line.sp)

private val typography = Typography(
    displayLarge = style(40, FontWeight.ExtraBold, 48),
    headlineLarge = style(32, FontWeight.Bold),
    headlineMedium = style(28, FontWeight.Bold),
    headlineSmall = style(24, FontWeight.Bold),
    titleLarge = style(22, FontWeight.Bold),
    titleMedium = style(17, FontWeight.SemiBold),
    titleSmall = style(15, FontWeight.SemiBold),
    bodyLarge = style(17),
    bodyMedium = style(15),
    bodySmall = style(13),
    labelLarge = style(15, FontWeight.SemiBold),
    labelMedium = style(13, FontWeight.Medium),
    labelSmall = style(11, FontWeight.SemiBold),
)

@Composable
fun SrudzhTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Palette.brand,
            onPrimary = Palette.onBrand,
            secondary = Palette.accent,
            background = Palette.bg,
            onBackground = Palette.text,
            surface = Palette.surface,
            onSurface = Palette.text,
            surfaceVariant = Palette.raised,
            onSurfaceVariant = Palette.secondary,
            surfaceContainer = Palette.surface,
            surfaceContainerHigh = Palette.raised,
            surfaceContainerHighest = Palette.raised,
            surfaceContainerLow = Palette.surface,
            outline = Palette.secondary,
            outlineVariant = Palette.divider,
            error = Palette.expense,
        ),
        typography = typography,
    ) {
        // Без этого текст вне карточек Material берёт чёрный цвет по умолчанию и пропадает на тёмном фоне.
        CompositionLocalProvider(LocalContentColor provides Palette.text, LocalTextStyle provides typography.bodyLarge, content = content)
    }
}
