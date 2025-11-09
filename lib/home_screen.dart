// lib/home_screen.dart (YAKOSOWE BURUNDU KURI PRESENCE)

import 'package:jembe_talk/services/firebase_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:animations/animations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:jembe_talk/loading_screen.dart';
import 'package:jembe_talk/network_video_player.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/message_status_service.dart';
import 'package:jembe_talk/services/presence_service.dart';
import 'package:jembe_talk/star_day_screen.dart';
import 'package:jembe_talk/tangaza_star/tangaza_star_screen.dart';
import 'package:jembe_talk/unified_notifications_screen.dart';
import 'package:jembe_talk/video_player_screen.dart'; 
import 'package:jembe_talk/welcome_screen.dart';
import 'package:liquid_pull_to_refresh/liquid_pull_to_refresh.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jembe_talk/chat_screen.dart';
import 'package:jembe_talk/contact_info_screen.dart';
import 'package:jembe_talk/settings_screen.dart';
import 'package:jembe_talk/online_contacts_screen.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

class TabItem {
  final String id;
  final String label;
  final IconData icon;
  final Widget screen;
  TabItem({required this.id, required this.label, required this.icon, required this.screen});
}

class _ChatData {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final String? phoneNumber;
  final int lastMessageTimestamp;
  final List<dynamic> blockedUsers;

