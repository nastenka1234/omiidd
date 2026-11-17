import 'dart:convert';

class Config {
  /// آدرس Worker. عمداً به‌صورت رمز‌شده (معکوسِ base64) نگه داشته می‌شود تا در فایل اپ
  /// به‌صورت متن ساده دیده نشود، و در هیچ جای رابط کاربری نمایش داده نمی‌شود.
  /// برای تغییر: base64 آدرس را بگیر، رشته را معکوس کن و اینجا بگذار.
  static const _u = '2VGZuMncltmcvdnLx1WNwcHMtMXdlpnLzIzNj1CdlNnb1NXLn5WasxWYm9yL6MHc0RHa';
  static String get defaultBaseUrl => utf8.decode(base64.decode(_u.split('').reversed.join()));
  /// با version در pubspec.yaml هماهنگ نگه‌دار.
  static const appVersion = '1.4.3';
  /// وقتی Worker فیلدهای اولویت را می‌پذیرد true کن (priority, status, carried, done_at ...).
  /// تا آن موقع به سرور فقط شکل قدیمی /progress فرستاده می‌شود تا درخواست‌ها رد نشوند.
  static const sendPriorityFields = false;
  /// وقتی Worker مسیر `POST /blocker/events` را دارد true کن (راهنما: docs/app-blocker.md).
  /// تا آن موقع شمارش‌های بلاکر فقط روی گوشی می‌ماند و به مشاور نمی‌رود.
  static const sendBlockerEvents = false;
  static const focusMinutes = 25;
  static const breakMinutes = 5;
}
