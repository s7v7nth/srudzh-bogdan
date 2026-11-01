package com.timofei.srudzhbogdan.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timofei.srudzh.core.Category
import com.timofei.srudzh.core.Ledger
import com.timofei.srudzh.core.newId
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.Actions
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.ui.AppIcons
import com.timofei.srudzhbogdan.ui.BarButton
import com.timofei.srudzhbogdan.ui.CategoryBadge
import com.timofei.srudzhbogdan.ui.CategoryColors
import com.timofei.srudzhbogdan.ui.ConfirmDialog
import com.timofei.srudzhbogdan.ui.FieldError
import com.timofei.srudzhbogdan.ui.ItemRow
import com.timofei.srudzhbogdan.ui.LocalNav
import com.timofei.srudzhbogdan.ui.Overlay
import com.timofei.srudzhbogdan.ui.Palette
import com.timofei.srudzhbogdan.ui.PickerDialog
import com.timofei.srudzhbogdan.ui.PlainField
import com.timofei.srudzhbogdan.ui.Route
import com.timofei.srudzhbogdan.ui.RowDivider
import com.timofei.srudzhbogdan.ui.Screen
import com.timofei.srudzhbogdan.ui.Section
import com.timofei.srudzhbogdan.ui.ValueRow

/** Категории верхнего уровня с подкатегориями под ними. */
fun categoryTree(l: Ledger, isIncome: Boolean, includeArchived: Boolean = false): List<Pair<Category, Int>> {
    val pool = l.categories.filter { it.isIncome == isIncome && (includeArchived || !it.archived) }
    return pool.filter { it.parent == null || l.category(it.parent) == null }.sortedBy { it.sortId }.flatMap { p ->
        listOf(p to 0) + pool.filter { it.parent == p.uuid }.sortedBy { it.sortId }.map { it to 1 }
    }
}

