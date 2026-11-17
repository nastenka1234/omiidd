import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/blocker.dart';
import '../../core/jalali.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import 'app_picker.dart';
import 'widgets.dart';

/// «بازه‌ی جدید» / ویرایش بازه. حالت (با اجازه / قطع کامل) همین‌جا و هنگام ساخت انتخاب می‌شود.
class ScheduleEditorPage extends StatefulWidget {
  final BlockSchedule? initial;
  const ScheduleEditorPage({super.key, this.initial});
  @override
  State<ScheduleEditorPage> createState() => _ScheduleEditorPageState();
}

class _ScheduleEditorPageState extends State<ScheduleEditorPage> {
  late final TextEditingController name;
  late String start, end, mode;
  late Set<int> days;
  late List<BlockApp> apps;
  late int maxUnlocks;
  bool saving = false;

  bool get isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    name = TextEditingController(text: s?.name ?? '');
    start = s?.start ?? '16:00';
    end = s?.end ?? '18:00';
    mode = s?.mode ?? 'soft';
    days = {...(s?.days ?? kWeekOrder)};
    apps = [...(s?.apps ?? const <BlockApp>[])];
    maxUnlocks = s?.maxUnlocks ?? 3;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final cur = isStart ? start : end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(cur.split(':')[0]), minute: int.parse(cur.split(':')[1])),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isStart) {
        start = v;
      } else {
        end = v;
      }
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  bool _activeNow(BlockSchedule s) {
    // تخمین محلی (برای هشدار قبل از ذخیره)؛ منطق اصلی در Kotlin است.
    final now = tehranNow();
    final nowMin = now.hour * 60 + now.minute;
    final dow = (now.weekday % 7) + 1; // Dart: دوشنبه=۱…یکشنبه=۷ ← Calendar: یکشنبه=۱…شنبه=۷
    final yDow = dow == 1 ? 7 : dow - 1;
    if (!s.overnight) return s.days.contains(dow) && nowMin >= s.startMin && nowMin < s.endMin;
    return (s.days.contains(dow) && nowMin >= s.startMin) || (s.days.contains(yDow) && nowMin < s.endMin);
  }

  Future<void> _save() async {
    if (saving) return;
    if (start == end) return _snack('شروع و پایان نباید یکی باشه');
    if (days.isEmpty) return _snack('حداقل یک روز انتخاب کن');
    if (apps.isEmpty) return _snack('حداقل یک اپ انتخاب کن');
    final id = widget.initial?.id ?? 'b${DateTime.now().millisecondsSinceEpoch}';
    final st = Blocker.state.value;
    final n = name.text.trim().isEmpty ? 'بازه‌ی ${fa((st?.schedules.length ?? 0) + 1)}' : name.text.trim();
    final s = BlockSchedule(
      id: id,
      name: n,
      days: days.toList()..sort(),
      start: start,
      end: end,
      apps: apps,
      mode: mode,
      maxUnlocks: maxUnlocks,
      enabled: widget.initial?.enabled ?? true,
    );
    if (s.strict) {
      final now = _activeNow(s);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('قطع کامل؟'),
          content: Text(
              'تا پایان هر بازه هیچ راهی برای باز کردن این اپ‌ها نیست و تنظیمات بلاکر قفل می‌شه. تماس و پیام آزاده.'
              '${now ? '\n\nالان وسط این بازه‌ای؛ قفل همین الان شروع می‌شه.' : ''}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('برمی‌گردم')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('آره، قطع کامل')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => saving = true);
    try {
      final all = [...(st?.schedules ?? <BlockSchedule>[])];
      final i = all.indexWhere((e) => e.id == id);
      if (i >= 0) {
        all[i] = s;
      } else {
        all.add(s);
      }
      await Blocker.saveSchedules(all);
      if (mounted) context.pop();
    } on BlockerError catch (e) {
      if (mounted) {
        setState(() => saving = false);
        _snack(e.fa);
      }
    }
  }

  Widget _timeTile(String label, String v, bool isStart) {
    final overnight = !isStart && BlockSchedule.toMin(end) <= BlockSchedule.toMin(start);
    return Expanded(
      child: Glass(
        onTap: () => _pickTime(isStart),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: T.tx2, fontSize: 12)),
          const SizedBox(height: 4),
          Text(fa(v), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (overnight) const Text('فردا صبح', style: TextStyle(color: T.acc, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _dayChip(int d) {
    final on = days.contains(d);
    return Press(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() {
          if (on) {
            days.remove(d);
          } else {
            days.add(d);
          }
        }),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? T.acc : Colors.transparent,
            border: Border.all(color: on ? T.acc : T.line2),
          ),
          child: Text(kDayShort[d]!,
              style: TextStyle(fontWeight: FontWeight.w700, color: on ? T.onAcc : T.tx)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'بازه‌ی جدید' : 'ویرایش بازه')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        const SectionLabel('اسم بازه'),
        TextField(controller: name, maxLength: 24, decoration: const InputDecoration(hintText: 'مثلاً: تمرکز عصر', counterText: '')),
        const SectionLabel('ساعت'),
        Row(children: [_timeTile('از', start, true), const SizedBox(width: 12), _timeTile('تا', end, false)]),
        const SectionLabel('روزها'),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (final d in kWeekOrder) _dayChip(d)]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          ActionChip(label: const Text('هر روز'), onPressed: () => setState(() => days = {...kWeekOrder})),
          ActionChip(
              label: const Text('شنبه تا چهارشنبه'), onPressed: () => setState(() => days = {7, 1, 2, 3, 4})),
        ]),
        const SectionLabel('اپ‌ها'),
        Glass(
          onTap: () async {
            final r = await pickApps(context, apps);
            if (r != null) setState(() => apps = r);
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(apps.isEmpty ? 'انتخاب اپ‌ها' : '${fa(apps.length)} اپ انتخاب شده',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.chevron_left_rounded, color: T.tx2),
            ]),
            if (apps.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in apps.take(8))
                  Row(mainAxisSize: MainAxisSize.min, children: [AppIcon(a.pkg, size: 28), const SizedBox(width: 6), Text(a.label, style: const TextStyle(fontSize: 12))]),
                if (apps.length > 8) Pill('+${fa(apps.length - 8)}'),
              ]),
            ],
          ]),
        ),
        const SectionLabel('حالت'),
        const Padding(
          padding: EdgeInsets.only(bottom: 10, right: 4),
          child: Text('این رو همین الان انتخاب می‌کنی، نه وسط بازه.', style: TextStyle(color: T.acc, fontSize: 12.5)),
        ),
        ModeCard(
          selected: mode == 'soft',
          icon: Icons.lock_clock_rounded,
          title: 'بلاک با اجازه‌ی خودم',
          desc: 'اپ بلاک می‌شه. اگه واقعاً لازمش داشتی، ۳۰ ثانیه صبر می‌کنی، مدت رو انتخاب می‌کنی و تأیید می‌کنی؛ بعدش دوباره بلاک می‌شه.',
          onTap: () => setState(() => mode = 'soft'),
        ),
        const SizedBox(height: 10),
        ModeCard(
          selected: mode == 'strict',
          icon: Icons.block_rounded,
          title: 'قطع کامل',
          desc: 'تا پایان بازه هیچ دکمه‌ی بازکردنی نیست و تنظیمات بلاکر هم قفل می‌شه. تماس و پیام همیشه آزاده.',
          onTap: () => setState(() => mode = 'strict'),
        ),
        if (mode == 'soft') ...[
          const SectionLabel('حداکثر تعداد اجازه در هر بازه'),
          Glass(
            child: Row(children: [
              const Expanded(child: Text('اجازه‌ها')),
              IconButton(
                  onPressed: maxUnlocks > 1 ? () => setState(() => maxUnlocks--) : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded)),
              SizedBox(width: 28, child: Text(fa(maxUnlocks), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
              IconButton(
                  onPressed: maxUnlocks < 5 ? () => setState(() => maxUnlocks++) : null,
                  icon: const Icon(Icons.add_circle_outline_rounded)),
            ]),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: PrimaryButton('ذخیره', busy: saving, onPressed: _save)),
      ]),
    );
  }
}
