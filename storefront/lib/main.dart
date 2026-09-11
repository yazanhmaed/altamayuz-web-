import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'firebase_options.dart';
import 'router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const StorefrontApp());
}

/// App-wide scroll feel. Guarantees touch-drag scrolling is enabled on web
/// regardless of Flutter-version defaults, and picks one deliberate
/// momentum/overscroll feel (iOS-style bounce) for every scroll view on both
/// iOS and Android rather than each platform's differing default.
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.touch,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());
}

class StorefrontApp extends StatelessWidget {
  const StorefrontApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'التميز للجلود الطبيعية المميزة',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _AppScrollBehavior(),
      theme: AppTheme.theme,
      locale: const Locale('ar'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar')],
      routerConfig: appRouter,
    );
  }
}
