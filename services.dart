import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'logic.dart';

final _auth = FirebaseAuth.instance;
final _db = FirebaseFirestore.instance;
final _fn = FirebaseFunctions.instance;

const roleNames = {
  'superadmin': 'مدير المسؤولين', 'admin': 'مسؤول', 'moderator': 'مشرف الشات',
  'scorer': 'مسجّل نتائج', 'editor': 'محرر أخبار', 'fan': 'مشجع / لاعب',
};

class AuthMsg implements Exception {
  final String m;
  AuthMsg(this.m);
}

class Session {
  final String uid, role;
  const Session(this.uid, this.role);
  bool get isSuper => role == 'superadmin';
  bool get isStaff => role != 'fan';
  bool get canTournament => const ['superadmin', 'admin', 'scorer'].contains(role); // الفرق والمباريات
  bool get canNews => const ['superadmin', 'admin', 'editor'].contains(role);
  bool get canChat => const ['superadmin', 'admin', 'moderator'].contains(role);
  bool get canQuestions => const ['superadmin', 'admin'].contains(role);
}

class Tournament {
  final List<Team> teams;
  final List<VMatch> all, group;
  final List<List<Tie>>? bracket; // null إذا الفرق أقل من 8
  Tournament(this.teams, this.all, this.group, this.bracket);
}

class Auth {
  // Firebase يحتاج بريداً فريداً: نشتقه من رقم الواتساب (مشجع) أو اسم المسؤول
  static String _email(String id) =>
      '${sha1.convert(utf8.encode(id.trim().toLowerCase()))}@volley.app';

  static Stream<Session?> get session => _auth.idTokenChanges().asyncMap((u) async {
        if (u == null) return null;
        final t = await u.getIdTokenResult();
        return Session(u.uid, (t.claims?['role'] as String?) ?? 'fan');
      });

  static Future<void> login(String id, String pass, {required bool staff}) =>
      _auth.signInWithEmailAndPassword(email: _email(staff ? 'staff:${id.trim()}' : id.trim()), password: pass);

  static Future<void> register({required String name, required String pass, String? phone, String? duty}) async {
    final staff = duty != null;
    final c = await _auth.createUserWithEmailAndPassword(
        email: _email(staff ? 'staff:$name' : phone!), password: pass);
    final uid = c.user!.uid;
    await _db.doc('profiles/$uid').set(
        {'name': name, 'coins': 0, 'xp': 0, 'createdAt': FieldValue.serverTimestamp()});
    await _db.doc('users/$uid').set(staff ? {'requestedDuty': duty} : {'whatsapp': phone});
  }

  static Future<void> logout() => _auth.signOut();

  /// صاحب مهمة: الاسم + كلمة سر المهمة التي أنشأها المدير. الخادم يتحقق وينشئ الحساب.
  static Future<void> registerStaff(String name, String pass) async {
    try {
      await _fn.httpsCallable('registerStaff').call({'name': name, 'password': pass});
    } on FirebaseFunctionsException catch (e) {
      throw AuthMsg(e.message ?? 'تعذر التسجيل');
    }
    await login(name, pass, staff: true);
  }

  /// يتحقق الخادم من الرمز ثم يمنح الصلاحية. يرجع نص الخطأ أو null
  static Future<String?> unlockAdmin(String code) async {
    try {
      await _fn.httpsCallable('redeemAdminCode').call({'code': code});
      await _auth.currentUser!.getIdToken(true); // لتحديث الـ claims
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'حدث خطأ';
    }
  }

  static Future<void> setRole(String uid, String role) =>
      _fn.httpsCallable('setRole').call({'uid': uid, 'role': role});
}

class Repo {
  static String get uid => _auth.currentUser!.uid;
  static Stream<DocumentSnapshot<Map<String, dynamic>>> profile(String uid) => _db.doc('profiles/$uid').snapshots();
  static Stream<DocumentSnapshot<Map<String, dynamic>>> userDoc(String uid) => _db.doc('users/$uid').snapshots();

