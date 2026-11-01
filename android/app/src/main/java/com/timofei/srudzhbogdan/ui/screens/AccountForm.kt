package com.timofei.srudzhbogdan.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.timofei.srudzh.core.Account
import com.timofei.srudzh.core.AccountKind
import com.timofei.srudzh.core.Money
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.Actions
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.ui.BarButton
import com.timofei.srudzhbogdan.ui.ConfirmDialog
import com.timofei.srudzhbogdan.ui.CurrencySymbol
import com.timofei.srudzhbogdan.ui.Currencies
import com.timofei.srudzhbogdan.ui.FieldError
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

@Composable
fun AccountFormScreen(accountId: Int?) {
    val nav = LocalNav.current
    val context = LocalContext.current
    val ledger = LedgerStore.value
    val existing = ledger.account(accountId)
    val hasTransactions = existing != null && ledger.transactions.any { it.accountId == existing.id }

    var name by rememberSaveable { mutableStateOf(existing?.name ?: "") }
    var kind by rememberSaveable { mutableStateOf(existing?.kind ?: AccountKind.CARD) }
    var currency by rememberSaveable { mutableStateOf(existing?.currency ?: ledger.base) }
    var opening by rememberSaveable { mutableStateOf("") }
    var primary by rememberSaveable { mutableStateOf(existing?.isPrimary ?: true) }
    var excluded by rememberSaveable { mutableStateOf(existing?.excluded ?: false) }
    var submitted by remember { mutableStateOf(false) }
    var pickKind by remember { mutableStateOf(false) }
    var pickCurrency by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    fun save() {
        submitted = true
        if (name.isBlank()) return
        if (existing != null) {
            Actions.updateAccount(
                existing.copy(
                    name = name.trim(), kind = kind, isPrimary = primary, excluded = excluded,
                    currency = if (hasTransactions) existing.currency else currency,
                ),
            )
        } else {
            val draft = Account(id = 0, name = name.trim(), currency = currency, kind = kind, isPrimary = primary, excluded = excluded)
            Actions.createAccount(context, draft, Money.parse(opening))
        }
        nav.pop()
    }

    Screen(
        stringResource(if (existing == null) R.string.account_newTitle else R.string.account_editTitle),
        leading = { BarButton(stringResource(R.string.common_cancel)) { nav.pop() } },
        actions = { BarButton(stringResource(R.string.common_save), bold = true, onClick = ::save) },
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Section(footer = if (hasTransactions) stringResource(R.string.account_currencyLocked) else null) {
                ItemRow {
                    PlainField(name, { name = it }, stringResource(R.string.field_name), Modifier.weight(1f))
                }
                if (submitted && name.isBlank()) FieldError(stringResource(R.string.error_name))
                RowDivider()
                ValueRow(stringResource(R.string.account_kind), stringResource(kind.label), onClick = { pickKind = true })
                RowDivider()
                ValueRow(stringResource(R.string.account_currency), currency, onClick = if (hasTransactions) null else ({ pickCurrency = true }))
                if (existing == null) {
                    RowDivider()
                    ItemRow {
                        PlainField(opening, { opening = it }, stringResource(R.string.account_opening), Modifier.weight(1f), keyboard = KeyboardType.Decimal)
                        CurrencySymbol(currency, color = Palette.secondary)
                    }
                }
                RowDivider()
                ToggleRow(stringResource(R.string.account_primary), primary) { primary = it }
                RowDivider()
                ToggleRow(stringResource(R.string.account_excluded), excluded) { excluded = it }
            }
            if (existing != null) {
                Section {
                    ItemRow({ confirmDelete = true }) {
                        Text(stringResource(R.string.common_delete), color = Palette.expense, modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }

    if (pickKind) {
        val kinds = listOf(AccountKind.CARD, AccountKind.CASH, AccountKind.SAVINGS) + listOfNotNull(existing?.kind).filter {
            it == AccountKind.CREDIT_LINE || it == AccountKind.DEBT
        }
        PickerDialog(stringResource(R.string.account_kind), kinds, kind, { Text(stringResource(it.label)) }, { kind = it }) { pickKind = false }
    }
    if (pickCurrency) {
        PickerDialog(stringResource(R.string.account_currency), Currencies.codes, currency, { code ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("$code · ${Currencies.name(code)}", modifier = Modifier.weight(1f))
                CurrencySymbol(code, color = Palette.secondary)
            }
        }, { currency = it }) { pickCurrency = false }
    }
    if (confirmDelete && existing != null) {
        ConfirmDialog(
            stringResource(R.string.account_deleteTitle), stringResource(R.string.account_deleteMessage),
            stringResource(R.string.common_delete),
            onConfirm = {
                nav.pop()
                Actions.deleteAccount(existing.id)
            },
            onDismiss = { confirmDelete = false },
        )
    }
}
