package com.timofei.srudzh.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Файл копии в формате iPhone-версии: копию с iPhone можно открыть на Android и наоборот.
 * Счета ссылаются друг на друга по номеру, категории по UUID, суммы хранятся строками, чтобы не терялись копейки.
 * Android дописывает к операциям поле `id`; iPhone такие лишние поля пропускает.
 * Этот же формат служит основным хранилищем данных на телефоне.
 */
object BackupCodec {
    const val CURRENT_VERSION = 1

    /** Swift пишет даты числом секунд от 1 января 2001 года (UTC). */
    private const val REFERENCE_EPOCH = 978_307_200L

    class NewerVersionException : Exception("backup from a newer app version")
    class BrokenFileException(cause: Throwable? = null) : Exception("not a backup file", cause)

    private val json = Json { ignoreUnknownKeys = true }

    // Чтение

    fun decode(text: String): Ledger {
        val root = try {
            json.parseToJsonElement(text).jsonObject
        } catch (e: Exception) {
            throw BrokenFileException(e)
        }
        if ((root.int("version") ?: 1) > CURRENT_VERSION) throw NewerVersionException()
        try {
            val s = root.obj("settings") ?: throw BrokenFileException()
            val settings = Settings(
                baseCurrency = s.str("baseCurrency") ?: "",
                chaos = s.bool("chaos"),
                scheduleWindowDays = s.int("scheduleWindowDays"),
                reportsPeriod = s.int("reportsPeriod"),
                digestEnabled = s.bool("digestEnabled"),
                digestMinutes = s.int("digestMinutes"),
            )
            val accounts = root.objects("accounts").map { a ->
                Account(
                    id = a.int("id") ?: throw BrokenFileException(),
                    name = a.str("name") ?: "",
                    currency = a.str("currency") ?: "",
                    kind = AccountKind.of(a.str("kind") ?: ""),
                    excluded = a.bool("excluded") ?: false,
                    isPrimary = a.bool("isPrimary") ?: true,
                    hiddenOnHome = a.bool("hiddenOnHome") ?: false,
                    sortId = a.int("sortID") ?: 0,
                    graceFromStatement = a.bool("graceFromStatement") ?: true,
                    creditLimit = a.dec("creditLimit"),
                    interestRate = a.dec("interestRate"),
                    minPercent = a.dec("minPercent"),
                    minFloor = a.dec("minFloor"),
                    statementDay = a.int("statementDay"),
                    graceDays = a.int("graceDays"),
                    dueDays = a.int("dueDays"),
                    debtOwedToMe = a.bool("debtOwedToMe"),
                    debtDue = a.date("debtDue"),
                    debtPrincipal = a.dec("debtPrincipal"),
                    loanCategory = a.str("loanCategory"),
                )
            }
            val categories = root.objects("categories").map { c ->
                Category(
                    uuid = c.str("uuid")?.uppercase() ?: throw BrokenFileException(),
                    name = c.str("name") ?: "",
                    isIncome = c.bool("isIncome") ?: false,
                    icon = c.str("icon") ?: "tag",
                    color = c.str("color") ?: "blue",
                    sortId = c.int("sortID") ?: 0,
                    archived = c.bool("archived") ?: false,
                    hiddenOnHome = c.bool("hiddenOnHome") ?: false,
                    lastUsed = c.date("lastUsed"),
                    parent = c.str("parent")?.uppercase(),
                )
            }
            val transactions = root.objects("transactions").map { t ->
                Transaction(
                    id = t.str("id") ?: newId(),
                    amount = t.dec("amount") ?: throw BrokenFileException(),
                    type = TxType.of(t.str("type") ?: ""),
                    date = t.date("date") ?: throw BrokenFileException(),
                    payee = t.str("payee") ?: "",
                    notes = t.str("notes") ?: "",
                    pending = t.bool("pending") ?: false,
                    transferId = t.str("transferID")?.uppercase(),
                    rateToBase = t.dec("rateToBase") ?: BigDecimal.ONE,
                    baseCode = t.str("baseCode") ?: "",
                    accountId = t.int("account"),
                    categoryId = t.str("category")?.uppercase(),
                    smsReview = SmsReview.of(t.int("smsReview") ?: 0),
                    smsKey = t.str("smsKey") ?: "",
                    smsCard = t.str("smsCard") ?: "",
                    smsCurrency = t.str("smsCurrency") ?: "",
                    smsBalance = t.dec("smsBalance"),
                )
            }
            return Ledger(
                settings = settings,
                accounts = accounts,
                categories = categories,
                transactions = transactions,
                cardAliases = root.objects("cardAliases").map { CardAlias(it.str("last4") ?: "", it.int("account")) },
                payeeAliases = root.objects("payeeAliases").map {
                    PayeeAlias(it.str("key") ?: "", it.str("original") ?: "", it.str("name") ?: "")
                },
                budgets = root.objects("budgets"),
                recurring = root.objects("recurring"),
                plan = root.objects("plan"),
            )
        } catch (e: BrokenFileException) {
            throw e
        } catch (e: Exception) {
            throw BrokenFileException(e)
        }
    }

    // Запись

