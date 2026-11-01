package com.timofei.srudzhbogdan.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SmsFailed
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timofei.srudzh.core.AccountKind
import com.timofei.srudzh.core.Ledger
import com.timofei.srudzh.core.Rates
import com.timofei.srudzh.core.TxType
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.data.RatesRepo
import com.timofei.srudzhbogdan.ui.AppIcons
import com.timofei.srudzhbogdan.ui.AppState
import com.timofei.srudzhbogdan.ui.Fmt
import com.timofei.srudzhbogdan.ui.LocalNav
import com.timofei.srudzhbogdan.ui.MoneyText
import com.timofei.srudzhbogdan.ui.Palette
import com.timofei.srudzhbogdan.ui.Route
import java.math.BigDecimal
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlin.math.roundToInt

/** Кружок на главном экране: счёт или категория. */
sealed interface NodeId {
    data class Acc(val id: Int) : NodeId
    data class Cat(val uuid: String) : NodeId
}

/**
 * Что тащим и над чем держим. Точка пальца читается только «призраком» кружка,
 * поэтому движение пальца не пересчитывает весь экран.
 */
@Stable
private class DragState {
    var root: LayoutCoordinates? = null
    val nodes = mutableMapOf<NodeId, LayoutCoordinates>()
    var source by mutableStateOf<NodeId?>(null)
    var hovered by mutableStateOf<NodeId?>(null)
    var finger by mutableStateOf(Offset.Zero)
    /** На сколько кружок-призрак висит над пальцем, чтобы палец его не закрывал. */
    var lift = 0f
}

private val CIRCLE = 50.dp
private val NODE_HEIGHT = 106.dp

/** Суммы за текущий месяц по категориям верхнего уровня (вместе с подкатегориями), в основной валюте. */
private fun monthTotals(l: Ledger, rates: Rates): Map<String, BigDecimal> {
    val zone = ZoneId.systemDefault()
    val month = YearMonth.now(zone)
    val own = mutableMapOf<String, BigDecimal>()
    for (t in l.transactions) {
        if (t.type == TxType.TRANSFER || YearMonth.from(t.date.atZone(zone)) != month) continue
        val c = t.categoryId ?: continue
        val v = rates.valueOf(t, l.currency(t), l.base) ?: continue
        own[c] = (own[c] ?: BigDecimal.ZERO).add(v.abs())
    }
    val result = mutableMapOf<String, BigDecimal>()
    for (c in l.categories) {
        if (c.parent != null) continue
        result[c.uuid] = l.categories.filter { it.parent == c.uuid }
            .fold(own[c.uuid] ?: BigDecimal.ZERO) { s, ch -> s.add(own[ch.uuid] ?: BigDecimal.ZERO) }
    }
    return result
}

private fun monthExpenses(l: Ledger, rates: Rates): BigDecimal {
    val zone = ZoneId.systemDefault()
    val month = YearMonth.now(zone)
    return l.transactions.filter { it.type == TxType.EXPENSE && YearMonth.from(it.date.atZone(zone)) == month }
        .fold(BigDecimal.ZERO) { s, t -> s.add((rates.valueOf(t, l.currency(t), l.base) ?: BigDecimal.ZERO).abs()) }
}

/**
 * Главный экран из кружков: сверху баланс, ниже лента доходов, лента счетов и страницы категорий расходов.
 * Кружок дохода тащим на счёт, счёт на категорию расхода, счёт на счёт (перевод).
 */
