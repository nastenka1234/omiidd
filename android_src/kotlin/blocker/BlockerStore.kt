package com.jojo.study_companion.blocker

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.MediaStore
import android.provider.Settings
import android.provider.Telephony
import android.telecom.TelecomManager
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

class BlockerException(val code: String) : Exception(code)

data class BApp(val pkg: String, val label: String)

data class BSchedule(
    val id: String,
    val name: String,
    val days: Set<Int>, // Calendar.DAY_OF_WEEK: 1=یکشنبه … 7=شنبه
    val startMin: Int,
    val endMin: Int,
    val apps: List<BApp>,
    val mode: String, // soft | strict
    val maxUnlocks: Int,
    val enabled: Boolean,
    val quickStartMs: Long = 0L,
    val quickEndMs: Long = 0L
)

class TimeWin(val startMs: Long, val endMs: Long)

class Active(val s: BSchedule, val w: TimeWin)

class Decision(
    val pkg: String,
    val label: String,
    val mode: String,
    val scheduleId: String,
    val windowStart: Long,
    val windowEnd: Long,
    val maxUnlocks: Int,
    val used: Int
)

/**
 * همه‌ی وضعیت بلاکر روی گوشی (SharedPreferences) نگه داشته می‌شود تا وقتی Flutter بسته است هم کار کند.
 * زمان: ساعت قابل‌اعتماد = لنگر (ساعت دیوار + elapsedRealtime). تغییر ناگهانی ساعت گوشی (بیش از ۲ دقیقه)
 * نادیده گرفته و گزارش می‌شود؛ بعد از هر ارتباط با سرور، لنگر با ساعت سرور تنظیم می‌شود.
 */
object BlockerStore {
    val TZ: TimeZone = TimeZone.getTimeZone("GMT+03:30") // ایران؛ بدون ساعت تابستانی
    private const val PREF = "omid_blocker"
    private const val CLOCK_TOLERANCE_MS = 120_000L
    private val lock = Any()
    private val lastLogged = HashMap<String, Long>()

    fun sp(c: Context): SharedPreferences =
        c.applicationContext.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    // ───────────── پرچم‌ها ─────────────
    fun isEnabled(c: Context): Boolean = sp(c).getBoolean("enabled", false)
    fun hasConsent(c: Context): Boolean = sp(c).getBoolean("consent", false)
    fun flag(c: Context, key: String): Boolean = sp(c).getBoolean("flag_$key", false)
    fun setFlag(c: Context, key: String, v: Boolean) {
        sp(c).edit().putBoolean("flag_$key", v).apply()
    }

    // ───────────── ساعت قابل‌اعتماد ─────────────
    fun bootCount(c: Context): Int {
        if (Build.VERSION.SDK_INT >= 24) {
            try {
                return Settings.Global.getInt(c.contentResolver, Settings.Global.BOOT_COUNT, -1)
            } catch (e: Throwable) {
                return -1
            }
        }
        return -1
    }

    private fun anchor(c: Context, wallMs: Long) {
        sp(c).edit()
            .putLong("clk_wall", wallMs)
            .putLong("clk_elapsed", SystemClock.elapsedRealtime())
            .putInt("clk_boot", bootCount(c))
            .apply()
    }

    private fun computeNow(c: Context, log: Boolean): Long {
        val p = sp(c)
        val wall = System.currentTimeMillis()
        val el = SystemClock.elapsedRealtime()
        val aw = p.getLong("clk_wall", 0L)
        val ae = p.getLong("clk_elapsed", 0L)
        val ab = p.getInt("clk_boot", -2)
        if (aw == 0L || ab != bootCount(c) || el < ae) {
            anchor(c, wall) // اولین بار یا بعد از ریست: به ساعت گوشی اعتماد می‌کنیم تا سرور تأیید کند
            return wall
        }
        val trusted = aw + (el - ae)
        val diff = wall - trusted
        if (diff > CLOCK_TOLERANCE_MS || diff < -CLOCK_TOLERANCE_MS) {
            if (log) logDebounced(c, "clock", 600_000L, "clock_changed", "", "", 0, "")
            return trusted
        }
        if (log && (diff > 5_000L || diff < -5_000L)) anchor(c, wall) // رانش کوچک طبیعی (NTP)
        return if (log) wall else trusted
    }

