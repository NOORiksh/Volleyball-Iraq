// نسخة معاينة تعمل في DartPad (https://dartpad.dev) بملف واحد وبدون Firebase.
// ⚠️ للعرض فقط: الحسابات في الذاكرة، والتحقق من الرمز هنا محلي. في التطبيق الحقيقي يتم على الخادم.
// حسابات التجربة: مشجع: 0770 / 123456   |   مسؤول: مدير / 123456 (ثم الرمز 20072026)
import 'package:flutter/material.dart';

// ======================= قوانين الكرة الطائرة =======================
class SetScore {
  final int a, b;
  const SetScore(this.a, this.b);
}

bool isValidSet(int a, int b, {required bool decider}) {
  final t = decider ? 15 : 25;
  final w = a > b ? a : b, l = a > b ? b : a;
  if (w < t) return false;
  return w > t ? w - l == 2 : w - l >= 2;
}

class Team {
  final String id, name;
  const Team(this.id, this.name);
  @override
  bool operator ==(Object o) => o is Team && o.id == id;
  @override
  int get hashCode => id.hashCode;
}

class VMatch {
  final Team a, b;
  final int bestOf;
  final List<SetScore> sets = [];
  VMatch(this.a, this.b, {this.bestOf = 3});
  int get need => bestOf ~/ 2 + 1;
  int get setsA => sets.where((s) => s.a > s.b).length;
  int get setsB => sets.where((s) => s.b > s.a).length;
  bool get finished => setsA == need || setsB == need;
  Team? get winner => !finished ? null : (setsA > setsB ? a : b);
  String? addSet(int x, int y) {
    if (finished) return 'المباراة منتهية';
    final decider = sets.length == bestOf - 1;
    if (!isValidSet(x, y, decider: decider)) {
      return decider ? 'الشوط الفاصل ينتهي عند 15 بفارق نقطتين' : 'الشوط ينتهي عند 25 بفارق نقطتين';
    }
    sets.add(SetScore(x, y));
    return null;
  }
}

class StandRow {
  final Team team;
  int played = 0, wins = 0, pts = 0, sw = 0, sl = 0, pf = 0, pa = 0;
  StandRow(this.team);
  double get setRatio => sl == 0 ? (sw == 0 ? 0 : 1e9) : sw / sl;
  double get pointRatio => pa == 0 ? (pf == 0 ? 0 : 1e9) : pf / pa;
}

List<StandRow> standings(List<Team> teams, List<VMatch> matches) {
  final rows = {for (final t in teams) t.id: StandRow(t)};
  for (final m in matches.where((m) => m.finished)) {
    final winnerIsA = m.winner == m.a;
    final ra = rows[m.a.id]!, rb = rows[m.b.id]!;
    final rw = winnerIsA ? ra : rb, rl = winnerIsA ? rb : ra;
    final full = (winnerIsA ? m.setsB : m.setsA) == m.need - 1; // 3-2 (أو 2-1 في 3 أشواط)
    rw.pts += full ? 2 : 3;
    rl.pts += full ? 1 : 0;
    rw.wins++;
    ra.played++;
    rb.played++;
    ra.sw += m.setsA; ra.sl += m.setsB;
    rb.sw += m.setsB; rb.sl += m.setsA;
    for (final s in m.sets) {
      ra.pf += s.a; ra.pa += s.b;
      rb.pf += s.b; rb.pa += s.a;
    }
  }
  return rows.values.toList()
    ..sort((x, y) {
      var c = y.pts.compareTo(x.pts);
      if (c != 0) return c;
      c = y.wins.compareTo(x.wins);
      if (c != 0) return c;
      c = y.setRatio.compareTo(x.setRatio);
      return c != 0 ? c : y.pointRatio.compareTo(x.pointRatio);
    });
}

class Tie {
  Team? a, b;
  VMatch? match;
  Tie([this.a, this.b]);
  Team? get winner => match?.winner;
}

List<List<Tie>> buildBracket(List<Team> s) => [
      [Tie(s[0], s[7]), Tie(s[3], s[4]), Tie(s[1], s[6]), Tie(s[2], s[5])],
      [Tie(), Tie()],
      [Tie()],
    ];

void advance(List<List<Tie>> rounds) {
  for (var r = 0; r < rounds.length - 1; r++) {
    for (var i = 0; i < rounds[r].length; i++) {
      final next = rounds[r + 1][i ~/ 2];
      if (i % 2 == 0) { next.a = rounds[r][i].winner; } else { next.b = rounds[r][i].winner; }
    }
  }
}

