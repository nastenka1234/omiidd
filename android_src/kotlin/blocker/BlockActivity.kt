package com.jojo.study_companion.blocker

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * صفحه‌ی بلاک روی اپ ممنوع.
 * - حالت با اجازه (soft): «برگرد به درس» یا «اجازه می‌خوام» ← ۳۰ ثانیه نفس عمیق ← انتخاب مدت ← تأیید نهایی.
 * - قطع کامل (strict): فقط «برگرد به درس»؛ هیچ راهی برای باز کردن نیست.
 */
class BlockActivity : Activity() {

    private enum class Step { HOME, WAIT, PICK, CONFIRM }

    private lateinit var root: FrameLayout
    private val ui = Handler(Looper.getMainLooper())
    private var pkg = ""
    private var label = ""
    private var dec: Decision? = null
    private var step = Step.HOME
    private var rendered: Step? = null
    private var waitStart = 0L
    private var pickMin = 5
    private var remainView: TextView? = null
    private var ring: RingView? = null

    private val ticker = object : Runnable {
        override fun run() {
            onTick()
            ui.postDelayed(this, 250L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Ui.BG
        window.navigationBarColor = Ui.BG
        root = FrameLayout(this)
        root.setBackgroundColor(Ui.BG)
        root.layoutDirection = View.LAYOUT_DIRECTION_RTL
        root.fitsSystemWindows = true
        setContentView(root)
        readIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readIntent(intent)
    }

    private fun readIntent(i: Intent?) {
        pkg = i?.getStringExtra("pkg") ?: ""
        label = i?.getStringExtra("label") ?: ""
        step = Step.HOME
        dec = BlockerStore.decideFor(this, pkg)
        render()
    }

    override fun onResume() {
        super.onResume()
        BlockerService.instance?.hideCover()
        if (rendered != step) render()
        ui.removeCallbacks(ticker)
        ui.post(ticker)
    }

    override fun onPause() {
        ui.removeCallbacks(ticker)
        super.onPause()
    }

    override fun onStop() {
        // رفتن از صفحه یعنی شمارش ۳۰ ثانیه‌ای باطل می‌شود.
        if (step != Step.HOME) step = Step.HOME
        super.onStop()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (step != Step.HOME) {
            step = Step.HOME
            render()
        } else {
            goHome()
        }
    }

    // ───────────── منطق ─────────────
    private fun onTick() {
        val d = BlockerStore.decideFor(this, pkg)
        if (d == null) {
            // بازه تموم شده یا اجازه فعال است: برو سراغ همان اپ
            openBlockedApp()
            finish()
            return
        }
        dec = d
        remainView?.text = remainText(d)
        if (step == Step.WAIT) {
            val el = SystemClock.elapsedRealtime() - waitStart
            val left = 30_000L - el
            if (left <= 0L) {
                step = Step.PICK
                render()
            } else {
                ring?.progress = el / 30_000f
                ring?.label = Ui.fa(((left + 999L) / 1000L).toInt())
            }
        }
    }

    private fun remainText(d: Decision): String {
        val left = d.windowEnd - BlockerStore.now(this)
        return Ui.remain(left) + " تا پایان بازه، ساعت " + Ui.hhmm(d.windowEnd)
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
        finish()
    }

    private fun goHome() {
        try {
            val h = Intent(Intent.ACTION_MAIN)
            h.addCategory(Intent.CATEGORY_HOME)
            h.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(h)
        } catch (e: Throwable) {
        }
        finish()
    }

    private fun openBlockedApp() {
        if (pkg.isEmpty()) return
        try {
            val i = packageManager.getLaunchIntentForPackage(pkg)
            if (i != null) {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
            }
        } catch (e: Throwable) {
        }
    }

    private fun startWait() {
        val d = dec ?: return
        BlockerStore.addEvent(this, "unlock_requested", d.pkg, d.label, 0, d.scheduleId)
        waitStart = SystemClock.elapsedRealtime()
        step = Step.WAIT
        render()
    }

    private fun doUnlock() {
        val d = dec ?: return
        if (BlockerStore.grant(this, d, pickMin)) {
            BlockerStore.addEvent(this, "unlocked", d.pkg, d.label, pickMin * 60, d.scheduleId)
            openBlockedApp()
            finish()
        } else {
            step = Step.HOME
            render()
        }
    }

    // ───────────── رابط ─────────────
    private fun dp(v: Int): Int = Ui.dp(this, v)

    private fun spacer(): View {
        val v = View(this)
        v.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
        return v
    }

    private fun add(col: LinearLayout, v: View, topDp: Int, w: Int, h: Int) {
        val lp = LinearLayout.LayoutParams(w, h)
        lp.topMargin = dp(topDp)
        lp.gravity = Gravity.CENTER_HORIZONTAL
        col.addView(v, lp)
    }

    private fun addText(col: LinearLayout, t: String, sp: Float, color: Int, bold: Boolean, topDp: Int): TextView {
        val v = Ui.text(this, t, sp, color, bold)
        add(col, v, topDp, LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        return v
    }

    private fun addButton(col: LinearLayout, v: View, topDp: Int) {
        add(col, v, topDp, LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
    }

    private fun render() {
        rendered = step
        root.removeAllViews()
        ring = null
        remainView = null
        val d = dec ?: BlockerStore.decideFor(this, pkg)
        if (d == null) {
            openBlockedApp()
            finish()
            return
        }
        dec = d
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.gravity = Gravity.CENTER_HORIZONTAL
        col.setPadding(dp(24), dp(24), dp(24), dp(24))
        when (step) {
            Step.HOME -> buildHome(col, d)
            Step.WAIT -> buildWait(col)
            Step.PICK -> buildPick(col)
            Step.CONFIRM -> buildConfirm(col, d)
        }
        col.alpha = 0f
        root.addView(col, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        col.animate().alpha(1f).setDuration(220L).start()
    }

    private fun buildHome(col: LinearLayout, d: Decision) {
        val strict = d.mode == "strict"
        col.addView(spacer())
        add(col, LockView(this, Ui.ACC), 0, dp(92), dp(92))
        add(col, Ui.chip(this, if (strict) "قطع کامل" else "با اجازه‌ی خودم", Ui.ACC, strict), 16, LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        addText(
            col,
            if (strict) d.label + " تا " + Ui.hhmm(d.windowEnd) + " قطعه" else d.label + " بلاک شده",
            26f, Color.WHITE, true, 16
        )
        addText(
            col,
            if (strict) "قطع کامل رو خودت برای این بازه انتخاب کردی" else "خودت این بازه رو برای تمرکز گذاشتی",
            15f, Ui.TX2, false, 6
        )
        remainView = addText(col, remainText(d), 14f, Ui.ACC, true, 14)
        col.addView(spacer())
        addButton(col, Ui.primary(this, "برگرد به درس") { goOmid() }, 0)
        if (strict) {
            addText(col, "تماس و پیام آزاده", 12f, Ui.TX2, false, 14)
        } else {
            val left = d.maxUnlocks - d.used
            if (left > 0) {
                addButton(col, Ui.ghost(this, "اجازه می‌خوام", true) { startWait() }, 12)
                addText(col, "۳۰ ثانیه صبر، " + Ui.fa(left) + " بار از " + Ui.fa(d.maxUnlocks) + " بار مونده", 12f, Ui.TX2, false, 10)
            } else {
                addButton(col, Ui.ghost(this, "اجازه‌هات تو این بازه تموم شده", false) {}, 12)
                addText(col, "تا پایان بازه همین‌جوری می‌مونه؛ از خودت ممنونم", 12f, Ui.TX2, false, 10)
            }
        }
    }

    private fun buildWait(col: LinearLayout) {
        col.addView(spacer())
        val r = RingView(this)
        r.label = "۳۰"
        ring = r
        add(col, r, 0, dp(200), dp(200))
        addText(col, "یک نفس عمیق بکش", 22f, Color.WHITE, true, 24)
        addText(col, "ببین واقعاً الان لازمش داری؟", 15f, Ui.TX2, false, 6)
        col.addView(spacer())
        addButton(col, Ui.primary(this, "برگرد به درس") { goOmid() }, 0)
    }

    private fun styleChip(v: TextView, selected: Boolean) {
        val bg = GradientDrawable()
        bg.setColor(if (selected) Ui.ACC else Color.TRANSPARENT)
        bg.setStroke(dp(1), if (selected) Ui.ACC else Ui.LINE)
        bg.cornerRadius = dp(999).toFloat()
        v.background = bg
        v.setTextColor(if (selected) Ui.ON_ACC else Color.WHITE)
    }

    private fun buildPick(col: LinearLayout) {
        col.addView(spacer())
        addText(col, "چند دقیقه؟", 26f, Color.WHITE, true, 0)
        addText(col, "بعد از این مدت دوباره بلاک می‌شه", 15f, Ui.TX2, false, 6)
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        row.gravity = Gravity.CENTER
        val chips = ArrayList<TextView>()
        val options = listOf(5, 10, 15)
        for (m in options) {
            val c = Ui.text(this, Ui.fa(m) + " دقیقه", 15f, Color.WHITE, true)
            c.setPadding(dp(18), dp(12), dp(18), dp(12))
            styleChip(c, m == pickMin)
            c.isClickable = true
            c.setOnClickListener {
                pickMin = m
                for (i in options.indices) styleChip(chips[i], options[i] == pickMin)
            }
            chips.add(c)
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.setMargins(dp(5), 0, dp(5), 0)
            row.addView(c, lp)
        }
        add(col, row, 28, LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        col.addView(spacer())
        addButton(col, Ui.primary(this, "باز کن") {
            step = Step.CONFIRM
            render()
        }, 0)
        addButton(col, Ui.ghost(this, "برگرد به درس", true) { goOmid() }, 12)
    }

    private fun buildConfirm(col: LinearLayout, d: Decision) {
        col.addView(spacer())
        add(col, LockView(this, Ui.ACC), 0, dp(84), dp(84))
        addText(col, "مطمئنی؟", 26f, Color.WHITE, true, 18)
        addText(
            col,
            "این اجازه‌ی شماره‌ی " + Ui.fa(d.used + 1) + " از " + Ui.fa(d.maxUnlocks) + " توئه.\n" +
                Ui.fa(pickMin) + " دقیقه بعد دوباره بلاک می‌شه.",
            15f, Ui.TX2, false, 8
        )
        col.addView(spacer())
        addButton(col, Ui.primary(this, "برگرد به درس") { goOmid() }, 0)
        addButton(col, Ui.ghost(this, "آره، باز کن", true) { doUnlock() }, 12)
    }
}
