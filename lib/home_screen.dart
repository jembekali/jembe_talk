// lib/home_screen.dart (VERSION 29.9 - FIXED NOTIFICATION SOUND FOR NEW SYNC LOGIC)

import 'dart:async';
import 'dart:io';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// --- MODELS & TABS ---
import 'package:jembe_talk/models/home_models.dart';
import 'package:jembe_talk/tabs/chats_tab.dart';
import 'package:jembe_talk/tabs/contacts_tab.dart';
import 'package:jembe_talk/tabs/tv_tab.dart';

// --- SCREENS & SERVICES ---
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
  final ValueNotifier<List<ChatData>> _chatsNotifier = ValueNotifier<List<ChatData>>([]);
  final ValueNotifier<List<ChatData>> _contactsNotifier = ValueNotifier<List<ChatData>>([]);
  
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  
  final StreamController<int> _unreadChatsCountController = StreamController<int>.broadcast();
  Stream<int>? _totalUnreadCountStream;
  StreamSubscription? _userChangesSubscription, _syncServiceSubscription, _connectivitySub, _broadcastSubscription; 
  Stream<bool>? _hasUnreadStarNotificationStream;
  
  final List<String> _tabOrder = const ['chats', 'contacts', 'tv', 'settings'];
  List<dynamic> _myBlockedUsers = [];
  double _dockBottom = 45.0; 

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController = PageController(initialPage: _currentIndex);
    
    _searchController.addListener(() { if (mounted) setState(() => _searchQuery = _searchController.text); });

    _initialWhatsAppStart();
    WidgetsBinding.instance.addObserver(this);
  }

  void _initialWhatsAppStart() async {
    await _loadWallpaper();
    await _loadDataFromLocalDb(); 
    _startBackgroundServices();
    _checkProfileIntegrity();

    // Auto-sync contacts app ikifunguka
    Future.delayed(const Duration(seconds: 2), () => _handleManualSync());
  }

  void _startBackgroundServices() {
    final user = _auth.currentUser;
    if (user == null) return;

    _syncServiceSubscription?.cancel();
    _broadcastSubscription?.cancel();
    _userChangesSubscription?.cancel();

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
    FlutterAppBadger.isAppBadgeSupported().then((sup) { if (sup) FlutterAppBadger.removeBadge(); });
  }

  void _setupSyncListener() {
    _syncServiceSubscription = syncService.uiMessageUpdateStream.listen((event) async { 
      if (!mounted) return;
      await _loadDataFromLocalDb();
      _updateUnreadCount();

      // ✅ KOSORA HANO: Reba niba event itangiye na "message_received" (kuko ubu ifite na Room ID)
      if (event.startsWith("message_received")) {
        // Kina ijwi niba GUSA nta Chat ifunguye (uri kuri Home)
        if (syncService.currentActiveChatId == null) {
          _notifPlayer.playNotificationSound('assets/audio/incoming_sound.mp3');
        }
      }
    });
  }

  Future<void> _updateUnreadCount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final count = await _dbHelper.getTotalUnreadCount(user.uid);
    if (!_unreadChatsCountController.isClosed) _unreadChatsCountController.add(count);
  }

  void _updateFCMToken() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  void _listenForGlobalBroadcasts() {
    _broadcastSubscription = _firestore.collection('global_broadcasts').doc('latest').snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) _loadDataFromLocalDb();
    });
  }

  void _listenForUserChanges() {
    final user = _auth.currentUser;
    if (user == null) return;
    _userChangesSubscription = _firestore.collection('users').doc(user.uid).snapshots().listen((snapshot) async {
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
      final matchedContacts = await _chatRepository.getAllMatchedContacts(currentUser.uid);
      if (mounted) {
        _chatsNotifier.value = List<ChatData>.from(recent);
        _contactsNotifier.value = List<ChatData>.from(matchedContacts);
      }
    } catch (e) { log("Error loading DB: $e"); }
  }

  Future<void> _handleManualSync() async {
    if (await FlutterContacts.requestPermission()) {
      final phoneContacts = await FlutterContacts.getContacts(withProperties: true);
      final Map<String, String> localContactsMap = {};
      for (var contact in phoneContacts) {
        for (var phone in contact.phones) {
          String cleanNum = phone.number.replaceAll(RegExp(r'\s+'), '');
          if (cleanNum.isNotEmpty) localContactsMap[cleanNum] = contact.displayName;
        }
      }
      if (localContactsMap.isNotEmpty) {
        await _chatRepository.warmUpMatchedContacts(localContactsMap);
        await _loadDataFromLocalDb();
      }
    }
  }

  void _listenToMyBlockedUsers() {
    final currentUser = _auth.currentUser; if (currentUser == null) return;
    _firestore.collection('users').doc(currentUser.uid).snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) setState(() { _myBlockedUsers = snapshot.data()?['blockedUsers'] as List? ?? []; });
    });
  }

  void _initializeTotalUnreadStream() {
    _totalUnreadCountStream = _firestore.collection('announcements').orderBy('createdAt', descending: true).limit(50).snapshots().asyncMap((snapshot) async {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('lastReadAnnouncementTimestamp') ?? 0;
      return snapshot.docs.where((doc) { 
        final t = doc.data()['createdAt'] as Timestamp?; 
        return t != null && t.millisecondsSinceEpoch > last; 
      }).length;
    });
  }

  void _initializeStarNotificationStream() {
    final currentUser = _auth.currentUser; if (currentUser == null) return;
    _hasUnreadStarNotificationStream = _firestore.collection('notifications').where('userId', isEqualTo: currentUser.uid).where('type', isEqualTo: 'star_winner').where('isRead', isEqualTo: false).limit(1).snapshots().map((s) => s.docs.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); 
    final lang = Provider.of<LanguageProvider>(context);

    final allTabs = {
      'chats': TabItem(id: 'chats', label: lang.t('chats'), icon: Icons.chat_bubble_outline_rounded, screen: ChatsTab(searchQuery: _searchQuery, chatsNotifier: _chatsNotifier, onRefresh: _loadDataFromLocalDb, myBlockedUsers: _myBlockedUsers)),
      'contacts': TabItem(id: 'contacts', label: lang.t('contacts'), icon: Icons.people_outline_rounded, screen: ContactsTab(searchQuery: _searchQuery, contactsNotifier: _contactsNotifier, onRefresh: _loadDataFromLocalDb)),
      'tv': TabItem(id: 'tv', label: lang.t('tv'), icon: Icons.tv_rounded, screen: const TVTab()),
      'settings': TabItem(id: 'settings', label: lang.t('settings'), icon: Icons.settings_rounded, screen: const SettingsScreen()),
    };
    final orderedTabs = _tabOrder.map((id) => allTabs[id]!).toList();
    
    return Scaffold(
      extendBody: true, extendBodyBehindAppBar: true,
      appBar: _isSearching 
        ? AppBar(title: TextField(controller: _searchController, autofocus: true, decoration: InputDecoration(hintText: lang.t('search'))), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _isSearching = false))) 
        : _buildCustomAppBar(context),
      
      body: Stack(children: [
        Container(color: theme.scaffoldBackgroundColor),
        if (_backgroundImagePath != null && File(_backgroundImagePath!).existsSync()) 
          Image.file(File(_backgroundImagePath!), height: double.infinity, width: double.infinity, fit: BoxFit.cover, color: Colors.black.withAlpha(128), colorBlendMode: BlendMode.darken),
        
        PageView(
          controller: _pageController, 
          physics: const BouncingScrollPhysics(), 
          onPageChanged: (i) => setState(() => _currentIndex = i), 
          children: orderedTabs.map((t) => t.screen).toList()
        ),

        Positioned(
          bottom: _dockBottom, left: 20, right: 20, 
          child: GestureDetector(
            onVerticalDragUpdate: (details) { setState(() { _dockBottom -= details.delta.dy; if (_dockBottom < 20) _dockBottom = 20; if (_dockBottom > 300) _dockBottom = 300; }); },
            child: Container(
              height: 68, decoration: BoxDecoration(color: Colors.black.withAlpha(225), borderRadius: BorderRadius.circular(35), border: Border.all(color: Colors.white24, width: 1.5)),
              child: Row(
                children: [
                  for (int i = 0; i < orderedTabs.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => _pageController.jumpToPage(i), 
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          if (orderedTabs[i].id == 'chats') 
                            StreamBuilder<int>(
                              stream: _unreadChatsCountController.stream, 
                              builder: (c, snap) => Badge(label: Text((snap.data ?? 0).toString()), isLabelVisible: (snap.data ?? 0) > 0, child: Icon(orderedTabs[i].icon, color: _currentIndex == i ? theme.colorScheme.secondary : Colors.white))
                            )
                          else 
                            Icon(orderedTabs[i].icon, color: _currentIndex == i ? theme.colorScheme.secondary : Colors.white),
                          Text(orderedTabs[i].label, style: const TextStyle(fontSize: 10, color: Colors.white))
                        ]),
                      ),
                    )
                ],
              ),
            ),
          ),
        )
      ]),
    );
  }

  PreferredSizeWidget _buildCustomAppBar(BuildContext context) {
    final theme = Theme.of(context); 
    final lang = Provider.of<LanguageProvider>(context);
    return PreferredSize(
      preferredSize: const Size.fromHeight(120),
      child: Container(
        color: theme.appBarTheme.backgroundColor?.withAlpha(245), 
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const SizedBox(width: 50),
            Row(children: [
              Text("Jembe Talk", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
              const SizedBox(width: 8),
              StreamBuilder<int>(stream: _totalUnreadCountStream, builder: (context, snapshot) {
                final unreadCount = snapshot.data ?? 0;
                return Badge(isLabelVisible: unreadCount > 0, label: Text(unreadCount.toString()), child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const UnifiedNotificationsScreen())), child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(Icons.notifications_none, size: 28, color: theme.iconTheme.color))));
              })
            ]),
            IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _showMainMenu(context))
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), 
            child: Row(children: [
              Expanded(
                child: InkWell(
                  onTap: _navigateToDayScreen, 
                  child: Container(
                    padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: theme.colorScheme.surface.withAlpha(140), borderRadius: BorderRadius.circular(15), border: Border.all(color: theme.colorScheme.secondary.withAlpha(76))), 
                    child: StreamBuilder<bool>(
                      stream: _hasUnreadStarNotificationStream, 
                      builder: (c, snap) {
                        final isWinner = snap.data ?? false;
                        return FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(isWinner ? lang.t('winner').toUpperCase() : "Star Day", style: TextStyle(fontWeight: FontWeight.bold, color: isWinner ? Colors.pinkAccent : theme.textTheme.bodyLarge?.color)), const SizedBox(width: 6), const FaIcon(FontAwesomeIcons.solidStar, color: Colors.amber, size: 18)]));
                      }
                    )
                  )
                )
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const TangazaStarScreen())), 
                  child: Container(
                    padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: theme.colorScheme.surface.withAlpha(140), borderRadius: BorderRadius.circular(15), border: Border.all(color: theme.colorScheme.secondary.withAlpha(76))), 
                    child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Tangaza Star", style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)), const SizedBox(width: 6), const FaIcon(FontAwesomeIcons.solidStar, color: Colors.amber, size: 18)]))
                  )
                )
              ),
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _isSearching = true))
            ]),
          )
        ]),
      ),
    );
  }

  void _navigateToDayScreen() async {
    final uid = _auth.currentUser?.uid; if (uid == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (c) => StarDayScreen(userId: uid)));
    final snap = await _firestore.collection('notifications').where('userId', isEqualTo: uid).where('type', isEqualTo: 'star_winner').where('isRead', isEqualTo: false).get();
    for (var d in snap.docs) { d.reference.update({'isRead': true}); }
  }

  void _showMainMenu(BuildContext context) { 
    final lang = Provider.of<LanguageProvider>(context, listen: false); 
    showMenu(context: context, position: const RelativeRect.fromLTRB(100, 80, 0, 0), items: [ 
      PopupMenuItem(onTap: () => _showWallpaperDialog(), child: ListTile(leading: const Icon(Icons.wallpaper), title: Text(lang.t('wallpaper')))), 
      PopupMenuItem(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsScreen())), child: ListTile(leading: const Icon(Icons.settings), title: Text(lang.t('settings'))))
    ]); 
  }

  void _showWallpaperDialog() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showDialog(context: context, builder: (c) => AlertDialog(title: Text(lang.t('wallpaper')), content: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo), title: Text(lang.t('wallpaper_change')), onTap: () async {
        Navigator.pop(context); final file = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (file != null) { (await SharedPreferences.getInstance()).setString('wallpaperPath', file.path); setState(() => _backgroundImagePath = file.path); }
      }),
      if (_backgroundImagePath != null) ListTile(leading: const Icon(Icons.delete_forever, color: Colors.redAccent), title: Text(lang.t('wallpaper_delete')), onTap: () async {
        Navigator.pop(context); (await SharedPreferences.getInstance()).remove('wallpaperPath'); setState(() => _backgroundImagePath = null);
      })
    ])));
  }

  Future<void> _loadWallpaper() async { final p = await SharedPreferences.getInstance(); setState(() => _backgroundImagePath = p.getString('wallpaperPath')); }

  void _checkProfileIntegrity() async {
    final user = _auth.currentUser; if (user == null) return;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists && mounted && (doc.data()?['displayName'] ?? "").isEmpty) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const ProfileSetupScreen()));
    }
  }

  @override
  void dispose() {
    _pageController.dispose(); _searchController.dispose();
    _unreadChatsCountController.close();
    _userChangesSubscription?.cancel(); _syncServiceSubscription?.cancel(); 
    _broadcastSubscription?.cancel(); 
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}