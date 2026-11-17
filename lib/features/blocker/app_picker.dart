import 'package:flutter/material.dart';
import '../../core/blocker.dart';
import '../../core/jalali.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import 'widgets.dart';

/// اپ‌های پرتکرارِ حواس‌پرت‌کن؛ اگر نصب باشند بالای فهرست می‌آیند.
const _popular = {
  'com.instagram.android',
  'org.telegram.messenger',
  'org.telegram.messenger.web',
  'com.google.android.youtube',
  'com.zhiliaoapp.musically',
  'com.ss.android.ugc.trill',
  'com.whatsapp',
  'ir.eitaa.messenger',
  'ir.resaneh1.iptv',
  'app.rubika.messenger',
  'ir.nasim',
  'com.snapchat.android',
  'com.twitter.android',
  'com.facebook.katana',
  'com.facebook.lite',
  'com.reddit.frontpage',
  'com.pinterest',
  'com.discord',
  'com.netflix.mediaclient',
  'ir.aparat',
  'com.aparat',
};

/// انتخاب اپ‌ها (شیت تمام‌صفحه). خروجی: فهرست انتخاب‌شده یا null اگر لغو شد.
Future<List<BlockApp>?> pickApps(BuildContext context, List<BlockApp> selected) {
  return showModalBottomSheet<List<BlockApp>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AppPickerSheet(selected: selected),
  );
}

class _AppPickerSheet extends StatefulWidget {
  final List<BlockApp> selected;
  const _AppPickerSheet({required this.selected});
  @override
  State<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<_AppPickerSheet> {
  late final Map<String, BlockApp> sel = {for (final a in widget.selected) a.pkg: a};
  List<BlockApp>? all;
  bool failed = false;
  String q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Blocker.listApps();
      final pop = [for (final a in l) if (_popular.contains(a.pkg)) a];
      final rest = [for (final a in l) if (!_popular.contains(a.pkg)) a];
      if (mounted) setState(() => all = [...pop, ...rest]);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = all;
    final shown = list == null
        ? <BlockApp>[]
        : [for (final a in list) if (q.isEmpty || a.label.toLowerCase().contains(q.toLowerCase())) a];
    return SizedBox(
      height: MediaQuery.of(context).size.height * .92,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('کدوم اپ‌ها بلاک بشن؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('تلفن، پیام، ساعت، دوربین و امید اینجا نیستن چون همیشه آزادن.',
                style: TextStyle(color: T.tx2, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => q = v.trim()),
              decoration: const InputDecoration(
                hintText: 'جستجو',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ]),
        ),
        Expanded(
          child: failed
              ? const Center(child: Text('فهرست اپ‌ها خونده نشد', style: TextStyle(color: T.tx2)))
              : list == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final a = shown[i];
                        final on = sel.containsKey(a.pkg);
                        return InkWell(
                          onTap: () => setState(() {
                            if (on) {
                              sel.remove(a.pkg);
                            } else {
                              sel[a.pkg] = a;
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: Row(children: [
                              AppIcon(a.pkg, size: 40),
                              const SizedBox(width: 12),
                              Expanded(child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if (_popular.contains(a.pkg)) ...[const Pill('پرتکرار'), const SizedBox(width: 8)],
                              Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined, color: on ? T.acc : T.tx2),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                sel.isEmpty ? 'تأیید' : 'تأیید (${fa(sel.length)} اپ)',
                onPressed: () => Navigator.pop(context, sel.values.toList()),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
