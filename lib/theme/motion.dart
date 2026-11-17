import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'lottie_views.dart';
import 'tokens.dart';

/// همه‌ی حرکت‌ها نرم‌اند (فقط محو شدن و جابه‌جایی خیلی کم، بدون جهش و فنر).
/// اگر کاربر «کاهش حرکت» را در تنظیمات گوشی روشن کرده باشد، همه خاموش می‌شوند.
class Motion {
  static const page = Duration(milliseconds: 250);
  static const soft = Duration(milliseconds: 350);
  static const step = Duration(milliseconds: 40); // فاصله‌ی ظاهر شدن آیتم‌های فهرست
  static const curve = Curves.easeOutCubic;
  static bool reduce(BuildContext c) => MediaQuery.disableAnimationsOf(c);
}

/// انتقال بین صفحه‌ها: محو شدن ۲۵۰ms (fade-through)، بدون حرکت.
CustomTransitionPage<void> fadePage(GoRouterState s, Widget child) => CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: Motion.page,
      reverseTransitionDuration: Motion.page,
      transitionsBuilder: (context, anim, secondary, c) {
        if (Motion.reduce(context)) return c;
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
          child: FadeTransition(
            // صفحه‌ی زیرین هنگام آمدن صفحه‌ی بعد کمی کم‌رنگ می‌شود
            opacity: Tween<double>(begin: 1, end: .0).animate(
                CurvedAnimation(parent: secondary, curve: const Interval(0, .5, curve: Curves.easeIn))),
            child: c,
          ),
        );
      },
    );

/// ظاهر شدن تدریجی آیتم i‌ام: محو شدن + ۱۰ پیکسل بالا آمدن، با تأخیر i×۴۰ms.
/// فقط یک بار (اولین ساخت) اجرا می‌شود.
class Reveal extends StatefulWidget {
  final int index;
  final Widget child;
  const Reveal({super.key, required this.index, required this.child});
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.soft);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Motion.curve);
  Timer? _t;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduce(context)) {
      _c.value = 1;
      return;
    }
    // سقف تأخیر: فهرست‌های بلند آخرشان معطل نشوند
    final delay = Motion.step * (widget.index > 12 ? 12 : widget.index);
    _t = Timer(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, 10 * (1 - _a.value)), child: child),
        ),
      );
}

/// عدد را نرم از مقدار قبلی (یا صفر) تا مقدار تازه بالا می‌برد.
class CountUp extends StatelessWidget {
  final int value;
  final Widget Function(int v) builder;
  const CountUp(this.value, {super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    if (Motion.reduce(context)) return builder(value);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Motion.curve,
      builder: (_, v, __) => builder(v.round()),
    );
  }
}

/// کشیدن برای تازه‌سازی، با رنگ اپ؛ فهرست کوتاه هم قابل کشیدن است.
class SoftRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const SoftRefresh({super.key, required this.onRefresh, required this.child});
  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: T.acc,
        backgroundColor: T.surfaceHi,
        onRefresh: onRefresh,
        child: child,
      );
}

/// ListView ای که همیشه قابل کشیدن است (برای SoftRefresh).
const kPull = AlwaysScrollableScrollPhysics();

/// جشن پایان اولویت‌های اصلی روز: کاراکتر خوشحال ~۱٫۲ ثانیه، محو شدن نرم، خودش می‌رود.
Future<void> showDayCelebration(BuildContext context, {String text = 'آفرین! امروزت تموم شد'}) async {
  if (Motion.reduce(context)) return;
  HapticFeedback.lightImpact();
  final nav = Navigator.of(context, rootNavigator: true);
  unawaited(showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 210,
                height: 210,
                child: Lottie.asset(LottieAssets.happy,
                    repeat: false,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.celebration_rounded, size: 96, color: T.acc)),
              ),
              Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: T.tx)),
            ]),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, a, __, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeInOut), child: child),
  ));
  await Future<void>.delayed(const Duration(milliseconds: 1500)); // ۳۰۰ ورود + ~۱۲۰۰ نمایش
  if (nav.canPop()) nav.pop();
}
