package com.timofei.srudzhbogdan.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timofei.srudzh.core.Money
import com.timofei.srudzh.core.Transaction
import com.timofei.srudzh.core.TxType
import com.timofei.srudzh.core.newId
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.Actions
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.data.RatesRepo
import com.timofei.srudzhbogdan.ui.BarButton
import com.timofei.srudzhbogdan.ui.CategoryBadge
import com.timofei.srudzhbogdan.ui.ConfirmDialog
import com.timofei.srudzhbogdan.ui.CurrencySymbol
import com.timofei.srudzhbogdan.ui.EmptyState
import com.timofei.srudzhbogdan.ui.FieldError
import com.timofei.srudzhbogdan.ui.Fmt
import com.timofei.srudzhbogdan.ui.ItemRow
import com.timofei.srudzhbogdan.ui.LocalNav
import com.timofei.srudzhbogdan.ui.Palette
import com.timofei.srudzhbogdan.ui.PickerDialog
import com.timofei.srudzhbogdan.ui.PlainField
import com.timofei.srudzhbogdan.ui.RowDivider
import com.timofei.srudzhbogdan.ui.Screen
import com.timofei.srudzhbogdan.ui.Section
import com.timofei.srudzhbogdan.ui.ToggleRow
import com.timofei.srudzhbogdan.ui.ValueRow
import com.timofei.srudzhbogdan.ui.glyph
import com.timofei.srudzhbogdan.ui.label
import com.timofei.srudzhbogdan.ui.tint
import kotlinx.coroutines.delay
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Новая операция или правка существующей (`editId`). У перевода две половинки: исходящая и входящая,
 * у каждой своя сумма, если валюты счетов разные.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddTransactionScreen(initialType: TxType, from: Int?, to: Int?, category: String?, editId: String?) {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    val zone = ZoneId.systemDefault()

    // Редактируемая операция: для перевода берём исходящую половинку, входящая идёт парой.
    val start = remember { LedgerStore.value }
    val edited = editId?.let { start.transaction(it) }
    val partner = edited?.transferId?.let { id -> start.transactions.firstOrNull { it.transferId == id && it.id != edited.id } }
    val outTx = if (edited != null && edited.type == TxType.TRANSFER && edited.amount.signum() > 0) partner ?: edited else edited
    val inTx = if (edited?.type == TxType.TRANSFER) (if (outTx?.id == edited.id) partner else edited) else null
    val isEditing = outTx != null

    var type by rememberSaveable { mutableStateOf(outTx?.type ?: initialType) }
    var amountText by rememberSaveable { mutableStateOf(outTx?.let { Fmt.input(it.amount) } ?: "") }
    var receivedText by rememberSaveable { mutableStateOf(inTx?.let { Fmt.input(it.amount) } ?: "") }
    var receivedEdited by rememberSaveable { mutableStateOf(isEditing) }
    var payee by rememberSaveable { mutableStateOf(outTx?.payee ?: "") }
    var accountId by rememberSaveable {
        mutableStateOf(outTx?.accountId ?: from ?: start.accounts.sortedBy { it.sortId }.firstOrNull { it.id != to }?.id)
    }
    var toAccountId by rememberSaveable { mutableStateOf(inTx?.accountId ?: to) }
    var categoryId by rememberSaveable { mutableStateOf(outTx?.categoryId ?: category) }
    var dateTime by rememberSaveable { mutableStateOf(LocalDateTime.ofInstant(outTx?.date ?: Instant.now(), zone)) }
    var notes by rememberSaveable { mutableStateOf(outTx?.notes ?: "") }
    var pending by rememberSaveable { mutableStateOf(outTx?.pending ?: false) }
    var submitted by remember { mutableStateOf(false) }

    var pickAccount by remember { mutableStateOf(false) }
    var pickToAccount by remember { mutableStateOf(false) }
    var pickCategory by remember { mutableStateOf(false) }
    var pickDate by remember { mutableStateOf(false) }
    var pickTime by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    val account = l.account(accountId)
    val toAccount = l.account(toAccountId)
    val amount = Money.parse(amountText)?.takeIf { it.signum() > 0 }
    val received = Money.parse(receivedText)?.takeIf { it.signum() > 0 }
    val crossCurrency = type == TxType.TRANSFER && account != null && toAccount != null && account.currency != toAccount.currency

    // Сумма зачисления по текущему курсу, пока пользователь не ввёл свою.
    LaunchedEffect(amountText, accountId, toAccountId, type) {
        if (crossCurrency && !receivedEdited && amount != null) {
            RatesRepo.rates(l.base).convert(amount, account!!.currency, toAccount!!.currency)?.let { receivedText = Fmt.input(it) }
        }
    }

    fun save() {
        submitted = true
        val a = account ?: return
        val value = amount ?: return
        val date = dateTime.atZone(zone).toInstant()
        val txs: List<Transaction>
        if (type == TxType.TRANSFER) {
            val b = toAccount ?: return
            val incoming = if (a.currency == b.currency) value else (received ?: return)
            val transferId = outTx?.transferId ?: newId()
            txs = listOf(
                (outTx ?: Transaction(amount = value, type = type, date = date)).copy(
                    amount = value.negate(), type = TxType.TRANSFER, date = date, notes = notes, pending = pending,
                    transferId = transferId, accountId = a.id, categoryId = null,
                ),
                (inTx ?: Transaction(amount = incoming, type = type, date = date)).copy(
                    amount = incoming, type = TxType.TRANSFER, date = date, notes = notes, pending = pending,
                    transferId = transferId, accountId = b.id, categoryId = null,
                ),
            )
        } else {
            val signed = if (type == TxType.EXPENSE) value.negate() else value
            txs = listOf(
                (outTx ?: Transaction(amount = signed, type = type, date = date)).copy(
                    amount = signed, type = type, date = date, payee = payee.trim(), notes = notes, pending = pending,
                    accountId = a.id, categoryId = categoryId,
                ),
            )
            Actions.touchCategory(categoryId)
        }
        Actions.saveTransactions(txs)
        nav.pop()
    }

    Screen(
        stringResource(if (isEditing) R.string.edit_title else R.string.add_title),
        leading = { BarButton(stringResource(R.string.common_cancel)) { nav.pop() } },
        actions = { BarButton(stringResource(R.string.common_save), bold = true, onClick = ::save) },
    ) {
        if (l.accounts.isEmpty()) {
            EmptyState(stringResource(R.string.add_needAccount), stringResource(R.string.add_need_account_hint), Icons.Filled.CreditCard)
            return@Screen
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            TypeSwitch(type, enabled = !isEditing) {
                type = it
                if (l.category(categoryId)?.isIncome != (it == TxType.INCOME)) categoryId = null
            }
            Section {
                AmountRow(
                    amountText, { amountText = it },
                    stringResource(if (type == TxType.TRANSFER) R.string.transfer_sent else R.string.field_amount),
                    account?.currency ?: l.base, type.tint, autoFocus = !isEditing,
                )
                if (submitted && amount == null) FieldError(stringResource(R.string.error_amount))
            }
            Section {
                ValueRow(
                    stringResource(if (type == TxType.TRANSFER) R.string.transfer_from else R.string.field_account),
                    account?.name ?: stringResource(R.string.field_choose), onClick = { pickAccount = true },
                )
                if (submitted && account == null) FieldError(stringResource(R.string.error_account))
                RowDivider()
                if (type == TxType.TRANSFER) {
                    ValueRow(stringResource(R.string.transfer_to), toAccount?.name ?: stringResource(R.string.field_choose), onClick = { pickToAccount = true })
                    if (submitted && toAccount == null) FieldError(stringResource(R.string.error_toAccount))
                } else {
                    ItemRow { PlainField(payee, { payee = it }, stringResource(R.string.field_payee), Modifier.weight(1f)) }
                    RowDivider()
                    val c = l.category(categoryId)
                    ItemRow({ pickCategory = true }) {
                        Text(stringResource(R.string.field_category), modifier = Modifier.weight(1f))
                        if (c != null) CategoryBadge(c, 24.dp)
                        Text(c?.name ?: stringResource(R.string.category_none), color = Palette.secondary)
                    }
                }
            }
            if (crossCurrency) {
                Section(footer = stringResource(R.string.transfer_rateFooter)) {
                    AmountRow(receivedText, { receivedText = it; receivedEdited = true }, stringResource(R.string.transfer_received), toAccount!!.currency, Palette.transfer)
                    if (submitted && received == null) FieldError(stringResource(R.string.error_received))
                    if (amount != null && received != null) {
                        val rate = Fmt.rate(received.divide(amount, 4, RoundingMode.HALF_UP))
                        Text(
                            stringResource(R.string.transfer_rate, account!!.currency, rate, toAccount.currency),
                            style = MaterialTheme.typography.bodySmall, color = Palette.secondary,
                            modifier = Modifier.padding(start = 16.dp, bottom = 10.dp),
                        )
                    }
                }
            }
            Section {
                ValueRow(stringResource(R.string.field_date), Fmt.short(dateTime.atZone(zone).toInstant()), onClick = { pickDate = true })
                RowDivider()
                ValueRow(stringResource(R.string.field_time), Fmt.time(dateTime.atZone(zone).toInstant()), onClick = { pickTime = true })
                RowDivider()
                ToggleRow(stringResource(R.string.field_pending), pending) { pending = it }
                RowDivider()
                ItemRow { PlainField(notes, { notes = it }, stringResource(R.string.field_notes), Modifier.weight(1f), singleLine = false) }
            }
            if (isEditing) {
                Section {
                    ItemRow({ confirmDelete = true }) {
                        Text(stringResource(R.string.common_delete), color = Palette.expense, modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }

    val accounts = l.accounts.sortedBy { it.sortId }
    if (pickAccount) {
        PickerDialog(stringResource(R.string.field_account), accounts, account, { a -> AccountOption(a.name, a.currency) }, { accountId = it.id }) { pickAccount = false }
    }
    if (pickToAccount) {
        PickerDialog(stringResource(R.string.transfer_to), accounts.filter { it.id != accountId }, toAccount, { a -> AccountOption(a.name, a.currency) }, { toAccountId = it.id }) { pickToAccount = false }
    }
    if (pickCategory) {
        CategoryPicker(isIncome = type == TxType.INCOME, selected = categoryId, onPick = { categoryId = it }, onClose = { pickCategory = false })
    }
    if (pickDate) {
        val state = rememberDatePickerState(initialSelectedDateMillis = dateTime.toLocalDate().atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { pickDate = false },
            confirmButton = {
                TextButton({
                    state.selectedDateMillis?.let {
                        val d = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                        dateTime = LocalDateTime.of(d, dateTime.toLocalTime())
                    }
                    pickDate = false
                }) { Text(stringResource(R.string.common_ok), color = Palette.accent) }
            },
            dismissButton = { TextButton({ pickDate = false }) { Text(stringResource(R.string.common_cancel), color = Palette.secondary) } },
            colors = DatePickerDefaults.colors(containerColor = Palette.raised),
        ) {
            DatePicker(state, colors = DatePickerDefaults.colors(containerColor = Palette.raised, selectedDayContainerColor = Palette.brand, selectedDayContentColor = Palette.onBrand, todayDateBorderColor = Palette.brand))
        }
    }
    if (pickTime) {
        val state = rememberTimePickerState(dateTime.hour, dateTime.minute, is24Hour = true)
        AlertDialog(
            onDismissRequest = { pickTime = false },
            confirmButton = {
                TextButton({
                    dateTime = LocalDateTime.of(dateTime.toLocalDate(), LocalTime.of(state.hour, state.minute))
                    pickTime = false
                }) { Text(stringResource(R.string.common_ok), color = Palette.accent) }
            },
            dismissButton = { TextButton({ pickTime = false }) { Text(stringResource(R.string.common_cancel), color = Palette.secondary) } },
            text = { TimePicker(state) },
            containerColor = Palette.raised,
        )
    }
    if (confirmDelete && edited != null) {
        ConfirmDialog(
            stringResource(R.string.tx_delete_title),
            if (edited.transferId != null) stringResource(R.string.tx_delete_transfer) else null,
            stringResource(R.string.common_delete),
            onConfirm = { nav.pop(); Actions.deleteTransaction(edited.id) },
            onDismiss = { confirmDelete = false },
        )
    }
}

@Composable
fun AccountOption(name: String, currency: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(name, modifier = Modifier.weight(1f))
        Text(currency, color = Palette.secondary)
    }
}

/** Переключатель «расход · доход · перевод» с цветом и стрелкой типа. */
@Composable
private fun TypeSwitch(type: TxType, enabled: Boolean, onChange: (TxType) -> Unit) {
    Row(
        Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(type.tint.copy(alpha = 0.18f)).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (t in TxType.entries) {
            val on = t == type
            Row(
                Modifier.weight(1f).height(38.dp).clip(RoundedCornerShape(10.dp))
                    .background(if (on) Palette.raised else Palette.raised.copy(alpha = 0f))
                    .clickable(enabled = enabled && !on) { onChange(t) },
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
            ) {
                val color = if (on) t.tint else if (enabled) Palette.text else Palette.secondary
                Icon(t.glyph, null, tint = color, modifier = Modifier.size(16.dp))
                Text(" " + stringResource(t.label), color = color, style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

/** Поле суммы с символом валюты справа. В новой операции сразу открывает клавиатуру. */
@Composable
fun AmountRow(
    text: String,
    onChange: (String) -> Unit,
    placeholder: String,
    currency: String,
    color: Color,
    autoFocus: Boolean = false,
) {
    val focus = remember { FocusRequester() }
    if (autoFocus) LaunchedEffect(Unit) {
        delay(300)
        runCatching { focus.requestFocus() }
    }
    ItemRow {
        PlainField(
            text, { s -> onChange(s.filter { it.isDigit() || it == ',' || it == '.' }) }, placeholder,
            Modifier.weight(1f).focusRequester(focus), keyboard = KeyboardType.Decimal,
            style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"), color = color,
        )
        ProvideTextStyle(MaterialTheme.typography.titleLarge) {
            CurrencySymbol(currency, color = Palette.secondary)
        }
    }
}
