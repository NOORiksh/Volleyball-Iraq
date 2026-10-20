import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'admin_access.dart';
import 'admin_content.dart';
import 'logic.dart';
import 'news_page.dart';
import 'services.dart';

class _Sec {
  final IconData icon;
  final String title, sub;
  final Widget Function() page;
  _Sec(this.icon, this.title, this.sub, this.page);
}

/// بوابة الإدارة: الرمز السري يفتح حساب "مدير المسؤولين"، ثم تظهر الأقسام حسب الصلاحية.
class AdminPage extends StatefulWidget {
  final Session session;
  const AdminPage({super.key, required this.session});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final code = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    if (!s.isStaff) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock, size: 48),
          const SizedBox(height: 8),
          const Text('رمز مدير المسؤولين', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: code, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رمز الدخول السري')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : () async {
              setState(() => busy = true);
              final e = await Auth.unlockAdmin(code.text.trim());
              if (mounted) {
                setState(() => busy = false);
                if (e != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e)));
              }
            },
            child: const Text('دخول'),
          ),
        ]),
      );
    }
    final secs = <_Sec>[
      if (s.canTournament) _Sec(Icons.sports_volleyball, 'البطولة', 'الفرق والمباريات والنتائج والتصفيات', () => const TournamentAdmin()),
      if (s.canNews) _Sec(Icons.campaign, 'الأخبار والإشعارات', 'نشر وتعديل وحذف مع صور', () => NewsPage(session: s)),
      if (s.canQuestions) _Sec(Icons.quiz, 'بنك الأسئلة', 'إضافة وتعديل وحذف الأسئلة', () => const QuestionsAdmin()),
      if (s.canChat) _Sec(Icons.block, 'المحظورون من الشات', 'رفع الحظر (الحذف والحظر من الشات بضغطة مطوّلة)', () => const BansAdmin()),
      if (s.isSuper) ...[
        _Sec(Icons.handshake, 'الرعاة', 'إضافة الرعاة وشعاراتهم وروابطهم', () => const SponsorsAdmin()),
        _Sec(Icons.image, 'المحتوى والصور', 'نصوص وصور الصفحة الرئيسية', () => const SiteAdmin()),
        _Sec(Icons.vpn_key, 'كلمات سر المهام', 'إنشاء باسورد لكل مهمة للتسجيل به', () => const PasswordsAdmin()),
        _Sec(Icons.groups, 'الحسابات والصلاحيات', 'أصحاب المهام: تغيير الدور أو السحب', () => const StaffAdmin()),
      ],
    ];
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(leading: const Icon(Icons.shield), title: Text('صلاحيتك: ${roleNames[s.role] ?? s.role}'))),
      for (final x in secs)
        Card(
          child: ListTile(
            leading: Icon(x.icon), title: Text(x.title), subtitle: Text(x.sub), trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => x.page())),
          ),
        ),
    ]);
  }
}

// ======================= البطولة =======================
class TournamentAdmin extends StatefulWidget {
  const TournamentAdmin({super.key});
  @override
  State<TournamentAdmin> createState() => _TournamentAdminState();
}

