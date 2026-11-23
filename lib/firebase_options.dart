// lib/firebase_options.dart
//
// Vindara — Default Firebase Options
// Project: vindara-d3d93
// Package: com.vindara.app

// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholder-Vindara-Android-Key',
    appId: '1:325236805162:android:com.vindara.app',
    messagingSenderId: '325236805162',
    projectId: 'vindara-d3d93',
    storageBucket: 'vindara-d3d93.appspot.com',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholder-Vindara-Web-Key',
    appId: '1:325236805162:web:vindara',
    messagingSenderId: '325236805162',
    projectId: 'vindara-d3d93',
    storageBucket: 'vindara-d3d93.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholder-Vindara-iOS-Key',
    appId: '1:325236805162:ios:com.vindara.app',
    messagingSenderId: '325236805162',
    projectId: 'vindara-d3d93',
    storageBucket: 'vindara-d3d93.appspot.com',
    iosBundleId: 'com.vindara.app',
  );
}

