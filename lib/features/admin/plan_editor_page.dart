import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/jalali.dart';
import '../../core/models.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../../theme/lottie_views.dart';

class PlanEditor extends StatefulWidget {
  final String studentId;
  const PlanEditor({super.key, required this.studentId});
  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  static const _maxParts = 5; // اولویت ۱ تا ۵؛ ترتیب فهرست = اولویت
  late final List<String> days = [for (var i = 0; i < 7; i++) addDays(todayIso(), i)];
  final Map<String, List<PlanItem>> mine = {};
  final Map<String, PlanDay> server = {};
  final Set<String> dirty = {};
  bool loading = true, saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/admin/plan/${widget.studentId}', q: {'from': days.first});
      for (final x in (r['plans'] as List? ?? [])) {
        final p = PlanDay.fromJson(x);
        server[p.day] = p;
      }
      for (final d in days) {
        final p = server[d];
        final src = p == null ? <PlanItem>[] : (p.base.isNotEmpty ? p.base : p.items);
        mine[d] = [for (final i in src) PlanItem.fromJson(i.toJson())];
      }
    } on ApiError catch (e) {
      error = e.fa;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (dirty.isEmpty) return;
    setState(() => saving = true);
    try {
      await Api.i.put('/admin/plan/${widget.studentId}', body: {
        'days': [
          for (final d in days)
            if (dirty.contains(d)) {'day': d, 'items': [for (final i in mine[d]!) i.toJson()]},
        ],
      });
      dirty.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برنامه ذخیره شد')));
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _edit(String day, int? index) async {
    final it = index == null ? PlanItem(minutes: 60) : PlanItem.fromJson(mine[day]![index].toJson());
    final part = TextEditingController(text: it.part);
    final subject = TextEditingController(text: it.subject);
    final minutes = TextEditingController(text: it.minutes == 0 ? '' : '${it.minutes}');
    final tests = TextEditingController(text: it.testsTarget == 0 ? '' : '${it.testsTarget}');
    final note = TextEditingController(text: it.note);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: part, decoration: const InputDecoration(labelText: 'نام پارت (اجباری)')),
            const SizedBox(height: 10),
            TextField(controller: subject, decoration: const InputDecoration(labelText: 'درس')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'دقیقه (۰–۳۶۰)'))),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: tests,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'هدف تست'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'یادداشت')),
            const SizedBox(height: 14),
            Row(children: [
              if (index != null) ...[
                GhostButton('حذف', icon: Icons.delete_outline_rounded, onPressed: () => Navigator.pop(context, 'del')),
                const SizedBox(width: 10),
              ],
              Expanded(child: PrimaryButton('تأیید', onPressed: () => Navigator.pop(context, 'ok'))),
            ]),
          ]),
        ),
      ),
    );
    if (action == null) return;
    setState(() {
      final list = mine[day]!;
      if (action == 'del' && index != null) {
        list.removeAt(index);
      } else if (action == 'ok' && part.text.trim().isNotEmpty) {
        final n = PlanItem(
          part: part.text.trim(),
          subject: subject.text.trim(),
          minutes: (int.tryParse(minutes.text.trim().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).clamp(0, 360),
          testsTarget: (int.tryParse(tests.text.trim().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).clamp(0, 500),
          note: note.text.trim(),
        );
        if (index == null) {
          if (list.length >= _maxParts) return;
          list.add(n);
        } else {
          list[index] = n;
        }
      }
      dirty.add(day);
    });
  }

  void _copyPrev(String day) {
    final i = days.indexOf(day);
    if (i <= 0) return;
    setState(() {
      mine[day] = [for (final x in mine[days[i - 1]]!) PlanItem.fromJson(x.toJson())];
      dirty.add(day);
    });
  }

  String _line(PlanItem i) =>
      '${i.part}${i.subject.isEmpty ? '' : ' — ${i.subject}'}، ${fmtMin(i.minutes)}${i.testsTarget > 0 ? '، ${fa(i.testsTarget)} تست' : ''}';

  Future<void> _copyTo(String from) async {
    final others = [for (final x in days) if (x != from) x];
    final targets = await showModalBottomSheet<Set<String>>(
      context: context,
      builder: (_) => _CopyToSheet(days: others),
    );
    if (targets == null || targets.isEmpty) return;
    setState(() {
      for (final t in targets) {
        mine[t] = [for (final x in mine[from]!) PlanItem.fromJson(x.toJson())];
        dirty.add(t);
      }
    });
  }

  Widget _actionChip(String label, IconData icon, VoidCallback on) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: on,
        child: Pill(label, icon: icon, color: T.tx),
      );

  Widget _partRow(String d, int i, Key key) {
    final it = mine[d]![i];
    final optional = i == 4;
    return InkWell(
      key: key,
      onTap: () => _edit(d, i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ReorderableDragStartListener(
            index: i,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(0, 2, 8, 0),
              child: Icon(Icons.drag_indicator_rounded, size: 20, color: T.tx2),
            ),
          ),
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: optional ? Colors.transparent : T.acc,
              border: Border.all(color: T.acc),
            ),
            child: Text(fa(i + 1),
                style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: optional ? T.acc : T.onAcc)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.part, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (it.subject.isNotEmpty) Pill(it.subject),
                Pill(fmtMin(it.minutes)),
                if (it.testsTarget > 0) Pill('${fa(it.testsTarget)} تست'),
                if (optional) const Pill('اختیاری', color: T.acc),
              ]),
            ]),
          ),
          const Icon(Icons.edit_rounded, size: 15, color: T.tx2),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppLoader();
    if (error != null) return Center(child: Text(error!));
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
          for (final d in days)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Glass(
                borderColor: dirty.contains(d) ? T.acc : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(jalaliFull(d), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (d != days.first) _actionChip('کپی از روز قبل', Icons.copy_rounded, () => _copyPrev(d)),
                    if (mine[d]!.isNotEmpty)
                      _actionChip('کپی به روزهای دیگر', Icons.content_copy_rounded, () => _copyTo(d)),
                  ]),
                  if (mine[d]!.isEmpty)
                    const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text('خالی', style: TextStyle(color: T.tx2)))
                  else
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, _, __) =>
                          Material(color: T.surfaceHi, borderRadius: BorderRadius.circular(12), child: child),
                      onReorder: (o, n) => setState(() {
                        if (n > o) n -= 1;
                        final x = mine[d]!.removeAt(o);
                        mine[d]!.insert(n, x);
                        dirty.add(d);
                      }),
                      children: [
                        for (var i = 0; i < mine[d]!.length; i++) _partRow(d, i, ObjectKey(mine[d]![i])),
                      ],
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                        onPressed: mine[d]!.length >= _maxParts ? null : () => _edit(d, null),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(mine[d]!.length >= _maxParts ? 'حداکثر ${fa(_maxParts)} پارت' : 'افزودن پارت')),
                  ),
                  if (server[d]?.source == 'ai')
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('نسخه‌ی AI در برابر برنامه‌ی من',
                            style: TextStyle(color: T.hi, fontSize: 13)),
                        children: [
                          Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('برنامه‌ی من:', style: TextStyle(fontWeight: FontWeight.w700)),
                                for (final i in server[d]!.base)
                                  Text(_line(i), style: const TextStyle(color: T.tx2, fontSize: 12)),
                                const SizedBox(height: 8),
                                const Text('ویرایش AI:', style: TextStyle(fontWeight: FontWeight.w700)),
                                for (final i in server[d]!.items)
                                  Text(_line(i), style: const TextStyle(color: T.hi, fontSize: 12)),
                                if (server[d]!.note.isNotEmpty)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(server[d]!.note,
                                          style: const TextStyle(color: T.tx2, fontSize: 12))),
                              ])),
                        ],
                      ),
                    ),
                ]),
              ),
            ),
        ]),
      ),
      Container(
        decoration: const BoxDecoration(color: T.bg, border: Border(top: BorderSide(color: T.line))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: PrimaryButton(dirty.isEmpty ? 'تغییری نیست' : 'ذخیره‌ی ${fa(dirty.length)} تغییر',
                busy: saving, onPressed: dirty.isEmpty ? null : _save),
          ),
        ),
      ),
    ]);
  }
}