    fun now(c: Context): Long = computeNow(c, true)

    /** بعد از هر پاسخ سرور صدا زده می‌شود. */
    fun syncServerTime(c: Context, serverMs: Long) {
        val before = computeNow(c, false)
        if (Math.abs(serverMs - before) > CLOCK_TOLERANCE_MS) {
            logDebounced(c, "clock", 600_000L, "clock_changed", "", "", 0, "")
        }
        anchor(c, serverMs)
    }

    fun todayStartMs(c: Context): Long {
        val cal = Calendar.getInstance(TZ)
        cal.timeInMillis = computeNow(c, false)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    // ───────────── بازه‌ها ─────────────
    private fun parseHm(s: String): Int {
        val p = s.split(":")
        val h = p[0].trim().toInt()
        val m = p[1].trim().toInt()
        if (h !in 0..23 || m !in 0..59) throw IllegalArgumentException("time")
        return h * 60 + m
    }

    private fun hm(min: Int): String =
        String.format(java.util.Locale.US, "%02d:%02d", min / 60, min % 60)

    fun parseSchedules(json: String, filterFree: Set<String>): List<BSchedule> {
        val arr = JSONArray(json)
        val out = ArrayList<BSchedule>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val id = o.getString("id")
            if (id.isEmpty() || id == "quick") throw IllegalArgumentException("id")
            val days = HashSet<Int>()
            val da = o.getJSONArray("days")
            for (k in 0 until da.length()) {
                val d = da.getInt(k)
                if (d in 1..7) days.add(d)
            }
            val st = parseHm(o.getString("start"))
            val en = parseHm(o.getString("end"))
            if (days.isEmpty() || st == en) throw IllegalArgumentException("time")
            val apps = ArrayList<BApp>()
            val aa = o.getJSONArray("apps")
            for (k in 0 until aa.length()) {
                val a = aa.getJSONObject(k)
                val p = a.getString("package")
                if (p.isNotEmpty() && !filterFree.contains(p)) apps.add(BApp(p, a.optString("label", p)))
            }
            if (apps.isEmpty()) throw IllegalArgumentException("apps")
            val mode = if (o.optString("mode") == "strict") "strict" else "soft"
            var mx = o.optInt("max_unlocks", 3)
            if (mx < 1) mx = 1
            if (mx > 5) mx = 5
            out.add(
                BSchedule(
                    id, o.optString("name", "بازه"), days, st, en, apps, mode, mx,
                    o.optBoolean("enabled", true)
                )
            )
        }
        return out
    }

    fun toJson(s: BSchedule): JSONObject {
        val o = JSONObject()
        o.put("id", s.id)
        o.put("name", s.name)
        val da = JSONArray()
        for (d in s.days.sorted()) da.put(d)
        o.put("days", da)
        o.put("start", hm(s.startMin))
        o.put("end", hm(s.endMin))
        val aa = JSONArray()
        for (a in s.apps) {
            val ao = JSONObject()
            ao.put("package", a.pkg)
            ao.put("label", a.label)
            aa.put(ao)
        }
        o.put("apps", aa)
        o.put("mode", s.mode)
        o.put("max_unlocks", s.maxUnlocks)
        o.put("enabled", s.enabled)
        return o
    }

    fun schedulesJsonArray(c: Context): JSONArray {
        val out = JSONArray()
        for (s in loadSchedules(c)) out.put(toJson(s))
        return out
    }

    fun loadSchedules(c: Context): List<BSchedule> {
        return try {
            parseSchedules(sp(c).getString("schedules", "[]") ?: "[]", emptySet())
        } catch (e: Throwable) {
            emptyList()
        }
    }

