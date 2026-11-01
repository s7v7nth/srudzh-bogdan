package com.timofei.srudzhbogdan.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timofei.srudzh.core.SmsReview
import com.timofei.srudzh.core.TxType
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.data.RatesRepo
import com.timofei.srudzhbogdan.sms.SmsInbox
import com.timofei.srudzhbogdan.sms.SmsNotifier
import com.timofei.srudzhbogdan.ui.screens.AccountActivityScreen
import com.timofei.srudzhbogdan.ui.screens.AccountFormScreen
import com.timofei.srudzhbogdan.ui.screens.AccountsScreen
import com.timofei.srudzhbogdan.ui.screens.ActivityScreen
import com.timofei.srudzhbogdan.ui.screens.AddTransactionScreen
import com.timofei.srudzhbogdan.ui.screens.BackupScreen
import com.timofei.srudzhbogdan.ui.screens.BaseCurrencyScreen
import com.timofei.srudzhbogdan.ui.screens.CategoriesScreen
import com.timofei.srudzhbogdan.ui.screens.CategoryFormScreen
import com.timofei.srudzhbogdan.ui.screens.ChaosHome
import com.timofei.srudzhbogdan.ui.screens.PayeeAliasesScreen
import com.timofei.srudzhbogdan.ui.screens.SettingsScreen
import com.timofei.srudzhbogdan.ui.screens.SmsReviewScreen
import com.timofei.srudzhbogdan.ui.screens.SmsSettingsScreen
import com.timofei.srudzhbogdan.ui.screens.WelcomeScreen
import kotlinx.coroutines.launch

/** Экраны поверх вкладок. Открываются стопкой, «назад» закрывает верхний. */
sealed interface Route {
    data class Add(val type: TxType, val from: Int? = null, val to: Int? = null, val category: String? = null) : Route
    data class Edit(val txId: String) : Route
    data class AccountForm(val accountId: Int? = null) : Route
    data class AccountActivity(val accountId: Int) : Route
    data class CategoryForm(val uuid: String? = null, val isIncome: Boolean = false, val onSaved: ((String) -> Unit)? = null) : Route
    data object Settings : Route
    data object BaseCurrency : Route
    data object Categories : Route
    data object SmsSettings : Route
    data object PayeeAliases : Route
    data object Backup : Route
    data object SmsReview : Route
}

class Navigator {
    private var counter = 0L
    val stack = mutableStateListOf<Pair<Long, Route>>()
    fun push(route: Route) {
        stack.add(counter++ to route)
    }
    fun pop() {
        if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex)
    }
}

val LocalNav = staticCompositionLocalOf<Navigator> { error("no navigator") }

/** То, что меняется вне данных: выдано ли разрешение на СМС. Проверяется при каждом возвращении в приложение. */
object AppState {
    var smsGranted by mutableStateOf(false)
}

@Composable
fun AppRoot(openReview: MutableState<Boolean>) {
    val nav = remember { Navigator() }
    val ledger by LedgerStore.ledger.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    LifecycleResumeEffect(Unit) {
        AppState.smsGranted = SmsInbox.hasPermission(context)
        scope.launch { RatesRepo.refreshIfNeeded() }
        // При заходе в приложение показываем разбор, если накопились СМС банка.
        val l = LedgerStore.value
        if (l.base.isNotEmpty() && nav.stack.isEmpty() && l.transactions.any { it.smsReview != SmsReview.DONE }) {
            nav.push(Route.SmsReview)
        }
        onPauseOrDispose {}
    }
    LaunchedEffect(openReview.value) {
        if (openReview.value) {
            openReview.value = false
            if (nav.stack.none { it.second == Route.SmsReview }) nav.push(Route.SmsReview)
        }
    }

    if (ledger.base.isEmpty()) {
        WelcomeScreen()
        return
    }
    CompositionLocalProvider(LocalNav provides nav) {
        // Объявлен раньше экранов: их собственные «назад» (закрыть окно выбора и т. п.) срабатывают первыми.
        BackHandler(enabled = nav.stack.isNotEmpty()) { nav.pop() }
        Box(Modifier.fillMaxSize().background(Palette.bg)) {
            HomeTabs()
            for ((id, route) in nav.stack) key(id) { RouteHost(route) }
        }
    }
    if (nav.stack.any { it.second == Route.SmsReview }) LaunchedEffect(Unit) { SmsNotifier.clear(context) }
}

