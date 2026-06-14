// lib/chat_screen.dart (VERSION 6.55 - BLOCK LOGIC + PERSISTENT SEEN + DEEP LINK)
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

import 'widgets/chat/chat_app_bar.dart';
import 'widgets/chat/message_bubble.dart';
import 'widgets/chat/chat_attachment_panel.dart';
import 'widgets/chat/staged_media_widgets.dart';
import 'widgets/chat/chat_game_manager.dart';
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
  final String receiverEmail, receiverID;
  const ChatScreenWrapper({super.key, required this.receiverEmail, required this.receiverID});
  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => AudioPlayerService())], 
    child: ChatScreen(receiverEmail: receiverEmail, receiverID: receiverID)
  );
}

class ChatScreen extends StatefulWidget {
  final String receiverEmail, receiverID;
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
  
  int _currentOffset = 0, _otherUserLastReadTs = 0; 
  final int _pageSize = 30;
  bool _isFetchingMore = false, _hasMoreMessages = true, _isEditingMessage = false, _showScrollDownButton = false;
  String? _editingMessageId, _highlightedMessageId;
  int _newMessagesCount = 0; 
  
  Stream<DocumentSnapshot>? _currentUserStream, _receiverUserStream;
  Stream<DatabaseEvent>? _presenceStream, _activityStream;
  DatabaseReference? _myActivityStatusRef;
  StreamSubscription? _gameStreamSubscription, _uiUpdateSubscription, _uploadProgressSubscription, _roomSubscription;
  
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
  Timer? _typingTimer, _highlightTimer; 
  DateTime? _timeWhenPaused;
  String _selectedEmojiCategory = "😊";

