import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'analytics.dart';
import 'firebase_options.dart';
import 'router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // No Flutter Web implementation of Firebase Crashlytics exists yet, so
  // uncaught errors are reported as Analytics events instead — the closest
  // available stand-in for crash reporting on this platform.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _reportError(details.exception);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _reportError(error);
    return true;
  };

  runApp(const StorefrontApp());
}

/// Guards against the reporter re-entering itself if logging throws.
bool _reportingError = false;

/// Logs an uncaught error as `client_error` (`app_exception` is reserved by
/// Firebase Analytics and is rejected). Param values are capped at 100 chars,
/// the Analytics limit. Never throws.
void _reportError(Object error) {
  if (_reportingError) return;
  _reportingError = true;
  try {
    String cap(String s) => s.length > 100 ? s.substring(0, 100) : s;
    String screen = '';
    try {
      screen = appRouter.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {}
    analytics
        .logEvent(
          name: 'client_error',
          parameters: {
            'message': cap(error.toString()),
            'type': cap(error.runtimeType.toString()),
            'screen': cap(screen),
          },
        )
        .catchError((_) {});
  } catch (_) {
  } finally {
    _reportingError = false;
  }
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
