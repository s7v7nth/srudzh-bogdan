package com.timofei.srudzh.core

sealed interface CategorySuggestion<out T> {
    /** Магазин видим впервые: показываем квиз со всеми категориями. */
    data object Unknown : CategorySuggestion<Nothing>

    /** Категория понятна: траты идут в дайджест уже с ней. */
    data class Confident<T>(val id: T) : CategorySuggestion<T>

    /** Были разные категории: квиз с вариантами, самые частые первыми. */
    data class Ask<T>(val ids: List<T>) : CategorySuggestion<T>
}

/** Память о магазинах: по прошлым ответам решает, спрашивать пользователя или подставить категорию. */
object MerchantMemory {
    /** Сколько вариантов показывать в квизе (остальное через «другая категория»). */
    const val MAX_OPTIONS = 3

    /** Ключ магазина: регистр, пунктуация, код страны и номер точки не мешают узнать тот же магазин. */
    fun key(merchant: String): String {
        val tokens = merchant.uppercase()
            .map { if (it.isLetterOrDigit()) it else ' ' }
            .joinToString("")
            .split(' ')
            .filter { it.isNotEmpty() }
            .toMutableList()
        if (tokens.size > 1 && tokens[0].length == 3 && tokens[0].all { it in 'A'..'Z' }) tokens.removeAt(0)
        while (tokens.size > 1 && tokens.last().all { it.isDigit() }) tokens.removeAt(tokens.lastIndex)
        return tokens.joinToString(" ")
    }

    /**
     * `counts`: сколько раз в этом магазине выбирали каждую категорию (порядок важен при равенстве).
     * Одна категория за всё время → уверенно. Несколько → спрашиваем, но если одна категория
     * явно доминирует (не меньше 80% при минимум 5 покупках), тоже берём её.
     */
    fun <T> suggest(counts: List<Pair<T, Int>>): CategorySuggestion<T> {
        val used = counts.filter { it.second > 0 }
        if (used.isEmpty()) return CategorySuggestion.Unknown
        if (used.size == 1) return CategorySuggestion.Confident(used[0].first)
        val sorted = used.withIndex()
            .sortedWith(compareByDescending<IndexedValue<Pair<T, Int>>> { it.value.second }.thenBy { it.index })
            .map { it.value }
        val total = sorted.sumOf { it.second }
        if (total >= 5 && sorted[0].second * 5 >= total * 4) return CategorySuggestion.Confident(sorted[0].first)
        return CategorySuggestion.Ask(sorted.take(MAX_OPTIONS).map { it.first })
    }
}
