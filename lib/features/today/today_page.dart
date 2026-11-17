import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/focus_timer.dart';
import '../../core/jalali.dart';
import '../../core/models.dart';
import '../../core/priority.dart';
import '../../core/progress_store.dart';
import '../../theme/glass.dart';
import '../../theme/skeleton.dart';
import '../../theme/tokens.dart';
import 'day_bar.dart';
import 'done_sheet.dart';
import '../../theme/lottie_views.dart';
import '../../theme/motion.dart';

class TodayData {
  final PlanDay plan;
  final Map<String, PartProgress> progress;
  final DayState state;
  final int streak;
  final FocusTimerState? timer; // تایمر روشن/نیمه‌کاره‌ی امروز
  TodayData(this.plan, this.progress, this.state, this.streak, [this.timer]);
}

final todayProvider = FutureProvider.autoDispose<TodayData>((ref) async {
  final day = todayIso();
  final r = await Api.i.getC('/plan', q: {'day': day});
  final plan = PlanDay.fromJson(r);
  // تایمری که وقتی اپ بسته بود می‌رفت: مطالعه‌اش را همین‌جا ثبت کن، بعد پیشرفت را بخوان.
  final timer = await FocusTimerStore.settle();
  final prog = await ProgressStore.load(day);
  final state = Priority.compute(plan, prog);
  if (state.mandatoryAllDone) await ProgressStore.markDayDone(day);
  final streak = await ProgressStore.streak(day);
  return TodayData(plan, prog, state, streak, timer);
});

String _greet() {
  final h = tehranNow().hour;
  if (h < 5) return 'شب بخیر';
  if (h < 12) return 'صبح بخیر';
  if (h < 17) return 'ظهر بخیر';
  if (h < 20) return 'عصر بخیر';
  return 'شب بخیر';
}

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(authProvider)?.name ?? '';
    final data = ref.watch(todayProvider);
    final streak = data.valueOrNull?.streak ?? 0;
    // جشن: فقط وقتی «همین الان» آخرین اولویت اصلی تموم شد (نه موقع باز کردن اپ)
    ref.listen<AsyncValue<TodayData>>(todayProvider, (prev, next) {
      final was = prev?.valueOrNull?.state.mandatoryAllDone;
      final now = next.valueOrNull?.state.mandatoryAllDone;
      if (was == false && now == true) showDayCelebration(context);
    });
    return SoftRefresh(
      onRefresh: () async => ref.refresh(todayProvider.future),
      child: ListView(physics: kPull, padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? _greet() : '${_greet()}، $name',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(children: [
              Text(jalaliFull(todayIso()), style: const TextStyle(color: T.tx2, fontSize: 13)),
              if (streak > 0) ...[
                const SizedBox(width: 10),
                CountUp(streak,
                    builder: (v) => Pill('${fa(v)} روز پیاپی', icon: Icons.local_fire_department_rounded, color: T.acc)),
              ],
            ]),
          ]),
        ),
        data.when(
          loading: () => const Column(children: [Skeleton(height: 120), SizedBox(height: 12), SkeletonList()]),
          error: (e, _) => ErrorState(
            e is ApiError ? e.fa : 'مشکلی پیش آمد، دوباره تلاش کن',
            onRetry: () => ref.invalidate(todayProvider),
          ),
          data: (d) => _Body(d, () => ref.invalidate(todayProvider)),
        ),
      ]),
    );
  }
}

class _Body extends StatelessWidget {
  final TodayData d;
  final VoidCallback refresh;
  const _Body(this.d, this.refresh);

  @override
  Widget build(BuildContext context) {
    final plan = d.plan;
    final st = d.state;
    final reportReady = st.mandatoryAllDone || tehranNow().hour >= 20;
    return Column(children: [
      if (plan.source == 'ai')
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Glass(
            borderColor: T.acc,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('برنامه‌ی امروزت بر اساس دیروزت تنظیم شد',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              if (plan.note.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(plan.note, style: const TextStyle(color: T.tx2, fontSize: 13))),
            ]),
          ),
        )
      else if (plan.note.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Glass(child: Text(plan.note)),
        ),
      if (d.timer != null && d.timer!.sid == (Api.i.sid ?? '_'))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Glass(
            borderColor: T.acc,
            onTap: () async {
              await context.push(
                  '/focus?part=${Uri.encodeQueryComponent(d.timer!.part)}&subject=${Uri.encodeQueryComponent(d.timer!.subject)}');
              refresh();
            },
            child: Row(children: [
              Icon(d.timer!.running ? Icons.timer_rounded : Icons.pause_circle_outline_rounded, color: T.acc),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${d.timer!.running ? 'تایمر هنوز روشنه' : 'تایمر متوقف شده'}: ${d.timer!.part}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: T.tx2),
            ]),
          ),
        ),
      if (plan.items.isEmpty)
        const _Empty()
      else ...[
        DayProgressBar(st, onTap: () => DayProgressBar.showParts(context, st)),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 24, 4, 12),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('اولویت‌های امروز',
                style: TextStyle(color: T.tx2, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
        for (final p in st.parts)
          Reveal(
            index: p.index,
            child: _PriorityRow(
              day: plan.day,
              st: p,
              count: st.parts.length,
              last: p.index == st.parts.length - 1,
              reportReady: reportReady,
              refresh: refresh,
            ),
          ),
        const SizedBox(height: 12),
        if (reportReady)
          SizedBox(
            width: double.infinity,
            child: PrimaryButton('گزارشکار شبانه', icon: Icons.nights_stay_rounded, onPressed: () => context.push('/report')),
          )
        else
          Glass(
            child: Row(children: [
              const Icon(Icons.schedule_rounded, size: 18, color: T.tx2),
              const SizedBox(width: 10),
              Expanded(
                child: Text('گزارش شبانه از ساعت ${fa('20:00')} باز می‌شه',
                    style: const TextStyle(color: T.tx2, fontSize: 13)),
              ),
            ]),
          ),
      ],
    ]);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const StateView(
        asset: LottieAssets.happy,
        title: 'امروز برنامه‌ای نداری',
        sub: 'از مشاورت بخواه برنامه‌ات رو بنویسه.',
        size: 220,
      );
}

