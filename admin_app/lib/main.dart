import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'cubit/dashboard/dashboard_cubit.dart';
import 'cubit/inventory/inventory_cubit.dart';
import 'cubit/order/order_cubit.dart';
import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> registerOwnerToken() async {
  // Web push needs a VAPID key + service worker that aren't configured yet,
  // so owner-token registration is limited to mobile for now.
  if (kIsWeb) return;
  try {
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('owner')
          .set({'fcmToken': token}, SetOptions(merge: true));
    }
  } catch (e) {
    debugPrint('registerOwnerToken failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Required once before any `DateFormat(..., 'ar')` call (e.g. order_card.dart's
  // creation-date display) — intl throws a LocaleDataException otherwise.
  await initializeDateFormatting('ar');
  runApp(const AdminApp());
}

/// Auth gate. Each branch builds its own [MaterialApp] (via [_buildApp]) so
/// the cubit providers can sit above the Navigator — pushed routes like
/// AddProductScreen read them — while still being created only once a user
/// is signed in. Signing out swaps the whole signed-in subtree away, which
/// closes the cubits (dropping cached orders/products) and any pushed routes.
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildApp(
            home: const Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return _buildApp(home: const LoginScreen());
        }
        return _SignedInApp(key: ValueKey(user.uid));
      },
    );
  }
}

/// Created fresh on every sign-in (keyed by uid in [AdminApp]), so the
/// owner's FCM token is registered once per session — now with an
/// authenticated user, which the owner-only `settings` rule requires.
class _SignedInApp extends StatefulWidget {
  const _SignedInApp({super.key});

  @override
  State<_SignedInApp> createState() => _SignedInAppState();
}

class _SignedInAppState extends State<_SignedInApp> {
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _verifyOwner();
  }

  /// The rules are the real gate (owner UID lives only there); this probe of
  /// an owner-only doc just keeps any other account from sitting on a screen
  /// full of permission errors — it's signed straight back out to Login.
  Future<void> _verifyOwner() async {
    try {
      await FirebaseFirestore.instance.collection('settings').doc('owner').get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        setLoginNotice('هذا الحساب غير مصرح له بالدخول');
        await FirebaseAuth.instance.signOut();
        return;
      }
      // Other failures (e.g. offline) fall through — the rules still apply.
    } catch (_) {}
    if (!mounted) return;
    setState(() => _verified = true);
    registerOwnerToken();
  }

  @override
  Widget build(BuildContext context) {
    if (!_verified) {
      return _buildApp(
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => InventoryCubit()),
        BlocProvider(create: (_) => OrderCubit()),
        BlocProvider(create: (_) => DashboardCubit()),
      ],
      child: _buildApp(home: const HomeScreen()),
    );
  }
}

Widget _buildApp({required Widget home}) {
  return MaterialApp(
    title: 'إدارة المتجر',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ar')],
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF1F3A3D),
      fontFamily: 'Tajawal',
    ),
    home: home,
  );
}