  // ---------- البطولة ----------
  static Stream<Tournament> tournament() => _db.collection('matches').snapshots().asyncMap((ms) async {
        final ts = await _db.collection('teams').orderBy('seed').get();
        final teams = ts.docs.map((d) => Team(d.id, d['name'])).toList();
        final byId = {for (final t in teams) t.id: t};
        final all = <VMatch>[];
        for (final d in ms.docs) {
          final x = d.data();
          final a = byId[x['teamA']], b = byId[x['teamB']];
          if (a == null || b == null) continue;
          final m = VMatch(a, b, bestOf: x['bestOf'] ?? 3, stage: x['stage'] ?? 'group', slot: x['slot'] ?? 0, id: d.id);
          for (final s in (x['sets'] as List? ?? [])) { m.sets.add(SetScore(s['a'], s['b'])); }
          all.add(m);
        }
        List<List<Tie>>? br;
        if (teams.length >= 8) {
          br = buildBracket(teams.take(8).toList());
          const stages = ['qf', 'sf', 'final'];
          for (final m in all.where((m) => stages.contains(m.stage))) {
            final r = stages.indexOf(m.stage);
            if (m.slot < br[r].length) br[r][m.slot].match = m;
          }
          advance(br); // تصعيد تلقائي للفائز
        }
        return Tournament(teams, all, all.where((m) => m.stage == 'group').toList(), br);
      });

  static Future<void> addTeam(String name, int seed) => _db.collection('teams').add({'name': name, 'seed': seed});
  static Future<void> createMatch(Team a, Team b, int bestOf, String stage, int slot) =>
      _db.collection('matches').add({'teamA': a.id, 'teamB': b.id, 'bestOf': bestOf, 'stage': stage, 'slot': slot, 'sets': []});
  static Future<void> deleteMatch(String id) => _db.doc('matches/$id').delete();

  /// يتحقق من القوانين محلياً ثم يكتب المصفوفة كاملة (arrayUnion يحذف الأشواط المتطابقة!)
  static Future<String?> addSet(VMatch m, int a, int b) async {
    final err = m.addSet(a, b);
    if (err != null) return err;
    await _db.doc('matches/${m.id}').update({'sets': m.sets.map((s) => {'a': s.a, 'b': s.b}).toList()});
    return null;
  }

  // ---------- الشات والإشراف ----------
  static Stream<QuerySnapshot<Map<String, dynamic>>> chat() =>
      _db.collection('messages').orderBy('at', descending: true).limit(100).snapshots();

  static Future<void> send(String name, String text) => _db.collection('messages').add(
      {'uid': uid, 'name': name, 'text': text, 'at': FieldValue.serverTimestamp()});
  static Future<void> deleteMessage(String id) => _db.doc('messages/$id').delete();
  static Future<void> ban(String uid, String name) =>
      _db.doc('bans/$uid').set({'name': name, 'by': Repo.uid, 'at': FieldValue.serverTimestamp()});
  static Future<void> unban(String uid) => _db.doc('bans/$uid').delete();
  static Stream<QuerySnapshot<Map<String, dynamic>>> bans() => _db.collection('bans').snapshots();

  // ---------- الأخبار والإشعارات ----------
  static Stream<QuerySnapshot<Map<String, dynamic>>> news() =>
      _db.collection('news').orderBy('at', descending: true).limit(50).snapshots();
  static Future<void> addNews(String title, String body, bool pinned) => _db.collection('news').add(
      {'title': title, 'body': body, 'pinned': pinned, 'by': uid, 'at': FieldValue.serverTimestamp()});
  static Future<void> deleteNews(String id) => _db.doc('news/$id').delete();
  static Stream<QuerySnapshot<Map<String, dynamic>>> notifications() =>
      _db.collection('notifications').orderBy('at', descending: true).limit(50).snapshots();

  // ---------- الاختبار ----------
  static Stream<QuerySnapshot<Map<String, dynamic>>> questions() => _db.collection('questions').snapshots();
  static Stream<QuerySnapshot<Map<String, dynamic>>> leaderboard() =>
      _db.collection('profiles').orderBy('xp', descending: true).limit(20).snapshots();
  static Future<Map<String, dynamic>> submitAnswer(String qid, int choice) async {
    final r = await _fn.httpsCallable('submitAnswer').call({'questionId': qid, 'choice': choice});
    return Map<String, dynamic>.from(r.data);
  }
}