  @override
  void initState() {
    super.initState(); 
    syncService.currentActiveChatId = _getChatRoomID(); 
    _scrollController = AutoScrollController(axis: Axis.vertical);
    _scrollController.addListener(_scrollListener); 
    WidgetsBinding.instance.addObserver(this);
    
    _initStreams(); 
    _initListeners(); 
    _loadCachedSeenTs();

    _loadLocalMessagesOnly().then((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _startBackgroundOperations();
      });
    });
    
    _loadDraft(); 
  }

  void _startBackgroundOperations() {
    _loadWallpapers();
    _updateReceivedMessagesStatusToSeen();
    _syncFirestoreMessagesSilently(); 
    _listenForGameUpdates();
    _listenToRoomStatus(); 
    syncService.triggerSync();
  }

  Future<void> _loadCachedSeenTs() async {
    final prefs = await SharedPreferences.getInstance();
    int? cached = prefs.getInt('seen_ts_${_getChatRoomID()}');
    if (cached != null && mounted) setState(() { _otherUserLastReadTs = cached; });
  }

  Future<void> _saveCachedSeenTs(int ts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('seen_ts_${_getChatRoomID()}', ts);
  }

  void _listenToRoomStatus() {
    _roomSubscription = _firestore.collection('chat_rooms').doc(_getChatRoomID()).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        final data = snap.data() as Map<String, dynamic>;
        final Map? tsMap = data['lastReadTimestamps'];
        if (tsMap != null && tsMap[widget.receiverID] != null) {
          int ts = (tsMap[widget.receiverID] as Timestamp).millisecondsSinceEpoch;
          if (ts != _otherUserLastReadTs) {
             _saveCachedSeenTs(ts); 
             setState(() { _otherUserLastReadTs = ts; });
             _refreshMessages(); 
          }
        }
      }
    });
  }

  String _getChatRoomID() { 
    final uid = _auth.currentUser?.uid ?? ""; 
    List<String> ids = [uid, widget.receiverID]; 
    ids.sort(); return ids.join('_'); 
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) { 
      if (!_isFetchingMore && _hasMoreMessages) _loadMoreMessages(); 
    }
    if (_scrollController.offset <= 100 && _newMessagesCount > 0) setState(() => _newMessagesCount = 0);
    final bool s = _scrollController.offset > 400; 
    if (s != _showScrollDownButton) setState(() => _showScrollDownButton = s);
  }

  void _updateChatItems(List<Map<String, dynamic>> messages) {
    if (messages.isEmpty) { _chatItems = ['E2EE_NOTICE']; return; }
    List<dynamic> items = [];
    final sorted = List<Map<String, dynamic>>.from(messages)..sort((a, b) => (b['timestamp'] as int? ?? 0).compareTo(a['timestamp'] as int? ?? 0));
    for (int i = 0; i < sorted.length; i++) {
      final msg = sorted[i]; 
      final date = DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int? ?? 0); 
      items.add(msg);
      if (i + 1 < sorted.length) {
        final nextDate = DateTime.fromMillisecondsSinceEpoch(sorted[i+1]['timestamp'] as int? ?? 0);
        if (!isSameDay(date, nextDate)) items.add(_formatDateSeparator(date));
      } else { items.add(_formatDateSeparator(date)); }
    } 
    if (!_hasMoreMessages) items.add('E2EE_NOTICE');
    _chatItems = items;
  }

  bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  String _formatDateSeparator(DateTime d) {
    final lang = Provider.of<LanguageProvider>(context, listen: false); 
    if (isSameDay(d, DateTime.now())) return lang.t('chat_date_separator_today');
    if (isSameDay(d, DateTime.now().subtract(const Duration(days: 1)))) return lang.t('chat_date_separator_yesterday');
    return DateFormat.yMMMMd(lang.currentLanguage == 'fr' ? 'fr_FR' : 'en_US').format(d);
  }

  String _formatLastSeen(int ts) {
    final lang = Provider.of<LanguageProvider>(context, listen: false); 
    final ls = DateTime.fromMillisecondsSinceEpoch(ts); 
    final now = DateTime.now(); 
    String time = DateFormat.Hm().format(ls);
    if (isSameDay(ls, now)) return "${lang.t('chat_last_seen_prefix')} $time";
    if (isSameDay(ls, now.subtract(const Duration(days: 1)))) return "${lang.t('chat_last_seen_yesterday_prefix')} $time";
    return "${lang.t('chat_last_seen_date_prefix')} ${DateFormat('dd/MM').format(ls)} $time";
  }

  Future<void> _loadWallpapers() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() { 
      _globalBackgroundImagePath = prefs.getString('wallpaperPath'); 
      _chatBackgroundImagePath = prefs.getString('wallpaperPath_${_getChatRoomID()}'); 
    });
  }

  Future<void> _loadLocalMessagesOnly() async {
    try {
      _currentOffset = 0; _hasMoreMessages = true;
      final local = await chatMessageService.getMessagesPaged(chatRoomID: _getChatRoomID(), limit: _pageSize, offset: 0);
      if (mounted) setState(() { _messages = List<Map<String, dynamic>>.from(local); _updateChatItems(_messages); _isLoading = false; });
      _scrollToMostRecent();
    } catch (_) { if(mounted) setState(() => _isLoading = false); }
  }

  Future<void> _syncFirestoreMessagesSilently() async {
    final chatID = _getChatRoomID(); final prefs = await SharedPreferences.getInstance();
    final clearTs = prefs.getInt('chat_clear_timestamp_$chatID') ?? 0;
    final lastTs = _messages.isNotEmpty ? _messages.first['timestamp'] as int : 0;
    final startTs = lastTs > clearTs ? lastTs : clearTs;
    try {
      final snap = await _firestore.collection('chat_rooms').doc(chatID).collection('messages').where('timestamp', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(startTs)).orderBy('timestamp').get();
      if (snap.docs.isNotEmpty) {
        for (var doc in snap.docs) {
          final data = doc.data(); 
          if (data['timestamp'] is Timestamp) data['timestamp'] = (data['timestamp'] as Timestamp).millisecondsSinceEpoch;
          await chatMessageService.saveMessage({...data, 'id': doc.id, 'chatRoomID': chatID});
        }
        _refreshMessages();
      }
    } catch (_) {}
  }

  void _initStreams() {
    final uid = _auth.currentUser?.uid; if (uid == null) return; final rId = _getChatRoomID();
    _currentUserStream = _firestore.collection('users').doc(uid).snapshots();
    _receiverUserStream = _firestore.collection('users').doc(widget.receiverID).snapshots();
    _presenceStream = FirebaseDatabase.instance.ref('status/${widget.receiverID}').onValue.asBroadcastStream();
    _myActivityStatusRef = FirebaseDatabase.instance.ref('activity/$rId/$uid');
    _activityStream = FirebaseDatabase.instance.ref('activity/$rId/${widget.receiverID}').onValue.asBroadcastStream();
  }

  void _initListeners() {
    _uiUpdateSubscription = syncService.uiMessageUpdateStream.listen((event) {
      if (mounted) {
        if (event.startsWith("message_received:")) {
          final String incomingRoomId = event.split(":").last;
          if (incomingRoomId == _getChatRoomID()) {
            Provider.of<AudioPlayerService>(context, listen: false).playNotificationSound('assets/audio/incoming_sound.mp3');
            if (_scrollController.offset > 200) setState(() => _newMessagesCount++);
            _updateReceivedMessagesStatusToSeen(); 
          }
        } 
        _refreshMessages();
      }
    });

    _uploadProgressSubscription = syncService.uploadProgressStream.listen((data) {
      if (mounted) { 
        String mId = data['messageId']; double p = (data['progress'] as num).toDouble();
        setState(() { 
          if (p >= 1.0) { 
            _uploadProgress.remove(mId); 
            Provider.of<AudioPlayerService>(context, listen: false).playNotificationSound('assets/audio/sent_sound.mp3');
            _refreshMessages(); 
          } else {
            _uploadProgress[mId] = p.clamp(0.0, 1.0); 
          }
        });
      }
    });
    _messageController.addListener(() { if (mounted) { setState(() => _isComposing = _messageController.text.trim().isNotEmpty); _updateTypingStatus(); } });
  }

  void _listenForGameUpdates() {
    _gameStreamSubscription = _firestore.collection('games').doc(_getChatRoomID()).snapshots().listen((snap) {
      if (mounted) {
        setState(() { 
          _currentGameData = snap.exists ? snap.data() : null; 
          if (snap.exists && _currentGameData?['status'] == 'active') {
            _isWaitingForGameAcceptance = false;
            _isPreparingInvitation = false;
          }
        });
      }
    });
  }

  Future<void> _createGameInFirestore(Map<String, dynamic> msg) async {
    final rId = _getChatRoomID();
    await chatMessageService.deleteMessage(msg['id']);
    final Map<String, dynamic> board = {};
    for (int r = 0; r < 10; r++) board[r.toString()] = List.generate(10, (c) => ((r + c) % 2 != 0) ? (r < 4 ? {'player': 2, 'type': 'man'} : (r > 5 ? {'player': 1, 'type': 'man'} : null)) : null);
    await _firestore.collection('games').doc(rId).set({ 'boardState': board, 'player1Id': msg['senderID'], 'player2Id': _auth.currentUser!.uid, 'turn': msg['senderID'], 'status': 'active', 'player1Score': 0, 'player2Score': 0, 'createdAt': FieldValue.serverTimestamp() });
    _refreshMessages();
  }

  Future<void> _handleDeclineInvitation(Map<String, dynamic> msg) async { 
    _sendMessage(type: 'dame_invitation_declined', text: Provider.of<LanguageProvider>(context, listen: false).t('chat_invitation_declined_message'));
    await chatMessageService.deleteMessage(msg['id']); 
    _refreshMessages();
  }

  void _stopGame() async { await _firestore.collection('games').doc(_getChatRoomID()).delete(); }

  Future<void> _updateReceivedMessagesStatusToSeen() async {
    final rId = _getChatRoomID(); final uid = _auth.currentUser?.uid; if (uid == null) return;
    _firestore.collection('chat_rooms').doc(rId).set({ 'lastReadTimestamps': { uid: FieldValue.serverTimestamp() } }, SetOptions(merge: true));
    await DatabaseHelper.instance.markMessagesAsRead(rId, uid);
    syncService.notifyUIMessageUpdate("refresh_badges");
  }

  Future<void> _clearChat() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showDialog(context: context, builder: (c) => AlertDialog(title: Text(lang.t('chat_clear_chat_dialog_title')), actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: Text(lang.t('chat_clear_chat_dialog_no'))),
      TextButton(onPressed: () async { Navigator.pop(c); setState(() => _isLoading = true); final rId = _getChatRoomID(); final now = DateTime.now().millisecondsSinceEpoch; final prefs = await SharedPreferences.getInstance(); await prefs.setInt('chat_clear_timestamp_$rId', now); await chatMessageService.clearChatHistory(rId); await _refreshMessages(); if(mounted) setState(() => _isLoading = false); }, child: Text(lang.t('chat_clear_chat_dialog_yes')))
    ]));
  }

  Future<void> _showWallpaperDialog() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false); final prefs = await SharedPreferences.getInstance();
    showDialog(context: context, builder: (c) => AlertDialog(title: Text(lang.t('wallpaper')), content: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo_library), title: Text(lang.t('btn_change_photo')), onTap: () async { Navigator.pop(c); final img = await ImagePicker().pickImage(source: ImageSource.gallery); if (img != null) { await prefs.setString('wallpaperPath_${_getChatRoomID()}', img.path); if(mounted) setState(() { _chatBackgroundImagePath = img.path; }); } }),
      if (_chatBackgroundImagePath != null) ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: Text(lang.t('btn_remove_photo')), onTap: () async { Navigator.pop(c); await prefs.remove('wallpaperPath_${_getChatRoomID()}'); if(mounted) setState(() { _chatBackgroundImagePath = null; }); }),
    ])));
  }

  Future<void> _loadMoreMessages() async {
    if (_isFetchingMore || !_hasMoreMessages) return; 
    setState(() => _isFetchingMore = true); _currentOffset += _pageSize;
    final more = await chatMessageService.getMessagesPaged(chatRoomID: _getChatRoomID(), limit: _pageSize, offset: _currentOffset);
    if (mounted) setState(() { if (more.isEmpty) _hasMoreMessages = false; else { _messages.addAll(more); _updateChatItems(_messages); } _isFetchingMore = false; });
  }

  Future<void> _refreshMessages() async {
    final local = await chatMessageService.getMessagesPaged(chatRoomID: _getChatRoomID(), limit: _pageSize, offset: 0);
    if (mounted) setState(() { _messages = List<Map<String, dynamic>>.from(local); _updateChatItems(_messages); });
  }

  void _updateTypingStatus() { _typingTimer?.cancel(); if (_messageController.text.trim().isNotEmpty) { _myActivityStatusRef?.set("typing"); _typingTimer = Timer(const Duration(seconds: 2), () => _myActivityStatusRef?.set("idle")); } else _myActivityStatusRef?.set("idle"); }
  Future<void> _loadDraft() async { final p = await SharedPreferences.getInstance(); final d = p.getString('draft_${_getChatRoomID()}'); if (d != null) setState(() => _messageController.text = d); }
  Future<void> _saveDraft() async { final p = await SharedPreferences.getInstance(); final t = _messageController.text.trim(); if (t.isNotEmpty) await p.setString('draft_${_getChatRoomID()}', t); else await p.remove('draft_${_getChatRoomID()}'); }
  void _scrollToMostRecent() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.jumpTo(0.0); }); }
  void _scrollToMessage(String id) { final idx = _chatItems.indexWhere((it) => it is Map && it['id'] == id); if (idx != -1) { _scrollController.scrollToIndex(idx, preferPosition: AutoScrollPosition.middle, duration: const Duration(milliseconds: 600)); setState(() => _highlightedMessageId = id); _highlightTimer?.cancel(); _highlightTimer = Timer(const Duration(seconds: 2), () { if (mounted) setState(() => _highlightedMessageId = null); }); } }
  void _forceHideKeyboard() { _focusNode.unfocus(); FocusScope.of(context).unfocus(); SystemChannels.textInput.invokeMethod('TextInput.hide'); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { 
    if (state == AppLifecycleState.paused) { _timeWhenPaused = DateTime.now(); _saveDraft(); } 
    else if (state == AppLifecycleState.resumed) { _updateReceivedMessagesStatusToSeen(); _refreshMessages(); }
  }

  void _addOptimisticMessage(Map<String, dynamic> d) {
    if (!mounted) return;
    setState(() { _messages = [d, ..._messages]; _updateChatItems(_messages); });
    _scrollToMostRecent();
  }

  void _sendMessage({String? text, String type = 'text'}) async {
    final txt = text ?? _messageController.text.trim(); if (txt.isEmpty && type == 'text') return;
    if (type == 'dame_invitation') setState(() => _isWaitingForGameAcceptance = true);
    if (_isEditingMessage && _editingMessageId != null) { 
      final mId = _editingMessageId!; _cancelEditingMessage(); 
      await chatMessageService.updateMessageContent(chatRoomID: _getChatRoomID(), messageId: mId, newText: txt); 
      _refreshMessages(); syncService.triggerSync(); return; 
    }
    final mId = const Uuid().v4();
    final d = { 'id': mId, 'chatRoomID': _getChatRoomID(), 'senderID': _auth.currentUser!.uid, 'receiverID': widget.receiverID, 'messageType': type, 'message': txt, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'status': 'pending', 'replyingTo': _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null, 'isEdited': 0, 'isPlayed': 0 };
    if (type == 'text') _messageController.clear();
    await chatMessageService.saveMessage(d); _addOptimisticMessage(d); 
    if (mounted) setState(() => _replyingToMessage = null);
    
    _firestore.collection('chat_rooms').doc(_getChatRoomID()).collection('messages').doc(mId).set({ 
      ...d, 'timestamp': FieldValue.serverTimestamp(), 'status': 'sent', 'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 4))) 
    }).then((_) { 
      Provider.of<AudioPlayerService>(context, listen: false).playNotificationSound('assets/audio/sent_sound.mp3');
      chatMessageService.updateMessageStatus(mId, 'sent'); 
      syncService.notifyUIMessageUpdate("refresh_ui"); 
    });
    
    _firestore.collection('chat_rooms').doc(_getChatRoomID()).set({ 'lastMessage': txt, 'lastMessageSenderID': _auth.currentUser!.uid, 'lastMessageTimestamp': FieldValue.serverTimestamp(), 'lastMessageType': type }, SetOptions(merge: true));
    HapticFeedback.lightImpact();
  }

  Future<void> _sendPhoto() async { 
    if (_selectedImageData == null) return; 
    final imgD = _selectedImageData!; final cap = _captionController.text.trim(); 
    setState(() { _selectedImageData = null; _captionController.clear(); _replyingToMessage = null; }); 
    final tPath = path.join((await getTemporaryDirectory()).path, '${const Uuid().v4()}.png'); 
    await File(tPath).writeAsBytes(imgD); 
    final perm = await mediaUploadService.saveFilePermanently(tPath); 
    final d = _createMediaData('image', perm); d['message'] = cap; 
    await chatMessageService.saveMessage(d); _addOptimisticMessage(d); 
    mediaUploadService.sendMediaMessageFromData(d); 
  }

  Future<void> _sendStagedVideo() async { 
    if (_stagedVideoFile == null) return; 
    final vFile = _stagedVideoFile!; final tPath = _stagedThumbnailPath; final cap = _captionController.text.trim(); 
    _stagedVideoController?.dispose(); 
    setState(() { _stagedVideoController = null; _stagedVideoFile = null; _stagedThumbnailPath = null; _captionController.clear(); _replyingToMessage = null; }); 
    final d = _createMediaData('video', vFile.path); d['thumbnailLocalPath'] = tPath; d['message'] = cap; 
    await chatMessageService.saveMessage(d); _addOptimisticMessage(d); 
    mediaUploadService.sendMediaMessageFromData(d); 
  }

  Future<void> _sendVoiceMessage(File soundF, String duration) async { 
    int dur = 0; try { final p = duration.split(':'); if (p.length == 2) dur = int.parse(p[0]) * 60 + int.parse(p[1]); } catch (_) {} 
    final mId = const Uuid().v4(); 
    final d = { 'id': mId, 'chatRoomID': _getChatRoomID(), 'senderID': _auth.currentUser!.uid, 'receiverID': widget.receiverID, 'messageType': 'voice_note', 'timestamp': DateTime.now().millisecondsSinceEpoch, 'status': 'pending', 'localPath': soundF.path, 'storagePath': "chats/${_getChatRoomID()}/voices/$mId${path.extension(soundF.path)}", 'duration': dur, 'fileName': path.basename(soundF.path), 'replyingTo': _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null, 'isEdited': 0, 'isPlayed': 0 }; 
    await chatMessageService.saveMessage(d); _addOptimisticMessage(d); 
    Future.delayed(const Duration(milliseconds: 300), () => syncService.triggerSync());
    if (mounted) setState(() => _replyingToMessage = null); 
  }

  Map<String, dynamic> _createMediaData(String t, String p) => { 'id': const Uuid().v4(), 'chatRoomID': _getChatRoomID(), 'senderID': _auth.currentUser!.uid, 'receiverID': widget.receiverID, 'messageType': t, 'localPath': p, 'timestamp': DateTime.now().millisecondsSinceEpoch, 'status': 'uploading', 'fileName': p.split('/').last, 'replyingTo': _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null, 'isEdited': 0, 'isPlayed': 0 };

  void _retryUpload(String id) async { await chatMessageService.updateMessageStatus(id, 'pending'); syncService.triggerSync(); }

  Future<void> _processAndStageVideo() async {
    if (_videoEditorController == null || _selectedVideoFile == null) return; setState(() => _isProcessingVideo = true); _forceHideKeyboard(); 
    try {
      final thumbFuture = mediaUploadService.generateThumbnail(_selectedVideoFile!.path); 
      final outPath = path.join((await getTemporaryDirectory()).path, 'trimmed_${const Uuid().v4()}.mp4');
      final command = '-ss ${_videoEditorController!.startTrim.inSeconds}.${_videoEditorController!.startTrim.inMilliseconds.remainder(1000)} -i "${_selectedVideoFile!.path}" -t ${_videoEditorController!.trimmedDuration.inSeconds}.${_videoEditorController!.trimmedDuration.inMilliseconds.remainder(1000)} -c:v libx264 -preset ultrafast -crf 28 -y "$outPath"';
      await FFmpegKit.executeAsync(command, (session) async {
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) { 
          final perm = await mediaUploadService.saveFilePermanently(outPath); final t = await thumbFuture; 
          _stagedVideoController = VideoPlayerController.file(File(perm)); await _stagedVideoController!.initialize(); _stagedVideoController!.setLooping(true); 
          if (mounted) setState(() { _stagedVideoFile = File(perm); _stagedThumbnailPath = t; _isProcessingVideo = false; _videoEditorController?.dispose(); _videoEditorController = null; _selectedVideoFile = null; }); 
        } else if (mounted) setState(() => _isProcessingVideo = false);
      }, null, (stats) { final dur = _videoEditorController!.trimmedDuration.inMilliseconds; if (dur > 0 && mounted) setState(() => _videoProcessingProgress = (stats.getTime() / dur).clamp(0.0, 1.0)); });
    } catch (_) { if (mounted) setState(() => _isProcessingVideo = false); }
  }

  void _cancelVideoSelection() { if (_isProcessingVideo) FFmpegKit.cancel(); setState(() { _videoEditorController?.dispose(); _videoEditorController = null; _selectedVideoFile = null; _isProcessingVideo = false; }); }

  // 🔥 IYI NIYO LOGIC YA BLOCKING NYAKURI
  void _toggleBlock(bool isReceiverBlocked) async { 
    final ref = _firestore.collection('users').doc(_auth.currentUser!.uid);
    if (isReceiverBlocked) {
      await ref.update({'blockedUsers': FieldValue.arrayRemove([widget.receiverID])}); 
    } else {
      await ref.update({'blockedUsers': FieldValue.arrayUnion([widget.receiverID])}); 
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); final lang = Provider.of<LanguageProvider>(context);
    final isGV = _isPreparingInvitation || (_currentGameData != null && _currentGameData!['status'] == 'active');
    
    return StreamBuilder<DocumentSnapshot>(
      stream: _currentUserStream,
      builder: (context, snapMe) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _receiverUserStream,
          builder: (context, snapThem) {
            bool isThemBlocked = false, isMeBlocked = false;
            if (snapMe.hasData && snapMe.data!.exists) {
              isThemBlocked = (snapMe.data!.data() as Map?)?['blockedUsers']?.contains(widget.receiverID) ?? false;
            }
            if (snapThem.hasData && snapThem.data!.exists) {
              isMeBlocked = (snapThem.data!.data() as Map?)?['blockedUsers']?.contains(_auth.currentUser?.uid) ?? false;
            }

            ImageProvider bg; 
            if (_chatBackgroundImagePath != null && File(_chatBackgroundImagePath!).existsSync()) bg = FileImage(File(_chatBackgroundImagePath!)); 
            else if (_globalBackgroundImagePath != null && File(_globalBackgroundImagePath!).existsSync()) bg = FileImage(File(_globalBackgroundImagePath!)); 
            else bg = const AssetImage('assets/images/star_pattern_dark.png');
            
            return PopScope(
              canPop: false, onPopInvokedWithResult: (didPop, result) { 
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
                  receiverEmail: widget.receiverEmail, receiverID: widget.receiverID, presenceStream: _presenceStream, activityStream: _activityStream, currentUserStream: _currentUserStream, receiverUserStream: _receiverUserStream, onNavigateBack: () { _saveDraft(); Navigator.pop(context); }, onNavigateToContactInfo: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ContactInfoScreen(userID: widget.receiverID, userEmail: widget.receiverEmail))), 
                  onMenuSelection: (v, {isReceiverBlocked = false}) {
                    if (v == 'block') _toggleBlock(isReceiverBlocked);
                    else _handleMenuSelection(v, isReceiverBlocked: isReceiverBlocked);
                  }, 
                ),
                body: Stack(children: [ 
                  Container(color: theme.scaffoldBackgroundColor), SafeArea(child: Column(children: [
                    ChatGameManager( isPreparingInvitation: _isPreparingInvitation, isWaitingForGameAcceptance: _isWaitingForGameAcceptance, currentGameData: _currentGameData, chatRoomID: _getChatRoomID(), receiverEmail: widget.receiverEmail, onSendInvitation: () => _sendMessage(text: lang.t('chat_invitation_message'), type: 'dame_invitation'), onCancelInvitation: () => setState(() { _isPreparingInvitation = false; _isWaitingForGameAcceptance = false; }), onStopGame: _stopGame ),
                    Expanded(child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8), 
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(color: theme.colorScheme.surface.withAlpha(200), borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)), image: DecorationImage(image: bg, fit: bg is AssetImage ? BoxFit.none : BoxFit.cover, repeat: bg is AssetImage ? ImageRepeat.repeat : ImageRepeat.noRepeat, colorFilter: ColorFilter.mode(Colors.black.withAlpha(128), BlendMode.darken))), 
                        child: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildMessagesList(lang) )),
                    
                    // 🔥 BLOCK UI OVERRIDE: Niba umwe yafunze undi, Composer irahagarara.
                    if (isMeBlocked || isThemBlocked) 
                       _buildBlockedBar(theme, lang, isThemBlocked)
                    else ...[
                      if (_isAttachmentPanelVisible) _buildAttachmentPanelContent(), 
                      _buildComposerContainer(theme, isGV)
                    ],
                  ])), 
                  if (_showScrollDownButton) _buildScrollDownButton(theme),
                ]), 
              ), 
            );
          }
        );
      }
    );
  }

  // 🔥 BAR YEREKANA KO UFUNZE UMUNTU CYANGWA YAGUFUNZE
  Widget _buildBlockedBar(ThemeData theme, LanguageProvider lang, bool isThemBlocked) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16), 
      decoration: BoxDecoration(color: theme.colorScheme.surface, border: Border(top: BorderSide(color: theme.dividerColor))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(isThemBlocked ? lang.t('chat_user_is_blocked_sender') : lang.t('chat_user_is_blocked_receiver'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        if (isThemBlocked) TextButton(onPressed: () => _toggleBlock(true), child: Text(lang.t('unblock'), style: const TextStyle(fontWeight: FontWeight.bold)))
      ])
    );
  }

  Widget _buildMessagesList(LanguageProvider lang) {
    return ListView.builder(
      reverse: true, controller: _scrollController, itemCount: _chatItems.length, padding: const EdgeInsets.fromLTRB(10, 20, 10, 10), 
      cacheExtent: 1000, addAutomaticKeepAlives: true, addRepaintBoundaries: true,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, i) { 
        final item = _chatItems[i]; 
        if (item == 'E2EE_NOTICE') {
          return Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 20), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(15)), child: Column(mainAxisSize: MainAxisSize.min, children: [ const Icon(Icons.lock_outline_rounded, color: Colors.amberAccent, size: 24), const SizedBox(height: 8), Text(lang.t('chat_security_notice'), style: const TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center) ])));
        }
        if (item is String) return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(item, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70))));
        final Map<String, dynamic> msg = Map<String, dynamic>.from(item as Map);
        final mId = msg['id']; bool isF = true, isL = true; 
        if (i > 0 && _chatItems[i-1] is Map) if (_chatItems[i-1]['senderID'] == msg['senderID']) isF = false; 
        if (i < _chatItems.length - 1 && _chatItems[i+1] is Map) if (_chatItems[i+1]['senderID'] == msg['senderID']) isL = false;

        if (msg['senderID'] == _auth.currentUser?.uid && msg['status'] != 'seen') {
          if (_otherUserLastReadTs >= (msg['timestamp'] ?? 0)) msg['status'] = 'seen';
        }

        return RepaintBoundary(
          child: AutoScrollTag( key: ValueKey(mId), controller: _scrollController, index: i, child: MessageBubble( messageData: msg, isMe: msg['senderID'] == _auth.currentUser!.uid, isSelected: _selectedMessages.contains(mId), receiverDisplayName: widget.receiverEmail, uploadProgress: _uploadProgress[mId], isHighlighted: _highlightedMessageId == mId, isFirstInGroup: isF, isLastInGroup: isL, onSwipeReply: (m) { HapticFeedback.lightImpact(); setState(() { _replyingToMessage = m; _isEditingMessage = false; _isEmojiPickerVisible = false; _isAttachmentPanelVisible = false; }); Future.delayed(const Duration(milliseconds: 300), () { if (mounted) _focusNode.requestFocus(); }); }, onReplyTap: (id) => _scrollToMessage(id), onLongPress: (id) => _toggleSelection(id), onTap: (id) { if(_isSelectionMode) _toggleSelection(id); }, onAcceptInvitation: () => _createGameInFirestore(msg), onDeclineInvitation: (m) => _handleDeclineInvitation(m), onDelete: () => _showDeleteDialog(msg), onRetryUpload: () => syncService.triggerSync(), onEdit: () => _onEditMessage(msg), ) ),
        );
      },
    );
  }

  Widget _buildComposerContainer(ThemeData theme, bool isGV) {
    final lang = Provider.of<LanguageProvider>(context); 
    if (_selectedImageData != null) return PhotoPreviewComposer(imageData: _selectedImageData!, captionController: _captionController, onCancel: () => setState(() => _selectedImageData = null), onSend: () => _sendPhoto(), onImageEdited: (b) => setState(() => _selectedImageData = b));
    if (_videoEditorController != null) return VideoEditorComposer(controller: _videoEditorController!, isProcessing: _isProcessingVideo, processingProgress: _videoProcessingProgress, onCancel: _cancelVideoSelection, onSave: _processAndStageVideo);
    if (_stagedVideoController != null) return StagedVideoPreview(controller: _stagedVideoController!, captionController: _captionController, onCancel: () => setState(() { _stagedVideoController?.dispose(); _stagedVideoController = null; _stagedVideoFile = null; }), onSend: () => _sendStagedVideo());
    
    return StreamBuilder<DatabaseEvent>(
      stream: _presenceStream,
      builder: (context, presenceSnapshot) {
        String hint = lang.t('chat_message_input_hint');
        if (presenceSnapshot.hasData && presenceSnapshot.data!.snapshot.value != null) {
          try {
            final d = Map<String, dynamic>.from(presenceSnapshot.data!.snapshot.value as Map);
            if (d['state'] == 'offline' && d['last_changed'] != null) hint = _formatLastSeen(d['last_changed'] as int);
          } catch (_) {}
        }
        return Column(children: [ if (_isEditingMessage) _buildEditBar(theme), if (_replyingToMessage != null && !_isEditingMessage) _buildReplyBar(theme, lang), _buildComposer(theme, hint, isGV) ]);
      }
    );
  }

  Widget _buildComposer(ThemeData t, String h, bool iG) => Container( padding: const EdgeInsets.fromLTRB(8, 8, 8, 25), decoration: BoxDecoration(color: t.scaffoldBackgroundColor), child: Stack(alignment: Alignment.bottomRight, children: [ Material(elevation: 2, borderRadius: BorderRadius.circular(30), child: Container(constraints: const BoxConstraints(minHeight: 56), padding: const EdgeInsets.only(right: 58), decoration: BoxDecoration(color: t.cardColor, borderRadius: BorderRadius.circular(30)), child: Row(children: [ IconButton(icon: Icon(_isEmojiPickerVisible ? Icons.keyboard_rounded : Icons.face_retouching_natural_rounded, color: Colors.amber), onPressed: iG ? null : _toggleEmojiPicker), Expanded(child: TextField( focusNode: _focusNode, controller: _messageController, maxLines: 5, minLines: 1, readOnly: iG, decoration: InputDecoration(hintText: h, border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 10)) )), IconButton(icon: const Icon(Icons.attach_file_rounded), onPressed: iG ? null : () { _forceHideKeyboard(); _showAnimatedMenu(); }), ]))), Positioned(bottom: 2, right: 0, child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: (_isComposing || _isEditingMessage || _replyingToMessage != null) && !iG ? FloatingActionButton(mini: true, backgroundColor: t.colorScheme.primary, child: Icon(_isEditingMessage ? Icons.check : Icons.send_rounded, color: Colors.white), onPressed: () => _sendMessage()) : SocialMediaRecorder(startRecording: () => _myActivityStatusRef?.set("recording"), stopRecording: (time) => _myActivityStatusRef?.set("idle"), sendRequestFunction: (f, d) => _sendVoiceMessage(f, d), recordIcon: FloatingActionButton(mini: true, backgroundColor: t.colorScheme.secondary, child: const Icon(Icons.mic_none_rounded, color: Colors.white), onPressed: () {})))) ]));

  void _showAnimatedMenu() { showGeneralDialog(context: context, barrierDismissible: true, barrierLabel: 'M', transitionDuration: const Duration(milliseconds: 400), pageBuilder: (ctx, a1, a2) => Align(alignment: Alignment.bottomCenter, child: _buildAttachmentPanelContent(isDialog: true))); }
  Widget _buildAttachmentPanelContent({bool isDialog = false}) { void close() { if (isDialog) Navigator.pop(context); else setState(() => _isAttachmentPanelVisible = false); } return ChatAttachmentPanel( onCameraTap: () async { close(); final i = await ImagePicker().pickImage(source: ImageSource.camera); if(i != null) setState(() { _selectedImageData = File(i.path).readAsBytesSync(); }); }, onPhotoTap: () async { close(); final i = await ImagePicker().pickImage(source: ImageSource.gallery); if(i != null) setState(() { _selectedImageData = File(i.path).readAsBytesSync(); }); }, onVideoTap: () async { close(); final v = await ImagePicker().pickVideo(source: ImageSource.gallery); if(v != null) { final controller = VideoEditorController.file(File(v.path), maxDuration: const Duration(minutes: 5)); await controller.initialize(); setState(() { _selectedVideoFile = File(v.path); _videoEditorController = controller; }); } }, onAudioTap: () async { close(); final res = await FilePicker.platform.pickFiles(type: FileType.audio); if(res != null) { final perm = await mediaUploadService.saveFilePermanently(res.files.single.path!); final data = _createMediaData('audio_file', perm); data['fileName'] = res.files.single.name; chatMessageService.saveMessage(data).then((_) { _addOptimisticMessage(data); mediaUploadService.sendMediaMessageFromData(data); }); } }, onDocumentTap: () async { close(); final res = await FilePicker.platform.pickFiles(type: FileType.any); if(res != null) { final perm = await mediaUploadService.saveFilePermanently(res.files.single.path!); final data = _createMediaData('document', perm); data['fileName'] = res.files.single.name; chatMessageService.saveMessage(data).then((_) { _addOptimisticMessage(data); mediaUploadService.sendMediaMessageFromData(data); }); } }, onContactTap: () async { close(); await mediaUploadService.sendContact(context, chatRoomID: _getChatRoomID(), receiverID: widget.receiverID); _refreshMessages(); }, onDameTap: () { close(); _forceHideKeyboard(); setState(() { _isPreparingInvitation = true; }); }, onLudoTap: () { close(); }, onClose: close ); }
  void _handleMenuSelection(String v, {bool isReceiverBlocked = false}) { switch (v) { case 'view_contact': Navigator.push(context, MaterialPageRoute(builder: (c) => ContactInfoScreen(userID: widget.receiverID, userEmail: widget.receiverEmail))); break; case 'wallpaper': _showWallpaperDialog(); break; case 'clear_chat': _clearChat(); break; } }
  void _toggleSelection(String id) { setState(() { if (_selectedMessages.contains(id)) { _selectedMessages.remove(id); if (_selectedMessages.isEmpty) _isSelectionMode = false; } else { _selectedMessages.add(id); _isSelectionMode = true; } }); }
  void _onShare() { final msgs = _chatItems.whereType<Map<String, dynamic>>().where((m) => _selectedMessages.contains(m['id'])).toList(); setState(() { _isSelectionMode = false; _selectedMessages.clear(); }); Navigator.push(context, MaterialPageRoute(builder: (c) => ForwardScreen(messagesToForward: msgs))); }
  void _onCopy() { final t = _chatItems.whereType<Map<String, dynamic>>().where((m) => _selectedMessages.contains(m['id']) && m['messageType'] == 'text').map((m) => m['message']).join('\n'); if (t.isNotEmpty) Clipboard.setData(ClipboardData(text: t)); setState(() { _isSelectionMode = false; _selectedMessages.clear(); }); }
  void _onReplyFromSelection() { if (_selectedMessages.length == 1) { final msg = _chatItems.firstWhere((it) => it is Map && it['id'] == _selectedMessages.first); setState(() { _replyingToMessage = msg as Map<String, dynamic>; _isEditingMessage = false; _isSelectionMode = false; _selectedMessages.clear(); }); _focusNode.requestFocus(); } }
  void _onEditMessage(Map<String, dynamic> m) { setState(() { _isEditingMessage = true; _editingMessageId = m['id']; _messageController.text = m['message'] ?? ""; _replyingToMessage = null; _isEmojiPickerVisible = false; _isAttachmentPanelVisible = false; }); Future.delayed(const Duration(milliseconds: 300), () { if (mounted) _focusNode.requestFocus(); }); }
  void _cancelEditingMessage() { setState(() { _isEditingMessage = false; _editingMessageId = null; _messageController.clear(); }); _forceHideKeyboard(); }
  void _toggleEmojiPicker() async { if (_isEmojiPickerVisible) { Navigator.pop(context); } else { _forceHideKeyboard(); _showEmojiPickerDialog(); } }
  void _showEmojiPickerDialog() { if (mounted) setState(() => _isEmojiPickerVisible = true); showGeneralDialog(context: context, barrierDismissible: true, barrierLabel: 'Emoji', pageBuilder: (context, anim1, anim2) => StatefulBuilder(builder: (context, setPickerState) => Align(alignment: Alignment.centerLeft, child: Material(color: Colors.transparent, child: Container(width: MediaQuery.of(context).size.width * 0.85, height: 450, decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24)), child: Column(children: [ Container(height: 50, child: ListView(scrollDirection: Axis.horizontal, children: emojiCategories.keys.map((cat) => GestureDetector(onTap: () => setPickerState(() => _selectedEmojiCategory = cat), child: Container(padding: const EdgeInsets.symmetric(horizontal: 15), alignment: Alignment.center, child: Text(cat, style: const TextStyle(fontSize: 22))), )).toList())), Expanded(child: GridView.builder(padding: const EdgeInsets.all(10), itemCount: emojiCategories[_selectedEmojiCategory]!.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7), itemBuilder: (ctx, i) => GestureDetector(onTap: () { final e = emojiCategories[_selectedEmojiCategory]![i]; if (_messageController.text.isEmpty) { Navigator.pop(context); _sendMessage(text: e, type: 'large_emoji'); } else { _messageController.text += e; } }, child: Center(child: Text(emojiCategories[_selectedEmojiCategory]![i], style: const TextStyle(fontSize: 26))), ), )), ])))))).then((_) { if(mounted) setState(() => _isEmojiPickerVisible = false); }); }
  Future<void> _showDeleteDialog(Map<String, dynamic> msg) async { final lang = Provider.of<LanguageProvider>(context, listen: false); showDialog(context: context, builder: (c) => AlertDialog( title: Text(lang.t('chat_delete_confirm_dialog_title')), actions: [ TextButton(onPressed: () { Navigator.pop(c); chatMessageService.deleteMessage(msg['id']); _refreshMessages(); }, child: Text(lang.t('chat_delete_for_me'))), if (msg['senderID'] == _auth.currentUser!.uid) TextButton(onPressed: () async { Navigator.pop(c); await _firestore.collection('chat_rooms').doc(_getChatRoomID()).collection('messages').doc(msg['id']).update({'messageType': 'deleted', 'message': ''}); await chatMessageService.deleteMessage(msg['id']); _refreshMessages(); }, child: Text(lang.t('chat_delete_for_everyone'), style: const TextStyle(color: Colors.red))), ] )); }
  AppBar _buildSelectionAppBar() { final lang = Provider.of<LanguageProvider>(context); return AppBar( backgroundColor: Colors.blueGrey[800], title: Text("${_selectedMessages.length} ${lang.t('chat_selection_bar_title')}"), actions: [ if (_selectedMessages.length == 1) IconButton(icon: const Icon(Icons.reply), onPressed: _onReplyFromSelection), IconButton(icon: const Icon(Icons.share), onPressed: _onShare), IconButton(icon: const Icon(Icons.copy), onPressed: _onCopy), IconButton(icon: const Icon(Icons.delete), onPressed: () async { for (var id in _selectedMessages) await chatMessageService.deleteMessage(id); setState(() { _isSelectionMode = false; _selectedMessages.clear(); }); _refreshMessages(); }), ] ); }
  Widget _buildScrollDownButton(ThemeData theme) => Positioned( bottom: 80, right: 20, child: FloatingActionButton.small( onPressed: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut), backgroundColor: theme.colorScheme.primary.withOpacity(0.8), child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white) ) );
  Widget _buildEditBar(ThemeData t) => Container(padding: const EdgeInsets.all(10), child: Row(children: [ const Icon(Icons.edit, color: Colors.blue), const Text(" Editing message"), const Spacer(), IconButton(icon: const Icon(Icons.close), onPressed: _cancelEditingMessage) ]));
  Widget _buildReplyBar(ThemeData theme, LanguageProvider lang) => Container(padding: const EdgeInsets.all(10), child: Row(children: [ Container(width: 4, height: 40, color: theme.colorScheme.primary), const SizedBox(width: 10), Expanded(child: Text(lang.t('chat_reply_to_yourself'))), IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _replyingToMessage = null)) ]));

  @override
  void dispose() { _roomSubscription?.cancel(); syncService.currentActiveChatId = null; _saveDraft(); _scrollController.dispose(); _gameStreamSubscription?.cancel(); _uiUpdateSubscription?.cancel(); _uploadProgressSubscription?.cancel(); _messageController.dispose(); _captionController.dispose(); _stagedVideoController?.dispose(); _videoEditorController?.dispose(); _focusNode.dispose(); _myActivityStatusRef?.set("idle"); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
}