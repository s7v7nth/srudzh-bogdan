package com.timofei.srudzhbogdan.ui.screens

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timofei.srudzh.core.BackupCodec
import com.timofei.srudzh.core.Ledger
import com.timofei.srudzhbogdan.BuildConfig
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.Actions
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.data.RatesRepo
import com.timofei.srudzhbogdan.ui.AppState
import com.timofei.srudzhbogdan.ui.ConfirmDialog
import com.timofei.srudzhbogdan.ui.CurrencySymbol
import com.timofei.srudzhbogdan.ui.Currencies
import com.timofei.srudzhbogdan.ui.Fmt
import com.timofei.srudzhbogdan.ui.ItemRow
import com.timofei.srudzhbogdan.ui.LocalNav
import com.timofei.srudzhbogdan.ui.Palette
import com.timofei.srudzhbogdan.ui.PrimaryButton
import com.timofei.srudzhbogdan.ui.Route
import com.timofei.srudzhbogdan.ui.RowDivider
import com.timofei.srudzhbogdan.ui.Screen
import com.timofei.srudzhbogdan.ui.Secondary
import com.timofei.srudzhbogdan.ui.Section
import com.timofei.srudzhbogdan.ui.ToggleRow
import com.timofei.srudzhbogdan.ui.ValueRow
import kotlinx.coroutines.launch
import java.time.Instant

@Composable
fun SettingsScreen() {
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    val updated by RatesRepo.lastUpdated.collectAsStateWithLifecycle()
    val refreshing by RatesRepo.refreshing.collectAsStateWithLifecycle()
    val error by RatesRepo.lastError.collectAsStateWithLifecycle()

    Screen(stringResource(R.string.settings_title), onBack = { nav.pop() }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Section(footer = stringResource(R.string.settings_chaosFooter)) {
                ToggleRow(stringResource(R.string.settings_chaos), l.settings.chaos == true) { Actions.setChaos(it) }
            }
            Section {
                ItemRow({ nav.push(Route.BaseCurrency) }) {
                    Text(stringResource(R.string.settings_baseCurrency), Modifier.weight(1f))
                    Text(l.base, color = Palette.secondary)
                    CurrencySymbol(l.base, color = Palette.secondary)
                }
                RowDivider()
                ValueRow(stringResource(R.string.settings_categories), onClick = { nav.push(Route.Categories) })
                RowDivider()
                ValueRow(
                    stringResource(R.string.sms_title),
                    stringResource(if (AppState.smsGranted) R.string.sms_permission_on else R.string.sms_permission_off),
                    onClick = { nav.push(Route.SmsSettings) },
                )
                RowDivider()
                ValueRow(stringResource(R.string.backup_title), onClick = { nav.push(Route.Backup) })
            }
            Section(stringResource(R.string.rates_header), stringResource(R.string.rates_footer)) {
                ValueRow(stringResource(R.string.rates_updated), updated?.let(Fmt::shortTime) ?: stringResource(R.string.rates_builtin))
                if (error) {
                    RowDivider()
                    ItemRow {
                        Icon(Icons.Filled.WifiOff, null, tint = Palette.warn)
                        Text(stringResource(R.string.rates_error), color = Palette.warn, style = MaterialTheme.typography.bodySmall)
                    }
                }
                RowDivider()
                ItemRow({ if (!refreshing) scope.launch { RatesRepo.refresh() } }) {
                    Text(stringResource(R.string.rates_refresh), color = Palette.accent, modifier = Modifier.weight(1f))
                    if (refreshing) CircularProgressIndicator(Modifier.size(20.dp), color = Palette.accent, strokeWidth = 2.dp)
                }
            }
            Secondary(
                "${stringResource(R.string.settings_version)} ${BuildConfig.VERSION_NAME}",
                Modifier.padding(horizontal = 32.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun CurrencyRow(code: String, selected: Boolean, onClick: () -> Unit) {
    ItemRow(onClick) {
        Column(Modifier.weight(1f)) {
            Text(Currencies.name(code))
            Secondary(code)
        }
        CurrencySymbol(code, color = Palette.secondary)
        if (selected) Icon(Icons.Filled.Check, null, tint = Palette.accent)
    }
}

/** Выбор основной валюты в настройках. */
@Composable
fun BaseCurrencyScreen() {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    Screen(stringResource(R.string.settings_baseCurrency), onBack = { nav.pop() }) {
        LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
            item {
                Section(footer = stringResource(R.string.base_footer)) {
                    Currencies.codes.forEachIndexed { i, code ->
                        if (i > 0) RowDivider()
                        CurrencyRow(code, code == l.base) { Actions.setBase(code) }
                    }
                }
            }
        }
    }
}

/** Читает файл копии. Ошибку возвращает текстом, понятным пользователю. */
private fun readBackup(context: Context, uri: Uri): Result<Ledger> = runCatching {
    val text = context.contentResolver.openInputStream(uri)!!.use { it.readBytes().decodeToString() }
    BackupCodec.decode(text)
}.recoverCatching { e ->
    throw IllegalStateException(
        context.getString(if (e is BackupCodec.NewerVersionException) R.string.backup_error_newer else R.string.backup_error_read_android),
    )
}

/** Перенос данных: копия с iPhone на этот телефон и обратно. */
@Composable
fun BackupScreen() {
    val nav = LocalNav.current
    val context = LocalContext.current
    var pendingRestore by remember { mutableStateOf<Ledger?>(null) }
    var message by remember { mutableStateOf<String?>(null) }

    val open = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        readBackup(context, uri).onSuccess { pendingRestore = it }.onFailure { message = it.message }
    }
    val create = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        message = runCatching {
            context.contentResolver.openOutputStream(uri)!!.use { it.write(BackupCodec.encode(LedgerStore.value).toByteArray()) }
            context.getString(R.string.backup_exported)
        }.getOrElse { it.message }
    }

    Screen(stringResource(R.string.backup_title), onBack = { nav.pop() }) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Section(footer = stringResource(R.string.backup_import_hint)) {
                ItemRow({ open.launch(arrayOf("*/*")) }) { Text(stringResource(R.string.backup_import), color = Palette.accent) }
            }
            Section(footer = stringResource(R.string.backup_export_hint)) {
                ItemRow({
                    create.launch(BackupCodec.fileName(Instant.now(), LedgerStore.value.transactions.size))
                }) { Text(stringResource(R.string.backup_export), color = Palette.accent) }
            }
            message?.let { Secondary(it, Modifier.padding(horizontal = 32.dp, vertical = 8.dp)) }
        }
    }

    pendingRestore?.let { backup ->
        ConfirmDialog(
            stringResource(R.string.backup_confirm_title), stringResource(R.string.backup_confirm_android),
            stringResource(R.string.backup_confirm_action),
            onConfirm = {
                Actions.restore(backup)
                message = context.getString(R.string.backup_restored)
            },
            onDismiss = { pendingRestore = null },
        )
    }
}