    fun encode(ledger: Ledger, created: Instant = Instant.now()): String = buildJsonObject {
        put("version", CURRENT_VERSION)
        putDate("created", created)
        put("settings", buildJsonObject {
            val s = ledger.settings
            put("baseCurrency", s.baseCurrency)
            s.chaos?.let { put("chaos", it) }
            s.scheduleWindowDays?.let { put("scheduleWindowDays", it) }
            s.reportsPeriod?.let { put("reportsPeriod", it) }
            s.digestEnabled?.let { put("digestEnabled", it) }
            s.digestMinutes?.let { put("digestMinutes", it) }
        })
        put("accounts", buildJsonArray {
            for (a in ledger.accounts.sortedBy { it.sortId }) add(buildJsonObject {
                put("id", a.id)
                put("name", a.name)
                put("currency", a.currency)
                put("kind", a.kind.raw)
                put("excluded", a.excluded)
                put("isPrimary", a.isPrimary)
                put("hiddenOnHome", a.hiddenOnHome)
                put("graceFromStatement", a.graceFromStatement)
                put("sortID", a.sortId)
                putDec("creditLimit", a.creditLimit)
                putDec("interestRate", a.interestRate)
                putDec("minPercent", a.minPercent)
                putDec("minFloor", a.minFloor)
                a.statementDay?.let { put("statementDay", it) }
                a.graceDays?.let { put("graceDays", it) }
                a.dueDays?.let { put("dueDays", it) }
                a.debtOwedToMe?.let { put("debtOwedToMe", it) }
                a.debtDue?.let { putDate("debtDue", it) }
                putDec("debtPrincipal", a.debtPrincipal)
                a.loanCategory?.let { put("loanCategory", it) }
            })
        })
        put("categories", buildJsonArray {
            for (c in ledger.categories) add(buildJsonObject {
                put("uuid", c.uuid)
                put("name", c.name)
                put("icon", c.icon)
                put("color", c.color)
                put("isIncome", c.isIncome)
                put("archived", c.archived)
                put("hiddenOnHome", c.hiddenOnHome)
                put("sortID", c.sortId)
                c.lastUsed?.let { putDate("lastUsed", it) }
                c.parent?.let { put("parent", it) }
            })
        })
        put("transactions", buildJsonArray {
            for (t in ledger.transactions.sortedBy { it.date }) add(buildJsonObject {
                put("id", t.id)
                put("amount", t.amount.plain())
                put("type", t.type.raw)
                putDate("date", t.date)
                put("payee", t.payee)
                put("notes", t.notes)
                put("pending", t.pending)
                t.transferId?.let { put("transferID", it) }
                put("rateToBase", t.rateToBase.plain())
                put("baseCode", t.baseCode)
                t.accountId?.let { put("account", it) }
                t.categoryId?.let { put("category", it) }
                put("smsReview", t.smsReview.raw)
                put("smsKey", t.smsKey)
                put("smsCard", t.smsCard)
                put("smsCurrency", t.smsCurrency)
                putDec("smsBalance", t.smsBalance)
            })
        })
        put("budgets", JsonArray(ledger.budgets))
        put("recurring", JsonArray(ledger.recurring))
        put("plan", JsonArray(ledger.plan))
        put("cardAliases", buildJsonArray {
            for (c in ledger.cardAliases) add(buildJsonObject {
                put("last4", c.last4)
                c.accountId?.let { put("account", it) }
            })
        })
        put("payeeAliases", buildJsonArray {
            for (p in ledger.payeeAliases) add(buildJsonObject {
                put("key", p.key)
                put("original", p.original)
                put("name", p.name)
            })
        })
    }.toString()

    // Имя файла

    private val nameFormat = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss").withZone(ZoneOffset.UTC)

    /** `srudzh-20261025-143210-n1240.json`, как у автокопий iPhone: время копии (UTC) и число операций. */
    fun fileName(date: Instant, transactions: Int): String = "srudzh-${nameFormat.format(date)}-n$transactions.json"

    // Даты

    fun dateToJson(instant: Instant): BigDecimal =
        BigDecimal.valueOf(instant.epochSecond - REFERENCE_EPOCH).add(BigDecimal.valueOf(instant.nano.toLong(), 9))

    fun dateFromJson(seconds: BigDecimal): Instant {
        val whole = seconds.setScale(0, RoundingMode.FLOOR)
        val nanos = seconds.subtract(whole).movePointRight(9).setScale(0, RoundingMode.HALF_UP).toLong()
        return Instant.ofEpochSecond(whole.toLong() + REFERENCE_EPOCH, nanos)
    }

    private fun JsonObjectBuilder.putDate(key: String, value: Instant) = put(key, JsonPrimitive(dateToJson(value)))
    private fun JsonObjectBuilder.putDec(key: String, value: BigDecimal?) {
        if (value != null) put(key, value.plain())
    }

    private fun JsonObject.prim(key: String): JsonPrimitive? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }
    private fun JsonObject.str(key: String): String? = prim(key)?.takeIf { it.isString }?.content
    private fun JsonObject.int(key: String): Int? = prim(key)?.takeIf { !it.isString }?.intOrNull
    private fun JsonObject.bool(key: String): Boolean? = prim(key)?.takeIf { !it.isString }?.booleanOrNull
    private fun JsonObject.dec(key: String): BigDecimal? = str(key)?.toBigDecimalOrNull()
    private fun JsonObject.date(key: String): Instant? =
        prim(key)?.takeIf { !it.isString }?.content?.toBigDecimalOrNull()?.let(::dateFromJson)
    private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
    private fun JsonObject.objects(key: String): List<JsonObject> =
        (this[key] as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
}