String roundName(int r, int n) => r == n - 1 ? 'النهائي' : r == n - 2 ? 'نصف النهائي' : 'ربع النهائي';

// ======================= فحوص ذاتية =======================
class T {
  final String name;
  final bool ok;
  T(this.name, this.ok);
}

Set<int> _simulate(int target) {
  // يلعب الشوط نقطة بنقطة ويجمع كل النتائج النهائية الممكنة (مستقل عن isValidSet)
  final ended = <int>{};
  var alive = <int>{0};
  for (var i = 0; i < 80; i++) {
    final next = <int>{};
    for (final k in alive) {
      final a = k ~/ 100, b = k % 100;
      for (final s in [[a + 1, b], [a, b + 1]]) {
        final hi = s[0] > s[1] ? s[0] : s[1];
        final key = s[0] * 100 + s[1];
        if (hi >= target && (s[0] - s[1]).abs() >= 2) { ended.add(key); } else { next.add(key); }
      }
    }
    alive = next;
  }
  return ended;
}

VMatch _mk(Team x, Team y, int bo, List<List<int>> sets) {
  final m = VMatch(x, y, bestOf: bo);
  for (final s in sets) { m.addSet(s[0], s[1]); }
  return m;
}

List<T> runSelfTests() {
  final r = <T>[];
  void t(String n, bool ok) => r.add(T(n, ok));
  for (final dec in [false, true]) {
    final e = _simulate(dec ? 15 : 25);
    var bad = 0;
    for (var x = 0; x <= 50; x++) {
      for (var y = 0; y <= 50; y++) {
        if (isValidSet(x, y, decider: dec) != e.contains(x * 100 + y)) bad++;
      }
    }
    t('مطابقة المحاكاة لكل النتائج حتى 50 (${dec ? "فاصل 15" : "عادي 25"}): $bad اختلاف', bad == 0);
  }
  t('26-24 صالح', isValidSet(26, 24, decider: false));
  t('25-24 غير صالح', !isValidSet(25, 24, decider: false));
  t('27-24 غير صالح', !isValidSet(27, 24, decider: false));
  t('16-14 صالح في الفاصل', isValidSet(16, 14, decider: true));
  t('15-14 غير صالح في الفاصل', !isValidSet(15, 14, decider: true));

  final a = const Team('a', 'أ'), b = const Team('b', 'ب'), c = const Team('c', 'ج'), d = const Team('d', 'د');
  final m = VMatch(a, b);
  t('3 أشواط: الشوط 1', m.addSet(25, 20) == null);
  t('3 أشواط: الشوط 2', m.addSet(20, 25) == null);
  t('الشوط الثالث فاصل: يرفض 25-20', m.addSet(25, 20) != null);
  t('الشوط الثالث يقبل 15-13', m.addSet(15, 13) == null);
  t('انتهت المباراة والفائز أ', m.finished && m.winner == a);
  t('لا أشواط بعد النهاية', m.addSet(25, 0) != null);

  StandRow row(List<StandRow> s, Team x) => s.firstWhere((e) => e.team == x);
  var s = standings([a, b], [_mk(a, b, 5, [[25, 10], [25, 10], [25, 10]])]);
  t('3-0 ← الفائز 3 والخاسر 0', row(s, a).pts == 3 && row(s, b).pts == 0);
  s = standings([a, b], [_mk(a, b, 5, [[25, 10], [10, 25], [25, 10], [25, 10]])]);
  t('3-1 ← الفائز 3 والخاسر 0', row(s, a).pts == 3 && row(s, b).pts == 0);
  s = standings([a, b], [_mk(a, b, 5, [[25, 10], [10, 25], [25, 10], [10, 25], [15, 10]])]);
  t('3-2 ← الفائز 2 والخاسر 1', row(s, a).pts == 2 && row(s, b).pts == 1);
  s = standings([b, a, c, d], [_mk(a, c, 5, [[25, 10], [25, 10], [25, 10]]), _mk(b, d, 5, [[25, 10], [10, 25], [25, 10], [25, 10]])]);
  t('تعادل نقاط ومباريات ← نسبة الأشواط تحسم (أ قبل ب)', s[0].team == a && s[1].team == b);

  final seeds = List.generate(8, (i) => Team('s$i', 'ف$i'));
  final br = buildBracket(seeds);
  br[0][0].match = _mk(seeds[0], seeds[7], 3, [[25, 10], [25, 10]]);
  br[0][1].match = _mk(seeds[3], seeds[4], 3, [[10, 25], [10, 25]]);
  advance(br);
  t('تصعيد: فائز 1×8 إلى نصف النهائي (خانة أ)', br[1][0].a == seeds[0]);
  t('تصعيد: فائز 4×5 إلى نصف النهائي (خانة ب)', br[1][0].b == seeds[4]);
  return r;
}

