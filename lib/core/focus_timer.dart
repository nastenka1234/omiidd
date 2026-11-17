import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'jalali.dart';
import 'offline_queue.dart';
import 'progress_store.dart';

/// عکس لحظه‌ای تایمر (خروجی خالص [FocusTimerState.at]).
class FocusSnap {
  final int study; // کل ثانیه‌های مطالعه‌ی جلسه
  final int phaseUsed; // ثانیه‌ی گذشته از فاز فعلی
  final bool onBreak;
  final int switches; // تعداد تعویض فاز از آخرین commit
  final bool capped; // سقف «بدون سر زدن به اپ» خورده
  const FocusSnap(this.study, this.phaseUsed, this.onBreak, this.switches, this.capped);
}

/// وضعیت تایمر بر پایه‌ی زمان واقعی (epoch)، نه شمارش ثانیه‌ی Timer.
/// هر چه دانش‌آموز اپ را ببندد، بکشد یا گوشی را قفل کند، زمان از روی ساعت حساب می‌شود
/// و موقع برگشت دقیقاً از همان نقطه ادامه می‌دهد.
class FocusTimerState {
  /// بیشترین زمان پیوسته‌ی «در حال اجرا» بدون سر زدن به اپ (فراموش‌کردن شبانه).
  static const maxAwaySec = 8 * 3600;

  final String sid, part, subject, day, mode, startedAt;
  final int focusSec, breakSec;
  final bool onBreak, running;
  final int segStartMs; // شروع قطعه‌ی در حال اجرا (epoch ms)
  final int phaseUsed; // ثانیه‌ی مصرف‌شده‌ی فاز، قبل از segStartMs
  final int studyBase; // ثانیه‌ی مطالعه، قبل از segStartMs
  final int flushed; // مقداری از studyBase/study که به ProgressStore رفته

  const FocusTimerState({
    required this.sid,
    required this.part,
    required this.subject,
    required this.day,
    required this.mode,
    required this.startedAt,
    required this.focusSec,
    required this.breakSec,
    required this.onBreak,
    required this.running,
    required this.segStartMs,
    required this.phaseUsed,
    required this.studyBase,
    required this.flushed,
  });

  FocusTimerState copy({
    String? mode,
    bool? onBreak,
    bool? running,
    int? segStartMs,
    int? phaseUsed,
    int? studyBase,
    int? flushed,
  }) =>
      FocusTimerState(
        sid: sid,
        part: part,
        subject: subject,
        day: day,
        mode: mode ?? this.mode,
        startedAt: startedAt,
        focusSec: focusSec,
        breakSec: breakSec,
        onBreak: onBreak ?? this.onBreak,
        running: running ?? this.running,
        segStartMs: segStartMs ?? this.segStartMs,
        phaseUsed: phaseUsed ?? this.phaseUsed,
        studyBase: studyBase ?? this.studyBase,
        flushed: flushed ?? this.flushed,
      );

  /// محاسبه‌ی خالص: وضعیت در لحظه‌ی [nowMs].
  FocusSnap at(int nowMs) {
    var onB = onBreak, used = phaseUsed, study = studyBase, sw = 0;
    var capped = false;
    if (running) {
      var d = (nowMs - segStartMs) ~/ 1000;
      if (d < 0) d = 0; // ساعت گوشی عقب رفت؛ جلو نمی‌افتیم
      if (d > maxAwaySec) {
        d = maxAwaySec;
        capped = true;
      }
      if (mode == 'pomodoro' && focusSec > 0 && breakSec > 0) {
        while (d > 0) {
          final len = onB ? breakSec : focusSec;
          final rem = len - used;
          if (d >= rem) {
            if (!onB) study += rem;
            d -= rem;
            onB = !onB;
            used = 0;
            sw++;
          } else {
            if (!onB) study += d;
            used += d;
            d = 0;
          }
        }
      } else {
        study += d;
        used += d;
      }
    }
    return FocusSnap(study, used, onB, sw, capped);
  }

  /// نتیجه‌ی [at] را در یک وضعیت تازه «ثابت» می‌کند (قطعه از nowMs دوباره شروع می‌شود).
  /// اگر سقف خورده باشد تایمر متوقف می‌شود.
  FocusTimerState commit(int nowMs, {bool? running}) {
    final s = at(nowMs);
    final run = (running ?? this.running) && !s.capped;
    return copy(
        onBreak: s.onBreak, running: run, segStartMs: nowMs, phaseUsed: s.phaseUsed, studyBase: s.study);
  }

