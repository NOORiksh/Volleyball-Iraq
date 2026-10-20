import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'services.dart';

class ChatPage extends StatefulWidget {
  final Session session;
  const ChatPage({super.key, required this.session});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ctrl = TextEditingController();
  String myName = '';

  @override
  void initState() {
    super.initState();
    Repo.profile(widget.session.uid).first.then((d) => myName = d.data()?['name'] ?? '');
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _send() async {
    final t = ctrl.text.trim();
    if (t.isEmpty) return;
    ctrl.clear();
    try {
      await Repo.send(myName, t);
    } on FirebaseException catch (e) {
      _toast(e.code == 'permission-denied' ? 'أنت محظور من الشات أو الرسالة غير مقبولة' : 'تعذر الإرسال');
    }
  }

  void _menu(String id, String uid, String name) {
    final s = widget.session;
    if (!s.canChat) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.delete), title: const Text('حذف الرسالة'),
              onTap: () { Navigator.pop(context); Repo.deleteMessage(id); }),
          if (uid != s.uid) ListTile(leading: const Icon(Icons.block), title: Text('حظر $name'),
              onTap: () { Navigator.pop(context); Repo.ban(uid, name); _toast('تم الحظر'); }),
          if (s.isSuper && uid != s.uid) ListTile(leading: const Icon(Icons.shield), title: const Text('ترقية إلى مشرف'),
              onTap: () async { Navigator.pop(context); await Auth.setRole(uid, 'admin'); _toast('تمت الترقية (تسري عند إعادة دخوله)'); }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Repo.chat(),
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final docs = s.data!.docs;
              return ListView.builder(
                reverse: true,
                itemCount: docs.length,
                itemBuilder: (c, k) {
                  final d = docs[k].data();
                  final mine = d['uid'] == widget.session.uid;
                  return GestureDetector(
                    onLongPress: () => _menu(docs[k].id, d['uid'], d['name'] ?? ''),
                    child: Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Card(
                        color: mine ? Theme.of(context).colorScheme.primaryContainer : null,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(d['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            Text(d['text'] ?? ''),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: TextField(controller: ctrl, maxLength: 500, onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'اكتب رسالة...', counterText: '', border: OutlineInputBorder()))),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]);
}