// ======================= الحالة (تجريبية في الذاكرة) =======================
class Store extends ChangeNotifier {
  final teams = List.generate(8, (i) => Team('t$i', 'الفريق ${i + 1}'));
  final group = <VMatch>[];
  late List<List<Tie>> bracket = buildBracket(teams);
  final accounts = <String, List<String>>{'fan:0770': ['123456', 'fan'], 'staff:مدير': ['123456', 'staff']};
  String? role; // fan | staff
  bool adminUnlocked = false;

  Store() {
    group.add(_mk(teams[0], teams[1], 5, [[25, 20], [25, 22], [25, 18]]));
    group.add(_mk(teams[2], teams[3], 5, [[25, 20], [20, 25], [25, 23], [22, 25], [15, 12]]));
    group.add(VMatch(teams[0], teams[2], bestOf: 5));
    bracket[0][0].match = VMatch(teams[0], teams[7], bestOf: 3);
    advance(bracket);
  }

  String? login(String id, String pass, bool staff) {
    final acc = accounts['${staff ? 'staff' : 'fan'}:$id'];
    if (acc == null || acc[0] != pass) return 'بيانات الدخول غير صحيحة';
    role = acc[1];
    adminUnlocked = false;
    notifyListeners();
    return null;
  }

  String? register(String id, String pass, bool staff) {
    if (pass.length < 6) return 'كلمة السر 6 أحرف على الأقل';
    final k = '${staff ? 'staff' : 'fan'}:$id';
    if (accounts.containsKey(k)) return 'الحساب مسجل مسبقاً';
    accounts[k] = [pass, staff ? 'staff' : 'fan'];
    return login(id, pass, staff);
  }

  void logout() { role = null; adminUnlocked = false; notifyListeners(); }
  void refresh() { advance(bracket); notifyListeners(); }
}

final store = Store();

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'بطولة شهداء العراق للكرة الطائرة',
          theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8590C))),
          builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          home: store.role == null ? const LoginPage() : const HomePage(),
        ),
      );
}

// ======================= شاشة تسجيل الدخول =======================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final id = TextEditingController(), pass = TextEditingController();
  bool staff = false, register = false;

  void _go() {
    final err = register ? store.register(id.text.trim(), pass.text, staff) : store.login(id.text.trim(), pass.text, staff);
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
                const Icon(Icons.sports_volleyball, size: 72, color: Color(0xFFE8590C)),
                const Text('بطولة شهداء العراق\nللكرة الطائرة', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                SegmentedButton<bool>(
                  segments: const [ButtonSegment(value: false, label: Text('مشجع / لاعب')), ButtonSegment(value: true, label: Text('مسؤول'))],
                  selected: {staff},
                  onSelectionChanged: (s) => setState(() => staff = s.first),
                ),
                const SizedBox(height: 12),
                TextField(controller: id, decoration: InputDecoration(labelText: staff ? 'الاسم' : 'رقم الواتساب', border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: pass, obscureText: true, onSubmitted: (_) => _go(), decoration: const InputDecoration(labelText: 'كلمة السر', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                FilledButton(onPressed: _go, child: Padding(padding: const EdgeInsets.all(12), child: Text(register ? 'إنشاء حساب' : 'دخول'))),
                TextButton(onPressed: () => setState(() => register = !register), child: Text(register ? 'لدي حساب' : 'حساب جديد')),
                const Text('تجربة: مشجع 0770 / 123456 — مسؤول مدير / 123456', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ),
      );
}

// ======================= الشاشة الرئيسية =======================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    final staff = store.role == 'staff';
    if (i >= (staff ? 3 : 2)) i = 0;
    return Scaffold(
      appBar: AppBar(title: const Text('شهداء العراق - كرة طائرة'), actions: [IconButton(icon: const Icon(Icons.logout), onPressed: store.logout)]),
      body: ListenableBuilder(
        listenable: store,
        builder: (_, __) => <Widget>[_Standings(), _Bracket(), if (staff) _Admin()][i],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.leaderboard), label: 'الترتيب'),
          const NavigationDestination(icon: Icon(Icons.account_tree), label: 'التصفيات'),
          if (staff) const NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: 'الإدارة'),
        ],
      ),
    );
  }
}

