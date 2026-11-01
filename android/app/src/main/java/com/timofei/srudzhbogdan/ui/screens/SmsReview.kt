package com.timofei.srudzhbogdan.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timofei.srudzh.core.Account
import com.timofei.srudzh.core.CategorySuggestion
import com.timofei.srudzh.core.Ledger
import com.timofei.srudzh.core.SmsImporter
import com.timofei.srudzh.core.SmsReview
import com.timofei.srudzh.core.Transaction
import com.timofei.srudzh.core.TxType
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.Actions
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.ui.BarButton
import com.timofei.srudzhbogdan.ui.CategoryBadge
import com.timofei.srudzhbogdan.ui.EmptyState
import com.timofei.srudzhbogdan.ui.Fmt
import com.timofei.srudzhbogdan.ui.ItemRow
import com.timofei.srudzhbogdan.ui.LocalNav
import com.timofei.srudzhbogdan.ui.MoneyText
import com.timofei.srudzhbogdan.ui.Overlay
import com.timofei.srudzhbogdan.ui.Palette
import com.timofei.srudzhbogdan.ui.PickerDialog
import com.timofei.srudzhbogdan.ui.PlainField
import com.timofei.srudzhbogdan.ui.PrimaryButton
import com.timofei.srudzhbogdan.ui.RowDivider
import com.timofei.srudzhbogdan.ui.Screen
import com.timofei.srudzhbogdan.ui.Secondary
import com.timofei.srudzhbogdan.ui.Section
import com.timofei.srudzhbogdan.ui.ValueRow

/** Разбор накопившихся СМС: сначала счета, потом квиз по категориям, в конце дайджест. */
@Composable
fun SmsReviewScreen() {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    var skipped by remember { mutableStateOf(setOf<String>()) }
    var editing by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { Actions.reclassifyQuiz() }

    val pending = l.transactions.filter { it.smsReview != SmsReview.DONE }.sortedBy { it.date }
    val accountStep = pending.firstOrNull { it.smsReview == SmsReview.ACCOUNT }
    val quiz = pending.filter { it.smsReview == SmsReview.QUIZ && it.id !in skipped }
    val digest = pending.filter { it.smsReview == SmsReview.DIGEST }

    val title = when {
        accountStep != null -> stringResource(R.string.sms_account_title)
        quiz.isNotEmpty() -> stringResource(R.string.sms_quiz_title)
        digest.isNotEmpty() -> stringResource(R.string.sms_digest_title)
        else -> stringResource(R.string.sms_title)
    }
    Screen(title, leading = { BarButton(stringResource(R.string.sms_later)) { nav.pop() } }) {
        when {
            accountStep != null -> AccountStep(l, accountStep)
            quiz.isNotEmpty() -> QuizStep(l, quiz.first(), quiz.size) { skipped = skipped + quiz.first().id }
            digest.isNotEmpty() -> DigestStep(l, digest, onEdit = { editing = it }) {
                Actions.finishDigest()
                nav.pop()
            }
            else -> EmptyState(stringResource(R.string.sms_allDone), stringResource(R.string.sms_allDoneHint), Icons.Filled.CheckCircle,
                Modifier.padding(top = 80.dp))
        }
    }
    editing?.let { id -> DigestEdit(id) { editing = null } }
}

// Какой это счёт

