// Gerado a partir do google-services.json
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web não suportado');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Plataforma não suportada');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAFQEoQtlgmLArimBTHrDWak_6xBvCYROE',
    appId: '1:307488308337:android:334976e324208ae2ec6fd0',
    messagingSenderId: '307488308337',
    projectId: 'korespectre',
    storageBucket: 'korespectre.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAm6RIIaVIqeLMU8WZWUIBWQJ8OEukpaKE',
    appId: '1:307488308337:ios:f138ec0e962f0906ec6fd0',
    messagingSenderId: '307488308337',
    projectId: 'korespectre',
    storageBucket: 'korespectre.firebasestorage.app',
    iosBundleId: 'com.korecloud.koreSpectre',
  );
}
