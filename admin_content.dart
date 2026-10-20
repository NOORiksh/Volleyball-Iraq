import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'services.dart';
import 'widgets.dart';

void _toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<void> _confirm(BuildContext context, String q, Future<void> Function() go) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(title: Text(q), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
    ]),
  );
  if (ok == true) await go();
}

// ======================= الرعاة =======================
class SponsorsAdmin extends StatelessWidget {
  const SponsorsAdmin({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الرعاة')),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('راعٍ جديد')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: Cms.sponsors(),
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final docs = s.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('لا يوجد رعاة بعد'));
            return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
              for (final d in docs)
                Card(
                  child: ListTile(
                    onTap: () => _edit(context, d),
                    leading: SizedBox(
                      width: 48, height: 48,
                      child: '${d.data()['logo'] ?? ''}'.isEmpty
                          ? const Icon(Icons.store)
                          : Image.network('${d.data()['logo']}', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                    ),
                    title: Text('${d.data()['name'] ?? ''}'),
                    subtitle: Text('${d.data()['tier'] == 'main' ? 'الراعي الرئيسي' : 'راعٍ'} · ${d.data()['link'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(value: d.data()['active'] != false, onChanged: (v) => Cms.saveSponsor(d.id, {'active': v})),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _confirm(context, 'حذف الراعي؟', () => Cms.deleteSponsor(d.id))),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );

  Future<void> _edit(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>>? d) async {
    final x = d?.data() ?? <String, dynamic>{};
    final name = TextEditingController(text: '${x['name'] ?? ''}');
    final link = TextEditingController(text: '${x['link'] ?? ''}');
    final order = TextEditingController(text: '${x['order'] ?? 0}');
    String tier = '${x['tier'] ?? 'regular'}', logo = '${x['logo'] ?? ''}';
    bool active = x['active'] != false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(d == null ? 'راعٍ جديد' : 'تعديل الراعي'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الراعي')),
              TextField(controller: link, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'رابط الراعي (https://...)')),
              TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الترتيب (الأصغر أولاً)')),
              DropdownButtonFormField<String>(
                value: tier,
                items: const [DropdownMenuItem(value: 'main', child: Text('الراعي الرئيسي')), DropdownMenuItem(value: 'regular', child: Text('راعٍ'))],
                onChanged: (v) => set(() => tier = v!),
                decoration: const InputDecoration(labelText: 'الفئة'),
              ),
              SwitchListTile(value: active, onChanged: (v) => set(() => active = v), title: const Text('ظاهر في الصفحة الرئيسية')),
              ImageField(label: 'شعار الراعي', folder: 'sponsors', url: logo, onChanged: (u) => set(() => logo = u)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final l = link.text.trim();
                if (name.text.trim().isEmpty) return;
                if (l.isNotEmpty && !l.startsWith('http')) { _toast(context, 'الرابط يجب أن يبدأ بـ https://'); return; }
                Navigator.pop(ctx);
                await Cms.saveSponsor(d?.id, {'name': name.text.trim(), 'link': l, 'tier': tier, 'order': int.tryParse(order.text) ?? 0, 'active': active, 'logo': logo});
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================= نصوص وصور الصفحة الرئيسية =======================
class SiteAdmin extends StatefulWidget {
  const SiteAdmin({super.key});
  @override
  State<SiteAdmin> createState() => _SiteAdminState();
}

class _SiteAdminState extends State<SiteAdmin> {
  final title = TextEditingController(), subtitle = TextEditingController(), about = TextEditingController();
  final sponsorsTitle = TextEditingController(), footer = TextEditingController();
  String hero = '', logo = '';
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    Cms.site().first.then((d) {
      final x = d.data() ?? <String, dynamic>{};
      title.text = '${x['title'] ?? ''}'; subtitle.text = '${x['subtitle'] ?? ''}'; about.text = '${x['about'] ?? ''}';
      sponsorsTitle.text = '${x['sponsorsTitle'] ?? ''}'; footer.text = '${x['footer'] ?? ''}';
      hero = '${x['heroImage'] ?? ''}'; logo = '${x['logo'] ?? ''}';
      if (mounted) setState(() => loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المحتوى والصور'), actions: [
          TextButton(
            onPressed: !loaded ? null : () async {
              await Cms.saveSite({'title': title.text.trim(), 'subtitle': subtitle.text.trim(), 'about': about.text.trim(),
                'sponsorsTitle': sponsorsTitle.text.trim(), 'footer': footer.text.trim(), 'heroImage': hero, 'logo': logo});
              if (context.mounted) _toast(context, 'تم الحفظ');
            },
            child: const Text('حفظ'),
          ),
        ]),
        body: !loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان الصفحة الرئيسية')),
                TextField(controller: subtitle, decoration: const InputDecoration(labelText: 'العنوان الفرعي')),
                TextField(controller: about, maxLines: 5, decoration: const InputDecoration(labelText: 'نبذة عن البطولة')),
                TextField(controller: sponsorsTitle, decoration: const InputDecoration(labelText: 'عنوان قسم الرعاة (الافتراضي: رعاة البطولة)')),
                TextField(controller: footer, maxLines: 2, decoration: const InputDecoration(labelText: 'نص أسفل الصفحة')),
                ImageField(label: 'صورة الغلاف', folder: 'site', url: hero, onChanged: (u) => setState(() => hero = u)),
                ImageField(label: 'شعار البطولة', folder: 'site', url: logo, onChanged: (u) => setState(() => logo = u)),
              ]),
      );
}

// ======================= بنك الأسئلة =======================
class QuestionsAdmin extends StatelessWidget {
  const QuestionsAdmin({super.key});
  static const cats = {'rules': 'القوانين', 'court': 'الملعب', 'terms': 'المصطلحات', 'history': 'التاريخ', 'tournament': 'البطولة'};

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('بنك الأسئلة')),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('سؤال جديد')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: Repo.questions(),
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final docs = s.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('لا توجد أسئلة'));
            return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
              for (final d in docs)
                ListTile(
                  title: Text('${d.data()['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(cats['${d.data()['category']}'] ?? '${d.data()['category']}'),
                  onTap: () => _edit(context, d),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _confirm(context, 'حذف السؤال؟', () => Cms.deleteQuestion(d.id))),
                ),
            ]);
          },
        ),
      );

  Future<void> _edit(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>>? d) async {
    final x = d?.data() ?? <String, dynamic>{};
    final opts = List<String>.from((x['options'] as List?) ?? const []);
    while (opts.length < 4) { opts.add(''); }
    final text = TextEditingController(text: '${x['text'] ?? ''}'), exp = TextEditingController(text: '${x['explanation'] ?? ''}');
    final oc = [for (final o in opts.take(4)) TextEditingController(text: o)];
    int correct = d == null ? 0 : ((await Cms.correctOf(d.id)) ?? 0);
    if (correct > 3) correct = 0;
    String cat = cats.containsKey('${x['category']}') ? '${x['category']}' : 'rules';
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(d == null ? 'سؤال جديد' : 'تعديل السؤال'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: text, maxLines: 2, decoration: const InputDecoration(labelText: 'نص السؤال')),
              for (var i = 0; i < 4; i++) TextField(controller: oc[i], decoration: InputDecoration(labelText: 'الخيار ${i + 1}${i > 1 ? " (اختياري)" : ""}')),
              DropdownButtonFormField<int>(
                value: correct,
                items: [for (var i = 0; i < 4; i++) DropdownMenuItem(value: i, child: Text('الإجابة الصحيحة: الخيار ${i + 1}'))],
                onChanged: (v) => set(() => correct = v!),
              ),
              DropdownButtonFormField<String>(
                value: cat,
                items: cats.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => set(() => cat = v!),
                decoration: const InputDecoration(labelText: 'التصنيف'),
              ),
              TextField(controller: exp, maxLines: 2, decoration: const InputDecoration(labelText: 'شرح الإجابة (اختياري)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final filled = <String>[];
                var ci = -1;
                for (var i = 0; i < 4; i++) {
                  final t = oc[i].text.trim();
                  if (t.isEmpty) continue;
                  if (i == correct) ci = filled.length;
                  filled.add(t);
                }
                if (text.text.trim().isEmpty || filled.length < 2 || ci < 0) {
                  _toast(context, 'اكتب السؤال وخيارين على الأقل، والإجابة الصحيحة يجب أن تكون خياراً غير فارغ');
                  return;
                }
                Navigator.pop(ctx);
                await Cms.saveQuestion(d?.id, {'category': cat, 'difficulty': x['difficulty'] ?? 2, 'text': text.text.trim(), 'options': filled, 'explanation': exp.text.trim()}, ci);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
