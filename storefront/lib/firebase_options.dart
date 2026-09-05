// File generated normally by the FlutterFire CLI (`flutterfire configure`).
//
// This is a placeholder so the project compiles out of the box. Before
// running the app, replace every value below with the ones from your
// Firebase project (Project settings > General > Your apps), or simply
// run `flutterfire configure` from this directory to regenerate the file.
//
// This app must share the SAME Firebase project as admin_app/ so that the
// storefront's products_public reads and submitPublicOrder calls reach the
// same Firestore database and Cloud Functions.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'TODO-REPLACE-WITH-YOUR-WEB-API-KEY',
    appId: 'TODO-REPLACE-WITH-YOUR-WEB-APP-ID',
    messagingSenderId: 'TODO-REPLACE-WITH-YOUR-SENDER-ID',
    projectId: 'TODO-REPLACE-WITH-YOUR-PROJECT-ID',
    authDomain: 'TODO-REPLACE.firebaseapp.com',
    storageBucket: 'TODO-REPLACE.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'TODO-REPLACE-WITH-YOUR-ANDROID-API-KEY',
    appId: 'TODO-REPLACE-WITH-YOUR-ANDROID-APP-ID',
    messagingSenderId: 'TODO-REPLACE-WITH-YOUR-SENDER-ID',
    projectId: 'TODO-REPLACE-WITH-YOUR-PROJECT-ID',
    storageBucket: 'TODO-REPLACE.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TODO-REPLACE-WITH-YOUR-IOS-API-KEY',
    appId: 'TODO-REPLACE-WITH-YOUR-IOS-APP-ID',
    messagingSenderId: 'TODO-REPLACE-WITH-YOUR-SENDER-ID',
    projectId: 'TODO-REPLACE-WITH-YOUR-PROJECT-ID',
    storageBucket: 'TODO-REPLACE.appspot.com',
    iosBundleId: 'com.altamayuz.storefront',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'TODO-REPLACE-WITH-YOUR-MACOS-API-KEY',
    appId: 'TODO-REPLACE-WITH-YOUR-MACOS-APP-ID',
    messagingSenderId: 'TODO-REPLACE-WITH-YOUR-SENDER-ID',
    projectId: 'TODO-REPLACE-WITH-YOUR-PROJECT-ID',
    storageBucket: 'TODO-REPLACE.appspot.com',
    iosBundleId: 'com.altamayuz.storefront',
  );
}
