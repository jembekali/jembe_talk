// lib/home_screen.dart (VERSION 32.36 - SMOOTH TAB TRANSITIONS)

import 'dart:async';
import 'dart:io';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:jembe_talk/models/home_models.dart';
import 'package:jembe_talk/tabs/chats_tab.dart';
import 'package:jembe_talk/tabs/contacts_tab.dart';
import 'package:jembe_talk/tabs/tv_tab.dart';
import 'package:jembe_talk/tangaza_star/feed_manager.dart';

import 'package:jembe_talk/main.dart';
import 'package:jembe_talk/settings_screen.dart';
import 'package:jembe_talk/star_day_screen.dart';
import 'package:jembe_talk/tangaza_star/tangaza_star_screen.dart';
import 'package:jembe_talk/unified_notifications_screen.dart';
import 'package:jembe_talk/welcome_screen.dart';
import 'package:jembe_talk/profile_setup_screen.dart';
import 'package:jembe_talk/language_provider.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/chat_repository.dart';
import 'package:jembe_talk/services/sync_service.dart';
import 'package:jembe_talk/services/audio_service.dart';
import 'package:jembe_talk/services/presence_service.dart';
import 'package:jembe_talk/user_blocked_screen.dart';
import 'package:jembe_talk/services/update_service.dart';
import 'package:jembe_talk/screens/update_guard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late PageController _pageController;
  int _currentIndex = 0;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ChatRepository _chatRepository = ChatRepository();
  final AudioPlayerService _notifPlayer = AudioPlayerService();

  String? _backgroundImagePath;
  final ValueNotifier<List<ChatData>> _chatsNotifier =
      ValueNotifier<List<ChatData>>([]);
  final ValueNotifier<List<ChatData>> _contactsNotifier =
      ValueNotifier<List<ChatData>>([]);

  final StreamController<int> _unreadChatsCountController =
      StreamController<int>.broadcast();
  Stream<int>? _totalUnreadCountStream;
  StreamSubscription? _userChangesSubscription,
      _syncServiceSubscription,
      _broadcastSubscription,
      _securitySub;
  Stream<bool>? _hasUnreadStarNotificationStream;

  final List<String> _tabOrder = const [
    'chats',
    'contacts',
    'posts',
    'tv',
    'settings'
  ];
  List<dynamic> _myBlockedUsers = [];
  double _dockBottom = 45.0;
  bool _softUpdateSkipped = false;
  Timer? _refreshDebouncer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController = PageController(initialPage: _currentIndex);
    _initialSetup();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    context.read<FeedManager>().forceCleanup();
    PaintingBinding.instance.imageCache.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      presenceService.initialize();
      syncService.start();
      _updateUnreadCount();
    } else if (state == AppLifecycleState.paused) {
      context.read<FeedManager>().pauseAll();
    }
  }

  void _initialSetup() async {
    await _loadWallpaper();
    await _loadDataFromLocalDb();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runBackgroundSecurityChecks();
      _startBackgroundServices();
      _checkProfileIntegrity();
      Future.delayed(const Duration(seconds: 3), () => _handleManualSync());
    });
  }

  void _runBackgroundSecurityChecks() {
    final user = _auth.currentUser;
    if (user == null) return;
    _securitySub = FirebaseDatabase.instanceFor(
            app: Firebase.app(),
            databaseURL: "https://jembe-talk-1-default-rtdb.firebaseio.com")
        .ref('app_settings')
        .onValue
        .listen((event) async {
      if (!mounted) return;
      if (event.snapshot.exists) {
        final settings = Map<String, dynamic>.from(event.snapshot.value as Map);
        if (settings['maintenance_mode'] == true) {
          _redirect(GlobalMaintenanceScreen(
              message: settings['maintenance_message'] ?? "Coming back soon!"));
          return;
        }
        final pkg = await PackageInfo.fromPlatform();
        if (UpdateService.isVersionOlder(
            pkg.version, settings['latest_version'] ?? pkg.version)) {
          int daysLeft = UpdateService.getRemainingDays(
              settings['release_date'] ?? DateTime.now().toIso8601String());
          if (daysLeft <= 0) {
            _redirect(const UpdateGuardScreen(daysLeft: 0, forceUpdate: true));
          } else if (!_softUpdateSkipped) {
            _redirect(UpdateGuardScreen(
                daysLeft: daysLeft,
                forceUpdate: false,
                onSkip: () {
                  setState(() => _softUpdateSkipped = true);
                  Navigator.pop(context);
                }));
          }
        }
      }
    });
    _firestore.collection('users').doc(user.uid).snapshots().listen((snap) {
      if (mounted && snap.exists && snap.data()?['isDisabled'] == true) {
        _redirect(const UserBlockedScreen());
      }
    });
  }

  void _redirect(Widget screen) {
    if (mounted)
      Navigator.pushAndRemoveUntil(
          context, MaterialPageRoute(builder: (c) => screen), (r) => false);
  }

  void _startBackgroundServices() {
    final user = _auth.currentUser;
    if (user == null) return;
    presenceService.initialize();
    _listenToMyBlockedUsers();
    syncService.start();
    _listenForUserChanges();
    _initializeTotalUnreadStream();
    _initializeStarNotificationStream();
    _setupSyncListener();
    _listenForGlobalBroadcasts();
    _updateFCMToken();
    _updateUnreadCount();
    FirebaseMessaging.instance.subscribeToTopic("all_users");
    FlutterAppBadger.isAppBadgeSupported().then((sup) {
      if (sup) FlutterAppBadger.removeBadge();
    });
  }

  void _setupSyncListener() {
    _syncServiceSubscription =
        syncService.uiMessageUpdateStream.listen((event) async {
      if (!mounted) return;
      if (event == "refresh_ui" ||
          event.startsWith("refresh") ||
          event.startsWith("message_received") ||
          event.startsWith("status_updated")) {
        _handleRefreshWithDebounce();
      }
      _updateUnreadCount();
      if (event.startsWith("message_received") &&
          syncService.currentActiveChatId == null) {
        _notifPlayer.playNotificationSound('assets/audio/incoming_sound.mp3');
      }
    });
  }

  void _handleRefreshWithDebounce() {
    if (_refreshDebouncer?.isActive ?? false) _refreshDebouncer!.cancel();
    _refreshDebouncer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _loadDataFromLocalDb();
    });
  }

  Future<void> _updateUnreadCount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final count = await _dbHelper.getTotalUnreadCount(user.uid);
    if (!_unreadChatsCountController.isClosed)
      _unreadChatsCountController.add(count);
  }

  void _updateFCMToken() async {
    final user = _auth.currentUser;
    if (user == null) return;
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _firestore.collection('users').doc(user.uid).set(
          {'fcmToken': token, 'lastUpdated': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    }
  }

  void _listenForGlobalBroadcasts() {
    _broadcastSubscription = _firestore
        .collection('global_broadcasts')
        .doc('latest')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) _handleRefreshWithDebounce();
    });
  }

  void _listenForUserChanges() {
    final user = _auth.currentUser;
    if (user == null) return;
    _userChangesSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists && mounted) {
        final data = Map<String, dynamic>.from(snapshot.data()!);
        data['id'] = user.uid;
        await _dbHelper.saveJembeContact(data);
      }
    });
  }

  Future<void> _loadDataFromLocalDb() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      final recent = await _chatRepository.getAllRecentChats(currentUser.uid);
      final matchedContacts =
          await _chatRepository.getAllMatchedContacts(currentUser.uid);
      if (mounted) {
        _chatsNotifier.value = List<ChatData>.from(recent);
        _contactsNotifier.value = List<ChatData>.from(matchedContacts);
      }
    } catch (e) {
      log("Error loading DB: $e");
    }
  }

  Future<void> _handleManualSync() async {
    if (await FlutterContacts.requestPermission()) {
      final phoneContacts =
          await FlutterContacts.getContacts(withProperties: true);
      final Map<String, String> localContactsMap = {};
      for (var contact in phoneContacts) {
        for (var phone in contact.phones) {
          String cleanNum = phone.number.replaceAll(RegExp(r'\s+'), '');
          if (cleanNum.isNotEmpty)
            localContactsMap[cleanNum] = contact.displayName;
        }
      }
      if (localContactsMap.isNotEmpty) {
        await _chatRepository.warmUpMatchedContacts(localContactsMap);
        _handleRefreshWithDebounce();
      }
    }
  }

  void _listenToMyBlockedUsers() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _firestore
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted)
        setState(() {
          _myBlockedUsers = snapshot.data()?['blockedUsers'] as List? ?? [];
        });
    });
  }

  void _initializeTotalUnreadStream() {
    _totalUnreadCountStream = _firestore
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .asyncMap((snapshot) async {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('lastReadAnnouncementTimestamp') ?? 0;
      return snapshot.docs.where((doc) {
        final t = doc.data()['createdAt'] as Timestamp?;
        return t != null && t.millisecondsSinceEpoch > last;
      }).length;
    });
  }

  void _initializeStarNotificationStream() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _hasUnreadStarNotificationStream = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: currentUser.uid)
        .where('type', isEqualTo: 'star_winner')
        .where('isRead', isEqualTo: false)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty);
  }

  String _getCurrentDayKey() {
    switch (DateTime.now().weekday) {
      case 1:
        return 'mon';
      case 2:
        return 'tue';
      case 3:
        return 'wed';
      case 4:
        return 'thu';
      case 5:
        return 'fri';
      case 6:
        return 'sat';
      case 7:
        return 'sun';
      default:
        return 'mon';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);
    final allTabs = {
      'chats': TabItem(
          id: 'chats',
          label: lang.t('chats'),
          icon: Icons.chat_bubble_outline_rounded,
          screen: ChatsTab(
              chatsNotifier: _chatsNotifier,
              onRefresh: _loadDataFromLocalDb,
              myBlockedUsers: _myBlockedUsers)),
      'contacts': TabItem(
          id: 'contacts',
          label: lang.t('contacts'),
          icon: Icons.people_outline_rounded,
          screen: ContactsTab(
              contactsNotifier: _contactsNotifier,
              onRefresh: _loadDataFromLocalDb)),
      'posts': TabItem(
          id: 'posts',
          label: "Posts",
          icon: Icons.auto_awesome_motion_rounded,
          screen: const TangazaStarScreen()),
      'tv': TabItem(
          id: 'tv',
          label: lang.t('tv'),
          icon: Icons.tv_rounded,
          screen: const TVTab()),
      'settings': TabItem(
          id: 'settings',
          label: lang.t('settings'),
          icon: Icons.settings_rounded,
          screen: const SettingsScreen()),
    };
    final orderedTabs = _tabOrder.map((id) => allTabs[id]!).toList();
    final bool isPostsTab = _currentIndex == 2;

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _pageController.animateToPage(0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic);
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: isPostsTab ? null : _buildCustomAppBar(context),
        body: Stack(children: [
          if (_backgroundImagePath != null &&
              File(_backgroundImagePath!).existsSync())
            Positioned.fill(
                child: Image.file(File(_backgroundImagePath!),
                    fit: BoxFit.cover,
                    color: Colors.black.withAlpha(140),
                    colorBlendMode: BlendMode.darken,
                    cacheWidth: 400))
          else
            Container(color: theme.scaffoldBackgroundColor),

          RepaintBoundary(
            child: PageView.builder(
              controller: _pageController,
              itemCount: orderedTabs.length,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (i) {
                // KOSORA FREEZE:
                // 1. Niba avuye kuri Posts (index 2), hagarika audio ako kanya
                if (_currentIndex == 2 && i != 2) {
                  context.read<FeedManager>().pauseAll();
                }

                setState(() => _currentIndex = i);

                // 2. Niba agiye kuri Posts (index 2), iha UI akanya ko kurangiza transition
                // mbere yo gutangiza video controllers.
                if (i == 2) {
                  Future.delayed(const Duration(milliseconds: 450), () {
                    if (mounted && _currentIndex == 2) {
                      context.read<FeedManager>().resumeActive();
                    }
                  });
                }
              },
              itemBuilder: (context, index) =>
                  RepaintBoundary(child: orderedTabs[index].screen),
            ),
          ),

          // Floating Dock
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            bottom: isPostsTab ? -100 : _dockBottom,
            left: 15,
            right: 15,
            child: RepaintBoundary(
              child: Container(
                height: 68,
                decoration: BoxDecoration(
                    color: Colors.black.withAlpha(235),
                    borderRadius: BorderRadius.circular(35),
                    border: Border.all(color: Colors.white24, width: 1.2)),
                child: Row(
                  children: [
                    for (int i = 0; i < orderedTabs.length; i++)
                      Expanded(
                        child: InkWell(
                          onTap: () => _pageController.animateToPage(i,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOutCubic),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (orderedTabs[i].id == 'posts')
                                  const Badge(
                                      label: Text("99+"),
                                      backgroundColor: Colors.red,
                                      child: Icon(
                                          Icons.auto_awesome_motion_rounded,
                                          color: Colors.white,
                                          size: 24))
                                else if (orderedTabs[i].id == 'chats')
                                  StreamBuilder<int>(
                                      stream:
                                          _unreadChatsCountController.stream,
                                      builder: (c, snap) => Badge(
                                          label:
                                              Text((snap.data ?? 0).toString()),
                                          isLabelVisible: (snap.data ?? 0) > 0,
                                          child: Icon(orderedTabs[i].icon,
                                              color: _currentIndex == i
                                                  ? theme.colorScheme.secondary
                                                  : Colors.white)))
                                else
                                  Icon(orderedTabs[i].icon,
                                      color: _currentIndex == i
                                          ? theme.colorScheme.secondary
                                          : Colors.white),
                                Text(orderedTabs[i].label,
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: _currentIndex == i
                                            ? theme.colorScheme.secondary
                                            : Colors.white70))
                              ]),
                        ),
                      )
                  ],
                ),
              ),
            ),
          )
        ]),
      ),
    );
  }

  PreferredSizeWidget _buildCustomAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final lang = Provider.of<LanguageProvider>(context);
    return PreferredSize(
      preferredSize: const Size.fromHeight(115),
      child: Container(
        color: theme.appBarTheme.backgroundColor?.withAlpha(245),
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const SizedBox(width: 50),
            Row(children: [
              Text("Jembe Talk",
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color)),
              const SizedBox(width: 8),
              StreamBuilder<int>(
                  stream: _totalUnreadCountStream,
                  builder: (context, snapshot) {
                    final unreadCount = snapshot.data ?? 0;
                    return Badge(
                        isLabelVisible: unreadCount > 0,
                        label: Text(unreadCount.toString()),
                        child: InkWell(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (c) =>
                                        const UnifiedNotificationsScreen())),
                            child: Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Icon(Icons.notifications_none,
                                    size: 28, color: theme.iconTheme.color))));
                  })
            ]),
            IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showMainMenu(context))
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: InkWell(
                  onTap: _navigateToDayScreen,
                  child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withAlpha(140),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                              color:
                                  theme.colorScheme.secondary.withAlpha(76))),
                      child: StreamBuilder<bool>(
                          stream: _hasUnreadStarNotificationStream,
                          builder: (c, snap) {
                            final isWinner = snap.data ?? false;
                            String buttonLabel = isWinner
                                ? lang.t('winner').toUpperCase()
                                : lang.t(_getCurrentDayKey()).toUpperCase();
                            return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(buttonLabel,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.2,
                                          color: isWinner
                                              ? Colors.pinkAccent
                                              : theme
                                                  .textTheme.bodyLarge?.color)),
                                  const SizedBox(width: 10),
                                  const FaIcon(FontAwesomeIcons.solidStar,
                                      color: Colors.amber, size: 20)
                                ]);
                          }))),
            ),
          )
        ]),
      ),
    );
  }

  void _navigateToDayScreen() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    context.read<FeedManager>().pauseAll();
    await Navigator.push(
        context, MaterialPageRoute(builder: (c) => StarDayScreen(userId: uid)));
    final snap = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('type', isEqualTo: 'star_winner')
        .where('isRead', isEqualTo: false)
        .get();
    for (var d in snap.docs) {
      d.reference.update({'isRead': true});
    }
  }

  void _showMainMenu(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showMenu(
        context: context,
        position: const RelativeRect.fromLTRB(100, 80, 0, 0),
        items: [
          PopupMenuItem(
              onTap: () => _showWallpaperDialog(),
              child: ListTile(
                  leading: const Icon(Icons.wallpaper),
                  title: Text(lang.t('wallpaper')))),
          PopupMenuItem(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (c) => const SettingsScreen())),
              child: ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text(lang.t('settings'))))
        ]);
  }

  void _showWallpaperDialog() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
            title: Text(lang.t('wallpaper')),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.photo),
                  title: Text(lang.t('wallpaper_change')),
                  onTap: () async {
                    Navigator.pop(context);
                    final file = await ImagePicker()
                        .pickImage(source: ImageSource.gallery);
                    if (file != null) {
                      (await SharedPreferences.getInstance())
                          .setString('homeWallpaperPath', file.path);
                      setState(() => _backgroundImagePath = file.path);
                    }
                  }),
              if (_backgroundImagePath != null)
                ListTile(
                    leading: const Icon(Icons.delete_forever,
                        color: Colors.redAccent),
                    title: Text(lang.t('wallpaper_delete')),
                    onTap: () async {
                      Navigator.pop(context);
                      (await SharedPreferences.getInstance())
                          .remove('homeWallpaperPath');
                      setState(() => _backgroundImagePath = null);
                    })
            ])));
  }

  Future<void> _loadWallpaper() async {
    final p = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _backgroundImagePath = p.getString('homeWallpaperPath'));
  }

  void _checkProfileIntegrity() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists && mounted && (doc.data()?['displayName'] ?? "").isEmpty) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (c) => const ProfileSetupScreen()));
    }
  }

  @override
  void dispose() {
    _refreshDebouncer?.cancel();
    _pageController.dispose();
    _unreadChatsCountController.close();
    _userChangesSubscription?.cancel();
    _syncServiceSubscription?.cancel();
    _broadcastSubscription?.cancel();
    _securitySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