    /** جلسه‌ی سریع اتاق تمرکز (بازه‌ی موقت با شناسه‌ی quick). */
    fun loadQuick(c: Context): BSchedule? {
        val raw = sp(c).getString("quick", null) ?: return null
        return try {
            val o = JSONObject(raw)
            val end = o.getLong("end")
            if (end <= computeNow(c, false)) return null
            val apps = ArrayList<BApp>()
            val aa = o.getJSONArray("apps")
            for (k in 0 until aa.length()) {
                val a = aa.getJSONObject(k)
                apps.add(BApp(a.getString("package"), a.optString("label", a.getString("package"))))
            }
            BSchedule(
                "quick", "جلسه‌ی تمرکز", setOf(1, 2, 3, 4, 5, 6, 7), 0, 0, apps,
                if (o.optString("mode") == "strict") "strict" else "soft",
                o.optInt("max_unlocks", 3), true, o.getLong("start"), end
            )
        } catch (e: Throwable) {
            null
        }
    }

    fun allSchedules(c: Context): List<BSchedule> {
        val out = ArrayList<BSchedule>(loadSchedules(c))
        val q = loadQuick(c)
        if (q != null) out.add(q)
        return out
    }

    fun activeWindow(s: BSchedule, nowMs: Long): TimeWin? {
        if (!s.enabled) return null
        if (s.quickEndMs > 0L) {
            return if (nowMs >= s.quickStartMs && nowMs < s.quickEndMs) TimeWin(s.quickStartMs, s.quickEndMs) else null
        }
        val durMin = if (s.endMin > s.startMin) s.endMin - s.startMin else 24 * 60 - s.startMin + s.endMin
        val cal = Calendar.getInstance(TZ)
        for (back in 0..1) {
            cal.timeInMillis = nowMs
            cal.add(Calendar.DAY_OF_YEAR, -back)
            cal.set(Calendar.HOUR_OF_DAY, s.startMin / 60)
            cal.set(Calendar.MINUTE, s.startMin % 60)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            if (!s.days.contains(cal.get(Calendar.DAY_OF_WEEK))) continue
            val start = cal.timeInMillis
            val end = start + durMin * 60_000L
            if (nowMs >= start && nowMs < end) return TimeWin(start, end)
        }
        return null
    }

    fun activeNow(c: Context, nowMs: Long): List<Active> {
        val out = ArrayList<Active>()
        for (s in allSchedules(c)) {
            val w = activeWindow(s, nowMs) ?: continue
            out.add(Active(s, w))
        }
        return out
    }

    /** پایان قطع کاملِ فعال (ms)؛ ۰ یعنی قفلی نیست. */
    fun strictUntil(c: Context): Long {
        if (!isEnabled(c)) return 0L
        val now = computeNow(c, false)
        var end = 0L
        for (a in activeNow(c, now)) {
            if (a.s.mode == "strict" && a.w.endMs > end) end = a.w.endMs
        }
        return end
    }

    // ───────────── تصمیم‌گیری ─────────────
    fun decide(c: Context, pkg: String, active: List<Active>): Decision? {
        if (AlwaysFree.get(c).contains(pkg)) return null
        var best: Decision? = null
        for (a in active) {
            val app = a.s.apps.firstOrNull { it.pkg == pkg } ?: continue
            val d = Decision(
                pkg, app.label, a.s.mode, a.s.id, a.w.startMs, a.w.endMs, a.s.maxUnlocks,
                unlockCount(c, a.s.id, a.w.startMs)
            )
            val cur = best
            if (cur == null) {
                best = d
            } else {
                val dStrict = d.mode == "strict"
                val cStrict = cur.mode == "strict"
                if ((dStrict && !cStrict) || (dStrict == cStrict && d.windowEnd > cur.windowEnd)) best = d
            }
        }
        val b = best ?: return null
        if (b.mode == "soft" && hasGrant(c, pkg)) return null
        return b
    }

    fun decideFor(c: Context, pkg: String): Decision? {
        val now = computeNow(c, false)
        return decide(c, pkg, activeNow(c, now))
    }

