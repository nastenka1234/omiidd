package com.jojo.study_companion.blocker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** رنگ‌ها و ابزارهای ظاهری مشترک بین صفحه‌ی بلاک و پوشش روی صفحه (هم‌رنگ با پالت اپ). */
object Ui {
    val BG: Int = Color.parseColor("#161316")
    val CARD: Int = Color.parseColor("#1E1A1B")
    val ACC: Int = Color.parseColor("#FF6D29")
    val BROWN: Int = Color.parseColor("#453027")
    val LINE: Int = Color.parseColor("#3A2E2F")
    val TX2: Int = Color.parseColor("#BABABA")
    val BAD: Int = Color.parseColor("#EB5757")
    val ON_ACC: Int = Color.parseColor("#161316")

    private var tfBold: Typeface? = null
    private var tfReg: Typeface? = null

    fun bold(c: Context): Typeface {
        tfBold?.let { return it }
        val t = try {
            Typeface.createFromAsset(c.applicationContext.assets, "flutter_assets/assets/fonts/Vazirmatn-Bold.ttf")
        } catch (e: Throwable) {
            Typeface.DEFAULT_BOLD
        }
        tfBold = t
        return t
    }

    fun reg(c: Context): Typeface {
        tfReg?.let { return it }
        val t = try {
            Typeface.createFromAsset(c.applicationContext.assets, "flutter_assets/assets/fonts/Vazirmatn-Regular.ttf")
        } catch (e: Throwable) {
            Typeface.DEFAULT
        }
        tfReg = t
        return t
    }

    fun dp(c: Context, v: Int): Int = (v * c.resources.displayMetrics.density + 0.5f).toInt()

    fun fa(s: String): String {
        val sb = StringBuilder()
        for (ch in s) {
            if (ch in '0'..'9') sb.append('۰' + (ch - '0')) else sb.append(ch)
        }
        return sb.toString()
    }

    fun fa(n: Int): String = fa(n.toString())

    fun hhmm(ms: Long): String {
        val f = SimpleDateFormat("HH:mm", Locale.US)
        f.timeZone = BlockerStore.TZ
        return fa(f.format(Date(ms)))
    }

    fun remain(ms: Long): String {
        val m = ((ms + 59_999L) / 60_000L).toInt()
        if (m <= 0) return "کمتر از یک دقیقه"
        if (m < 60) return fa(m) + " دقیقه"
        val h = m / 60
        val r = m % 60
        return if (r == 0) fa(h) + " ساعت" else fa(h) + " ساعت و " + fa(r) + " دقیقه"
    }

    fun text(c: Context, t: String, sp: Float, color: Int, isBold: Boolean): TextView {
        val v = TextView(c)
        v.text = t
        v.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, sp)
        v.setTextColor(color)
        v.typeface = if (isBold) bold(c) else reg(c)
        v.gravity = Gravity.CENTER
        v.setLineSpacing(0f, 1.3f)
        return v
    }

    private fun pressable(v: View) {
        v.setOnTouchListener { view, ev ->
            when (ev.action) {
                MotionEvent.ACTION_DOWN -> view.animate().scaleX(0.97f).scaleY(0.97f).setDuration(90).start()
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> view.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                else -> {}
            }
            false
        }
    }

    /** تنها دکمه‌ی پررنگ هر صفحه. */
    fun primary(c: Context, label: String, onClick: () -> Unit): TextView {
        val v = text(c, label, 15f, ON_ACC, true)
        val bg = GradientDrawable()
        bg.setColor(ACC)
        bg.cornerRadius = dp(c, 14).toFloat()
        v.background = bg
        v.minHeight = dp(c, 52)
        v.isClickable = true
        v.setOnClickListener { onClick() }
        pressable(v)
        return v
    }

    fun ghost(c: Context, label: String, enabled: Boolean, onClick: () -> Unit): TextView {
        val v = text(c, label, 14f, if (enabled) Color.WHITE else Color.parseColor("#77BABABA"), true)
        val bg = GradientDrawable()
        bg.setColor(Color.TRANSPARENT)
        bg.setStroke(dp(c, 1), LINE)
        bg.cornerRadius = dp(c, 14).toFloat()
        v.background = bg
        v.minHeight = dp(c, 46)
        if (enabled) {
            v.isClickable = true
            v.setOnClickListener { onClick() }
            pressable(v)
        }
        return v
    }

    fun chip(c: Context, label: String, color: Int, filled: Boolean): TextView {
        val v = text(c, label, 12f, if (filled) ON_ACC else color, true)
        val bg = GradientDrawable()
        bg.setColor(if (filled) color else Color.TRANSPARENT)
        bg.setStroke(dp(c, 1), if (filled) color else LINE)
        bg.cornerRadius = dp(c, 999).toFloat()
        v.background = bg
        v.setPadding(dp(c, 12), dp(c, 4), dp(c, 12), dp(c, 4))
        return v
    }
}