@Composable
fun ChaosHome() {
    val nav = LocalNav.current
    val haptic = LocalHapticFeedback.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    val table by RatesRepo.table.collectAsStateWithLifecycle()
    val rates = remember(table, l.base) { Rates(table, l.base) }
    var editing by remember { mutableStateOf(false) }
    val drag = remember { DragState() }
    drag.lift = with(LocalDensity.current) { 36.dp.toPx() }

    val incomeList = l.categories.filter { it.parent == null && it.isIncome && !it.archived && (editing || !it.hiddenOnHome) }.sortedBy { it.sortId }
    val expenseList = l.categories.filter { it.parent == null && !it.isIncome && !it.archived && (editing || !it.hiddenOnHome) }.sortedBy { it.sortId }
    val accountList = l.accounts.filter { editing || !it.hiddenOnHome }.sortedBy { it.sortId }
    val totals = remember(l, rates) { monthTotals(l, rates) }

    fun group(id: NodeId): Int? = when (id) {
        is NodeId.Acc -> 0
        is NodeId.Cat -> l.category(id.uuid)?.let { if (it.isIncome) 1 else 2 }
    }

    /** Что получится, если отпустить `source` над `target`. null, если пара не имеет смысла. */
    fun request(source: NodeId, target: NodeId): Route.Add? {
        if (source is NodeId.Acc && target is NodeId.Acc && source != target) return Route.Add(TxType.TRANSFER, from = source.id, to = target.id)
        if (source is NodeId.Acc && target is NodeId.Cat && l.category(target.uuid)?.isIncome == false) {
            return Route.Add(TxType.EXPENSE, from = source.id, category = target.uuid)
        }
        if (source is NodeId.Cat && l.category(source.uuid)?.isIncome == true && target is NodeId.Acc) {
            return Route.Add(TxType.INCOME, from = target.id, category = source.uuid)
        }
        return null
    }

    fun canDrop(source: NodeId, target: NodeId): Boolean =
        if (editing) source != target && group(source) != null && group(source) == group(target) else request(source, target) != null

    fun target(): NodeId? {
        val root = drag.root ?: return null
        val src = drag.source ?: return null
        val p = drag.finger - Offset(0f, drag.lift)
        return drag.nodes.entries.firstOrNull { (id, c) ->
            id != src && c.isAttached && canDrop(src, id) && root.localBoundingBoxOf(c).inflate(8f).contains(p)
        }?.key
    }

    /** Ставит `source` на место `target`, остальные сдвигаются. */
    fun reorder(source: NodeId, target: NodeId) {
        val ids: List<NodeId> = when (group(source)) {
            0 -> accountList.map { NodeId.Acc(it.id) }
            1 -> incomeList.map { NodeId.Cat(it.uuid) }
            else -> expenseList.map { NodeId.Cat(it.uuid) }
        }
        val from = ids.indexOf(source)
        val to = ids.indexOf(target)
        if (from < 0 || to < 0) return
        val order = ids.toMutableList().apply { removeAt(from); add(to, source) }
        LedgerStore.update { cur ->
            order.withIndex().fold(cur) { acc, (i, id) ->
                when (id) {
                    is NodeId.Acc -> acc.updateAccount(id.id) { it.copy(sortId = i) }
                    is NodeId.Cat -> acc.updateCategory(id.uuid) { it.copy(sortId = i) }
                }
            }
        }
    }

    fun toggleHidden(id: NodeId) = LedgerStore.update { cur ->
        when (id) {
            is NodeId.Acc -> cur.updateAccount(id.id) { it.copy(hiddenOnHome = !it.hiddenOnHome) }
            is NodeId.Cat -> cur.updateCategory(id.uuid) { it.copy(hiddenOnHome = !it.hiddenOnHome) }
        }
    }

    fun tap(id: NodeId) {
        val first = l.accounts.minByOrNull { it.sortId }?.id
        when (id) {
            is NodeId.Acc -> nav.push(if (editing) Route.AccountForm(id.id) else Route.Add(TxType.EXPENSE, from = id.id))
            is NodeId.Cat -> {
                val c = l.category(id.uuid) ?: return
                nav.push(
                    when {
                        editing -> Route.CategoryForm(c.uuid, c.isIncome)
                        c.isIncome -> Route.Add(TxType.INCOME, from = first, category = c.uuid)
                        else -> Route.Add(TxType.EXPENSE, from = first, category = c.uuid)
                    },
                )
            }
        }
    }

    fun drop() {
        val s = drag.source
        val t = drag.hovered
        drag.source = null
        drag.hovered = null
        if (s == null || t == null) return
        if (editing) reorder(s, t) else request(s, t)?.let(nav::push)
    }

    LaunchedEffect(drag.hovered) { if (drag.hovered != null) haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove) }

    // Обработчики живут в одном объекте и обновляются при каждой перерисовке: жест, начатый на кружке,
    // не прерывается, когда экран пересчитывается под пальцем.
    val gestures = remember { NodeGestures() }
    gestures.onTap = ::tap
    gestures.onStart = { id, p ->
        drag.finger = p
        drag.hovered = null
        drag.source = id
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
    }
    gestures.onMove = { p ->
        drag.finger = p
        val h = target()
        if (h != drag.hovered) drag.hovered = h
    }
    gestures.onEnd = ::drop

    @Composable
    fun node(id: NodeId, title: String, icon: ImageVector, color: Color, text: Color, amount: BigDecimal, code: String, hidden: Boolean, width: Dp) {
        val src = drag.source
        Node(
            id, title, icon, color, text, amount, code, isCategory = id is NodeId.Cat, hidden = hidden, editing = editing,
            hovered = drag.hovered == id, isSource = src == id, dimmed = src != null && src != id && !canDrop(src, id),
            width = width, drag = drag, gestures = gestures, onToggleHidden = { toggleHidden(id) },
        )
    }

    Box(Modifier.fillMaxSize().onGloballyPositioned { drag.root = it }) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState(), enabled = drag.source == null)
                .windowInsetsPadding(WindowInsets.statusBars).padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Header(editing, onEdit = { editing = !editing }, onSettings = { nav.push(Route.Settings) }, onSms = { nav.push(Route.SmsSettings) })
            BalanceCard(l, rates)
            Ribbon(stringResource(R.string.chaos_zone_income), Palette.chaosIncome, drag.source == null) { w ->
                for (c in incomeList) node(NodeId.Cat(c.uuid), c.name, AppIcons.of(c.icon), Palette.chaosIncome, Palette.chaosIncomeText, totals[c.uuid] ?: BigDecimal.ZERO, l.base, c.hiddenOnHome, w)
                AddCell(Palette.chaosIncomeText, w) { nav.push(Route.CategoryForm(isIncome = true)) }
            }
            Ribbon(stringResource(R.string.chaos_zone_accounts), Palette.chaosAccount, drag.source == null) { w ->
                for (a in accountList) node(NodeId.Acc(a.id), a.name, AppIcons.account(a.kind), Palette.chaosAccount, Palette.chaosAccountText, l.balance(a.id), a.currency, a.hiddenOnHome, w)
                AddCell(Palette.chaosAccountText, w) { nav.push(Route.AccountForm()) }
            }
            ExpensePages(expenseList.size, drag.source == null) { index, w ->
                if (index < expenseList.size) {
                    val c = expenseList[index]
                    node(NodeId.Cat(c.uuid), c.name, AppIcons.of(c.icon), Palette.chaosExpense, Palette.chaosExpenseText, totals[c.uuid] ?: BigDecimal.ZERO, l.base, c.hiddenOnHome, w)
                } else {
                    AddCell(Palette.chaosExpenseText, w) { nav.push(Route.CategoryForm(isIncome = false)) }
                }
            }
            if (l.transactions.isEmpty() || editing) {
                Text(
                    stringResource(R.string.chaos_hint), style = MaterialTheme.typography.bodySmall, color = Palette.secondary,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp),
                )
            }
        }
        Ghost(drag, l)
    }
}

