
// lib/chat_screen.dart (VERSION IKOSOYE: INTERNAL NAVIGATION FIXED)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:jembe_talk/contact_info_screen.dart';
import 'package:jembe_talk/full_photo_screen.dart';
import 'package:jembe_talk/services/audio_service.dart';
import 'package:jembe_talk/services/media_upload_service.dart';
import 'package:jembe_talk/widgets/chat/chat_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:social_media_recorder/screen/social_media_recorder.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_emoji_selector_plus/flutter_emoji_selector_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:jembe_talk/services/database_helper.dart';
import 'package:jembe_talk/services/sync_service.dart';
import 'package:video_editor/video_editor.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:jembe_talk/services/file_storage_service.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:jembe_talk/forward_screen.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:just_audio/just_audio.dart'; 

// IMPORTS ZONGEWEHO KUGIRA NGO BI KORE
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jembe_talk/tangaza_star/tangaza_star_screen.dart'; // <--- NTIWIBAGIRWE IYI

import 'language_provider.dart';
import 'dame_game_logic.dart';

class ChatScreenWrapper extends StatelessWidget {
  final String receiverEmail;
  final String receiverID;
  const ChatScreenWrapper({super.key, required this.receiverEmail, required this.receiverID});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioPlayerService()),
      ],
      child: ChatScreen(receiverEmail: receiverEmail, receiverID: receiverID),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String receiverEmail;
  final String receiverID;
  const ChatScreen({super.key, required this.receiverEmail, required this.receiverID});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late AutoScrollController _scrollController;
  
  String? _globalBackgroundImagePath;
  String? _chatBackgroundImagePath;
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  StreamSubscription? _messageSubscription;
  
  bool _isSelectionMode = false;
  final Set<String> _selectedMessages = {};

  Stream<DocumentSnapshot>? _currentUserStream;
  Stream<DocumentSnapshot>? _receiverUserStream;
  StreamSubscription? _gameStreamSubscription;
  Map<String, dynamic>? _currentGameData;
  Map<String, dynamic>? _optimisticGameData;

  bool _isPreparingInvitation = false;
  bool _isWaitingForGameAcceptance = false;

  DateTime? _timeWhenPaused;

  final TextEditingController _messageController = TextEditingController();
  bool _isComposing = false;
  final Map<String, double> _uploadProgress = {};
  final FocusNode _focusNode = FocusNode();
  bool _isEmojiPickerVisible = false;
  bool _isAttachmentPanelVisible = false;
  List<dynamic> _chatItems = [];

  StreamSubscription? _uploadProgressSubscription;

  final TextEditingController _captionController = TextEditingController();
  Uint8List? _selectedImageData;

  VideoEditorController? _videoEditorController;
  File? _selectedVideoFile;
  bool _isProcessingVideo = false;
  double _videoProcessingProgress = 0.0;
  
  File? _stagedVideoFile;
  String? _stagedThumbnailPath;
  VideoPlayerController? _stagedVideoController; 
  
  bool _isGameHardStopped = false;

  StreamSubscription? _uiUpdateSubscription;
  
  Stream<DatabaseEvent>? _presenceStream;
  Stream<DatabaseEvent>? _activityStream;
  DatabaseReference? _myActivityStatusRef;
  Timer? _typingTimer;

  Map<String, dynamic>? _replyingToMessage;
  
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  AudioPlayerService? _audioPlayerService;


  @override
  void initState() {
    super.initState();
    
    _scrollController = AutoScrollController(
      viewportBoundaryGetter: () => Rect.fromLTRB(0, 0, 0, MediaQuery.of(context).padding.bottom),
      axis: Axis.vertical
    );

    WidgetsBinding.instance.addObserver(this);
    _currentUserStream = _firestore.collection('users').doc(_auth.currentUser!.uid).snapshots();
    _receiverUserStream = _firestore.collection('users').doc(widget.receiverID).snapshots();
    _presenceStream = FirebaseDatabase.instance.ref('status/${widget.receiverID}').onValue.asBroadcastStream();
    final chatRoomID = _getChatRoomID();
    _myActivityStatusRef = FirebaseDatabase.instance.ref('activity/$chatRoomID/${_auth.currentUser!.uid}');
    _activityStream = FirebaseDatabase.instance.ref('activity/$chatRoomID/${widget.receiverID}').onValue.asBroadcastStream();
    
    _loadInitialData();

    _uiUpdateSubscription = syncService.uiMessageUpdateStream.listen((updatedMessageId) {
      if(mounted) {
        log("UI update received for message: $updatedMessageId. Reloading messages.");
        _loadInitialMessages(forceReload: true);
      }
    });
    
    _uploadProgressSubscription = syncService.uploadProgressStream.listen((progressData) {
      if (mounted) {
        final messageId = progressData['messageId'];
        final progress = progressData['progress'] as double?;
        setState(() {
          if (progress == null || progress >= 1.0) {
            _uploadProgress.remove(messageId);
          } else {
            _uploadProgress[messageId] = progress;
          }
        });
      }
    });

    _messageController.addListener(() {
      if (mounted) {
        setState(() => _isComposing = _messageController.text.trim().isNotEmpty);
        _updateTypingStatus();
      }
    });
    
    syncService.triggerSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audioPlayerService = Provider.of<AudioPlayerService>(context, listen: false);
  }
  
  void _updateTypingStatus() {
    if(!mounted) return;
    _typingTimer?.cancel();
    if (_messageController.text.trim().isNotEmpty) {
      _myActivityStatusRef?.set("typing");
      _typingTimer = Timer(const Duration(seconds: 2), () {
        if(mounted) _myActivityStatusRef?.set("idle");
      });
    } else {
      _myActivityStatusRef?.set("idle");
    }
  }

  Future<void> _loadInitialData() async {
    await _syncAndDisplayInitialMessages();
    _listenForGameUpdates();
  }

  Future<List<Map<String, dynamic>>> _fetchNewerMessages(int sinceTimestamp) async {
    final chatRoomID = _getChatRoomID();
    List<Map<String, dynamic>> newMessages = [];

    try {
      final querySnapshot = await _firestore
          .collection('chat_rooms')
          .doc(chatRoomID)
          .collection('messages')
          .where('timestamp', isGreaterThan: sinceTimestamp)
          .orderBy('timestamp')
          .get();

      final prefs = await SharedPreferences.getInstance();
      final clearTimestamp = prefs.getInt('clear_timestamp_$chatRoomID') ?? 0;

      for (var doc in querySnapshot.docs) {
        final serverData = doc.data();
        final serverMessage = Map<String, dynamic>.from(serverData);
        if (serverMessage['timestamp'] is Timestamp) {
          serverMessage['timestamp'] = (serverMessage['timestamp'] as Timestamp).millisecondsSinceEpoch;
        }

        if (serverMessage['timestamp'] >= clearTimestamp) {
          final bool wasSaved = await DatabaseHelper.instance.saveMessage(serverMessage);
          
          if (wasSaved) {
            newMessages.add(serverMessage);
          }
        }
      }
    } catch (e) {
      final lang = Provider.of<LanguageProvider>(context, listen: false);
      log("${lang.t('chat_error_loading_new_messages')}: $e");
    }
    return newMessages;
  }
  
  Future<void> _syncAndDisplayInitialMessages() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    await _loadWallpapers();
    final chatRoomID = _getChatRoomID();
    
    final localMessages = await DatabaseHelper.instance.getMessagesForChatRoom(chatRoomID);
    
    final lastLocalTimestamp = localMessages.isNotEmpty ? localMessages.last['timestamp'] as int : 0;
    final newFirestoreMessages = await _fetchNewerMessages(lastLocalTimestamp);
    
    final allMessages = [...localMessages, ...newFirestoreMessages];

    if (mounted) {
      setState(() {
        _messages = allMessages;
        _chatItems = _getChatItemsWithSeparators(_messages);
        _isLoading = false;
      });
      
      _updateReceivedMessagesStatusToSeen();
      _listenForFirebaseMessages();
    }
  }

  Future<void> _loadInitialMessages({bool forceReload = false}) async {
    final chatRoomID = _getChatRoomID();
    final localMessages = await DatabaseHelper.instance.getMessagesForChatRoom(chatRoomID);
    if (mounted) {
      setState(() {
        _messages = List.from(localMessages);
        _chatItems = _getChatItemsWithSeparators(_messages);
      });

      if(!forceReload) {
        _scrollToMostRecent();
      }
      _updateReceivedMessagesStatusToSeen();
    }
  }


  void _listenForGameUpdates() {
    final chatRoomID = _getChatRoomID();
    _gameStreamSubscription = _firestore.collection('games').doc(chatRoomID).snapshots().listen((gameSnapshot) {
      if (!mounted) return;
  
      Map<String, dynamic>? newGameData;
      bool opponentStoppedGame = false;
  
      if (gameSnapshot.exists && gameSnapshot.data() != null) {
        final data = gameSnapshot.data()!;
        newGameData = data;
  
        if (_currentGameData != null && _currentGameData!['status'] == 'active' && data['status'] == 'stopped') {
           if (data['stoppedBy'] != _auth.currentUser!.uid) {
             opponentStoppedGame = true;
           }
        }
        
        if (data['status'] == 'active' && _isPreparingInvitation) {
          setState(() {
            _isPreparingInvitation = false;
            _isWaitingForGameAcceptance = false;
          });
          _focusNode.unfocus();
        }

      } else {
        newGameData = null;
      }
  
      setState(() {
        _currentGameData = newGameData;
      });
  
      if (opponentStoppedGame) {
        _showOpponentStoppedGameDialog();
      }
    });
  }

  void _showOpponentStoppedGameDialog() {
    if (!mounted) return;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(lang.t('chat_game_stopped_dialog_title')),
          content: Text(lang.t('chat_game_stopped_dialog_content')),
          actions: <Widget>[
            TextButton(
              child: Text(lang.t('chat_game_stopped_dialog_ok')),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _timeWhenPaused = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _updateReceivedMessagesStatusToSeen();
      _deleteStaleGameIfNeeded();
    }
  }

  Future<void> _deleteStaleGameIfNeeded() async {
    if (_timeWhenPaused == null) return;
    final elapsed = DateTime.now().difference(_timeWhenPaused!);
    if (elapsed.inMinutes >= 10) {
      final chatRoomID = _getChatRoomID();
      try {
        final gameDoc = await _firestore.collection('games').doc(chatRoomID).get();
        if (gameDoc.exists && gameDoc.data()?['status'] == 'active') {
          await gameDoc.reference.delete();
          final lang = Provider.of<LanguageProvider>(context, listen: false);
          debugPrint(lang.t('chat_stale_game_deleted_log'));
        }
      } catch (e) {
        final lang = Provider.of<LanguageProvider>(context, listen: false);
        debugPrint("${lang.t('chat_error_deleting_stale_game')}: $e");
      }
    }
    _timeWhenPaused = null;
  }

  void _scrollToMostRecent({bool animated = false}) {
    if (!_scrollController.hasClients) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(0.0);
        }
      }
    });
  }
  

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _messageSubscription?.cancel();
    _gameStreamSubscription?.cancel();
    _messageController.dispose();
    _captionController.dispose();
    _focusNode.dispose();
    _videoEditorController?.dispose();
    _stagedVideoController?.dispose();
    _audioPlayerService?.stop(); 
    
    _uploadProgressSubscription?.cancel();
    _uiUpdateSubscription?.cancel();
    
    _typingTimer?.cancel();
    _highlightTimer?.cancel();
    _myActivityStatusRef?.set("idle");
    
    super.dispose();
  }

  Future<void> _loadWallpapers() async {
    final prefs = await SharedPreferences.getInstance();
    final chatRoomID = _getChatRoomID();
    if (mounted) {
      setState(() {
        _globalBackgroundImagePath = prefs.getString('wallpaperPath');
        _chatBackgroundImagePath = prefs.getString('wallpaperPath_$chatRoomID');
      });
    }
  }

  String _getChatRoomID() {
    List<String> ids = [_auth.currentUser!.uid, widget.receiverID];
    ids.sort();
    return ids.join('_');
  }

  List<dynamic> _getChatItemsWithSeparators(List<Map<String, dynamic>> messages) {
    List<dynamic> items = [];
    if (messages.isEmpty) return items;
    messages.sort((a, b) {
      final timestampA = a['timestamp'] as int;
      final timestampB = b['timestamp'] as int;
      return timestampB.compareTo(timestampA);
    });
    DateTime? lastDate;
    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];
      final messageTimestamp = message['timestamp'];
      final DateTime messageDate = DateTime.fromMillisecondsSinceEpoch(messageTimestamp);

      items.add(message);

      final DateTime? nextMessageDate = (i + 1 < messages.length)
        ? DateTime.fromMillisecondsSinceEpoch(messages[i+1]['timestamp'])
        : null;

      if (nextMessageDate == null || !isSameDay(messageDate, nextMessageDate)) {
         items.add(_formatDateSeparator(messageDate.millisecondsSinceEpoch));
      }
    }
    return items;
  }

  bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateSeparator(int timestamp) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDay = DateTime(date.year, date.month, date.day);
    if (messageDay == today) return lang.t('chat_date_separator_today');
    if (messageDay == yesterday) return lang.t('chat_date_separator_yesterday');
    return DateFormat.yMMMMd(lang.currentLanguage == 'fr' ? 'fr_FR' : 'en_US').format(date);
  }
  
  void _listenForFirebaseMessages() async {
    final chatRoomID = _getChatRoomID();
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _messageSubscription?.cancel();

    final lastLocalTimestamp = _messages.isNotEmpty ? _messages.first['timestamp'] as int : 0;

    final query = _firestore
        .collection('chat_rooms')
        .doc(chatRoomID)
        .collection('messages')
        .where('timestamp', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastLocalTimestamp));

    _messageSubscription = query.snapshots().listen((snapshot) async {
      if (!mounted || snapshot.docChanges.isEmpty) return;

      bool didStateChange = false;
      bool shouldScroll = false;
      List<DocumentReference> messagesToMarkAsSeen = [];

      for (var change in snapshot.docChanges) {
        final doc = change.doc;
        final serverData = doc.data();
        if (serverData == null) continue;

        final serverMessage = Map<String, dynamic>.from(serverData);
        if (serverMessage['timestamp'] is Timestamp) {
            serverMessage['timestamp'] = (serverMessage['timestamp'] as Timestamp).millisecondsSinceEpoch;
        }

        if (change.type == DocumentChangeType.removed) {
          await DatabaseHelper.instance.deleteMessage(doc.id);
          didStateChange = true;
        } else {
          final bool wasSaved = await DatabaseHelper.instance.saveMessage(serverMessage);
          if (wasSaved) {
            didStateChange = true;
            if (change.type == DocumentChangeType.added && serverMessage['senderID'] != currentUser.uid) {
              shouldScroll = true;
            }
          }
        }
        
        if (serverMessage['receiverID'] == currentUser.uid && serverMessage['status'] != 'seen') {
          messagesToMarkAsSeen.add(doc.reference);
        }
      }

      if (didStateChange && mounted) {
        await _loadInitialMessages(forceReload: true);
      }

      if (messagesToMarkAsSeen.isNotEmpty) {
        WriteBatch batch = _firestore.batch();
        for (var ref in messagesToMarkAsSeen) {
          batch.update(ref, {'status': 'seen'});
        }
        await batch.commit().catchError((e) => log("Error batch updating status to seen: $e"));
      }
      
      if (shouldScroll) {
        _scrollToMostRecent(animated: true);
      }
    });
  }

  void _addOptimisticMessage(Map<String, dynamic> messageData) {
    setState(() {
      _messages.insert(0, messageData);
      _chatItems = _getChatItemsWithSeparators(_messages);
    });
    _scrollToMostRecent(animated: true);
  }

  void _sendMessage({String? text, String messageType = 'text'}) async {
    _typingTimer?.cancel();
    _myActivityStatusRef?.set("idle");

    if (messageType == 'text') {
      if (_messageController.text.trim().isEmpty) return;
      text = _messageController.text.trim();
      _messageController.clear();
      _focusNode.requestFocus(); 
      HapticFeedback.mediumImpact();
    } else if (messageType == 'large_emoji') {
      if (text == null || text.trim().isEmpty) return;
      text = text.trim();
    }
    final currentUser = _auth.currentUser!;
    final chatRoomID = _getChatRoomID();
    final messageId = const Uuid().v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> messageData = {
      DatabaseHelper.columnId: messageId,
      DatabaseHelper.columnChatRoomID: chatRoomID,
      DatabaseHelper.columnSenderID: currentUser.uid,
      DatabaseHelper.columnReceiverID: widget.receiverID,
      DatabaseHelper.columnMessageType: messageType,
      DatabaseHelper.columnTimestamp: timestamp,
      DatabaseHelper.columnStatus: 'pending',
      DatabaseHelper.columnMessage: text,
      DatabaseHelper.columnReplyingTo: _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null,
    };
    await DatabaseHelper.instance.saveMessage(messageData);
    _addOptimisticMessage(messageData);

    if(mounted) {
      setState(() {
        _replyingToMessage = null;
      });
    }

    syncService.triggerSync();
  }

  Future<void> _sendVoiceMessage(File soundFile, String duration) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    
    int durationInSeconds = 0;
    try {
      final parts = duration.split(':');
      if (parts.length == 2) {
        durationInSeconds = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    } catch (e) {
      final lang = Provider.of<LanguageProvider>(context, listen: false);
      debugPrint("${lang.t('chat_error_calculating_audio_duration')}: $e");
    }

    final messageId = const Uuid().v4();
    final messageData = {
      DatabaseHelper.columnId: messageId,
      DatabaseHelper.columnChatRoomID: _getChatRoomID(),
      DatabaseHelper.columnSenderID: currentUser.uid,
      DatabaseHelper.columnReceiverID: widget.receiverID,
      DatabaseHelper.columnMessageType: 'voice_note',
      DatabaseHelper.columnTimestamp: DateTime.now().millisecondsSinceEpoch,
      DatabaseHelper.columnStatus: 'uploading',
      DatabaseHelper.columnLocalPath: soundFile.path,
      DatabaseHelper.columnDuration: durationInSeconds,
      DatabaseHelper.columnFileName: path.basename(soundFile.path),
      DatabaseHelper.columnReplyingTo: _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null,
    };

    _addOptimisticMessage(messageData);
    if(mounted) {
      setState(() {
        _replyingToMessage = null;
      });
    }
    await mediaUploadService.sendMediaMessageFromData(messageData);
  }


  void _handleDeclineInvitation(Map<String, dynamic> invitationMessage) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    _sendMessage(
      messageType: 'dame_invitation_declined',
      text: lang.t('chat_invitation_declined_message'),
    );

    final messageIdToDelete = invitationMessage['id'];
    if (messageIdToDelete != null) {
      await _deleteMessageForMe(messageIdToDelete);
    }
  }

  Future<void> _updateReceivedMessagesStatusToSeen() async {
    final chatRoomID = _getChatRoomID();
    final myID = _auth.currentUser!.uid;
    final query = _firestore
        .collection('chat_rooms')
        .doc(chatRoomID)
        .collection('messages')
        .where('receiverID', isEqualTo: myID)
        .where('status', isNotEqualTo: 'seen');
    final querySnapshot = await query.get();
    if (querySnapshot.docs.isNotEmpty) {
      WriteBatch batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.update(doc.reference, {'status': 'seen'});
      }
      await batch.commit().catchError((e) {
        debugPrint("Error batch updating status to seen: $e");
      });
    }
  }

  void _sendGameInvitation() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    setState(() => _isWaitingForGameAcceptance = true);
    _focusNode.unfocus();
    _sendMessage(messageType: 'dame_invitation', text: lang.t('chat_invitation_message'));
  }

  Future<void> _pickAndPreviewImage(ImageSource source) async {
    _focusNode.unfocus();
    final image = await ImagePicker().pickImage(source: source);
    if (image == null) return;

    final imageBytes = await File(image.path).readAsBytes();
    if (!mounted) return;

    setState(() {
      _selectedImageData = imageBytes;
    });
  }

  Future<void> _sendPhoto() async {
    if (_selectedImageData == null) return;
    
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = path.join(tempDir.path, '${const Uuid().v4()}.png');
    final tempFile = File(tempFilePath);
    await tempFile.writeAsBytes(_selectedImageData!);

    final permanentPath = await mediaUploadService.saveFilePermanently(tempFile.path);
    
    final messageId = const Uuid().v4();
    final messageData = {
      DatabaseHelper.columnId: messageId,
      DatabaseHelper.columnChatRoomID: _getChatRoomID(),
      DatabaseHelper.columnSenderID: _auth.currentUser!.uid,
      DatabaseHelper.columnReceiverID: widget.receiverID,
      DatabaseHelper.columnMessageType: 'image',
      DatabaseHelper.columnTimestamp: DateTime.now().millisecondsSinceEpoch,
      DatabaseHelper.columnStatus: 'uploading',
      DatabaseHelper.columnLocalPath: permanentPath,
      DatabaseHelper.columnMessage: _captionController.text.trim(),
      DatabaseHelper.columnFileName: path.basename(permanentPath),
      DatabaseHelper.columnReplyingTo: _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null,
    };

    _addOptimisticMessage(messageData);
    if(mounted) {
      setState(() {
        _selectedImageData = null;
        _captionController.clear();
        _replyingToMessage = null;
      });
    }

    await mediaUploadService.sendMediaMessageFromData(messageData);
  }

  void _cancelPhotoSelection() {
    setState(() {
      _selectedImageData = null;
      _captionController.clear();
    });
  }

  Future<void> _processAndStageVideo() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (_videoEditorController == null || _selectedVideoFile == null) return;
    setState(() => _isProcessingVideo = true);
    
    await _stagedVideoController?.dispose();
    _stagedVideoController = null;

    try {
      final thumbnailFuture = mediaUploadService.generateThumbnail(_selectedVideoFile!.path);
      String videoPathToSave;
      final bool hasTrimmed = _videoEditorController!.startTrim != Duration.zero ||
          _videoEditorController!.endTrim != _videoEditorController!.video.value.duration;
      if (!hasTrimmed) {
        videoPathToSave = _selectedVideoFile!.path;
      } else {
        final Directory appDocDir = await getTemporaryDirectory();
        final String outputPath = '${appDocDir.path}/trimmed_video_${const Uuid().v4()}.mp4';
        final completer = Completer<bool>();
        final command = '-ss ${_videoEditorController!.startTrim.inSeconds}.${_videoEditorController!.startTrim.inMilliseconds.remainder(1000)} -i "${_selectedVideoFile!.path}" -t ${(_videoEditorController!.endTrim - _videoEditorController!.startTrim).inSeconds}.${(_videoEditorController!.endTrim - _videoEditorController!.startTrim).inMilliseconds.remainder(1000)} -c:v libx264 -preset ultrafast -crf 28 -c:a aac -b:a 128k -y "$outputPath"';
        FFmpegKit.executeAsync(
          command,
          (session) async {
            final returnCode = await session.getReturnCode();
            completer.complete(ReturnCode.isSuccess(returnCode));
          },
          null,
          (statistics) {
            if (mounted) {
              final duration = (_videoEditorController!.endTrim - _videoEditorController!.startTrim).inMilliseconds;
              if (duration > 0) {
                setState(() => _videoProcessingProgress = (statistics.getTime() / duration).clamp(0.0, 1.0));
              }
            }
          },
        );
        final success = await completer.future;
        if (!success) throw Exception(lang.t('chat_error_processing_video'));
        videoPathToSave = outputPath;
      }
      final permanentPath = await mediaUploadService.saveFilePermanently(videoPathToSave);
      final thumbnailPath = await thumbnailFuture;

      if (mounted) {
        _stagedVideoController = VideoPlayerController.file(File(permanentPath));
        await _stagedVideoController!.initialize();
        _stagedVideoController!.setLooping(true);

        setState(() {
          _stagedVideoFile = File(permanentPath);
          _stagedThumbnailPath = thumbnailPath;
          _isProcessingVideo = false;
          _videoProcessingProgress = 0.0;
          _cancelVideoSelection(); 
        });
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_generic'))));
        setState(() {
          _isProcessingVideo = false;
          _videoProcessingProgress = 0.0;
          _cancelVideoSelection();
        });
      }
    }
  }

  Future<void> _sendStagedVideo() async {
    if (_stagedVideoFile == null) return;
  
    final messageId = const Uuid().v4();
    final messageData = {
      DatabaseHelper.columnId: messageId,
      DatabaseHelper.columnChatRoomID: _getChatRoomID(),
      DatabaseHelper.columnSenderID: _auth.currentUser!.uid,
      DatabaseHelper.columnReceiverID: widget.receiverID,
      DatabaseHelper.columnMessageType: 'video',
      DatabaseHelper.columnTimestamp: DateTime.now().millisecondsSinceEpoch,
      DatabaseHelper.columnStatus: 'uploading',
      DatabaseHelper.columnLocalPath: _stagedVideoFile!.path,
      DatabaseHelper.columnThumbnailLocalPath: _stagedThumbnailPath,
      DatabaseHelper.columnFileName: path.basename(_stagedVideoFile!.path),
      DatabaseHelper.columnMessage: _captionController.text.trim(),
      DatabaseHelper.columnReplyingTo: _replyingToMessage != null ? jsonEncode(_replyingToMessage) : null,
    };

    _addOptimisticMessage(messageData);

    if (mounted) {
      _cancelStagedVideo();
      setState(() {
        _replyingToMessage = null;
      });
    }
    
    await mediaUploadService.sendMediaMessageFromData(messageData);
  }

  Map<String, dynamic> _getInitialBoardForFirestore() {
    final initialBoard = List.generate(10, (row) {
      return List.generate(10, (col) {
        if ((row + col) % 2 != 0) {
          if (row < 4) return {'player': 2, 'type': 'man'};
          if (row > 5) return {'player': 1, 'type': 'man'};
        }
        return null;
      });
    });
    final Map<String, dynamic> boardForFirestore = {};
    for (int i = 0; i < initialBoard.length; i++) {
      boardForFirestore[i.toString()] = initialBoard[i];
    }
    return boardForFirestore;
  }

  Future<void> _createGameInFirestore(Map<String, dynamic> invitationMessage) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final int invitationTimestamp = invitationMessage['timestamp'];
    final now = DateTime.now().millisecondsSinceEpoch;
    const expirationLimit = Duration(minutes: 5);
    if ((now - invitationTimestamp) > expirationLimit.inMilliseconds) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.t('chat_invitation_expired'))),
      );
      return;
    }

    final chatRoomID = _getChatRoomID();
    
    final messageIdToDelete = invitationMessage['id'];
    if (messageIdToDelete != null) {
        await _deleteMessageForMe(messageIdToDelete);
    }
    
    final invitationSenderId = invitationMessage['senderID'];
    final currentUser = _auth.currentUser!;
    
    final player1Id = invitationSenderId;
    final player2Id = currentUser.uid;
    final player1Doc = await _firestore.collection('users').doc(player1Id).get();
    final player1Email = player1Doc.data()?['displayName'] ?? 'Player 1';
    final player2Doc = await _firestore.collection('users').doc(player2Id).get();
    final player2Email = player2Doc.data()?['displayName'] ?? 'Player 2';
    
    final gameData = {
      'boardState': _getInitialBoardForFirestore(),
      'player1Id': player1Id,
      'player2Id': player2Id,
      'player1Email': player1Email,
      'player2Email': player2Email,
      'turn': player1Id,
      'status': 'active',
      'winnerId': null,
      'endReason': null,
      'stoppedBy': null,
    };
    
    setState(() {
      _optimisticGameData = gameData;
    });

    final gameDataForFirestore = Map<String, dynamic>.from(gameData);
    gameDataForFirestore['createdAt'] = FieldValue.serverTimestamp();
    
    await _firestore.collection('games').doc(chatRoomID).set(gameDataForFirestore);
    
    _focusNode.unfocus();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _optimisticGameData = null;
        });
      }
    });
  }

  Future<void> _toggleBlockUser(bool isCurrentlyBlocked) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final currentUserRef = _firestore.collection('users').doc(_auth.currentUser!.uid);
    try {
      if (isCurrentlyBlocked) {
        await currentUserRef.update({
          'blockedUsers': FieldValue.arrayRemove([widget.receiverID])
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_user_unblocked'))));
      } else {
        await currentUserRef.update({
          'blockedUsers': FieldValue.arrayUnion([widget.receiverID])
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_user_blocked'))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${lang.t('chat_block_error')}: $e")));
    }
  }

  void _handleMenuSelection(String value, {bool isReceiverBlocked = false}) {
    switch (value) {
      case 'view_contact':
        _navigateToContactInfo();
        break;
      case 'wallpaper':
        _showAnimatedWallpaperDialog();
        break;
      case 'clear_chat':
        _clearChat();
        break;
      case 'block':
        _toggleBlockUser(isReceiverBlocked);
        break;
    }
  }
  
  Future<void> _clearChat() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Clear Chat Dialog',
      transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (context, animation, secondaryAnimation) {
        return AlertDialog(
          title: Text(lang.t('chat_clear_chat_dialog_title')),
          content: Text(lang.t('chat_clear_chat_dialog_content')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(lang.t('chat_clear_chat_dialog_no')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(lang.t('chat_clear_chat_dialog_yes')),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );

    if (confirmed == true) {
      final chatRoomID = _getChatRoomID();
      
      final lastMessageTimestamp = _messages.isNotEmpty 
        ? _messages.first['timestamp'] as int 
        : DateTime.now().millisecondsSinceEpoch;

      await DatabaseHelper.instance.clearChat(chatRoomID);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('clear_timestamp_$chatRoomID', lastMessageTimestamp);

      if (mounted) {
        setState(() {
          _messages.clear();
          _chatItems.clear();
        });
      }
    }
  }

  void _toggleEmojiPicker() async {
    if (_isGameVisible()) return;
  
    if (_isEmojiPickerVisible) {
      Navigator.of(context).pop();
    } else {
      if (mounted) {
        setState(() {
          _isAttachmentPanelVisible = false;
        });
      }
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      await Future.delayed(const Duration(milliseconds: 100));
      if(mounted) _showAnimatedEmojiPicker();
    }
  }

  void _onEmojiSelected(EmojiData emoji) {
    if (_messageController.text.trim().isEmpty) {
      _sendMessage(text: emoji.char, messageType: 'large_emoji');
      if (_isEmojiPickerVisible) Navigator.of(context).pop();
    } else {
      _messageController.text += emoji.char;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    }
  }

  void _showAnimatedEmojiPicker() async {
    setState(() => _isEmojiPickerVisible = true);
    await showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: 'Emoji Picker', transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(alignment: Alignment.center, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Material(color: Colors.transparent, child: ClipRRect(borderRadius: BorderRadius.circular(24), child: SizedBox(height: 350, child: EmojiSelector(onSelected: _onEmojiSelected,)),),),),);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(begin: const Offset(-1.0, 0.0), end: Offset.zero);
        return SlideTransition(position: tween.animate(CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic)), child: FadeTransition(opacity: animation, child: child),);
      },
    );
    if (mounted) {
       setState(() => _isEmojiPickerVisible = false);
    }
  }

  void _navigateBackToHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _navigateToContactInfo() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => ContactInfoScreen(userID: widget.receiverID, userEmail: widget.receiverEmail, photoUrl: null,)));
  }

  void _showComingSoon() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_coming_soon_game')), duration: const Duration(seconds: 2),),);
  }

  Future<void> _pickVideo() async {
    _focusNode.unfocus();
    final XFile? videoFile = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (videoFile == null || !mounted) return;
    _videoEditorController?.dispose();
    _videoEditorController = VideoEditorController.file(
      File(videoFile.path),
      maxDuration: const Duration(minutes: 5),
    );
    await _videoEditorController!.initialize();
    setState(() {
      _selectedVideoFile = File(videoFile.path);
    });
  }

  Future<void> _pickDocument() async {
    _focusNode.unfocus();
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final permanentPath = await mediaUploadService.saveFilePermanently(file.path!);

      final messageId = const Uuid().v4();
      final messageData = {
        DatabaseHelper.columnId: messageId,
        DatabaseHelper.columnChatRoomID: _getChatRoomID(),
        DatabaseHelper.columnSenderID: _auth.currentUser!.uid,
        DatabaseHelper.columnReceiverID: widget.receiverID,
        DatabaseHelper.columnMessageType: 'document',
        DatabaseHelper.columnTimestamp: DateTime.now().millisecondsSinceEpoch,
        DatabaseHelper.columnStatus: 'uploading',
        DatabaseHelper.columnLocalPath: permanentPath,
        DatabaseHelper.columnFileName: file.name,
      };

      _addOptimisticMessage(messageData);
      await mediaUploadService.sendMediaMessageFromData(messageData);
    }
  }

  Future<void> _pickAudio() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    _focusNode.unfocus();
    // Logic: Use FileType.any to avoid strict system pickers, then filter for audio extensions.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final extension = file.extension?.toLowerCase();
      
      const allowedAudioExtensions = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'wma', 'flac', 'amr', '3gp'];
      
      if (extension == null || !allowedAudioExtensions.contains(extension)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_invalid_audio_file'))));
        }
        return;
      }

      final permanentPath = await mediaUploadService.saveFilePermanently(file.path!);
      
      final messageId = const Uuid().v4();
      final messageData = {
        DatabaseHelper.columnId: messageId,
        DatabaseHelper.columnChatRoomID: _getChatRoomID(),
        DatabaseHelper.columnSenderID: _auth.currentUser!.uid,
        DatabaseHelper.columnReceiverID: widget.receiverID,
        DatabaseHelper.columnMessageType: 'audio_file',
        DatabaseHelper.columnTimestamp: DateTime.now().millisecondsSinceEpoch,
        DatabaseHelper.columnStatus: 'uploading',
        DatabaseHelper.columnLocalPath: permanentPath,
        DatabaseHelper.columnFileName: file.name,
      };

      _addOptimisticMessage(messageData);
      await mediaUploadService.sendMediaMessageFromData(messageData);
    }
  }

  Future<void> _pickContact() async {
    _focusNode.unfocus();
    await mediaUploadService.sendContact(
      context,
      chatRoomID: _getChatRoomID(),
      receiverID: widget.receiverID,
    );
    _loadInitialMessages(forceReload: true);
  }

  void _cancelVideoSelection() {
    setState(() {
      _videoEditorController?.dispose();
      _videoEditorController = null;
      _selectedVideoFile = null;
    });
  }
  
  void _cancelStagedVideo() {
    _stagedVideoController?.dispose();
    setState(() {
      _stagedVideoController = null;
      _stagedVideoFile = null;
      _stagedThumbnailPath = null;
      _captionController.clear();
    });
  }

  Future<void> _showAnimatedWallpaperDialog() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final chatRoomID = _getChatRoomID();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 750),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: AlertDialog(
            title: Text(lang.t('chat_change_wallpaper_dialog_title')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(lang.t('chat_change_wallpaper_option')),
                  onTap: () async {
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
                    if (pickedFile != null) {
                      await prefs.setString('wallpaperPath_$chatRoomID', pickedFile.path);
                      if (mounted) {
                        setState(() => _chatBackgroundImagePath = pickedFile.path);
                      }
                    }
                  },
                ),
                if (_chatBackgroundImagePath != null)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: Text(lang.t('chat_remove_wallpaper_option'), style: const TextStyle(color: Colors.redAccent)),
                    onTap: () async {
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      await prefs.remove('wallpaperPath_$chatRoomID');
                      if (mounted) {
                        setState(() => _chatBackgroundImagePath = null);
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isGameVisible() {
    bool isLiveGameActive = _currentGameData != null && (_currentGameData!['status'] == 'active' || _currentGameData!['status'] == 'finished');
    bool isOptimisticGame = _optimisticGameData != null;
    return _isPreparingInvitation || isLiveGameActive || isOptimisticGame;
  }
  
  String _formatLastSeen(int timestamp) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final lastSeenDay = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);

    if (lastSeenDay == today) {
      return "${lang.t('chat_last_seen_prefix')} ${DateFormat.Hm().format(lastSeen)}";
    } else if (lastSeenDay == yesterday) {
      return "${lang.t('chat_last_seen_yesterday_prefix')} ${DateFormat.Hm().format(lastSeen)}";
    } else {
      return "${lang.t('chat_last_seen_date_prefix')} ${DateFormat.yMd().format(lastSeen)}";
    }
  }

  void _handleSend() {
    if (_stagedVideoFile != null) {
       _sendStagedVideo();
    } else if (_messageController.text.trim().isNotEmpty) {
      _sendMessage(messageType: 'text');
    }
  }

  void _startReplying(Map<String, dynamic> message) {
    setState(() {
      _replyingToMessage = message;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }
  
  Future<void> _showDeleteConfirmationDialog(Map<String, dynamic> message) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final messageId = message['id'] as String?;
    if (messageId == null || !mounted) return;

    final isMe = message['senderID'] == _auth.currentUser!.uid;
    final timestamp = message['timestamp'] as int? ?? 0;
    final isRecent = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp)).inMinutes < 60;

    List<Widget> actions = [
      TextButton(
        onPressed: () {
          Navigator.of(context).pop();
          _deleteMessageForMe(messageId);
        },
        child: Text(lang.t('chat_delete_for_me')),
      ),
    ];

    if (isMe && isRecent) {
      actions.add(
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            _deleteMessageForEveryone(messageId);
          },
          child: Text(lang.t('chat_delete_for_everyone')),
        ),
      );
    }
    
    actions.add(
      ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(lang.t('chat_delete_cancel')),
      ),
    );

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Delete Dialog',
      transitionDuration: const Duration(milliseconds: 800),
      pageBuilder: (context, animation, secondaryAnimation) {
        return AlertDialog(
          title: Text(lang.t('chat_delete_confirm_dialog_title')),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: actions,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _deleteMessageForMe(String messageId) async {
    await DatabaseHelper.instance.deleteMessage(messageId);
    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m['id'] == messageId);
        _chatItems.removeWhere((item) => item is Map && item['id'] == messageId);
      });
    }
  }

  Future<void> _deleteMessageForEveryone(String messageId) async {
    try {
      final chatRoomID = _getChatRoomID();
      await _firestore
          .collection('chat_rooms')
          .doc(chatRoomID)
          .collection('messages')
          .doc(messageId)
          .update({
        'message': '', 
        'messageType': 'deleted',
      });
      await _deleteMessageForMe(messageId);
    } catch (e) {
      final lang = Provider.of<LanguageProvider>(context, listen: false);
      log("Error deleting message for everyone: $e");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_delete_for_everyone'))));
      }
    }
  }

  void _onDeleteSelected() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lang.t('chat_multi_delete_dialog_title')),
        content: Text(lang.t('chat_multi_delete_dialog_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(lang.t('chat_delete_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(lang.t('chat_delete_for_me')),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      for (var messageId in _selectedMessages) {
         await _deleteMessageForMe(messageId);
      }
      _clearSelection();
    }
  }


  void _toggleSelection(String messageId) {
    setState(() {
      if (_selectedMessages.contains(messageId)) {
        _selectedMessages.remove(messageId);
        if (_selectedMessages.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessages.add(messageId);
        _isSelectionMode = true;
      }
    });
  }

  void _onCopy() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (_selectedMessages.isEmpty) return;
    final messagesToCopy = _chatItems
      .where((item) => item is Map && _selectedMessages.contains(item['id']) && item['messageType'] == 'text')
      .map((item) => (item as Map)['message'] as String)
      .join('\n');

    if (messagesToCopy.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: messagesToCopy));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_copied_to_clipboard'))));
    }
    _clearSelection();
  }

  void _onReplyFromSelection() {
    if (_selectedMessages.length != 1) return;
    final messageId = _selectedMessages.first;
    final message = _chatItems.firstWhere((item) => item is Map && item['id'] == messageId, orElse: () => null);
    if (message != null) {
      _startReplying(message);
    }
    _clearSelection();
  }

  void _onShare() {
    if (_selectedMessages.isEmpty) return;

    final messagesToForward = _chatItems
        .whereType<Map<String, dynamic>>()
        .where((item) => _selectedMessages.contains(item['id']))
        .toList();
    
    _clearSelection();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ForwardScreen(messagesToForward: messagesToForward),
      ),
    );
  }

  void _clearSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedMessages.clear();
    });
  }
  
  void _scrollToMessage(String messageId) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final index = _chatItems.indexWhere((item) => item is Map && item['id'] == messageId);

    if (index != -1) {
      _scrollController.scrollToIndex(
        index,
        preferPosition: AutoScrollPosition.middle,
        duration: const Duration(milliseconds: 800),
      );
      
      setState(() {
        _highlightedMessageId = messageId;
      });
      
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if(mounted) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });
    } else {
      log("${lang.t('chat_log_message_not_found')}: $messageId");
    }
  }


  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final isGameVisible = _isGameVisible();

    if (isGameVisible && _focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
         _focusNode.unfocus();
      });
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if(didPop) return;

        if (_isSelectionMode) {
          _clearSelection();
          return;
        }

        if (_isAttachmentPanelVisible) {
          setState(() {
            _isAttachmentPanelVisible = false;
          });
          return;
        }
        
        if (_selectedImageData != null) {
          _cancelPhotoSelection();
        } else if (_selectedVideoFile != null) {
          _cancelVideoSelection();
        } else if (_stagedVideoFile != null) {
          _cancelStagedVideo();
        } else if (_isPreparingInvitation) {
          setState(() {
            _isPreparingInvitation = false;
            _isWaitingForGameAcceptance = false;
          });
        } else if (_focusNode.hasFocus) {
          _focusNode.unfocus();
        } else {
          _navigateBackToHome();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        extendBodyBehindAppBar: true,
        appBar: _isSelectionMode
            ? _buildSelectionAppBar()
            : ChatAppBar(
                receiverEmail: widget.receiverEmail,
                receiverID: widget.receiverID,
                presenceStream: _presenceStream,
                activityStream: _activityStream,
                currentUserStream: _currentUserStream,
                receiverUserStream: _receiverUserStream,
                onNavigateBack: _navigateBackToHome,
                onNavigateToContactInfo: _navigateToContactInfo,
                onMenuSelection: _handleMenuSelection,
              ),
        body: Stack(
          children: [
            Container(color: theme.scaffoldBackgroundColor),
            SafeArea(
              child: Column(
                children: [
                  _buildLiveGameArea(),
                  Expanded(
                    child: _buildMessagesContainer(),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _isAttachmentPanelVisible ? _buildAttachmentPanel() : const SizedBox.shrink(),
                  ),
                  _buildMessageComposerContainer(isGameVisible: isGameVisible),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesContainer() {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    
    ImageProvider? backgroundImage;
    BoxFit fit = BoxFit.cover;
    ImageRepeat repeat = ImageRepeat.noRepeat;
    ColorFilter? colorFilter = ColorFilter.mode(Colors.black.withAlpha(128), BlendMode.darken);

    if (_chatBackgroundImagePath != null && File(_chatBackgroundImagePath!).existsSync()) {
      backgroundImage = FileImage(File(_chatBackgroundImagePath!));
    } else if (_globalBackgroundImagePath != null && File(_globalBackgroundImagePath!).existsSync()) {
      backgroundImage = FileImage(File(_globalBackgroundImagePath!));
    } else {
      backgroundImage = const AssetImage('assets/images/star_pattern_dark.png');
      fit = BoxFit.none;
      repeat = ImageRepeat.repeat;
      colorFilter = ColorFilter.mode(Colors.white.withAlpha(26), BlendMode.srcATop);
    }
    
    return GestureDetector(
      onTap: () {
        if (_isAttachmentPanelVisible) {
          setState(() {
            _isAttachmentPanelVisible = false;
          });
        } else if (_focusNode.hasFocus) {
          _focusNode.unfocus();
        }
      },
      child: Container(
        key: const ValueKey('messages_container'),
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withAlpha(200),
          borderRadius: BorderRadius.circular(24.0),
          image: DecorationImage(
            image: backgroundImage,
            fit: fit,
            repeat: repeat,
            colorFilter: colorFilter,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _chatItems.isEmpty
            ? Center(child: Text(lang.t('chat_no_messages')))
            : ListView.builder(
          reverse: true, 
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
          itemCount: _chatItems.length,
          itemBuilder: (context, index) {
            final item = _chatItems[index];

            return AutoScrollTag(
              key: ValueKey(item is String ? "date_${item}_$index" : (item as Map)['id']),
              controller: _scrollController,
              index: index,
              child: Builder(
                builder: (context) {
                  if (item is String) {
                    return DateSeparator(date: item);
                  } else {
                    final messageData = item as Map<String, dynamic>;
                    final messageId = messageData['id'] ?? 'temp_${messageData['timestamp']}';
                    final progress = _uploadProgress[messageId];
                    final isHighlighted = _highlightedMessageId == messageId;

                    return Slidable(
                      key: ValueKey(messageId),
                      startActionPane: ActionPane(
                        motion: const BehindMotion(),
                        extentRatio: 0.25,
                        children: [
                          SlidableAction(
                            onPressed: (_) => _startReplying(messageData),
                            backgroundColor: Colors.transparent,
                            foregroundColor: Theme.of(context).colorScheme.primary,
                            icon: Icons.reply,
                          ),
                        ],
                      ),
                      endActionPane: ActionPane(
                        motion: const BehindMotion(),
                        children: [
                          SlidableAction(
                            onPressed: (_) => _showDeleteConfirmationDialog(messageData),
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            icon: Icons.delete_outline,
                          ),
                        ],
                      ),
                      child: GestureDetector(
                        onLongPress: () => _toggleSelection(messageId),
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleSelection(messageId);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          decoration: BoxDecoration(
                            color: isHighlighted ? theme.colorScheme.primary.withOpacity(0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16)
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          child: MessageBubble(
                            messageData: messageData,
                            isMe: messageData['senderID'] == _auth.currentUser!.uid,
                            isSelected: _selectedMessages.contains(messageId),
                            uploadProgress: progress,
                            onAcceptInvitation: () => _createGameInFirestore(messageData),
                            onDeclineInvitation: (invitationMessage) => _handleDeclineInvitation(invitationMessage),
                            onRetryUpload: () {
                              _retryUpload(messageData['id']);
                            },
                            onReplyTap: (repliedToId) => _scrollToMessage(repliedToId),
                            receiverDisplayName: widget.receiverEmail,
                          ),
                        ),
                      ),
                    );
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }
  
  void _retryUpload(String messageId) async {
    if (mounted) {
      setState(() {
        final index = _chatItems.indexWhere((item) => item is Map && item['id'] == messageId);
        if (index != -1) {
          final oldMessage = _chatItems[index] as Map<String, dynamic>;
          final newMessage = Map<String, dynamic>.from(oldMessage);
          newMessage['status'] = 'uploading';
          _chatItems[index] = newMessage;
          
          _uploadProgress[messageId] = 0.0;
        }
      });
    }
    await DatabaseHelper.instance.updateMessageStatus(messageId, 'pending');
    syncService.triggerSync();
  }
  
  Widget _buildMessageComposerContainer({required bool isGameVisible}) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingToMessage != null)
           Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withAlpha(200),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _replyingToMessage!['senderID'] == _auth.currentUser!.uid 
                            ? lang.t('chat_reply_to_yourself') 
                            : widget.receiverEmail,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _replyingToMessage!['message'] ?? lang.t('chat_reply_media_placeholder'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _cancelReply,
                )
              ],
            ),
           ),
        StreamBuilder<DocumentSnapshot>(
          stream: _currentUserStream,
          builder: (context, currentUserSnapshot) {
            return StreamBuilder<DocumentSnapshot>(
              stream: _receiverUserStream,
              builder: (context, receiverSnapshot) {
                if (!currentUserSnapshot.hasData || !receiverSnapshot.hasData) {
                  return _buildMessageComposer(isGameVisible: isGameVisible, hintText: lang.t('chat_message_input_hint'), isReadOnly: true);
                }

                final currentUserData = currentUserSnapshot.data?.data() as Map<String, dynamic>?;
                final myBlockedUsers = currentUserData?['blockedUsers'] as List<dynamic>? ?? [];
                final iHaveBlockedReceiver = myBlockedUsers.contains(widget.receiverID);

                final receiverData = receiverSnapshot.data?.data() as Map<String, dynamic>?;
                final receiverBlockedUsers = receiverData?['blockedUsers'] as List<dynamic>? ?? [];
                final amIBlockedByReceiver = receiverBlockedUsers.contains(_auth.currentUser!.uid);

                if (amIBlockedByReceiver) {
                  return Container(
                    padding: const EdgeInsets.all(16.0),
                    margin: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withAlpha(220),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Text(
                      lang.t('chat_user_is_blocked_receiver'),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                
                if (iHaveBlockedReceiver) {
                  return Container(
                    padding: const EdgeInsets.all(16.0),
                    margin: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withAlpha(220),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Text(
                      lang.t('chat_user_is_blocked_sender'),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                
                return _buildMessageComposer(isGameVisible: isGameVisible);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildStagedVideoPreviewComposer() {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor.withAlpha(240),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: (_stagedVideoController != null && _stagedVideoController!.value.isInitialized)
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _stagedVideoController!.value.aspectRatio,
                        child: VideoPlayer(_stagedVideoController!),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_stagedVideoController!.value.isPlaying) {
                              _stagedVideoController!.pause();
                            } else {
                              _stagedVideoController!.play();
                            }
                          });
                        },
                        child: AnimatedOpacity(
                          opacity: _stagedVideoController!.value.isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            color: Colors.black.withOpacity(0.3),
                            child: const Center(
                              child: Icon(Icons.play_arrow, color: Colors.white, size: 60),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: _cancelStagedVideo,
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: FloatingActionButton(
                          onPressed: _sendStagedVideo,
                          backgroundColor: theme.colorScheme.primary,
                          child: Icon(Icons.send, color: theme.colorScheme.onPrimary),
                        ),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(30),
            shadowColor: Colors.black.withAlpha(77),
            child: TextField(
              focusNode: _focusNode,
              controller: _captionController,
              style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              decoration: InputDecoration(
                hintText: lang.t('chat_add_caption_hint'),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                fillColor: theme.cardColor,
                filled: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleAttachmentButtonPress() {
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 100;

    if (isKeyboardVisible) {
      // Keyboard is up, so toggle the inline panel.
      setState(() {
        _isAttachmentPanelVisible = !_isAttachmentPanelVisible;
      });
    } else {
      // Keyboard is down, show the dialog animating from the bottom.
      if (_isAttachmentPanelVisible) {
        setState(() {
          _isAttachmentPanelVisible = false;
        });
      }
      _showAnimatedDialogMenu(); 
    }
  }

  Widget _buildMessageComposer({required bool isGameVisible, String? hintText, bool? isReadOnly}) {
    if (_selectedImageData != null) {
      return _buildPhotoPreviewComposer();
    }
    if (_selectedVideoFile != null) {
      return _buildVideoEditorComposer();
    }
    
    if (_stagedVideoFile != null) {
      return _buildStagedVideoPreviewComposer();
    }
    
    return StreamBuilder<DatabaseEvent>(
      stream: _presenceStream,
      builder: (context, snapshot) {
        final lang = Provider.of<LanguageProvider>(context);
        String finalHintText = hintText ?? lang.t('chat_message_input_hint');
        if (hintText == null) {
          if (isGameVisible) {
            finalHintText = lang.t('chat_voice_in_game_hint');
          } else if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            try {
              final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
              final state = data['state'];
              if (state == 'offline') {
                final timestamp = data['last_changed'] as int;
                finalHintText = _formatLastSeen(timestamp);
              }
            } catch(e) {
              finalHintText = lang.t('chat_message_input_hint');
            }
          }
        }
        
        final theme = Theme.of(context);
        bool finalIsReadOnly = isReadOnly ?? isGameVisible;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          color: theme.scaffoldBackgroundColor,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(30),
                shadowColor: Colors.black.withAlpha(77),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(30),),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: IconButton(
                          icon: Icon(_isEmojiPickerVisible ? Icons.keyboard : Icons.emoji_emotions_outlined, color: theme.iconTheme.color?.withAlpha(179)),
                          onPressed: finalIsReadOnly ? null : _toggleEmojiPicker,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: TextField(
                            focusNode: _focusNode,
                            onTap: () {
                              if(_isAttachmentPanelVisible) {
                                setState(() {
                                  _isAttachmentPanelVisible = false;
                                });
                              }
                            },
                            controller: _messageController,
                            readOnly: finalIsReadOnly,
                            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                            keyboardType: TextInputType.multiline,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: finalHintText,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              fillColor: finalIsReadOnly ? Colors.grey.withOpacity(0.1) : null,
                              filled: finalIsReadOnly,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                          icon: Icon(Icons.attach_file, color: theme.iconTheme.color?.withAlpha(179)),
                          onPressed: finalIsReadOnly ? null : _handleAttachmentButtonPress,
                      ),
                      const SizedBox(width: 55),
                    ],
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: _isComposing && !isGameVisible
                    ? FloatingActionButton(key: const ValueKey('send_button'), onPressed: _handleSend, backgroundColor: theme.colorScheme.primary, elevation: 2, child: Icon(Icons.send, color: theme.colorScheme.onPrimary),)
                    : SocialMediaRecorder(
                        key: const ValueKey('mic_recorder'),
                        sendRequestFunction: (File soundFile, String duration) {
                           _myActivityStatusRef?.set("idle");
                           _sendVoiceMessage(soundFile, duration);
                        },
                        recordIcon: FloatingActionButton(
                          key: const ValueKey('mic_button'), 
                          onPressed: () { _myActivityStatusRef?.set("recording"); }, 
                          backgroundColor: theme.colorScheme.secondary,
                          elevation: 2, 
                          child: Icon(Icons.mic, color: theme.colorScheme.onSecondary),
                        ),
                ),
              ),
            ],
          ),
        );
      }
    );
  }
  
  Widget _buildPhotoPreviewComposer() {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Container(
      height: screenHeight * 0.4,
      color: theme.scaffoldBackgroundColor,
      child: Material(
        color: theme.cardColor,
        elevation: 8,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_selectedImageData!, fit: BoxFit.contain),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final editedImageBytes = await Navigator.push<Uint8List?>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ImageEditor(image: _selectedImageData!),
                            ),
                          );
                          if (editedImageBytes != null && mounted) {
                            setState(() {
                              _selectedImageData = editedImageBytes;
                            });
                          }
                        },
                      ),
                      Expanded(
                        child: TextField(
                          controller: _captionController,
                          style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                          decoration: InputDecoration(
                            hintText: lang.t('chat_add_caption_hint'),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _cancelPhotoSelection,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _sendPhoto,
                    icon: const Icon(Icons.send),
                    label: Text(lang.t('chat_send_button')),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 40),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoEditorComposer() {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    return Container(
      height: screenHeight * 0.5,
      color: theme.scaffoldBackgroundColor,
      child: Material(
        color: theme.cardColor,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            children: [
              Expanded(
                child: _videoEditorController != null && _videoEditorController!.initialized
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedBuilder(
                    animation: _videoEditorController!.video,
                    builder: (_, __) =>
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CropGridViewer.preview(controller: _videoEditorController!),
                            GestureDetector(
                              onTap: () {
                                if (_videoEditorController!.isPlaying) {
                                  _videoEditorController!.video.pause();
                                } else {
                                  _videoEditorController!.video.play();
                                }
                              },
                              child: Container(
                                color: Colors.transparent,
                                child: Center(
                                  child: Opacity(
                                    opacity: _videoEditorController!.isPlaying ? 0 : 1,
                                    child: Container(
                                      width: 50,
                                      height: 50,
                                      decoration: const BoxDecoration(
                                        color: Colors.black45,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _videoEditorController!.isPlaying ? Icons.pause : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                  ),
                )
                    : const Center(child: CircularProgressIndicator()),
              ),
              const SizedBox(height: 16),
              if (_videoEditorController != null && _videoEditorController!.initialized)
                AnimatedBuilder(
                    animation: _videoEditorController!,
                    builder: (_, __) {
                      final duration = _videoEditorController!.trimmedDuration;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                            "${lang.t('chat_video_duration')}: ${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}",
                            style: theme.textTheme.bodyMedium
                        ),
                      );
                    }
                ),
              if (_videoEditorController != null && _videoEditorController!.initialized)
                TrimSlider(
                    controller: _videoEditorController!,
                    height: 45,
                    child: TrimTimeline(
                      controller: _videoEditorController!,
                      padding: const EdgeInsets.all(2.0),
                    )),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _cancelVideoSelection,
                    icon: const Icon(Icons.close),
                    label: Text(lang.t('chat_video_trim_cancel')),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                  _isProcessingVideo
                      ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _videoProcessingProgress,
                      strokeWidth: 3,
                    ),
                  )
                      : ElevatedButton.icon(
                    onPressed: _processAndStageVideo,
                    icon: const Icon(Icons.check),
                    label: Text(lang.t('chat_video_trim_continue')),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)
                    ),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showAnimatedDialogMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Attachment Menu',
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => Container(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
        return Transform.translate(
          offset: Offset(0, 150 * (1 - curvedAnimation.value)),
          child: Transform.rotate(
            angle: (1 - curvedAnimation.value) * -0.1,
            child: Opacity(
              opacity: curvedAnimation.value,
              child: AlertDialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                contentPadding: EdgeInsets.zero,
                content: _buildAttachmentContent(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentContent() {
    final lang = Provider.of<LanguageProvider>(context);
    final List<Widget> items = [
      _buildMenuItem(icon: Icons.camera_alt, label: lang.t('chat_attachment_camera'), color: Colors.purple, onTap: () {
        Navigator.pop(context);
        _pickAndPreviewImage(ImageSource.camera);
      }),
      _buildMenuItem(icon: Icons.photo_library, label: lang.t('chat_attachment_photo'), color: Colors.pink, onTap: () {
        Navigator.pop(context);
        _pickAndPreviewImage(ImageSource.gallery);
      }),
      _buildMenuItem(icon: Icons.videocam, label: lang.t('chat_attachment_video'), color: Colors.orange, onTap: () {
        Navigator.pop(context);
        _pickVideo();
      }),
      _buildMenuItem(icon: Icons.headset, label: lang.t('chat_attachment_audio'), color: Colors.lightBlue, onTap: () {
        Navigator.pop(context);
        _pickAudio();
      }),
      _buildMenuItem(icon: Icons.insert_drive_file, label: lang.t('chat_attachment_document'), color: Colors.green, onTap: () {
        Navigator.pop(context);
        _pickDocument();
      }),
      _buildMenuItem(icon: Icons.contact_page, label: lang.t('chat_attachment_contact'), color: Colors.teal, onTap: () {
        Navigator.pop(context);
        _pickContact();
      }),
      _buildMenuItem(icon: Icons.casino, label: lang.t('chat_attachment_dame'), color: Colors.brown, onTap: () async {
        Navigator.pop(context);
        if (_focusNode.hasFocus) {
          _focusNode.unfocus();
          await Future.delayed(const Duration(milliseconds: 300));
        }
        if (mounted) {
          setState(() {
            _isGameHardStopped = false;
            _isPreparingInvitation = true;
          });
        }
      }),
      _buildMenuItem(icon: Icons.grid_on_sharp, label: lang.t('chat_attachment_chess'), color: Colors.grey.shade700, onTap: () {
        Navigator.pop(context);
        _showComingSoon();
      }),
    ];
    return Container(
      width: 350, padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 10, spreadRadius: 2)],),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: items.sublist(0, 4)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: items.sublist(4, 8)),
          ],
        ),
    );
  }

  Widget _buildAttachmentPanel() {
    final lang = Provider.of<LanguageProvider>(context);
    void handleMenuTap(VoidCallback originalOnTap) {
      if (mounted) {
        setState(() {
          _isAttachmentPanelVisible = false;
        });
      }
      Future.delayed(const Duration(milliseconds: 250), originalOnTap);
    }

    final List<Widget> items = [
      _buildMenuItem(icon: Icons.camera_alt, label: lang.t('chat_attachment_camera'), color: Colors.purple, onTap: () => handleMenuTap(() => _pickAndPreviewImage(ImageSource.camera))),
      _buildMenuItem(icon: Icons.photo_library, label: lang.t('chat_attachment_photo'), color: Colors.pink, onTap: () => handleMenuTap(() => _pickAndPreviewImage(ImageSource.gallery))),
      _buildMenuItem(icon: Icons.videocam, label: lang.t('chat_attachment_video'), color: Colors.orange, onTap: () => handleMenuTap(_pickVideo)),
      _buildMenuItem(icon: Icons.headset, label: lang.t('chat_attachment_audio'), color: Colors.lightBlue, onTap: () => handleMenuTap(_pickAudio)),
      _buildMenuItem(icon: Icons.insert_drive_file, label: lang.t('chat_attachment_document'), color: Colors.green, onTap: () => handleMenuTap(_pickDocument)),
      _buildMenuItem(icon: Icons.contact_page, label: lang.t('chat_attachment_contact'), color: Colors.teal, onTap: () => handleMenuTap(_pickContact)),
      _buildMenuItem(icon: Icons.casino, label: lang.t('chat_attachment_dame'), color: Colors.brown, onTap: () {
        handleMenuTap(() async {
          if (_focusNode.hasFocus) {
            _focusNode.unfocus();
            await Future.delayed(const Duration(milliseconds: 300));
          }
          if (mounted) {
            setState(() {
              _isGameHardStopped = false;
              _isPreparingInvitation = true;
            });
          }
        });
      }),
      _buildMenuItem(icon: Icons.grid_on_sharp, label: lang.t('chat_attachment_chess'), color: Colors.grey.shade700, onTap: () => handleMenuTap(_showComingSoon)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(26),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: items.sublist(0, 4)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: items.sublist(4, 8)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 50, height: 50, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 24)), const SizedBox(height: 6), Text(label, style: const TextStyle(fontSize: 12)),],),
    );
  }

  AppBar _buildSelectionAppBar() {
    final lang = Provider.of<LanguageProvider>(context);
    final bool canCopy = _selectedMessages.isNotEmpty && _chatItems
      .where((item) => item is Map && _selectedMessages.contains(item['id']) && item['messageType'] == 'text')
      .isNotEmpty;

    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
      title: Text("${_selectedMessages.length} ${lang.t('chat_selection_bar_title')}"),
      backgroundColor: Colors.blueGrey[800],
      actions: [
        if (_selectedMessages.length == 1)
          IconButton(icon: const Icon(Icons.reply), tooltip: lang.t('chat_selection_bar_reply'), onPressed: _onReplyFromSelection),
        IconButton(icon: const Icon(Icons.share), tooltip: lang.t('chat_selection_bar_share'), onPressed: _onShare),
        if (canCopy)
          IconButton(icon: const Icon(Icons.copy), tooltip: lang.t('chat_selection_bar_copy'), onPressed: _onCopy),
        IconButton(icon: const Icon(Icons.delete), tooltip: lang.t('chat_selection_bar_delete'), onPressed: _onDeleteSelected),
      ],
    );
  }

  Future<void> _stopGame() async {
    final chatRoomID = _getChatRoomID();
    final gameRef = _firestore.collection('games').doc(chatRoomID);

    final gameDoc = await gameRef.get();
    if(gameDoc.exists) {
        await gameRef.update({
        'status': 'stopped',
        'stoppedBy': _auth.currentUser!.uid,
      });
    }

    setState(() {
      _isGameHardStopped = true;
    });
  }

  Widget _buildLiveGameArea() {
    Widget? gameWidget;

    if (_isGameHardStopped) {
      gameWidget = null;
    } else if (_currentGameData != null && (_currentGameData!['status'] == 'active' || _currentGameData!['status'] == 'finished')) {
      gameWidget = DameGameWidget(
        chatRoomID: _getChatRoomID(),
        gameData: _currentGameData!,
        opponentDisplayName: widget.receiverEmail,
        key: ValueKey('game_${_currentGameData!['status']}'),
        onGameStopped: _stopGame,
      );
    }

    if (gameWidget == null && _isPreparingInvitation) {
      final initialBoard = List.generate(10, (row) => List.generate(10, (col) {
        if ((row + col) % 2 != 0) {
          if (row < 4) return {'player': 2, 'type': 'man'};
          if (row > 5) return {'player': 1, 'type': 'man'};
        }
        return null;
      }));
      final previewGameData = {'board': initialBoard};
      gameWidget = DameGameWidget(
        key: const ValueKey('invitation'),
        chatRoomID: '',
        gameData: previewGameData,
        isInvitation: true,
        isWaiting: _isWaitingForGameAcceptance,
        onSendInvitation: _sendGameInvitation,
        onCancel: () {
          setState(() {
            _isPreparingInvitation = false;
            _isWaitingForGameAcceptance = false;
          });
        },
      );
    }

    if (gameWidget == null && _optimisticGameData != null) {
      gameWidget = DameGameWidget(
          chatRoomID: _getChatRoomID(),
          gameData: _optimisticGameData!,
          key: const ValueKey('optimistic_game'),
          onGameStopped: _stopGame,
      );
    }
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, -1.0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          ),
          child: child,
        );
      },
      child: gameWidget ?? const SizedBox.shrink(key: ValueKey('no_game')),
    );
  }
}

class DateSeparator extends StatelessWidget {
  final String date;
  const DateSeparator({super.key, required this.date});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12.0), child: Chip(label: Text(date), backgroundColor: Theme.of(context).cardColor.withAlpha(204))));
}


class ImageBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final bool isUploadingOrFailed;

  const ImageBubble({
    super.key, 
    required this.messageData,
    this.isUploadingOrFailed = false,
  });

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  bool _isDownloading = false;
  double? _downloadProgress;
  bool _localFileExists = false;
  String? _localPath;
  http.Client? _httpClient;

  @override
  void initState() {
    super.initState();
    _checkIfFileExists();
  }

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messageData[DatabaseHelper.columnLocalPath] != oldWidget.messageData[DatabaseHelper.columnLocalPath]) {
      _checkIfFileExists();
    }
  }

  Future<void> _checkIfFileExists() async {
    _localPath = widget.messageData[DatabaseHelper.columnLocalPath];
    bool exists = _localPath != null && await File(_localPath!).exists();
    if (mounted) {
      setState(() => _localFileExists = exists);
    }
  }

  void _handleTap() async {
    final localPath = widget.messageData[DatabaseHelper.columnLocalPath];
    if (localPath != null && await File(localPath).exists()) {
      final String messageId = widget.messageData[DatabaseHelper.columnId] ?? 'image_${widget.messageData['timestamp']}';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullPhotoScreen(
            imageUrl: localPath, 
            isLocalFile: true,
            heroTag: messageId,
          ),
        ),
      );
    } else {
      _handleDownloadTap();
    }
  }
  
  void _handleDownloadTap() {
    if (_isDownloading) {
      _httpClient?.close();
      if (mounted) setState(() { _isDownloading = false; _downloadProgress = null; });
    } else {
      _startDownload();
    }
  }

  Future<void> _startDownload() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final onlineUrl = widget.messageData[DatabaseHelper.columnFileUrl];
    final messageId = widget.messageData[DatabaseHelper.columnId];

    if (onlineUrl == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_generic'))));
      return;
    }

    setState(() { _isDownloading = true; _downloadProgress = 0.0; });

    try {
      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(onlineUrl));
      final response = await _httpClient!.send(request);

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = path.basename(Uri.parse(onlineUrl).path);
        final tempFile = File(path.join(tempDir.path, fileName));
        
        final sink = tempFile.openWrite();
        final totalBytes = response.contentLength ?? -1;
        int receivedBytes = 0;

        await response.stream.listen((List<int> chunk) {
          if(!mounted || !_isDownloading) { sink.close(); _httpClient?.close(); return; }
          receivedBytes += chunk.length;
          if (totalBytes != -1) { setState(() => _downloadProgress = receivedBytes / totalBytes); }
          sink.add(chunk);
        }).asFuture();

        await sink.close();

        final finalPath = await FileStorageService.instance.saveFileToPublicDirectory(
          tempFilePath: tempFile.path, 
          dirType: StorageDirectoryType.images, 
          fileName: fileName
        );
        
        if (finalPath != null) {
          await DatabaseHelper.instance.updateMessageLocalPath(messageId, finalPath);
          
          syncService.notifyUIMessageUpdate(messageId);

          if (mounted) {
             _localPath = finalPath;
             setState(() {
               _localFileExists = true;
               _isDownloading = false;
               _downloadProgress = null;
             });
          }
        } else {
          throw Exception(lang.t('chat_error_write_failed'));
        }

      } else {
        throw Exception(lang.t('chat_error_download_failed'));
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_generic'))));
        setState(() { _isDownloading = false; _downloadProgress = null; });
      }
    } finally {
      _httpClient?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.messageData[DatabaseHelper.columnMessage] as String?;
    final isMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser!.uid;
    final textColor = isMe ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurface;
    
    final thumbnailPath = widget.messageData[DatabaseHelper.columnThumbnailLocalPath];
    final thumbnailUrl = widget.messageData[DatabaseHelper.columnThumbnailUrl] as String?;

    ImageProvider? displayImageProvider;
    if (_localFileExists && _localPath != null) {
      displayImageProvider = FileImage(File(_localPath!));
    } else if (thumbnailPath != null && File(thumbnailPath).existsSync()) {
      displayImageProvider = FileImage(File(thumbnailPath));
    } else if (thumbnailUrl != null) {
      displayImageProvider = CachedNetworkImageProvider(thumbnailUrl);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 250,
            width: 250,
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                if (displayImageProvider != null)
                  GestureDetector(
                    onTap: _handleTap,
                    child: Image(
                      image: displayImageProvider,
                      fit: BoxFit.cover,
                       errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[800],
                            child: const Center(child: Icon(Icons.broken_image, color: Colors.white60)),
                          );
                        },
                    ),
                  )
                else
                  Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.image_outlined, color: Colors.white54, size: 50),
                  ),
                
                if (!_localFileExists && !widget.isUploadingOrFailed)
                   Positioned.fill(
                     child: GestureDetector(
                        onTap: _handleDownloadTap,
                        child: Container(
                          color: Colors.black.withOpacity(0.4),
                          child: Center(
                            child: _isDownloading
                                ? SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CircularProgressIndicator(
                                          value: _downloadProgress,
                                          color: Colors.white,
                                          backgroundColor: Colors.white30,
                                          strokeWidth: 3,
                                        ),
                                        const Center(
                                          child: Icon(Icons.close, color: Colors.white70, size: 25),
                                        ),
                                      ],
                                    ),
                                  )
                                : const Icon(
                                    Icons.download_for_offline,
                                    color: Colors.white,
                                    size: 50,
                                  ),
                          ),
                        ),
                      ),
                   ),
              ],
            ),
          ),
        ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6.0, left: 4.0, right: 4.0),
            child: Text(caption, style: TextStyle(color: textColor)),
          ),
      ],
    );
  }
}

class VoiceBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;

  const VoiceBubble({super.key, required this.messageData});

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  bool _isDownloading = false;
  double? _downloadProgress;
  bool _localFileExists = false;
  String? _localPath;
  http.Client? _httpClient;
  
  @override
  void initState() {
    super.initState();
    _checkIfFileExists();
  }

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VoiceBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messageData[DatabaseHelper.columnLocalPath] != oldWidget.messageData[DatabaseHelper.columnLocalPath]) {
      _checkIfFileExists();
    }
  }

  Future<void> _checkIfFileExists() async {
    _localPath = widget.messageData[DatabaseHelper.columnLocalPath];
    
    bool exists = false;
    if (_localPath != null && _localPath!.isNotEmpty) {
      exists = await File(_localPath!).exists();
    }
    
    if (mounted) {
      setState(() {
        _localFileExists = exists;
      });
    }
  }
  
  void _handleDownloadTap() {
    if (_isDownloading) {
      _httpClient?.close();
      if(mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = null;
        });
      }
    } else {
      _startDownload();
    }
  }

  Future<void> _startDownload() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final onlineUrl = widget.messageData[DatabaseHelper.columnFileUrl];
    final messageId = widget.messageData[DatabaseHelper.columnId];

    if (onlineUrl == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_generic'))));
      return;
    }

    setState(() { _isDownloading = true; _downloadProgress = 0.0; });

    try {
      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(onlineUrl));
      final response = await _httpClient!.send(request);

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = widget.messageData[DatabaseHelper.columnFileName] ?? path.basename(Uri.parse(onlineUrl).path);
        final tempFile = File(path.join(tempDir.path, fileName));
        
        final sink = tempFile.openWrite();
        final totalBytes = response.contentLength ?? -1;
        int receivedBytes = 0;

        await for (var chunk in response.stream) {
          if(!mounted || !_isDownloading) {
            await sink.close();
            _httpClient?.close();
            return;
          }
          receivedBytes += chunk.length;
          if (totalBytes != -1) { setState(() => _downloadProgress = receivedBytes / totalBytes); }
          sink.add(chunk);
        }
        await sink.close();
        
        final finalPath = await FileStorageService.instance.saveFileToPublicDirectory(
          tempFilePath: tempFile.path, 
          dirType: StorageDirectoryType.documents, 
          fileName: fileName
        );
        
        if (finalPath != null) {
          await DatabaseHelper.instance.updateMessageLocalPath(messageId, finalPath);

          syncService.notifyUIMessageUpdate(messageId);
          
          if (mounted) {
             setState(() {
               _localPath = finalPath;
               _localFileExists = true;
               _isDownloading = false;
               _downloadProgress = null;
             });
          }
        } else {
          throw Exception(lang.t('chat_error_write_failed'));
        }

      } else {
        throw Exception(lang.t('chat_error_download_failed'));
      }
    } catch (e) {
      if (e is http.ClientException) {
        debugPrint("Gukurura byahagaritswe.");
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_generic'))));
      }
      if(mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = null;
        });
      }
    } finally {
      _httpClient?.close();
      _httpClient = null;
    }
  }
  
  String _formatDuration(Duration d) {
    if (d.inMilliseconds < 0) return "00:00";
    if (d.inHours > 0) {
      return d.toString().split('.').first.padLeft(8, "0");
    }
    return "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final messageType = widget.messageData[DatabaseHelper.columnMessageType];

    if (messageType == 'voice_note') {
      return _buildVoiceNoteUI();
    } else {
      return _buildAudioFileUI();
    }
  }
  
  Widget _buildVoiceNoteUI() {
    final isMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser!.uid;
    final textColor = isMe ? Colors.white : Colors.black;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        color: Colors.transparent,
        child: _localFileExists 
          ? _buildVoiceNotePlayerUI(textColor) 
          : _buildVoiceNoteDownloaderUI(textColor),
      ),
    );
  }
  
  Widget _buildAudioFileUI() {
    final isMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser!.uid;
    final textColor = isMe ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).textTheme.bodyLarge?.color;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 250,
        color: Colors.transparent,
        child: _localFileExists 
          ? _buildAudioFilePlayerUI(textColor!)
          : _buildAudioFileDownloaderUI(textColor!),
      ),
    );
  }

  Widget _buildVoiceNotePlayerUI(Color textColor) {
    final playerService = context.watch<AudioPlayerService>();
    final isMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser!.uid;

    final Color activeWaveColor = isMe ? Colors.white : Theme.of(context).colorScheme.primary;
    final Color inactiveWaveColor = isMe ? Colors.white.withOpacity(0.4) : Colors.blue.shade200;

    final isCurrentMessage = playerService.currentMessageId == widget.messageData['id'];
    final isPlaying = isCurrentMessage && playerService.isPlaying;
    
    final position = isCurrentMessage ? playerService.position : Duration.zero;
    final totalDurationValue = widget.messageData['duration'] ?? 0;
    final totalDuration = isCurrentMessage && playerService.duration.inSeconds > 0 
        ? playerService.duration 
        : Duration(seconds: totalDurationValue > 0 ? totalDurationValue : 1);

    final audioSource = _localPath ?? widget.messageData[DatabaseHelper.columnFileUrl];

    void handlePlayPause() {
      if (audioSource != null) {
        final isLocal = !(audioSource as String).startsWith('http');
        playerService.loadAudio(widget.messageData['id'], audioSource, isLocal);
      }
    }

    final List<double> waveform = (widget.messageData['waveform'] != null && widget.messageData['waveform'].isNotEmpty) 
          ? List<double>.from(jsonDecode(widget.messageData['waveform'])) 
          : List.filled(60, 0.1); 
          
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: handlePlayPause,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isMe ? Colors.black.withOpacity(0.2) : Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 35,
              child: WaveformPainter(
                waveform: waveform,
                progress: (totalDuration.inMilliseconds == 0) ? 0 : position.inMilliseconds / totalDuration.inMilliseconds,
                activeColor: activeWaveColor,
                inactiveColor: inactiveWaveColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(totalDuration),
            style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioFilePlayerUI(Color textColor) {
    final lang = Provider.of<LanguageProvider>(context);
    final playerService = context.watch<AudioPlayerService>();
    final isCurrentMessage = playerService.currentMessageId == widget.messageData['id'];
    final isPlaying = isCurrentMessage && playerService.isPlaying;
    
    final position = isCurrentMessage ? playerService.position : Duration.zero;
    final totalDurationValue = widget.messageData['duration'] ?? 0;
    final totalDuration = isCurrentMessage && playerService.duration.inSeconds > 0 
        ? playerService.duration 
        : Duration(seconds: totalDurationValue > 0 ? totalDurationValue : 1);

    final audioSource = _localPath ?? widget.messageData[DatabaseHelper.columnFileUrl];
    final fileName = widget.messageData[DatabaseHelper.columnFileName] as String?;

    void handlePlayPause() {
      if (audioSource != null) {
        final isLocal = !(audioSource as String).startsWith('http');
        playerService.loadAudio(widget.messageData['id'], audioSource, isLocal);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.music_note_rounded, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fileName ?? lang.t('chat_reply_audio_file'),
                  style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
            ),
            child: Slider(
              value: position.inMilliseconds.toDouble().clamp(0.0, totalDuration.inMilliseconds.toDouble()),
              min: 0.0,
              max: totalDuration.inMilliseconds.toDouble(),
              onChanged: (value) {
                if(isCurrentMessage) {
                  playerService.seek(Duration(milliseconds: value.toInt()));
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position), style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7))),
                IconButton(
                  icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: textColor, size: 30),
                  onPressed: handlePlayPause,
                ),
                Text(_formatDuration(totalDuration), style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceNoteDownloaderUI(Color textColor) {
    final totalDurationValue = widget.messageData['duration'] ?? 0;
    final totalDuration = Duration(seconds: totalDurationValue);

    return InkWell(
      onTap: _handleDownloadTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        height: 51,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _formatDuration(totalDuration),
              style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.8)),
            ),
            _isDownloading
              ? SizedBox(
                  width: 30,
                  height: 30,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                          value: _downloadProgress,
                          strokeWidth: 2,
                          color: Colors.white,
                          backgroundColor: Colors.white.withOpacity(0.3)
                      ),
                    ]
                  ),
                )
              : Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.download_for_offline_outlined, color: Colors.white, size: 20),
                ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAudioFileDownloaderUI(Color textColor) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final fileName = widget.messageData[DatabaseHelper.columnFileName] as String?;
    final totalDurationValue = widget.messageData[DatabaseHelper.columnDuration] ?? 0;
    final totalDuration = Duration(seconds: totalDurationValue);

    return InkWell(
      onTap: _handleDownloadTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)
                  ),
                  child: Icon(Icons.music_note, color: theme.colorScheme.primary, size: 28),
                ),
                if (_isDownloading)
                  SizedBox(
                    width: 52, height: 52,
                    child: Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(value: _downloadProgress, strokeWidth: 3, color: theme.colorScheme.primary, backgroundColor: Colors.black.withOpacity(0.2)),
                        Center(child: Icon(Icons.close, color: textColor, size: 20))
                      ],
                    ),
                  )
                else
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.download_for_offline_outlined, color: Colors.white, size: 28),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName ?? lang.t('chat_attachment_audio'),
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                   Text(
                    _formatDuration(totalDuration),
                    style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoPlayerBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final String? caption;
  final bool isUploadingOrFailed;

  const VideoPlayerBubble({
    super.key, 
    required this.messageData, 
    this.caption,
    this.isUploadingOrFailed = false,
  });

  @override
  State<VideoPlayerBubble> createState() => _VideoPlayerBubbleState();
}

