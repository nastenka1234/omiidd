import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'api_client.dart';
import 'config.dart';
import 'jalali.dart';
import 'offline_queue.dart';

/// Calendar.DAY_OF_WEEK در اندروید: ۱=یکشنبه … ۷=شنبه. ترتیب هفته‌ی ایرانی: شنبه تا جمعه.
const kWeekOrder = [7, 1, 2, 3, 4, 5, 6];
const kDayName = {
  7: 'شنبه',
  1: 'یکشنبه',
  2: 'دوشنبه',
  3: 'سه‌شنبه',
  4: 'چهارشنبه',
  5: 'پنجشنبه',
  6: 'جمعه',
};
const kDayShort = {7: 'ش', 1: 'ی', 2: 'د', 3: 'س', 4: 'چ', 5: 'پ', 6: 'ج'};

String daysLabel(List<int> days) {
  final s = days.toSet();
  if (s.length == 7) return 'هر روز';
  if (s.length == 5 && s.containsAll([7, 1, 2, 3, 4])) return 'شنبه تا چهارشنبه';
  return [for (final d in kWeekOrder) if (s.contains(d)) kDayName[d]!].join('، ');
}

/// «۱۴:۳۰» با رقم فارسی از رشته‌ی HH:mm.
String faClock(String hhmm) => fa(hhmm);

class BlockerError implements Exception {
  final String code;
  BlockerError(this.code);

  String get fa {
    switch (code) {
      case 'strict_locked':
        return 'قطع کامل فعاله؛ تا پایان بازه نمی‌شه تغییرش داد';
      case 'perm_missing':
        return 'اول مجوزها رو فعال کن';
      case 'bad_schedule':
        return 'بازه کامل نیست؛ اسم، روز، ساعت و اپ‌ها رو چک کن';
      case 'disabled':
        return 'اول اپ‌بلاکر رو روشن کن';
      case 'unsupported':
        return 'اپ‌بلاکر فقط روی اندروید کار می‌کنه';
      default:
        return 'مشکلی پیش آمد، دوباره تلاش کن';
    }
  }

  @override
  String toString() => code;
}

class BlockApp {
  final String pkg, label;
  const BlockApp(this.pkg, this.label);
  Map<String, dynamic> toJson() => {'package': pkg, 'label': label};
  factory BlockApp.fromJson(Map j) => BlockApp('${j['package']}', '${j['label'] ?? j['package']}');
}

class BlockSchedule {
  final String id, name, start, end, mode; // start/end: HH:mm ، mode: soft | strict
  final List<int> days;
  final List<BlockApp> apps;
  final int maxUnlocks;
  final bool enabled;

  const BlockSchedule({
    required this.id,
    required this.name,
    required this.days,
    required this.start,
    required this.end,
    required this.apps,
    required this.mode,
    required this.maxUnlocks,
    required this.enabled,
  });

  bool get strict => mode == 'strict';
  static int toMin(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  int get startMin => toMin(start);
  int get endMin => toMin(end);
  bool get overnight => endMin <= startMin;

  BlockSchedule copyWith({
    String? name,
    List<int>? days,
    String? start,
    String? end,
    List<BlockApp>? apps,
    String? mode,
    int? maxUnlocks,
    bool? enabled,
  }) =>
      BlockSchedule(
        id: id,
        name: name ?? this.name,
        days: days ?? this.days,
        start: start ?? this.start,
        end: end ?? this.end,
        apps: apps ?? this.apps,
        mode: mode ?? this.mode,
        maxUnlocks: maxUnlocks ?? this.maxUnlocks,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'days': days,
        'start': start,
        'end': end,
        'apps': [for (final a in apps) a.toJson()],
        'mode': mode,
        'max_unlocks': maxUnlocks,
        'enabled': enabled,
      };

  factory BlockSchedule.fromJson(Map j) => BlockSchedule(
        id: '${j['id']}',
        name: '${j['name'] ?? 'بازه'}',
        days: [for (final d in (j['days'] as List? ?? [])) (d as num).toInt()],
        start: '${j['start']}',
        end: '${j['end']}',
        apps: [for (final a in (j['apps'] as List? ?? [])) BlockApp.fromJson(a as Map)],
        mode: '${j['mode']}' == 'strict' ? 'strict' : 'soft',
        maxUnlocks: (j['max_unlocks'] as num?)?.toInt() ?? 3,
        enabled: j['enabled'] != false,
      );
}

class QuickInfo {
  final String mode;
  final int endMs;
  final List<BlockApp> apps;
  const QuickInfo(this.mode, this.endMs, this.apps);
  bool get strict => mode == 'strict';
}

class BlockerPerms {
  final bool usage, overlay, notifications, battery, xiaomi, popupDone, autostartDone;
  final bool? popup;
  const BlockerPerms({
    this.usage = false,
    this.overlay = false,
    this.notifications = true,
    this.battery = false,
    this.xiaomi = false,
    this.popup,
    this.popupDone = false,
    this.autostartDone = false,
  });