  _ChatData({
    required this.userId, 
    required this.displayName, 
    this.photoUrl, 
    this.phoneNumber, 
    required this.lastMessageTimestamp,
    this.blockedUsers = const [],
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late PageController _pageController;
  int _currentIndex = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  String? _backgroundImagePath;

  final ValueNotifier<List<_ChatData>> _chatsNotifier = ValueNotifier<List<_ChatData>>([]);
  final ValueNotifier<List<_ChatData>> _contactsNotifier = ValueNotifier<List<_ChatData>>([]);

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Stream<int>? _totalUnreadCountStream;
  StreamSubscription? _userChangesSubscription;
  Stream<int>? _totalUnreadChatsCountStream;
  
  StreamSubscription? _allMessagesSubscription;
  StreamSubscription? _myBlockedUsersSubscription;

  late AnimationController _loveStarController;
  late Animation<double> _loveStarAnimation;

  Stream<bool>? _hasUnreadStarNotificationStream;

  List<String> _tabOrder = [];
  final List<String> _defaultTabOrder = ['chats', 'contacts', 'tv', 'settings'];
  bool _tabOrderLoaded = false;
  
  List<dynamic> _myBlockedUsers = [];

  final PresenceService _presenceService = PresenceService();

  @override
  void initState() {
    super.initState();
    
    FirebaseService().saveUserFcmToken();

    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);

    _presenceService.initialize();
    
    _loadInitialData();
    _loadTabOrder();
    _listenForUserChanges();
    
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      MessageStatusService.instance.initialize(currentUser.uid);
      _listenToMyBlockedUsers(); 
    }

    _listenForAllMessageChanges();
    _initializeTotalUnreadStream();
    _initializeTotalUnreadChatsStream();
    _searchController.addListener(() { if (mounted) setState(() => _searchQuery = _searchController.text); });
    _loveStarController = AnimationController(duration: const Duration(milliseconds: 7500), vsync: this)..repeat(reverse: true);
    _loveStarAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: _loveStarController, curve: Curves.easeInOut));
    _initializeStarNotificationStream();
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

  void _listenToMyBlockedUsers() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _myBlockedUsersSubscription?.cancel();
    _myBlockedUsersSubscription = _firestore.collection('users').doc(currentUser.uid).snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        final userData = snapshot.data();
        setState(() {
          _myBlockedUsers = userData?['blockedUsers'] as List<dynamic>? ?? [];
        });
      }
    });
  }
  
  Future<void> _loadInitialData() async {
    await _loadWallpaper();
    await _loadDataFromLocalDb();
    _syncAndLoadData();
  }
  
  Future<void> _loadDataFromLocalDb() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    final contactMapsFromDb = await _dbHelper.getJembeContacts();
    final phoneContactsMap = await _getPhoneContactsMap();
    
    List<_ChatData> chatsFromDb = [];
    List<_ChatData> contactsFromDb = [];
    
    for (var map in contactMapsFromDb) {
      if (map['userId'] != currentUser.uid) {
        String phoneNumber = map['phoneNumber'] ?? '';
        String normalizedPhoneNumber = _normalizePhoneNumber(phoneNumber);
        String displayNameToShow = phoneContactsMap[normalizedPhoneNumber] ?? map['displayName'] ?? phoneNumber;
        
        List<String> ids = [currentUser.uid, map['userId']];
        ids.sort();
        String chatRoomID = ids.join('_');
        final lastMessage = await _dbHelper.getLastMessage(chatRoomID);
        final lastMessageTimestamp = lastMessage?['timestamp'] as int? ?? 0;
        
        final blockedUsersJson = map['blockedUsers'];
        final blockedUsersList = (blockedUsersJson is String && blockedUsersJson.isNotEmpty) 
            ? jsonDecode(blockedUsersJson) 
            : [];
        
        final chatData = _ChatData(
          userId: map['userId'],
          displayName: displayNameToShow,
          photoUrl: map['photoUrl'],
          phoneNumber: phoneNumber,
          lastMessageTimestamp: lastMessageTimestamp,
          blockedUsers: blockedUsersList,
        );

        if (lastMessageTimestamp > 0) {
            chatsFromDb.add(chatData);
        }
        
        if (phoneContactsMap.containsKey(normalizedPhoneNumber)) {
          contactsFromDb.add(chatData);
        }
      }
    }
    
    chatsFromDb.sort((a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp));
    
    if (mounted) {
      _chatsNotifier.value = chatsFromDb;
      _contactsNotifier.value = contactsFromDb;
    }
  }

  Future<void> _refreshData() async {
    await _syncAndLoadData();
  }
  
  Future<void> _syncAndLoadData() async { 
    await _syncUsersFromFirebase(); 
    await _loadDataFromLocalDb();
  }

  void _listenForAllMessageChanges() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _allMessagesSubscription?.cancel();
    _allMessagesSubscription = _firestore
        .collectionGroup('messages')
        .where(Filter.or(
          Filter('receiverID', isEqualTo: currentUser.uid),
          Filter('senderID', isEqualTo: currentUser.uid),
        ))
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docChanges.isEmpty || !mounted) return;
      
      bool needsRefresh = false;

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final messageDoc = change.doc;
          final messageData = messageDoc.data();
          if (messageData != null) {
            final localMessage = Map<String, dynamic>.from(messageData);
            localMessage['id'] = messageDoc.id;
            if (messageDoc.reference.parent.parent != null) {
              localMessage['chatRoomID'] = messageDoc.reference.parent.parent!.id;
            } else { continue; }
            if (messageData['timestamp'] is Timestamp) {
              localMessage['timestamp'] = (messageData['timestamp'] as Timestamp).millisecondsSinceEpoch;
            }
            await _dbHelper.saveMessage(localMessage);
            needsRefresh = true;
          }
        }
      }

      if (needsRefresh && mounted) {
        await _loadDataFromLocalDb();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _searchController.dispose();
    _userChangesSubscription?.cancel();
    _allMessagesSubscription?.cancel();
    _myBlockedUsersSubscription?.cancel();
    _loveStarController.dispose();
    _chatsNotifier.dispose();
    _contactsNotifier.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (index == _currentIndex) return;
    if (_isSearching) { 
      setState(() { 
        _isSearching = false; 
        _searchController.clear(); 
      }); 
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOut,
    );
  }

  void _initializeTotalUnreadChatsStream() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final stream = _firestore.collectionGroup('messages').where('receiverID', isEqualTo: currentUser.uid).where('status', isNotEqualTo: 'seen').snapshots().map((snapshot) {
      final chatRoomIDs = <String>{};
      for (var doc in snapshot.docs) { final parent = doc.reference.parent.parent; if (parent != null) { chatRoomIDs.add(parent.id); } }
      return chatRoomIDs.length;
    });
    if (mounted) { setState(() => _totalUnreadChatsCountStream = stream); }
  }

  void _listenForUserChanges() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _userChangesSubscription = _firestore.collection('users').snapshots().listen((snapshot) async {
      bool needsRefresh = false;
      for (var docChange in snapshot.docChanges) {
        if (docChange.type == DocumentChangeType.added || docChange.type == DocumentChangeType.modified) {
          final userData = docChange.doc.data();
          if (userData != null) { 
            final dataToSave = Map<String, dynamic>.from(userData);
            dataToSave['id'] = docChange.doc.id; 
            if (dataToSave['blockedUsers'] is List) {
              dataToSave['blockedUsers'] = jsonEncode(dataToSave['blockedUsers']);
            }
            await _dbHelper.saveJembeContact(dataToSave); 
            needsRefresh = true; 
          }
        }
      }
      if (needsRefresh && mounted) { await _syncAndLoadData(); }
    });
  }

  Future<Map<String, String>> _getPhoneContactsMap() async {
    Map<String, String> phoneContactsMap = {};
    PermissionStatus status = await Permission.contacts.status;
    if (status.isDenied) {
      status = await Permission.contacts.request();
    }
    if (status.isGranted) {
      try {
        List<Contact> contacts = await FlutterContacts.getContacts(withProperties: true);
        for (var contact in contacts) {
          for (var phone in contact.phones) {
            if (phone.number.isNotEmpty) {
              String normalizedPhone = _normalizePhoneNumber(phone.number);
              if (!phoneContactsMap.containsKey(normalizedPhone)) {
                phoneContactsMap[normalizedPhone] = contact.displayName;
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Ikosa ryo gusoma contacts: $e");
      }
    } else {
      debugPrint("Umukoresha ntiyemeye ko porogaramu isoma contacts ze.");
    }
    return phoneContactsMap;
  }
  
  String _normalizePhoneNumber(String phone) {
    String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length >= 8) {
        String potentialNumber = digitsOnly.substring(digitsOnly.length - 8);
        if (potentialNumber.startsWith('6') || potentialNumber.startsWith('7')) {
            return '+257$potentialNumber';
        }
    }
    if (phone.trim().startsWith('+')) {
        return phone.replaceAll(RegExp(r'[\s-()]'), '');
    }
    return digitsOnly;
  }

  void _initializeTotalUnreadStream() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) { if (mounted) { setState(() => _totalUnreadCountStream = Stream.value(0)); } return; }
    final announcementsStream = _firestore.collection('announcements').orderBy('createdAt', descending: true).limit(50).snapshots().asyncMap((snapshot) async {
      final prefs = await SharedPreferences.getInstance();
      final lastReadMillis = prefs.getInt('lastReadAnnouncementTimestamp') ?? 0;
      final lastReadTimestamp = Timestamp.fromMillisecondsSinceEpoch(lastReadMillis);
      return snapshot.docs.where((doc) { final createdAt = doc.data()['createdAt'] as Timestamp?; return createdAt != null && createdAt.compareTo(lastReadTimestamp) > 0; }).length;
    });
    if (mounted) { setState(() => _totalUnreadCountStream = announcementsStream); }
  }

  Future<void> _onNotificationsPressed() async { Navigator.push(context, PageRouteBuilder(transitionDuration: const Duration(milliseconds: 1000), pageBuilder: (context, animation, secondaryAnimation) => const UnifiedNotificationsScreen(), transitionsBuilder: (context, animation, secondaryAnimation, child) { return FadeThroughTransition(animation: animation, secondaryAnimation: secondaryAnimation, child: child); })).then((_) => _initializeTotalUnreadStream()); }
  AppBar _buildSearchAppBar(BuildContext context) { final theme = Theme.of(context); return AppBar(backgroundColor: theme.appBarTheme.backgroundColor?.withAlpha(230), elevation: 0, leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _isSearching = false; _searchController.clear(); })), title: TextField(controller: _searchController, autofocus: true, decoration: const InputDecoration(hintText: 'Shakisha...', border: InputBorder.none), style: TextStyle(fontSize: 18, color: theme.textTheme.bodyLarge?.color))); }
  String _getCurrentDayInKirundi() {
    final now = DateTime.now();
    switch (now.weekday) {
      case DateTime.monday: return "Kuwambere"; case DateTime.tuesday: return "Kuwakabiri"; case DateTime.wednesday: return "Kuwagatatu"; case DateTime.thursday: return "Kuwakane"; case DateTime.friday: return "Kuwagatanu"; case DateTime.saturday: return "Kuwagatandatu"; case DateTime.sunday: return "Kuwamungu"; default: return "";
    }
  }
  
  Future<void> _saveTabOrder(List<String> order) async { final prefs = await SharedPreferences.getInstance(); await prefs.setStringList('tabOrder', order); }
  
  Future<void> _loadTabOrder() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? savedOrder = prefs.getStringList('tabOrder');
    if (savedOrder == null) { _tabOrder = List.from(_defaultTabOrder); } else {
      _tabOrder = savedOrder;
      for (var id in _defaultTabOrder) { if (!_tabOrder.contains(id)) { _tabOrder.add(id); } }
    }
    if (mounted) { setState(() { _tabOrderLoaded = true; }); }
  }

  void _initializeStarNotificationStream() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final now = DateTime.now();
    const announcementHour = 18;
    final todayAnnouncementTime = DateTime(now.year, now.month, now.day, announcementHour);
    DateTime lastAnnouncementTime;
    if (now.isBefore(todayAnnouncementTime)) { lastAnnouncementTime = todayAnnouncementTime.subtract(const Duration(days: 1)); } else { lastAnnouncementTime = todayAnnouncementTime; }
    final lastAnnouncementFirebaseTimestamp = Timestamp.fromDate(lastAnnouncementTime);
    final stream = _firestore.collection('notifications').where('userId', isEqualTo: currentUser.uid).where('type', isEqualTo: 'star_winner').where('isRead', isEqualTo: false).where('timestamp', isGreaterThanOrEqualTo: lastAnnouncementFirebaseTimestamp).limit(1).snapshots().map((snapshot) => snapshot.docs.isNotEmpty);
    if (mounted) { setState(() { _hasUnreadStarNotificationStream = stream; }); }
  }

  void _navigateToDayScreen() async {
    final String? currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    if (!mounted) return;
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => StarDayScreen(userId: currentUserId)));
    if (result is String && result.isNotEmpty) { final String postId = result; _navigateToTangazaStar(targetPostId: postId); }
    _markStarNotificationsAsRead(currentUserId);
  }

  Future<void> _markStarNotificationsAsRead(String userId) async {
    final querySnapshot = await _firestore.collection('notifications').where('userId', isEqualTo: userId).where('type', isEqualTo: 'star_winner').where('isRead', isEqualTo: false).get();
    final batch = _firestore.batch();
    for (var doc in querySnapshot.docs) { batch.update(doc.reference, {'isRead': true}); }
    await batch.commit();
  }

  void _navigateToTangazaStar({String? targetPostId}) { Navigator.push(context, PageRouteBuilder(transitionDuration: const Duration(milliseconds: 1000), pageBuilder: (context, animation, secondaryAnimation) => TangazaStarScreen(targetPostId: targetPostId), transitionsBuilder: (context, animation, secondaryAnimation, child) { return SharedAxisTransition(animation: animation, secondaryAnimation: secondaryAnimation, transitionType: SharedAxisTransitionType.scaled, child: child); })); }

  PreferredSizeWidget _buildCustomAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.of(context).padding.top;
    const double appBarHeight = kToolbarHeight;
    const double bottomSectionHeight = 56.0;
    const double totalHeight = appBarHeight + bottomSectionHeight;
    return PreferredSize(preferredSize: const Size.fromHeight(totalHeight), child: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: theme.appBarTheme.backgroundColor?.withAlpha(200), child: Padding(padding: EdgeInsets.only(top: topPadding), child: Column(children: [ SizedBox(height: appBarHeight, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const SizedBox(width: 56), Row(mainAxisSize: MainAxisSize.min, children: [ Text("Jembe Talk", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)), const SizedBox(width: 8), StreamBuilder<int>(stream: _totalUnreadCountStream, builder: (context, snapshot) { return Badge(isLabelVisible: (snapshot.data ?? 0) > 0, label: Text((snapshot.data ?? 0).toString()), child: Material(color: Colors.transparent, child: InkWell(onTap: _onNotificationsPressed, borderRadius: BorderRadius.circular(30), child: Padding(padding: const EdgeInsets.all(6.0), child: Icon(Icons.notifications_none, size: 28, color: theme.iconTheme.color))))); })]), IconButton(padding: const EdgeInsets.only(right: 8.0), icon: const Icon(Icons.more_vert), onPressed: () => _showMainMenu(context))])), SizedBox(height: bottomSectionHeight, child: Padding(padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0), child: Row(children: [ Expanded(flex: 1, child: StreamBuilder<bool>(stream: _hasUnreadStarNotificationStream, builder: (context, snapshot) { final bool isWinner = snapshot.data ?? false; return ScaleTransition(scale: _loveStarAnimation, child: InkWell(onTap: _navigateToDayScreen, borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomLeft: Radius.circular(24), topLeft: Radius.circular(8), bottomRight: Radius.circular(8)), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: theme.colorScheme.surface.withAlpha(50), borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomLeft: Radius.circular(24), topLeft: Radius.circular(8), bottomRight: Radius.circular(8)), border: Border.all(color: theme.colorScheme.secondary.withAlpha(150), width: 1.5)), child: Center(child: isWinner ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [ Text("WINNER", style: TextStyle(color: Colors.pinkAccent.shade100, fontSize: 13.0, fontWeight: FontWeight.bold, letterSpacing: 1.2)), const SizedBox(width: 5), const FaIcon(FontAwesomeIcons.solidStar, color: Colors.amber, size: 15)]) : Row(mainAxisAlignment: MainAxisAlignment.center, children: [ Text(_getCurrentDayInKirundi(), style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 12.0, fontWeight: FontWeight.bold)), const SizedBox(width: 6), FaIcon(FontAwesomeIcons.solidCalendarDays, color: Colors.amber, size: 18)]))))); })), const SizedBox(width: 8), Expanded(flex: 1, child: ScaleTransition(scale: _loveStarAnimation, child: InkWell(onTap: () => _navigateToTangazaStar(targetPostId: null), borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomRight: Radius.circular(24), topRight: Radius.circular(8), bottomLeft: Radius.circular(8)), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: theme.colorScheme.surface.withAlpha(50), borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomRight: Radius.circular(24), topRight: Radius.circular(8), bottomLeft: Radius.circular(8)), border: Border.all(color: theme.colorScheme.secondary.withAlpha(150), width: 1.5)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [ Text("Tangaza Star", style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 12.0, fontWeight: FontWeight.bold)), const SizedBox(width: 6), const FaIcon(FontAwesomeIcons.solidStar, color: Colors.amber, size: 18)]))))), IconButton(icon: const Icon(Icons.search, size: 28), onPressed: () => setState(() => _isSearching = true))])))]))))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_tabOrderLoaded) { return Scaffold(backgroundColor: theme.scaffoldBackgroundColor, body: const Center(child: CircularProgressIndicator())); }
    
    final allTabs = {
      'chats': TabItem(id: 'chats', label: 'Chats', icon: Icons.chat_bubble_outline, screen: UsersListTab(searchQuery: _searchQuery, chatsNotifier: _chatsNotifier, onRefresh: _refreshData, onChatClosed: () => _syncAndLoadData(), myBlockedUsers: _myBlockedUsers)),
      'contacts': TabItem(id: 'contacts', label: 'Contacts', icon: Icons.people_outline, screen: ContactsListTab(contactsNotifier: _contactsNotifier, onRefresh: _refreshData, onChatClosed: () => _syncAndLoadData(), myBlockedUsers: _myBlockedUsers)),
      'tv': TabItem(id: 'tv', label: 'TV', icon: Icons.tv_outlined, screen: const TVListTab()),
      'settings': TabItem(id: 'settings', label: 'Settings', icon: Icons.settings_outlined, screen: const SettingsScreen()),
    };
    final orderedTabs = _tabOrder.map((id) => allTabs[id]!).toList();
    
    return Scaffold(extendBodyBehindAppBar: true, appBar: _isSearching ? _buildSearchAppBar(context) : _buildCustomAppBar(context), body: Stack(children: [ Container(color: theme.scaffoldBackgroundColor), if (_backgroundImagePath != null && File(_backgroundImagePath!).existsSync()) Image.file(File(_backgroundImagePath!), height: double.infinity, width: double.infinity, fit: BoxFit.cover, color: Colors.black.withAlpha(128), colorBlendMode: BlendMode.darken), SafeArea(
      child: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: orderedTabs.map((tab) => tab.screen).toList(),
      ),
    ) ] ), bottomNavigationBar: Container(height: kBottomNavigationBarHeight + MediaQuery.of(context).padding.bottom, color: theme.colorScheme.surface.withAlpha(200), child: SafeArea(bottom: false, child: ReorderableListView(scrollDirection: Axis.horizontal, buildDefaultDragHandles: false, onReorder: (int oldIndex, int newIndex) { setState(() { if (newIndex > oldIndex) { newIndex -= 1; } final String item = _tabOrder.removeAt(oldIndex); _tabOrder.insert(newIndex, item); _saveTabOrder(_tabOrder); if (_currentIndex == oldIndex) { _currentIndex = newIndex; } else if (_currentIndex > oldIndex && _currentIndex <= newIndex) { _currentIndex--; } else if (_currentIndex < oldIndex && _currentIndex >= newIndex) { _currentIndex++; } }); }, proxyDecorator: (widget, index, animation) { return AnimatedBuilder(animation: animation, builder: (context, child) { final double animValue = Curves.easeInOut.transform(animation.value); final double elevation = lerpDouble(0, 8, animValue)!; return Material(elevation: elevation, color: Colors.transparent, child: widget); }, child: widget); }, children: List.generate(orderedTabs.length, (index) { final tab = orderedTabs[index]; final isSelected = _currentIndex == index; return ReorderableDragStartListener(key: ValueKey(tab.id), index: index, child: GestureDetector(
      onTap: () => _goToPage(index), 
      child: Container(width: MediaQuery.of(context).size.width / orderedTabs.length, padding: const EdgeInsets.symmetric(vertical: 4), child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [ if (tab.id == 'chats') StreamBuilder<int>(stream: _totalUnreadChatsCountStream, builder: (context, snapshot) { final count = snapshot.data ?? 0; return Badge(label: Text(count.toString()), isLabelVisible: count > 0, child: Icon(tab.icon, color: isSelected ? theme.colorScheme.secondary : theme.textTheme.bodyMedium?.color)); }) else Icon(tab.icon, color: isSelected ? theme.colorScheme.secondary : theme.textTheme.bodyMedium?.color), const SizedBox(height: 4), Text(tab.label, style: TextStyle(fontSize: 12, color: isSelected ? theme.colorScheme.secondary : theme.textTheme.bodyMedium?.color))])))); })))));
  }

  Future<void> _syncUsersFromFirebase() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      final usersSnapshot = await _firestore.collection('users').get();
      for (var userDoc in usersSnapshot.docs) { 
        final userData = userDoc.data(); 
        final dataToSave = Map<String, dynamic>.from(userData);
        dataToSave['id'] = userDoc.id; 
        if (dataToSave['blockedUsers'] is List) {
          dataToSave['blockedUsers'] = jsonEncode(dataToSave['blockedUsers']);
        }
        await _dbHelper.saveJembeContact(dataToSave); 
      }
    } catch (e) { debugPrint("Ikosa ryo guhuza amakuru y'abakoresha: $e"); }
  }

  Future<void> _logout() async {
    MessageStatusService.instance.dispose();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _auth.signOut();
    if (!mounted) return;
    navigator.pushAndRemoveUntil(PageRouteBuilder(pageBuilder: (context, animation, secondaryAnimation) => const WelcomeScreen(), transitionsBuilder: (context, animation, secondaryAnimation, child) { return FadeTransition(opacity: animation, child: child); }, transitionDuration: const Duration(milliseconds: 1250)), (route) => false);
  }

  void _showMainMenu(BuildContext context) { showMenu(context: context, position: const RelativeRect.fromLTRB(100, 80, 0, 0), color: Theme.of(context).colorScheme.surface, items: [ PopupMenuItem(onTap: () { Future.delayed(const Duration(seconds: 0), () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OnlineContactsScreen()))); }, child: const ListTile(leading: Icon(Icons.online_prediction_outlined), title: Text("Abari ku murongo"))), PopupMenuItem(onTap: _showAnimatedWallpaperDialog, child: const ListTile(leading: Icon(Icons.wallpaper_outlined), title: Text("Ifoto y'inyuma"))), PopupMenuItem(onTap: _logout, child: const ListTile(leading: Icon(Icons.logout_outlined), title: Text("Sohoka")))]); }
  Future<void> _loadWallpaper() async { final prefs = await SharedPreferences.getInstance(); if (mounted) { setState(() => _backgroundImagePath = prefs.getString('wallpaperPath')); } }
  Future<void> _showAnimatedWallpaperDialog() async {
    showGeneralDialog(context: context, barrierDismissible: true, barrierLabel: '', transitionDuration: const Duration(milliseconds: 750), pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(), transitionBuilder: (context, animation, secondaryAnimation, child) { return ScaleTransition(scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack), child: AlertDialog(title: const Text("Ifoto y'Inyuma"), content: Column(mainAxisSize: MainAxisSize.min, children: [ ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Hindura ifoto'), onTap: () async { if (!mounted) return; Navigator.of(context).pop(); final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery); if (pickedFile != null) { final prefs = await SharedPreferences.getInstance(); await prefs.setString('wallpaperPath', pickedFile.path); if (mounted) { setState(() => _backgroundImagePath = pickedFile.path); } } }), if (_backgroundImagePath != null) ListTile(leading: const Icon(Icons.delete_outline, color: Colors.redAccent), title: const Text('Futa ifoto', style: TextStyle(color: Colors.redAccent)), onTap: () async { if (!mounted) return; Navigator.of(context).pop(); final prefs = await SharedPreferences.getInstance(); await prefs.remove('wallpaperPath'); if (mounted) { setState(() => _backgroundImagePath = null); } })]))); }); }
}

class TVListTab extends StatefulWidget {
  const TVListTab({super.key});
  @override
  State<TVListTab> createState() => _TVListTabState();
}

class _TVListTabState extends State<TVListTab> {
  bool _isTvOn = false;
  Future<void> _onItemTap(Map<String, dynamic> channelData) async {
    final type = channelData['type'];
    final name = channelData['name'] ?? 'Video';
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => LoadingScreen(
          channelName: name,
          onLoadingComplete: () async {
            if (!mounted) return;
            if (type == 'youtube') {
              final videoId = channelData['videoId'];
              if (videoId != null && videoId.isNotEmpty) {
                Navigator.pushReplacement(context, MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(videoId: videoId, title: name),
                ));
              }
            } else if (type == 'tv') {
              final streamUrl = channelData['streamUrl'];
              if (streamUrl != null && streamUrl.isNotEmpty) {
                Navigator.pushReplacement(context, MaterialPageRoute(
                  builder: (context) => NetworkVideoPlayerScreen(streamUrl: streamUrl, title: name),
                ));
              }
            }
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Widget _buildTvOffScreen(BuildContext context) {
    return Container(
      key: const ValueKey('tv_off'),
      decoration: BoxDecoration(
        color: Colors.black,
        gradient: RadialGradient(colors: [Colors.grey[900]!, Colors.black], radius: 0.8),
      ),
      child: Center(child: Icon(Icons.power_settings_new, color: Colors.grey.withOpacity(0.1), size: 80)),
    );
  }
  
  Widget _buildTvOnScreen(BuildContext context) { 
    return Container(
      key: const ValueKey('tv_on'), 
      color: const Color(0xFF0a0a1a),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              "URUTONDE GWAMA TV.",
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('tv_channels').orderBy('order').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Habaye ikibazo: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("Nta kintu kiraboneka.", style: TextStyle(color: Colors.white70)));
                }
                final channels = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final channelData = channels[index].data() as Map<String, dynamic>;
                    return ListTile(
                      leading: Icon(
                        Icons.tv_rounded,
                        color: Colors.blue.shade200,
                      ),
                      title: Text(channelData['name'] ?? 'Ata zina', style: const TextStyle(color: Colors.white, fontSize: 16)),
                      onTap: () => _onItemTap(channelData),
                    );
                  },
                );
              },
            ),
          ),
        ],
      )
    ); 
  }
  
  @override
  Widget build(BuildContext context) { 
    final theme = Theme.of(context); 
    return Column(children: [ 
      Expanded(
        flex: 8, 
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8), 
            decoration: BoxDecoration( border: Border.all(color: Colors.black38, width: 4), borderRadius: BorderRadius.zero, color: Colors.black ), 
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 2000), 
                transitionBuilder: (child, animation) { return FadeTransition(opacity: animation, child: child); }, 
                child: _isTvOn ? _buildTvOnScreen(context) : _buildTvOffScreen(context)
              )
            )
          )
        )
      ),
      Expanded(
        flex: 2, 
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 750), 
            transitionBuilder: (child, animation){ return ScaleTransition(scale: animation, child: child); }, 
            child: _isTvOn 
              ? Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text("Hitamwo TV ushaka kuraba.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: theme.textTheme.bodyMedium?.color)),) 
              : ElevatedButton.icon(
                  onPressed: () { setState(() { _isTvOn = true; }); }, 
                  icon: const Icon(Icons.power_settings_new_rounded), 
                  label: const Text("Open"), 
                  style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.secondary, foregroundColor: theme.colorScheme.onSecondary, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                )
          )
        )
      )
    ]); 
  }
}