@Composable
private fun RouteHost(route: Route) {
    val shown = remember { MutableTransitionState(false).apply { targetState = true } }
    AnimatedVisibility(shown, enter = slideInHorizontally { it / 4 } + fadeIn(), exit = ExitTransition.None) {
        // Пустой обработчик касаний: экран сверху не пропускает нажатия на экраны под ним.
        Box(Modifier.fillMaxSize().background(Palette.bg).pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent() } }) {
            when (route) {
                is Route.Add -> AddTransactionScreen(route.type, route.from, route.to, route.category, null)
                is Route.Edit -> AddTransactionScreen(TxType.EXPENSE, null, null, null, route.txId)
                is Route.AccountForm -> AccountFormScreen(route.accountId)
                is Route.AccountActivity -> AccountActivityScreen(route.accountId)
                is Route.CategoryForm -> CategoryFormScreen(route.uuid, route.isIncome, route.onSaved)
                Route.Settings -> SettingsScreen()
                Route.BaseCurrency -> BaseCurrencyScreen()
                Route.Categories -> CategoriesScreen()
                Route.SmsSettings -> SmsSettingsScreen()
                Route.PayeeAliases -> PayeeAliasesScreen()
                Route.Backup -> BackupScreen()
                Route.SmsReview -> SmsReviewScreen()
            }
        }
    }
}

@Composable
private fun HomeTabs() {
    val nav = LocalNav.current
    val ledger by LedgerStore.ledger.collectAsStateWithLifecycle()
    val chaos = ledger.settings.chaos == true
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var fanOpen by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = Palette.bg,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            NavigationBar(containerColor = Palette.surface) {
                val colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = Palette.onBrand, indicatorColor = Palette.brand,
                    selectedTextColor = Palette.text, unselectedIconColor = Palette.secondary, unselectedTextColor = Palette.secondary,
                )
                NavigationBarItem(
                    selected = tab == 0, onClick = { tab = 0 }, colors = colors,
                    icon = { Icon(if (chaos) Icons.Filled.GridView else Icons.Filled.CreditCard, null) },
                    label = { Text(stringResource(R.string.tab_accounts)) },
                )
                NavigationBarItem(
                    selected = tab == 1, onClick = { tab = 1 }, colors = colors,
                    icon = { Icon(Icons.AutoMirrored.Filled.List, null) },
                    label = { Text(stringResource(R.string.tab_activity)) },
                )
            }
        },
    ) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            when {
                tab == 1 -> ActivityScreen(accountId = null)
                chaos -> ChaosHome()
                else -> AccountsScreen()
            }
            if (fanOpen) {
                Box(
                    Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f))
                        .clickable(remember { MutableInteractionSource() }, null) { fanOpen = false },
                )
            }
            if (!(chaos && tab == 0)) {
                AddFan(fanOpen, onToggle = { fanOpen = !fanOpen }, onPick = { fanOpen = false; nav.push(Route.Add(it)) },
                    modifier = Modifier.align(Alignment.BottomEnd).padding(end = 20.dp, bottom = 20.dp))
            }
        }
    }
}

/** «+» раскрывается в три кнопки: у каждого типа операции свой цвет и стрелка. */
@Composable
private fun AddFan(open: Boolean, onToggle: () -> Unit, onPick: (TxType) -> Unit, modifier: Modifier) {
    val angle by animateFloatAsState(if (open) 45f else 0f, label = "plus")
    Column(modifier, horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for ((i, t) in listOf(TxType.EXPENSE, TxType.INCOME, TxType.TRANSFER).withIndex()) {
            AnimatedVisibility(open, enter = fadeIn() + slideInVertically { it * (3 - i) / 2 }, exit = fadeOut() + slideOutVertically { it * (3 - i) / 2 }) {
                Row(
                    Modifier.shadow(6.dp, CircleShape).background(Palette.raised, RoundedCornerShape(50))
                        .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(50))
                        .clickable { onPick(t) }.padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(stringResource(t.label), style = MaterialTheme.typography.labelLarge)
                    Box(Modifier.size(40.dp).background(t.tint, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(t.glyph, null, tint = Palette.onBrand)
                    }
                }
            }
        }
        Box(
            Modifier.size(56.dp).shadow(14.dp, CircleShape, ambientColor = Palette.brand, spotColor = Palette.brand)
                .background(Palette.brand, CircleShape).clickable(onClick = onToggle),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Add, stringResource(R.string.add_title), tint = Palette.onBrand, modifier = Modifier.size(30.dp).rotate(angle))
        }
    }
}
