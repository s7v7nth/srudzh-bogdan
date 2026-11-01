package com.timofei.srudzhbogdan.sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Telephony
import androidx.core.content.ContextCompat
import com.timofei.srudzhbogdan.data.Actions
import java.time.Instant

object SmsInbox {
    /** Разрешения, без которых приложение не видит СМС. */
    val permissions = arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS)

    fun hasPermission(context: Context): Boolean = permissions.all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Загружает СМС банка из памяти телефона начиная с `since` (null — все).
     * Возвращает число новых операций: уже добавленные СМС узнаются и не повторяются.
     */
    fun importHistory(context: Context, since: Instant?): Int {
        val messages = mutableListOf<Pair<String, Instant>>()
        val selection = since?.let { "${Telephony.Sms.DATE} >= ?" }
        val args = since?.let { arrayOf(it.toEpochMilli().toString()) }
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.BODY, Telephony.Sms.DATE),
            selection, args, "${Telephony.Sms.DATE} ASC",
        )?.use { c ->
            val body = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val date = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            while (c.moveToNext()) {
                val text = c.getString(body) ?: continue
                messages += text to Instant.ofEpochMilli(c.getLong(date))
            }
        }
        return Actions.importSmsBatch(context, messages)
    }
}