class UsersListTab extends StatelessWidget {
  final String searchQuery;
  final ValueNotifier<List<_ChatData>> chatsNotifier;
  final Future<void> Function() onRefresh;
  final VoidCallback onChatClosed;
  final List<dynamic> myBlockedUsers;
  const UsersListTab({super.key, required this.searchQuery, required this.chatsNotifier, required this.onRefresh, required this.onChatClosed, required this.myBlockedUsers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LiquidPullToRefresh(
        onRefresh: onRefresh,
        color: theme.scaffoldBackgroundColor,
        backgroundColor: theme.colorScheme.secondary,
        child: ValueListenableBuilder<List<_ChatData>>(
            valueListenable: chatsNotifier,
            builder: (context, chats, child) {
              final filteredChats = searchQuery.isEmpty ? chats : chats.where((chat) => chat.displayName.toLowerCase().contains(searchQuery.toLowerCase())).toList();
              if (filteredChats.isEmpty) { return const Center(child: Text("Nta biganiro bibonetse.", textAlign: TextAlign.center)); }
              return AnimationLimiter(
                  child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      itemCount: filteredChats.length,
                      itemBuilder: (context, index) {
                        final chatData = filteredChats[index];
                        return AnimationConfiguration.staggeredList(
                          position: index, 
                          duration: const Duration(milliseconds: 500),
                          child: SlideAnimation(
                            verticalOffset: 50.0, 
                            child: FadeInAnimation(
                              child: ChatListItem(
                                key: ValueKey(chatData.userId), 
                                chatData: chatData, 
                                myBlockedUsers: myBlockedUsers, 
                                onClosed: onChatClosed
                              )
                            )
                          )
                        );
                      }
                  )
              );
            }
        )
    );
  }
}

