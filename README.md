# بطولة شهداء العراق للكرة الطائرة — دليل الإعداد

مشروع Firebase: `volleyball-iraq` · الحزمة: `com.iraq.volleyball` (الإعدادات مولَّدة من google-services.json في `lib/firebase_options.dart`)

## 1) من لوحة Firebase (مرة واحدة)
1. Authentication ← Sign-in method ← فعّل **Email/Password**.
2. Firestore Database ← Create database.
3. Storage ← Get started (للصور).
4. رقّ المشروع إلى خطة **Blaze** (شرط لتشغيل Cloud Functions).

## 2) نشر الخادم (من جهازك)
```bash
npm i -g firebase-tools && firebase login
cd functions && npm i && cd ..
firebase functions:secrets:set ADMIN_CODE      # رمز مدير المسؤولين (اختر رمزاً جديداً أطول من 8 أرقام)
firebase functions:secrets:set PW_PEPPER       # أي نص عشوائي طويل (لتشفير كلمات سر المهام)
firebase deploy --only firestore:rules,storage,functions
```
رفع الأسئلة (يحتاج مفتاح حساب خدمة: Project settings ← Service accounts ← Generate key، احفظه key.json ولا ترفعه إلى GitHub):
```bash
cd functions && npm i && cd ..
GOOGLE_APPLICATION_CREDENTIALS=key.json NODE_PATH=functions/node_modules node tools/seed.js questions
```

## 3) بناء الـ APK
**الأسهل: GitHub Actions** — ارفع المشروع إلى مستودع GitHub، ثم:
- يدوياً: Actions ← Build APK ← Run workflow ← حمّل `shuhada-iraq-apk` من Artifacts.
- أو برابط عام: `git tag v1.0.0 && git push --tags` ← يظهر الـ APK في صفحة Releases.

**Codemagic:** اربط المستودع وسيقرأ `codemagic.yaml` تلقائياً.

**محلياً:**
```bash
flutter create --org com.iraq --platforms=android .   # يولّد android/ دون المساس بـ lib
python3 tools/setup_android.py                        # Firebase + minSdk 23 + الصلاحيات
flutter pub get && flutter build apk --release
# الناتج: build/app/outputs/flutter-apk/app-release.apk
```
الـ APK موقَّع بمفتاح التطوير (يصلح للتثبيت المباشر). للنشر على Google Play أنشئ keystore ووقّع الإصدار.

## 4) أول استخدام
1. سجّل من التطبيق: مسؤول ← حساب جديد ← المهمة **مدير المسؤولين** ← اسم وكلمة سر.
2. تبويب الإدارة ← أدخل الرمز السري (ADMIN_CODE) ← تصبح مدير المسؤولين.
3. من «كلمات سر المهام» أنشئ باسوردات لأصحاب المهام؛ يسجّلون بها من: مسؤول ← حساب جديد ← الاسم + الباسورد.
4. من «الرعاة» و«المحتوى والصور» أضف الرعاة وعدّل الصفحة الرئيسية.

## ملاحظات
- Realtime Database غير مستخدمة (الشات في Firestore).
- `dartpad_demo.dart` نسخة عرض بلا Firebase ولا تتضمن الرعاة ولا الباسوردات.
- فحص الخادم: `node test/functions_test.js`
