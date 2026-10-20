// مولَّد من google-services.json (مشروع volleyball-iraq، حزمة com.iraq.volleyball)
// مفتاح API لأندرويد في Firebase ليس سرّاً؛ الحماية الفعلية في قواعد Firestore/Storage.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('هذا التطبيق مخصص لأندرويد فقط.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB6Qjn5UGJk3yRx-F3EPsVK_ZN3wH_ZKZ0',
    appId: '1:727712823053:android:fa3cb2be5ff2a45eb56244',
    messagingSenderId: '727712823053',
    projectId: 'volleyball-iraq',
    storageBucket: 'volleyball-iraq.firebasestorage.app',
  );
}