class _VideoPlayerBubbleState extends State<VideoPlayerBubble> {
  bool _isDownloading = false;
  double? _downloadProgress;
  bool _localFileExists = false;
  String? _localPath;
  http.Client? _httpClient;
  VideoPlayerController? _controller;
  Timer? _hideControlsTimer;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _checkIfFileExistsAndInitialize();
  }
  
  @override
  void didUpdateWidget(covariant VideoPlayerBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messageData[DatabaseHelper.columnLocalPath] != oldWidget.messageData[DatabaseHelper.columnLocalPath]) {
      _resetController();
    }
  }

  @override
  void dispose() {
    _httpClient?.close();
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _resetController() async {
    _hideControlsTimer?.cancel();
    await _controller?.dispose();
    _controller = null;
    await _checkIfFileExistsAndInitialize();
  }

  Future<void> _checkIfFileExistsAndInitialize() async {
    _localPath = widget.messageData[DatabaseHelper.columnLocalPath];
    bool exists = _localPath != null && await File(_localPath!).exists();
    if (mounted) {
      setState(() { _localFileExists = exists; });
    }
  }

  Future<void> _initializeController() async {
    if (_localPath == null || _controller != null) return;

    final newController = VideoPlayerController.file(File(_localPath!));
    try {
      await newController.initialize();
      if (mounted) {
        setState(() { _controller = newController; });
        _startHideControlsTimer();
        newController.addListener(() {
          if (mounted && newController.value.position >= newController.value.duration) {
            _hideControlsTimer?.cancel();
            setState(() { _showControls = true; });
          }
        });
        newController.play();
      }
    } catch (e) {
      final lang = Provider.of<LanguageProvider>(context, listen: false);
      log("${lang.t('chat_error_video_init')}: $e");
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if(!_showControls) return;
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller?.value.isPlaying == true) {
        setState(() { _showControls = false; });
      }
    });
  }

  void _handleTap() {
    if (_localFileExists && _localPath != null) {
      if (_controller == null || !_controller!.value.isInitialized) {
        _initializeController();
      } else {
        _toggleControlsVisibility();
      }
    } else {
      _handleDownloadTap();
    }
  }
  
  void _handleDownloadTap() {
    if (_isDownloading) {
      _httpClient?.close();
      if(mounted) setState(() { _isDownloading = false; _downloadProgress = null; });
    } else {
      _startDownload();
    }
  }

  Future<void> _startDownload() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final onlineUrl = widget.messageData[DatabaseHelper.columnFileUrl];
    final messageId = widget.messageData[DatabaseHelper.columnId];
    if (onlineUrl == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_generic'))));
      return;
    }

    setState(() { _isDownloading = true; _downloadProgress = 0.0; });

    try {
      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(onlineUrl));
      final response = await _httpClient!.send(request);

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = path.basename(Uri.parse(onlineUrl).path);
        final tempFile = File(path.join(tempDir.path, fileName));

        final sink = tempFile.openWrite();
        final totalBytes = response.contentLength ?? -1;
        int receivedBytes = 0;

        await response.stream.listen((List<int> chunk) {
          if(!mounted || !_isDownloading) { sink.close(); _httpClient?.close(); return; }
          receivedBytes += chunk.length;
          if (totalBytes != -1) { setState(() => _downloadProgress = receivedBytes / totalBytes); }
          sink.add(chunk);
        }).asFuture();

        await sink.close();
        
        final finalPath = await FileStorageService.instance.saveFileToPublicDirectory(
          tempFilePath: tempFile.path, 
          dirType: StorageDirectoryType.video, 
          fileName: fileName
        );

        if (finalPath != null) {
          await DatabaseHelper.instance.updateMessageLocalPath(messageId, finalPath);

          syncService.notifyUIMessageUpdate(messageId);
          
          if (mounted) {
             _localPath = finalPath;
             _localFileExists = true;
             _isDownloading = false;
             _downloadProgress = null;
          }
        } else {
          throw Exception(lang.t('chat_error_write_failed'));
        }

      } else {
        throw Exception(lang.t('chat_error_download_failed'));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_generic'))));
        setState(() { _isDownloading = false; _downloadProgress = null; });
      }
    } finally {
      _httpClient?.close();
    }
  }

  void _togglePlayPause() {
    if (_controller != null && _controller!.value.isInitialized) {
      setState(() {
        if(_controller!.value.isPlaying){
          _controller!.pause();
          _hideControlsTimer?.cancel();
        } else {
          if(_controller!.value.position >= _controller!.value.duration){
            _controller!.seekTo(Duration.zero);
          }
          _controller!.play();
          _startHideControlsTimer();
        }
      });
    } else if (_localFileExists) {
      _initializeController();
    }
  }

  void _toggleControlsVisibility() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideControlsTimer();
      } else {
        _hideControlsTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUserMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser!.uid;
    final textColor = isUserMe ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface;

    final thumbnailPath = widget.messageData[DatabaseHelper.columnThumbnailLocalPath];
    final thumbnailUrl = widget.messageData[DatabaseHelper.columnThumbnailUrl] as String?;

    ImageProvider? thumbnailProvider;
    if (thumbnailPath != null && File(thumbnailPath).existsSync()) {
      thumbnailProvider = FileImage(File(thumbnailPath));
    } else if (thumbnailUrl != null) {
      thumbnailProvider = CachedNetworkImageProvider(thumbnailUrl);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 200,
            width: 250,
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                if (_controller != null && _controller!.value.isInitialized)
                  GestureDetector(
                    onTap: _toggleControlsVisibility,
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                else if (thumbnailProvider != null)
                  GestureDetector(
                    onTap: _handleTap,
                    child: Image(
                        image: thumbnailProvider,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(color: Colors.black87, child: const Icon(Icons.videocam, color: Colors.white54, size: 50)),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _handleTap,
                    child: Container(color: Colors.black87, child: const Icon(Icons.videocam, color: Colors.white54, size: 50))
                  ),
                
                if (_controller != null && _controller!.value.isInitialized) ...[
                    GestureDetector(
                      onTap: _toggleControlsVisibility,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          color: Colors.black26,
                          child: Center(
                            child: IconButton(
                              icon: Icon(
                                _controller != null && _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, 
                                color: const Color.fromRGBO(255, 255, 255, 0.8), 
                                size: 50
                              ),
                              onPressed: _togglePlayPause,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: IconButton(
                          icon: const Icon(Icons.fullscreen, color: Colors.white),
                          onPressed: () async {
                            if (_localPath != null){
                              final currentPosition = _controller?.value.position ?? Duration.zero;
                              _controller?.pause();
                              
                              final newPosition = await Navigator.of(context).push(PageRouteBuilder<Duration>(
                                  pageBuilder: (context, animation, secondaryAnimation) => FullScreenVideoPlayer(videoUrl: _localPath!, startAt: currentPosition),
                                  transitionDuration: const Duration(milliseconds: 600),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    const begin = Offset(0.0, 1.0);
                                    const end = Offset.zero;
                                    const curve = Curves.easeInOut;
                                    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                    var offsetAnimation = animation.drive(tween);
                                    return SlideTransition(position: offsetAnimation, child: child);
                                  },
                                ));

                              if (newPosition != null && _controller != null) {
                                _controller?.seekTo(newPosition);
                                _controller?.play();
                              }
                            }
                          },
                        ),
                      ),
                    ),
                     if (_controller != null && _controller!.value.isInitialized)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: AnimatedOpacity(
                          opacity: _showControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: VideoProgressIndicator(
                            _controller!,
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor: theme.colorScheme.primary,
                              bufferedColor: Colors.grey.withOpacity(0.5),
                              backgroundColor: Colors.black.withOpacity(0.3),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          ),
                        ),
                      ),
                  ] 
                else if (_localFileExists) 
                  Center(
                    child: IconButton(
                      icon: const Icon(Icons.play_circle_fill, color: Color.fromRGBO(255, 255, 255, 0.8), size: 50),
                      onPressed: _togglePlayPause,
                    ),
                  )
                else if (!_localFileExists && !widget.isUploadingOrFailed)
                  Positioned(
                    bottom: 8, right: 8,
                    child: GestureDetector(
                      onTap: _handleDownloadTap,
                      child: Container(
                        width: 40, height: 40,
                        padding: _isDownloading ? const EdgeInsets.all(4) : EdgeInsets.zero,
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle,),
                        child: _isDownloading
                          ? Stack(fit: StackFit.expand, children: [
                              CircularProgressIndicator(value: _downloadProgress, color: Colors.white, backgroundColor: Colors.white30, strokeWidth: 3),
                              const Center(child: Icon(Icons.close, color: Colors.white70, size: 20)),
                            ])
                          : const Icon(Icons.download_for_offline, color: Colors.white, size: 30),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (widget.caption != null && widget.caption!.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 6.0, left: 4.0, right: 4.0),
              child: Text(widget.caption!, style: TextStyle(color: textColor))
          ),
      ],
    );
  }
}

class MessageBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final bool isMe;
  final bool isSelected;
  final double? uploadProgress;
  final VoidCallback? onAcceptInvitation;
  final Function(Map<String, dynamic>)? onDeclineInvitation;
  final VoidCallback? onRetryUpload;
  final Function(String messageId)? onReplyTap;
  final String receiverDisplayName;

  const MessageBubble({
    super.key,
    required this.messageData,
    required this.isMe,
    required this.isSelected,
    this.uploadProgress,
    this.onAcceptInvitation,
    this.onDeclineInvitation,
    this.onRetryUpload,
    this.onReplyTap,
    required this.receiverDisplayName,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _actionTaken = false;

  Widget _buildStatusIcon(String? status, ThemeData theme) {
    IconData icon;
    Color color;
    final isVoiceNote = widget.messageData['messageType'] == 'voice_note';
    
    switch (status) {
      case 'seen':
        icon = Icons.visibility;
        color = Colors.cyan.shade300;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = widget.isMe && isVoiceNote ? Colors.white.withOpacity(0.8) : (theme.textTheme.bodyMedium?.color ?? Colors.grey);
        break;
      case 'sent':
        icon = Icons.done;
        color = widget.isMe && isVoiceNote ? Colors.white.withOpacity(0.8) : (theme.textTheme.bodyMedium?.color ?? Colors.grey);
        break;
      case 'failed':
      case 'canceled':
        icon = Icons.error_outline;
        color = Colors.red.shade400;
        break;
      case 'pending':
      case 'uploading':
      case 'paused':
      default:
        icon = Icons.watch_later_outlined;
        color = widget.isMe && isVoiceNote ? Colors.white.withOpacity(0.8) : (theme.textTheme.bodyMedium?.color ?? Colors.grey);
    }
    return Icon(icon, size: 16, color: color);
  }

  String _formatMessageTimestamp(int? timestampMillis) {
    if (timestampMillis == null) {
      if (widget.messageData['status'] == 'pending') return '';
      return DateFormat.Hm().format(DateTime.now());
    }
    return DateFormat.Hm().format(DateTime.fromMillisecondsSinceEpoch(timestampMillis));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messageType = widget.messageData['messageType'];
    final isLargeEmoji = messageType == 'large_emoji';
    final isContact = messageType == 'contact';
    final isVoiceNote = messageType == 'voice_note';
    final isAudioFile = messageType == 'audio_file';
    final isAudio = isVoiceNote || isAudioFile;
    
    Color bubbleColor;
    Color textColor;

    if (widget.isMe) {
      if (isVoiceNote) {
        bubbleColor = const Color(0xFF262626);
        textColor = Colors.white;
      } else if (isAudioFile) {
        bubbleColor = theme.colorScheme.surfaceVariant;
        textColor = theme.colorScheme.onSurfaceVariant;
      } else {
        bubbleColor = theme.colorScheme.primaryContainer;
        textColor = theme.colorScheme.onPrimaryContainer;
      }
    } else {
      if (isVoiceNote) {
        bubbleColor = Colors.blue;
        textColor = Colors.white;
      } else {
        bubbleColor = theme.colorScheme.surface;
        textColor = theme.colorScheme.onSurface;
      }
    }
    
    if (isLargeEmoji || isContact) {
      bubbleColor = Colors.transparent;
    }
    if (widget.isSelected) {
      bubbleColor = theme.colorScheme.primary.withOpacity(0.4);
    }

    final bool hasOverlay = ['uploading', 'paused', 'failed', 'canceled'].contains(widget.messageData['status']);

    int? timestampValue;
    if (widget.messageData['timestamp'] is int) {
      timestampValue = widget.messageData['timestamp'];
    }

    final replyInfo = widget.messageData[DatabaseHelper.columnReplyingTo] as String?;
    Map<String, dynamic>? replyMessage;
    if (replyInfo != null) {
      try {
        replyMessage = jsonDecode(replyInfo);
      } catch (e) {
        log("Error decoding reply info: $e");
      }
    }

    Widget messageContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (replyMessage != null)
          _ReplyPreview(
            replyMessage: replyMessage,
            onTap: () {
              if (widget.onReplyTap != null && replyMessage!['id'] != null) {
                widget.onReplyTap!(replyMessage!['id']);
              }
            },
            receiverDisplayName: widget.receiverDisplayName,
          ),
        _buildMessageContent(context, widget.messageData, textColor, hasOverlay),
      ],
    );

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: (isLargeEmoji || isContact || isAudioFile) ? EdgeInsets.zero : (isVoiceNote ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(isAudioFile ? 12 : 16)
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                messageContent,
                if (!isLargeEmoji && !isContact && !isAudio && messageType != 'deleted') const SizedBox(height: 4),
                if (!isLargeEmoji && !isContact && !isAudio && messageType != 'deleted')
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_formatMessageTimestamp(timestampValue), style: TextStyle(fontSize: 10, color: textColor.withAlpha(179)),),
                      if (widget.isMe) const SizedBox(width: 4),
                      if (widget.isMe) _buildStatusIcon(widget.messageData['status'], theme),
                    ],
                  )
              ],
            ),
          ),
          if(widget.isMe && isVoiceNote)
             Positioned(
               bottom: -2,
               right: 8,
               child: Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Text(
                     _formatMessageTimestamp(timestampValue),
                     style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.8)),
                   ),
                   const SizedBox(width: 4),
                   _buildStatusIcon(widget.messageData['status'], theme),
                 ],
               ),
             ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context, Map<String, dynamic> data, Color textColor, bool hasOverlay) {
    final lang = Provider.of<LanguageProvider>(context);
    final type = data[DatabaseHelper.columnMessageType];
    Widget content;
    switch (type) {
      case 'deleted':
        content = Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.not_interested, size: 14, color: textColor.withAlpha(179)),
              const SizedBox(width: 6),
              Text(
                lang.t('chat_deleted_message_placeholder'),
                style: TextStyle(color: textColor.withAlpha(179), fontStyle: FontStyle.italic),
              ),
            ],
          ),
        );
        break;
      case 'dame_invitation_declined':
        content = Text(data['message'] ?? lang.t('chat_declined_invitation_placeholder'), style: TextStyle(color: textColor, fontStyle: FontStyle.italic));
        break;
      case 'dame_invitation':
        final int timestamp = data['timestamp'] ?? 0;
        final bool isExpired = (DateTime.now().millisecondsSinceEpoch - timestamp) > const Duration(minutes: 5).inMilliseconds;

        content = Column(
          crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(data['message'] ?? '', style: TextStyle(color: textColor, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),

            if (!widget.isMe && !_actionTaken && !isExpired)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _actionTaken = true);
                      widget.onDeclineInvitation?.call(widget.messageData);
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
                    child: Text(lang.t('dialog_no')),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _actionTaken = true);
                      widget.onAcceptInvitation?.call();
                    },
                    child: Text(lang.t('dame_resign_confirm').split(',').first), // "Ego" from "Ego, Natsinzwe"
                  ),
                ],
              ),

            if (!widget.isMe && isExpired)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  lang.t('chat_invitation_expired'),
                  style: TextStyle(color: textColor.withAlpha(179), fontStyle: FontStyle.italic, fontSize: 12),
                ),
              ),

          ],
        );
        break;
      case 'large_emoji':
        content = Padding(padding: const EdgeInsets.all(8.0), child: Text(data['message'] ?? '', style: const TextStyle(fontSize: 50)),);
        break;
      case 'text':
        // HANO NIHO UBWENGE BWA LINK BWAJEMO
        content = SelectableLinkify(
          onOpen: (link) async {
            final String url = link.url;
            
            // 1. REBA NIBA ARI LINK YA JEMBE TALK
            if (url.contains('jembe-talk.web.app/post') && url.contains('id=')) {
              try {
                final uri = Uri.parse(url);
                final postId = uri.queryParameters['id'];
                if (postId != null) {
                  // Fungura Tangaza Star imbere muri App
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => TangazaStarScreen(targetPostId: postId),
                    ),
                  );
                  return; // Sohotse, ntukore ibindi
                }
              } catch (e) {
                debugPrint("Ikosa ryo gusesengura link: $e");
              }
            }

            // 2. NIBA ATARI IYA JEMBE TALK (YouTube, TikTok, etc.)
            try {
              final Uri uri = Uri.parse(url);
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                 if (!await launchUrl(uri)) {
                    throw 'Ntibishobotse gufungura';
                 }
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ntibikunze gufungura: $url')),
              );
            }
          },
          text: data['message'] ?? '',
          style: TextStyle(color: textColor, fontSize: 16),
          linkStyle: TextStyle(
            color: widget.isMe ? Colors.white : Colors.blue,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.bold,
          ),
          options: const LinkifyOptions(humanize: false),
        );
        break;
      case 'image':
        content = ImageBubble(
          messageData: data,
          isUploadingOrFailed: hasOverlay,
        );
        break;
      case 'video':
        content = VideoPlayerBubble(
          messageData: data, 
          caption: data[DatabaseHelper.columnMessage],
          isUploadingOrFailed: hasOverlay,
        );
        break;
      case 'voice_note':
      case 'audio_file':
        content = VoiceBubble(messageData: data);
        break;
      
      case 'document':
        content = DocumentBubble(
          messageData: data,
          textColor: textColor,
        );
        break;
        
      case 'contact':
        try {
          final contactJson = jsonDecode(data['message']) as Map<String, dynamic>;
          content = ContactBubble(
            contactData: contactJson,
          );
        } catch (e) {
          log("Error decoding contact JSON: $e");
          content = Text('[Contact yaje nabi]', style: TextStyle(color: textColor, fontStyle: FontStyle.italic));
        }
        break;
      default:
        content = Text(lang.t('chat_unsupported_message'), style: TextStyle(color: textColor));
    }
    
    if (hasOverlay) {
      final status = data['status'];
      final bool isUploading = status == 'uploading' || status == 'paused';
      final bool isFailedOrCanceled = status == 'failed' || status == 'canceled';
      
      return Stack(
        alignment: Alignment.center,
        children: [
          content,
          if(type == 'document') // REMOVED audio overlay to allow playback
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(isUploading ? 80 : 40),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          Positioned(
            bottom: 8,
            right: 8,
            child: GestureDetector(
              onTap: () {
                if(isFailedOrCanceled) {
                  widget.onRetryUpload?.call();
                } else {
                  syncService.cancelUpload(data[DatabaseHelper.columnId]);
                }
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: isUploading
                    ? Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: widget.uploadProgress,
                            backgroundColor: Colors.white.withAlpha(77),
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                          const Center(
                            child: Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ],
                      )
                    : Icon(
                        isFailedOrCanceled ? Icons.upload_rounded : Icons.error, 
                        color: Colors.white, 
                        size: 24,
                      ),
              ),
            ),
          ),
        ],
      );
    }
    return content;
  }
}

