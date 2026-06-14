// lib/main.dart (VERSION 52.1 - FINAL STABLE & CLEAN SECURITY)

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

// PROJECT IMPORTS
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/services/presence_service.dart';
import 'package:jembe_talk/services/sync_service.dart';
import 'package:jembe_talk/services/notification_service.dart';
import 'package:jembe_talk/tangaza_star/feed_manager.dart';
import 'package:jembe_talk/tangaza_star/tangaza_star_screen.dart';
import 'package:jembe_talk/theme_manager.dart';
import 'package:jembe_talk/welcome_screen.dart';
import 'package:jembe_talk/profile_setup_screen.dart';
import 'package:jembe_talk/email_verification_screen.dart';
import 'package:jembe_talk/settings_screen.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart' as sp;
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/forward_screen.dart';
import 'package:permission_handler/permission_handler.dart';

// SECURITY & UPDATE IMPORTS
import 'package:jembe_talk/user_blocked_screen.dart';
import 'package:jembe_talk/screens/update_guard_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  }
  if (message.data['type'] == 'chat') {
    await NotificationService.initialize();
    NotificationService.showChatNotification(message);
  }
}

class GlobalNavigator {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  } catch (e) {
    debugPrint("SystemUI error ignored: $e");
  }

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    final prefs = await sp.SharedPreferences.getInstance();

    _initFirestoreSettings();
    _initSilentServices();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeManager(prefs)),
          ChangeNotifierProvider(create: (_) => FeedManager()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: const MyApp(),
      ),
    );
  } catch (e) {
    debugPrint("Critical Launch Error: $e");
  }
}

void _initFirestoreSettings() {
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 52428800,
  );
}

void _initSilentServices() {
  unawaited(FirebaseAppCheck.instance.activate(
    androidProvider:
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    appleProvider: AppleProvider.deviceCheck,
  ));
  unawaited(initializeDateFormatting('fr_FR', null));
  unawaited(NotificationService.initialize());
  if (Platform.isAndroid) unawaited(MediaStore.ensureInitialized());
  unawaited(FirebaseMessaging.instance
      .requestPermission(alert: true, badge: true, sound: true));
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static const platform = MethodChannel('app.channel.shared.data');
  StreamSubscription? _securitySubscription,
      _deviceConflictSubscription,
      _authSubscription,
      _appStatusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestAndroidPermissions();

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        final prefs = await sp.SharedPreferences.getInstance();
        await prefs.setString('current_user_uid', user.uid);
        presenceService.initialize();
        syncService.start();
        _startGlobalSecurityGuard();
        _startAppStatusGuard();
      } else {
        _stopAllGuards();
      }
    });

    _initDynamicLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _handlePlatformIntents();
      });
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['type'] == 'chat') {
        NotificationService.showChatNotification(message);
      } else {
        NotificationService.showNotification(message);
      }
    });
  }

  void _startAppStatusGuard() {
    _appStatusSubscription?.cancel();
    _appStatusSubscription = FirebaseFirestore.instance
        .collection('app_config')
        .doc('settings')
        .snapshots()
        .listen((snap) async {
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      if (data['isMaintenance'] == true) {
        _handleRedirection(GlobalMaintenanceScreen(
            message: data['maintenanceMessage'] ?? "App iri mu mavugurura..."));
        return;
      }
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;
      final String minVersion = data['minVersion'] ?? currentVersion;
      if (_isVersionLower(currentVersion, minVersion)) {
        _handleRedirection(const UpdateGuardScreen(daysLeft: 0));
      }
    });
  }

  bool _isVersionLower(String current, String min) {
    try {
      List<int> c = current.split('.').map(int.parse).toList();
      List<int> m = min.split('.').map(int.parse).toList();
      for (int i = 0; i < c.length && i < m.length; i++) {
        if (c[i] < m[i]) return true;
        if (c[i] > m[i]) return false;
      }
      return m.length > c.length;
    } catch (e) {
      return false;
    }
  }

  void _stopAllGuards() async {
    _securitySubscription?.cancel();
    _deviceConflictSubscription?.cancel();
    _appStatusSubscription?.cancel();
    final prefs = await sp.SharedPreferences.getInstance();
    await prefs.remove('current_user_uid');
    await prefs.remove('is_profile_complete');
  }

  void _startGlobalSecurityGuard() {
    _securitySubscription?.cancel();
    _deviceConflictSubscription?.cancel();
    _securitySubscription = presenceService.banStatusStream.listen((isBlocked) {
      if (isBlocked && mounted) _handleRedirection(const UserBlockedScreen());
    });
    _deviceConflictSubscription =
        presenceService.deviceConflictStream.listen((hasConflict) {
      if (hasConflict && mounted) _handleForceLogout();
    });
  }

  void _handleForceLogout() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    String message = lang.t('security_force_logout');
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      _handleRedirection(const WelcomeScreen());
      Future.delayed(const Duration(milliseconds: 500), () {
        if (GlobalNavigator.navigatorKey.currentContext != null) {
          ScaffoldMessenger.of(GlobalNavigator.navigatorKey.currentContext!)
              .showSnackBar(
            SnackBar(
                content: Text(message),
                backgroundColor: Colors.redAccent,
                duration: const Duration(seconds: 8)),
          );
        }
      });
    }
  }

  Future<void> _requestAndroidPermissions() async {
    if (Platform.isAndroid) await Permission.notification.request();
  }

  void _handleRedirection(Widget screen) {
    GlobalNavigator.navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (c) => screen),
      (r) => false,
    );
  }

  Future<void> _initDynamicLinks() async {
    try {
      final PendingDynamicLinkData? initialLink =
          await FirebaseDynamicLinks.instance.getInitialLink();
      if (initialLink != null) _handleIncomingLink(initialLink.link);
      FirebaseDynamicLinks.instance.onLink
          .listen((data) => _handleIncomingLink(data.link));
    } catch (_) {}
  }

  void _handleIncomingLink(Uri deepLink) {
    String link = deepLink.toString();
    if (FirebaseAuth.instance.isSignInWithEmailLink(link)) {
      _handleEmailSignIn(link);
    } else if (deepLink.path.contains('/post') &&
        deepLink.queryParameters.containsKey('id')) {
      _safeNavigateToPost(deepLink.queryParameters['id']!);
    }
  }

  Future<void> _handleEmailSignIn(String emailLink) async {
    try {
      final prefs = await sp.SharedPreferences.getInstance();
      String? savedEmail = prefs.getString('email_for_login');
      if (savedEmail != null) {
        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailLink(email: savedEmail, emailLink: emailLink);
        if (userCredential.user != null) {
          await prefs.remove('email_for_login');
          _handleRedirection(const HomeScreen());
        }
      }
    } catch (_) {}
  }

  Future<void> _handlePlatformIntents() async {
    try {
      final Map<dynamic, dynamic>? sharedData =
          await platform.invokeMethod('getSharedData');
      if (sharedData == null || sharedData['value'] == null) return;
      String value = sharedData['value'] ?? '';
      if (sharedData['type'] == "share") {
        final Map<String, dynamic> msg = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'message': value,
          'messageType': 'text',
          'senderID': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          'timestamp': DateTime.now().millisecondsSinceEpoch
        };
        GlobalNavigator.navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (context) => ForwardScreen(messagesToForward: [msg])));
      }
    } on PlatformException catch (e) {
      debugPrint("Native Channel Error: ${e.message}");
    } catch (e) {
      debugPrint("Shared Data error: $e");
    }
  }

  void _safeNavigateToPost(String postId) {
    Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (GlobalNavigator.navigatorKey.currentState != null &&
          FirebaseAuth.instance.currentUser != null) {
        GlobalNavigator.navigatorKey.currentState!.push(MaterialPageRoute(
            builder: (context) => TangazaStarScreen(targetPostId: postId)));
        timer.cancel();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      presenceService.goOnline();
      _handlePlatformIntents();
      try {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } catch (_) {}
    } else {
      presenceService.goOffline();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _securitySubscription?.cancel();
    _deviceConflictSubscription?.cancel();
    _authSubscription?.cancel();
    _appStatusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    return MaterialApp(
      navigatorKey: GlobalNavigator.navigatorKey,
      title: 'Jembe Talk',
      debugShowCheckedModeBanner: false,
      themeMode: themeManager.themeMode,
      theme: themeManager.getLightTheme,
      darkTheme: themeManager.getDarkTheme,
      routes: {
        '/settings': (context) => const SettingsScreen(),
        '/home': (context) => const HomeScreen(),
      },
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.0)),
          child: SafeArea(top: false, bottom: true, child: child!),
        );
      },
      home: const AuthGate(),
    );
  }
}

