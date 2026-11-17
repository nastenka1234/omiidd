package com.jojo.study_companion.blocker

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * سرویس پیش‌زمینه‌ی بلاکر. فقط وقتی یک بازه‌ی فعال هست اپ جلوی صفحه را می‌خواند؛
 * بیرون از بازه‌ها هیچ داده‌ای خوانده یا ثبت نمی‌شود. بدون Flutter هم کار می‌کند.
 */
class BlockerService : Service() {

    companion object {
        const val CH = "omid_blocker"
        const val CH_ALERT = "omid_blocker_alert"
        const val NID = 7101
        const val NID_ALERT = 7102
        const val ACTION_STOP = "com.jojo.study_companion.blocker.STOP"

        @Volatile
        var instance: BlockerService? = null

        fun start(c: Context) {
            try {
                ContextCompat.startForegroundService(c.applicationContext, Intent(c.applicationContext, BlockerService::class.java))
            } catch (e: Throwable) {
            }
        }

        fun stop(c: Context) {
            try {
                c.applicationContext.stopService(Intent(c.applicationContext, BlockerService::class.java))
            } catch (e: Throwable) {
            }
        }
    }

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private val main = Handler(Looper.getMainLooper())
    private var running = false

    private var lastFg: String? = null
    private var lastQuery = 0L
    private var lastLaunchAt = 0L
    private var lastLaunchPkg = ""
    private var lastNotifText = ""
    private var lastPermCheck = 0L
    private var cover: View? = null

    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            var delay = 3000L
            try {
                delay = step()
            } catch (t: Throwable) {
                delay = 3000L
            }
            if (running) handler?.postDelayed(this, delay)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null && intent.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!BlockerStore.isEnabled(this)) {
            // برای اینکه سیستم از «startForegroundService بدون startForeground» ایراد نگیرد، اول نوتیف را بالا می‌آوریم.
            try {
                promote(buildNotification("اپ‌بلاکر خاموشه", ""))
            } catch (e: Throwable) {
            }
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            promote(buildNotification("بلاکر امید فعاله", "بیرون از بازه‌ها هیچ‌چیز خونده نمی‌شه"))
        } catch (e: Throwable) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!running) {
            running = true
            val t = HandlerThread("omid-blocker")
            t.start()
            thread = t
            val h = Handler(t.looper)
            handler = h
            h.post(tick)
        }
        return START_STICKY
    }

    private fun promote(n: Notification) {
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NID, n)
        }
    }

    override fun onDestroy() {
        running = false
        handler?.removeCallbacksAndMessages(null)
        thread?.quitSafely()
        main.post { hideCoverNow() }
        instance = null
        super.onDestroy()
    }

    // ───────────── نوتیفیکیشن ─────────────
    private fun createChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val ch = NotificationChannel(CH, "اپ‌بلاکر", NotificationManager.IMPORTANCE_MIN)
        ch.description = "نوتیف ثابت و کم‌مزاحمت تا بلاکر کار کند"
        ch.setShowBadge(false)
        nm.createNotificationChannel(ch)
        val al = NotificationChannel(CH_ALERT, "هشدار بلاکر", NotificationManager.IMPORTANCE_DEFAULT)
        nm.createNotificationChannel(al)
    }

    private fun smallIcon(): Int {
        val id = resources.getIdentifier("ic_omid_blocker", "drawable", packageName)
        return if (id != 0) id else applicationInfo.icon
    }

    private fun openAppIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        return PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun buildNotification(title: String, text: String): Notification {
        val b = NotificationCompat.Builder(this, CH)
            .setContentTitle(title)
            .setSmallIcon(smallIcon())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(openAppIntent())
        if (text.isNotEmpty()) b.setContentText(text)
        return b.build()
    }

    private fun updateNotification(title: String, text: String) {
        val key = "$title|$text"
        if (key == lastNotifText) return
        lastNotifText = key
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NID, buildNotification(title, text))
        } catch (e: Throwable) {
        }
    }

    private fun alert(text: String) {
        try {
            val n = NotificationCompat.Builder(this, CH_ALERT)
                .setContentTitle("بلاکر امید")
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setSmallIcon(smallIcon())
                .setAutoCancel(true)
                .setContentIntent(openAppIntent())
                .build()
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NID_ALERT, n)
        } catch (e: Throwable) {
        }
    }

    // ───────────── حلقه‌ی اصلی ─────────────
    private fun step(): Long {
        val ctx = applicationContext
        if (!BlockerStore.isEnabled(ctx)) {
            stopSelf()
            return 5000L
        }
        val now = BlockerStore.now(ctx)
        val realNow = SystemClock.elapsedRealtime()
        if (realNow - lastPermCheck > 20_000L) {
            lastPermCheck = realNow
            checkPermissions(ctx)
        }
        val active = BlockerStore.activeNow(ctx, now)
        if (active.isEmpty()) {
            updateNotification("بلاکر امید فعاله", "بیرون از بازه‌ها هیچ‌چیز خونده نمی‌شه")
            lastFg = null
            lastQuery = 0L
            main.post { hideCoverNow() }
            return 4000L
        }
        var endMs = 0L
        var name = ""
        for (a in active) {
            if (a.w.endMs > endMs) {
                endMs = a.w.endMs
                name = a.s.name
            }
        }
        updateNotification("بازه‌ی «$name» فعاله", "تا " + Ui.hhmm(endMs))

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!pm.isInteractive || km.isKeyguardLocked) {
            lastFg = null
            lastQuery = 0L
            return 2500L
        }
        if (!BlockerPerms.usage(ctx)) return 5000L

        val fg = readForeground(ctx) ?: return 800L
        val d = BlockerStore.decide(ctx, fg, active)
        if (d == null) {
            main.post { hideCoverNow() }
            return 800L
        }
        launchBlock(ctx, d)
        return 800L
    }

    @Suppress("DEPRECATION")
    private fun readForeground(ctx: Context): String? {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val begin = if (lastQuery == 0L || lastQuery > end) end - 15_000L else lastQuery - 1_500L
        lastQuery = end
        val ev = usm.queryEvents(begin, end) ?: return lastFg
        val e = UsageEvents.Event()
        var latest: String? = null
        var latestT = 0L
        while (ev.hasNextEvent()) {
            ev.getNextEvent(e)
            if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND && e.timeStamp >= latestT) {
                latest = e.packageName
                latestT = e.timeStamp
            }
        }
        if (latest != null) lastFg = latest
        return lastFg
    }

    private fun launchBlock(ctx: Context, d: Decision) {
        val t = SystemClock.elapsedRealtime()
        if (d.pkg == lastLaunchPkg && t - lastLaunchAt < 1500L) return
        lastLaunchPkg = d.pkg
        lastLaunchAt = t
        BlockerStore.logDebounced(
            ctx, "blk_" + d.pkg, 8_000L,
            if (d.mode == "strict") "strict_denied" else "blocked", d.pkg, d.label, 0, d.scheduleId
        )
        main.post { showCover(d) }
        try {
            val i = Intent(ctx, BlockActivity::class.java)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NO_ANIMATION)
            i.putExtra("pkg", d.pkg)
            i.putExtra("label", d.label)
            ctx.startActivity(i)
        } catch (e: Throwable) {
        }
    }

    private fun checkPermissions(ctx: Context) {
        val ok = BlockerPerms.usage(ctx) && BlockerPerms.overlay(ctx)
        val sp = BlockerStore.sp(ctx)
        val was = sp.getBoolean("perm_ok", true)
        if (!ok && was) {
            sp.edit().putBoolean("perm_ok", false).apply()
            BlockerStore.addEvent(ctx, "permission_revoked", "", "", 0, "")
            alert("بلاکر خاموش شد چون یکی از مجوزها برداشته شده. برای روشن شدن دوباره، مجوزها رو از داخل اپ فعال کن.")
        } else if (ok && !was) {
            sp.edit().putBoolean("perm_ok", true).apply()
        }
    }

    // ───────────── پوشش فوری روی اپ ممنوع ─────────────
    fun hideCover() {
        main.post { hideCoverNow() }
    }

    private fun hideCoverNow() {
        val v = cover ?: return
        cover = null
        try {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (e: Throwable) {
        }
    }

    @Suppress("DEPRECATION")
    private fun showCover(d: Decision) {
        if (cover != null) return
        if (!BlockerPerms.overlay(this)) return
        try {
            val c = this
            val col = LinearLayout(c)
            col.orientation = LinearLayout.VERTICAL
            col.gravity = Gravity.CENTER
            col.setBackgroundColor(Ui.BG)
            col.setPadding(Ui.dp(c, 24), Ui.dp(c, 24), Ui.dp(c, 24), Ui.dp(c, 24))
            col.layoutDirection = View.LAYOUT_DIRECTION_RTL
            val lock = LockView(c, Ui.ACC)
            col.addView(lock, LinearLayout.LayoutParams(Ui.dp(c, 84), Ui.dp(c, 84)))
            val title = Ui.text(
                c,
                if (d.mode == "strict") d.label + " تا " + Ui.hhmm(d.windowEnd) + " قطعه" else d.label + " بلاک شده",
                22f, android.graphics.Color.WHITE, true
            )
            val tlp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            tlp.topMargin = Ui.dp(c, 20)
            col.addView(title, tlp)
            val back = Ui.primary(c, "برگرد به درس") {
                hideCoverNow()
                goOmid()
            }
            val blp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, Ui.dp(c, 52))
            blp.topMargin = Ui.dp(c, 28)
            col.addView(back, blp)

            val type = if (Build.VERSION.SDK_INT >= 26) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.OPAQUE
            )
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).addView(col, lp)
            cover = col
        } catch (e: Throwable) {
            cover = null
        }
    }

    private fun goOmid() {
        try {
            val i = packageManager.getLaunchIntentForPackage(packageName)
            if (i != null) {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
            }
        } catch (e: Throwable) {
        }
    }
}
