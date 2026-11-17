import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/jalali.dart';
import '../../core/models.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../../theme/lottie_views.dart';
import '../../theme/motion.dart';

final statsProvider =
    FutureProvider.autoDispose.family<Stats, (int, String?)>((ref, key) async {
  final r = await Api.i.getC('/stats', q: sq(key.$2, {'range': key.$1}));
  return Stats.fromJson(r);
});

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) => Consumer(
        builder: (context, ref, _) => SoftRefresh(
          onRefresh: () async {
            ref.invalidate(statsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 500));
          },
          child: ListView(
            physics: kPull,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: const [PageTitle('آمار'), StatsView()],
          ),
        ),
      );
}

/// برای دانش‌آموز (studentId == null) و ادمین (با ?student=).
class StatsView extends ConsumerStatefulWidget {
  final String? studentId;
  const StatsView({super.key, this.studentId});
  @override
  ConsumerState<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends ConsumerState<StatsView> {
  int range = 7;
  static const _ranges = [(3, '۳ روز'), (7, 'هفته'), (30, 'ماه'), (90, '۳ ماه')];

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(statsProvider((range, widget.studentId)));
    return Column(children: [
      Wrap(spacing: 8, children: [
        for (final r in _ranges)
          ChoiceChip(
            label: Text(r.$2),
            selected: range == r.$1,
            onSelected: (_) => setState(() => range = r.$1),
            selectedColor: T.acc,
            backgroundColor: T.glass,
            side: const BorderSide(color: T.line),
            labelStyle: TextStyle(
                fontFamily: 'Vazirmatn',
                fontWeight: FontWeight.w700,
                color: range == r.$1 ? T.bg : T.tx),
            showCheckmark: false,
          ),
      ]),
      const SizedBox(height: 12),
      st.when(
        loading: () => const AppLoader(),
        error: (e, _) => ErrorState(e is ApiError ? e.fa : 'خطا در دریافت آمار',
            onRetry: () => ref.invalidate(statsProvider((range, widget.studentId)))),
        data: (s) => Column(children: [
          Row(children: [
            Expanded(child: CountUp(s.totalMin.round(), builder: (v) => _Total('جمع مطالعه', fmtMin(v)))),
            const SizedBox(width: 10),
            Expanded(child: CountUp(s.totalTests, builder: (v) => _Total('جمع تست', fa(v)))),
          ]),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'ساعت مطالعه',
            days: s.days,
            bars: (d) => [(d.studyMin / 60, T.acc)],
            unit: 'ساعت',
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'تعداد تست',
            days: s.days,
            bars: (d) => [(d.tests.toDouble(), T.acc), (d.correct.toDouble(), T.hi)],
            unit: 'تست',
          ),
          const SizedBox(height: 12),
          Glass(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('جمع هر پارت', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (s.parts.isEmpty) const Text('داده‌ای نیست', style: TextStyle(color: T.tx2)),
              for (final p in s.parts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(p.part)),
                    Expanded(
                        flex: 2,
                        child: Text('${fa(p.tests)} تست',
                            style: const TextStyle(color: T.tx2, fontSize: 13))),
                    Expanded(
                        flex: 2,
                        child: Text('${fa(p.percent.round())}٪ درست',
                            style: const TextStyle(color: T.hi, fontSize: 13))),
                    Expanded(
                        flex: 3,
                        child: Text(fmtMin(p.minutes),
                            style: const TextStyle(color: T.tx2, fontSize: 13))),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _Total extends StatelessWidget {
  final String label, value;
  const _Total(this.label, this.value);
  @override
  Widget build(BuildContext context) => Glass(
        radius: 24,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: T.tx2, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _ChartCard extends StatelessWidget {
  final String title, unit;
  final List<DayStat> days;
  final List<(double, Color)> Function(DayStat) bars;
  const _ChartCard({required this.title, required this.days, required this.bars, required this.unit});

  @override
  Widget build(BuildContext context) {
    final n = days.length;
    final rodW = n <= 7 ? 14.0 : (n <= 30 ? 5.0 : 2.0);
    final step = n <= 7 ? 1 : (n <= 30 ? 5 : 15);
    double maxY = 1;
    for (final d in days) {
      for (final b in bars(d)) {
        if (b.$1 > maxY) maxY = b.$1;
      }
    }
    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        SizedBox(
          height: 170,
          child: days.isEmpty
              ? const Center(child: Text('داده‌ای نیست', style: TextStyle(color: T.tx2)))
              : BarChart(BarChartData(
                  maxY: maxY * 1.15,
                  gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => const FlLine(color: T.line, strokeWidth: .5)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (v, m) => Text(
                            fa(v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)),
                            style: const TextStyle(color: T.tx2, fontSize: 10)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= n || (n - 1 - i) % step != 0) return const SizedBox.shrink();
                          final j = jalaliShort(days[i].day).split(' ').first;
                          return Text(j, style: const TextStyle(color: T.tx2, fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < n; i++)
                      BarChartGroupData(x: i, barsSpace: 2, barRods: [
                        for (final b in bars(days[i]))
                          BarChartRodData(
                              toY: b.$1,
                              color: b.$2,
                              width: rodW,
                              borderRadius: BorderRadius.circular(rodW > 6 ? 6 : 1)),
                      ]),
                  ],
                )),
        ),
      ]),
    );
  }
}