private class NodeGestures {
    var onTap: (NodeId) -> Unit = {}
    var onStart: (NodeId, Offset) -> Unit = { _, _ -> }
    var onMove: (Offset) -> Unit = {}
    var onEnd: () -> Unit = {}
}

@Composable
private fun Header(editing: Boolean, onEdit: () -> Unit, onSettings: () -> Unit, onSms: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp).height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onSettings) { Icon(Icons.Filled.Settings, stringResource(R.string.settings_title)) }
        Spacer(Modifier.weight(1f))
        if (!AppState.smsGranted) {
            Row(
                Modifier.clip(RoundedCornerShape(50)).background(Palette.warn.copy(alpha = 0.15f)).clickable(onClick = onSms)
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Filled.SmsFailed, null, tint = Palette.warn, modifier = Modifier.size(16.dp))
                Text(stringResource(R.string.sms_off_chip), color = Palette.warn, style = MaterialTheme.typography.labelMedium)
            }
            Spacer(Modifier.weight(1f))
        }
        Box(
            Modifier.padding(end = 4.dp).clip(RoundedCornerShape(50)).background(if (editing) Palette.brand else Palette.secondary.copy(alpha = 0.15f))
                .clickable(onClick = onEdit).padding(horizontal = 14.dp, vertical = 7.dp),
        ) {
            Text(
                stringResource(if (editing) R.string.common_done else R.string.chaos_edit),
                color = if (editing) Palette.onBrand else Palette.text, style = MaterialTheme.typography.labelLarge,
            )
        }
    }
}

