// lib/main.dart (FINAL STABLE VERSION - WELCOME FLOW FIXED)

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/presence_service.dart';
import 'package:jembe_talk/services/sync_service.dart';
import 'package:jembe_talk/services/notification_service.dart'; 
import 'package:jembe_talk/tangaza_star/feed_manager.dart';
import 'package:jembe_talk/tangaza_star/tangaza_star_screen.dart'; 
import 'package:jembe_talk/theme_manager.dart';
import 'package:jembe_talk/welcome_screen.dart'; // <<< WelcomeScreen // <<< UnifiedAuthScreen
import 'package:jembe_talk/profile_setup_screen.dart';
import 'package:jembe_talk/email_verification_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:animations/animations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/forward_screen.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart'; 
import 'package:permission_handler/permission_handler.dart'; 

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
}

class GlobalNavigator {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

void main() async {
  // 1. Gufungura amarembo ya Flutter vuba
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Kora edgeToEdge settings ako kanya
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent, 
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false, 
  ));

  try {
    // 3. Tangiza Firebase
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    
    // 🔥 OPTIMIZATION: Configure Firestore cache size
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    final prefs = await SharedPreferences.getInstance();
    
    // 🚀 ANDROID 14 FIX: Request notification permission before services start
    if (Platform.isAndroid) {
      unawaited(Permission.notification.request());
    }

    // 🔥 INSTANT BOOT: Ibi bintu nibikore mu buryo bwa "Background"
    unawaited(initializeDateFormatting('fr_FR', null));
    unawaited(NotificationService.initialize());
    if (Platform.isAndroid) unawaited(MediaStore.ensureInitialized());
    
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // 4. Tangiza amasevisi yo muri background bituje
    _runStartupBackgroundTasks();

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
    final fallbackPrefs = await SharedPreferences.getInstance();
    runApp(MultiProvider(providers: [
      ChangeNotifierProvider(create: (_) => ThemeManager(fallbackPrefs)), 
      ChangeNotifierProvider(create: (_) => FeedManager()), 
      ChangeNotifierProvider(create: (_) => LanguageProvider())
    ], child: const MyApp()));
  }
}

void _runStartupBackgroundTasks() {
  syncService.start();
  FlutterAppBadger.isAppBadgeSupported().then((supported) {
    if (supported) FlutterAppBadger.removeBadge();
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final PresenceService _presenceService = PresenceService();
  static const platform = MethodChannel('app.channel.shared.data');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presenceService.initialize();
    _initDynamicLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePlatformIntents());
  }

  // --- 1. HANDLE DYNAMIC LINKS (POSTS & AUTH) ---
  Future<void> _initDynamicLinks() async {
    try {
      final PendingDynamicLinkData? initialLink = await FirebaseDynamicLinks.instance.getInitialLink();
      if (initialLink != null) _handleIncomingLink(initialLink.link);
      FirebaseDynamicLinks.instance.onLink.listen((data) => _handleIncomingLink(data.link));
    } catch (e) {}
  }

  void _handleIncomingLink(Uri deepLink) {
    String link = deepLink.toString();
    if (FirebaseAuth.instance.isSignInWithEmailLink(link)) {
      _handleEmailSignIn(link);
    } 
    else if (deepLink.path.contains('/post') && deepLink.queryParameters.containsKey('id')) {
      _safeNavigateToPost(deepLink.queryParameters['id']!);
    }
  }

  // --- 2. LOGIC YO KWINJIZA UMUNTU KORESHEJE LINK ---
  Future<void> _handleEmailSignIn(String emailLink) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedEmail = prefs.getString('email_for_login');
      String? savedPhone = prefs.getString('phone_for_login');
      if (savedEmail != null) {
        UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailLink(
          email: savedEmail,
          emailLink: emailLink,
        );
        if (userCredential.user != null) {
          await prefs.remove('email_for_login');
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).get();
          if (userDoc.exists) {
            GlobalNavigator.navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (c) => const HomeScreen()), (r) => false);
          } else {
            if (savedPhone != null) {
              await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
                'uid': userCredential.user!.uid, 'email': savedEmail, 'phoneNumber': savedPhone, 'createdAt': FieldValue.serverTimestamp(),
              });
            }
            GlobalNavigator.navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (c) => const ProfileSetupScreen()), (r) => false);
          }
        }
      }
    } catch (e) {}
  }

  Future<void> _handlePlatformIntents() async {
    try {
      final Map<dynamic, dynamic>? sharedData = await platform.invokeMethod('getSharedData');
      if (sharedData == null || sharedData['value'] == null) return;
      String type = sharedData['type'] ?? '';
      String value = sharedData['value'] ?? '';
      if (type == "view") {
        if (value.contains('/post') && value.contains('id=')) {
          final uri = Uri.parse(value);
          final postId = uri.queryParameters['id'];
          if (postId != null) _safeNavigateToPost(postId);
        }
      } 
      else if (type == "share") {
        final Map<String, dynamic> msg = { 
          'id': DateTime.now().millisecondsSinceEpoch.toString(), 
          'message': value, 'messageType': 'text', 'senderID': FirebaseAuth.instance.currentUser?.uid ?? 'unknown', 'timestamp': DateTime.now().millisecondsSinceEpoch 
        };
        GlobalNavigator.navigatorKey.currentState?.push(MaterialPageRoute(builder: (context) => ForwardScreen(messagesToForward: [msg])));
      }
    } catch (e) {}
  }

  void _safeNavigateToPost(String postId) {
    Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (GlobalNavigator.navigatorKey.currentState != null && FirebaseAuth.instance.currentUser != null) {
        GlobalNavigator.navigatorKey.currentState!.push(MaterialPageRoute(builder: (context) => TangazaStarScreen(targetPostId: postId)));
        timer.cancel();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { 
      _presenceService.goOnline(); _handlePlatformIntents(); SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } 
    else { _presenceService.goOffline(); }
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }

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
      builder: (context, child) {
        return MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)), child: SafeArea(top: false, bottom: true, child: child!));
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // --- 🚀 KOSORA HANO: Banza WelcomeScreen kugira ngo abone indimi ---
        if (!snapshot.hasData) {
          return const WelcomeScreen(); 
        }

        final user = snapshot.data!;
        
        // NIBA ARI MUKWEMEZA EMAIL (Sensing)
        if (!user.emailVerified) {
          return EmailVerificationScreen(email: user.email ?? "");
        }

        // NIBA BYOSE ARI OK: Jya kuri Home
        return const HomeScreen();
      },
    );
  }
}