/// كل ما يخص إدارة المحتوى (للمدير وللأدوار حسب القواعد)
class Cms {
  // ---- نصوص وصور الصفحة الرئيسية ----
  static Stream<DocumentSnapshot<Map<String, dynamic>>> site() => _db.doc('settings/site').snapshots();
  static Future<void> saveSite(Map<String, dynamic> d) => _db.doc('settings/site').set(d, SetOptions(merge: true));

  // ---- رفع الصور إلى Firebase Storage ----
  static Future<String> uploadImage(String folder, Uint8List bytes, String ext) async {
    final ref = FirebaseStorage.instance.ref('$folder/${DateTime.now().millisecondsSinceEpoch}.$ext');
    await ref.putData(bytes, SettableMetadata(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'));
    return ref.getDownloadURL();
  }

  // ---- الرعاة ----
  static Stream<QuerySnapshot<Map<String, dynamic>>> sponsors() => _db.collection('sponsors').orderBy('order').snapshots();
  static Future<void> saveSponsor(String? id, Map<String, dynamic> d) async {
    if (id == null) {
      await _db.collection('sponsors').add(d);
    } else {
      await _db.doc('sponsors/$id').set(d, SetOptions(merge: true));
    }
  }
  static Future<void> deleteSponsor(String id) => _db.doc('sponsors/$id').delete();

  // ---- الأسئلة (السؤال + إجابته في مجموعة مغلقة) ----
  static Future<void> saveQuestion(String? id, Map<String, dynamic> q, int correct) async {
    final ref = id == null ? _db.collection('questions').doc() : _db.doc('questions/$id');
    final b = _db.batch();
    b.set(ref, q);
    b.set(_db.doc('answers/${ref.id}'), {'correct': correct});
    await b.commit();
  }
  static Future<void> deleteQuestion(String id) async {
    final b = _db.batch();
    b.delete(_db.doc('questions/$id'));
    b.delete(_db.doc('answers/$id'));
    await b.commit();
  }
  static Future<int?> correctOf(String id) async => (await _db.doc('answers/$id').get()).data()?['correct'] as int?;

  // ---- الفرق والنتائج ----
  static Future<void> editTeam(String id, String name, int? seed) =>
      _db.doc('teams/$id').update({if (name.isNotEmpty) 'name': name, if (seed != null) 'seed': seed});
  static Future<void> deleteTeam(String id) => _db.doc('teams/$id').delete();
  static Future<void> popSet(VMatch m) async {
    if (m.sets.isEmpty) return;
    m.sets.removeLast();
    await _db.doc('matches/${m.id}').update({'sets': m.sets.map((s) => {'a': s.a, 'b': s.b}).toList()});
  }

  // ---- الأخبار (إضافة/تعديل بصورة) ----
  static Future<void> saveNews(String? id, String title, String body, bool pinned, String image) async {
    final d = {'title': title, 'body': body, 'pinned': pinned, 'image': image};
    if (id == null) {
      await _db.collection('news').add({...d, 'by': Repo.uid, 'at': FieldValue.serverTimestamp()});
    } else {
      await _db.doc('news/$id').update(d);
    }
  }

  // ---- كلمات سر المهام والحسابات (عبر الخادم) ----
  static Stream<QuerySnapshot<Map<String, dynamic>>> rolePasswords() =>
      _db.collection('rolePasswords').orderBy('createdAt', descending: true).snapshots();
  static Stream<QuerySnapshot<Map<String, dynamic>>> staffAccounts() =>
      _db.collection('staffAccounts').orderBy('createdAt', descending: true).snapshots();
  static Future<String?> createRolePassword(String role, String label, String pw) async {
    try {
      await _fn.httpsCallable('createRolePassword').call({'role': role, 'label': label, 'password': pw});
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'تعذر الإنشاء';
    }
  }
  static Future<void> deleteRolePassword(String id, bool revoke) async {
    await _fn.httpsCallable('deleteRolePassword').call({'id': id, 'revokeHolders': revoke});
  }
}