/// یک ردیف از فهرست عمودی اولویت‌ها (مثل stepper): دایره + کارت.
class _PriorityRow extends StatelessWidget {
  final String day;
  final PartState st;
  final int count;
  final bool last, reportReady;
  final VoidCallback refresh;
  const _PriorityRow({
    required this.day,
    required this.st,
    required this.count,
    required this.last,
    required this.reportReady,
    required this.refresh,
  });

  Future<void> _markDone(BuildContext context) async {
    final ok = await showDoneSheet(context, day, st, nextPriority: st.index + 1 < count ? st.priority + 1 : null);
    if (ok == true) refresh();
  }

  Future<void> _start(BuildContext context) async {
    await context.push(
        '/focus?part=${Uri.encodeQueryComponent(st.item.part)}&subject=${Uri.encodeQueryComponent(st.item.subject)}');
    refresh();
  }

  Widget _circle() {
    const size = 30.0;
    if (st.isDone) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: T.acc, width: 2)),
        child: const Icon(Icons.check_rounded, size: 17, color: T.acc),
      );
    }
    if (st.isLocked) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: T.line),
        child: const Icon(Icons.lock_rounded, size: 14, color: T.tx2),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: st.optional ? Colors.transparent : T.acc,
        border: Border.all(color: T.acc, width: 2),
      ),
      child: Text(fa(st.priority),
          style: TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: st.optional ? T.acc : T.onAcc)),
    );
  }

  Widget _card(BuildContext context) {
    final it = st.item;
    if (st.isDone) {
      final pp = st.pp;
      return Glass(
        onTap: () => _markDone(context),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.part,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: T.tx2, decoration: TextDecoration.lineThrough)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill('${fa(pp?.tests ?? 0)} تست'),
                if (pp?.correctKnown == true) Pill('${fa(pp!.correct)} درست', color: T.ok),
              ]),
            ]),
          ),
          const Icon(Icons.edit_outlined, size: 16, color: T.tx2),
        ]),
      );
    }
    if (st.isLocked) {
      return Opacity(
        opacity: .6,
        child: Glass(
          onTap: () => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('اول اولویت ${fa(st.blockedBy)} رو تموم کن'))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.part, style: const TextStyle(fontWeight: FontWeight.w700, color: T.tx2)),
            const SizedBox(height: 4),
            Text('بعد از اولویت ${fa(st.blockedBy)} باز می‌شه',
                style: const TextStyle(color: T.tx2, fontSize: 12)),
          ]),
        ),
      );
    }
    final frac = (st.studiedMin / st.targetMin).clamp(0.0, 1.0).toDouble();
    final startPrimary = !(reportReady && st.optional);
    final startBtn = startPrimary
        ? PrimaryButton('شروع تمرکز', icon: Icons.play_arrow_rounded, onPressed: () => _start(context))
        : GhostButton('شروع تمرکز', icon: Icons.play_arrow_rounded, onPressed: () => _start(context));
    return Glass(
      highlight: true,
      borderColor: T.line2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (it.subject.isNotEmpty) Pill(it.subject, color: T.acc),
          if (st.optional) const Pill('اختیاری، ولی مفید'),
          if (st.carried) const Pill('فردا ادامه می‌دی', color: T.warn),
        ]),
        if (it.subject.isNotEmpty || st.optional || st.carried) const SizedBox(height: 10),
        Text(it.part, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill(fmtMin(it.minutes), icon: Icons.schedule_rounded),
          if (it.testsTarget > 0) Pill('هدف ${fa(it.testsTarget)} تست', icon: Icons.edit_note_rounded),
        ]),
        if (it.note.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(it.note, style: const TextStyle(color: T.tx2, fontSize: 13))),
        const SizedBox(height: 14),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: frac),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: T.brown, color: T.acc),
          ),
        ),
        const SizedBox(height: 6),
        Text('مطالعه: ${fmtMin(st.studiedMin)}', style: const TextStyle(color: T.tx2, fontSize: 12)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: startBtn),
          const SizedBox(width: 10),
          Expanded(child: GhostButton('تموم شد', icon: Icons.check_rounded, onPressed: () => _markDone(context))),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 30,
          child: Column(children: [
            _circle(),
            if (!last)
              Expanded(
                child: Center(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: st.isDone ? T.acc : T.line2,
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 12),
            child: _card(context),
          ),
        ),
      ]),
    );
  }
}
