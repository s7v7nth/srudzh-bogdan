package com.timofei.srudzhbogdan.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.timofei.srudzh.core.Category
import com.timofei.srudzh.core.TxType
import com.timofei.srudzhbogdan.R

val TxType.glyph: ImageVector
    get() = when (this) {
        TxType.EXPENSE -> Icons.Filled.ArrowDownward
        TxType.INCOME -> Icons.Filled.ArrowUpward
        TxType.TRANSFER -> Icons.Filled.SwapHoriz
    }

val TxType.label: Int
    get() = when (this) {
        TxType.EXPENSE -> R.string.tx_expense
        TxType.INCOME -> R.string.tx_income
        TxType.TRANSFER -> R.string.tx_transfer
    }

/** Экран с заголовком: слева «назад» или текстовая кнопка, справа действия. */
@Composable
fun Screen(
    title: String,
    onBack: (() -> Unit)? = null,
    leading: (@Composable () -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    /** Внутри вкладок низ экрана занят панелью вкладок: отступ нужен только сверху. */
    inTabs: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val insets = if (inTabs) WindowInsets.statusBars else WindowInsets.safeDrawing
    Column(Modifier.fillMaxSize().background(Palette.bg).windowInsetsPadding(insets)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            when {
                leading != null -> leading()
                onBack != null -> IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.common_back))
                }
                else -> Spacer(Modifier.width(12.dp))
            }
            Text(
                title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).padding(horizontal = 4.dp),
            )
            actions()
        }
        content()
    }
}

/** Текстовая кнопка в шапке экрана («Отмена», «Сохранить»). */
@Composable
fun BarButton(text: String, enabled: Boolean = true, bold: Boolean = false, onClick: () -> Unit) {
    TextButton(onClick = onClick, enabled = enabled) {
        Text(
            text, color = if (enabled) Palette.accent else Palette.secondary,
            fontWeight = if (bold) FontWeight.Bold else FontWeight.Medium,
        )
    }
}

/** Группа строк на карточке, как сгруппированный список iPhone. */
@Composable
fun Section(
    header: String? = null,
    footer: String? = null,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        if (header != null) {
            Text(
                header.uppercase(), style = MaterialTheme.typography.labelSmall, color = Palette.secondary,
                modifier = Modifier.padding(start = 16.dp, bottom = 6.dp),
            )
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Palette.surface)) { content() }
        if (footer != null) {
            Text(
                footer, style = MaterialTheme.typography.bodySmall, color = Palette.secondary,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp),
            )
        }
    }
}

@Composable
fun RowDivider() = HorizontalDivider(Modifier.padding(start = 16.dp), color = Palette.divider)

/** Строка карточки: что угодно слева, по нажатию действие. */
@Composable
fun ItemRow(
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    val m = if (onClick != null || onLongClick != null) {
        modifier.combinedClickableCompat(onClick ?: {}, onLongClick)
    } else modifier
    Row(
        m.fillMaxWidth().heightIn(min = 50.dp).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

/** Подпись слева, значение справа. */
@Composable
fun ValueRow(label: String, value: String? = null, onClick: (() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null) {
    ItemRow(onClick) {
        Text(label, modifier = Modifier.weight(1f))
        if (value != null) Text(value, color = Palette.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        trailing?.invoke()
    }
}

@Composable
fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    ItemRow({ onChange(!checked) }) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(
            checked = checked, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = Palette.brand, checkedThumbColor = Palette.onBrand),
        )
    }
}

/** Поле ввода без рамки, внутри строки карточки. */
@Composable
fun PlainField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    keyboard: KeyboardType = KeyboardType.Text,
    style: TextStyle = LocalTextStyle.current,
    color: Color = Palette.text,
    singleLine: Boolean = true,
) {
    BasicTextField(
        value = value, onValueChange = onChange, singleLine = singleLine,
        textStyle = style.copy(color = color), cursorBrush = SolidColor(Palette.accent),
        keyboardOptions = KeyboardOptions(keyboardType = keyboard),
        modifier = modifier,
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, style = style, color = Palette.secondary)
                inner()
            }
        },
    )
}