/** Выбор категории при вводе операции: недавние сверху, поиск, создание новой. */
@Composable
fun CategoryPicker(isIncome: Boolean, selected: String?, onPick: (String?) -> Unit, onClose: () -> Unit) {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    var search by remember { mutableStateOf("") }
    val pool = l.categories.filter { it.isIncome == isIncome && !it.archived }
    val recent = pool.filter { it.lastUsed != null }.sortedByDescending { it.lastUsed }.take(5)

    fun pick(uuid: String?) {
        onPick(uuid)
        onClose()
    }

    Overlay(onClose) {
        Screen(
            stringResource(R.string.field_category), onBack = onClose,
            actions = {
                IconButton({ nav.push(Route.CategoryForm(isIncome = isIncome, onSaved = { pick(it) })) }) {
                    Icon(Icons.Filled.Add, stringResource(R.string.category_new))
                }
            },
        ) {
            LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    Row(
                        Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp))
                            .background(Palette.raised).padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Filled.Search, null, tint = Palette.secondary, modifier = Modifier.size(20.dp))
                        PlainField(search, { search = it }, stringResource(R.string.category_search), Modifier.weight(1f))
                    }
                }
                if (search.isBlank()) {
                    item {
                        Section {
                            ItemRow({ pick(null) }) {
                                Text(stringResource(R.string.category_none), modifier = Modifier.weight(1f))
                                if (selected == null) Icon(Icons.Filled.Check, null, tint = Palette.accent)
                            }
                        }
                    }
                    if (recent.isNotEmpty()) item {
                        Section(stringResource(R.string.category_recent)) {
                            recent.forEachIndexed { i, c ->
                                if (i > 0) RowDivider()
                                PickRow(c, 0, c.uuid == selected) { pick(c.uuid) }
                            }
                        }
                    }
                    item {
                        Section(stringResource(R.string.category_all)) {
                            categoryTree(l, isIncome).forEachIndexed { i, (c, level) ->
                                if (i > 0) RowDivider()
                                PickRow(c, level, c.uuid == selected) { pick(c.uuid) }
                            }
                        }
                    }
                } else {
                    item {
                        Section {
                            pool.filter { it.name.contains(search.trim(), ignoreCase = true) }.forEachIndexed { i, c ->
                                if (i > 0) RowDivider()
                                PickRow(c, 0, c.uuid == selected) { pick(c.uuid) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PickRow(c: Category, level: Int, selected: Boolean, onClick: () -> Unit) {
    ItemRow(onClick) {
        if (level > 0) Spacer(Modifier.width(20.dp))
        CategoryBadge(c, 28.dp)
        Text(c.name, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Filled.Check, null, tint = Palette.accent)
    }
}

/** Настройки → Категории. */
@Composable
fun CategoriesScreen() {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    Screen(
        stringResource(R.string.settings_categories), onBack = { nav.pop() },
        actions = { IconButton({ nav.push(Route.CategoryForm()) }) { Icon(Icons.Filled.Add, stringResource(R.string.category_new)) } },
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            for ((isIncome, title) in listOf(false to R.string.category_expenses, true to R.string.category_income)) {
                Section(stringResource(title)) {
                    categoryTree(l, isIncome, includeArchived = true).forEachIndexed { i, (c, level) ->
                        if (i > 0) RowDivider()
                        ItemRow({ nav.push(Route.CategoryForm(c.uuid, c.isIncome)) }, modifier = Modifier.alpha(if (c.archived) 0.5f else 1f)) {
                            if (level > 0) Spacer(Modifier.width(20.dp))
                            CategoryBadge(c, 28.dp)
                            Text(c.name, modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun CategoryFormScreen(uuid: String?, initialIncome: Boolean, onSaved: ((String) -> Unit)?) {
    val nav = LocalNav.current
    val l by LedgerStore.ledger.collectAsStateWithLifecycle()
    val existing = remember { LedgerStore.value.category(uuid) }
    var name by rememberSaveable { mutableStateOf(existing?.name ?: "") }
    var isIncome by rememberSaveable { mutableStateOf(existing?.isIncome ?: initialIncome) }
    var parent by rememberSaveable { mutableStateOf(existing?.parent) }
    var icon by rememberSaveable { mutableStateOf(existing?.icon ?: "tag") }
    var color by rememberSaveable { mutableStateOf(existing?.color ?: "blue") }
    var submitted by remember { mutableStateOf(false) }
    var pickParent by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val hasChildren = existing != null && l.categories.any { it.parent == existing.uuid }
    val parents = l.categories.filter { it.parent == null && it.isIncome == isIncome && !it.archived && it.uuid != existing?.uuid }

    fun save() {
        submitted = true
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        val c = existing?.copy(name = trimmed, icon = icon, color = color, parent = parent)
            ?: Category(
                uuid = newId(), name = trimmed, isIncome = isIncome, icon = icon, color = color, parent = parent,
                sortId = (l.categories.filter { it.parent == parent && it.isIncome == isIncome }.maxOfOrNull { it.sortId } ?: -1) + 1,
            )
        Actions.saveCategory(c)
        nav.pop()
        onSaved?.invoke(c.uuid)
    }

    Screen(
        stringResource(if (existing == null) R.string.category_newTitle else R.string.category_editTitle),
        leading = { BarButton(stringResource(R.string.common_cancel)) { nav.pop() } },
        actions = { BarButton(stringResource(R.string.common_save), bold = true, onClick = ::save) },
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Section {
                ItemRow {
                    CategoryBadge(Category(uuid = "", name = name, isIncome = isIncome, icon = icon, color = color), 36.dp)
                    PlainField(name, { name = it }, stringResource(R.string.field_name), Modifier.weight(1f))
                }
                if (submitted && name.isBlank()) FieldError(stringResource(R.string.error_name))
                if (existing == null) {
                    RowDivider()
                    ValueRow(stringResource(R.string.field_type), stringResource(if (isIncome) R.string.tx_income else R.string.tx_expense),
                        onClick = { isIncome = !isIncome; parent = null })
                }
                if (!hasChildren) {
                    RowDivider()
                    ValueRow(stringResource(R.string.category_parent), l.category(parent)?.name ?: stringResource(R.string.category_topLevel),
                        onClick = { pickParent = true })
                }
            }
            Section(stringResource(R.string.category_icon)) {
                Grid(AppIcons.categoryChoices) { i ->
                    Box(
                        Modifier.size(44.dp).clip(CircleShape)
                            .background(if (icon == i) Palette.accent.copy(alpha = 0.2f) else Color.Transparent)
                            .clickable { icon = i },
                        contentAlignment = Alignment.Center,
                    ) { Icon(AppIcons.of(i), null, tint = if (icon == i) Palette.accent else Palette.text) }
                }
            }
            Section(stringResource(R.string.category_color)) {
                Grid(CategoryColors.names) { c ->
                    Box(
                        Modifier.size(34.dp).clip(CircleShape).background(CategoryColors.of(c)).clickable { color = c },
                        contentAlignment = Alignment.Center,
                    ) { if (color == c) Icon(Icons.Filled.Check, null, tint = Color.White) }
                }
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

    if (pickParent) {
        PickerDialog(
            stringResource(R.string.category_parent), listOf<Category?>(null) + parents, l.category(parent),
            { c -> Text(c?.name ?: stringResource(R.string.category_topLevel)) }, { parent = it?.uuid },
        ) { pickParent = false }
    }
    if (confirmDelete && existing != null) {
        val count = l.transactions.count { it.categoryId == existing.uuid }
        ConfirmDialog(
            stringResource(R.string.category_deleteTitle), stringResource(R.string.category_delete_message, count),
            stringResource(R.string.common_delete),
            onConfirm = { nav.pop(); Actions.deleteCategory(existing.uuid) },
            onDismiss = { confirmDelete = false },
        )
    }
}

/** Сетка по 6 в ряд внутри карточки. */
@Composable
private fun <T> Grid(items: List<T>, cell: @Composable (T) -> Unit) {
    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (row in items.chunked(6)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                for (item in row) Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { cell(item) }
                repeat(6 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
