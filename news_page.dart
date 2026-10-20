import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services.dart';
import 'widgets.dart';

String _fmt(dynamic t) {
  if (t is! Timestamp) return '...';
  final d = t.toDate();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
}

/// طلب إذن الإشعارات (أندرويد 13+) والاشتراك في موضوع "all" + عرض الإشعار أثناء فتح التطبيق
class Notifier {
  static bool _done = false;
  static Future<void> init(BuildContext context) async {
    if (_done) return;
    _done = true;
    final m = FirebaseMessaging.instance;
    await m.requestPermission();
    await m.subscribeToTopic('all');
    FirebaseMessaging.onMessage.listen((msg) {
      final n = msg.notification;
      if (n == null || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${n.title ?? ''}\n${n.body ?? ''}'),
        duration: const Duration(seconds: 5),
      ));
    });
  }
}

/// جرس في الشريط العلوي مع عدّاد غير المقروء (آخر وقت اطلاع محفوظ محلياً)
class BellButton extends StatefulWidget {
  final Session session;
  const BellButton({super.key, required this.session});
  @override
  State<BellButton> createState() => _BellButtonState();
}

class _BellButtonState extends State<BellButton> {
  int lastSeen = 0;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) => setState(() => lastSeen = p.getInt('notifSeen') ?? 0));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Repo.notifications(),
        builder: (c, s) {
          final unread = (s.data?.docs ?? []).where((d) {
            final t = d.data()['at'];
            return t is! Timestamp || t.millisecondsSinceEpoch > lastSeen; // at=null => للتو
          }).length;
          return IconButton(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications)),
            onPressed: () async {
              final now = DateTime.now().millisecondsSinceEpoch;
              (await SharedPreferences.getInstance()).setInt('notifSeen', now);
              setState(() => lastSeen = now);
              if (context.mounted) {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => NewsPage(session: widget.session)));
              }
            },
          );
        },
      );
}

class NewsPage extends StatelessWidget {
  final Session session;
  const NewsPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(title: const Text('الأخبار والإشعارات'),
              bottom: const TabBar(tabs: [Tab(text: 'الأخبار'), Tab(text: 'الإشعارات')])),
          floatingActionButton: session.canNews
              ? FloatingActionButton.extended(onPressed: () => _compose(context, null), icon: const Icon(Icons.add), label: const Text('خبر جديد'))
              : null,
          body: TabBarView(children: [_news(context), _notifs()]),
        ),
      );

  Widget _news(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Repo.news(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs.toList()
            ..sort((a, b) => (b.data()['pinned'] == true ? 1 : 0) - (a.data()['pinned'] == true ? 1 : 0));
          if (docs.isEmpty) return const Center(child: Text('لا توجد أخبار بعد'));
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
            for (final d in docs)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ('${d.data()['image'] ?? ''}'.isNotEmpty)
                    Image.network('${d.data()['image']}', height: 170, width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  ListTile(
                    isThreeLine: true,
                    leading: Icon(d.data()['pinned'] == true ? Icons.push_pin : Icons.article),
                    title: Text(d.data()['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${d.data()['body'] ?? ''}\n${_fmt(d.data()['at'])}'),
                    trailing: session.canNews
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.edit), onPressed: () => _compose(context, d)),
                            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => Repo.deleteNews(d.id)),
                          ])
                        : null,
                  ),
                ]),
              ),
          ]);
        },
      );

  Widget _notifs() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Repo.notifications(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.docs.isEmpty) return const Center(child: Text('لا توجد إشعارات'));
          return ListView(children: [
            for (final d in s.data!.docs)
              ListTile(
                leading: Icon(d.data()['type'] == 'result' ? Icons.sports_volleyball : Icons.campaign),
                title: Text(d.data()['title'] ?? ''),
                subtitle: Text('${d.data()['body'] ?? ''}\n${_fmt(d.data()['at'])}'),
                isThreeLine: true,
              ),
          ]);
        },
      );

  /// نشر خبر جديد (يصل كإشعار) أو تعديل خبر موجود (بدون إشعار جديد)
  Future<void> _compose(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>>? d) async {
    final x = d?.data() ?? <String, dynamic>{};
    final t = TextEditingController(text: '${x['title'] ?? ''}'), b = TextEditingController(text: '${x['body'] ?? ''}');
    bool pin = x['pinned'] == true;
    String img = '${x['image'] ?? ''}';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(d == null ? 'نشر خبر (يصل كإشعار للجميع)' : 'تعديل الخبر'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: t, maxLength: 80, decoration: const InputDecoration(labelText: 'العنوان')),
              TextField(controller: b, maxLines: 4, maxLength: 800, decoration: const InputDecoration(labelText: 'النص')),
              SwitchListTile(value: pin, onChanged: (v) => set(() => pin = v), title: const Text('تثبيت في الأعلى')),
              ImageField(label: 'صورة الخبر (اختياري)', folder: 'news', url: img, onChanged: (u) => set(() => img = u)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                if (t.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await Cms.saveNews(d?.id, t.text.trim(), b.text.trim(), pin, img);
              },
              child: Text(d == null ? 'نشر' : 'حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