class _ReplyPreview extends StatelessWidget {
  final Map<String, dynamic> replyMessage;
  final VoidCallback onTap;
  final String receiverDisplayName;

  const _ReplyPreview({
    required this.replyMessage, 
    required this.onTap, 
    required this.receiverDisplayName
  });

  String _getPreviewText(LanguageProvider lang) {
    final type = replyMessage['messageType'];
    switch (type) {
      case 'text':
        return replyMessage['message'] ?? '';
      case 'image':
        return lang.t('chat_reply_photo');
      case 'video':
        return lang.t('chat_reply_video');
      case 'voice_note':
        return lang.t('chat_reply_voice_note');
      case 'audio_file':
        return lang.t('chat_reply_audio_file');
      case 'document':
        return replyMessage['fileName'] ?? lang.t('chat_reply_document');
      case 'contact':
        return lang.t('chat_reply_contact');
      default:
        return lang.t('chat_reply_generic_message');
    }
  }

  IconData _getPreviewIcon() {
    final type = replyMessage['messageType'];
     switch (type) {
      case 'image': return Icons.photo_camera;
      case 'video': return Icons.videocam;
      case 'voice_note': return Icons.mic;
      case 'audio_file': return Icons.headset;
      case 'document': return Icons.insert_drive_file;
      case 'contact': return Icons.person;
      default: return Icons.messenger_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final isMe = replyMessage['senderID'] == FirebaseAuth.instance.currentUser!.uid;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.1),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? lang.t('chat_reply_to_yourself') : receiverDisplayName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (replyMessage['messageType'] != 'text')
                          Icon(_getPreviewIcon(), size: 14, color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7)),
                        if (replyMessage['messageType'] != 'text')
                          const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _getPreviewText(lang),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class WaveformPainter extends StatelessWidget {
  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  const WaveformPainter({
    super.key, 
    required this.waveform, 
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) =>
      CustomPaint(
        size: Size.infinite, 
        painter: _WaveformCustomPainter(
          waveData: waveform, 
          progress: progress, 
          activeColor: activeColor,
          inactiveColor: inactiveColor
        ),
      );
}

class _WaveformCustomPainter extends CustomPainter {
  final List<double> waveData;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformCustomPainter({
    required this.waveData,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintInactive = Paint()..color = inactiveColor;
    final paintActive = Paint()..color = activeColor;
    
    const barWidth = 3.0;
    const barGap = 2.0;

    final maxBars = (size.width / (barWidth + barGap)).floor();

    for (int i = 0; i < maxBars; i++) {
      final barHeight = waveData[(i * waveData.length / maxBars).floor()].clamp(0.05, 1.0) * size.height;
      
      final x = i * (barWidth + barGap);
      final y = (size.height - barHeight) / 2;
      
      final currentBarPosition = i / maxBars;
      final paint = currentBarPosition < progress ? paintActive : paintInactive;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2)
        ),
        paint
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}


class ImagePreviewScreen extends StatefulWidget {
  final String imagePath;

  const ImagePreviewScreen({super.key, required this.imagePath});

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  final TextEditingController _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop(),),),
      body: Column(
        children: [
          Expanded(child: InteractiveViewer(child: Center(child: Image.file(File(widget.imagePath)),),),),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
            child: Row(
              children: [
                Expanded(child: Container(decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(24),), child: TextField(controller: _captionController, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: lang.t('chat_add_caption_hint'), hintStyle: const TextStyle(color: Colors.white70), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),),),),),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: () {
                    final result = {'path': widget.imagePath, 'caption': _captionController.text.trim(),};
                    Navigator.of(context).pop(result);
                  },
                  backgroundColor: theme.colorScheme.primary,
                  child: Icon(Icons.send, color: theme.colorScheme.onPrimary),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final Duration startAt;

  const FullScreenVideoPlayer({super.key, required this.videoUrl, required this.startAt});

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }

  Future<void> initializePlayer() async {
    final isLocal = !widget.videoUrl.startsWith('http');
    _videoPlayerController = isLocal ? VideoPlayerController.file(File(widget.videoUrl)) : VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    try {
      await _videoPlayerController.initialize();
      await _videoPlayerController.seekTo(widget.startAt);
      _createChewieController();
    } catch (e) {
      final lang = Provider.of<LanguageProvider>(context, listen: false);
      debugPrint("${lang.t('chat_error_video_play')}: $e");
    }
    finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _createChewieController() {
    _chewieController = ChewieController(videoPlayerController: _videoPlayerController, autoPlay: true, looping: false);
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _isLoading ? const CircularProgressIndicator()
                : (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized)
                ? Chewie(controller: _chewieController!)
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error, color: Colors.red, size: 40), const SizedBox(height: 16), Text(lang.t('chat_error_video_play'), style: const TextStyle(color: Colors.white))]),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () {
                  final currentPosition = _videoPlayerController.value.position;
                  Navigator.of(context).pop(currentPosition);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ContactBubble extends StatelessWidget {
  final Map<String, dynamic> contactData;

  const ContactBubble({
    super.key,
    required this.contactData,
  });

  Future<void> _addContactToPhone(BuildContext context) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    try {
      if (await Permission.contacts.request().isGranted) {
        
        final newContact = Contact()
          ..name.first = contactData['name'] ?? ''
          ..phones = [Phone(contactData['number'] ?? '')];
          
        await FlutterContacts.openExternalInsert(newContact);

      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lang.t('chat_no_permission_to_save_contact')))
          );
        }
      }
    } catch (e) {
      log("CONTACT SAVE ERROR: $e");
      if(context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${lang.t('chat_error_saving_contact')}: $e'))
          );
      }
    }
  }

  Future<void> _findAndInteractWithUser(BuildContext context, {required bool openChat}) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final phoneNumber = contactData['number'];
    if (phoneNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_contact_no_number'))));
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (context.mounted) Navigator.of(context).pop();

      if (userQuery.docs.isNotEmpty) {
        final userDoc = userQuery.docs.first;
        final userData = userDoc.data();
        if (context.mounted) {
            final route = MaterialPageRoute(
              builder: (context) => openChat
                ? ChatScreenWrapper(
                    receiverID: userDoc.id,
                    receiverEmail: userData['displayName'] ?? 'User',
                  )
                : ContactInfoScreen(
                    userID: userDoc.id,
                    userEmail: userData['displayName'] ?? 'User',
                    photoUrl: userData['photoUrl'],
                ),
            );
            if(openChat) {
              Navigator.pushReplacement(context, route);
            } else {
              Navigator.push(context, route);
            }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lang.t('chat_user_not_on_jembe')))
          );
        }
      }
    } catch (e) {
      log("CONTACT SEARCH ERROR: $e");
      if (context.mounted) Navigator.of(context).pop(); 
      if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${lang.t('chat_error_finding_user')}: $e'))
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final theme = Theme.of(context);
    final contactName = contactData['name'] ?? lang.t('search_users_unknown_name');
    
    final backgroundColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 250,
        color: backgroundColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _findAndInteractWithUser(context, openChat: false),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Icon(Icons.person, color: theme.colorScheme.onSecondaryContainer, size: 30),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        contactName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, size: 20, color: textColor?.withOpacity(0.7)),
                      tooltip: lang.t('chat_copy_contact_number'),
                      onPressed: () {
                        final phoneNumber = contactData['number'] as String?;
                        if (phoneNumber != null && phoneNumber.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: phoneNumber));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(lang.t('chat_contact_number_copied')),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        } else {
                           ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(lang.t('chat_contact_no_number_in_contact')),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, thickness: 0.5, color: textColor?.withOpacity(0.2)),
            
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => _findAndInteractWithUser(context, openChat: true),
                      style: TextButton.styleFrom(
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
                      ),
                      child: Text(lang.t('chat_message_button')),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 0.5, color: textColor?.withOpacity(0.2)),
                  Expanded(
                    child: TextButton(
                      onPressed: () => _addContactToPhone(context),
                      style: TextButton.styleFrom(
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
                      ),
                      child: Text(lang.t('chat_add_contact_button')),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}


class DocumentBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final Color textColor;
  const DocumentBubble({super.key, required this.messageData, required this.textColor});

  @override
  State<DocumentBubble> createState() => _DocumentBubbleState();
}