@Composable
fun FieldError(text: String) {
    Text(text, color = Palette.expense, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
}

/** Круглый значок категории её цветом. */
@Composable
fun CategoryBadge(category: Category?, size: Dp = 30.dp) {
    val c = CategoryColors.of(category?.color)
    Box(Modifier.size(size).clip(CircleShape).background(c.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
        Icon(AppIcons.of(category?.icon), null, tint = c, modifier = Modifier.size(size * 0.55f))
    }
}

/** Круглая иконка типа операции для списков. */
@Composable
fun TxTypeBadge(type: TxType, size: Dp = 36.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(type.tint.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
        Icon(type.glyph, null, tint = type.tint, modifier = Modifier.size(size * 0.5f))
    }
}

/** Значок категории с маленькой меткой типа операции в углу. */
@Composable
fun TxCategoryBadge(category: Category?, type: TxType) {
    Box {
        CategoryBadge(category, 36.dp)
        Box(
            Modifier.align(Alignment.BottomEnd).offset(4.dp, 4.dp).size(16.dp).clip(CircleShape)
                .background(type.tint).border(1.5.dp, Palette.bg, CircleShape),
            contentAlignment = Alignment.Center,
        ) { Icon(type.glyph, null, tint = Color.White, modifier = Modifier.size(10.dp)) }
    }
}

@Composable
fun EmptyState(title: String, hint: String? = null, icon: ImageVector? = null, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (icon != null) Icon(icon, null, tint = Palette.secondary, modifier = Modifier.size(44.dp))
        Text(title, style = MaterialTheme.typography.titleMedium)
        if (hint != null) Text(hint, color = Palette.secondary, style = MaterialTheme.typography.bodyMedium)
    }
}

/** Большая лаймовая кнопка внизу экрана. */
@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        modifier.fillMaxWidth().heightIn(min = 52.dp).clip(RoundedCornerShape(16.dp))
            .background(if (enabled) Palette.brand else Palette.raised)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = if (enabled) Palette.onBrand else Palette.secondary, style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
fun ConfirmDialog(title: String, message: String?, confirm: String, destructive: Boolean = true, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = message?.let { { Text(it) } },
        confirmButton = {
            TextButton(onClick = { onConfirm(); onDismiss() }) {
                Text(confirm, color = if (destructive) Palette.expense else Palette.accent)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel), color = Palette.secondary) } },
        containerColor = Palette.raised,
    )
}

/** Выбор одного варианта из списка в окне (счёт, валюта, тип). */
@Composable
fun <T> PickerDialog(
    title: String,
    options: List<T>,
    selected: T?,
    label: @Composable (T) -> Unit,
    onPick: (T) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            LazyColumn {
                items(options) { o ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { onPick(o); onDismiss() }
                            .padding(horizontal = 8.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.weight(1f)) { label(o) }
                        if (o == selected) Icon(Icons.Filled.Check, null, tint = Palette.accent)
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel), color = Palette.secondary) } },
        containerColor = Palette.raised,
    )
}

/** Окно на весь экран поверх текущего (выбор категории и т. п.). «Назад» закрывает его. */
@Composable
fun Overlay(onClose: () -> Unit, content: @Composable () -> Unit) {
    BackHandler(onBack = onClose)
    Box(Modifier.fillMaxSize().background(Palette.bg).pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent() } }) {
        content()
    }
}

@OptIn(ExperimentalFoundationApi::class)
fun Modifier.combinedClickableCompat(onClick: () -> Unit, onLongClick: (() -> Unit)?): Modifier =
    combinedClickable(onClick = onClick, onLongClick = onLongClick)

/** Вторичный текст строки. */
@Composable
fun Secondary(text: String, modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE) {
    CompositionLocalProvider(LocalContentColor provides Palette.secondary) {
        Text(text, style = MaterialTheme.typography.bodySmall, modifier = modifier, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
    }
}
