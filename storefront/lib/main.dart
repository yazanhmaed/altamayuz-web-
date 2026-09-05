import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/store_home_page.dart';
import 'theme/app_theme.dart';

/// reCAPTCHA v3 site key for Firebase App Check on web.
///
/// Pass it at build/run time:
///   flutter run --dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=6Lxxxx...
/// When empty (e.g. local dev before the key is set up), App Check is
/// skipped so the app still boots.
const String _appCheckSiteKey =
    String.fromEnvironment('APP_CHECK_RECAPTCHA_SITE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (_appCheckSiteKey.isNotEmpty) {
    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider(_appCheckSiteKey),
    );
  } else if (kDebugMode) {
    debugPrint(
      'App Check disabled: APP_CHECK_RECAPTCHA_SITE_KEY not set. '
      'Backend calls will fail if App Check enforcement is on.',
    );
  }
  runApp(const StorefrontApp());
}

class StorefrontApp extends StatelessWidget {
  const StorefrontApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'المتجر',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const StoreHomePage(),
    );
  }
}
