import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Iyi irakenewe kuri MethodChannel
import 'package:jembe_talk/home_screen.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/presence_service.dart';
import 'package:jembe_talk/services/sync_service.dart';
import 'package:jembe_talk/tangaza_star/feed_manager.dart';
import 'package:jembe_talk/tangaza_star/star_post_detail_screen.dart'; // Iyi irakenewe niba unyuze muri Dynamic Links
import 'package:jembe_talk/theme_manager.dart';
import 'package:jembe_talk/welcome_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:animations/animations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/forward_screen.dart';
import 'package:jembe_talk/tangaza_star/tangaza_star_screen.dart'; // <--- NTIWIBAGIRWE IYI IMPORT

class GlobalNavigator {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

void main() async {
  // 1. Ibi bigomba kuba ibya mbere na mbere
  WidgetsFlutterBinding.ensureInitialized();

  // 2. UBURINZI BWA MEDIASTORE
  if (Platform.isAndroid) {
    try {
      await MediaStore.ensureInitialized();
    } catch (e) {
      debugPrint("IMBURU: MediaStore yanze gukora (MissingPluginException). App irakomeza: $e");
    }
  }

  // 3. Izindi Initializations zose
  try {
    await initializeDateFormatting('fr_FR', null);

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    final prefs = await SharedPreferences.getInstance();

    // Isuku ya database (Cleanup)
    try {
      final lastCleanup = prefs.getInt('last_cleanup_timestamp') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - lastCleanup > const Duration(days: 1).inMilliseconds) {
        await DatabaseHelper.instance.cleanupDeletedMessagesLog();
        await prefs.setInt('last_cleanup_timestamp', DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint("Ikosa ryo gukora Cleanup: $e");
    }

    // Gutangira Sync Service
    syncService.start();

    // 4. Fungura App
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

  } catch (e, stack) {
    // Niba hari ikintu gikomeye cyanze mbere yo kugera kuri runApp
    debugPrint("IKOSA RIKOMEYE MURI MAIN: $e");
    debugPrint(stack.toString());

    // Fallback niba Prefs zanze
    final fallbackPrefs = await SharedPreferences.getInstance();
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeManager(fallbackPrefs)),
          ChangeNotifierProvider(create: (_) => FeedManager()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: const MyApp(),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final PresenceService _presenceService = PresenceService();
  
  // Umuyoboro wo kuvugana na Android Native (Method Channel)
  static const platform = MethodChannel('app.channel.shared.data');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _presenceService.initialize();
    } catch (e) {
      debugPrint("Presence service error: $e");
    }
    
    // Tangira kumviriza Links zose (Share cyangwa Click)
    _initDynamicLinks();
    _checkSharedText();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  // HANO NIHO UBWENGE BWOSE BURI (Share vs Deep Link)
  Future<void> _checkSharedText() async {
    try {
      // Baza Android uti: "Hari icyo ufite?"
      final String? sharedData = await platform.invokeMethod('getSharedText');
      
      if (sharedData != null && sharedData.isNotEmpty) {
        debugPrint("Twakiriye Data ivuye kuri Android: $sharedData");
        
        // 1. REBA NIBA ARI LINK YA JEMBE TALK POST
        // Urugero: https://jembe-talk.web.app/post?id=12345
        if (sharedData.contains('jembe-talk.web.app/post') && sharedData.contains('id=')) {
           try {
             // Gerageza gukuramo ID
             // Turashaka ibiri inyuma ya 'id='
             final RegExp regExp = RegExp(r'[?&]id=([^&#]+)');
             final match = regExp.firstMatch(sharedData);
             final String? postId = match?.group(1);
             
             if (postId != null && postId.isNotEmpty) {
               debugPrint("Link ya Post yabonetse: $postId. Turi kujya muri Tangaza Star...");
               // Jya muri Tangaza Star
               _navigateToPost(postId);
               return; // Hagararira aha, ntuje muri Forward screen
             }
           } catch (e) {
             debugPrint("Ikosa ryo gusesengura ID ya link: $e");
           }
        }

        // 2. NIBA ATARI LINK YACU, NI SHARE ISANZWE (Forward)
        debugPrint("Iyi ni share isanzwe, turi kujya kuri Forward Screen.");
        final Map<String, dynamic> forwardedMessage = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'message': sharedData,
          'messageType': 'text',
          'senderID': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        GlobalNavigator.navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => ForwardScreen(messagesToForward: [forwardedMessage]),
          ),
        );
      }
    } on PlatformException catch (e) {
      debugPrint("Ikosa ryo kwakira data kuri channel: '${e.message}'.");
    }
  }

  // Uburyo bwa kera bwa Firebase Dynamic Links (Backup)
  Future<void> _initDynamicLinks() async {
    try {
      final PendingDynamicLinkData? initialLink = await FirebaseDynamicLinks.instance.getInitialLink();
      if (initialLink != null) {
        _handleDeepLink(initialLink.link);
      }

      FirebaseDynamicLinks.instance.onLink.listen((dynamicLinkData) {
        _handleDeepLink(dynamicLinkData.link);
      }).onError((error) {
        debugPrint('Ikosa ryo kwumviriza link: $error');
      });
    } catch (e) {
      debugPrint("Dynamic Links error: $e");
    }
  }

  void _handleDeepLink(Uri deepLink) {
    // Reba niba ari '/post' kandi ifite 'id'
    if (deepLink.path.contains('/post') && deepLink.queryParameters.containsKey('id')) {
      final String? postId = deepLink.queryParameters['id'];
      if (postId != null && postId.isNotEmpty) {
        _navigateToPost(postId);
      }
    }
  }

  // Function yihariye yo guhita ujya muri Tangaza Star
  void _navigateToPost(String postId) {
    debugPrint("Navigating to Tangaza Star Post ID: $postId");
    
    // Koresha Scheduler kugira ngo tubikore frame ikurikira niba app irimo kuza
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GlobalNavigator.navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => TangazaStarScreen(targetPostId: postId),
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _presenceService.goOnline();
      // Iyo App igarutse (ivuye kuri WhatsApp), ongera urebe niba hari link
      _checkSharedText();
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
      navigatorKey: GlobalNavigator.navigatorKey,
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
            return const Center(child: CircularProgressIndicator(color: Color(0xFF1E8449)));
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