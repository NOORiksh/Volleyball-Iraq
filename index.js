const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const crypto = require('crypto');
admin.initializeApp();
const db = admin.firestore();
const ADMIN_CODE = defineSecret('ADMIN_CODE'); // firebase functions:secrets:set ADMIN_CODE
const sha = (s) => crypto.createHash('sha256').update(String(s)).digest();

// الرمز السري يُتحقق منه هنا فقط، ثم يُمنح claim باسم role=admin
exports.redeemAdminCode = onCall({ secrets: [ADMIN_CODE], enforceAppCheck: false }, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'سجّل الدخول أولاً');
  const uid = req.auth.uid, now = Date.now();
  const u = await db.doc(`users/${uid}`).get();
  if (!u.exists || u.data().requestedDuty !== 'مدير المسؤولين') throw new HttpsError('permission-denied', 'الرمز خاص بحساب مدير المسؤولين');
  const mine = db.doc(`adminAttempts/${uid}`), glob = db.doc('adminAttempts/_global');
  const [m, g] = await Promise.all([mine.get(), glob.get()]);
  const md = m.data() || { count: 0 }, gd = g.data() || { count: 0, since: now };
  if (md.lockedUntil > now) throw new HttpsError('resource-exhausted', 'محاولات كثيرة، حاول لاحقاً');
  if (now - gd.since < 3600e3 && gd.count >= 50) throw new HttpsError('resource-exhausted', 'النظام مقفل مؤقتاً');

  const ok = crypto.timingSafeEqual(sha(req.data.code), sha(ADMIN_CODE.value()));
  if (!ok) {
    const count = md.count + 1;
    await mine.set({ count, lockedUntil: count >= 5 ? now + 3600e3 : 0 });
    const fresh = now - gd.since >= 3600e3;
    await glob.set({ count: fresh ? 1 : gd.count + 1, since: fresh ? now : gd.since });
    throw new HttpsError('permission-denied', 'الرمز غير صحيح');
  }
  await mine.delete();
  await admin.auth().setCustomUserClaims(uid, { role: 'superadmin' });
  return { role: 'superadmin' };
});

// مدير المسؤولين فقط: ترقية/تخفيض أي حساب
exports.setRole = onCall(async (req) => {
  if (req.auth?.token.role !== 'superadmin') throw new HttpsError('permission-denied', 'للمدير فقط');
  const { uid, role } = req.data;
  if (!['fan', 'admin', 'superadmin', 'moderator', 'scorer', 'editor'].includes(role)) throw new HttpsError('invalid-argument', 'دور غير صالح');
  await admin.auth().setCustomUserClaims(uid, role === 'fan' ? {} : { role });
  await admin.auth().revokeRefreshTokens(uid); // يُلغي الجلسات القديمة فلا تبقى الصلاحية السابقة
  const sa = db.doc(`staffAccounts/${uid}`);
  if ((await sa.get()).exists) { if (role === 'fan') await sa.delete(); else await sa.update({ role }); }
  return { ok: true };
});

// تصحيح الإجابة وصرف المكافأة على الخادم (الإجابات الصحيحة لا تصل للتطبيق)
exports.submitAnswer = onCall(async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', '');
  const { questionId, choice } = req.data, uid = req.auth.uid;
  const a = await db.doc(`answers/${questionId}`).get();
  if (!a.exists) throw new HttpsError('not-found', 'سؤال غير موجود');
  const correctIndex = a.data().correct, done = db.doc(`profiles/${uid}/answered/${questionId}`);
  if (choice !== correctIndex) return { correct: false, correctIndex, coins: 0, xp: 0 };
  return db.runTransaction(async (t) => {
    if ((await t.get(done)).exists) return { correct: true, correctIndex, coins: 0, xp: 0 };
    t.set(done, { at: admin.firestore.FieldValue.serverTimestamp() });
    t.update(db.doc(`profiles/${uid}`), {
      coins: admin.firestore.FieldValue.increment(10), xp: admin.firestore.FieldValue.increment(20) });
    return { correct: true, correctIndex, coins: 10, xp: 20 };
  });
});

// ================= الأخبار والإشعارات =================
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');

// يسجّل الإشعار داخل التطبيق ويرسل Push لكل المشتركين في موضوع "all"
async function notify(title, body, type) {
  await db.collection('notifications').add({
    title, body, type, at: admin.firestore.FieldValue.serverTimestamp() });
  await admin.messaging().send({ topic: 'all', notification: { title, body } });
}

// خبر جديد من المسؤول => إشعار
exports.onNewsCreated = onDocumentCreated('news/{id}', (e) => {
  const d = e.data?.data();
  if (!d) return;
  return notify(d.title, String(d.body || '').slice(0, 120), 'news');
});

// انتهاء مباراة (وصول أحد الفريقين لعدد الأشواط المطلوب) => إشعار بالنتيجة
exports.onMatchUpdated = onDocumentUpdated('matches/{id}', async (e) => {
  const wins = (m) => { let a = 0, b = 0; for (const s of m.sets || []) { if (s.a > s.b) a++; else b++; } return [a, b]; };
  const before = e.data.before.data(), after = e.data.after.data();
  const need = Math.floor((after.bestOf || 3) / 2) + 1;
  const [ba, bb] = wins(before), [aa, ab] = wins(after);
  const done = (x, y) => x >= need || y >= need;
  if (done(ba, bb) || !done(aa, ab)) return;
  const [ta, tb] = await Promise.all([db.doc(`teams/${after.teamA}`).get(), db.doc(`teams/${after.teamB}`).get()]);
  const A = ta.data().name, B = tb.data().name;
  return notify('انتهت المباراة', `${A} ${aa} - ${ab} ${B} · الفائز: ${aa > ab ? A : B}`, 'result');
});