class ChatListItem extends StatelessWidget {
  final _ChatData chatData;
  final List<dynamic> myBlockedUsers;
  final VoidCallback onClosed;
  const ChatListItem({super.key, required this.chatData, required this.myBlockedUsers, required this.onClosed});
  String _getChatRoomID(String uid1, String uid2) { List<String> ids = [uid1, uid2]; ids.sort(); return ids.join('_'); }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();
    final chatRoomID = _getChatRoomID(currentUser.uid, chatData.userId);
    
    final bool iBlockedThisUser = myBlockedUsers.contains(chatData.userId);
    final bool thisUserBlockedMe = chatData.blockedUsers.contains(currentUser.uid);
    final String? photoUrl = (iBlockedThisUser || thisUserBlockedMe) ? null : chatData.photoUrl;
    
    final lastMessageStream = FirebaseFirestore.instance.collection('chat_rooms').doc(chatRoomID).collection('messages').orderBy('timestamp', descending: true).limit(1).snapshots();
    final unreadCountStream = FirebaseFirestore.instance.collection('chat_rooms').doc(chatRoomID).collection('messages').where('receiverID', isEqualTo: currentUser.uid).where('status', isNotEqualTo: 'seen').snapshots();
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        child: OpenContainer(
            onClosed: (_) => onClosed(),
            transitionDuration: const Duration(milliseconds: 750), 
            closedColor: Colors.transparent, middleColor: theme.scaffoldBackgroundColor, openColor: theme.scaffoldBackgroundColor, closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), closedElevation: 0, openElevation: 0,
            openBuilder: (context, action) => ChatScreenWrapper(receiverEmail: chatData.displayName, receiverID: chatData.userId),
            closedBuilder: (context, openContainer) {
              return StreamBuilder<QuerySnapshot>(stream: unreadCountStream, builder: (context, unreadSnapshot) {
                final unreadCount = unreadSnapshot.data?.docs.length ?? 0;
                final hasUnread = unreadCount > 0;
                return StreamBuilder<QuerySnapshot>(stream: lastMessageStream, builder: (context, lastMessageSnapshot) {
                  final lastMessageData = (lastMessageSnapshot.hasData && lastMessageSnapshot.data!.docs.isNotEmpty) ? lastMessageSnapshot.data!.docs.first.data() as Map<String, dynamic> : null;
                  return ClipRRect(borderRadius: BorderRadius.circular(16.0), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0), child: Container(decoration: BoxDecoration(color: theme.colorScheme.surface.withAlpha(150), borderRadius: BorderRadius.circular(16.0), border: Border.all(color: theme.colorScheme.onSurface.withAlpha(51))), child: Row(children: [
                    Container(width: 8, color: hasUnread ? theme.colorScheme.secondary : Colors.transparent),
                    Expanded(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    leading: OpenContainer(transitionType: ContainerTransitionType.fade, transitionDuration: const Duration(milliseconds: 1000), closedColor: Colors.transparent, closedElevation: 0, openBuilder: (c, a) => ContactInfoScreen(userID: chatData.userId, userEmail: chatData.displayName, photoUrl: photoUrl), closedBuilder: (c, a) => Hero(tag: 'profile-pic-${chatData.userId}', child: CircleAvatar(radius: 28, backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null, child: photoUrl == null ? const Icon(Icons.person, size: 30) : null))), title: Text(chatData.displayName, style: TextStyle(fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal, color: theme.textTheme.bodyLarge?.color)), subtitle: LastMessagePreview(lastMessage: lastMessageData, currentUserID: currentUser.uid), trailing: TrailingInfo(lastMessage: lastMessageData, unreadCount: unreadCount))),
                  ]))));
                });
              });
            }));
  }
}

