package com.jojo.study_companion.blocker

import android.app.Activity
import android.app.AppOpsManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

/** وضعیت مجوزها و باز کردن صفحه‌ی تنظیمات درست (به‌خصوص شیائومی/Poco با HyperOS). */
object BlockerPerms {

    fun usage(c: Context): Boolean {
        return try {
            val ops = c.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= 29) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), c.packageName)
            } else {
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), c.packageName)
            }
            if (mode == AppOpsManager.MODE_DEFAULT) {
                c.checkCallingOrSelfPermission("android.permission.PACKAGE_USAGE_STATS") == PackageManager.PERMISSION_GRANTED
            } else {
                mode == AppOpsManager.MODE_ALLOWED
            }
        } catch (e: Throwable) {
            false
        }
    }

    fun overlay(c: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 23) Settings.canDrawOverlays(c) else true

    fun notifications(c: Context): Boolean = try {
        NotificationManagerCompat.from(c).areNotificationsEnabled()
    } catch (e: Throwable) {
        true
    }

    fun battery(c: Context): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        return try {
            val pm = c.getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(c.packageName)
        } catch (e: Throwable) {
            false
        }
    }

    fun isXiaomi(): Boolean {
        val m = (Build.MANUFACTURER ?: "").lowercase()
        val b = (Build.BRAND ?: "").lowercase()
        return m.contains("xiaomi") || b.contains("xiaomi") || b.contains("redmi") || b.contains("poco")
    }

    /** «نمایش پنجره‌ی پاپ‌آپ در پس‌زمینه» در MIUI/HyperOS؛ اگر خوانده نشد null (نامشخص). */
    fun xiaomiPopup(c: Context): Boolean? {
        if (!isXiaomi()) return null
        return try {
            val ops = c.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val m = AppOpsManager::class.java.getMethod(
                "checkOpNoThrow",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                String::class.java
            )
            val r = m.invoke(ops, 10021, Process.myUid(), c.packageName) as Int
            r == AppOpsManager.MODE_ALLOWED
        } catch (e: Throwable) {
            null
        }
    }

    fun toJson(c: Context): JSONObject {
        val o = JSONObject()
        o.put("usage", usage(c))
        o.put("overlay", overlay(c))
        o.put("notifications", notifications(c))
        o.put("battery", battery(c))
        o.put("xiaomi", isXiaomi())
        val popup = xiaomiPopup(c)
        o.put("popup", if (popup == null) JSONObject.NULL else popup)
        o.put("popup_done", BlockerStore.flag(c, "popup_done"))
        o.put("autostart_done", BlockerStore.flag(c, "autostart_done"))
        o.put("sdk", Build.VERSION.SDK_INT)
        return o
    }

    private fun tryStart(a: Activity, intents: List<Intent>): Boolean {
        for (i in intents) {
            try {
                a.startActivity(i)
                return true
            } catch (e: ActivityNotFoundException) {
            } catch (e: SecurityException) {
            } catch (e: Throwable) {
            }
        }
        return false
    }

    fun open(a: Activity, kind: String): Boolean {
        val pkg = a.packageName
        val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
        val list = ArrayList<Intent>()
        when (kind) {
            "usage" -> {
                if (Build.VERSION.SDK_INT >= 29) {
                    list.add(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:$pkg")))
                }
                list.add(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
            }
            "overlay" -> {
                list.add(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$pkg")))
                list.add(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
            }
            "notifications" -> {
                if (Build.VERSION.SDK_INT >= 26) {
                    list.add(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg))
                }
            }
            "battery" -> {
                if (Build.VERSION.SDK_INT >= 23) {
                    list.add(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$pkg")))
                    list.add(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
            }
            "popup" -> {
                list.add(
                    Intent("miui.intent.action.APP_PERM_EDITOR")
                        .setClassName("com.miui.securitycenter", "com.miui.permcenter.permissions.PermissionsEditorActivity")
                        .putExtra("extra_pkgname", pkg)
                )
                list.add(
                    Intent("miui.intent.action.APP_PERM_EDITOR")
                        .setPackage("com.miui.securitycenter")
                        .putExtra("extra_pkgname", pkg)
                )
            }
            "autostart" -> {
                list.add(
                    Intent().setComponent(
                        ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
                    )
                )
            }
        }
        list.add(details)
        for (i in list) i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return tryStart(a, list)
    }
}