@Composable
private fun BalanceCard(l: Ledger, rates: Rates) {
    var showAll by remember { mutableStateOf(false) }
    val total = remember(l, rates, showAll) { netWorth(l, rates, showAll).first }
    val expenses = remember(l, rates) { monthExpenses(l, rates) }
    Box(
        Modifier.padding(horizontal = 12.dp).fillMaxWidth().heightIn(min = 140.dp).shadow(6.dp, RoundedCornerShape(20.dp))
            .clip(RoundedCornerShape(20.dp)).background(Palette.surface).padding(14.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(if (showAll) R.string.chaos_balance_all else R.string.chaos_balance), style = MaterialTheme.typography.labelMedium, color = Palette.secondary)
            ProvideTextStyle(MaterialTheme.typography.headlineLarge.copy(fontSize = 34.sp)) {
                MoneyText(total, l.base, color = if (total.signum() < 0) Palette.expense else Palette.text, weight = FontWeight.Bold)
            }
            if (showAll) {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    ProvideTextStyle(MaterialTheme.typography.labelMedium) {
                        for ((code, sum) in byCurrency(l, all = true)) MoneyText(sum, code, color = Palette.secondary, weight = FontWeight.SemiBold)
                    }
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Filled.ArrowDownward, null, tint = Palette.expense, modifier = Modifier.size(14.dp))
                        Text(
                            stringResource(R.string.chaos_expenses) + " · " + Fmt.month(Instant.now()),
                            color = Palette.expense, style = MaterialTheme.typography.labelMedium,
                        )
                    }
                    ProvideTextStyle(MaterialTheme.typography.titleSmall) { MoneyText(expenses, l.base, weight = FontWeight.SemiBold) }
                }
            }
        }
        Box(Modifier.align(Alignment.TopEnd)) { HoldEye(showAll) { showAll = it } }
    }
}

/** Цветная подложка зоны: бледная, чтобы не спорить с балансом. */
private fun Modifier.zone(tint: Color): Modifier = this
    .clip(RoundedCornerShape(22.dp))
    .background(Brush.linearGradient(listOf(tint.copy(alpha = 0.18f), tint.copy(alpha = 0.05f))))
    .drawBehind {
        drawCircle(Brush.radialGradient(listOf(tint.copy(alpha = 0.22f), Color.Transparent), center = Offset(size.width * 0.15f, 0f), radius = size.height),
            radius = size.height, center = Offset(size.width * 0.15f, 0f))
        drawCircle(Brush.radialGradient(listOf(tint.copy(alpha = 0.14f), Color.Transparent), center = Offset(size.width * 0.85f, size.height), radius = size.height),
            radius = size.height, center = Offset(size.width * 0.85f, size.height))
    }