class _DocumentBubbleState extends State<DocumentBubble> {
  bool _isDownloading = false;
  double? _downloadProgress;
  bool _localFileExists = false;
  String? _localPath;
  http.Client? _httpClient;

  @override
  void initState() {
    super.initState();
    _checkIfFileExists();
  }

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }

  Future<void> _checkIfFileExists() async {
    _localPath = widget.messageData[DatabaseHelper.columnLocalPath];
    if (_localPath != null && await File(_localPath!).exists()) {
      if (mounted) {
        setState(() {
          _localFileExists = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _localFileExists = false;
        });
      }
    }
  }
  
  void _openFile() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (_localPath != null) {
      final result = await OpenFilex.open(_localPath!);
      
      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lang.t('chat_error_no_app_to_open_file'))),
          );
        }
      }
    }
  }

  Future<void> _startDownload() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final onlineUrl = widget.messageData[DatabaseHelper.columnFileUrl];
    final messageId = widget.messageData[DatabaseHelper.columnId];

    if (onlineUrl == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_generic'))));
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      _httpClient = http.Client();
      final request = http.Request('GET', Uri.parse(onlineUrl));
      final response = await _httpClient!.send(request);

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = widget.messageData[DatabaseHelper.columnFileName] ?? path.basename(Uri.parse(onlineUrl).path);
        final tempFile = File(path.join(tempDir.path, fileName));
        
        final sink = tempFile.openWrite();
        final totalBytes = response.contentLength ?? -1;
        int receivedBytes = 0;

        await for (var chunk in response.stream) {
          if(!mounted || !_isDownloading) {
            await sink.close();
            _httpClient?.close();
            return;
          }
          receivedBytes += chunk.length;
          if (totalBytes != -1) {
            setState(() => _downloadProgress = receivedBytes / totalBytes);
          }
          sink.add(chunk);
        }
        await sink.close();

        final finalPath = await FileStorageService.instance.saveFileToPublicDirectory(
          tempFilePath: tempFile.path, 
          dirType: StorageDirectoryType.documents, 
          fileName: fileName
        );
        
        if (finalPath != null) {
          await DatabaseHelper.instance.updateMessageLocalPath(messageId, finalPath);

          syncService.notifyUIMessageUpdate(messageId);

          if (mounted) {
             setState(() {
               _localPath = finalPath;
               _localFileExists = true;
               _isDownloading = false;
               _downloadProgress = null;
             });
             _openFile();
          }
        } else {
          throw Exception(lang.t('chat_error_writing_document'));
        }

      } else {
        throw Exception(lang.t('chat_error_download_failed'));
      }
    } catch (e) {
      if (e is http.ClientException) {
        debugPrint("Gukurura dosiye byahagaritswe.");
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lang.t('chat_error_generic'))));
      }
      if(mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = null;
        });
      }
    } finally {
      _httpClient?.close();
      _httpClient = null;
    }
  }
  
  void _handleTap() {
    if (_localFileExists) {
      _openFile();
    } else {
      if (!_isDownloading) {
         _startDownload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final fileName = widget.messageData[DatabaseHelper.columnFileName] ?? lang.t('chat_reply_document');
    
    return InkWell(
      onTap: _handleTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        width: 250,
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _localFileExists ? Icons.insert_drive_file_outlined : Icons.download_for_offline_outlined,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                if (_isDownloading)
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      value: _downloadProgress,
                      strokeWidth: 3,
                      color: Colors.white,
                      backgroundColor: Colors.white.withOpacity(0.3),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fileName,
                style: TextStyle(color: widget.textColor, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------------------
// DAME GAME WIDGET & PIECES
// -------------------------------------------------------------------------------------

class DamePieceWidget extends StatelessWidget {
  final DamePiece piece;
  final double squareSize;
  final bool isSelected;
  final bool mustPlay;
  final VoidCallback? onTap;

  const DamePieceWidget({
    required Key key,
    required this.piece,
    required this.squareSize,
    this.isSelected = false,
    this.mustPlay = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isPlayer1 = piece.player == 1;

    final lightPiece = BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: mustPlay ? Colors.red.shade900 : (isSelected ? Colors.yellowAccent : Colors.black54),
        width: isSelected || mustPlay ? 3.5 : 2,
      ),
      gradient: const RadialGradient(
        colors: [Color(0xFFF5DEB3), Color(0xFFDEB887)], // Wheat -> BurlyWood
        center: Alignment(-0.3, -0.3),
        radius: 0.8,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.4),
          blurRadius: 3,
          offset: const Offset(2, 2),
        )
      ]
    );

    final darkPiece = BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: mustPlay ? Colors.red.shade900 : (isSelected ? Colors.yellowAccent : Colors.black54),
        width: isSelected || mustPlay ? 3.5 : 2,
      ),
       gradient: const RadialGradient(
        colors: [Color(0xFF8B5A2B), Color(0xFF654321)], // Dark Tan -> Dark Brown
        center: Alignment(-0.3, -0.3),
        radius: 0.8,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.4),
          blurRadius: 3,
          offset: const Offset(2, 2),
        )
      ]
    );

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: squareSize,
        height: squareSize,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Container(
            decoration: isPlayer1 ? lightPiece : darkPiece,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (piece.type == DamePieceType.king)
                  Icon(
                    Icons.star,
                    color: isPlayer1 ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.8),
                    size: squareSize * 0.6,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DameGameWidget extends StatefulWidget {
  final String chatRoomID;
  final Map<String, dynamic> gameData;
  final String? opponentDisplayName;
  
  final bool isInvitation;
  final bool isWaiting;
  final VoidCallback? onSendInvitation;
  final VoidCallback? onCancel;
  final VoidCallback? onGameStopped; 

  const DameGameWidget({
    super.key,
    required this.chatRoomID,
    required this.gameData,
    this.opponentDisplayName,
    this.isInvitation = false,
    this.isWaiting = false,
    this.onSendInvitation,
    this.onCancel,
    this.onGameStopped, 
  });

  @override
  State<DameGameWidget> createState() => _DameGameWidgetState();
}

class _DameGameWidgetState extends State<DameGameWidget> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late DameGameLogic _gameLogic;
  bool _isPlayer1 = true;
  DameMove? _lastMove;
  bool _isSubmittingMove = false;

  late AudioPlayer _movePlayer, _capturePlayer, _promotePlayer, _winPlayer, _losePlayer;

  late AnimationController _animationController;
  late Animation<Offset> _animation;
  DamePiece? _movingPiece;
  Offset? _movingPieceFromOffset;
  bool _isAnimating = false;
  DameMove? _moveForAnimation;

  bool _hasShownGameEndDialog = false;

  @override
  void initState() {
    super.initState();
    _initializeGame();
    _checkForGameEnd();

    _movePlayer = AudioPlayer(); _capturePlayer = AudioPlayer(); _promotePlayer = AudioPlayer();
    _winPlayer = AudioPlayer(); _losePlayer = AudioPlayer();
    _loadSounds();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _processMoveAfterAnimation();
      }
    });
  }

  Future<void> _loadSounds() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    try {
      await _movePlayer.setAsset('assets/audio/move.mp3');
      await _capturePlayer.setAsset('assets/audio/capture.mp3');
      await _promotePlayer.setAsset('assets/audio/promote.mp3');
      await _winPlayer.setAsset('assets/audio/win.mp3');
      await _losePlayer.setAsset('assets/audio/lose.mp3');
    } catch (e) {
      debugPrint("${lang.t('dame_sound_error')}: $e");
    }
  }

  void _playSound(AudioPlayer player) {
    if (player.playing) {
      player.stop();
    }
    player.seek(Duration.zero);
    player.play();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _movePlayer.dispose(); _capturePlayer.dispose(); _promotePlayer.dispose();
    _winPlayer.dispose(); _losePlayer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DameGameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.gameData != oldWidget.gameData) {
      if (mounted) setState(() {
        _isSubmittingMove = false;
        _initializeGame();
      });
      if (widget.gameData['status'] == 'finished') {
        _checkForGameEnd();
      }
    }
  }

  void _initializeGame() {
    if (!widget.isInvitation) {
      _isPlayer1 = widget.gameData['player1Id'] == _auth.currentUser!.uid;
    }
    _gameLogic = DameGameLogic(myPlayerNumber: _isPlayer1 ? 1 : 2, boardSize: 10);
    final boardData = widget.gameData['boardState'] ?? widget.gameData['board']; 
    if(boardData != null) {
        _gameLogic.initializeBoard(boardData);
    }
  }

  void _checkForGameEnd() {
    if (_hasShownGameEndDialog) return;

    if (widget.isInvitation || widget.gameData['status'] != 'finished') return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

      _hasShownGameEndDialog = true;

      final lang = Provider.of<LanguageProvider>(context, listen: false);
      final winnerId = widget.gameData['winnerId'];
      final reason = widget.gameData['endReason'] ?? lang.t('dame_game_finished');
      final amIWinner = winnerId == _auth.currentUser!.uid;
      
      String dialogTitle;
      
      if (winnerId == null) {
        dialogTitle = lang.t('dame_game_stopped');
      } else {
        if (amIWinner) {
          dialogTitle = lang.t('dame_you_won');
          _playSound(_winPlayer);
        } else {
          dialogTitle = lang.t('dame_you_lost');
          _playSound(_losePlayer);
        }
      }
      
      showDialog(
        context: context,
        barrierDismissible: false, // Force user to tap OK
        builder: (context) => AlertDialog(
          title: Text(dialogTitle),
          content: Text(reason),
          actions: [
            TextButton(
              child: Text(lang.t('btn_ok')),
              onPressed: () {
                Navigator.of(context).pop();
                _hasShownGameEndDialog = false;
                _resetGameForNewMatch(); 
              },
            ),
          ],
        ),
      );
    });
  }

  bool get _isMyTurn => !_isSubmittingMove && !_isAnimating && !widget.isInvitation && widget.gameData['turn'] == _auth.currentUser!.uid && widget.gameData['status'] == 'active';

  void _handleTap(int tappedRow, int tappedCol) {
    if (!_isMyTurn) return;

    int actualRow = _isPlayer1 ? tappedRow : 9 - tappedRow;
    int actualCol = _isPlayer1 ? tappedCol : 9 - tappedCol;

    final move = _gameLogic.getMoveTo(actualRow, actualCol);
    
    if (move != null) {
      if(mounted) setState(() {
        _moveForAnimation = move;
        _movingPiece = _gameLogic.board[move.fromRow][move.fromCol]!.copy();
        
        final screenWidth = MediaQuery.of(context).size.width;
        final boardMargin = 8.0;
        final boardSize = screenWidth - (boardMargin * 2);
        final squareSize = boardSize / 10;
        
        final visualFromRow = _isPlayer1 ? move.fromRow : 9 - move.fromRow;
        final visualFromCol = _isPlayer1 ? move.fromCol : 9 - move.fromCol;
        final visualToRow = _isPlayer1 ? move.toRow : 9 - move.toRow;
        final visualToCol = _isPlayer1 ? move.toCol : 9 - move.toCol;
        
        _movingPieceFromOffset = Offset(visualFromCol * squareSize, visualFromRow * squareSize);
        final toOffset = Offset(visualToCol * squareSize, visualToRow * squareSize);
        
        _animation = Tween<Offset>(begin: Offset.zero, end: toOffset - _movingPieceFromOffset!).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeInOut)
        );
        
        _isAnimating = true;
        _animationController.forward(from: 0.0);
      });

    } else {
       _gameLogic.handleTap(actualRow, actualCol);
       if(mounted) setState(() {});
    }
  }

  void _processMoveAfterAnimation() {
    if (_moveForAnimation == null) return;
    
    final move = _moveForAnimation!;
    int actualRow = move.toRow;
    int actualCol = move.toCol;
    
    final wasCapture = move.isCapture;
    final piece = _gameLogic.board[move.fromRow][move.fromCol]!;

    final bool willBecomeKing = (piece.type == DamePieceType.man) && 
                             ((_gameLogic.myPlayerNumber == 1 && move.toRow == 0) || 
                              (_gameLogic.myPlayerNumber == 2 && move.toRow == 9));

    bool turnEnded = _gameLogic.handleTap(actualRow, actualCol);

    if (willBecomeKing) {
      _playSound(_promotePlayer);
    } else if (wasCapture) {
      _playSound(_capturePlayer);
    } else {
      _playSound(_movePlayer);
    }
    
    if(mounted) setState(() {
      _lastMove = move;
      _isAnimating = false;
      _movingPiece = null;
      _moveForAnimation = null;
    });

    if (turnEnded) {
      _endTurn();
    }
  }

  Future<void> _endTurn() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if(mounted) setState(() { _isSubmittingMove = true; });
    final newBoard = _gameLogic.board;
    final nextPlayerId = widget.gameData['turn'] == widget.gameData['player1Id'] ? widget.gameData['player2Id'] : widget.gameData['player1Id'];
    final int nextPlayerNumber = (nextPlayerId == widget.gameData['player1Id']) ? 1 : 2;

    DameGameLogic tempLogic = DameGameLogic(myPlayerNumber: nextPlayerNumber, boardSize: 10);
    final List<dynamic> boardAsListOfMaps = newBoard.map((row) => row.map((piece) => piece == null ? null : {'player': piece.player, 'type': piece.type.name}).toList()).toList();
    tempLogic.initializeBoard(boardAsListOfMaps);
    if (!tempLogic.hasAnyValidMoves(nextPlayerNumber)) {
      await _declareWinner(_auth.currentUser!.uid, lang.t('dame_win_reason_no_moves'));
    } else {
      await _updateGameInFirestore(newBoard);
    }
  }

  Future<void> _handleResign() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (widget.isInvitation) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(lang.t('dame_resign_title')),
        content: Text(lang.t('dame_resign_body')),
        actions: <Widget>[
          TextButton( child: Text(lang.t('dialog_no')), onPressed: () => Navigator.of(context).pop(false), ),
          TextButton( child: Text(lang.t('dame_resign_confirm')), onPressed: () => Navigator.of(context).pop(true), style: TextButton.styleFrom(foregroundColor: Colors.red), ),
        ],
      ),
    );
    if (confirm == true) {
      final opponentId = _isPlayer1 ? widget.gameData['player2Id'] : widget.gameData['player1Id'];
      await _declareWinner(opponentId, lang.t('dame_win_reason_resign'));
    }
  }
  
  Future<void> _resetGameForNewMatch() async {
    // Only reset if it's not already active (prevent double reset if both click fast)
    // Though Firestore handles writes well, checking state is good practice.
    if (widget.gameData['status'] == 'active') return;

    final initialBoard = List.generate(10, (row) {
      return List.generate(10, (col) {
        if ((row + col) % 2 != 0) {
          if (row < 4) return {'player': 2, 'type': 'man'};
          if (row > 5) return {'player': 1, 'type': 'man'};
        }
        return null;
      });
    });
    final Map<String, dynamic> boardForFirestore = {};
    for (int i = 0; i < initialBoard.length; i++) {
      boardForFirestore[i.toString()] = initialBoard[i];
    }
    
    // Determine starter (winner starts or P1)
    final starterId = widget.gameData['winnerId'] ?? widget.gameData['player1Id'];

    // Update firestore to ACTIVE
    await _firestore.collection('games').doc(widget.chatRoomID).update({
      'boardState': boardForFirestore, 
      'status': 'active',
      'turn': starterId,
      'winnerId': null, 
      'endReason': null,
    });
  }

  Future<void> _handleStopGame() async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    if (widget.isInvitation) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(lang.t('dame_stop_game_title')),
        content: Text(lang.t('dame_stop_game_body')),
        actions: <Widget>[
          TextButton( child: Text(lang.t('dialog_no')), onPressed: () => Navigator.of(context).pop(false), ),
          TextButton( child: Text(lang.t('dialog_yes')), onPressed: () => Navigator.of(context).pop(true), style: TextButton.styleFrom(foregroundColor: Colors.red), ),
        ],
      ),
    );
    if (confirm == true) {
      widget.onGameStopped?.call();
      await _firestore.collection('games').doc(widget.chatRoomID).delete();
    }
  }

  Future<void> _declareWinner(String winnerId, String reason) async {
    if (widget.isInvitation) return;

    // Increment Score
    int p1Score = widget.gameData['player1Score'] ?? 0;
    int p2Score = widget.gameData['player2Score'] ?? 0;

    if (winnerId == widget.gameData['player1Id']) {
      p1Score++;
    } else if (winnerId == widget.gameData['player2Id']) {
      p2Score++;
    }

    await _firestore.collection('games').doc(widget.chatRoomID).update({
      'status': 'finished', 
      'winnerId': winnerId, 
      'endReason': reason,
      'player1Score': p1Score,
      'player2Score': p2Score,
    });
  }

  Future<void> _updateGameInFirestore(List<List<DamePiece?>> newBoard) async {
    if (widget.isInvitation) return;
    List<List<Map<String, dynamic>?>> boardAsLists = newBoard.map((row) => row.map((piece) => piece == null ? null : {'player': piece.player, 'type': piece.type.name}).toList()).toList();
    final Map<String, dynamic> boardForFirestore = {};
    for (int i = 0; i < boardAsLists.length; i++) {
      boardForFirestore[i.toString()] = boardAsLists[i];
    }
    String nextPlayer = widget.gameData['turn'] == widget.gameData['player1Id'] ? widget.gameData['player2Id'] : widget.gameData['player1Id'];
    await _firestore.collection('games').doc(widget.chatRoomID).update({
      'boardState': boardForFirestore, 'turn': nextPlayer,
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    String currentTurnPlayerId = widget.gameData['turn'] ?? '';
    String opponentName = widget.opponentDisplayName ?? lang.t('dame_opponent_default_name');
    bool isGameActive = widget.gameData['status'] == 'active';
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: Column(children: [
        if (widget.isInvitation)
          _buildInvitationHeader()
        else if (isGameActive)
          _buildActiveGameHeader(currentTurnPlayerId, opponentName)
        else
          const SizedBox(height: 48),
            
        AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2)),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final squareSize = constraints.maxWidth / 10;
                return Stack(
                  children: [
                    for (int i = 0; i < 100; i++) ...[
                      Positioned(
                        top: (i ~/ 10) * squareSize,
                        left: (i % 10) * squareSize,
                        child: Container(
                          width: squareSize,
                          height: squareSize,
                          color: ((i ~/ 10) + (i % 10)) % 2 == 0 ? const Color(0xFFD2B48C) : const Color(0xFF8B4513),
                        ),
                      ),
                    ],
                    ..._buildPossibleMoveIndicators(squareSize),
                    ..._buildDamePieces(squareSize),
                    if (_isAnimating && _movingPiece != null && _movingPieceFromOffset != null)
                      Positioned(
                        top: _movingPieceFromOffset!.dy,
                        left: _movingPieceFromOffset!.dx,
                        child: AnimatedBuilder(
                          animation: _animation,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: _animation.value,
                              child: child,
                            );
                          },
                          child: DamePieceWidget(
                            key: const ValueKey('moving_piece'),
                            piece: _movingPiece!,
                            squareSize: squareSize,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        
        if (widget.isInvitation)
          _buildInvitationButtons()
        else if (isGameActive)
          _buildActiveGameFooter(),
      ]),
    );
  }
  
  List<Widget> _buildDamePieces(double squareSize) {
    final List<Widget> pieces = [];
    if (_gameLogic.board.length != 10) return pieces; 

    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 10; c++) {
        if (_isAnimating && r == _moveForAnimation?.fromRow && c == _moveForAnimation?.fromCol) {
          continue;
        }

        final piece = _gameLogic.board[r][c];
        if (piece != null) {
          final visualRow = _isPlayer1 || widget.isInvitation ? r : 9 - r;
          final visualCol = _isPlayer1 || widget.isInvitation ? c : 9 - c;
          bool isSelected = (_gameLogic.selectedRow == r && _gameLogic.selectedCol == c);
          bool mustPlay = _gameLogic.forcedCaptureMoves.any((m) => m.fromRow == r && m.fromCol == c) && !_gameLogic.isMultiJump;
          
          pieces.add(
            Positioned(
              top: visualRow * squareSize,
              left: visualCol * squareSize,
              child: DamePieceWidget(
                key: ValueKey('piece_${piece.player}_${r}_$c'), 
                piece: piece,
                squareSize: squareSize,
                isSelected: isSelected,
                mustPlay: mustPlay,
                onTap: () => _handleTap(visualRow, visualCol),
              ),
            ),
          );
        }
      }
    }
    return pieces;
  }

  List<Widget> _buildPossibleMoveIndicators(double squareSize) {
    final List<Widget> indicators = [];
    if (_isAnimating) return indicators;
    for (final move in _gameLogic.possibleMoves) {
      final visualRow = _isPlayer1 || widget.isInvitation ? move.toRow : 9 - move.toRow;
      final visualCol = _isPlayer1 || widget.isInvitation ? move.toCol : 9 - move.toCol;
      indicators.add( Positioned( top: visualRow * squareSize, left: visualCol * squareSize, child: GestureDetector( onTap: () => _handleTap(visualRow, visualCol), child: SizedBox( width: squareSize, height: squareSize, child: Center( child: Container( width: squareSize * 0.4, height: squareSize * 0.4, decoration: BoxDecoration( color: Colors.green.withOpacity(0.5), shape: BoxShape.circle, ), ), ), ), ), ), );
    }
    return indicators;
  }

  Widget _buildActiveGameHeader(String currentTurnPlayerId, String opponentName) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final bool isMyTurn = currentTurnPlayerId == _auth.currentUser?.uid;
    
    int score1 = widget.gameData['player1Score'] ?? 0;
    int score2 = widget.gameData['player2Score'] ?? 0;

    String displayText;
    if (isMyTurn) { 
      displayText = lang.t('dame_your_turn'); 
    } else { 
      displayText = lang.t('dame_opponent_turn').replaceAll('{opponentName}', opponentName); 
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "$score1 - $score2",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text( 
            displayText, 
            style: TextStyle( 
              fontSize: 16, 
              fontWeight: FontWeight.bold, 
              color: isMyTurn ? Colors.green.shade700 : Colors.orange.shade800
            ), 
            overflow: TextOverflow.ellipsis, 
          ),
        ],
      ),
    );
  }
  
  Widget _buildActiveGameFooter() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          OutlinedButton.icon(
            onPressed: _handleStopGame,
            icon: const Icon(Icons.close),
            label: Text(lang.t('dame_stop_game_button')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade800,
              side: BorderSide(color: Colors.grey.shade400),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _handleResign,
            icon: const Icon(Icons.flag),
            label: Text(lang.t('dame_resign_button')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvitationHeader() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    return SizedBox( height: 48, child: widget.isWaiting 
      ? Row( mainAxisAlignment: MainAxisAlignment.center, children: [ const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), Text(lang.t('dame_invitation_sent'), style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic)), ], ) 
      : Center( child: Text(lang.t('dame_send_invitation_header'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), ), 
    );
  }

  Widget _buildInvitationButtons() {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    return Padding( 
      padding: const EdgeInsets.only(top: 10, bottom: 10), 
      child: Row( 
        mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
        children: [ 
          ElevatedButton.icon( 
            onPressed: widget.onCancel, 
            icon: const Icon(Icons.close), 
            label: Text(widget.isWaiting ? lang.t('dame_cancel_invitation_button') : lang.t('dame_cancel_button')), 
            style: ElevatedButton.styleFrom( backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)) ), 
          ), 
          if (!widget.isWaiting) 
            ElevatedButton.icon( 
              onPressed: widget.onSendInvitation, 
              icon: const Icon(Icons.send), 
              label: Text(lang.t('dame_send_invitation_button')), 
              style: ElevatedButton.styleFrom( backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)) ), 
            ), 
        ], 
      ), 
    );
  }
}