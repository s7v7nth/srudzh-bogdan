package com.timofei.srudzhbogdan.ui.screens

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.SmsFailed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timofei.srudzh.core.PayeeAlias
import com.timofei.srudzh.core.SmsOutcome
import com.timofei.srudzh.core.SmsReview
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.Actions
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.sms.SmsInbox
import com.timofei.srudzhbogdan.ui.AppState
import com.timofei.srudzhbogdan.ui.EmptyState
import com.timofei.srudzhbogdan.ui.ItemRow
import com.timofei.srudzhbogdan.ui.LocalNav
import com.timofei.srudzhbogdan.ui.Palette
import com.timofei.srudzhbogdan.ui.PickerDialog
import com.timofei.srudzhbogdan.ui.Route
import com.timofei.srudzhbogdan.ui.RowDivider
import com.timofei.srudzhbogdan.ui.Screen
import com.timofei.srudzhbogdan.ui.Secondary
import com.timofei.srudzhbogdan.ui.Section
import com.timofei.srudzhbogdan.ui.ValueRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.temporal.ChronoUnit

/** Разрешения для СМС; на Android 13+ ещё и уведомления «пришла операция». */
val smsPermissions: Array<String> =
    SmsInbox.permissions + if (Build.VERSION.SDK_INT >= 33) arrayOf(Manifest.permission.POST_NOTIFICATIONS) else emptyArray()