class LastMessagePreview extends StatelessWidget {
  final Map<String, dynamic>? lastMessage;
  final String currentUserID;
  const LastMessagePreview({super.key, required this.lastMessage, required this.currentUserID});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (lastMessage == null) { return Text("", style: TextStyle(color: theme.textTheme.bodyMedium?.color)); }
    final messageType = lastMessage!['messageType'];
    final isMe = lastMessage!['senderID'] == currentUserID;
    IconData? messageIcon;
    String messageText;
    switch (messageType) {
      case 'text': messageText = lastMessage!['message'] ?? ''; break;
      case 'image': messageIcon = Icons.photo_camera; messageText = 'Ifoto'; break;
      case 'video': messageIcon = Icons.videocam; messageText = 'Video'; break;
      case 'voice_note': messageIcon = Icons.mic; messageText = 'Ijwi'; break;
      default: messageText = 'Ubutumwa';
    }
    return Row(children: [ if (isMe) _buildStatusIcon(lastMessage!['status'], theme), if (messageIcon != null) Icon(messageIcon, color: theme.textTheme.bodyMedium?.color, size: 16), if (messageIcon != null) const SizedBox(width: 4), Expanded(child: Text(messageText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textTheme.bodyMedium?.color)))]);
  }
  Widget _buildStatusIcon(String? status, ThemeData theme) {
    IconData icon; Color color = theme.textTheme.bodyMedium?.color ?? Colors.grey;
    switch (status) {
      case 'seen': icon = Icons.visibility; color = Colors.cyan.shade300; break;
      case 'delivered': icon = Icons.done_all; color = theme.textTheme.bodyMedium?.color ?? Colors.grey; break;
      case 'sent': icon = Icons.done; color = theme.textTheme.bodyMedium?.color ?? Colors.grey; break;
      case 'failed': icon = Icons.error_outline; color = Colors.red.shade400; break;
      case 'pending': default: icon = Icons.watch_later_outlined; color = theme.textTheme.bodyMedium?.color ?? Colors.grey;
    }
    return Padding(padding: const EdgeInsets.only(right: 6.0), child: Icon(icon, size: 16, color: color));
  }
}