@Composable
private fun AccountStep(l: Ledger, tx: Transaction) {
    val context = LocalContext.current
    val forCard = tx.smsCard.isNotEmpty()
    var newName by remember(tx.id) { mutableStateOf("") }

    fun choose(a: Account) {
        if (forCard) Actions.bindCard(tx.smsCard, a) else Actions.assignSms(tx.id, a)
    }

    Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        Section {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (forCard) {
                    Text(stringResource(R.string.sms_account_card, tx.smsCard), style = MaterialTheme.typography.headlineSmall)
                    Secondary(stringResource(R.string.sms_account_cardHint))
                } else {
                    Text(stringResource(R.string.sms_account_transfer), style = MaterialTheme.typography.headlineSmall)
                    ProvideTextStyle(MaterialTheme.typography.titleLarge) { MoneyText(tx.amount, tx.smsCurrency, colored = true) }
                    Secondary(Fmt.shortTime(tx.date))
                }
            }
        }
        if (l.accounts.isNotEmpty()) Section(stringResource(R.string.sms_account_pick)) {
            l.accounts.sortedBy { it.sortId }.forEachIndexed { i, a ->
                if (i > 0) RowDivider()
                ItemRow({ choose(a) }) { AccountOption(a.name, a.currency) }
            }
        }
        Section(stringResource(R.string.sms_account_new)) {
            ItemRow { PlainField(newName, { newName = it }, stringResource(R.string.sms_account_newName), Modifier.weight(1f)) }
            RowDivider()
            ItemRow({
                if (newName.isNotBlank()) {
                    val draft = Account(id = 0, name = newName.trim(), currency = tx.smsCurrency.ifEmpty { l.base })
                    val id = Actions.createAccount(context, draft, null)
                    LedgerStore.value.account(id)?.let(::choose)
                }
            }) {
                Text(stringResource(R.string.sms_account_create), color = if (newName.isBlank()) Palette.secondary else Palette.accent)
            }
        }
    }
}

// Квиз

@Composable
private fun QuizStep(l: Ledger, tx: Transaction, remaining: Int, onSkip: () -> Unit) {
    var renaming by remember { mutableStateOf(false) }
    val suggested = remember(l, tx.id) {
        val s = SmsImporter.suggestion(l, tx)
        if (s is CategorySuggestion.Ask) s.ids.mapNotNull { l.category(it) }.filter { !it.isIncome && !it.archived } else emptyList()
    }
    val account = l.account(tx.accountId)

    Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        Section(stringResource(R.string.sms_quiz_left, remaining)) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(tx.payee, style = MaterialTheme.typography.headlineSmall)
                    ProvideTextStyle(MaterialTheme.typography.headlineMedium) {
                        MoneyText(tx.amount, account?.currency ?: tx.smsCurrency, colored = true)
                    }
                    Secondary(listOfNotNull(Fmt.shortTime(tx.date), account?.name).joinToString(" · "))
                }
                TextButton({ renaming = true }) {
                    Icon(Icons.Filled.Edit, null, tint = Palette.accent, modifier = Modifier.size(18.dp))
                    Text(" " + stringResource(R.string.alias_rename), color = Palette.accent)
                }
            }
        }
        if (suggested.isNotEmpty()) {
            Section(stringResource(R.string.sms_quiz_maybe)) {
                suggested.forEachIndexed { i, c ->
                    if (i > 0) RowDivider()
                    ItemRow({ Actions.answerQuiz(tx.id, c.uuid) }) { CategoryBadge(c); Text(c.name, Modifier.weight(1f)) }
                }
            }
        }
        Section(stringResource(if (suggested.isEmpty()) R.string.sms_quiz_pick else R.string.sms_quiz_other)) {
            categoryTree(l, isIncome = false).filter { (c, _) -> suggested.none { it.uuid == c.uuid } }.forEachIndexed { i, (c, level) ->
                if (i > 0) RowDivider()
                ItemRow({ Actions.answerQuiz(tx.id, c.uuid) }) {
                    if (level > 0) Spacer(Modifier.width(20.dp))
                    CategoryBadge(c)
                    Text(c.name, Modifier.weight(1f))
                }
            }
        }
        Section {
            ItemRow(onSkip) { Text(stringResource(R.string.sms_quiz_skip), color = Palette.accent) }
        }
    }
    if (renaming) RenameDialog(tx.payee, onDismiss = { renaming = false }) { Actions.renamePayee(tx.payee, it) }
}

@Composable
fun RenameDialog(current: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var text by remember { mutableStateOf(current) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.alias_rename_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Secondary(stringResource(R.string.alias_rename_hint))
                PlainField(text, { text = it }, stringResource(R.string.field_payee), Modifier.fillMaxWidth())
            }
        },
        confirmButton = { TextButton({ onSave(text); onDismiss() }) { Text(stringResource(R.string.common_save), color = Palette.accent) } },
        dismissButton = { TextButton(onDismiss) { Text(stringResource(R.string.common_cancel), color = Palette.secondary) } },
        containerColor = Palette.raised,
    )
}

