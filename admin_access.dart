import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services.dart';

const _tasks = {
  'admin': 'مسؤول (البطولة + الأخبار + الأسئلة + الشات)',
  'moderator': 'مشرف شات (حذف الرسائل والحظر)',
  'scorer': 'مسجّل نتائج (الفرق والمباريات)',
  'editor': 'محرر أخبار',
};

String _gen() {
  const a = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(10, (_) => a[r.nextInt(a.length)]).join();
}

// ======================= كلمات سر المهام =======================
class PasswordsAdmin extends StatelessWidget {
  const PasswordsAdmin({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('كلمات سر المهام')),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _create(context), icon: const Icon(Icons.add), label: const Text('باسورد جديد')),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('أنشئ باسوردًا لكل مهمة وسلّمه لصاحبها. يسجّل من شاشة الدخول: مسؤول ← حساب جديد ← الاسم + هذا الباسورد، '
                  'فتُمنح له صلاحيات مهمته تلقائياً. الباسورد لا يظهر بعد إنشائه (يُحفظ مشفّراً)، فاحتفظ به.'),
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Cms.rolePasswords(),
            builder: (c, s) {
              final docs = s.data?.docs ?? [];
              if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد كلمات سر بعد')));
              return Column(children: [
                for (final d in docs)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.vpn_key),
                      title: Text('${d.data()['label'] ?? ''}'),
                      subtitle: Text('${roleNames['${d.data()['role']}'] ?? d.data()['role']} · سُجّل بها ${d.data()['uses'] ?? 0}'),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, d.id)),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      );

  Future<void> _create(BuildContext context) async {
    final label = TextEditingController(), pw = TextEditingController(text: _gen());
    String role = 'moderator';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('باسورد مهمة جديد'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: label, maxLength: 40, decoration: const InputDecoration(labelText: 'اسم المهمة (مثال: مشرف الشات)')),
              DropdownButtonFormField<String>(
                isExpanded: true, value: role,
                items: _tasks.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => set(() => role = v!),
                decoration: const InputDecoration(labelText: 'الصلاحيات'),
              ),
              TextField(
                controller: pw,
                decoration: InputDecoration(labelText: 'الباسورد (8 أحرف على الأقل)', suffixIcon: IconButton(icon: const Icon(Icons.casino), onPressed: () => set(() => pw.text = _gen()))),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final err = await Cms.createRolePassword(role, label.text.trim(), pw.text.trim());
                if (!context.mounted) return;
                if (err != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  return;
                }
                await Clipboard.setData(ClipboardData(text: pw.text.trim()));
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الإنشاء ونُسخ الباسورد — سلّمه لصاحب المهمة')));
              },
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, String id) async {
    bool revoke = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('حذف الباسورد؟'),
          content: CheckboxListTile(value: revoke, onChanged: (v) => set(() => revoke = v ?? true), title: const Text('سحب الصلاحية من كل من سجّل بهذا الباسورد')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (ok == true) await Cms.deleteRolePassword(id, revoke);
  }
}

// ======================= الحسابات والصلاحيات =======================
class StaffAdmin extends StatelessWidget {
  const StaffAdmin({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الحسابات والصلاحيات')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: Cms.staffAccounts(),
          builder: (c, s) {
            final docs = s.data?.docs ?? [];
            if (docs.isEmpty) return const Center(child: Text('لا يوجد أصحاب مهام بعد'));
            return ListView(children: [
              for (final d in docs)
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text('${d.data()['name'] ?? ''}'),
                  subtitle: Text('${d.data()['label'] ?? ''} · ${roleNames['${d.data()['role']}'] ?? d.data()['role']}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      await Auth.setRole(d.id, v);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التحديث (يسري عند إعادة دخوله)')));
                    },
                    itemBuilder: (_) => [
                      for (final e in _tasks.keys) PopupMenuItem(value: e, child: Text('تحويل إلى: ${roleNames[e]}')),
                      const PopupMenuItem(value: 'fan', child: Text('سحب الصلاحية (مشجع)')),
                    ],
                  ),
                ),
            ]);
          },
        ),
      );
}
