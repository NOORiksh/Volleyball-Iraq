// node tools/seed.js questions            -> يرفع الأسئلة (بدون الإجابات) + الإجابات في مجموعة منفصلة
// node tools/seed.js super <UID>          -> يجعل الحساب "مدير المسؤولين" (أول مرة فقط)
// يتطلب: GOOGLE_APPLICATION_CREDENTIALS يشير لمفتاح حساب الخدمة
const admin = require('firebase-admin');
admin.initializeApp();
const [cmd, arg] = process.argv.slice(2);
(async () => {
  if (cmd === 'super') {
    await admin.auth().setCustomUserClaims(arg, { role: 'superadmin' });
    console.log('تم. على المستخدم تسجيل الخروج والدخول من جديد.');
  } else if (cmd === 'questions') {
    const qs = require('../questions.json').questions, db = admin.firestore();
    for (let i = 0; i < qs.length; i += 200) {
      const b = db.batch();
      qs.slice(i, i + 200).forEach((q) => {
        const { answerIndex, ...pub } = q;
        b.set(db.doc(`questions/${q.id}`), pub);
        b.set(db.doc(`answers/${q.id}`), { correct: answerIndex });
      });
      await b.commit();
    }
    console.log(`رُفع ${qs.length} سؤال`);
  }
})();
