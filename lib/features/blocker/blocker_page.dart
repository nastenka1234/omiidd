import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/blocker.dart';
import '../../core/jalali.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import 'widgets.dart';

String clockOfMs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(const Duration(hours: 3, minutes: 30));
  return fa('${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}');
}

/// تنظیمات اپ‌بلاکر (۱E): کلید اصلی، مجوزها، بازه‌ها، «همیشه آزاد» و خلاصه‌ی امروز.
class BlockerPage extends StatefulWidget {
  const BlockerPage({super.key});
  @override
  State<BlockerPage> createState() => _BlockerPageState();
}

class _BlockerPageState extends State<BlockerPage> with WidgetsBindingObserver {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Blocker.refresh();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => Blocker.refresh());
  }

  @override
  void dispose() {
    _t?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) Blocker.refresh();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggle(BlockerState s, bool v) async {
    if (v) {
      if (!s.consent) {
        final ok = await showBlockerConsent(context);
        if (ok != true) return;
        await Blocker.setConsent(true);
      }
      if (!s.perms.core) {
        if (!mounted) return;
        await context.push('/blocker/permissions');
        final n = await Blocker.refresh();
        if (n?.perms.core != true) return;
      }
    }
    try {
      await Blocker.setEnabled(v);
    } on BlockerError catch (e) {
      if (mounted) _snack(e.fa);
    }
  }

  Future<void> _setScheduleEnabled(BlockerState s, BlockSchedule sc, bool v) async {
    if (!v && s.active.contains(sc.id) && !sc.strict) {
      final ok = await _confirm('الان داخل این بازه‌ای', 'اگه خاموشش کنی بلاک همین الان برداشته می‌شه. خودت می‌خوای؟', 'خاموش کن');
      if (ok != true) return;
    }
    try {
      await Blocker.saveSchedules([for (final e in s.schedules) e.id == sc.id ? e.copyWith(enabled: v) : e]);
    } on BlockerError catch (e) {
      if (mounted) _snack(e.fa);
    }
  }

  Future<void> _delete(BlockerState s, BlockSchedule sc) async {
    final ok = await _confirm('«${sc.name}» حذف بشه؟', 'این بازه برای همیشه پاک می‌شه.', 'حذف');
    if (ok != true) return;
    try {
      await Blocker.saveSchedules([for (final e in s.schedules) if (e.id != sc.id) e]);
    } on BlockerError catch (e) {
      if (mounted) _snack(e.fa);
    }
  }

  Future<bool?> _confirm(String title, String body, String yes) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(yes, style: const TextStyle(color: T.bad))),
          ],
        ),
      );

  Future<void> _edit(BlockerState s, BlockSchedule? sc) async {
    if (s.locked) return _snack('قطع کامل فعاله؛ تا ${clockOfMs(s.strictUntil)} تنظیمات قفله');
    await context.push('/blocker/edit', extra: sc);
    Blocker.refresh();
  }

  Widget _lockBanner(BlockerState s) {
    final left = (s.lockLeftMs / 60000).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        borderColor: T.acc,
        highlight: true,
        child: Row(children: [
          const Icon(Icons.lock_rounded, color: T.acc),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('قطع کامل فعاله تا ${clockOfMs(s.strictUntil)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${fmtMin(left)} مونده؛ تنظیمات و بازه‌ها قفله.', style: const TextStyle(color: T.tx2, fontSize: 12.5)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _master(BlockerState s) {
    return Glass(
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: T.brown, borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.shield_rounded, color: s.enabled ? T.acc : T.tx2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('اپ‌بلاکر', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              s.enabled ? (s.running ? 'روشنه و کار می‌کنه' : 'روشنه') : 'اختیاریه و فقط به انتخاب خودت',
              style: const TextStyle(color: T.tx2, fontSize: 12.5),
            ),
          ]),
        ),
        Switch(value: s.enabled, onChanged: s.locked ? null : (v) => _toggle(s, v)),
      ]),
    );
  }

  Widget _permCard(BlockerState s) {
    final p = s.perms;
    final missing = <String>[
      if (!p.usage) 'دسترسی به آمار استفاده',
      if (!p.overlay) 'نمایش روی اپ‌های دیگر',
    ];
    final soft = <String>[
      if (!p.battery) 'بدون محدودیت باتری',
      if (!p.notifications) 'اعلان',
      if (p.xiaomi && !(p.popup == true || p.popupDone)) 'پاپ‌آپ در پس‌زمینه',
      if (p.xiaomi && !p.autostartDone) 'شروع خودکار',
    ];
    final ok = missing.isEmpty && soft.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Glass(
        onTap: () async {
          await context.push('/blocker/permissions');
          Blocker.refresh();
        },
        borderColor: missing.isNotEmpty && s.enabled ? T.bad.withOpacity(.7) : null,
        child: Row(children: [
          Icon(ok ? Icons.verified_user_rounded : Icons.warning_amber_rounded,
              color: ok ? T.ok : (missing.isNotEmpty ? T.bad : T.warn)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ok ? 'همه‌ی مجوزها آماده‌ست' : 'مجوزها', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (!ok) ...[
                const SizedBox(height: 2),
                Text(
                  missing.isNotEmpty
                      ? 'لازم: ${missing.join('، ')}'
                      : 'برای پایداری بهتر: ${soft.join('، ')}',
                  style: const TextStyle(color: T.tx2, fontSize: 12.5),
                ),
              ],
            ]),
          ),
          if (!ok) const Pill('فعال کن', color: T.acc),
          const Icon(Icons.chevron_left_rounded, color: T.tx2),
        ]),
      ),
    );
  }

  Widget _quickCard(BlockerState s) {
    final q = s.quick!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Glass(
        child: Row(children: [
          const Icon(Icons.timer_outlined, color: T.acc),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('بلاکِ جلسه‌ی تمرکز فعاله', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${q.strict ? 'قطع کامل' : 'با اجازه'} تا ${clockOfMs(q.endMs)}',
                  style: const TextStyle(color: T.tx2, fontSize: 12.5)),
            ]),
          ),
          if (!q.strict)
            GhostButton('توقف', onPressed: () async {
              try {
                await Blocker.stopQuick();
              } on BlockerError catch (e) {
                if (mounted) _snack(e.fa);
              }
            }),
        ]),
      ),
    );
  }

  Widget _today(BlockerState s) {
    final rows = [for (final a in s.today) if (a.attempts + a.requested + a.unlocked > 0) a];
    if (rows.isEmpty && s.revokedToday == 0 && s.clockToday == 0) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('امروز چه شد'),
      Glass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final a in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                AppIcon(a.pkg, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${fa(a.attempts)} بار تلاش برای باز کردن ${a.label}'
                    '${a.unlocked > 0 ? '، ${fa(a.unlocked)} بار اجازه گرفتی' : ''}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ]),
            ),
          if (s.revokedToday > 0)
            Text('مجوز بلاکر ${fa(s.revokedToday)} بار برداشته شد.', style: const TextStyle(color: T.warn, fontSize: 12.5)),
          if (s.clockToday > 0)
            Text('تغییر ساعت گوشی ${fa(s.clockToday)} بار دیده شد.', style: const TextStyle(color: T.warn, fontSize: 12.5)),
        ]),
      ),
    ]);
  }

  Widget _card(BlockerState s, BlockSchedule sc) {
    final live = s.active.contains(sc.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: s.enabled ? 1 : .55,
        child: Glass(
          onTap: () => _edit(s, sc),
          highlight: live,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(sc.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              if (live) const Padding(padding: EdgeInsets.only(left: 8), child: Pill('الان فعاله', color: T.ok)),
              Switch(value: sc.enabled, onChanged: s.locked ? null : (v) => _setScheduleEnabled(s, sc, v)),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: T.tx2),
                onSelected: (v) {
                  if (v == 'edit') _edit(s, sc);
                  if (v == 'del') {
                    if (s.locked) {
                      _snack('قطع کامل فعاله؛ تا ${clockOfMs(s.strictUntil)} تنظیمات قفله');
                    } else {
                      _delete(s, sc);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                  PopupMenuItem(value: 'del', child: Text('حذف')),
                ],
              ),
            ]),
            Text('${fa(sc.start)} تا ${fa(sc.end)}${sc.overnight ? ' (فردا صبح)' : ''}  —  ${daysLabel(sc.days)}',
                style: const TextStyle(color: T.tx2, fontSize: 12.5)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Pill(sc.strict ? 'قطع کامل' : 'با اجازه‌ی خودم', icon: sc.strict ? Icons.block_rounded : Icons.lock_clock_rounded, color: T.acc),
              if (!sc.strict) Pill('${fa(sc.maxUnlocks)} اجازه'),
              for (final a in sc.apps.take(3)) Pill(a.label),
              if (sc.apps.length > 3) Pill('+${fa(sc.apps.length - 3)}'),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _free() => Glass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Wrap(spacing: 6, runSpacing: 6, children: [
            Pill('تلفن', icon: Icons.call_outlined),
            Pill('پیام', icon: Icons.sms_outlined),
            Pill('ساعت و آلارم', icon: Icons.alarm_rounded),
            Pill('دوربین', icon: Icons.photo_camera_outlined),
            Pill('امید', icon: Icons.star_rounded),
          ]),
          const SizedBox(height: 10),
          const Text('این‌ها هیچ‌وقت بلاک نمی‌شن، حتی در قطع کامل؛ تماس اضطراری همیشه ممکنه.',
              style: TextStyle(color: T.tx2, fontSize: 12.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (!Blocker.supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('اپ‌بلاکر')),
        body: const Center(child: Text('اپ‌بلاکر فقط روی اندروید کار می‌کنه', style: TextStyle(color: T.tx2))),
      );
    }
    return ValueListenableBuilder<BlockerState?>(
      valueListenable: Blocker.state,
      builder: (context, s, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('اپ‌بلاکر')),
          body: s == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
                  if (s.locked) _lockBanner(s),
                  _master(s),
                  _permCard(s),
                  if (s.quick != null) _quickCard(s),
                  if (s.enabled) _today(s),
                  const SectionLabel('بازه‌ها'),
                  if (s.schedules.isEmpty)
                    Glass(
                      child: Column(children: [
                        const Icon(Icons.hourglass_empty_rounded, color: T.tx2, size: 32),
                        const SizedBox(height: 8),
                        const Text('هنوز بازه‌ای نساختی', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text('یک بازه بساز و اپ‌هایی که حواست رو پرت می‌کنن توش بلاک کن.',
                            textAlign: TextAlign.center, style: TextStyle(color: T.tx2, fontSize: 12.5)),
                      ]),
                    )
                  else
                    for (final sc in s.schedules) _card(s, sc),
                  const SectionLabel('همیشه آزاد'),
                  _free(),
                ]),
          bottomNavigationBar: s == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: PrimaryButton('بازه‌ی جدید', icon: Icons.add_rounded, onPressed: s.locked ? null : () => _edit(s, null)),
                  ),
                ),
        );
      },
    );
  }
}