    // ───────────── اجازه‌ها (حالت با اجازه) ─────────────
    private fun obj(c: Context, key: String): JSONObject {
        return try {
            JSONObject(sp(c).getString(key, "{}") ?: "{}")
        } catch (e: Throwable) {
            JSONObject()
        }
    }

    fun unlockCount(c: Context, scheduleId: String, windowStart: Long): Int =
        obj(c, "unlocks").optInt("$scheduleId@$windowStart", 0)

    fun hasGrant(c: Context, pkg: String): Boolean {
        val g = obj(c, "grants").optJSONObject(pkg) ?: return false
        if (g.optInt("boot", -1) != bootCount(c)) return false
        return g.optLong("until", 0L) > SystemClock.elapsedRealtime()
    }

    fun grantLeftMs(c: Context, pkg: String): Long {
        val g = obj(c, "grants").optJSONObject(pkg) ?: return 0L
        if (g.optInt("boot", -1) != bootCount(c)) return 0L
        return Math.max(0L, g.optLong("until", 0L) - SystemClock.elapsedRealtime())
    }

    /** اجازه‌ی کوتاه؛ هیچ‌وقت از پایان بازه بیشتر نمی‌شود. */
    fun grant(c: Context, d: Decision, minutes: Int): Boolean = synchronized(lock) { grantLocked(c, d, minutes) }

    private fun grantLocked(c: Context, d: Decision, minutes: Int): Boolean {
        if (d.mode != "soft") return false
        val now = computeNow(c, false)
        if (unlockCount(c, d.scheduleId, d.windowStart) >= d.maxUnlocks) return false
        val limit = Math.max(0L, d.windowEnd - now)
        val ms = Math.min(minutes * 60_000L, limit)
        if (ms <= 0L) return false
        val grants = obj(c, "grants")
        val g = JSONObject()
        g.put("until", SystemClock.elapsedRealtime() + ms)
        g.put("boot", bootCount(c))
        grants.put(d.pkg, g)
        val unlocks = obj(c, "unlocks")
        val key = d.scheduleId + "@" + d.windowStart
        unlocks.put(key, unlocks.optInt(key, 0) + 1)
        // قدیمی‌ها را پاک کن (بیش از ۳ روز)
        val keysIt = unlocks.keys()
        val dead = ArrayList<String>()
        while (keysIt.hasNext()) {
            val k = keysIt.next()
            val at = k.substringAfter("@", "0").toLongOrNull() ?: 0L
            if (now - at > 3 * 24 * 3_600_000L) dead.add(k)
        }
        for (k in dead) unlocks.remove(k)
        sp(c).edit().putString("grants", grants.toString()).putString("unlocks", unlocks.toString()).apply()
        return true
    }

    // ───────────── رویدادها (فقط شمارش و بسته‌ی بلاک‌شده) ─────────────
    fun addEvent(c: Context, event: String, pkg: String, label: String, durSec: Int, schedule: String) {
        synchronized(lock) {
            val arr = try {
                JSONArray(sp(c).getString("events", "[]") ?: "[]")
            } catch (e: Throwable) {
                JSONArray()
            }
            val o = JSONObject()
            o.put("ts", computeNow(c, false))
            o.put("package", pkg)
            o.put("label", label)
            o.put("event", event)
            o.put("duration_sec", durSec)
            o.put("schedule", schedule)
            arr.put(o)
            var out = arr
            if (arr.length() > 500) {
                out = JSONArray()
                for (i in arr.length() - 500 until arr.length()) out.put(arr.get(i))
            }
            sp(c).edit().putString("events", out.toString()).apply()
        }
    }

    fun logDebounced(
        c: Context, key: String, ms: Long, event: String, pkg: String, label: String, durSec: Int, schedule: String
    ) {
        val t = SystemClock.elapsedRealtime()
        synchronized(lock) {
            val last = lastLogged[key]
            if (last != null && t - last < ms) return
            lastLogged[key] = t
        }
        addEvent(c, event, pkg, label, durSec, schedule)
    }