@Composable
fun SmsSettingsScreen() {
    val nav = LocalNav.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    val pending = l.transactions.count { it.smsReview != SmsReview.DONE }
    var asked by remember { mutableStateOf(false) }
    var pickCard by remember { mutableStateOf<String?>(null) }
    var askPeriod by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var historyResult by remember { mutableStateOf<String?>(null) }
    var pasted by remember { mutableStateOf("") }
    var pasteResult by remember { mutableStateOf<Int?>(null) }
    var periodAfterGrant by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        AppState.smsGranted = SmsInbox.hasPermission(context)
        asked = true
        if (periodAfterGrant && AppState.smsGranted) askPeriod = true
        periodAfterGrant = false
    }

    fun loadHistory(since: Instant?) {
        loading = true
        historyResult = null
        scope.launch {
            val added = withContext(Dispatchers.IO) { SmsInbox.importHistory(context, since) }
            loading = false
            historyResult = if (added > 0) context.getString(R.string.sms_history_result, added) else context.getString(R.string.sms_history_none)
            if (added > 0) nav.push(Route.SmsReview)
        }
    }

    Screen(stringResource(R.string.sms_title), onBack = { nav.pop() }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Section(footer = stringResource(R.string.sms_android_footer) +
                if (asked && !AppState.smsGranted) "\n\n" + stringResource(R.string.sms_permission_manual) else "") {
                ItemRow {
                    Icon(
                        if (AppState.smsGranted) Icons.Filled.Sms else Icons.Filled.SmsFailed, null,
                        tint = if (AppState.smsGranted) Palette.income else Palette.warn,
                    )
                    Text(
                        stringResource(if (AppState.smsGranted) R.string.sms_permission_on else R.string.sms_permission_off),
                        Modifier.weight(1f),
                    )
                }
                if (!AppState.smsGranted) {
                    RowDivider()
                    ItemRow({ permissionLauncher.launch(smsPermissions) }) {
                        Text(stringResource(R.string.sms_permission_grant), color = Palette.accent)
                    }
                }
            }
            Section {
                ValueRow(stringResource(R.string.sms_review), if (pending > 0) "$pending" else null, onClick = { nav.push(Route.SmsReview) })
            }
            Section(stringResource(R.string.sms_cards), stringResource(R.string.sms_cards_hint)) {
                l.cardAliases.sortedBy { it.last4 }.forEachIndexed { i, alias ->
                    if (i > 0) RowDivider()
                    ItemRow({ pickCard = alias.last4 }) {
                        Text("••${alias.last4}", Modifier.weight(1f))
                        Text(l.account(alias.accountId)?.name ?: stringResource(R.string.field_choose), color = Palette.secondary)
                        IconButton({ Actions.deleteCardAlias(alias.last4) }, Modifier.size(32.dp)) {
                            Icon(Icons.Filled.Close, stringResource(R.string.common_delete), tint = Palette.secondary, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            Section {
                ValueRow(stringResource(R.string.alias_title), onClick = { nav.push(Route.PayeeAliases) })
            }
            Section(footer = stringResource(R.string.sms_history_hint)) {
                ItemRow({
                    if (loading) return@ItemRow
                    if (SmsInbox.hasPermission(context)) askPeriod = true
                    else {
                        periodAfterGrant = true
                        permissionLauncher.launch(smsPermissions)
                    }
                }) {
                    Text(stringResource(R.string.sms_history), color = Palette.accent, modifier = Modifier.weight(1f))
                    if (loading) CircularProgressIndicator(Modifier.size(20.dp), color = Palette.accent, strokeWidth = 2.dp)
                }
                historyResult?.let { RowDivider(); ItemRow { Secondary(it) } }
            }
            Section(stringResource(R.string.sms_paste)) {
                ItemRow {
                    BasicTextField(
                        pasted, { pasted = it; pasteResult = null },
                        textStyle = LocalTextStyle.current.copy(color = Palette.text), cursorBrush = SolidColor(Palette.accent),
                        modifier = Modifier.weight(1f).heightIn(min = 72.dp),
                        decorationBox = { inner ->
                            if (pasted.isEmpty()) Text(stringResource(R.string.sms_paste_placeholder), color = Palette.secondary)
                            inner()
                        },
                    )
                }
                RowDivider()
                ItemRow({
                    if (pasted.isBlank()) return@ItemRow
                    pasteResult = when (Actions.importSms(context, pasted)) {
                        is SmsOutcome.Added -> { pasted = ""; R.string.intent_addSMS_added }
                        SmsOutcome.Duplicate -> R.string.intent_addSMS_duplicate
                        SmsOutcome.Unrecognized -> R.string.intent_addSMS_unrecognized
                    }
                }) {
                    Text(stringResource(R.string.sms_paste_add), color = if (pasted.isBlank()) Palette.secondary else Palette.accent)
                }
                pasteResult?.let { RowDivider(); ItemRow { Secondary(stringResource(it)) } }
            }
        }
    }

    pickCard?.let { last4 ->
        val current = l.cardAliases.firstOrNull { it.last4 == last4 }?.accountId
        PickerDialog("••$last4", l.accounts.sortedBy { it.sortId }, l.account(current), { AccountOption(it.name, it.currency) },
            { Actions.setCardAccount(last4, it.id) }) { pickCard = null }
    }
    if (askPeriod) {
        val now = Instant.now()
        val options = listOf(
            R.string.sms_history_month to now.minus(31, ChronoUnit.DAYS),
            R.string.sms_history_3months to now.minus(92, ChronoUnit.DAYS),
            R.string.sms_history_all to null,
        )
        AlertDialog(
            onDismissRequest = { askPeriod = false },
            title = { Text(stringResource(R.string.sms_history_period)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    for ((label, since) in options) {
                        TextButton({ askPeriod = false; loadHistory(since) }, Modifier.fillMaxWidth()) {
                            Text(stringResource(label), color = Palette.accent, modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton({ askPeriod = false }) { Text(stringResource(R.string.common_cancel), color = Palette.secondary) } },
            containerColor = Palette.raised,
        )
    }
}

/** Свои имена магазинов из СМС. Новое имя применяется и к прошлым операциям. */
@Composable
fun PayeeAliasesScreen() {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    Screen(stringResource(R.string.alias_title), onBack = { nav.pop() }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            if (l.payeeAliases.isEmpty()) {
                EmptyState(stringResource(R.string.alias_empty), stringResource(R.string.alias_empty_hint), Icons.Filled.CheckCircle)
            } else {
                Section(footer = stringResource(R.string.alias_list_hint)) {
                    l.payeeAliases.sortedBy { it.name.lowercase() }.forEachIndexed { i, alias ->
                        if (i > 0) RowDivider()
                        AliasRow(alias)
                    }
                }
            }
        }
    }
}

@Composable
private fun AliasRow(alias: PayeeAlias) {
    var text by remember(alias.key, alias.name) { mutableStateOf(alias.name) }
    fun commit() {
        if (text.isBlank()) text = alias.name else if (text != alias.name) Actions.renamePayee(alias.name, text)
    }
    ItemRow {
        Column(Modifier.weight(1f)) {
            BasicTextField(
                text, { text = it }, singleLine = true,
                textStyle = LocalTextStyle.current.copy(color = Palette.text), cursorBrush = SolidColor(Palette.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { commit() }),
                modifier = Modifier.fillMaxWidth().onFocusChanged { if (!it.isFocused) commit() },
            )
            Secondary(alias.original)
        }
        IconButton({ Actions.deletePayeeAlias(alias.key) }, Modifier.size(32.dp)) {
            Icon(Icons.Filled.Close, stringResource(R.string.common_delete), tint = Palette.secondary, modifier = Modifier.size(18.dp))
        }
    }
}
