import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'services.dart';

class QuizPage extends StatelessWidget {
  QuizPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [Tab(text: 'الأسئلة'), Tab(text: 'المتصدرون')]),
          Expanded(child: TabBarView(children: [const _Questions(), _Board()])),
        ]),
      );
}

class _Questions extends StatefulWidget {
  const _Questions();
  @override
  State<_Questions> createState() => _QuestionsState();
}

class _QuestionsState extends State<_Questions> {
  int q = 0;
  int? picked, correct;
  String note = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Repo.questions(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          docs ??= (s.data!.docs.toList()..shuffle());
          if (docs!.isEmpty) return const Center(child: Text('لا توجد أسئلة بعد'));
          final d = docs![q % docs!.length];
          final opts = List<String>.from(d['options']);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(d['text'], style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var k = 0; k < opts.length; k++)
              Card(
                color: picked == null ? null : k == correct ? Colors.green.shade100 : (k == picked ? Colors.red.shade100 : null),
                child: ListTile(
                  title: Text(opts[k]),
                  onTap: picked != null ? null : () async {
                    setState(() => picked = k);
                    final r = await Repo.submitAnswer(d.id, k); // التصحيح والمكافأة على الخادم
                    setState(() {
                      correct = r['correctIndex'];
                      note = r['correct'] ? (r['coins'] > 0 ? 'أحسنت! +${r['coins']} عملة و +${r['xp']} خبرة' : 'صحيح (سبق أن كسبت نقاط هذا السؤال)') : 'إجابة خاطئة';
                    });
                  },
                ),
              ),
            if (correct != null) ...[
              Text(note),
              if ((d.data()['explanation'] ?? '') != '') Text(d['explanation'], style: const TextStyle(fontSize: 12)),
              FilledButton(onPressed: () => setState(() { q++; picked = null; correct = null; }), child: const Text('السؤال التالي')),
            ]
          ]);
        },
      );
}

class _Board extends StatelessWidget {
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Repo.leaderboard(),
        builder: (c, s) => !s.hasData
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                for (var k = 0; k < s.data!.docs.length; k++)
                  ListTile(
                    leading: CircleAvatar(child: Text('${k + 1}')),
                    title: Text(s.data!.docs[k]['name'] ?? ''),
                    trailing: Text('${s.data!.docs[k]['xp']} XP · ${s.data!.docs[k]['coins']} 🪙'),
                  ),
              ]),
      );
}
