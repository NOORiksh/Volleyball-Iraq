import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'admin_page.dart';
import 'chat_page.dart';
import 'firebase_options.dart'; // يُولَّد بالأمر: flutterfire configure
import 'home_tab.dart';
import 'logic.dart';
import 'news_page.dart';
import 'quiz_page.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const VolleyApp());
}

class VolleyApp extends StatelessWidget {
  const VolleyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'بطولة شهداء العراق للكرة الطائرة',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8590C))),
        home: StreamBuilder<Session?>(
          stream: Auth.session,
          builder: (c, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return s.data == null ? const LoginPage() : HomePage(session: s.data!);
          },
        ),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController(), phone = TextEditingController(), pass = TextEditingController();
  bool staff = false, register = false, busy = false;
  String duty = 'مسؤول';

  Future<void> _submit() async {
    setState(() => busy = true);
    try {
      if (register) {
        if (staff && duty == 'مسؤول') {
          await Auth.registerStaff(name.text.trim(), pass.text); // بكلمة سر المهمة
        } else {
          await Auth.register(name: name.text.trim(), pass: pass.text, phone: staff ? null : phone.text.trim(), duty: staff ? duty : null);
        }
      } else {
        await Auth.login(staff ? name.text : phone.text, pass.text, staff: staff);
      }
    } on FirebaseAuthException catch (e) {
      final msg = {
        'email-already-in-use': 'الحساب مسجل مسبقاً',
        'weak-password': 'كلمة السر ضعيفة (6 أحرف على الأقل)',
        'invalid-credential': 'بيانات الدخول غير صحيحة',
      }[e.code] ?? (e.message ?? 'خطأ');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on AuthMsg catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.m)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.sports_volleyball, size: 72, color: Color(0xFFE8590C)),
            const Text('بطولة شهداء العراق\nللكرة الطائرة', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('مشجع / لاعب')), ButtonSegment(value: true, label: Text('مسؤول'))],
              selected: {staff},
              onSelectionChanged: (s) => setState(() => staff = s.first),
            ),
            const SizedBox(height: 12),
            if (register || staff) _f(name, 'الاسم'),
            if (!staff) _f(phone, 'رقم الواتساب', type: TextInputType.phone),
            if (staff && register)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  value: duty,
                  items: const ['مسؤول', 'مدير المسؤولين'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => duty = v!),
                  decoration: const InputDecoration(labelText: 'المهمة', border: OutlineInputBorder()),
                ),
              ),
            _f(pass, staff && register && duty == 'مسؤول' ? 'كلمة سر المهمة (من مدير المسؤولين)' : 'كلمة السر', obscure: true),
            if (staff && register)
              Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Text(duty == 'مسؤول'
                      ? 'اكتب كلمة سر المهمة التي أعطاك إياها مدير المسؤولين؛ تحدد صلاحياتك تلقائياً.'
                      : 'بعد الدخول افتح تبويب الإدارة وأدخل الرمز السري.', style: const TextStyle(fontSize: 12))),
            FilledButton(onPressed: busy ? null : _submit, child: Padding(padding: const EdgeInsets.all(12), child: Text(register ? 'إنشاء حساب' : 'دخول'))),
            TextButton(onPressed: () => setState(() => register = !register), child: Text(register ? 'لدي حساب' : 'حساب جديد')),
          ]),
        ),
      );

  Widget _f(TextEditingController c, String l, {bool obscure = false, TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, obscureText: obscure, keyboardType: type,
            decoration: InputDecoration(labelText: l, border: const OutlineInputBorder())),
      );
}

class HomePage extends StatefulWidget {
  final Session session;
  const HomePage({super.key, required this.session});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int i = 0;
  @override
  void initState() {
    super.initState();
    Notifier.init(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Repo.userDoc(s.uid),
      builder: (c, u) {
        final showAdmin = s.isStaff || (u.data?.data()?['requestedDuty'] != null);
        final pages = <Widget>[const HomeTab(), const TournamentTab(), QuizPage(), ChatPage(session: s), if (showAdmin) AdminPage(session: s)];
        if (i >= pages.length) i = 0;
        return Scaffold(
          appBar: AppBar(
            title: const Text('شهداء العراق - كرة طائرة'),
            actions: [
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: Repo.profile(s.uid),
                builder: (c, p) {
                  final d = p.data?.data();
                  return Row(children: [
                    Chip(avatar: const Icon(Icons.monetization_on, size: 18), label: Text('${d?['coins'] ?? 0}')),
                    const SizedBox(width: 6),
                    Chip(label: Text('م${((d?['xp'] ?? 0) as int) ~/ 100 + 1}')),
                  ]);
                },
              ),
              BellButton(session: s),
              IconButton(icon: const Icon(Icons.logout), onPressed: Auth.logout),
            ],
          ),
          body: pages[i],
          bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: (v) => setState(() => i = v),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home), label: 'الرئيسية'),
              const NavigationDestination(icon: Icon(Icons.leaderboard), label: 'البطولة'),
              const NavigationDestination(icon: Icon(Icons.quiz), label: 'اختبر نفسك'),
              const NavigationDestination(icon: Icon(Icons.chat), label: 'الشات'),
              if (showAdmin) const NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: 'الإدارة'),
            ],
          ),
        );
      },
    );
  }
}

class StandingsPage extends StatelessWidget {
  const StandingsPage({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<Tournament>(
        stream: Repo.tournament(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final rows = standings(s.data!.teams, s.data!.group);
          if (rows.isEmpty) return const Center(child: Text('لا توجد فرق بعد'));
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const ['#', 'الفريق', 'لعب', 'فوز', 'نقاط', 'أشواط', 'نسبة'].map((e) => DataColumn(label: Text(e))).toList(),
              rows: [
                for (var k = 0; k < rows.length; k++)
                  DataRow(cells: [
                    DataCell(Text('${k + 1}')), DataCell(Text(rows[k].team.name)),
                    DataCell(Text('${rows[k].played}')), DataCell(Text('${rows[k].wins}')),
                    DataCell(Text('${rows[k].pts}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('${rows[k].sw}-${rows[k].sl}')), DataCell(Text(rows[k].pointRatio.toStringAsFixed(2))),
                  ])
              ],
            ),
          );
        },
      );
}

class BracketPage extends StatelessWidget {
  const BracketPage({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<Tournament>(
        stream: Repo.tournament(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final br = s.data!.bracket;
          if (br == null) return const Center(child: Text('تحتاج الشجرة 8 فرق على الأقل'));
          return ListView(padding: const EdgeInsets.all(12), children: [
            for (var r = 0; r < br.length; r++) ...[
              Text(roundName(r, br.length), style: Theme.of(context).textTheme.titleLarge),
              for (final t in br[r])
                Card(
                  child: ListTile(
                    title: Text('${t.a?.name ?? '؟'}  ضد  ${t.b?.name ?? '؟'}'),
                    subtitle: Text(t.match == null ? 'لم تبدأ' : 'الأشواط ${t.match!.setsA} - ${t.match!.setsB}'),
                    trailing: t.winner == null ? null : const Icon(Icons.emoji_events, color: Colors.amber),
                  ),
                ),
            ]
          ]);
        },
      );
}

class TournamentTab extends StatelessWidget {
  const TournamentTab({super.key});
  @override
  Widget build(BuildContext context) => const DefaultTabController(
        length: 2,
        child: Column(children: [
          TabBar(tabs: [Tab(text: 'الترتيب'), Tab(text: 'التصفيات')]),
          Expanded(child: TabBarView(children: [StandingsPage(), BracketPage()])),
        ]),
      );
}