class TrailingInfo extends StatelessWidget {
  final Map<String, dynamic>? lastMessage;
  final int unreadCount;
  const TrailingInfo({super.key, required this.lastMessage, required this.unreadCount});
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime messageTime;
    if (timestamp is Timestamp) { messageTime = timestamp.toDate(); } else if (timestamp is int) { messageTime = DateTime.fromMillisecondsSinceEpoch(timestamp); } else { return ''; }
    final now = DateTime.now();
    if (now.year == messageTime.year && now.month == messageTime.month && now.day == messageTime.day) { return ('${messageTime.hour}:${messageTime.minute.toString().padLeft(2, '0')}'); }
    return ('${messageTime.day}/${messageTime.month}/${messageTime.year % 100}');
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (lastMessage == null) { return const SizedBox.shrink(); }
    final timestamp = _formatTimestamp(lastMessage!['timestamp']);
    return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [ Text(timestamp, style: TextStyle(color: unreadCount > 0 ? const Color(0xFF25D366) : theme.textTheme.bodyMedium?.color, fontSize: 12)), const SizedBox(height: 4), if (unreadCount > 0) Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle), child: Text(unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))) else const SizedBox(height: 22)]);
  }
}

class ContactsListTab extends StatelessWidget {
  final ValueNotifier<List<_ChatData>> contactsNotifier;
  final Future<void> Function() onRefresh;
  final VoidCallback onChatClosed;
  final List<dynamic> myBlockedUsers;
  const ContactsListTab({super.key, required this.contactsNotifier, required this.onRefresh, required this.onChatClosed, required this.myBlockedUsers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LiquidPullToRefresh(
        onRefresh: onRefresh,
        color: theme.scaffoldBackgroundColor,
        backgroundColor: theme.colorScheme.secondary,
        child: ValueListenableBuilder<List<_ChatData>>(
            valueListenable: contactsNotifier,
            builder: (context, contacts, child) {
              if (contacts.isEmpty) { return Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ Text("Nta n'umwe mu bo mufitanye inomero akoresha Jembe Talk.\nGerageza gukora 'refresh'.", textAlign: TextAlign.center, style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 16)), const SizedBox(height: 20), ElevatedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh), label: const Text("Vugurura"))]))); }
              final sortedContacts = List<_ChatData>.from(contacts);
              sortedContacts.sort((a, b) => a.displayName.compareTo(b.displayName));
              return AnimationLimiter(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: sortedContacts.length,
                  itemBuilder: (context, index) {
                    final user = sortedContacts[index];
                    return AnimationConfiguration.staggeredList(
                      position: index, 
                      duration: const Duration(milliseconds: 500),
                      child: SlideAnimation(
                        verticalOffset: 50.0, 
                        child: FadeInAnimation(
                          child: _ContactListItem(
                            chatData: user,
                            myBlockedUsers: myBlockedUsers,
                            onClosed: onChatClosed,
                          )
                        )
                      )
                    );
                  },
                ),
              );
            }
        )
    );
  }
}

