package com.timofei.srudzhbogdan.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timofei.srudzh.core.Account
import com.timofei.srudzh.core.AccountKind
import com.timofei.srudzh.core.Balances
import com.timofei.srudzh.core.Ledger
import com.timofei.srudzh.core.Rates
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.data.RatesRepo
import com.timofei.srudzhbogdan.ui.AppIcons
import com.timofei.srudzhbogdan.ui.AppState
import com.timofei.srudzhbogdan.ui.EmptyState
import com.timofei.srudzhbogdan.ui.ItemRow
import com.timofei.srudzhbogdan.ui.LocalNav
import com.timofei.srudzhbogdan.ui.MoneyText
import com.timofei.srudzhbogdan.ui.Palette
import com.timofei.srudzhbogdan.ui.Route
import com.timofei.srudzhbogdan.ui.RowDivider
import com.timofei.srudzhbogdan.ui.Screen
import com.timofei.srudzhbogdan.ui.Secondary
import com.timofei.srudzhbogdan.ui.Section
import com.timofei.srudzhbogdan.ui.ToggleRow
import java.math.BigDecimal

val AccountKind.label: Int
    get() = when (this) {
        AccountKind.CARD -> R.string.kind_card
        AccountKind.CASH -> R.string.kind_cash
        AccountKind.SAVINGS -> R.string.kind_savings
        AccountKind.CREDIT_LINE -> R.string.kind_creditLine
        AccountKind.DEBT -> R.string.kind_debt
        AccountKind.LOAN -> R.string.kind_loan
    }

/** Общий капитал в основной валюте и коды валют, для которых нет курса. */
fun netWorth(l: Ledger, r: Rates, all: Boolean, includePending: Boolean = true): Pair<BigDecimal, Set<String>> {
    var total = BigDecimal.ZERO
    val missing = mutableSetOf<String>()
    for (a in l.accounts) {
        if (!all && !a.isPrimary) continue
        val b = l.balance(a.id, includePending)
        val v = r.convert(b, a.currency, l.base)
        if (v != null) total = total.add(v) else missing += a.currency
    }
    return total to missing
}

/** Остатки по валютам без пересчёта по курсу. */
fun byCurrency(l: Ledger, all: Boolean, includePending: Boolean = true): List<Pair<String, BigDecimal>> =
    l.accounts.filter { all || it.isPrimary }.groupBy { it.currency }
        .map { (code, list) -> code to list.fold(BigDecimal.ZERO) { s, a -> s.add(l.balance(a.id, includePending)) } }
        .sortedBy { it.first }

/** Кнопка-модификатор: пока держишь, итог показывает все счета, а не только основные. */
@Composable
fun HoldEye(showAll: Boolean, onChange: (Boolean) -> Unit) {
    Box(
        Modifier.size(36.dp).clip(CircleShape)
            .background(if (showAll) Palette.brand else Palette.secondary.copy(alpha = 0.15f))
            .pointerInput(Unit) {
                detectTapGestures(onPress = {
                    onChange(true)
                    tryAwaitRelease()
                    onChange(false)
                })
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            if (showAll) Icons.Filled.Visibility else Icons.Outlined.Visibility,
            stringResource(R.string.chaos_balance_showAll),
            tint = if (showAll) Palette.onBrand else Palette.secondary, modifier = Modifier.size(20.dp),
        )
    }
}

/** Плашка «чтение СМС выключено»: без разрешения приложение не видит СМС банка. */
@Composable
fun SmsOffBanner() {
    val nav = LocalNav.current
    if (AppState.smsGranted) return
    Section {
        ItemRow({ nav.push(Route.SmsSettings) }) {
            Icon(Icons.Filled.Sms, null, tint = Palette.warn)
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.sms_permission_off), color = Palette.warn)
                Secondary(stringResource(R.string.sms_permission_grant))
            }
        }
    }
}