  /// بدون این دو بلاکر اصلاً کار نمی‌کند.
  bool get core => usage && overlay;

  factory BlockerPerms.fromJson(Map j) => BlockerPerms(
        usage: j['usage'] == true,
        overlay: j['overlay'] == true,
        notifications: j['notifications'] != false,
        battery: j['battery'] == true,
        xiaomi: j['xiaomi'] == true,
        popup: j['popup'] as bool?,
        popupDone: j['popup_done'] == true,
        autostartDone: j['autostart_done'] == true,
      );
}

class AppCount {
  final String pkg, label;
  final int blocked, requested, unlocked, strict;
  const AppCount(this.pkg, this.label, this.blocked, this.requested, this.unlocked, this.strict);
  int get attempts => blocked + strict;
}

class BlockerState {
  final bool enabled, consent, running;
  final List<BlockSchedule> schedules;
  final QuickInfo? quick;
  final int strictUntil, nowMs;
  final List<String> active;
  final BlockerPerms perms;
  final List<AppCount> today;
  final int revokedToday, clockToday;
  final int _fetchedLocal;

  BlockerState({
    required this.enabled,
    required this.consent,
    required this.running,
    required this.schedules,
    required this.quick,
    required this.strictUntil,
    required this.nowMs,
    required this.active,
    required this.perms,
    required this.today,
    required this.revokedToday,
    required this.clockToday,
  }) : _fetchedLocal = DateTime.now().millisecondsSinceEpoch;

  /// ساعت قابل‌اعتماد گوشی (که با تغییر ساعت دستی فریب نمی‌خورد).
  int get trustedNow => nowMs + (DateTime.now().millisecondsSinceEpoch - _fetchedLocal);
  int get lockLeftMs => strictUntil <= 0 ? 0 : (strictUntil - trustedNow).clamp(0, 1 << 40).toInt();
  bool get locked => lockLeftMs > 0;

