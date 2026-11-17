import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/blocker.dart';
import '../../core/config.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';

/// آیکون اپ (از سیستم گرفته می‌شود و کش می‌شود).
class AppIcon extends StatelessWidget {
  final String pkg;
  final double size;
  const AppIcon(this.pkg, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: Blocker.icon(pkg),
      builder: (_, s) => ClipRRect(
        borderRadius: BorderRadius.circular(size * .26),
        child: s.data != null
            ? Image.memory(s.data!, width: size, height: size, gaplessPlayback: true)
            : Container(
                width: size,
                height: size,
                color: T.brown,
                child: Icon(Icons.apps_rounded, size: size * .5, color: T.tx2),
              ),
      ),
    );
  }
}

/// کارت انتخاب حالت (رادیو).
class ModeCard extends StatelessWidget {
  final bool selected;
  final String title, desc;
  final IconData icon;
  final VoidCallback? onTap;
  const ModeCard({
    super.key,
    required this.selected,
    required this.title,
    required this.desc,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      highlight: selected,
      borderColor: selected ? T.acc : null,
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            color: selected ? T.acc : T.tx2),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: selected ? T.acc : T.tx),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
            const SizedBox(height: 6),
            Text(desc, style: const TextStyle(color: T.tx2, fontSize: 12.5)),
          ]),
        ),
      ]),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text, style: const TextStyle(color: T.tx2, fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

/// صفحه‌ی توضیح ساده قبل از روشن‌کردن (چون دانش‌آموزان ممکن است زیر ۱۸ سال باشند).
Future<bool?> showBlockerConsent(BuildContext context) {
  Widget row(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 20, color: T.acc),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 13.5))),
        ]),
      );
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('قبل از روشن کردن', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('این ابزار اختیاریه و فقط به انتخاب خودته.', style: TextStyle(color: T.tx2, fontSize: 13)),
          const SizedBox(height: 16),
          row(Icons.visibility_outlined, 'فقط وقتی یکی از بازه‌هات فعاله، می‌بینه کدوم اپ جلوی صفحه‌ست.'),
          row(Icons.schedule_rounded, 'بیرون از بازه‌ها هیچ‌چیز خونده یا ثبت نمی‌شه.'),
          row(Icons.lock_outline_rounded,
              'محتوای صفحه، تاریخچه و لیست اپ‌هات خونده یا فرستاده نمی‌شه. دوربین و میکروفون هم استفاده نمی‌شه.'),
          row(
              Icons.person_outline_rounded,
              Config.sendBlockerEvents
                  ? 'مشاورت فقط تعداد تلاش‌ها رو می‌بینه؛ مثلاً «۳ بار تلاش برای باز کردن اینستاگرام».'
                  : 'فعلاً این شمارش‌ها فقط روی گوشی خودته و برای مشاور فرستاده نمی‌شه.'),
          row(Icons.call_outlined, 'تلفن، پیام، ساعت و آلارم، دوربین و خود امید همیشه آزادن.'),
          row(Icons.power_settings_new_rounded,
              'هر وقت بخوای خاموشش می‌کنی؛ جز وقتی که خودت «قطع کامل» رو برای یک بازه انتخاب کردی.'),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: PrimaryButton('متوجه شدم، روشن کن', onPressed: () => Navigator.pop(c, true))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: GhostButton('فعلاً نه', onPressed: () => Navigator.pop(c, false))),
        ]),
      ),
    ),
  );
}
