// lib/main.dart (Iyakosowe amakosa yose, App Check irahagaze)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/services/presence_service.dart'; // <<< IMPINDUKA #1 >>>
import 'package:jembe_talk/services/sync_service.dart';
import 'package:jembe_talk/theme_manager.dart';
import 'package:jembe_talk/welcome_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:animations/animations.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  syncService.start();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeManager(prefs),
      child: const MyApp(),
    ),
  );
}

// <<< IMPINDUKA #2: TWAHINDURIYEMO STATLESS IKABA STATEFUL WIDGET >>>
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final PresenceService _presenceService = PresenceService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presenceService.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _presenceService.goOnline();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _presenceService.goOffline();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    const pageTransitionsTheme = PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SharedAxisPageTransitionsBuilder(
          transitionType: SharedAxisTransitionType.horizontal,
        ),
        TargetPlatform.iOS: SharedAxisPageTransitionsBuilder(
          transitionType: SharedAxisTransitionType.horizontal,
        ),
      },
    );
    return MaterialApp(
      title: 'Jembe Talk',
      debugShowCheckedModeBanner: false,
      themeMode: themeManager.themeMode,
      theme: themeManager.getLightTheme.copyWith(
        pageTransitionsTheme: pageTransitionsTheme,
      ),
      darkTheme: themeManager.getDarkTheme.copyWith(
        pageTransitionsTheme: pageTransitionsTheme,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData) {
            return const HomeScreen();
          }
          return const WelcomeScreen();
        },
      ),
    );
  }
}