@Composable
private fun ZoneTitle(text: String) {
    Text(
        text.uppercase(), style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.6.sp), color = Palette.text.copy(alpha = 0.72f),
        modifier = Modifier.padding(start = 20.dp, top = 8.dp, bottom = 2.dp),
    )
}

/** Лента кружков с прокруткой вбок. В ширину помещается ровно 4 кружка. */
@Composable
private fun Ribbon(title: String, tint: Color, scrollable: Boolean, content: @Composable (Dp) -> Unit) {
    BoxWithConstraints(Modifier.padding(horizontal = 12.dp).fillMaxWidth().zone(tint)) {
        val cell = (maxWidth - 16.dp) / 4
        Column {
            ZoneTitle(title)
            Row(Modifier.horizontalScroll(rememberScrollState(), enabled = scrollable).padding(horizontal = 8.dp)) { content(cell) }
        }
    }
}

/** Категории расходов страницами по 2 ряда из 4 кружков, последняя ячейка «+». */
@Composable
private fun ExpensePages(count: Int, scrollable: Boolean, cell: @Composable (Int, Dp) -> Unit) {
    val slots = count + 1
    val pages = (slots + 7) / 8
    val pager = rememberPagerState { pages }
    BoxWithConstraints(Modifier.padding(horizontal = 12.dp).fillMaxWidth().zone(Palette.chaosExpense)) {
        val w = (maxWidth - 16.dp) / 4
        Column(Modifier.padding(bottom = 8.dp)) {
            ZoneTitle(stringResource(R.string.chaos_zone_expenses))
            HorizontalPager(pager, userScrollEnabled = scrollable, verticalAlignment = Alignment.Top) { page ->
                Column(Modifier.padding(horizontal = 8.dp).height(NODE_HEIGHT * 2 + 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (row in 0 until 2) Row {
                        for (col in 0 until 4) {
                            val i = page * 8 + row * 4 + col
                            if (i < slots) cell(i, w) else Spacer(Modifier.width(w))
                        }
                    }
                }
            }
            if (pages > 1) {
                Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.Center) {
                    repeat(pages) { i ->
                        Box(
                            Modifier.padding(3.dp).size(6.dp).clip(CircleShape)
                                .background(if (i == pager.currentPage) Palette.text else Palette.text.copy(alpha = 0.25f)),
                        )
                    }
                }
            }
        }
    }
}

/** Стеклянный кружок с иконкой: цветная заливка, блик по краю и цветная тень. */
@Composable
private fun Bubble(icon: ImageVector, color: Color, size: Dp = CIRCLE) {
    Box(
        Modifier.size(size).shadow(6.dp, CircleShape, ambientColor = color, spotColor = color)
            .background(Brush.linearGradient(listOf(color.copy(alpha = 0.95f), color.copy(alpha = 0.7f))), CircleShape)
            .border(1.dp, Brush.linearGradient(listOf(Color.White.copy(alpha = 0.7f), Color.White.copy(alpha = 0.1f))), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(size * 0.44f))
    }
}