class _Standings extends StatelessWidget {
  const _Standings();
  @override
  Widget build(BuildContext context) {
    final rows = standings(store.teams, store.group);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const ['#', 'الفريق', 'لعب', 'فوز', 'نقاط', 'أشواط', 'نسبة'].map((e) => DataColumn(label: Text(e))).toList(),
        rows: [
          for (var k = 0; k < rows.length; k++)
            DataRow(cells: [
              DataCell(Text('${k + 1}')), DataCell(Text(rows[k].team.name)), DataCell(Text('${rows[k].played}')),
              DataCell(Text('${rows[k].wins}')), DataCell(Text('${rows[k].pts}', style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text('${rows[k].sw}-${rows[k].sl}')), DataCell(Text(rows[k].pointRatio.toStringAsFixed(2))),
            ])
        ],
      ),
    );
  }
}

class _Bracket extends StatelessWidget {
  const _Bracket();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        for (var r = 0; r < store.bracket.length; r++) ...[
          Text(roundName(r, store.bracket.length), style: Theme.of(context).textTheme.titleLarge),
          for (final t in store.bracket[r])
            Card(
              child: ListTile(
                title: Text('${t.a?.name ?? '؟'}  ضد  ${t.b?.name ?? '؟'}'),
                subtitle: Text(t.match == null ? 'لم تبدأ' : 'الأشواط ${t.match!.setsA} - ${t.match!.setsB}'),
                trailing: t.winner == null ? null : const Icon(Icons.emoji_events, color: Colors.amber),
              ),
            ),
        ]
      ]);
}

// ======================= لوحة الإدارة (محمية بالرمز) =======================
class _Admin extends StatefulWidget {
  const _Admin();
  @override
  State<_Admin> createState() => _AdminState();
}

class _AdminState extends State<_Admin> {
  final code = TextEditingController();
  List<T>? results;

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    if (!store.adminUnlocked) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock, size: 48),
          TextField(controller: code, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رمز الدخول السري')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              if (code.text.trim() == '20072026') { store.adminUnlocked = true; store.refresh(); } else { _toast('الرمز غير صحيح'); }
            },
            child: const Text('دخول'),
          ),
        ]),
      );
    }
    final ms = <VMatch>[...store.group, for (final r in store.bracket) for (final t in r) if (t.match != null) t.match!];
    return ListView(padding: const EdgeInsets.all(12), children: [
      FilledButton.icon(onPressed: () => setState(() => results = runSelfTests()), icon: const Icon(Icons.fact_check), label: const Text('تشغيل فحص قواعد الكرة الطائرة')),
      if (results != null) ...[
        Padding(padding: const EdgeInsets.all(8), child: Text('${results!.where((e) => e.ok).length} / ${results!.length} نجح', style: const TextStyle(fontWeight: FontWeight.bold))),
        for (final x in results!) ListTile(dense: true, leading: Icon(x.ok ? Icons.check_circle : Icons.cancel, color: x.ok ? Colors.green : Colors.red), title: Text(x.name)),
      ],
      const Divider(),
      for (final m in ms)
        Card(
          child: ListTile(
            title: Text('${m.a.name} × ${m.b.name}  (best of ${m.bestOf})'),
            subtitle: Text(m.sets.map((s) => '${s.a}-${s.b}').join('  |  ') + (m.finished ? '  ✔' : '')),
            trailing: m.finished ? null : IconButton(icon: const Icon(Icons.add_circle), onPressed: () => _addSet(m)),
          ),
        ),
    ]);
  }

  Future<void> _addSet(VMatch m) async {
    final a = TextEditingController(), b = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('نتيجة الشوط ${m.sets.length + 1}${m.sets.length == m.bestOf - 1 ? " (فاصل)" : ""}'),
        content: Row(children: [
          Expanded(child: TextField(controller: a, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: m.a.name))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: b, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: m.b.name))),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              final err = m.addSet(int.tryParse(a.text) ?? -1, int.tryParse(b.text) ?? -1);
              Navigator.pop(ctx);
              if (err != null) { _toast(err); } else { store.refresh(); }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