/** Первый запуск: основная валюта или перенос данных с iPhone. */
@Composable
fun WelcomeScreen() {
    val context = LocalContext.current
    var selected by remember { mutableStateOf(Currencies.deviceDefault) }
    var error by remember { mutableStateOf<String?>(null) }

    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        // Ответ на разрешение не важен: без него приложение тоже работает, СМС можно включить позже в настройках.
        Actions.seedCategories(context)
        Actions.setBase(selected)
    }
    val open = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        readBackup(context, uri).onSuccess { Actions.restore(it) }.onFailure { error = it.message }
    }

    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(vertical = 16.dp)) {
            item {
                Column(Modifier.padding(horizontal = 24.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Image(
                        painterResource(R.mipmap.ic_launcher_foreground), null,
                        Modifier.size(96.dp).clip(RoundedCornerShape(24.dp)),
                    )
                    Text(stringResource(R.string.welcome_title), style = MaterialTheme.typography.headlineMedium)
                    Text(stringResource(R.string.welcome_subtitle), color = Palette.secondary)
                }
            }
            item {
                Section {
                    ItemRow({ open.launch(arrayOf("*/*")) }) {
                        Text(stringResource(R.string.welcome_restore), color = Palette.accent, modifier = Modifier.weight(1f))
                    }
                }
                error?.let { Text(it, color = Palette.expense, modifier = Modifier.padding(horizontal = 32.dp)) }
            }
            item {
                Section(stringResource(R.string.settings_baseCurrency)) {
                    Currencies.codes.forEachIndexed { i, code ->
                        if (i > 0) RowDivider()
                        CurrencyRow(code, code == selected) { selected = code }
                    }
                }
            }
        }
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Secondary(stringResource(R.string.welcome_sms))
            PrimaryButton(stringResource(R.string.welcome_continue)) { permissions.launch(smsPermissions) }
        }
    }
}
