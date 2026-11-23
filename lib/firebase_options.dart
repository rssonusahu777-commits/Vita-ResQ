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
    apiKey: 'AIzaSyCpw7Qwe5S_VX-x3VOwkFKGwj-MAfnt5Is',
    appId: '1:46771632912:android:18d8ff3e8666d4d6f1c395',
    messagingSenderId: '46771632912',
    projectId: 'vindara-d3d93',
    storageBucket: 'vindara-d3d93.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCpw7Qwe5S_VX-x3VOwkFKGwj-MAfnt5Is',
    appId: '1:46771632912:web:vindara',
    messagingSenderId: '46771632912',
    projectId: 'vindara-d3d93',
    storageBucket: 'vindara-d3d93.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCpw7Qwe5S_VX-x3VOwkFKGwj-MAfnt5Is',
    appId: '1:46771632912:ios:com.vindara.app',
    messagingSenderId: '46771632912',
    projectId: 'vindara-d3d93',
    storageBucket: 'vindara-d3d93.firebasestorage.app',
    iosBundleId: 'com.vindara.app',
  );
}
