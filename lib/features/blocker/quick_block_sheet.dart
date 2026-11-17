import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/blocker.dart';
import '../../core/jalali.dart';
import '../../core/prefs.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import 'app_picker.dart';
import 'blocker_page.dart';
import 'widgets.dart';

/// «بلاک کن در این جلسه» در اتاق تمرکز، با همان دو حالت. خروجی true یعنی بلاک این جلسه شروع شد.
Future<bool?> showQuickBlockSheet(BuildContext context) async {
  await Blocker.refresh();
  if (!context.mounted) return null;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _QuickSheet(),
  );
}

class _QuickSheet extends StatefulWidget {
  const _QuickSheet();
  @override
  State<_QuickSheet> createState() => _QuickSheetState();
}

class _QuickSheetState extends State<_QuickSheet> {
  String mode = 'soft';
  late int minutes = const [25, 45, 60, 90].contains(Prefs.focusMin) ? Prefs.focusMin : 25;
  List<BlockApp> apps = [];
  bool busy = false;
  String? err;

  @override
  void initState() {
    super.initState();
    final s = Blocker.state.value;
    final seen = <String>{};
    // پیش‌فرض: اپ‌هایی که قبلاً در بازه‌هات انتخاب کردی
    apps = [
      for (final sc in (s?.schedules ?? <BlockSchedule>[]))
        for (final a in sc.apps)
          if (seen.add(a.pkg)) a
    ];
  }

  Future<void> _start() async {
    if (apps.isEmpty) {
      setState(() => err = 'حداقل یک اپ انتخاب کن');
      return;
    }
    if (mode == 'strict') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('قطع کامل برای این جلسه؟'),
          content: Text('تا ${fmtMin(minutes)} دیگه هیچ راهی برای باز کردن این اپ‌ها نیست و تنظیمات بلاکر قفل می‌شه.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('برمی‌گردم')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('آره، قطع کامل')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await Blocker.startQuick(mode: mode, minutes: minutes, apps: apps);
      if (mounted) Navigator.pop(context, true);
    } on BlockerError catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          err = e.fa;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Blocker.state.value;
    final ready = s != null && s.enabled && s.perms.core;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('بلاک کن در این جلسه', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (!ready) ...[
            const Text('اپ‌بلاکر هنوز آماده نیست. اول از تنظیمات روشنش کن و مجوزها رو بده.', style: TextStyle(color: T.tx2)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton('رفتن به اپ‌بلاکر', onPressed: () {
                final router = GoRouter.of(context);
                Navigator.pop(context, false);
                router.push('/blocker');
              }),
            ),
          ] else if (s.quick != null) ...[
            Text('بلاک جلسه فعاله تا ${clockOfMs(s.quick!.endMs)}.', style: const TextStyle(color: T.tx2)),
            const SizedBox(height: 16),
            if (!s.quick!.strict)
              SizedBox(
                width: double.infinity,
                child: GhostButton('توقف بلاک', onPressed: () async {
                  try {
                    await Blocker.stopQuick();
                    if (context.mounted) Navigator.pop(context, false);
                  } on BlockerError catch (e) {
                    if (mounted) setState(() => err = e.fa);
                  }
                }),
              ),
          ] else ...[
            ModeCard(
              selected: mode == 'soft',
              icon: Icons.lock_clock_rounded,
              title: 'بلاک با اجازه‌ی خودم',
              desc: 'با ۳۰ ثانیه صبر و تأیید می‌تونی کوتاه بازش کنی.',
              onTap: () => setState(() => mode = 'soft'),
            ),
            const SizedBox(height: 10),
            ModeCard(
              selected: mode == 'strict',
              icon: Icons.block_rounded,
              title: 'قطع کامل',
              desc: 'تا پایان جلسه هیچ راهی نیست. تماس و پیام آزاده.',
              onTap: () => setState(() => mode = 'strict'),
            ),
            const SectionLabel('مدت'),
            Wrap(spacing: 8, children: [
              for (final m in const [25, 45, 60, 90, 120])
                ChoiceChip(
                  label: Text(fmtMin(m)),
                  selected: minutes == m,
                  onSelected: (_) => setState(() => minutes = m),
                ),
            ]),
            const SectionLabel('اپ‌ها'),
            Glass(
              onTap: () async {
                final r = await pickApps(context, apps);
                if (r != null) setState(() => apps = r);
              },
              child: Row(children: [
                Expanded(
                  child: Text(apps.isEmpty ? 'انتخاب اپ‌ها' : '${fa(apps.length)} اپ انتخاب شده',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const Icon(Icons.chevron_left_rounded, color: T.tx2),
              ]),
            ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: T.bad, fontSize: 12.5))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: PrimaryButton('شروع بلاک', busy: busy, onPressed: _start)),
          ],
        ]),
      ),
    );
  }
}
