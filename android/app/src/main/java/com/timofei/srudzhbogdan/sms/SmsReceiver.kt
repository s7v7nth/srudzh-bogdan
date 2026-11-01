package com.timofei.srudzhbogdan.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import com.timofei.srudzh.core.SmsOutcome
import com.timofei.srudzhbogdan.data.Actions
import com.timofei.srudzhbogdan.data.LedgerStore
import java.time.Instant
import kotlin.concurrent.thread

/**
 * Новое СМС: если это СМС банка, операция сразу попадает в учёт и ждёт разбора.
 * Остальные сообщения не сохраняются: разбор принимает только известные форматы банка.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)?.filterNotNull() ?: return
        if (parts.isEmpty()) return
        // Длинное СМС приходит частями: склеиваем их по отправителю.
        val messages = parts.groupBy { it.originatingAddress ?: "" }.values.map { group ->
            group.joinToString("") { it.messageBody ?: "" } to Instant.ofEpochMilli(group.first().timestampMillis)
        }
        val pending = goAsync()
        thread {
            try {
                val added = messages.count { (text, time) -> Actions.importSms(context, text, time) is SmsOutcome.Added }
                if (added > 0) {
                    LedgerStore.flush()
                    SmsNotifier.show(context)
                }
            } finally {
                pending.finish()
            }
        }
    }
}
