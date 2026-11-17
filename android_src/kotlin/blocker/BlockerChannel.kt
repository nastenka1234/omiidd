package com.jojo.study_companion.blocker

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** پل Flutter ↔ بلاکر بومی (MethodChannel('omid/blocker')). منطق اصلی همه در Kotlin است. */
object BlockerChannel {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "omid/blocker").setMethodCallHandler { call, result ->
            handle(activity, call, result)
        }
    }

    private fun handle(a: Activity, call: MethodCall, result: MethodChannel.Result) {
        val c = a.applicationContext
        try {
            when (call.method) {
                "getState" -> result.success(state(c))
                "setEnabled" -> {
                    BlockerStore.setEnabled(c, call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                "saveSchedules" -> {
                    BlockerStore.saveSchedules(c, call.argument<String>("json") ?: "[]")
                    result.success(null)
                }
                "listApps" -> worker.execute {
                    try {
                        val s = listApps(c)
                        main.post { result.success(s) }
                    } catch (t: Throwable) {
                        main.post { result.error("failed", t.message, null) }
                    }
                }
                "getIcon" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    worker.execute {
                        val bytes = try {
                            icon(c, pkg)
                        } catch (t: Throwable) {
                            null
                        }
                        main.post { result.success(bytes) }
                    }
                }
                "openSettings" -> result.success(BlockerPerms.open(a, call.argument<String>("kind") ?: "details"))
                "setFlag" -> {
                    BlockerStore.setFlag(c, call.argument<String>("key") ?: "", call.argument<Boolean>("value") == true)
                    result.success(null)
                }
                "setConsent" -> {
                    BlockerStore.sp(c).edit().putBoolean("consent", call.argument<Boolean>("value") == true).apply()
                    result.success(null)
                }
                "syncTime" -> {
                    val ms = call.argument<Number>("ms")?.toLong() ?: 0L
                    if (ms > 0L) BlockerStore.syncServerTime(c, ms)
                    result.success(null)
                }
                "events" -> result.success(BlockerStore.pendingEvents(c).toString())
                "ackEvents" -> {
                    BlockerStore.ackEvents(c, call.argument<Number>("upTo")?.toLong() ?: 0L)
                    result.success(null)
                }
                "startQuick" -> {
                    BlockerStore.startQuick(
                        c,
                        call.argument<String>("mode") ?: "soft",
                        call.argument<Int>("minutes") ?: 25,
                        call.argument<String>("apps") ?: "[]",
                        call.argument<Int>("max_unlocks") ?: 3
                    )
                    result.success(null)
                }
                "stopQuick" -> {
                    BlockerStore.stopQuick(c)
                    result.success(null)
                }
                "ensureRunning" -> {
                    if (BlockerStore.isEnabled(c)) BlockerService.start(c)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: BlockerException) {
            result.error(e.code, e.code, null)
        } catch (t: Throwable) {
            result.error("failed", t.message, null)
        }
    }

    private fun state(c: Context): String {
        val now = BlockerStore.now(c)
        val o = JSONObject()
        o.put("enabled", BlockerStore.isEnabled(c))
        o.put("consent", BlockerStore.hasConsent(c))
        o.put("schedules", BlockerStore.schedulesJsonArray(c))
        val q = BlockerStore.loadQuick(c)
        if (q != null) {
            val qo = JSONObject()
            qo.put("mode", q.mode)
            qo.put("start", q.quickStartMs)
            qo.put("end", q.quickEndMs)
            qo.put("max_unlocks", q.maxUnlocks)
            val aa = JSONArray()
            for (app in q.apps) {
                val ao = JSONObject()
                ao.put("package", app.pkg)
                ao.put("label", app.label)
                aa.put(ao)
            }
            qo.put("apps", aa)
            o.put("quick", qo)
        } else {
            o.put("quick", JSONObject.NULL)
        }
        o.put("strict_until", BlockerStore.strictUntil(c))
        o.put("now", now)
        val act = JSONArray()
        for (a in BlockerStore.activeNow(c, now)) act.put(a.s.id)
        o.put("active", act)
        o.put("perms", BlockerPerms.toJson(c))
        o.put("summary", BlockerStore.summary(c, BlockerStore.todayStartMs(c)))
        o.put("running", BlockerService.instance != null)
        return o.toString()
    }

    private fun listApps(c: Context): String {
        val pm = c.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val free = AlwaysFree.get(c)
        val seen = HashSet<String>()
        val rows = ArrayList<Pair<String, String>>()
        for (r in pm.queryIntentActivities(intent, 0)) {
            val p = r.activityInfo.packageName
            if (free.contains(p) || !seen.add(p)) continue
            rows.add(Pair(p, r.loadLabel(pm).toString()))
        }
        rows.sortBy { it.second.lowercase() }
        val arr = JSONArray()
        for (r in rows) {
            val o = JSONObject()
            o.put("p", r.first)
            o.put("l", r.second)
            arr.put(o)
        }
        return arr.toString()
    }

    private fun icon(c: Context, pkg: String): ByteArray? {
        return try {
            val d = c.packageManager.getApplicationIcon(pkg)
            val size = 96
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val cv = Canvas(bmp)
            d.setBounds(0, 0, size, size)
            d.draw(cv)
            val bos = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
            bos.toByteArray()
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }
}