class _ContactListItem extends StatelessWidget {
  final _ChatData chatData;
  final List<dynamic> myBlockedUsers;
  final VoidCallback onClosed;
  const _ContactListItem({required this.chatData, required this.myBlockedUsers, required this.onClosed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    final bool iBlockedThisUser = myBlockedUsers.contains(chatData.userId);
    final bool thisUserBlockedMe = chatData.blockedUsers.contains(currentUser.uid);
    final String? photoUrl = (iBlockedThisUser || thisUserBlockedMe) ? null : chatData.photoUrl;
    
    final String receiverID = chatData.userId;
    final String receiverName = chatData.displayName;

    return Padding(padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        child: OpenContainer(
            onClosed: (_) => onClosed(),
            transitionDuration: const Duration(milliseconds: 750), 
            closedColor: Colors.transparent, middleColor: theme.scaffoldBackgroundColor, openColor: theme.scaffoldBackgroundColor, closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)), closedElevation: 0, openElevation: 0,
            openBuilder: (context, action) => ChatScreenWrapper(receiverEmail: receiverName, receiverID: receiverID),
            closedBuilder: (context, openContainer) {
              return ClipRRect(borderRadius: BorderRadius.circular(16.0), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0), child: Container(decoration: BoxDecoration(color: theme.colorScheme.surface.withAlpha(150), borderRadius: BorderRadius.circular(16.0), border: Border.all(color: theme.colorScheme.onSurface.withAlpha(51))), child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              leading: OpenContainer(transitionType: ContainerTransitionType.fade, transitionDuration: const Duration(milliseconds: 1000), closedColor: Colors.transparent, closedElevation: 0, openBuilder: (c, a) => ContactInfoScreen(userID: receiverID, userEmail: receiverName, photoUrl: photoUrl), closedBuilder: (c, a) => Hero(tag: 'profile-pic-$receiverID', child: CircleAvatar(radius: 28, backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null, child: photoUrl == null ? const Icon(Icons.person, size: 30) : null))), title: Text(receiverName, style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontWeight: FontWeight.w500)), subtitle: Text(chatData.phoneNumber ?? '', style: TextStyle(color: theme.textTheme.bodyMedium?.color))))));
            }));
  }
}