// --- 🔥 FINAL STABLE AUTH GATE 🔥 ---
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription? _rtdbSubscription;
  bool? _isLocalProfileComplete;

  @override
  void initState() {
    super.initState();
    _loadInitialCache();
  }

  Future<void> _loadInitialCache() async {
    final prefs = await sp.SharedPreferences.getInstance();
    if (mounted)
      setState(() => _isLocalProfileComplete =
          prefs.getBool('is_profile_complete') ?? false);
  }

  void _listenToSecurity(String uid) {
    _rtdbSubscription?.cancel();
    _rtdbSubscription = FirebaseDatabase.instance
        .ref('status/$uid')
        .onValue
        .listen((event) async {
      if (!mounted) return;
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null || data['is_deleted'] == true) {
        _forceSignOut();
      }
    });
  }

  Future<void> _forceSignOut() async {
    // 🔥 FIXED PREFIX: sp.SharedPreferences (Rimwe gusa)
    final prefs = await sp.SharedPreferences.getInstance();
    await prefs.remove('is_profile_complete');
    await FirebaseAuth.instance.signOut();
  }

  @override
  void dispose() {
    _rtdbSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Scaffold(
              body:
                  Center(child: CircularProgressIndicator(color: Colors.teal)));

        final user = snapshot.data;
        if (user == null) return const WelcomeScreen();
        if (!user.emailVerified)
          return EmailVerificationScreen(email: user.email ?? "");

        _listenToSecurity(user.uid);

        if (_isLocalProfileComplete == true) return const HomeScreen();

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (ctx, docSnap) {
            if (docSnap.connectionState == ConnectionState.waiting)
              return const Scaffold(
                  body: Center(
                      child: CircularProgressIndicator(color: Colors.teal)));

            if (!docSnap.hasData || !docSnap.data!.exists) {
              _forceSignOut();
              return const WelcomeScreen();
            }

            final userData = docSnap.data!.data() as Map<String, dynamic>?;
            if (userData == null ||
                userData['phoneNumber'] == null ||
                userData['displayName'] == null) {
              return const ProfileSetupScreen();
            }

            _markCompleteLocally();
            return const HomeScreen();
          },
        );
      },
    );
  }

  void _markCompleteLocally() async {
    final prefs = await sp.SharedPreferences.getInstance();
    await prefs.setBool('is_profile_complete', true);
  }
}

class GlobalMaintenanceScreen extends StatelessWidget {
  final String message;
  const GlobalMaintenanceScreen({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFF1C2935),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.settings_suggest_rounded,
                          color: Colors.amber, size: 100),
                      const SizedBox(height: 30),
                      const Text("Jembe Talk",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      Text(message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 16))
                    ]))));
  }
}