@Composable
fun AccountsScreen() {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    val table by RatesRepo.table.collectAsStateWithLifecycle()
    val rates = remember(table, l.base) { Rates(table, l.base) }
    var showAll by remember { mutableStateOf(false) }
    var includePending by remember { mutableStateOf(true) }
    var expanded by remember { mutableStateOf(false) }

    Screen(
        stringResource(R.string.tab_accounts), inTabs = true,
        leading = { IconButton({ nav.push(Route.Settings) }) { Icon(Icons.Filled.Settings, stringResource(R.string.settings_title)) } },
        actions = { IconButton({ nav.push(Route.AccountForm()) }) { Icon(Icons.Filled.AddCircleOutline, stringResource(R.string.accounts_add)) } },
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 96.dp)) {
            SmsOffBanner()
            Section {
                val (total, missing) = remember(l, rates, showAll, includePending) { netWorth(l, rates, showAll, includePending) }
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            stringResource(if (showAll) R.string.accounts_totalAll else R.string.accounts_total).uppercase(),
                            style = MaterialTheme.typography.labelSmall, color = Palette.secondary,
                        )
                        ProvideTextStyle(MaterialTheme.typography.displayLarge) {
                            MoneyText(total, l.base, colored = true, weight = FontWeight.ExtraBold)
                        }
                    }
                    HoldEye(showAll) { showAll = it }
                }
                if (missing.isNotEmpty()) {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.Warning, null, tint = Palette.warn, modifier = Modifier.size(16.dp))
                        Text(stringResource(R.string.rates_missing, missing.sorted().joinToString(", ")), color = Palette.warn, style = MaterialTheme.typography.bodySmall)
                    }
                }
                val split = byCurrency(l, showAll, includePending)
                if (split.size > 1) {
                    RowDivider()
                    ItemRow({ expanded = !expanded }) {
                        Text(stringResource(R.string.accounts_byCurrency), modifier = Modifier.weight(1f))
                        Icon(if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = Palette.secondary)
                    }
                    if (expanded) for ((code, sum) in split) {
                        ItemRow {
                            Text(code, color = Palette.secondary, modifier = Modifier.weight(1f))
                            MoneyText(sum, code)
                        }
                    }
                }
                RowDivider()
                ToggleRow(stringResource(R.string.accounts_includePending), includePending) { includePending = it }
            }
            Section(header = stringResource(R.string.accounts_header)) {
                if (l.accounts.isEmpty()) {
                    EmptyState(stringResource(R.string.accounts_empty), stringResource(R.string.accounts_emptyHint), Icons.Filled.CreditCard)
                }
                l.accounts.sortedBy { it.sortId }.forEachIndexed { i, a ->
                    if (i > 0) RowDivider()
                    AccountRow(l, rates, a, includePending)
                }
            }
        }
    }
}

@Composable
private fun AccountRow(l: Ledger, rates: Rates, a: Account, includePending: Boolean) {
    val nav = LocalNav.current
    val b = l.balance(a.id, includePending)
    ItemRow({ nav.push(Route.AccountActivity(a.id)) }, onLongClick = { nav.push(Route.AccountForm(a.id)) }) {
        Box(Modifier.size(34.dp).clip(CircleShape).background(Palette.accent.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
            Icon(AppIcons.account(a.kind), null, tint = Palette.accent, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(a.name)
            if (a.isCredit && a.creditLimit != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Secondary(stringResource(R.string.kind_creditLine))
                    MoneyText(Balances.availableCredit(a.creditLimit!!, b), a.currency, color = Palette.secondary)
                }
            } else {
                Secondary(stringResource(a.kind.label))
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            MoneyText(b, a.currency, colored = true, weight = FontWeight.SemiBold)
            if (a.currency != l.base) {
                rates.convert(b, a.currency, l.base)?.let { v ->
                    Row { Secondary("≈ "); MoneyText(v, l.base, color = Palette.secondary) }
                }
            }
        }
    }
}

/** Операции одного счёта. */
@Composable
fun AccountActivityScreen(accountId: Int) {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    val account = l.account(accountId)
    if (account == null) {
        // Счёт удалили из его же экрана: закрываем.
        LaunchedEffect(Unit) { nav.pop() }
        return
    }
    ActivityScreen(accountId = accountId, title = account.name, onBack = { nav.pop() },
        onEditAccount = { nav.push(Route.AccountForm(accountId)) })
}
