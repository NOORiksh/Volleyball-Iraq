#!/usr/bin/env python3
"""يُشغَّل بعد: flutter create --org com.iraq --platforms=android .
يضبط: google-services.json، minSdk 23، صلاحيات الإنترنت والإشعارات، اسم التطبيق، وإضافة Google Services."""
import pathlib, re, shutil, sys

root = pathlib.Path(__file__).resolve().parent.parent
android = root / 'android'
log = lambda m: print('[setup_android]', m)
def die(m): print('[setup_android] خطأ:', m); sys.exit(1)

if not android.exists(): die('مجلد android غير موجود. نفّذ flutter create أولاً.')
shutil.copy(root / 'google-services.json', android / 'app' / 'google-services.json')
log('تم نسخ google-services.json')

def find(folder, names):
    return next((folder / n for n in names if (folder / n).exists()), None)

app = find(android / 'app', ('build.gradle.kts', 'build.gradle'))
settings = find(android, ('settings.gradle.kts', 'settings.gradle'))
if not app: die('لم أجد android/app/build.gradle')
kts = app.suffix == '.kts'
txt = app.read_text(encoding='utf-8')

if 'com.iraq.volleyball' not in txt:
    die('applicationId ليس com.iraq.volleyball — تأكد أن اسم المشروع في pubspec هو volleyball')
log('applicationId = com.iraq.volleyball ✔')

# minSdk 23 (متطلب Firebase Auth/Messaging)
new = 'minSdk = 23' if kts else 'minSdkVersion 23'
txt, n = re.subn(r'minSdk(?:Version)?\s*=?\s*flutter\.minSdkVersion', new, txt)
if n == 0 and not re.search(r'minSdk(?:Version)?\s*=?\s*(2[3-9]|[3-9]\d)\b', txt):
    die('تعذر ضبط minSdk يدوياً: اجعله 23 في android/app/build.gradle')
log('minSdk = 23 ✔')

# إضافة Google Services: تُطبَّق فقط إذا نجح التعديل في الملفين (وإلا نكتفي بـ firebase_options.dart)
GS = 'com.google.gms.google-services'
plugin_ok = False
if settings and GS not in settings.read_text(encoding='utf-8') + txt:
    s = settings.read_text(encoding='utf-8')
    line = f'id("{GS}") version "4.4.2" apply false' if settings.suffix == '.kts' else f'id "{GS}" version "4.4.2" apply false'
    s2, n1 = re.subn(r'id\(?\s*["\']com\.android\.application["\']\s*\)?\s*version\s*["\'][^"\']+["\']\s*apply\s*false',
                     lambda m: m.group(0) + '\n    ' + line, s, count=1)
    line2 = f'id("{GS}")' if kts else f'id "{GS}"'
    t2, n2 = re.subn(r'id\(?\s*["\']dev\.flutter\.flutter-gradle-plugin["\']\)?',
                     lambda m: m.group(0) + '\n    ' + line2, txt, count=1)
    if n1 and n2:
        settings.write_text(s2, encoding='utf-8'); txt = t2; plugin_ok = True
if plugin_ok: log('تمت إضافة Google Services plugin ✔')
elif GS in txt: log('Google Services موجود مسبقاً ✔')
else: log('تحذير: لم تُضَف Google Services (لا مشكلة: firebase_options.dart يكفي للاتصال)')
app.write_text(txt, encoding='utf-8')

# AndroidManifest: إنترنت (غير موجود في نسخة release افتراضياً!) + إشعارات + فتح الروابط + اسم التطبيق
mf = android / 'app' / 'src' / 'main' / 'AndroidManifest.xml'
m = mf.read_text(encoding='utf-8')
ind = re.search(r'^([ \t]*)<application', m, re.M).group(1)
perms = ''.join(f'{ind}<uses-permission android:name="android.permission.{p}"/>\n'
                for p in ('INTERNET', 'POST_NOTIFICATIONS') if f'permission.{p}' not in m)
if perms: m = re.sub(r'^([ \t]*)<application', lambda mo: perms + mo.group(0), m, count=1, flags=re.M)
m = re.sub(r'android:label="[^"]*"', 'android:label="شهداء العراق"', m, count=1)
if 'android:scheme="https"' not in m:
    intent = (f'{ind}{ind}<intent>\n{ind}{ind}{ind}<action android:name="android.intent.action.VIEW"/>\n'
              f'{ind}{ind}{ind}<data android:scheme="https"/>\n{ind}{ind}</intent>\n')
    if '</queries>' in m: m = m.replace(f'{ind}</queries>', intent + f'{ind}</queries>', 1)
    else: m = re.sub(r'^([ \t]*)<application', lambda mo: f'{ind}<queries>\n' + intent + f'{ind}</queries>\n' + mo.group(0), m, count=1, flags=re.M)
mf.write_text(m, encoding='utf-8')
log('تم تعديل AndroidManifest ✔')