class _TournamentAdminState extends State<TournamentAdmin> {
  final teamName = TextEditingController(), seed = TextEditingController();
  Team? ta, tb;
  int bestOf = 3, slot = 0;
  String stage = 'group';

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('البطولة')),
        body: StreamBuilder<Tournament>(
          stream: Repo.tournament(),
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final t = s.data!;
            return ListView(padding: const EdgeInsets.all(12), children: [
              _card('إضافة فريق', [
                Row(children: [
                  Expanded(child: TextField(controller: teamName, decoration: const InputDecoration(labelText: 'اسم الفريق'))),
                  const SizedBox(width: 8),
                  SizedBox(width: 80, child: TextField(controller: seed, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'التصنيف'))),
                  IconButton(icon: const Icon(Icons.add), onPressed: () async {
                    if (teamName.text.trim().isEmpty) return;
                    await Repo.addTeam(teamName.text.trim(), int.tryParse(seed.text) ?? t.teams.length + 1);
                    teamName.clear(); seed.clear();
                  }),
                ]),
              ]),
              _card('الفرق', [
                for (final tm in t.teams)
                  ListTile(
                    dense: true, title: Text(tm.name),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _editTeam(tm)),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _confirm('حذف ${tm.name}؟', () => Cms.deleteTeam(tm.id))),
                    ]),
                  ),
              ]),
              _card('إنشاء مباراة', [
                Row(children: [
                  Expanded(child: _teamDrop(t.teams, ta, (v) => setState(() => ta = v))),
                  const Padding(padding: EdgeInsets.all(8), child: Text('×')),
                  Expanded(child: _teamDrop(t.teams, tb, (v) => setState(() => tb = v))),
                ]),
                Wrap(spacing: 8, children: [
                  DropdownButton<int>(value: bestOf, items: const [3, 5].map((e) => DropdownMenuItem(value: e, child: Text('$e أشواط'))).toList(), onChanged: (v) => setState(() => bestOf = v!)),
                  DropdownButton<String>(value: stage, items: const {'group': 'مجموعات', 'qf': 'ربع النهائي', 'sf': 'نصف النهائي', 'final': 'النهائي'}.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) => setState(() => stage = v!)),
                  if (stage != 'group') DropdownButton<int>(value: slot, items: List.generate(4, (i) => DropdownMenuItem(value: i, child: Text('موقع ${i + 1}'))), onChanged: (v) => setState(() => slot = v!)),
                ]),
                FilledButton(onPressed: () {
                  if (ta == null || tb == null || ta == tb) { _toast('اختر فريقين مختلفين'); return; }
                  Repo.createMatch(ta!, tb!, bestOf, stage, slot);
                }, child: const Text('إنشاء')),
              ]),
              const Text('المباريات', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final m in t.all)
                Card(
                  child: ListTile(
                    title: Text('${m.a.name} × ${m.b.name}  (${m.stage})'),
                    subtitle: Text(m.sets.map((x) => '${x.a}-${x.b}').join('  |  ') + (m.finished ? '  ✔' : '')),
                    trailing: Wrap(children: [
                      if (m.sets.isNotEmpty) IconButton(tooltip: 'تراجع عن آخر شوط', icon: const Icon(Icons.undo), onPressed: () => Cms.popSet(m)),
                      if (!m.finished) IconButton(icon: const Icon(Icons.add_circle), onPressed: () => _addSet(m)),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _confirm('حذف المباراة؟', () => Repo.deleteMatch(m.id!))),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );

  Widget _card(String title, List<Widget> kids) => Card(
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), ...kids])));

  Widget _teamDrop(List<Team> ts, Team? v, ValueChanged<Team?> f) => DropdownButton<Team>(
      isExpanded: true, value: v, hint: const Text('فريق'),
      items: ts.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(), onChanged: f);

  Future<void> _confirm(String q, Future<void> Function() go) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(title: Text(q), actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
      ]),
    );
    if (ok == true) await go();
  }

  Future<void> _editTeam(Team t) async {
    final n = TextEditingController(text: t.name), sd = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الفريق'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
          TextField(controller: sd, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'التصنيف (فارغ = بدون تغيير)')),
        ]),
        actions: [TextButton(onPressed: () { Navigator.pop(ctx); Cms.editTeam(t.id, n.text.trim(), int.tryParse(sd.text)); }, child: const Text('حفظ'))],
      ),
    );
  }

  Future<void> _addSet(VMatch m) async {
    final a = TextEditingController(), b = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('الشوط ${m.sets.length + 1}${m.sets.length == m.bestOf - 1 ? " (فاصل)" : ""}'),
        content: Row(children: [
          Expanded(child: TextField(controller: a, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: m.a.name))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: b, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: m.b.name))),
        ]),
        actions: [
          TextButton(onPressed: () async {
            Navigator.pop(ctx);
            final err = await Repo.addSet(m, int.tryParse(a.text) ?? -1, int.tryParse(b.text) ?? -1);
            if (err != null) _toast(err);
          }, child: const Text('حفظ')),
        ],
      ),
    );
  }
}

// ======================= المحظورون =======================
class BansAdmin extends StatelessWidget {
  const BansAdmin({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المحظورون من الشات')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: Repo.bans(),
          builder: (c, b) {
            final docs = b.data?.docs ?? [];
            if (docs.isEmpty) return const Center(child: Text('لا يوجد محظورون'));
            return ListView(children: [
              for (final d in docs)
                ListTile(title: Text('${d.data()['name'] ?? d.id}'), trailing: TextButton(onPressed: () => Repo.unban(d.id), child: const Text('رفع الحظر'))),
            ]);
          },
        ),
      );
}
