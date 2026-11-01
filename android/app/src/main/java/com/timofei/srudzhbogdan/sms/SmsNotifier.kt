package com.timofei.srudzhbogdan.sms

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.timofei.srudzh.core.SmsReview
import com.timofei.srudzhbogdan.MainActivity
import com.timofei.srudzhbogdan.R
import com.timofei.srudzhbogdan.data.LedgerStore

/** Уведомление «пришла операция из СМС»: нажатие открывает разбор. */
object SmsNotifier {
    private const val CHANNEL = "sms"
    private const val ID = 1
    const val EXTRA_REVIEW = "openReview"

    fun createChannel(context: Context) {
        val channel = NotificationChannel(CHANNEL, context.getString(R.string.notify_channel_sms), NotificationManager.IMPORTANCE_DEFAULT)
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun show(context: Context) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val waiting = LedgerStore.value.transactions.count { it.smsReview != SmsReview.DONE }
        val open = Intent(context, MainActivity::class.java).putExtra(EXTRA_REVIEW, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pi = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notify)
            .setContentTitle(context.getString(R.string.notify_sms_title))
            .setContentText(context.getString(R.string.notify_sms_text, waiting))
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(ID, n)
    }

    fun clear(context: Context) = NotificationManagerCompat.from(context).cancel(ID)
}