  factory BlockerState.fromJson(Map j) {
    final sum = (j['summary'] as Map?) ?? const {};
    return BlockerState(
      enabled: j['enabled'] == true,
      consent: j['consent'] == true,
      running: j['running'] == true,
      schedules: [for (final s in (j['schedules'] as List? ?? [])) BlockSchedule.fromJson(s as Map)],
      quick: j['quick'] is Map
          ? QuickInfo(
              '${(j['quick'] as Map)['mode']}',
              ((j['quick'] as Map)['end'] as num).toInt(),
              [for (final a in ((j['quick'] as Map)['apps'] as List? ?? [])) BlockApp.fromJson(a as Map)],
            )
          : null,
      strictUntil: (j['strict_until'] as num?)?.toInt() ?? 0,
      nowMs: (j['now'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      active: [for (final a in (j['active'] as List? ?? [])) '$a'],
      perms: BlockerPerms.fromJson((j['perms'] as Map?) ?? const {}),
      today: [
        for (final a in (sum['apps'] as List? ?? []))
          AppCount(
            '${(a as Map)['package']}',
            '${a['label']}',
            (a['blocked'] as num?)?.toInt() ?? 0,
            (a['requested'] as num?)?.toInt() ?? 0,
            (a['unlocked'] as num?)?.toInt() ?? 0,
            (a['strict'] as num?)?.toInt() ?? 0,
          )
      ],
      revokedToday: (sum['permission_revoked'] as num?)?.toInt() ?? 0,
      clockToday: (sum['clock_changed'] as num?)?.toInt() ?? 0,
    );
  }
}

/// اپ‌بلاکر (۱E). منطق اصلی در Kotlin است (MethodChannel('omid/blocker')) و وقتی Flutter بسته است هم کار می‌کند.
/// این کلاس فقط رابط است.
class Blocker {
  static const _ch = MethodChannel('omid/blocker');
  static final ValueNotifier<BlockerState?> state = ValueNotifier(null);
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static final Map<String, Future<Uint8List?>> _icons = {};
  static List<BlockApp>? _apps;
  static DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _uploadOff = false;

  static Future<dynamic> _call(String m, [Map<String, dynamic>? args]) async {
    if (!supported) throw BlockerError('unsupported');
    try {
      return await _ch.invokeMethod(m, args);
    } on PlatformException catch (e) {
      throw BlockerError(e.code);
    } on MissingPluginException {
      throw BlockerError('unsupported');
    }
  }

  static Future<BlockerState?> refresh() async {
    if (!supported) return null;
    try {
      final raw = await _call('getState') as String;
      final s = BlockerState.fromJson(jsonDecode(raw) as Map);
      state.value = s;
      return s;
    } catch (_) {
      return state.value;
    }
  }

  static Future<void> setEnabled(bool v) async {
    await _call('setEnabled', {'enabled': v});
    await refresh();
  }

  static Future<void> setConsent(bool v) => _call('setConsent', {'value': v});

  static Future<void> setFlag(String key, bool v) async {
    await _call('setFlag', {'key': key, 'value': v});
    await refresh();
  }

  static Future<void> saveSchedules(List<BlockSchedule> list) async {
    await _call('saveSchedules', {'json': jsonEncode([for (final s in list) s.toJson()])});
    await refresh();
  }

  static Future<List<BlockApp>> listApps({bool force = false}) async {
    if (_apps != null && !force) return _apps!;
    final raw = await _call('listApps') as String;
    _apps = [for (final a in jsonDecode(raw) as List) BlockApp('${(a as Map)['p']}', '${a['l']}')];
    return _apps!;
  }

  static Future<Uint8List?> icon(String pkg) => _icons.putIfAbsent(pkg, () async {
        try {
          final r = await _call('getIcon', {'package': pkg});
          return r is Uint8List ? r : null;
        } catch (_) {
          return null;
        }
      });

  static Future<bool> openSettings(String kind) async => (await _call('openSettings', {'kind': kind})) == true;

  static Future<void> startQuick({
    required String mode,
    required int minutes,
    required List<BlockApp> apps,
    int maxUnlocks = 3,
  }) async {
    await _call('startQuick', {
      'mode': mode,
      'minutes': minutes,
      'apps': jsonEncode([for (final a in apps) a.toJson()]),
      'max_unlocks': maxUnlocks,
    });
    await refresh();
  }

  static Future<void> stopQuick() async {
    await _call('stopQuick');
    await refresh();
  }

  // ───────────── چرخه‌ی عمر ─────────────
  static Future<void> onAppStart() async {
    if (!supported) return;
    await refresh();
    try {
      await _call('ensureRunning');
    } catch (_) {}
  }

  static Future<void> onResume() async {
    if (!supported) return;
    await onAppStart();
    unawaited(uploadEvents());
  }

  /// بعد از هر پاسخ سرور (هدر Date) ساعت قابل‌اعتماد بلاکر با ساعت سرور تنظیم می‌شود؛
  /// تغییر ساعت گوشی نمی‌تواند بازه‌ها را دور بزند.
  static void onServerDate(String httpDate) {
    if (!supported) return;
    final now = DateTime.now();
    if (now.difference(_lastTime).inSeconds < 60) return;
    try {
      final d = HttpDate.parse(httpDate);
      _lastTime = now;
      unawaited(_call('syncTime', {'ms': d.millisecondsSinceEpoch}).catchError((_) {}));
    } catch (_) {}
  }

  /// ارسال شمارش‌ها به مشاور. تا وقتی Worker مسیر `/blocker/events` را نداشته باشد خاموش است
  /// (Config.sendBlockerEvents). فقط نام اپ‌های بلاک‌شده و شمارش؛ هیچ داده‌ی دیگری نمی‌رود.
  static Future<void> uploadEvents() async {
    if (!supported || !Config.sendBlockerEvents || _uploadOff) return;
    if (Api.i.sid == null) return;
    try {
      final list = jsonDecode(await _call('events') as String) as List;
      if (list.isEmpty) return;
      var maxTs = 0;
      final out = <Map<String, dynamic>>[];
      for (final e in list) {
        final m = e as Map;
        final ts = (m['ts'] as num).toInt();
        if (ts > maxTs) maxTs = ts;
        out.add({
          'ts': DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true).toIso8601String(),
          'package': m['package'],
          'label': m['label'],
          'event': m['event'],
          'duration_sec': m['duration_sec'],
        });
      }
      await OfflineQueue.i.send('/blocker/events', {'day': todayIso(), 'events': out});
      await _call('ackEvents', {'upTo': maxTs});
    } on ApiError {
      _uploadOff = true; // خطای دائمی (مثلاً Worker هنوز مسیر را ندارد)؛ تا بازشدن بعدی اپ تلاش نکن
    } catch (_) {}
  }
}