// ================= كلمات سر المهام =================
// المدير ينشئ كلمة سر لمهمة (مسؤول / مشرف شات / مسجّل نتائج / محرر أخبار).
// تُخزَّن مشفّرة (HMAC) ومعرّف المستند هو الهاش نفسه، فلا تُقرأ ولا تتكرر.
const PW_PEPPER = defineSecret('PW_PEPPER'); // firebase functions:secrets:set PW_PEPPER
const ROLES = ['admin', 'moderator', 'scorer', 'editor'];
const hmac = (pw) => crypto.createHmac('sha256', PW_PEPPER.value()).update(String(pw)).digest('hex');
const emailOf = (name) => crypto.createHash('sha1').update(`staff:${String(name).trim().toLowerCase()}`).digest('hex') + '@volley.app';
const needSuper = (req) => { if (req.auth?.token.role !== 'superadmin') throw new HttpsError('permission-denied', 'للمدير فقط'); };

async function throttle(key, perLimit = 5, globalLimit = 100) {
  const now = Date.now();
  const mine = db.doc(`adminAttempts/${key}`), glob = db.doc('adminAttempts/_reg');
  const [m, g] = await Promise.all([mine.get(), glob.get()]);
  const md = m.data() || { count: 0 }, gd = g.data() || { count: 0, since: now };
  if (md.lockedUntil > now) throw new HttpsError('resource-exhausted', 'محاولات كثيرة، حاول لاحقاً');
  if (now - gd.since < 3600e3 && gd.count >= globalLimit) throw new HttpsError('resource-exhausted', 'النظام مقفل مؤقتاً');
  return {
    fail: async () => {
      const count = md.count + 1, fresh = now - gd.since >= 3600e3;
      await mine.set({ count, lockedUntil: count >= perLimit ? now + 3600e3 : 0 });
      await glob.set({ count: fresh ? 1 : gd.count + 1, since: fresh ? now : gd.since });
    },
    ok: () => mine.delete(),
  };
}

exports.createRolePassword = onCall({ secrets: [PW_PEPPER] }, async (req) => {
  needSuper(req);
  const { role, label, password } = req.data || {};
  const pw = String(password || ''), lab = String(label || '').trim();
  if (!ROLES.includes(role)) throw new HttpsError('invalid-argument', 'مهمة غير صالحة');
  if (pw.length < 8) throw new HttpsError('invalid-argument', 'الباسورد 8 أحرف على الأقل');
  if (!lab || lab.length > 40) throw new HttpsError('invalid-argument', 'اسم المهمة غير صالح');
  const ref = db.doc(`rolePasswords/${hmac(pw)}`);
  if ((await ref.get()).exists) throw new HttpsError('already-exists', 'هذا الباسورد مستخدم لمهمة أخرى');
  await ref.set({ role, label: lab, active: true, uses: 0, createdAt: admin.firestore.FieldValue.serverTimestamp() });
  return { ok: true };
});

exports.deleteRolePassword = onCall(async (req) => {
  needSuper(req);
  const { id, revokeHolders } = req.data || {};
  if (!id) throw new HttpsError('invalid-argument', '');
  if (revokeHolders) {
    const q = await db.collection('staffAccounts').where('pwId', '==', id).get();
    for (const d of q.docs) {
      await admin.auth().setCustomUserClaims(d.id, {});
      await admin.auth().revokeRefreshTokens(d.id);
      await d.ref.delete();
    }
  }
  await db.doc(`rolePasswords/${id}`).delete();
  return { ok: true };
});

// تسجيل صاحب مهمة: الاسم + كلمة سر المهمة. الحساب يُنشأ من الخادم فقط بعد التحقق من الكلمة.
exports.registerStaff = onCall({ secrets: [PW_PEPPER] }, async (req) => {
  const name = String(req.data?.name || '').trim(), pw = String(req.data?.password || '');
  if (name.length < 2 || name.length > 40) throw new HttpsError('invalid-argument', 'الاسم غير صالح');
  const th = await throttle('reg_' + crypto.createHash('sha1').update(name.toLowerCase()).digest('hex'));
  const h = hmac(pw), ref = db.doc(`rolePasswords/${h}`), snap = await ref.get();
  if (!snap.exists || snap.data().active === false) {
    await th.fail();
    throw new HttpsError('permission-denied', 'كلمة سر المهمة غير صحيحة');
  }
  const { role, label } = snap.data();
  let user;
  try { user = await admin.auth().createUser({ email: emailOf(name), password: pw, displayName: name }); }
  catch (e) {
    if (e.code === 'auth/email-already-exists') throw new HttpsError('already-exists', 'هذا الاسم مسجّل مسبقاً');
    throw e;
  }
  const uid = user.uid, ts = admin.firestore.FieldValue.serverTimestamp();
  await admin.auth().setCustomUserClaims(uid, { role });
  await Promise.all([
    db.doc(`profiles/${uid}`).set({ name, coins: 0, xp: 0, createdAt: ts }),
    db.doc(`users/${uid}`).set({ requestedDuty: 'مسؤول' }),
    db.doc(`staffAccounts/${uid}`).set({ name, role, label, pwId: h, createdAt: ts }),
    ref.update({ uses: admin.firestore.FieldValue.increment(1) }),
  ]);
  await th.ok();
  return { ok: true, role };
});
