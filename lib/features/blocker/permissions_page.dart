import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/blocker.dart';
import '../../core/jalali.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import 'widgets.dart';

/// راهنمای قدم‌به‌قدم مجوزها. هر مجوز: توضیح ساده + دکمه‌ی «فعال کن» + راه جایگزین.
class BlockerPermissionsPage extends StatefulWidget {
  const BlockerPermissionsPage({super.key});
  @override
  State<BlockerPermissionsPage> createState() => _BlockerPermissionsPageState();
}

class _BlockerPermissionsPageState extends State<BlockerPermissionsPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Blocker.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) Blocker.refresh();
  }

  Future<void> _open(String kind) async {
    final ok = await Blocker.openSettings(kind);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('صفحه‌ی تنظیمات باز نشد؛ از «تنظیمات گوشی ← اپ‌ها ← امید» دستی پیداش کن')));
    }
  }

  Widget _step({
    required int n,
    required String title,
    required String why,
    required bool? done,
    required String kind,
    String? alt,
    bool manual = false,
    String? manualKey,
  }) {
    final ok = done == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        borderColor: ok ? T.ok.withOpacity(.5) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: ok ? T.ok : T.tx2, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text('${fa(n)}. $title', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            if (done == null && !manual) const Pill('نامشخص'),
          ]),
          const SizedBox(height: 8),
          Text(why, style: const TextStyle(color: T.tx2, fontSize: 12.5)),
          if (alt != null) ...[
            const SizedBox(height: 6),
            Text(alt, style: const TextStyle(color: T.tx2, fontSize: 12)),
          ],
          if (!ok) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: GhostButton('فعال کن', icon: Icons.open_in_new_rounded, onPressed: () => _open(kind))),
              if (manual || done == null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton('انجام دادم', icon: Icons.done_rounded, onPressed: () => Blocker.setFlag(manualKey ?? '${kind}_done', true)),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مجوزهای بلاکر')),
      body: ValueListenableBuilder<BlockerState?>(
        valueListenable: Blocker.state,
        builder: (_, s, __) {
          final p = s?.perms ?? const BlockerPerms();
          final list = <bool?>[
            p.usage,
            p.overlay,
            p.notifications,
            p.battery,
            if (p.xiaomi) (p.popup == true || p.popupDone),
            if (p.xiaomi) p.autostartDone,
          ];
          final done = list.where((e) => e == true).length;
          var i = 0;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
            PageTitle('چند قدم تا آماده شدن', sub: '${fa(done)} از ${fa(list.length)} مجوز آماده‌ست'),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: list.isEmpty ? 0 : done / list.length, minHeight: 6),
            ),
            const SizedBox(height: 16),
            _step(
              n: ++i,
              title: 'دسترسی به آمار استفاده',
              why: 'برای اینکه بفهمیم کدوم اپ جلوی صفحه‌ست. فقط داخل بازه‌های فعال خونده می‌شه، نه بیرونش.',
              alt: 'پیدا نشد؟ تنظیمات ← حریم خصوصی (یا برنامه‌ها) ← دسترسی ویژه ← دسترسی به داده‌های استفاده ← امید.',
              done: p.usage,
              kind: 'usage',
            ),
            _step(
              n: ++i,
              title: 'نمایش روی اپ‌های دیگر',
              why: 'برای اینکه صفحه‌ی بلاک بتونه روی اپ ممنوع بیاد.',
              alt: 'پیدا نشد؟ تنظیمات ← اپ‌ها ← امید ← «نمایش روی سایر برنامه‌ها» رو روشن کن.',
              done: p.overlay,
              kind: 'overlay',
            ),
            _step(
              n: ++i,
              title: 'اعلان',
              why: 'یک نوتیف ثابت و بی‌صدا که نشون می‌ده بلاکر روشنه. بدونش اندروید ممکنه سرویس رو ساکت کنه.',
              done: p.notifications,
              kind: 'notifications',
            ),
            _step(
              n: ++i,
              title: 'بدون محدودیت باتری',
              why: 'تا اندروید بلاکر رو وسط روز نکشه. در پیام اندروید «اجازه بده» رو بزن.',
              alt: 'پیدا نشد؟ تنظیمات ← باتری ← امید ← «بدون محدودیت».',
              done: p.battery,
              kind: 'battery',
            ),
            if (p.xiaomi) ...[
              _step(
                n: ++i,
                title: 'پنجره‌ی پاپ‌آپ در پس‌زمینه (شیائومی / Poco)',
                why: 'بدون این، صفحه‌ی بلاک از پس‌زمینه باز نمی‌شه. در MIUI/HyperOS جداست و حتماً باید روشن باشه.',
                alt: 'مسیر: تنظیمات ← اپ‌ها ← مدیریت اپ‌ها ← امید ← سایر مجوزها ← «نمایش پنجره‌ی پاپ‌آپ در پس‌زمینه». بعدش «انجام دادم» رو بزن.',
                done: p.popup == true || p.popupDone ? true : (p.popup == null ? null : false),
                kind: 'popup',
                manual: true,
                manualKey: 'popup_done',
              ),
              _step(
                n: ++i,
                title: 'شروع خودکار',
                why: 'تا بعد از ریستارت گوشی، بلاکر خودش دوباره روشن بشه.',
                alt: 'مسیر: امنیت ← مجوزها ← شروع خودکار ← امید رو روشن کن. بعدش «انجام دادم» رو بزن.',
                done: p.autostartDone,
                kind: 'autostart',
                manual: true,
                manualKey: 'autostart_done',
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(p.core ? 'تمومه، برگرد' : 'برگرد', onPressed: () => context.pop()),
            ),
            if (!p.core)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('بدون دو مجوز اول، بلاکر روشن نمی‌شه.',
                    textAlign: TextAlign.center, style: TextStyle(color: T.warn, fontSize: 12)),
              ),
          ]);
        },
      ),
    );
  }
}
