package com.timofei.srudzhbogdan

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableStateOf
import com.timofei.srudzhbogdan.sms.SmsNotifier
import com.timofei.srudzhbogdan.ui.AppRoot
import com.timofei.srudzhbogdan.ui.SrudzhTheme

class MainActivity : ComponentActivity() {
    /** Открыть разбор СМС: приложение запущено нажатием на уведомление. */
    private val openReview = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        handle(intent)
        setContent { SrudzhTheme { AppRoot(openReview) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        if (intent?.getBooleanExtra(SmsNotifier.EXTRA_REVIEW, false) == true) {
            openReview.value = true
            intent.removeExtra(SmsNotifier.EXTRA_REVIEW)
        }
    }
}