    private fun eventsArray(c: Context): JSONArray = try {
        JSONArray(sp(c).getString("events", "[]") ?: "[]")
    } catch (e: Throwable) {
        JSONArray()
    }

    /** رویدادهای ارسال‌نشده (بعد از نشانگر ack). */
    fun pendingEvents(c: Context): JSONArray {
        val ack = sp(c).getLong("events_ack", 0L)
        val src = eventsArray(c)
        val out = JSONArray()
        for (i in 0 until src.length()) {
            val o = src.getJSONObject(i)
            if (o.optLong("ts", 0L) > ack) out.put(o)
        }
        return out
    }

    fun ackEvents(c: Context, upTo: Long) {
        sp(c).edit().putLong("events_ack", upTo).apply()
    }

    fun summary(c: Context, fromMs: Long): JSONObject {
        val per = LinkedHashMap<String, JSONObject>()
        var revoked = 0
        var clock = 0
        val src = eventsArray(c)
        for (i in 0 until src.length()) {
            val o = src.getJSONObject(i)
            if (o.optLong("ts", 0L) < fromMs) continue
            val ev = o.optString("event")
            val pkg = o.optString("package")
            if (ev == "permission_revoked") {
                revoked++
                continue
            }
            if (ev == "clock_changed") {
                clock++
                continue
            }
            if (pkg.isEmpty() || pkg == "omid_settings") continue
            val a = per.getOrPut(pkg) {
                val n = JSONObject()
                n.put("package", pkg)
                n.put("label", o.optString("label", pkg))
                n.put("blocked", 0)
                n.put("requested", 0)
                n.put("unlocked", 0)
                n.put("strict", 0)
                n
            }
            val k = when (ev) {
                "blocked" -> "blocked"
                "unlock_requested" -> "requested"
                "unlocked" -> "unlocked"
                "strict_denied" -> "strict"
                else -> ""
            }
            if (k.isNotEmpty()) a.put(k, a.getInt(k) + 1)
        }
        val arr = JSONArray()
        for (v in per.values) arr.put(v)
        val out = JSONObject()
        out.put("apps", arr)
        out.put("permission_revoked", revoked)
        out.put("clock_changed", clock)
        return out
    }

    // ───────────── عملیات از طرف رابط (با قفل قطع کامل) ─────────────
    fun saveSchedules(c: Context, json: String) {
        if (strictUntil(c) > 0L) {
            logDebounced(c, "strict_settings", 5_000L, "strict_denied", "omid_settings", "", 0, "")
            throw BlockerException("strict_locked")
        }
        val list = try {
            parseSchedules(json, AlwaysFree.get(c))
        } catch (e: Throwable) {
            throw BlockerException("bad_schedule")
        }
        val arr = JSONArray()
        for (s in list) arr.put(toJson(s))
        sp(c).edit().putString("schedules", arr.toString()).apply()
    }

    fun setEnabled(c: Context, v: Boolean) {
        if (!v && strictUntil(c) > 0L) {
            logDebounced(c, "strict_settings", 5_000L, "strict_denied", "omid_settings", "", 0, "")
            throw BlockerException("strict_locked")
        }
        if (v && !(BlockerPerms.usage(c) && BlockerPerms.overlay(c))) throw BlockerException("perm_missing")
        sp(c).edit().putBoolean("enabled", v).putBoolean("perm_ok", v).apply()
        if (v) BlockerService.start(c) else BlockerService.stop(c)
    }

