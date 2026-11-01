package com.timofei.srudzhbogdan.data

import android.content.Context
import android.content.SharedPreferences
import com.timofei.srudzh.core.RateTable
import com.timofei.srudzh.core.Rates
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.net.HttpURLConnection
import java.net.URL
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Курсы валют. Берутся из интернета раз в полсуток; без сети работают последние сохранённые
 * или встроенные в приложение. В сеть уходят только коды валют и дата, суммы и операции не отправляются.
 */
object RatesRepo {
    private const val PRIMARY = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@%s/v1/currencies/usd.json"
    private const val FALLBACK = "https://open.er-api.com/v6/latest/USD"

    private lateinit var prefs: SharedPreferences
    private val tableState = MutableStateFlow(RateTable())
    val table: StateFlow<RateTable> = tableState.asStateFlow()
    private val updatedState = MutableStateFlow<Instant?>(null)
    val lastUpdated: StateFlow<Instant?> = updatedState.asStateFlow()
    val refreshing = MutableStateFlow(false)
    val lastError = MutableStateFlow(false)
    private val dated = mutableMapOf<LocalDate, RateTable>()

    fun init(context: Context) {
        prefs = context.getSharedPreferences("rates", Context.MODE_PRIVATE)
        tableState.value = saved() ?: context.assets.open("rates-seed.json").use {
            RateTable.parseFawaz(it.readBytes().decodeToString())
        } ?: RateTable()
        updatedState.value = prefs.getLong("updated", 0).takeIf { it > 0 }?.let(Instant::ofEpochMilli)
    }

    fun rates(base: String) = Rates(tableState.value, base)

    /** Обновляет курсы, если они старше 12 часов. */
    suspend fun refreshIfNeeded() {
        val last = updatedState.value
        if (last != null && Duration.between(last, Instant.now()) < Duration.ofHours(12)) return
        refresh()
    }

    suspend fun refresh() {
        if (refreshing.value) return
        refreshing.value = true
        try {
            val loaded = load(PRIMARY.format("latest"), RateTable::parseFawaz) ?: load(FALLBACK, RateTable::parseErApi)
            if (loaded != null) {
                tableState.value = loaded
                updatedState.value = Instant.now()
                lastError.value = false
                persist(loaded)
            } else {
                lastError.value = true
            }
        } finally {
            refreshing.value = false
        }
    }

    /** Курсы на конкретную дату (для операций задним числом). null, если сервис недоступен. */
    suspend fun tableOn(date: Instant): RateTable? {
        val day = date.atZone(ZoneId.systemDefault()).toLocalDate()
        synchronized(dated) { dated[day] }?.let { return it }
        val t = load(PRIMARY.format(day.toString()), RateTable::parseFawaz) ?: return null
        synchronized(dated) { dated[day] = t }
        return t
    }

    private suspend fun load(url: String, parse: (String) -> RateTable?): RateTable? = withContext(Dispatchers.IO) {
        runCatching {
            val c = URL(url).openConnection() as HttpURLConnection
            c.connectTimeout = 15_000
            c.readTimeout = 15_000
            try {
                if (c.responseCode != 200) null else parse(c.inputStream.use { it.readBytes().decodeToString() })
            } finally {
                c.disconnect()
            }
        }.getOrNull()
    }

    private fun persist(t: RateTable) {
        val json = buildJsonObject {
            t.date?.let { put("date", it.epochSecond) }
            put("rates", JsonObject(t.perUsd.mapValues { JsonPrimitive(it.value.toPlainString()) }))
        }
        prefs.edit()
            .putString("table", json.toString())
            .putLong("updated", updatedState.value?.toEpochMilli() ?: 0)
            .apply()
    }

    private fun saved(): RateTable? = runCatching {
        val root = Json.parseToJsonElement(prefs.getString("table", null) ?: return null).jsonObject
        val rates = root["rates"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content.toBigDecimal() }
        RateTable(rates, root["date"]?.jsonPrimitive?.longOrNull?.let(Instant::ofEpochSecond)).takeIf { rates.isNotEmpty() }
    }.getOrNull()
}