@Composable
private fun Node(
    id: NodeId,
    title: String,
    icon: ImageVector,
    color: Color,
    text: Color,
    amount: BigDecimal,
    code: String,
    isCategory: Boolean,
    hidden: Boolean,
    editing: Boolean,
    hovered: Boolean,
    isSource: Boolean,
    dimmed: Boolean,
    width: Dp,
    drag: DragState,
    gestures: NodeGestures,
    onToggleHidden: () -> Unit,
) {
    val zero = amount.signum() == 0
    val scale by animateFloatAsState(if (hovered) 1.2f else if (isSource) 0.9f else 1f, label = "scale")
    val alpha = when {
        isSource -> 0.35f
        dimmed -> 0.4f
        hidden -> 0.45f
        else -> 1f
    }
    Column(
        Modifier.width(width).height(NODE_HEIGHT).alpha(alpha)
            .onGloballyPositioned { drag.nodes[id] = it }
            .pointerInput(id) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    var cancelled = false
                    val up = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                        waitForUpOrCancellation().also { if (it == null) cancelled = true }
                    }
                    if (up != null) {
                        up.consume()
                        gestures.onTap(id)
                        return@awaitEachGesture
                    }
                    if (cancelled) return@awaitEachGesture
                    // Долгое нажатие: кружок поднимается и едет за пальцем.
                    val root = drag.root ?: return@awaitEachGesture
                    val self = drag.nodes[id] ?: return@awaitEachGesture
                    gestures.onStart(id, root.localPositionOf(self, down.position))
                    drag(down.id) { change ->
                        gestures.onMove(root.localPositionOf(self, change.position))
                        change.consume()
                    }
                    gestures.onEnd()
                }
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(
            title, style = MaterialTheme.typography.labelMedium, color = Palette.text.copy(alpha = 0.72f), maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 4.dp),
        )
        Box(Modifier.size(CIRCLE + 12.dp).scale(scale), contentAlignment = Alignment.Center) {
            if (hovered) Box(Modifier.size(CIRCLE + 12.dp).border(3.dp, color, CircleShape))
            Box(Modifier.alpha(if (zero && isCategory) 0.7f else 1f)) { Bubble(icon, color) }
            if (editing) {
                Icon(
                    if (hidden) Icons.Filled.AddCircle else Icons.Filled.RemoveCircle, null,
                    tint = if (hidden) Palette.income else Palette.expense,
                    modifier = Modifier.align(Alignment.TopStart).size(22.dp).clip(CircleShape).background(Color.White)
                        .clickable(onClick = onToggleHidden),
                )
            }
        }
        // Пустая категория: прочерк вместо «0,00», чтобы взгляд цеплялся только за реальные траты.
        if (zero && isCategory) {
            Text("—", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = text.copy(alpha = 0.4f))
        } else {
            ProvideTextStyle(MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold)) {
                MoneyText(amount, code, color = if (amount.signum() < 0) Palette.expense else text, weight = FontWeight.Bold,
                    modifier = Modifier.alpha(if (zero) 0.5f else 1f))
            }
        }
    }
}

@Composable
private fun AddCell(color: Color, width: Dp, onClick: () -> Unit) {
    Column(
        Modifier.width(width).height(NODE_HEIGHT),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(" ", style = MaterialTheme.typography.labelMedium)
        Box(Modifier.size(CIRCLE + 12.dp), contentAlignment = Alignment.Center) {
            Box(
                Modifier.size(CIRCLE).clip(CircleShape).background(color.copy(alpha = 0.18f))
                    .border(1.dp, Color.White.copy(alpha = 0.25f), CircleShape).clickable(onClick = onClick),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.Add, stringResource(R.string.chaos_add), tint = color) }
        }
    }
}

/** Кружок, который едет за пальцем. */
@Composable
private fun Ghost(drag: DragState, l: Ledger) {
    val src = drag.source ?: return
    val (icon, color) = when (src) {
        is NodeId.Acc -> AppIcons.account(l.account(src.id)?.kind ?: AccountKind.CARD) to Palette.chaosAccount
        is NodeId.Cat -> l.category(src.uuid).let { AppIcons.of(it?.icon) to if (it?.isIncome == true) Palette.chaosIncome else Palette.chaosExpense }
    }
    val half = with(LocalDensity.current) { (CIRCLE / 2).toPx() }
    Box(
        Modifier.offset { IntOffset((drag.finger.x - half).roundToInt(), (drag.finger.y - drag.lift - half).roundToInt()) }.scale(1.1f),
    ) { Bubble(icon, color) }
}
