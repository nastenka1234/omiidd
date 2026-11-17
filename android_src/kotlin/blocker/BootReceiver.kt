package com.jojo.study_companion.blocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** بعد از روشن شدن گوشی یا آپدیت اپ، سرویس بلاکر دوباره بالا می‌آید (اگر دانش‌آموز روشنش کرده باشد). */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        try {
            if (BlockerStore.isEnabled(context)) BlockerService.start(context)
        } catch (e: Throwable) {
        }
    }
}