// Дайджест

@Composable
private fun DigestStep(l: Ledger, items: List<Transaction>, onEdit: (String) -> Unit, onFinish: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Section(stringResource(R.string.sms_digest_count, items.size), stringResource(R.string.sms_digest_hint)) {
                items.forEachIndexed { i, t ->
                    if (i > 0) RowDivider()
                    val category = l.category(t.categoryId)
                    val account = l.account(t.accountId)
                    ItemRow({ onEdit(t.id) }) {
                        CategoryBadge(category)
                        Column(Modifier.weight(1f)) {
                            Text(t.payee)
                            Secondary(listOfNotNull(category?.name ?: stringResource(R.string.category_none), account?.name).joinToString(" · "))
                            GapLabel(l, t)
                        }
                        MoneyText(t.amount, account?.currency ?: t.smsCurrency, colored = true)
                    }
                }
            }
        }
        PrimaryButton(stringResource(R.string.sms_digest_ok), Modifier.padding(16.dp), onClick = onFinish)
    }
}

/** «Остаток в банке отличается от приложения на …»: подсказка, что какой-то операции не хватает. */
@Composable
private fun GapLabel(l: Ledger, t: Transaction) {
    val gap = SmsImporter.balanceGap(l, t) ?: return
    val code = l.currency(t)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(Icons.Filled.Warning, null, tint = Palette.warn, modifier = Modifier.size(14.dp))
        Text(stringResource(R.string.sms_gap, Fmt.number(gap, code), code), color = Palette.warn, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun DigestEdit(txId: String, onClose: () -> Unit) {
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    val tx = l.transaction(txId)
    var name by remember { mutableStateOf(tx?.payee ?: "") }
    var pickCategory by remember { mutableStateOf(false) }
    var pickAccount by remember { mutableStateOf(false) }

    fun close() {
        if (tx != null && name.isNotBlank()) Actions.renamePayee(tx.payee, name)
        onClose()
    }

    Overlay(::close) {
        if (tx == null) {
            LaunchedEffect(Unit) { onClose() }
            return@Overlay
        }
        val account = l.account(tx.accountId)
        val category = l.category(tx.categoryId)
        Screen(tx.payee, onBack = ::close) {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Section {
                    ItemRow { PlainField(name, { name = it }, stringResource(R.string.field_payee), Modifier.weight(1f)) }
                    RowDivider()
                    ItemRow {
                        Text(stringResource(R.string.field_amount), Modifier.weight(1f))
                        MoneyText(tx.amount, account?.currency ?: tx.smsCurrency, colored = true, weight = FontWeight.SemiBold)
                    }
                    RowDivider()
                    ValueRow(stringResource(R.string.field_date), Fmt.shortTime(tx.date))
                }
                Section(footer = stringResource(R.string.sms_edit_hint)) {
                    ItemRow({ pickCategory = true }) {
                        Text(stringResource(R.string.field_category), Modifier.weight(1f))
                        if (category != null) CategoryBadge(category, 24.dp)
                        Text(category?.name ?: stringResource(R.string.category_none), color = Palette.secondary)
                    }
                    RowDivider()
                    ValueRow(stringResource(R.string.field_account), account?.name ?: stringResource(R.string.field_choose), onClick = { pickAccount = true })
                }
                if (SmsImporter.balanceGap(l, tx) != null) {
                    Section(footer = stringResource(R.string.sms_gap_hint)) { Row(Modifier.padding(16.dp)) { GapLabel(l, tx) } }
                }
            }
        }
        if (pickCategory) {
            CategoryPicker(tx.type == TxType.INCOME, tx.categoryId, onPick = { uuid ->
                LedgerStore.update { it.updateTransaction(txId) { t -> t.copy(categoryId = uuid) } }
                Actions.touchCategory(uuid)
            }, onClose = { pickCategory = false })
        }
        if (pickAccount) {
            PickerDialog(stringResource(R.string.field_account), l.accounts.sortedBy { it.sortId }, account, { AccountOption(it.name, it.currency) },
                { a -> Actions.saveTransactions(listOf(tx.copy(accountId = a.id))) }) { pickAccount = false }
        }
    }
}
