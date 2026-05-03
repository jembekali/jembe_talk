// lib/chat_screen.dart (VERSION 5.18 - ABSOLUTE REAL-TIME SEEN STATUS FIX)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_editor/video_editor.dart';
import 'package:path/path.dart' as path;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:social_media_recorder/screen/social_media_recorder.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

// --- Modular Widgets ---
import 'widgets/chat/chat_app_bar.dart';
import 'widgets/chat/message_bubble.dart';
import 'widgets/chat/chat_attachment_panel.dart';
import 'widgets/chat/staged_media_widgets.dart';
import 'widgets/chat/chat_game_manager.dart';

// --- Constants & Services ---
import 'constants/emojis.dart'; 
import 'language_provider.dart';
import 'services/audio_service.dart';
import 'services/media_upload_service.dart';
import 'services/chat_message_service.dart'; 
import 'services/database_helper.dart'; 
import 'services/sync_service.dart';
import 'contact_info_screen.dart';
import 'forward_screen.dart';

class ChatScreenWrapper extends StatelessWidget {
  final String receiverEmail;
  final String receiverID;
  const ChatScreenWrapper({super.key, required this.receiverEmail, required this.receiverID});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AudioPlayerService())],
      child: ChatScreen(receiverEmail: receiverEmail, receiverID: receiverID),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String receiverEmail;
  final String receiverID;
  const ChatScreen({super.key, required this.receiverID, required this.receiverEmail});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late AutoScrollController _scrollController;
  
  String? _globalBackgroundImagePath, _chatBackgroundImagePath;
  List<Map<String, dynamic>> _messages = [];
  List<dynamic> _chatItems = [];
  bool _isLoading = true, _isAttachmentPanelVisible = false, _isSelectionMode = false, _isEmojiPickerVisible = false;
  final Set<String> _selectedMessages = {};
  
  int _currentOffset = 0;
  final int _pageSize = 25;
  bool _isFetchingMore = false, _hasMoreMessages = true;
  bool _isEditingMessage = false;
  String? _editingMessageId;
  bool _showScrollDownButton = false;
  int _newMessagesCount = 0; 

  Stream<DocumentSnapshot>? _currentUserStream, _receiverUserStream;
  Stream<DatabaseEvent>? _presenceStream, _activityStream;
  DatabaseReference? _myActivityStatusRef;
  StreamSubscription? _gameStreamSubscription, _uiUpdateSubscription, _uploadProgressSubscription, _seenStatusSubscription;
  
  Map<String, dynamic>? _currentGameData, _replyingToMessage;
  final TextEditingController _messageController = TextEditingController(), _captionController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Map<String, double> _uploadProgress = {};
  
  Uint8List? _selectedImageData;
  VideoEditorController? _videoEditorController;
  File? _selectedVideoFile, _stagedVideoFile;
  String? _stagedThumbnailPath;
  VideoPlayerController? _stagedVideoController;
  
  bool _isProcessingVideo = false, _isPreparingInvitation = false, _isWaitingForGameAcceptance = false, _isComposing = false;
  double _videoProcessingProgress = 0.0;
  String? _highlightedMessageId;
  Timer? _typingTimer, _highlightTimer;
  DateTime? _timeWhenPaused;

  String _selectedEmojiCategory = "😊";

  @override
  void initState() {
    super.initState();
    syncService.currentActiveChatId = _getChatRoomID();
    _clearUnreadCount();
    _scrollController = AutoScrollController(viewportBoundaryGetter: () => Rect.fromLTRB(0, 0, 0, MediaQuery.of(context).padding.bottom), axis: Axis.vertical);
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addObserver(this);
    _initStreams();
    _loadInitialData();
    _initListeners();
    _initRealTimeSeenListener(); // ✅ IYI NIYO METODE NSHYA
    _loadDraft();
    syncService.triggerSync();
  }

  // ✅ METODE YA NYUMA IKOSORA SEEN STATUS REAL-TIME
  // Iyi listenere yitegereza impinduka zose muri Firestore muri iyi chat room gusa
  void _initRealTimeSeenListener() {
    final roomId = _getChatRoomID();
    _seenStatusSubscription = _firestore
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(40) // Ireba ubutumwa 40 bwa nyuma (Status zabo)
        .snapshots()
        .listen((snapshot) async {
      bool hasChanges = false;
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data != null) {
            final msgId = change.doc.id;
            final newStatus = data['status'] ?? 'sent';
            
            // 1. Reba niba ubutumwa busanzwe muri SQL
            final localMsg = await DatabaseHelper.instance.getMessageById(msgId);
            if (localMsg != null && localMsg['status'] != newStatus) {
              // 2. Niba status ya Firestore itandukanye n'iya SQL, ivugurure
              await DatabaseHelper.instance.updateMessageStatus(msgId, newStatus);
              hasChanges = true;
            }
          }
        }
      }
      // 3. Niba hari ubutumwa bwahinduye status (Sent -> Seen), refresha UI ako kanya
      if (hasChanges && mounted) {
        _refreshMessages();
      }
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isFetchingMore && _hasMoreMessages) _loadMoreMessages();
    }
    if (_scrollController.offset <= 100 && _newMessagesCount > 0) { setState(() => _newMessagesCount = 0); }
    final bool shouldShow = _scrollController.offset > 400;
    if (shouldShow != _showScrollDownButton) setState(() => _showScrollDownButton = shouldShow);
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString('draft_${_getChatRoomID()}');
    if (draft != null && draft.isNotEmpty) setState(() => _messageController.text = draft);
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final text = _messageController.text.trim();
    if (text.isNotEmpty) await prefs.setString('draft_${_getChatRoomID()}', text);
    else await prefs.remove('draft_${_getChatRoomID()}');
  }

  Future<void> _loadMoreMessages() async {
    if (_isFetchingMore || !_hasMoreMessages) return;
    setState(() => _isFetchingMore = true);
    _currentOffset += _pageSize;
    final more = await chatMessageService.getMessagesPaged(chatRoomID: _getChatRoomID(), limit: _pageSize, offset: _currentOffset);
    if (mounted) {
      setState(() {
        if (more.isEmpty) _hasMoreMessages = false;
        else {
          final existingIds = _messages.map((m) => m['id']).toSet();
          final newUnique = more.where((m) => !existingIds.contains(m['id'])).toList();
          _messages.addAll(newUnique);
          _chatItems = _getChatItemsWithSeparators(_messages);
        }
        _isFetchingMore = false;
      });
    }
  }

  void _forceHideKeyboard() {
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _initStreams() {
    final uid = _auth.currentUser?.uid; if (uid == null) return;
    _currentUserStream = _firestore.collection('users').doc(uid).snapshots();
    _receiverUserStream = _firestore.collection('users').doc(widget.receiverID).snapshots();
    _presenceStream = FirebaseDatabase.instance.ref('status/${widget.receiverID}').onValue.asBroadcastStream();
    final chatRoomID = _getChatRoomID();
    _myActivityStatusRef = FirebaseDatabase.instance.ref('activity/$chatRoomID/$uid');
    _activityStream = FirebaseDatabase.instance.ref('activity/$chatRoomID/${widget.receiverID}').onValue.asBroadcastStream();
  }

  void _initListeners() {
    _uiUpdateSubscription = syncService.uiMessageUpdateStream.listen((event) {
      if (mounted) {
        if (event.startsWith("message_received:")) {
          final String incomingRoomId = event.split(":").last;
          if (incomingRoomId == _getChatRoomID()) {
            Provider.of<AudioPlayerService>(context, listen: false).playNotificationSound('assets/audio/incoming_sound.mp3');
            if (_scrollController.offset > 200) setState(() => _newMessagesCount++);
          }
        }
        _refreshMessages();
      }
    });

    _uploadProgressSubscription = syncService.uploadProgressStream.listen((data) {
      if (mounted) {
        String msgId = data['messageId'];
        double prog = (data['progress'] as num).toDouble();
        setState(() { 
          if (prog >= 1.0) {
            _uploadProgress.remove(msgId);
            Provider.of<AudioPlayerService>(context, listen: false).playNotificationSound('assets/audio/sent_sound.mp3');
            for (var msg in _messages) { if (msg['id'] == msgId) { msg['status'] = 'sent'; break; } }
            _chatItems = _getChatItemsWithSeparators(_messages);
          } else { _uploadProgress[msgId] = prog.clamp(0.0, 1.0); }
        });
      }
    });
    _messageController.addListener(() {
      if (mounted) {
        setState(() => _isComposing = _messageController.text.trim().isNotEmpty);
        _updateTypingStatus();
      }
    });
  }

  Future<void> _refreshMessages() async {
    _currentOffset = 0; _hasMoreMessages = true;
    final local = await chatMessageService.getMessagesPaged(chatRoomID: _getChatRoomID(), limit: _pageSize, offset: 0);
    if (mounted) {
      setState(() { 
        final Map<String, Map<String, dynamic>> messageMap = {};
        for (var m in local) { messageMap[m['id']] = m; }
        _messages = messageMap.values.toList();
        _messages.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
        _chatItems = _getChatItemsWithSeparators(_messages); 
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) { _timeWhenPaused = DateTime.now(); _saveDraft(); }
    else if (state == AppLifecycleState.resumed) { _updateReceivedMessagesStatusToSeen(); _deleteStaleGameIfNeeded(); }
  }

  String _formatLastSeen(int timestamp) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    String time = DateFormat.Hm().format(lastSeen);
    if (isSameDay(lastSeen, now)) return "${lang.t('chat_last_seen_prefix')} $time";
    if (isSameDay(lastSeen, now.subtract(const Duration(days: 1)))) return "${lang.t('chat_last_seen_yesterday_prefix')} $time";
    return "${lang.t('chat_last_seen_date_prefix')} ${DateFormat('dd/MM').format(lastSeen)} $time";
  }

  Future<void> _updateReceivedMessagesStatusToSeen() async {
    final query = _firestore.collection('chat_rooms').doc(_getChatRoomID()).collection('messages').where('receiverID', isEqualTo: _auth.currentUser!.uid).where('status', isNotEqualTo: 'seen');
    final snap = await query.get();
    if (snap.docs.isNotEmpty) {
      WriteBatch batch = _firestore.batch();
      for (var doc in snap.docs) batch.update(doc.reference, {'status': 'seen'});
      await batch.commit().catchError((e) => log("Error seen update: $e"));
    }
  }

  Future<void> _deleteStaleGameIfNeeded() async {
    if (_timeWhenPaused == null) return;
    if (DateTime.now().difference(_timeWhenPaused!).inMinutes >= 10) {
      final gameDoc = await _firestore.collection('games').doc(_getChatRoomID()).get();
      if (gameDoc.exists && gameDoc.data()?['status'] == 'active') await gameDoc.reference.delete();
    }
    _timeWhenPaused = null;
  }

  void _updateTypingStatus() {
    if (mounted) {
      _typingTimer?.cancel();
      if (_messageController.text.trim().isNotEmpty) {
        _myActivityStatusRef?.set("typing");
        _typingTimer = Timer(const Duration(seconds: 2), () => _myActivityStatusRef?.set("idle"));
      } else _myActivityStatusRef?.set("idle");
    }
  }

  void _clearUnreadCount() async {
    if (widget.receiverID == 'jembe_talk_official_admin') {
      await DatabaseHelper.instance.markAdminMessagesAsRead(_auth.currentUser!.uid);
      syncService.notifyUIMessageUpdate("refresh_badges");
    }
  }

  Future<void> _loadInitialData() async {
    await _loadWallpapers();
    await _syncAndDisplayInitialMessages();
    _listenForGameUpdates();
  }

  Future<void> _syncAndDisplayInitialMessages() async {
    final chatID = _getChatRoomID();
    final prefs = await SharedPreferences.getInstance();
    final clearTs = prefs.getInt('chat_clear_timestamp_$chatID') ?? 0;
    final local = await chatMessageService.getMessagesPaged(chatRoomID: chatID, limit: _pageSize, offset: 0);
    final lastTs = local.isNotEmpty ? local.first['timestamp'] as int : 0;
    final startTs = lastTs > clearTs ? lastTs : clearTs;

    final snap = await _firestore.collection('chat_rooms').doc(chatID).collection('messages')
        .where('timestamp', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(startTs))
        .orderBy('timestamp').get();

    for (var doc in snap.docs) {
      final data = doc.data();
      if (data['timestamp'] is Timestamp) data['timestamp'] = (data['timestamp'] as Timestamp).millisecondsSinceEpoch;
      await chatMessageService.saveMessage(data);
    }
    await _loadInitialMessages();
    _updateReceivedMessagesStatusToSeen();
  }

  String _getChatRoomID() {
    final uid = _auth.currentUser?.uid ?? "";
    List<String> ids = [uid, widget.receiverID];
    ids.sort(); return ids.join('_');
  }

  Future<void> _loadInitialMessages({bool forceReload = false}) async {
    _currentOffset = 0; _hasMoreMessages = true;
    final local = await chatMessageService.getMessagesPaged(chatRoomID: _getChatRoomID(), limit: _pageSize, offset: 0);
    if (mounted) {
      setState(() { 
        final Map<String, Map<String, dynamic>> messageMap = {};
        for (var m in local) { messageMap[m['id']] = m; }
        _messages = messageMap.values.toList();
        _messages.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
        _chatItems = _getChatItemsWithSeparators(_messages); 
        _isLoading = false; 
      });
    }
    if (!forceReload) _scrollToMostRecent();
  }

  List<dynamic> _getChatItemsWithSeparators(List<Map<String, dynamic>> messages) {
    List<dynamic> items = []; if (messages.isEmpty) return items;
    messages.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i]; final date = DateTime.fromMillisecondsSinceEpoch(msg['timestamp']);
      items.add(msg);
      final nextDate = (i + 1 < messages.length) ? DateTime.fromMillisecondsSinceEpoch(messages[i+1]['timestamp']) : null;
      if (nextDate == null || !isSameDay(date, nextDate)) items.add(_formatDateSeparator(date));
    }
    return items;
  }
  bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateSeparator(DateTime date) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (isSameDay(date, DateTime.now())) return lang.t('chat_date_separator_today');
    if (isSameDay(date, DateTime.now().subtract(const Duration(days: 1)))) return lang.t('chat_date_separator_yesterday');
    return DateFormat.yMMMMd(lang.currentLanguage == 'fr' ? 'fr_FR' : 'en_US').format(date);
  }

  void _listenForGameUpdates() {
    _gameStreamSubscription = _firestore.collection('games').doc(_getChatRoomID()).snapshots().listen((snap) {
      if (mounted) {
        setState(() { 
          _currentGameData = snap.exists ? snap.data() : null; 
          if (_currentGameData != null && _currentGameData!['status'] == 'active') { 
            _isPreparingInvitation = false; _isWaitingForGameAcceptance = false; _forceHideKeyboard(); 
          } 
        });
      }
    });
  }

  void _scrollToMostRecent() {
    WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.jumpTo(0.0); });
  }

  void _scrollToMessage(String id) {
    final index = _chatItems.indexWhere((it) => it is Map && it['id'] == id);
    if (index != -1) {
      _scrollController.scrollToIndex(index, preferPosition: AutoScrollPosition.middle, duration: const Duration(milliseconds: 800));
      setState(() => _highlightedMessageId = id);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 2), () { if (mounted) setState(() => _highlightedMessageId = null); });
    }
  }

  void _handleMenuSelection(String value, {bool isReceiverBlocked = false}) {
    switch (value) {
      case 'view_contact': Navigator.push(context, MaterialPageRoute(builder: (c) => ContactInfoScreen(userID: widget.receiverID, userEmail: widget.receiverEmail))); break;
      case 'wallpaper': _showWallpaperDialog(); break;
      case 'clear_chat': _clearChat(); break;
      case 'block': _toggleBlock(isReceiverBlocked); break;
    }
  }

  Future<void> _showWallpaperDialog() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: 'Wallpaper', transitionDuration: const Duration(milliseconds: 700), 
      pageBuilder: (c, a1, a2) => const SizedBox(), 
      transitionBuilder: (c, a1, a2, child) => ScaleTransition(
        scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack), 
        child: AlertDialog(
          title: Text(lang.t('wallpaper')), 
          content: Column(mainAxisSize: MainAxisSize.min, children: [ 
            ListTile(leading: const Icon(Icons.photo_library), title: Text(lang.t('btn_change_photo')), onTap: () async { 
              Navigator.pop(c); final img = await ImagePicker().pickImage(source: ImageSource.gallery); 
              if (img != null) { await prefs.setString('wallpaperPath_${_getChatRoomID()}', img.path); setState(() => _chatBackgroundImagePath = img.path); } 
            }), 
            if (_chatBackgroundImagePath != null) ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: Text(lang.t('btn_remove_photo')), onTap: () async { 
              Navigator.pop(c); await prefs.remove('wallpaperPath_${_getChatRoomID()}'); setState(() => _chatBackgroundImagePath = null); 
            }), 
          ])
        )
      )
    );
  }

  Future<void> _clearChat() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showDialog(context: context, builder: (c) => AlertDialog(title: Text(lang.t('chat_clear_chat_dialog_title')), actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: Text(lang.t('chat_clear_chat_dialog_no'))), 
      TextButton(onPressed: () async { 
        Navigator.pop(c); setState(() => _isLoading = true);
        final roomId = _getChatRoomID();
        final now = DateTime.now().millisecondsSinceEpoch;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('chat_clear_timestamp_$roomId', now);
        await chatMessageService.clearChatHistory(roomId);
        await _refreshMessages(); setState(() => _isLoading = false);
      }, child: Text(lang.t('chat_clear_chat_dialog_yes')))
    ]));
  }

  void _toggleBlock(bool blocked) async {
    final ref = _firestore.collection('users').doc(_auth.currentUser!.uid);
    if (blocked) await ref.update({'blockedUsers': FieldValue.arrayRemove([widget.receiverID])});
    else await ref.update({'blockedUsers': FieldValue.arrayUnion([widget.receiverID])});
  }

  void _toggleSelection(String id) {
    HapticFeedback.mediumImpact();
    setState(() { if (_selectedMessages.contains(id)) { _selectedMessages.remove(id); if (_selectedMessages.isEmpty) _isSelectionMode = false; } else { _selectedMessages.add(id); _isSelectionMode = true; } });
  }

  void _onShare() {
    final msgs = _chatItems.whereType<Map<String, dynamic>>().where((m) => _selectedMessages.contains(m['id'])).toList();
    setState(() { _isSelectionMode = false; _selectedMessages.clear(); });
    Navigator.push(context, MaterialPageRoute(builder: (c) => ForwardScreen(messagesToForward: msgs)));
  }

  void _onCopy() {
    final text = _chatItems.whereType<Map<String, dynamic>>().where((m) => _selectedMessages.contains(m['id']) && m['messageType'] == 'text').map((m) => m['message']).join('\n');
    if (text.isNotEmpty) Clipboard.setData(ClipboardData(text: text));
    setState(() { _isSelectionMode = false; _selectedMessages.clear(); });
  }

  void _onReplyFromSelection() {
    if (_selectedMessages.length == 1) { 
      final msg = _chatItems.firstWhere((it) => it is Map && it['id'] == _selectedMessages.first); 
      setState(() { 
        _replyingToMessage = msg; 
        _isEditingMessage = false; _isSelectionMode = false; _selectedMessages.clear(); 
        _isEmojiPickerVisible = false; _isAttachmentPanelVisible = false;
      }); 
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) { _focusNode.requestFocus(); SystemChannels.textInput.invokeMethod('TextInput.show'); }
      });
    } 
  }

  void _onEditMessage(Map<String, dynamic> msg) {
    setState(() { 
      _isEditingMessage = true; _editingMessageId = msg['id']; _messageController.text = msg['message'] ?? ""; 
      _replyingToMessage = null; _isEmojiPickerVisible = false; _isAttachmentPanelVisible = false;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) { _focusNode.requestFocus(); SystemChannels.textInput.invokeMethod('TextInput.show'); }
    });
  }

  void _cancelEditingMessage() { setState(() { _isEditingMessage = false; _editingMessageId = null; _messageController.clear(); }); _forceHideKeyboard(); }

  void _toggleEmojiPicker() async {
    if (_isEmojiPickerVisible) { Navigator.pop(context); Future.delayed(const Duration(milliseconds: 150), () => _focusNode.requestFocus()); }
    else { _forceHideKeyboard(); setState(() => _isAttachmentPanelVisible = false); await Future.delayed(const Duration(milliseconds: 150)); _showEmojiPickerDialog(); }
  }

  void _showEmojiPickerDialog() {
    if (mounted) setState(() => _isEmojiPickerVisible = true);
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: 'Emoji', transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) => StatefulBuilder(
        builder: (context, setPickerState) => Align(alignment: Alignment.centerLeft, child: Material(color: Colors.transparent, child: Container(
          width: MediaQuery.of(context).size.width * 0.85, height: 450, margin: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, spreadRadius: 5)]),
          child: Column(children: [
            Container(height: 50, padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.withAlpha(51)))),
              child: ListView(scrollDirection: Axis.horizontal, children: emojiCategories.keys.map((cat) => GestureDetector(
                onTap: () => setPickerState(() => _selectedEmojiCategory = cat),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 15), alignment: Alignment.center, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _selectedEmojiCategory == cat ? Colors.blue : Colors.transparent, width: 2))), child: Text(cat, style: const TextStyle(fontSize: 22))),
              )).toList()),
            ),
            Expanded(child: GridView.builder(padding: const EdgeInsets.all(10), itemCount: emojiCategories[_selectedEmojiCategory]!.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5),
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () {
                  final emoji = emojiCategories[_selectedEmojiCategory]![i];
                  if (_messageController.text.trim().isEmpty) { Navigator.pop(context); _sendMessage(text: emoji, type: 'large_emoji'); HapticFeedback.heavyImpact(); } 
                  else { _messageController.text += emoji; _messageController.selection = TextSelection.fromPosition(TextPosition(offset: _messageController.text.length)); HapticFeedback.lightImpact(); }
                },
                child: Center(child: Text(emojiCategories[_selectedEmojiCategory]![i], style: const TextStyle(fontSize: 26))),
              ),
            )),
          ]),
        ))),
      ),
      transitionBuilder: (c, a1, a2, child) => SlideTransition(position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a1, curve: Curves.easeInOutCubic)), child: FadeTransition(opacity: a1, child: child)),
    ).then((_) { if (mounted) setState(() { _isEmojiPickerVisible = false; }); });
  }

  void _sendGameInvitation() { 
    final lang = Provider.of<LanguageProvider>(context, listen: false); 
    setState(() => _isWaitingForGameAcceptance = true); _sendMessage(type: 'dame_invitation', text: lang.t('chat_invitation_message')); 
  }

  Future<void> _createGameInFirestore(Map<String, dynamic> msg) async {
    final chatRoomID = _getChatRoomID(); final Map<String, dynamic> board = {};
    for (int r = 0; r < 10; r++) board[r.toString()] = List.generate(10, (c) => ((r + c) % 2 != 0) ? (r < 4 ? {'player': 2, 'type': 'man'} : (r > 5 ? {'player': 1, 'type': 'man'} : null)) : null);
    final data = { 'boardState': board, 'player1Id': msg['senderID'], 'player2Id': _auth.currentUser!.uid, 'turn': msg['senderID'], 'status': 'active', 'player1Score': 0, 'player2Score': 0, 'createdAt': FieldValue.serverTimestamp() };
    await _firestore.collection('games').doc(chatRoomID).set(data); await chatMessageService.deleteMessage(msg['id']); _refreshMessages();
  }

  Future<void> _handleDeclineInvitation(Map<String, dynamic> msg) async { 
    final lang = Provider.of<LanguageProvider>(context, listen: false); 
    _sendMessage(type: 'dame_invitation_declined', text: lang.t('chat_invitation_declined_message')); 
    await chatMessageService.deleteMessage(msg['id']); _refreshMessages(); 
  }
  void _stopGame() async { await _firestore.collection('games').doc(_getChatRoomID()).update({'status': 'stopped', 'stoppedBy': _auth.currentUser!.uid}); }

  Future<void> _processAndStageVideo() async {
    if (_videoEditorController == null || _selectedVideoFile == null) return;
    setState(() => _isProcessingVideo = true); _forceHideKeyboard(); 
    try {
      final thumbFuture = mediaUploadService.generateThumbnail(_selectedVideoFile!.path);
      final outPath = path.join((await getTemporaryDirectory()).path, 'trimmed_${const Uuid().v4()}.mp4');
      final command = '-ss ${_videoEditorController!.startTrim.inSeconds}.${_videoEditorController!.startTrim.inMilliseconds.remainder(1000)} -i "${_selectedVideoFile!.path}" -t ${_videoEditorController!.trimmedDuration.inSeconds}.${_videoEditorController!.trimmedDuration.inMilliseconds.remainder(1000)} -c:v libx264 -preset ultrafast -crf 28 -y "$outPath"';
      await FFmpegKit.executeAsync(command, (session) async {
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          final permPath = await mediaUploadService.saveFilePermanently(outPath); final thumb = await thumbFuture;
          _stagedVideoController = VideoPlayerController.file(File(permPath)); await _stagedVideoController!.initialize(); _stagedVideoController!.setLooping(true);
          if (mounted) setState(() { _stagedVideoFile = File(permPath); _stagedThumbnailPath = thumb; _isProcessingVideo = false; _videoEditorController?.dispose(); _videoEditorController = null; _selectedVideoFile = null; });
        } else { if (mounted) setState(() => _isProcessingVideo = false); }
      }, null, (stats) { 
        final dur = _videoEditorController!.trimmedDuration.inMilliseconds; 
        if (dur > 0 && mounted) setState(() => _videoProcessingProgress = (stats.getTime() / dur).clamp(0.0, 1.0)); 
      });
    } catch (_) { if (mounted) setState(() => _isProcessingVideo = false); }
  }

  void _addOptimisticMessage(Map<String, dynamic> data) { 
    setState(() { 
      if (!_messages.any((m) => m['id'] == data['id'])) {
         _messages.insert(0, data); 
         _chatItems = _getChatItemsWithSeparators(_messages); 
      }
    }); 
    _scrollToMostRecent(); 
  }

  void _sendMessage({String? text, String type = 'text'}) async {
    final txt = text ?? _messageController.text.trim(); if (txt.isEmpty && type == 'text') return;
    if (type == 'text' || type == 'large_emoji') { final p = await SharedPreferences.getInstance(); await p.remove('draft_${_getChatRoomID()}'); }

    if (_isEditingMessage && _editingMessageId != null) {
      final msgIdToEdit = _editingMessageId!; _cancelEditingMessage();
      await chatMessageService.updateMessageContent(chatRoomID: _getChatRoomID(), messageId: msgIdToEdit, newText: txt);
      await _refreshMessages(); syncService.triggerSync(); return;
    }

    final messageId = const Uuid().v4();
    final data = { 'id': messageId, 'chatRoomID': _getChatRoomID(), 'senderID': _auth.currentUser!.uid, 'receiverID': widget.receiverID, 'messageType': type, 'message': txt, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'status': 'pending', 'replyingTo': _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null, 'isEdited': 0, 'isPlayed': 0 };

    if (type == 'text') _messageController.clear();
    await chatMessageService.saveMessage(data); _addOptimisticMessage(data);
    if (mounted) setState(() => _replyingToMessage = null);

    _firestore.collection('chat_rooms').doc(_getChatRoomID()).set({'lastMessage': type == 'large_emoji' ? "Emoji" : txt, 'lastMessageSenderID': _auth.currentUser!.uid, 'lastMessageTimestamp': FieldValue.serverTimestamp(), 'lastMessageType': type}, SetOptions(merge: true));

    if (type == 'text' || type == 'large_emoji' || type == 'dame_invitation') {
      _firestore.collection('chat_rooms').doc(_getChatRoomID()).collection('messages').doc(messageId).set({...data, 'timestamp': FieldValue.serverTimestamp(), 'status': 'sent'}).then((_) {
        Provider.of<AudioPlayerService>(context, listen: false).playNotificationSound('assets/audio/sent_sound.mp3');
        chatMessageService.updateMessageStatus(messageId, 'sent'); syncService.notifyUIMessageUpdate(messageId); 
      }).catchError((_) { syncService.triggerSync(); });
    } else { syncService.triggerSync(); }
    HapticFeedback.lightImpact();
  }

  Future<void> _sendPhoto() async {
    if (_selectedImageData == null) return;
    final imgData = _selectedImageData!; final caption = _captionController.text.trim();
    setState(() { _selectedImageData = null; _captionController.clear(); _replyingToMessage = null; });
    final tempPath = path.join((await getTemporaryDirectory()).path, '${const Uuid().v4()}.png');
    await File(tempPath).writeAsBytes(imgData); final perm = await mediaUploadService.saveFilePermanently(tempPath);
    final data = _createMediaData('image', perm); data['message'] = caption;
    await chatMessageService.saveMessage(data); _addOptimisticMessage(data); 
    _firestore.collection('chat_rooms').doc(_getChatRoomID()).set({'lastMessage': "Photo 📷", 'lastMessageSenderID': _auth.currentUser!.uid, 'lastMessageTimestamp': FieldValue.serverTimestamp(), 'lastMessageType': 'image'}, SetOptions(merge: true));
    mediaUploadService.sendMediaMessageFromData(data);
  }

  Future<void> _sendStagedVideo() async {
    if (_stagedVideoFile == null) return;
    final vidFile = _stagedVideoFile!; final thumbPath = _stagedThumbnailPath; final caption = _captionController.text.trim();
    _stagedVideoController?.dispose();
    setState(() { _stagedVideoController = null; _stagedVideoFile = null; _stagedThumbnailPath = null; _captionController.clear(); _replyingToMessage = null; });
    final data = _createMediaData('video', vidFile.path); data['thumbnailLocalPath'] = thumbPath; data['message'] = caption;
    await chatMessageService.saveMessage(data); _addOptimisticMessage(data); 
    _firestore.collection('chat_rooms').doc(_getChatRoomID()).set({'lastMessage': "Video 🎥", 'lastMessageSenderID': _auth.currentUser!.uid, 'lastMessageTimestamp': FieldValue.serverTimestamp(), 'lastMessageType': 'video'}, SetOptions(merge: true));
    mediaUploadService.sendMediaMessageFromData(data);
  }

  Future<void> _sendVoiceMessage(File soundFile, String duration) async {
    int durSec = 0; try { final p = duration.split(':'); if (p.length == 2) durSec = int.parse(p[0]) * 60 + int.parse(p[1]); } catch (_) {}
    final messageId = const Uuid().v4();
    final data = { 'id': messageId, 'chatRoomID': _getChatRoomID(), 'senderID': _auth.currentUser!.uid, 'receiverID': widget.receiverID, 'messageType': 'voice_note', 'timestamp': DateTime.now().millisecondsSinceEpoch, 'status': 'uploading', 'localPath': soundFile.path, 'storagePath': "chats/${_getChatRoomID()}/voices/$messageId${path.extension(soundFile.path)}", 'duration': durSec, 'fileName': path.basename(soundFile.path), 'replyingTo': _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null, 'isEdited': 0, 'isPlayed': 0 };
    await chatMessageService.saveMessage(data); _addOptimisticMessage(data); 
    _firestore.collection('chat_rooms').doc(_getChatRoomID()).set({'lastMessage': "Voice note 🎤", 'lastMessageSenderID': _auth.currentUser!.uid, 'lastMessageTimestamp': FieldValue.serverTimestamp(), 'lastMessageType': 'voice_note'}, SetOptions(merge: true));
    mediaUploadService.sendMediaMessageFromData(data);
    if (mounted) setState(() => _replyingToMessage = null);
  }

  Map<String, dynamic> _createMediaData(String type, String p) => { 'id': const Uuid().v4(), 'chatRoomID': _getChatRoomID(), 'senderID': _auth.currentUser!.uid, 'receiverID': widget.receiverID, 'messageType': type, 'localPath': p, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'status': 'uploading', 'fileName': p.split('/').last, 'replyingTo': _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null, 'isEdited': 0, 'isPlayed': 0 };

  Future<void> _showDeleteDialog(Map<String, dynamic> msg) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final isMe = msg['senderID'] == _auth.currentUser!.uid;
    final isRecent = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] ?? 0)).inMinutes < 60;
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: 'Delete', transitionDuration: const Duration(milliseconds: 750),
      pageBuilder: (c, a1, a2) => AlertDialog( title: Text(lang.t('chat_delete_confirm_dialog_title')), actions: [ 
          TextButton(onPressed: () { Navigator.pop(c); chatMessageService.deleteMessage(msg['id']); _refreshMessages(); }, child: Text(lang.t('chat_delete_for_me'))), 
          if (isMe && isRecent) TextButton(onPressed: () async { Navigator.pop(c); await _firestore.collection('chat_rooms').doc(_getChatRoomID()).collection('messages').doc(msg['id']).update({'messageType': 'deleted', 'message': ''}); await chatMessageService.deleteMessage(msg['id']); _refreshMessages(); }, child: Text(lang.t('chat_delete_for_everyone'), style: const TextStyle(color: Colors.red))), 
        ]
      ),
      transitionBuilder: (c, a1, a2, child) => ScaleTransition(scale: CurvedAnimation(parent: a1, curve: Curves.easeOutQuart), child: FadeTransition(opacity: a1, child: child)),
    );
  }

  void _retryUpload(String id) async { 
    if (mounted) { setState(() { _uploadProgress.remove(id); final index = _chatItems.indexWhere((it) => it is Map && it['id'] == id); if (index != -1) { final newMsg = Map<String, dynamic>.from(_chatItems[index] as Map); newMsg['status'] = 'uploading'; _chatItems[index] = newMsg; _uploadProgress[id] = 0.02; } }); }
    await chatMessageService.updateMessageStatus(id, 'pending'); syncService.triggerSync(); 
  }

  void _cancelVideoSelection() { if (_isProcessingVideo) FFmpegKit.cancel(); setState(() { _videoEditorController?.dispose(); _videoEditorController = null; _selectedVideoFile = null; _isProcessingVideo = false; _videoProcessingProgress = 0.0; }); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); 
    final isGameActive = _isPreparingInvitation || (_currentGameData != null && _currentGameData!['status'] == 'active');
    ImageProvider? bg;
    if (_chatBackgroundImagePath != null && File(_chatBackgroundImagePath!).existsSync()) bg = FileImage(File(_chatBackgroundImagePath!));
    else if (_globalBackgroundImagePath != null && File(_globalBackgroundImagePath!).existsSync()) bg = FileImage(File(_globalBackgroundImagePath!));
    else bg = const AssetImage('assets/images/star_pattern_dark.png');

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return; _saveDraft();
        if (_isSelectionMode) { setState(() { _isSelectionMode = false; _selectedMessages.clear(); }); return; }
        if (_isEditingMessage) { _cancelEditingMessage(); return; } 
        if (_isAttachmentPanelVisible) { setState(() => _isAttachmentPanelVisible = false); return; }
        if (_selectedImageData != null) { setState(() => _selectedImageData = null); return; }
        if (_videoEditorController != null) { _cancelVideoSelection(); return; }
        if (_stagedVideoFile != null) { _stagedVideoController?.dispose(); setState(() { _stagedVideoController = null; _stagedVideoFile = null; }); return; }
        Navigator.pop(context);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true, extendBodyBehindAppBar: true,
        appBar: _isSelectionMode ? _buildSelectionAppBar() : ChatAppBar( 
          receiverEmail: widget.receiverEmail, receiverID: widget.receiverID, presenceStream: _presenceStream, activityStream: _activityStream, 
          currentUserStream: _currentUserStream, receiverUserStream: _receiverUserStream, onNavigateBack: () { _saveDraft(); Navigator.pop(context); }, 
          onNavigateToContactInfo: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ContactInfoScreen(userID: widget.receiverID, userEmail: widget.receiverEmail))), 
          onMenuSelection: (v, {isReceiverBlocked = false}) => _handleMenuSelection(v, isReceiverBlocked: isReceiverBlocked), 
        ),
        body: Stack(children: [
          Container(color: theme.scaffoldBackgroundColor),
          SafeArea(child: Column(children: [
            ChatGameManager( isPreparingInvitation: _isPreparingInvitation, isWaitingForGameAcceptance: _isWaitingForGameAcceptance, currentGameData: _currentGameData, chatRoomID: _getChatRoomID(), receiverEmail: widget.receiverEmail, onSendInvitation: _sendGameInvitation, onCancelInvitation: () => setState(() { _isPreparingInvitation = false; _isWaitingForGameAcceptance = false; }), onStopGame: _stopGame, ),
            Expanded(child: Stack(children: [
                AnimatedContainer( 
                  duration: const Duration(milliseconds: 600), margin: const EdgeInsets.symmetric(horizontal: 8), clipBehavior: Clip.antiAlias, 
                  decoration: BoxDecoration(color: theme.colorScheme.surface.withAlpha(200), borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)), image: DecorationImage(image: bg, fit: bg is AssetImage ? BoxFit.none : BoxFit.cover, repeat: bg is AssetImage ? ImageRepeat.repeat : ImageRepeat.noRepeat, colorFilter: ColorFilter.mode(Colors.black.withAlpha(128), BlendMode.darken))), 
                  child: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildMessagesList(), 
                ),
                if (_showScrollDownButton) 
                  Positioned(
                    bottom: 20, right: 20, 
                    child: Stack(clipBehavior: Clip.none, children: [
                      FloatingActionButton.small(
                        onPressed: () { _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut); setState(() => _newMessagesCount = 0); }, 
                        backgroundColor: theme.colorScheme.primary.withOpacity(0.8), 
                        child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white)
                      ),
                      if (_newMessagesCount > 0)
                        Positioned(top: -5, left: -5, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: Text('$_newMessagesCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
                    ])
                  ),
            ])),
            if (_isAttachmentPanelVisible) _buildAttachmentPanelContent(),
            _buildComposerContainer(theme, isGameActive),
          ])),
        ]),
      ),
    );
  }

  Widget _buildMessagesList() {
    final theme = Theme.of(context); final lang = Provider.of<LanguageProvider>(context);
    if (!_isLoading && _chatItems.isEmpty) { return Center(child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(15)), child: Column(mainAxisSize: MainAxisSize.min, children: [ const Icon(Icons.lock_outline_rounded, color: Colors.amberAccent, size: 30), const SizedBox(height: 10), Text(lang.t('chat_security_notice'), style: const TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center)]))); }
    return ListView.builder(
      reverse: true, controller: _scrollController, itemCount: _chatItems.length,
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
      cacheExtent: 1000, 
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, 
      itemBuilder: (context, i) {
        final item = _chatItems[i];
        if (item is String) return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Chip(label: Text(item, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), backgroundColor: theme.cardColor.withAlpha(204))));
        final msg = item as Map<String, dynamic>; final msgId = msg['id'];
        bool isFirst = true, isLast = true;
        if (i > 0 && _chatItems[i-1] is Map) { if (_chatItems[i-1]['senderID'] == msg['senderID']) isFirst = false; }
        if (i < _chatItems.length - 1 && _chatItems[i+1] is Map) { if (_chatItems[i+1]['senderID'] == msg['senderID']) isLast = false; }
        return AutoScrollTag(key: ValueKey(msgId), controller: _scrollController, index: i, child: MessageBubble( messageData: msg, isMe: msg['senderID'] == _auth.currentUser!.uid, isSelected: _selectedMessages.contains(msgId), receiverDisplayName: widget.receiverEmail, uploadProgress: _uploadProgress[msgId], isHighlighted: _highlightedMessageId == msgId, isFirstInGroup: isFirst, isLastInGroup: isLast, 
          onSwipeReply: (m) { 
            HapticFeedback.lightImpact(); 
            setState(() { _replyingToMessage = m; _isEditingMessage = false; _isEmojiPickerVisible = false; _isAttachmentPanelVisible = false; }); 
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) { _focusNode.requestFocus(); SystemChannels.textInput.invokeMethod('TextInput.show'); }
            });
          }, 
          onReplyTap: (id) => _scrollToMessage(id), onLongPress: (id) => _toggleSelection(id), onTap: (id) { if(_isSelectionMode) _toggleSelection(id); }, 
          onAcceptInvitation: () => _createGameInFirestore(msg), onDeclineInvitation: (m) => _handleDeclineInvitation(m), onDelete: () => _showDeleteDialog(msg), onRetryUpload: () => _retryUpload(msgId), onEdit: () => _onEditMessage(msg), 
        ));
      },
    );
  }

  Widget _buildComposerContainer(ThemeData theme, bool isGameActive) {
    final lang = Provider.of<LanguageProvider>(context);
    if (_selectedImageData != null) return PhotoPreviewComposer(imageData: _selectedImageData!, captionController: _captionController, onCancel: () => setState(() => _selectedImageData = null), onSend: () => _sendPhoto(), onImageEdited: (b) => setState(() => _selectedImageData = b));
    if (_videoEditorController != null) return VideoEditorComposer(controller: _videoEditorController!, isProcessing: _isProcessingVideo, processingProgress: _videoProcessingProgress, onCancel: _cancelVideoSelection, onSave: _processAndStageVideo);
    if (_stagedVideoController != null) return StagedVideoPreview(controller: _stagedVideoController!, captionController: _captionController, onCancel: () => setState(() { _stagedVideoController?.dispose(); _stagedVideoController = null; _stagedVideoFile = null; }), onSend: () => _sendStagedVideo());
    return StreamBuilder<DocumentSnapshot>(
      stream: _currentUserStream,
      builder: (context, snapMe) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _receiverUserStream,
          builder: (context, snapThem) {
            bool isMeBlocked = false, isThemBlocked = false;
            if (snapMe.hasData && snapMe.data!.exists) isThemBlocked = (snapMe.data!.data() as Map?)?['blockedUsers']?.contains(widget.receiverID) ?? false;
            if (snapThem.hasData && snapThem.data!.exists) isMeBlocked = (snapThem.data!.data() as Map?)?['blockedUsers']?.contains(_auth.currentUser?.uid) ?? false;
            if (isMeBlocked || isThemBlocked) { WidgetsBinding.instance.addPostFrameCallback((_) => _forceHideKeyboard()); return Container(padding: const EdgeInsets.all(20), margin: const EdgeInsets.all(10), decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.9), borderRadius: BorderRadius.circular(20)), child: Text(isThemBlocked ? lang.t('chat_user_is_blocked_sender') : lang.t('chat_user_is_blocked_receiver'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))); }
            return StreamBuilder<DatabaseEvent>( stream: _presenceStream, builder: (context, presenceSnapshot) {
                String hint = lang.t('chat_message_input_hint');
                if (presenceSnapshot.hasData && presenceSnapshot.data!.snapshot.value != null) { try { final d = presenceSnapshot.data!.snapshot.value as Map; if (d['state'] == 'offline') hint = _formatLastSeen(d['last_changed']); } catch (_) {} }
                if (isGameActive) hint = lang.t('chat_voice_in_game_hint');
                return Column(children: [ if (_isEditingMessage) _buildEditBar(theme), if (_replyingToMessage != null && !_isEditingMessage) _buildReplyBar(theme, lang), _buildComposer(theme, hint, isGameActive) ]);
              }
            );
          }
        );
      }
    );
  }

  Widget _buildEditBar(ThemeData t) => Container(padding: const EdgeInsets.all(10), margin: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))), child: Row(children: [ const Icon(Icons.edit, size: 16, color: Colors.blue), const SizedBox(width: 10), const Expanded(child: Text("Editing message", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13))), IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _cancelEditingMessage) ]));
  Widget _buildReplyBar(ThemeData theme, LanguageProvider lang) {
    final type = _replyingToMessage!['messageType']; String txt = _replyingToMessage!['message'] ?? ""; IconData? icon;
    if (type == 'image') { txt = lang.t('chat_reply_photo'); icon = Icons.photo_camera; } else if (type == 'video') { txt = lang.t('chat_reply_video'); icon = Icons.videocam; } else if (type == 'voice_note') { txt = lang.t('chat_reply_voice_note'); icon = Icons.mic; } else if (type == 'audio_file') { txt = lang.t('chat_reply_audio_file'); icon = Icons.headset; } else if (type == 'document') { txt = _replyingToMessage!['fileName'] ?? lang.t('chat_reply_document'); icon = Icons.insert_drive_file; }
    return Container(padding: const EdgeInsets.all(10), margin: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: theme.colorScheme.surface.withAlpha(200), borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))), child: Row(children: [ Container(width: 4, height: 40, color: theme.colorScheme.primary), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(lang.t('chat_reply_to_yourself'), style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 13)), Row(children: [ if (icon != null) Icon(icon, size: 14, color: Colors.grey), if (icon != null) const SizedBox(width: 5), Expanded(child: Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))) ]) ])), IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyingToMessage = null)) ]));
  }

  Widget _buildComposer(ThemeData t, String hint, bool isGV) => Container(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 25), decoration: BoxDecoration(color: t.scaffoldBackgroundColor, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
    child: Stack(alignment: Alignment.bottomRight, children: [
        Material(elevation: 2, shadowColor: Colors.black26, borderRadius: BorderRadius.circular(30), child: Container(constraints: const BoxConstraints(minHeight: 56), padding: const EdgeInsets.only(right: 58), decoration: BoxDecoration(color: t.cardColor, borderRadius: BorderRadius.circular(30)), child: Row(children: [
              IconButton(icon: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: _isEmojiPickerVisible ? const Icon(Icons.keyboard_rounded, key: ValueKey('kb'), color: Colors.blue, size: 30) : Container(key: const ValueKey('e'), padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.amber.shade300, Colors.amber.shade700])), child: const Icon(Icons.face_retouching_natural_rounded, color: Colors.white, size: 28))), onPressed: isGV ? null : _toggleEmojiPicker),
              Expanded(child: TextField(
                focusNode: _focusNode, 
                controller: _messageController, 
                maxLines: 5, minLines: 1, readOnly: isGV, 
                style: const TextStyle(fontSize: 15.5), 
                onTap: () { if (mounted) setState(() { _isEmojiPickerVisible = false; _isAttachmentPanelVisible = false; }); }, 
                decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(fontSize: 13, color: t.textTheme.bodySmall?.color?.withAlpha(128)), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10))
              )),
              IconButton(icon: Icon(Icons.attach_file_rounded, color: t.iconTheme.color?.withAlpha(179)), onPressed: isGV ? null : () { _forceHideKeyboard(); if (MediaQuery.of(context).viewInsets.bottom > 100) setState(() => _isAttachmentPanelVisible = !_isAttachmentPanelVisible); else _showAnimatedMenu(); }),
            ]))),
        Positioned(bottom: 2, right: 0, child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: (_isComposing || _isEditingMessage || _replyingToMessage != null) && !isGV 
              ? FloatingActionButton(key: const ValueKey('s'), mini: false, elevation: 4, backgroundColor: _isEditingMessage ? Colors.green : t.colorScheme.primary, child: Icon(_isEditingMessage ? Icons.check : Icons.send_rounded, color: Colors.white), onPressed: () => _sendMessage())
              : SocialMediaRecorder(key: const ValueKey('m'), startRecording: () => _myActivityStatusRef?.set("recording"), stopRecording: (time) => _myActivityStatusRef?.set("idle"), sendRequestFunction: (f, d) { _myActivityStatusRef?.set("idle"); _sendVoiceMessage(f, d); }, recordIcon: FloatingActionButton(elevation: 4, backgroundColor: t.colorScheme.secondary, child: const Icon(Icons.mic_none_rounded, color: Colors.white), onPressed: () {})))),
    ]),
  );

  void _showAnimatedMenu() { showGeneralDialog(context: context, barrierDismissible: true, barrierLabel: 'M', barrierColor: Colors.black26, transitionDuration: const Duration(milliseconds: 400), pageBuilder: (ctx, a1, a2) => Align(alignment: Alignment.bottomCenter, child: _buildAttachmentPanelContent(isDialog: true)), transitionBuilder: (ctx, a1, a2, child) => SlideTransition(position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a1, curve: Curves.easeOutBack)), child: FadeTransition(opacity: a1, child: child))); }

  Widget _buildAttachmentPanelContent({bool isDialog = false}) { 
    void close() { if (isDialog) Navigator.pop(context); else setState(() => _isAttachmentPanelVisible = false); }
    return ChatAttachmentPanel( 
      onCameraTap: () async { close(); final i = await ImagePicker().pickImage(source: ImageSource.camera); if(i != null) setState(() { _selectedImageData = File(i.path).readAsBytesSync(); }); }, 
      onPhotoTap: () async { close(); final i = await ImagePicker().pickImage(source: ImageSource.gallery); if(i != null) setState(() { _selectedImageData = File(i.path).readAsBytesSync(); }); }, 
      onVideoTap: () async { close(); final v = await ImagePicker().pickVideo(source: ImageSource.gallery); if(v != null) { final controller = VideoEditorController.file(File(v.path), maxDuration: const Duration(minutes: 5)); await controller.initialize(); if (mounted) setState(() { _selectedVideoFile = File(v.path); _videoEditorController = controller; }); } }, 
      onAudioTap: () async { close(); final res = await FilePicker.platform.pickFiles(type: FileType.audio); if(res != null) { final perm = await mediaUploadService.saveFilePermanently(res.files.single.path!); final data = {'id': const Uuid().v4(), 'chatRoomID': _getChatRoomID(), 'senderID': _auth.currentUser!.uid, 'receiverID': widget.receiverID, 'messageType': 'audio_file', 'localPath': perm, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'status': 'uploading', 'fileName': res.files.single.name, 'isEdited': 0, 'isPlayed': 0}; chatMessageService.saveMessage(data).then((_) { _addOptimisticMessage(data); mediaUploadService.sendMediaMessageFromData(data); }); } }, 
      onDocumentTap: () async { close(); final res = await FilePicker.platform.pickFiles(type: FileType.any); if(res != null) { final perm = await mediaUploadService.saveFilePermanently(res.files.single.path!); final data = {'id': const Uuid().v4(), 'chatRoomID': _getChatRoomID(), 'senderID': _auth.currentUser!.uid, 'receiverID': widget.receiverID, 'messageType': 'document', 'localPath': perm, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'status': 'uploading', 'fileName': res.files.single.name, 'isEdited': 0, 'isPlayed': 0}; chatMessageService.saveMessage(data).then((_) { _addOptimisticMessage(data); mediaUploadService.sendMediaMessageFromData(data); }); } }, 
      onContactTap: () async { close(); await mediaUploadService.sendContact(context, chatRoomID: _getChatRoomID(), receiverID: widget.receiverID); _refreshMessages(); }, 
      onDameTap: () { close(); _forceHideKeyboard(); setState(() { _isPreparingInvitation = true; }); }, 
      onLudoTap: () { close(); final lang = Provider.of<LanguageProvider>(context, listen: false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ludo ${lang.t('chat_coming_soon_game')}"), backgroundColor: Colors.indigo, behavior: SnackBarBehavior.floating)); }, 
      onClose: close, 
    ); 
  }

  AppBar _buildSelectionAppBar() { final lang = Provider.of<LanguageProvider>(context); return AppBar( backgroundColor: Colors.blueGrey[800], title: Text("${_selectedMessages.length} ${lang.t('chat_selection_bar_title')}"), actions: [ if (_selectedMessages.length == 1) IconButton(icon: const Icon(Icons.reply), onPressed: _onReplyFromSelection), IconButton(icon: const Icon(Icons.share), onPressed: _onShare), IconButton(icon: const Icon(Icons.copy), onPressed: _onCopy), IconButton(icon: const Icon(Icons.delete), onPressed: () async { for (var id in _selectedMessages) await chatMessageService.deleteMessage(id); setState(() { _isSelectionMode = false; _selectedMessages.clear(); }); _refreshMessages(); }), ] ); }

  Future<void> _loadWallpapers() async { final prefs = await SharedPreferences.getInstance(); if (mounted) setState(() { _globalBackgroundImagePath = prefs.getString('wallpaperPath'); _chatBackgroundImagePath = prefs.getString('wallpaperPath_${_getChatRoomID()}'); }); }

  @override
  void dispose() { 
    syncService.currentActiveChatId = null;
    _seenStatusSubscription?.cancel(); // ✅ Funga Real-Time Listener
    _saveDraft(); _scrollController.removeListener(_scrollListener); _scrollController.dispose(); _gameStreamSubscription?.cancel(); _uiUpdateSubscription?.cancel(); _uploadProgressSubscription?.cancel(); _messageController.dispose(); _captionController.dispose(); _stagedVideoController?.dispose(); _videoEditorController?.dispose(); _focusNode.dispose(); _myActivityStatusRef?.set("idle"); WidgetsBinding.instance.removeObserver(this); super.dispose(); 
  }
}