/** قفل با دایره‌ی قهوه‌ای پشتش. */
class LockView(c: Context, private val tint: Int) : View(c) {
    private val p = Paint(Paint.ANTI_ALIAS_FLAG)

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val s = minOf(w, h)
        val cx = w / 2f
        val cy = h / 2f
        p.style = Paint.Style.FILL
        p.color = Ui.BROWN
        canvas.drawCircle(cx, cy, s / 2f, p)

        val bw = s * 0.34f
        val bh = s * 0.26f
        val bl = cx - bw / 2f
        val bt = cy - bh / 2f + s * 0.08f
        p.color = tint
        canvas.drawRoundRect(RectF(bl, bt, bl + bw, bt + bh), s * 0.05f, s * 0.05f, p)

        p.style = Paint.Style.STROKE
        p.strokeWidth = s * 0.055f
        p.strokeCap = Paint.Cap.ROUND
        val sr = bw * 0.30f
        val top = bt - s * 0.07f
        val path = Path()
        path.moveTo(cx - sr, bt)
        path.lineTo(cx - sr, top)
        path.arcTo(RectF(cx - sr, top - sr, cx + sr, top + sr), 180f, 180f)
        path.lineTo(cx + sr, bt)
        canvas.drawPath(path, p)

        p.style = Paint.Style.FILL
        p.color = Ui.BG
        canvas.drawCircle(cx, bt + bh * 0.42f, s * 0.03f, p)
        canvas.drawRect(cx - s * 0.012f, bt + bh * 0.42f, cx + s * 0.012f, bt + bh * 0.72f, p)
    }
}

/** حلقه‌ی شمارش معکوس ۳۰ ثانیه‌ای. */
class RingView(c: Context) : View(c) {
    var progress = 0f
        set(v) {
            field = v
            invalidate()
        }
    var label = ""
        set(v) {
            field = v
            invalidate()
        }
    private val p = Paint(Paint.ANTI_ALIAS_FLAG)

    override fun onDraw(canvas: Canvas) {
        val s = minOf(width, height).toFloat()
        val stroke = s * 0.05f
        val r = RectF(stroke, stroke, s - stroke, s - stroke)
        p.style = Paint.Style.STROKE
        p.strokeWidth = stroke
        p.strokeCap = Paint.Cap.ROUND
        p.color = Ui.BROWN
        canvas.drawOval(r, p)
        p.color = Ui.ACC
        canvas.drawArc(r, -90f, 360f * progress, false, p)

        p.style = Paint.Style.FILL
        p.textAlign = Paint.Align.CENTER
        p.color = Color.WHITE
        p.typeface = Ui.bold(context)
        p.textSize = s * 0.34f
        val y = s / 2f - (p.descent() + p.ascent()) / 2f
        canvas.drawText(label, s / 2f, y, p)
    }
}
