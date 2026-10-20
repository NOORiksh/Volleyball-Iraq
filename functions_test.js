const Module = require('module'), assert = require('assert'), crypto = require('crypto');
const store = {}, claims = {}, revoked = [], emails = new Set();
const ref = (path) => ({ path,
  get: async () => ({ exists: path in store, data: () => store[path] }),
  set: async (v) => { store[path] = v; }, delete: async () => { delete store[path]; },
  update: async (v) => { Object.assign(store[path], v); } });
const col = (name) => ({ add: async () => 0,
  where: (f, op, v) => ({ get: async () => ({ docs: Object.keys(store).filter((k) => k.startsWith(name + '/') && store[k][f] === v)
    .map((k) => ({ id: k.split('/')[1], ref: { delete: async () => { delete store[k]; } } })) }) }) });
const fake = {
  'firebase-functions/v2/https': { onCall: (o, h) => (h || o), HttpsError: class extends Error { constructor(c, m) { super(m); this.code = c; } } },
  'firebase-functions/v2/firestore': { onDocumentCreated: () => 0, onDocumentUpdated: () => 0 },
  'firebase-functions/params': { defineSecret: () => ({ value: () => '20072026' }) },
  'firebase-admin': Object.assign(() => 0, {
    initializeApp() {},
    firestore: Object.assign(() => ({ doc: ref, collection: col }), { FieldValue: { serverTimestamp: () => 0, increment: (n) => n } }),
    auth: () => ({
      getUser: async (u) => ({ customClaims: claims[u] }),
      setCustomUserClaims: async (u, c) => { claims[u] = c; },
      revokeRefreshTokens: async (u) => revoked.push(u),
      createUser: async ({ email }) => { if (emails.has(email)) throw { code: 'auth/email-already-exists' }; emails.add(email); return { uid: 'u_' + emails.size }; } }),
    messaging: () => ({ send: async () => 0 }) }),
};
const orig = Module._load;
Module._load = (r, ...a) => (r in fake ? fake[r] : orig(r, ...a));
const f = require('../functions/index.js');
const call = (fn, uid, data, role) => fn({ auth: uid && { uid, token: { role } }, data });
const is = (c) => (e) => e.code === c;
const h = (pw) => crypto.createHmac('sha256', '20072026').update(pw).digest('hex');

(async () => {
  // ---- الرمز السري => مدير المسؤولين فقط لحساب مسجّل بهذه المهمة ----
  store['users/fan1'] = { whatsapp: '0770' };
  store['users/staff1'] = { requestedDuty: 'مسؤول' };
  store['users/boss'] = { requestedDuty: 'مدير المسؤولين' };
  await assert.rejects(call(f.redeemAdminCode, 'fan1', { code: '20072026' }), is('permission-denied'));
  await assert.rejects(call(f.redeemAdminCode, 'staff1', { code: '20072026' }), is('permission-denied'));
  await assert.rejects(call(f.redeemAdminCode, null, { code: '20072026' }));
  assert.strictEqual(claims.fan1, undefined); assert.strictEqual(claims.staff1, undefined);
  for (let i = 0; i < 5; i++) await assert.rejects(call(f.redeemAdminCode, 'boss', { code: '0000' + i }), is('permission-denied'));
  await assert.rejects(call(f.redeemAdminCode, 'boss', { code: '20072026' }), is('resource-exhausted')); // قفل
  assert.strictEqual(claims.boss, undefined);
  delete store['adminAttempts/boss']; delete store['adminAttempts/_global'];
  const r = await call(f.redeemAdminCode, 'boss', { code: '20072026' });
  assert.deepStrictEqual([r.role, claims.boss], ['superadmin', { role: 'superadmin' }]);

  // ---- إنشاء كلمات سر المهام ----
  await assert.rejects(call(f.createRolePassword, 'u', { role: 'admin', label: 'x', password: '12345678' }, 'admin'), is('permission-denied'));
  await assert.rejects(call(f.createRolePassword, 'boss', { role: 'superadmin', label: 'x', password: '12345678' }, 'superadmin'), is('invalid-argument'));
  await assert.rejects(call(f.createRolePassword, 'boss', { role: 'admin', label: 'x', password: 'short' }, 'superadmin'), is('invalid-argument'));
  await call(f.createRolePassword, 'boss', { role: 'moderator', label: 'مشرف الشات', password: 'Chat-2026' }, 'superadmin');
  await call(f.createRolePassword, 'boss', { role: 'scorer', label: 'حكم', password: 'Score-2026' }, 'superadmin');
  assert.ok(store['rolePasswords/' + h('Chat-2026')]);
  assert.ok(!JSON.stringify(store).includes('Chat-2026')); // لا يُخزَّن نصاً صريحاً
  await assert.rejects(call(f.createRolePassword, 'boss', { role: 'admin', label: 'y', password: 'Chat-2026' }, 'superadmin'), is('already-exists'));

  // ---- تسجيل صاحب مهمة بالباسورد ----
  await assert.rejects(call(f.registerStaff, null, { name: 'علي', password: 'wrong-pass' }), is('permission-denied'));
  assert.strictEqual(emails.size, 0); // لم يُنشأ حساب
  const ok = await call(f.registerStaff, null, { name: 'علي', password: 'Chat-2026' });
  assert.strictEqual(ok.role, 'moderator');
  assert.deepStrictEqual(claims.u_1, { role: 'moderator' });
  assert.strictEqual(store['staffAccounts/u_1'].label, 'مشرف الشات');
  assert.strictEqual(store['users/u_1'].requestedDuty, 'مسؤول');
  await assert.rejects(call(f.registerStaff, null, { name: ' علي ', password: 'Chat-2026' }), is('already-exists'));
  const ok2 = await call(f.registerStaff, null, { name: 'سارة', password: 'Score-2026' });
  assert.strictEqual(ok2.role, 'scorer');

  // ---- حذف الباسورد مع سحب الصلاحية من أصحابه ----
  await assert.rejects(call(f.deleteRolePassword, 'u_1', { id: h('Chat-2026') }, 'moderator'), is('permission-denied'));
  await call(f.deleteRolePassword, 'boss', { id: h('Chat-2026'), revokeHolders: true }, 'superadmin');
  assert.deepStrictEqual(claims.u_1, {}); assert.ok(revoked.includes('u_1'));
  assert.ok(!store['rolePasswords/' + h('Chat-2026')] && !store['staffAccounts/u_1']);
  assert.deepStrictEqual(claims.u_2, { role: 'scorer' }); // الآخرون لا يتأثرون
  await assert.rejects(call(f.registerStaff, null, { name: 'نور', password: 'Chat-2026' }), is('permission-denied'));

  // ---- setRole ----
  await assert.rejects(call(f.setRole, 'u_2', { uid: 'x', role: 'admin' }, 'scorer'), is('permission-denied'));
  await call(f.setRole, 'boss', { uid: 'u_2', role: 'editor' }, 'superadmin');
  assert.strictEqual(store['staffAccounts/u_2'].role, 'editor');
  await call(f.setRole, 'boss', { uid: 'u_2', role: 'fan' }, 'superadmin');
  assert.ok(!store['staffAccounts/u_2']);
  console.log('✔ كل اختبارات الخادم نجحت');
})().catch((e) => { console.error('✘', e); process.exit(1); });