    fun startQuick(c: Context, mode: String, minutes: Int, appsJson: String, maxUnlocks: Int) {
        if (!isEnabled(c)) throw BlockerException("disabled")
        if (strictUntil(c) > 0L) throw BlockerException("strict_locked")
        val apps = JSONArray()
        val src = try {
            JSONArray(appsJson)
        } catch (e: Throwable) {
            throw BlockerException("bad_schedule")
        }
        val free = AlwaysFree.get(c)
        for (i in 0 until src.length()) {
            val a = src.getJSONObject(i)
            val p = a.getString("package")
            if (p.isNotEmpty() && !free.contains(p)) {
                val ao = JSONObject()
                ao.put("package", p)
                ao.put("label", a.optString("label", p))
                apps.put(ao)
            }
        }
        if (apps.length() == 0) throw BlockerException("bad_schedule")
        val mins = if (minutes < 5) 5 else if (minutes > 180) 180 else minutes
        val now = computeNow(c, false)
        val o = JSONObject()
        o.put("mode", if (mode == "strict") "strict" else "soft")
        o.put("apps", apps)
        o.put("start", now)
        o.put("end", now + mins * 60_000L)
        o.put("max_unlocks", if (maxUnlocks < 1) 1 else if (maxUnlocks > 5) 5 else maxUnlocks)
        sp(c).edit().putString("quick", o.toString()).apply()
        BlockerService.start(c)
    }

    fun stopQuick(c: Context) {
        val q = loadQuick(c) ?: return
        if (q.mode == "strict") throw BlockerException("strict_locked")
        sp(c).edit().remove("quick").apply()
    }
}

/** اپ‌هایی که هیچ‌وقت بلاک نمی‌شوند: تلفن، پیام، ساعت/آلارم، دوربین، لانچر و خود امید. */
object AlwaysFree {
    private var cache: Set<String> = emptySet()
    private var at = 0L

    private val STATIC = listOf(
        "android", "com.android.systemui", "com.android.phone", "com.android.server.telecom",
        "com.android.incallui", "com.google.android.dialer", "com.android.dialer", "com.samsung.android.dialer",
        "com.samsung.android.incallui", "com.miui.securitycenter", "com.android.mms",
        "com.google.android.apps.messaging", "com.samsung.android.messaging", "com.android.deskclock",
        "com.google.android.deskclock", "com.sec.android.app.clockpackage", "com.android.camera",
        "com.android.camera2", "com.google.android.GoogleCamera", "com.sec.android.app.camera",
        "com.android.emergency", "com.google.android.apps.safetyhub", "com.android.settings.intelligence",
        "com.miui.home", "com.mi.android.globallauncher", "com.google.android.apps.nexuslauncher",
        "com.android.launcher", "com.android.launcher3", "com.sec.android.app.launcher"
    )

    fun get(c: Context): Set<String> {
        val t = SystemClock.elapsedRealtime()
        if (cache.isNotEmpty() && t - at < 60_000L) return cache
        val s = compute(c)
        cache = s
        at = t
        return s
    }

    private fun compute(c: Context): Set<String> {
        val ctx = c.applicationContext
        val pm = ctx.packageManager
        val out = HashSet<String>()
        out.add(ctx.packageName)
        out.addAll(STATIC)
        if (Build.VERSION.SDK_INT >= 23) {
            try {
                val tm = ctx.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                val dp = tm?.defaultDialerPackage
                if (dp != null) out.add(dp)
            } catch (e: Throwable) {
            }
        }
        try {
            val sp = Telephony.Sms.getDefaultSmsPackage(ctx)
            if (sp != null) out.add(sp)
        } catch (e: Throwable) {
        }
        try {
            val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            for (r in pm.queryIntentActivities(home, 0)) out.add(r.activityInfo.packageName)
        } catch (e: Throwable) {
        }
        val defaults = listOf(
            Intent(Intent.ACTION_DIAL, Uri.parse("tel:")),
            Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:")),
            Intent(MediaStore.ACTION_IMAGE_CAPTURE),
            Intent(AlarmClock.ACTION_SHOW_ALARMS)
        )
        for (i in defaults) {
            try {
                val r = pm.resolveActivity(i, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                val p = r?.activityInfo?.packageName
                if (p != null && p != "android") out.add(p) // «android» یعنی انتخاب‌گر، نه یک اپ
            } catch (e: Throwable) {
            }
        }
        return out
    }
}
