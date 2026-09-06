import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubit/inventory/inventory_cubit.dart';
import 'cubit/order/order_cubit.dart';
import 'firebase_options.dart';
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
  await registerOwnerToken();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => InventoryCubit()),
        BlocProvider(create: (_) => OrderCubit()),
      ],
      child: MaterialApp(
        title: 'إدارة المتجر',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF1F3A3D)),
        home: const HomeScreen(),
      ),
    );
  }
}
