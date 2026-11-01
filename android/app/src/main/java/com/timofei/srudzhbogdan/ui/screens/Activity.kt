package com.timofei.srudzhbogdan.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timofei.srudzh.core.Ledger
import com.timofei.srudzh.core.Rates
import com.timofei.srudzh.core.Transaction
import com.timofei.srudzh.core.TxType
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.data.RatesRepo
import com.timofei.srudzhbogdan.ui.BarButton
import com.timofei.srudzhbogdan.ui.EmptyState
import com.timofei.srudzhbogdan.ui.Fmt
import com.timofei.srudzhbogdan.ui.ItemRow
import com.timofei.srudzhbogdan.ui.LocalNav
import com.timofei.srudzhbogdan.ui.MoneyText
import com.timofei.srudzhbogdan.ui.Palette
import com.timofei.srudzhbogdan.ui.PlainField
import com.timofei.srudzhbogdan.ui.Route
import com.timofei.srudzhbogdan.ui.RowDivider
import com.timofei.srudzhbogdan.ui.Screen
import com.timofei.srudzhbogdan.ui.Secondary
import com.timofei.srudzhbogdan.ui.TxCategoryBadge
import com.timofei.srudzhbogdan.ui.TxTypeBadge
import com.timofei.srudzhbogdan.ui.glyph
import com.timofei.srudzhbogdan.ui.label
import com.timofei.srudzhbogdan.ui.tint
import java.time.ZoneId

/** Список операций по дням. Без `accountId` все операции, с ним только этого счёта. */
@Composable
fun ActivityScreen(
    accountId: Int?,
    title: String? = null,
    onBack: (() -> Unit)? = null,
    onEditAccount: (() -> Unit)? = null,
) {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    val table by RatesRepo.table.collectAsStateWithLifecycle()
    val rates = remember(table, l.base) { Rates(table, l.base) }
    var search by rememberSaveable { mutableStateOf("") }
    var typeFilter by rememberSaveable { mutableStateOf<TxType?>(null) }

    val days = remember(l, accountId, search, typeFilter) {
        val q = search.trim()
        val zone = ZoneId.systemDefault()
        l.transactions
            .filter { t ->
                (accountId == null || t.accountId == accountId) &&
                    (typeFilter == null || t.type == typeFilter) &&
                    (q.isEmpty() || t.payee.contains(q, ignoreCase = true) ||
                        (l.category(t.categoryId)?.name?.contains(q, ignoreCase = true) ?: false))
            }
            .sortedByDescending { it.date }
            .groupBy { it.date.atZone(zone).toLocalDate() }
            .toList()
    }

    Screen(
        title ?: stringResource(R.string.tab_activity),
        onBack = onBack,
        inTabs = accountId == null,
        actions = { if (onEditAccount != null) BarButton(stringResource(R.string.common_edit), onClick = onEditAccount) },
    ) {
        LazyColumn(contentPadding = PaddingValues(bottom = 110.dp)) {
            item {
                Row(
                    Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp))
                        .background(Palette.raised).padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Icons.Filled.Search, null, tint = Palette.secondary, modifier = Modifier.size(20.dp))
                    PlainField(search, { search = it }, stringResource(R.string.activity_search), Modifier.weight(1f))
                }
            }
            item {
                Row(
                    Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Chip(null, typeFilter == null) { typeFilter = null }
                    for (t in TxType.entries) Chip(t, typeFilter == t) { typeFilter = if (typeFilter == t) null else t }
                }
            }
            if (days.isEmpty()) {
                item { EmptyState(stringResource(R.string.activity_empty), stringResource(R.string.activity_emptyHint), Icons.AutoMirrored.Filled.List) }
            }
            for ((day, txs) in days) {
                item(key = day.toString()) {
                    Text(
                        Fmt.day(txs.first().date), style = MaterialTheme.typography.labelMedium, color = Palette.secondary,
                        modifier = Modifier.padding(start = 32.dp, top = 14.dp, bottom = 6.dp),
                    )
                }
                item(key = "$day-list") {
                    Column(Modifier.padding(horizontal = 16.dp).clip(RoundedCornerShape(16.dp)).background(Palette.surface)) {
                        txs.forEachIndexed { i, t ->
                            if (i > 0) RowDivider()
                            TxRow(l, rates, t, showAccount = accountId == null) { nav.push(Route.Edit(t.id)) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Chip(type: TxType?, on: Boolean, onClick: () -> Unit) {
    val tint = type?.tint ?: Palette.accent
    Row(
        Modifier.height(34.dp).clip(RoundedCornerShape(50)).background(if (on) Palette.brand else Palette.raised)
            .clickable(onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        val color = if (on) Palette.onBrand else tint
        if (type != null) Icon(type.glyph, null, tint = color, modifier = Modifier.size(16.dp))
        Text(stringResource(type?.label ?: R.string.filter_all), color = color, style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
fun TxRow(l: Ledger, rates: Rates, t: Transaction, showAccount: Boolean, onClick: () -> Unit) {
    val category = l.category(t.categoryId)
    val account = l.account(t.accountId)
    val currency = account?.currency ?: l.base
    ItemRow(onClick) {
        if (t.type == TxType.TRANSFER) TxTypeBadge(TxType.TRANSFER) else TxCategoryBadge(category, t.type)
        Column(Modifier.weight(1f)) {
            val title = when {
                l.isRepayment(t) && t.payee.isEmpty() -> stringResource(R.string.activity_repayment)
                t.payee.isNotEmpty() -> t.payee
                category != null -> category.name
                t.type == TxType.TRANSFER -> stringResource(R.string.tx_transfer)
                else -> stringResource(R.string.category_none)
            }
            Text(title, maxLines = 1)
            val sub = listOfNotNull(
                if (t.type == TxType.TRANSFER && t.payee.isEmpty()) null else category?.name,
                if (showAccount) account?.name else null,
            ).joinToString(" · ")
            if (sub.isNotEmpty()) Secondary(sub)
        }
        if (t.pending) Icon(Icons.Filled.Schedule, null, tint = Palette.secondary, modifier = Modifier.size(18.dp))
        Column(horizontalAlignment = Alignment.End) {
            MoneyText(t.amount, currency, colored = true, weight = FontWeight.SemiBold)
            if (account != null && currency != l.base) {
                rates.valueOf(t, currency, l.base)?.let { v ->
                    Row { Secondary("≈ "); MoneyText(v, l.base, color = Palette.secondary) }
                }
            }
        }
    }
}
