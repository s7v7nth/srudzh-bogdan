package com.timofei.srudzhbogdan

import android.app.Application
import com.timofei.srudzhbogdan.data.LedgerStore
import com.timofei.srudzhbogdan.data.RatesRepo
import com.timofei.srudzhbogdan.sms.SmsNotifier
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class SrudzhApp : Application() {
    override fun onCreate() {
        super.onCreate()
        LedgerStore.init(this)
        RatesRepo.init(this)
        SmsNotifier.createChannel(this)
    }

    companion object {
        /** Фоновые задачи, которые должны пережить закрытие экрана: курсы на дату операции и т. п. */
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    }
}