class _CopyToSheet extends StatefulWidget {
  final List<String> days;
  const _CopyToSheet({required this.days});
  @override
  State<_CopyToSheet> createState() => _CopyToSheetState();
}

class _CopyToSheetState extends State<_CopyToSheet> {
  final Set<String> sel = {};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('کپی به کدام روزها؟', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('برنامه‌ی روزهای انتخاب‌شده جایگزین می‌شود.',
            style: TextStyle(color: T.tx2, fontSize: 12)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in widget.days)
            FilterChip(
              label: Text(jalaliShort(d)),
              selected: sel.contains(d),
              showCheckmark: false,
              selectedColor: T.acc,
              backgroundColor: T.sec,
              side: BorderSide(color: sel.contains(d) ? T.acc : T.line2),
              labelStyle: TextStyle(color: sel.contains(d) ? T.onAcc : T.tx, fontWeight: FontWeight.w500),
              shape: const StadiumBorder(),
              onSelected: (v) => setState(() => v ? sel.add(d) : sel.remove(d)),
            ),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(sel.isEmpty ? 'یک روز انتخاب کن' : 'کپی به ${fa(sel.length)} روز',
              onPressed: sel.isEmpty ? null : () => Navigator.pop(context, sel)),
        ),
      ]),
    );
  }
}