  Map<String, dynamic> toJson() => {
        'sid': sid,
        'part': part,
        'subject': subject,
        'day': day,
        'mode': mode,
        'startedAt': startedAt,
        'focusSec': focusSec,
        'breakSec': breakSec,
        'onBreak': onBreak,
        'running': running,
        'segStartMs': segStartMs,
        'phaseUsed': phaseUsed,
        'studyBase': studyBase,
        'flushed': flushed,
      };

  static FocusTimerState? fromJson(Map j) {
    try {
      return FocusTimerState(
        sid: '${j['sid']}',
        part: '${j['part']}',
        subject: '${j['subject']}',
        day: '${j['day']}',
        mode: '${j['mode']}',
        startedAt: '${j['startedAt']}',
        focusSec: (j['focusSec'] as num).toInt(),
        breakSec: (j['breakSec'] as num).toInt(),
        onBreak: j['onBreak'] == true,
        running: j['running'] == true,
        segStartMs: (j['segStartMs'] as num).toInt(),
        phaseUsed: (j['phaseUsed'] as num).toInt(),
        studyBase: (j['studyBase'] as num).toInt(),
        flushed: (j['flushed'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// ذخیره‌ی ماندگار تایمر (SharedPreferences) + ثبت مطالعه در پیشرفت.
class FocusTimerStore {
  static const _key = 'focus_timer_v1';

  static Future<FocusTimerState?> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return null;
      final s = FocusTimerState.fromJson(jsonDecode(raw) as Map);
      // جلسه‌ی حساب دیگر، یا بدون حساب: دست نمی‌زنیم.
      if (s == null || s.sid != (Api.i.sid ?? '_')) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(FocusTimerState s) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }

  static FocusTimerState create({
    required String part,
    required String subject,
    required String mode,
    required int focusMin,
    required int breakMin,
  }) =>
      FocusTimerState(
        sid: Api.i.sid ?? '_',
        part: part,
        subject: subject,
        day: todayIso(),
        mode: mode,
        startedAt: DateTime.now().toUtc().toIso8601String(),
        focusSec: focusMin * 60,
        breakSec: breakMin * 60,
        onBreak: false,
        running: false,
        segStartMs: DateTime.now().millisecondsSinceEpoch,
        phaseUsed: 0,
        studyBase: 0,
        flushed: 0,
      );

  /// مطالعه‌ی هنوز ثبت‌نشده را به پیشرفت پارت اضافه می‌کند و وضعیت جدید را برمی‌گرداند.
  static Future<FocusTimerState> flush(FocusTimerState s, int study) async {
    final add = study - s.flushed;
    if (add <= 0 || s.part.isEmpty) return s;
    await ProgressStore.update(s.day, s.part, (p) => p.studySeconds += add);
    final n = s.copy(flushed: study);
    await save(n);
    return n;
  }

  /// پایان جلسه: مطالعه را ثبت می‌کند، به سرور می‌فرستد و تایمر را پاک می‌کند.
  static Future<void> finish(FocusTimerState s,
      {String? musicId, String? videoId, int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final snap = s.at(now);
    await flush(s, snap.study);
    if (snap.study >= 30) {
      try {
        await OfflineQueue.i.send('/focus/session', {
          'seconds': snap.study,
          'started_at': s.startedAt,
          'ended_at': DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String(),
          'mode': s.mode,
          'music_id': musicId,
          'video_id': videoId,
        });
      } catch (_) {}
    }
    await clear();
  }

  /// موقع باز شدن اپ / صفحه‌ی امروز: اگر تایمری از قبل مانده، مطالعه‌اش را ثبت کن.
  /// جلسه‌ی روزهای قبل بسته می‌شود؛ جلسه‌ی امروز می‌ماند تا دانش‌آموز ادامه بدهد.
  /// برمی‌گرداند: جلسه‌ی فعال امروز (اگر هست).
  static Future<FocusTimerState?> settle() async {
    final s = await load();
    if (s == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (s.day != todayIso()) {
      await finish(s, nowMs: s.running ? now : s.segStartMs);
      return null;
    }
    final c = s.commit(now);
    final f = await flush(c, c.studyBase);
    await save(f);
    return f;
  }
}
