import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Notifs {
  static final _p = FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  /// [askPermission] در پس‌زمینه (WorkManager) false است.
  static Future<void> init({bool askPermission = true}) async {
    if (_ready) return;
    _ready = true;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
    await _p.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    if (askPermission) {
      await _p
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  /// فقط یک یادآوری: گزارش شبانه، ۲۰:۱۵ (بعد از باز شدن گزارش در ساعت ۲۰:۰۰).
  /// یادآوری صبح حذف شد: متن ثابت بود و حتی وقتی برنامه‌ای ننوشته بودند می‌آمد.
  /// یک‌بارمصرف است (نه تکرار روزانه)؛ بعد از ثبت گزارش با [reportDone] به فردا می‌رود.
  static Future<void> scheduleDaily() async {
    await _p.cancel(1); // یادآوری صبحِ نسخه‌های قبلی
    await _reportAt(0);
  }

  /// گزارش امروز ثبت شد: یادآوری امشب نیاید، از فردا شب.
  static Future<void> reportDone() async {
    try {
      await init(askPermission: false);
      await _reportAt(1);
    } catch (_) {}
  }

  static Future<void> _reportAt(int plusDays) async {
    await _p.cancel(2);
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 15).add(Duration(days: plusDays));
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    await _p.zonedSchedule(
      2,
      'وقت گزارشکار شبانه‌ست',
      'تست‌ها و حالت امروز رو ثبت کن تا برنامه‌ی فردات تنظیم بشه.',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails('daily', 'یادآوری‌ها',
            importance: Importance.high, priority: Priority.high),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancel() => _p.cancelAll();

  /// یادآوری «همگام‌سازی لازم است»: بعد از هر همگام‌سازی موفق دوباره ۶ ساعت جلو می‌رود؛
  /// پس فقط وقتی نمایش داده می‌شود که ۶ ساعت بدون همگام‌سازی گذشته باشد.
  static Future<void> scheduleSyncReminder(Duration after) async {
    final when = tz.TZDateTime.now(tz.local).add(after);
    await _p.zonedSchedule(
      3,
      'پیشرفتت روی گوشی ذخیره‌ست',
      'وقتی اینترنت داشتی اپ رو باز کن تا برای مشاورت ارسال بشه.',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails('sync', 'همگام‌سازی',
            importance: Importance.defaultImportance, priority: Priority.defaultPriority),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelSyncReminder() => _p.cancel(3);
}
