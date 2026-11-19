// Public Firebase client configuration; contains no server credentials.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => apple,
    TargetPlatform.macOS => macos,
    TargetPlatform.android => android,
    _ => throw UnsupportedError('Firebase is configured for native apps only'),
  };
  static const apple = FirebaseOptions(
    apiKey: "AIzaSyCgVcVDNxyX2h-6fmvhPfRYX3eGsYznhLw",
    appId: "1:422174023287:ios:420cd37892e20813e8f072",
    messagingSenderId: "422174023287",
    projectId: "fayetteville-the-people-voice",
    storageBucket: "fayetteville-the-people-voice.firebasestorage.app",
    iosBundleId: "com.fayettevillepeoplevoice.peopleVoice",
  );
  static const android = FirebaseOptions(
    apiKey: "AIzaSyCkDUjIt6O9vnmrlTGg0-cRZQ0yeCVYyqs",
    appId: "1:422174023287:android:b5d08af03bd255e0e8f072",
    messagingSenderId: "422174023287",
    projectId: "fayetteville-the-people-voice",
    storageBucket: "fayetteville-the-people-voice.firebasestorage.app",
  );
  static const macos = FirebaseOptions(
    apiKey: "AIzaSyCgVcVDNxyX2h-6fmvhPfRYX3eGsYznhLw",
    appId: "1:422174023287:ios:5d5a3c09def2ad44e8f072",
    messagingSenderId: "422174023287",
    projectId: "fayetteville-the-people-voice",
    storageBucket: "fayetteville-the-people-voice.firebasestorage.app",
    iosBundleId: "com.fayettevillepeoplevoice.mac.a9x2dv8x8l",
  );
}
