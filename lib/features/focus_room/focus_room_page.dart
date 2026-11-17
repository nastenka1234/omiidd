import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/api_client.dart';
import '../../core/blocker.dart';
import '../../core/focus_timer.dart';
import '../../core/jalali.dart';
import '../../core/live.dart';
import '../../core/models.dart';
import '../../core/prefs.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../blocker/quick_block_sheet.dart';
import '../music/player_service.dart';

class FocusRoomPage extends StatefulWidget {
  final String part, subject;
  const FocusRoomPage({super.key, required this.part, required this.subject});
  @override
  State<FocusRoomPage> createState() => _FocusRoomPageState();
}

class _FocusRoomPageState extends State<FocusRoomPage> with WidgetsBindingObserver {
  final day = todayIso();
  String mode = 'pomodoro'; // free | pomodoro
  bool running = false, onBreak = false, videoReady = false;
  late int phaseLeft = Prefs.focusMin * 60;
  int sessionSeconds = 0, _ticks = 0;
  bool _ready = false; // بازیابی تایمر ذخیره‌شده تمام شده
  Timer? timer;
  VideoPlayerController? vc;
  String? videoId;
  bool quickHere = false; // بلاک این جلسه را همین‌جا شروع کرده‌ایم

  /// وضعیت تایمر بر پایه‌ی ساعت واقعی؛ ماندگار، پس با بستن/کشتن اپ از بین نمی‌رود.
  FocusTimerState? st;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Live.part = widget.part.isEmpty ? null : widget.part;
    if (Blocker.supported) Blocker.refresh();
    _loadVideo();
    _restore();
  }

  /// اگر تایمری از قبل (برای همین پارت) روشن یا نیمه‌کاره بوده، از همان نقطه ادامه بده.
  Future<void> _restore() async {
    try {
      final s = await FocusTimerStore.settle(); // مطالعه‌ی مانده را ثبت و جلسه‌ی روزهای قبل را می‌بندد
      if (s != null && s.part != widget.part) {
        await FocusTimerStore.finish(s); // جلسه‌ی پارت دیگر: ببند تا گم نشود
      } else if (s != null) {
        st = s;
        mode = s.mode;
      }
    } catch (_) {}
    _ready = true;
    if (!mounted) return;
    setState(_apply);
    if (st?.running ?? false) {
      _startTicker();
      Live.state.value = (st!.onBreak) ? 'break' : 'focus';
      WakelockPlus.enable();
      Live.beat();
    }
  }

  /// فیلدهای نمایشی را از وضعیت ماندگار می‌سازد.
  void _apply() {
    final s = st;
    if (s == null) {
      sessionSeconds = 0;
      running = false;
      onBreak = false;
      phaseLeft = Prefs.focusMin * 60;
      return;
    }
    final sn = s.at(_now());
    sessionSeconds = sn.study;
    running = s.running && !sn.capped;
    onBreak = sn.onBreak;
    phaseLeft = s.mode == 'pomodoro' ? (sn.onBreak ? s.breakSec : s.focusSec) - sn.phaseUsed : 0;
  }

  void _startTicker() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _loadVideo() async {
    try {
      final r = await Api.i.getC('/focus/videos');
      final list = [for (final x in (r['videos'] as List? ?? [])) FocusVideo.fromJson(x)];
      if (list.isEmpty) return;
      final v = list[DateTime.now().day % list.length];
      final c = VideoPlayerController.networkUrl(
        Uri.parse(Api.i.abs(v.url)),
        httpHeaders: Api.i.authHeaders,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        vc = c;
        videoId = v.id;
        videoReady = true;
      });
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    final now = _now();
    st ??= FocusTimerStore.create(
        part: widget.part, subject: widget.subject, mode: mode, focusMin: Prefs.focusMin, breakMin: Prefs.breakMin);
    if (st!.running) {
      timer?.cancel();
      st = st!.commit(now, running: false);
      await FocusTimerStore.save(st!);
      await _flush();
      Live.state.value = 'idle';
      WakelockPlus.disable();
    } else {
      st = st!.commit(now, running: true);
      await FocusTimerStore.save(st!);
      _startTicker();
      Live.state.value = st!.onBreak ? 'break' : 'focus';
      WakelockPlus.enable();
    }
    if (mounted) setState(_apply);
    Live.beat();
  }

  void _tick() {
    final s = st;
    if (s == null || !s.running) return;
    final now = _now();
    final sn = s.at(now);
    if (sn.switches > 0 || sn.capped) {
      // فاز عوض شده (شاید وقتی اپ بسته بود) یا سقف زمان پیوسته خورده: ثابتش کن.
      st = s.commit(now);
      FocusTimerStore.save(st!);
      if (sn.switches > 0) {
        HapticFeedback.heavyImpact();
        Live.state.value = sn.onBreak ? 'break' : 'focus';
        Live.beat();
        if (sn.onBreak && Prefs.autoMusic && PlayerService.i.loaded) PlayerService.i.next();
      }
      if (sn.capped) {
        timer?.cancel();
        Live.state.value = 'idle';
        WakelockPlus.disable();
        Live.beat();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تایمر خیلی طولانی روشن مانده بود و متوقف شد')));
        }
      }
    }
    if (mounted) setState(_apply);
    if (++_ticks >= 60) {
      _ticks = 0;
      _flush();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _flush();
    } else if (state == AppLifecycleState.resumed && _ready) {
      _tick(); // بلافاصله از روی ساعت واقعی به‌روز شو
      if (mounted) setState(_apply);
    }
  }

  /// مطالعه‌ی ثبت‌نشده را در پیشرفت پارت می‌نویسد (فقط تفاوت، پس دوبار حساب نمی‌شود).
  Future<void> _flush() async {
    final s = st;
    if (s == null || s.part.isEmpty) return;
    final study = s.at(_now()).study;
    if (study <= s.flushed) return;
    try {
      await FocusTimerStore.flush(s, study);
      if (st != null) {
        st = st!.copy(flushed: study > st!.flushed ? study : st!.flushed);
        await FocusTimerStore.save(st!);
      }
    } catch (_) {}
  }

  Future<void> _finish() async {
    timer?.cancel();
    final s = st;
    if (s != null) {
      final tag = PlayerService.i.player.sequenceState?.currentSource?.tag;
      await FocusTimerStore.finish(s, musicId: tag is MediaItem ? tag.id : null, videoId: videoId);
      st = null;
    }
    Live.state.value = 'idle';
    Live.part = null;
    Live.beat();
    // بلاک «با اجازه» این جلسه با پایان جلسه برداشته می‌شود؛ قطع کامل تا پایان مدتش می‌ماند.
    if (quickHere) {
      try {
        await Blocker.stopQuick();
      } catch (_) {}
    }
    if (mounted) context.pop();
  }

  Future<void> _confirmExit() async {
    if (sessionSeconds == 0) {
      timer?.cancel();
      await FocusTimerStore.clear();
      if (mounted) context.pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('پایان جلسه؟'),
          content: Text('${fmtMin(sessionSeconds / 60)} مطالعه ثبت می‌شود.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ادامه')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('پایان')),
          ],
        ),
      ),
    );
    if (ok == true) await _finish();
  }

  Future<void> _startMusic() async {
    try {
      final r = await Api.i.getC('/music');
      final list = [for (final x in (r['tracks'] as List? ?? [])) Track.fromJson(x)];
      if (list.isNotEmpty) await PlayerService.i.play(list, 0);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    vc?.dispose();
    WakelockPlus.disable();
    Live.state.value = 'idle';
    super.dispose(); // وضعیت تایمر عمداً پاک نمی‌شود: با برگشت، از همان نقطه ادامه می‌دهد
  }

  @override
  Widget build(BuildContext context) {
    final shown = mode == 'pomodoro' ? phaseLeft : sessionSeconds;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          if (vc != null)
            AnimatedOpacity(
              opacity: videoReady ? .55 : 0,
              duration: const Duration(milliseconds: 900),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                    width: vc!.value.size.width, height: vc!.value.size.height, child: VideoPlayer(vc!)),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [T.bg.withOpacity(.55), T.bg.withOpacity(.75)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                Row(children: [
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: _confirmExit),
                  const Spacer(),
                  if (Blocker.supported)
                    ValueListenableBuilder<BlockerState?>(
                      valueListenable: Blocker.state,
                      builder: (_, b, __) {
                        final on = b?.quick != null;
                        return TextButton.icon(
                          onPressed: () async {
                            final r = await showQuickBlockSheet(context);
                            if (r == true) quickHere = true;
                          },
                          icon: Icon(on ? Icons.shield_rounded : Icons.shield_outlined, size: 18, color: on ? T.acc : T.tx2),
                          label: Text(on ? 'بلاک فعاله' : 'بلاک کن در این جلسه',
                              style: TextStyle(color: on ? T.acc : T.tx2, fontSize: 12.5)),
                        );
                      },
                    ),
                ]),
                const Spacer(),
                if (widget.part.isNotEmpty)
                  Text(widget.part, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                if (widget.subject.isNotEmpty)
                  Text(widget.subject, style: const TextStyle(color: T.tx2)),
                const SizedBox(height: 10),
                Text(clock(shown), style: const TextStyle(fontSize: 84, fontWeight: FontWeight.w900, color: T.hi)),
                Text(
                  onBreak ? 'استراحت' : (running ? 'تمرکز' : 'آماده'),
                  style: const TextStyle(color: T.tx2, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text('مطالعه‌ی این جلسه: ${fmtMin(sessionSeconds / 60)}',
                    style: const TextStyle(color: T.tx2, fontSize: 12)),
                const SizedBox(height: 22),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: T.acc,
                    selectedForegroundColor: T.bg,
                    foregroundColor: T.tx,
                    side: const BorderSide(color: T.line),
                    textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700),
                  ),
                  segments: const [
                    ButtonSegment(value: 'pomodoro', label: Text('پومودورو')),
                    ButtonSegment(value: 'free', label: Text('آزاد')),
                  ],
                  selected: {mode},
                  onSelectionChanged: running || sessionSeconds > 0
                      ? null
                      : (s) => setState(() {
                            mode = s.first;
                            phaseLeft = Prefs.focusMin * 60;
                            st = null;
                          }),
                ),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton.filled(
                    iconSize: 44,
                    style: IconButton.styleFrom(
                        backgroundColor: T.acc, foregroundColor: T.bg, padding: const EdgeInsets.all(20)),
                    icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: _toggle,
                  ),
                  const SizedBox(width: 18),
                  if (sessionSeconds > 0) GhostButton('پایان', icon: Icons.stop_rounded, onPressed: _confirmExit),
                ]),
                const Spacer(),
                Glass(
                  radius: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: PlayerService.i.loaded
                      ? Row(children: [
                          const Icon(Icons.graphic_eq_rounded, color: T.acc),
                          const SizedBox(width: 10),
                          Expanded(
                            child: StreamBuilder<SequenceState?>(
                              stream: PlayerService.i.player.sequenceStateStream,
                              builder: (_, s) {
                                final tag = s.data?.currentSource?.tag;
                                return Text(tag is MediaItem ? tag.title : '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis);
                              },
                            ),
                          ),
                          StreamBuilder<PlayerState>(
                            stream: PlayerService.i.player.playerStateStream,
                            builder: (_, s) => IconButton(
                              icon: Icon((s.data?.playing ?? false)
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded),
                              onPressed: PlayerService.i.toggle,
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: PlayerService.i.next),
                        ])
                      : Row(children: [
                          const Icon(Icons.music_note_rounded, color: T.tx2),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('موزیک پخش نمی‌شود', style: TextStyle(color: T.tx2))),
                          TextButton(onPressed: _startMusic, child: const Text('پخش')),
                        ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
