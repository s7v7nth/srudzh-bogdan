package com.timofei.srudzhbogdan.data

import android.content.Context
import android.util.Log
import com.timofei.srudzh.core.BackupCodec
import com.timofei.srudzh.core.Ledger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Все данные приложения в памяти и в одном файле в формате копии iPhone.
 * Операций у одного человека тысячи, а не миллионы: файл в пару мегабайт пишется за доли секунды,
 * зато его можно целиком перенести на iPhone и обратно.
 */
object LedgerStore {
    private const val TAG = "LedgerStore"
    private lateinit var file: File
    private val state = MutableStateFlow(Ledger())
    val ledger: StateFlow<Ledger> = state.asStateFlow()

    private val lock = Any()
    private val writer = Executors.newSingleThreadExecutor()
    private val dirty = AtomicBoolean(false)

    fun init(context: Context) {
        file = File(context.filesDir, "ledger.json")
        state.value = load()
    }

    private fun load(): Ledger {
        if (!file.exists()) return Ledger()
        return try {
            BackupCodec.decode(file.readText())
        } catch (e: Exception) {
            // Файл не читается: откладываем его в сторону, а не затираем, чтобы данные можно было достать.
            Log.e(TAG, "ledger file is unreadable", e)
            file.renameTo(File(file.parentFile, "ledger-broken-${System.currentTimeMillis()}.json"))
            Ledger()
        }
    }

    val value: Ledger get() = state.value

    /** Меняет данные и сохраняет их в фоне. Возвращает новое состояние. */
    fun update(change: (Ledger) -> Ledger): Ledger {
        val next = synchronized(lock) {
            val n = change(state.value)
            state.value = n
            n
        }
        scheduleSave()
        return next
    }

    /** Несколько изменений подряд сохраняются одной записью: пишется самое свежее состояние. */
    private fun scheduleSave() {
        if (!dirty.getAndSet(true)) writer.execute {
            while (dirty.getAndSet(false)) write(state.value)
        }
    }

    private fun write(ledger: Ledger) {
        try {
            val tmp = File(file.parentFile, "ledger.json.tmp")
            tmp.writeText(BackupCodec.encode(ledger))
            if (!tmp.renameTo(file)) {
                file.delete()
                tmp.renameTo(file)
            }
        } catch (e: Exception) {
            Log.e(TAG, "save failed", e)
        }
    }

    /** Ждёт, пока данные лягут на диск (нужно, когда СМС пришло при закрытом приложении). */
    fun flush() {
        writer.submit {}.get()
    }
}
