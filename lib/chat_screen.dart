// lib/chat_screen.dart (YAKOSOWE BURUNDU KURI PHOTO DOWNLOAD)
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
import 'package:jembe_talk/dame_game_widget.dart';
import 'package:jembe_talk/services/firebase_service.dart';

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
  final ScrollController _scrollController = ScrollController();
  
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
  List<dynamic> _chatItems = [];

  StreamSubscription? _uploadProgressSubscription;

  // States for photo editing
  final TextEditingController _captionController = TextEditingController();
  Uint8List? _selectedImageData;

  VideoEditorController? _videoEditorController;
  File? _selectedVideoFile;
  bool _isProcessingVideo = false;
  double _videoProcessingProgress = 0.0;
  
  bool _isGameHardStopped = false;

  StreamSubscription? _uiUpdateSubscription;
  
  Stream<DatabaseEvent>? _presenceStream;
  Stream<DatabaseEvent>? _activityStream;
  DatabaseReference? _myActivityStatusRef;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentUserStream = _firestore.collection('users').doc(_auth.currentUser!.uid).snapshots();
    _receiverUserStream = _firestore.collection('users').doc(widget.receiverID).snapshots();
    
    _presenceStream = FirebaseDatabase.instance.ref('status/${widget.receiverID}').onValue.asBroadcastStream();
    final chatRoomID = _getChatRoomID();
    _myActivityStatusRef = FirebaseDatabase.instance.ref('activity/$chatRoomID/${_auth.currentUser!.uid}');
    _activityStream = FirebaseDatabase.instance.ref('activity/$chatRoomID/${widget.receiverID}').onValue.asBroadcastStream();
    
    _loadInitialData();

    _uiUpdateSubscription = syncService.uiMessageUpdateStream.listen((updatedMessageId) {
      final index = _messages.indexWhere((msg) => msg['id'] == updatedMessageId);
      if (index != -1 && mounted) {
        log("UI update received from FCM for message: $updatedMessageId. Reloading messages.");
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
  
  void _updateTypingStatus() {
    _typingTimer?.cancel();
    if (_messageController.text.trim().isNotEmpty) {
      _myActivityStatusRef?.set("typing");
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _myActivityStatusRef?.set("idle");
      });
    } else {
      _myActivityStatusRef?.set("idle");
    }
  }

  Future<void> _loadInitialData() async {
    await _loadInitialMessages();
    _listenForGameUpdates();
    _listenForFirebaseMessages();
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Umukino Wahagaritswe"),
          content: const Text("Mugenzi wawe yahagaritse umukino."),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
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
          debugPrint("Umukino ushaje wasibwe kuko umukoresha yamaze igihe adahari.");
        }
      } catch (e) {
        debugPrint("Habaye ikosa mu gusiba umukino ushaje: $e");
      }
    }
    _timeWhenPaused = null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadInitialMessages({bool forceReload = false}) async {
    await _loadWallpapers();
    final chatRoomID = _getChatRoomID();
    final localMessages = await DatabaseHelper.instance.getMessagesForChatRoom(chatRoomID);
    if (mounted) {
      setState(() {
        _messages = List.from(localMessages);
        _chatItems = _getChatItemsWithSeparators(_messages);
        _isLoading = false;
      });

      _scrollToBottom();
      
      _updateReceivedMessagesStatusToSeen();
    }
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
    if (mounted) context.read<AudioPlayerService>().stop();
    _uploadProgressSubscription?.cancel();
    _uiUpdateSubscription?.cancel();
    
    _typingTimer?.cancel();
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
      return timestampA.compareTo(timestampB);
    });
    DateTime? lastDate;
    for (var message in messages) {
      final messageTimestamp = message['timestamp'];
      final DateTime messageDate = DateTime.fromMillisecondsSinceEpoch(messageTimestamp);
      if (lastDate == null || !isSameDay(messageDate, lastDate)) {
        items.add(_formatDateSeparator(messageDate.millisecondsSinceEpoch));
        lastDate = messageDate;
      }
      items.add(message);
    }
    return items;
  }

  bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateSeparator(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDay = DateTime(date.year, date.month, date.day);
    if (messageDay == today) return "Uyumusi";
    if (messageDay == yesterday) return "Ejo";
    return DateFormat.yMMMMd('fr_FR').format(date);
  }
  
  void _listenForFirebaseMessages() async {
    final chatRoomID = _getChatRoomID();
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _messageSubscription?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final clearTimestamp = prefs.getInt('clear_timestamp_$chatRoomID') ?? 0;

    var query = _firestore
        .collection('chat_rooms')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp');

    if (_messages.isNotEmpty) {
      final lastLocalTimestamp = _messages.last['timestamp'];
      final effectiveTimestamp = clearTimestamp > lastLocalTimestamp ? clearTimestamp : lastLocalTimestamp;
      query = query.where('timestamp', isGreaterThan: effectiveTimestamp);
    } else {
      query = query.where('timestamp', isGreaterThan: clearTimestamp);
    }

    _messageSubscription = query.snapshots().listen((snapshot) async {
      if (!mounted) return;
      if (snapshot.docChanges.isEmpty) return;

      List<DocumentReference> messagesToMarkAsSeen = [];
      bool shouldReload = false;

      for (var change in snapshot.docChanges) {
        final doc = change.doc;
        final serverMessage = doc.data() as Map<String, dynamic>;
        
        if (serverMessage['timestamp'] is Timestamp) {
            serverMessage['timestamp'] = (serverMessage['timestamp'] as Timestamp).millisecondsSinceEpoch;
        }

        await DatabaseHelper.instance.saveMessage(serverMessage);

        shouldReload = true;

        if (serverMessage['receiverID'] == currentUser.uid && serverMessage['status'] != 'seen') {
          messagesToMarkAsSeen.add(doc.reference);
        }
      }

      if (messagesToMarkAsSeen.isNotEmpty) {
        WriteBatch batch = _firestore.batch();
        for (var ref in messagesToMarkAsSeen) {
          batch.update(ref, {'status': 'seen'});
        }
        await batch.commit().catchError((e) {
          debugPrint("Error batch updating status to seen: $e");
        });
      }
      
      if(shouldReload) {
        _loadInitialMessages(forceReload: true);
      }
    });
  }

  void _addOptimisticMessage(Map<String, dynamic> messageData) {
    setState(() {
      _messages.add(messageData);
      _chatItems = _getChatItemsWithSeparators(_messages);
    });
    _scrollToBottom();
  }

  void _sendMessage({String? text, String messageType = 'text'}) async {
    _typingTimer?.cancel();
    _myActivityStatusRef?.set("idle");
    
    if (messageType == 'text') {
      if (_messageController.text.trim().isEmpty) return;
      text = _messageController.text.trim();
      _messageController.clear();
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
    };
    await DatabaseHelper.instance.saveMessage(messageData);
    _addOptimisticMessage(messageData);
    syncService.triggerSync();
  }

  void _handleDeclineInvitation() {
    _sendMessage(
      messageType: 'dame_invitation_declined',
      text: "Nanse ubutumire bwawe.",
    );
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
        debugPrint("Ikosa ryo guhindura status mo 'seen' (ku basanzwe): $e");
      });
    }
  }

  void _sendGameInvitation() {
    setState(() => _isWaitingForGameAcceptance = true);
    _sendMessage(messageType: 'dame_invitation', text: "Wokwemera dukine Dame?");
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
    
    await mediaUploadService.sendMediaMessage(
      chatRoomID: _getChatRoomID(),
      receiverID: widget.receiverID,
      localPath: permanentPath,
      messageType: 'image',
      text: _captionController.text.trim(),
      fileName: path.basename(permanentPath),
    );

    if (mounted) {
      setState(() {
        _selectedImageData = null;
        _captionController.clear();
      });
      _loadInitialMessages(forceReload: true);
    }
  }

  void _cancelPhotoSelection() {
    setState(() {
      _selectedImageData = null;
      _captionController.clear();
    });
  }

  Future<void> _processAndAddOptimisticVideo() async {
    if (_videoEditorController == null || _selectedVideoFile == null) return;
    setState(() => _isProcessingVideo = true);
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
        if (!success) throw Exception("Gutunganya video byanze.");
        videoPathToSave = outputPath;
      }
      final permanentPath = await mediaUploadService.saveFilePermanently(videoPathToSave);
      final thumbnailPath = await thumbnailFuture;

      await mediaUploadService.sendMediaMessage(
        chatRoomID: _getChatRoomID(),
        receiverID: widget.receiverID,
        localPath: permanentPath,
        messageType: 'video',
        thumbnailLocalPath: thumbnailPath,
        fileName: path.basename(permanentPath),
      );
      
      _loadInitialMessages(forceReload: true);
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ikosa: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingVideo = false;
          _videoProcessingProgress = 0.0;
          _cancelVideoSelection();
        });
      }
    }
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
    final int invitationTimestamp = invitationMessage['timestamp'];
    final now = DateTime.now().millisecondsSinceEpoch;
    const expirationLimit = Duration(minutes: 5);
    if ((now - invitationTimestamp) > expirationLimit.inMilliseconds) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ntushobora kwemera ubu butumire. Bwarasaje.")),
      );
      return;
    }

    final chatRoomID = _getChatRoomID();
    
    final messageIdToDelete = invitationMessage['id'];
    if (messageIdToDelete != null) {
      _firestore.collection('chat_rooms').doc(chatRoomID).collection('messages').doc(messageIdToDelete).delete();
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
    
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _optimisticGameData = null;
        });
      }
    });
  }

  Future<void> _toggleBlockUser(bool isCurrentlyBlocked) async {
    final currentUserRef = _firestore.collection('users').doc(_auth.currentUser!.uid);
    try {
      if (isCurrentlyBlocked) {
        await currentUserRef.update({
          'blockedUsers': FieldValue.arrayRemove([widget.receiverID])
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uyu muntu yafunguwe.")));
      } else {
        await currentUserRef.update({
          'blockedUsers': FieldValue.arrayUnion([widget.receiverID])
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uyu muntu yafunzwe.")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Habaye ikosa: $e")));
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Futa ibiganiro"),
        content: const Text("Wemeye ko ibiganiro byose biri hano bisibwa burundu?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Oya"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Ego, Futa"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final chatRoomID = _getChatRoomID();
      
      final lastMessageTimestamp = _messages.isNotEmpty ? _messages.last['timestamp'] as int : DateTime.now().millisecondsSinceEpoch;

      await DatabaseHelper.instance.clearChat(chatRoomID);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('clear_timestamp_$chatRoomID', lastMessageTimestamp);

      if (mounted) {
        setState(() {
          _messages.clear();
          _chatItems.clear();
        });
        _listenForFirebaseMessages();
      }
    }
  }

  void _toggleEmojiPicker() async {
    if (_isGameVisible()) return;
  
    if (_isEmojiPickerVisible) {
      Navigator.of(context).pop();
    } else {
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uyu mukino uzoboneka vuba."), duration: Duration(seconds: 2),),);
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'],
    );
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final permanentPath = await mediaUploadService.saveFilePermanently(file.path!);
      await mediaUploadService.sendMediaMessage(
        chatRoomID: _getChatRoomID(),
        receiverID: widget.receiverID,
        localPath: permanentPath,
        messageType: 'document',
        fileName: file.name,
      );
      _loadInitialMessages(forceReload: true);
    }
  }

  Future<void> _pickAudio() async {
    _focusNode.unfocus();
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final permanentPath = await mediaUploadService.saveFilePermanently(file.path!);
      await mediaUploadService.sendMediaMessage(
        chatRoomID: _getChatRoomID(),
        receiverID: widget.receiverID,
        localPath: permanentPath,
        messageType: 'audio_file',
        fileName: file.name,
      );
      _loadInitialMessages(forceReload: true);
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

  Future<void> _showAnimatedWallpaperDialog() async {
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
            title: const Text("Ifoto y'Inyuma"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Hindura ifoto'),
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
                    title: const Text('Futa ifoto', style: TextStyle(color: Colors.redAccent)),
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
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final lastSeenDay = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);

    if (lastSeenDay == today) {
      return "Aheruka kumurongo saa ${DateFormat.Hm().format(lastSeen)}";
    } else if (lastSeenDay == yesterday) {
      return "Aheruka kumurongo ejo saa ${DateFormat.Hm().format(lastSeen)}";
    } else {
      return "Aheruka kumurongo kuwa ${DateFormat.yMd().format(lastSeen)}";
    }
  }

  @override
  Widget build(BuildContext context) {
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
        if (_selectedImageData != null) {
          _cancelPhotoSelection();
        } else if (_selectedVideoFile != null) {
          _cancelVideoSelection();
        } else if (_isPreparingInvitation) {
          setState(() {
            _isPreparingInvitation = false;
            _isWaitingForGameAcceptance = false;
          });
        } else if (_isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedMessages.clear();
          });
        } else {
          _navigateBackToHome();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        extendBodyBehindAppBar: true,
        appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
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
    
    return Container(
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
          ? const Center(child: Text("Nta butumwa buriho."))
          : ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
        itemCount: _chatItems.length,
        itemBuilder: (context, index) {
          final item = _chatItems[index];
          if (item is String) {
            return DateSeparator(key: ValueKey(item), date: item);
          } else {
            final messageData = item as Map<String, dynamic>;
            final messageId = messageData['id'] ?? 'temp_${messageData['timestamp']}';
            final progress = _uploadProgress[messageId];
            return MessageBubble(
              key: ValueKey(messageId),
              messageData: messageData,
              isMe: messageData['senderID'] == _auth.currentUser!.uid,
              isSelected: _selectedMessages.contains(messageId),
              uploadProgress: progress,
              onAcceptInvitation: () => _createGameInFirestore(messageData),
              onDeclineInvitation: _handleDeclineInvitation,
            );
          }
        },
      ),
    );
  }
  
  Widget _buildMessageComposerContainer({required bool isGameVisible}) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _currentUserStream,
      builder: (context, currentUserSnapshot) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _receiverUserStream,
          builder: (context, receiverSnapshot) {
            if (!currentUserSnapshot.hasData || !receiverSnapshot.hasData) {
              return _buildMessageComposer(isGameVisible: isGameVisible, hintText: "Message...", isReadOnly: true);
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
                child: const Text(
                  "Ntushobora kwandikira uyu muntu kuko yagufunze.",
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
                child: const Text(
                  "Ntushobora kwandikira uyu muntu kuko wamufunze. Mufungure kugira ngo mwongere muganire.",
                  textAlign: TextAlign.center,
                ),
              );
            }
            
            return _buildMessageComposer(isGameVisible: isGameVisible);
          },
        );
      },
    );
  }

  Widget _buildMessageComposer({required bool isGameVisible, String? hintText, bool? isReadOnly}) {
    if (_selectedImageData != null) {
      return _buildPhotoPreviewComposer();
    }
    if (_selectedVideoFile != null) {
      return _buildVideoEditorComposer();
    }
    
    return StreamBuilder<DatabaseEvent>(
      stream: _presenceStream,
      builder: (context, snapshot) {
        String finalHintText = hintText ?? "Message...";
        if (hintText == null) {
          if (isGameVisible) {
            finalHintText = "Koresha ijwi mu mukino...";
          } else if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            try {
              final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
              final state = data['state'];
              if (state == 'offline') {
                final timestamp = data['last_changed'] as int;
                finalHintText = _formatLastSeen(timestamp);
              }
            } catch(e) {
              finalHintText = "Message...";
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
                          onPressed: finalIsReadOnly ? null : _showAnimatedDialogMenu
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
                    ? FloatingActionButton(key: const ValueKey('send_button'), onPressed: () => _sendMessage(messageType: 'text'), backgroundColor: theme.colorScheme.primary, elevation: 2, child: Icon(Icons.send, color: theme.colorScheme.onPrimary),)
                    : SocialMediaRecorder(
                        key: const ValueKey('mic_recorder'),
                        sendRequestFunction: (File soundFile, String duration) async {
                          _myActivityStatusRef?.set("idle");
                          int durationInSeconds = 0;
                          try {
                            final parts = duration.split(':');
                            if (parts.length == 2) {
                              durationInSeconds = int.parse(parts[0]) * 60 + int.parse(parts[1]);
                            }
                          } catch (e) {
                            debugPrint("Error parsing duration: $e");
                          }
                          final permanentPath = await mediaUploadService.saveFilePermanently(soundFile.path);
                          await mediaUploadService.sendMediaMessage(
                            chatRoomID: _getChatRoomID(),
                            receiverID: widget.receiverID,
                            localPath: permanentPath,
                            messageType: 'voice_note',
                            duration: durationInSeconds,
                            fileName: path.basename(permanentPath)
                          );
                          _loadInitialMessages(forceReload: true);
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
                          decoration: const InputDecoration(
                            hintText: "Ongerako amajambo...",
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12),
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
                    label: const Text("OHEREZA"),
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
                            "Uburebure: ${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}",
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
                    label: const Text("HAGARIKA"),
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
                    onPressed: _processAndAddOptimisticVideo,
                    icon: const Icon(Icons.check),
                    label: const Text("KOMEZA"),
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
    _focusNode.unfocus();
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: '', transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => Container(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
        return Transform.translate(offset: Offset(0, 150 * (1 - curvedAnimation.value)), child: Transform.rotate(angle: (1 - curvedAnimation.value) * -0.1, child: Opacity(opacity: curvedAnimation.value, child: AlertDialog(backgroundColor: Colors.transparent, elevation: 0, contentPadding: EdgeInsets.zero, content: _buildAttachmentContent(),),),),);
      },
    );
  }

  Widget _buildAttachmentContent() {
    final List<Widget> items = [
      _buildMenuItem(icon: Icons.camera_alt, label: 'Camera', color: Colors.purple, onTap: () {
        Navigator.pop(context);
        _pickAndPreviewImage(ImageSource.camera);
      }),
      _buildMenuItem(icon: Icons.photo_library, label: 'Photo', color: Colors.pink, onTap: () {
        Navigator.pop(context);
        _pickAndPreviewImage(ImageSource.gallery);
      }),
      _buildMenuItem(icon: Icons.videocam, label: 'Video', color: Colors.orange, onTap: () {
        Navigator.pop(context);
        _pickVideo();
      }),
      _buildMenuItem(icon: Icons.headset, label: 'Audio', color: Colors.lightBlue, onTap: () {
        Navigator.pop(context);
        _pickAudio();
      }),
      _buildMenuItem(icon: Icons.insert_drive_file, label: 'Document', color: Colors.green, onTap: () {
        Navigator.pop(context);
        _pickDocument();
      }),
      _buildMenuItem(icon: Icons.contact_page, label: 'Contact', color: Colors.teal, onTap: () {
        Navigator.pop(context);
        _pickContact();
      }),
      _buildMenuItem(icon: Icons.casino, label: 'Dame', color: Colors.brown, onTap: () {
        Navigator.pop(context);
        setState(() {
          _isGameHardStopped = false;
          _isPreparingInvitation = true;
        });
      }),
      _buildMenuItem(icon: Icons.grid_on_sharp, label: 'Chess', color: Colors.grey.shade700, onTap: () {
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

  Widget _buildMenuItem({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 50, height: 50, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 24)), const SizedBox(height: 6), Text(label, style: const TextStyle(fontSize: 12)),],),
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(leading: IconButton(icon: const Icon(Icons.close), onPressed: () {
      setState(() {
        _isSelectionMode = false;
        _selectedMessages.clear();
      });
    }), title: Text("${_selectedMessages.length} bitoranijwe"), backgroundColor: Colors.blueGrey[800], actions: [IconButton(icon: const Icon(Icons.delete), onPressed: () {}),],);
  }

  AppBar _buildDefaultAppBar() {
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
      flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0), child: Container(color: theme.colorScheme.surface.withAlpha(180),),),),
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _navigateBackToHome),
      title: InkWell(
        onTap: _navigateToContactInfo,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Spacer(),
            _PresenceIndicator(presenceStream: _presenceStream),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: _currentUserStream,
                  builder: (context, currentUserSnapshot) {
                    return StreamBuilder<DocumentSnapshot>(
                      stream: _receiverUserStream,
                      builder: (context, receiverSnapshot) {
                        String? photoUrl;
                        if (currentUserSnapshot.hasData && receiverSnapshot.hasData) {
                          final currentUserData = currentUserSnapshot.data?.data() as Map<String, dynamic>?;
                          final myBlockedUsers = currentUserData?['blockedUsers'] as List<dynamic>? ?? [];
                          final iHaveBlockedReceiver = myBlockedUsers.contains(widget.receiverID);

                          final receiverData = receiverSnapshot.data?.data() as Map<String, dynamic>?;
                          final receiverBlockedUsers = receiverData?['blockedUsers'] as List<dynamic>? ?? [];
                          final amIBlockedByReceiver = receiverBlockedUsers.contains(_auth.currentUser!.uid);
                          
                          if (!iHaveBlockedReceiver && !amIBlockedByReceiver) {
                              photoUrl = receiverData?['photoUrl'];
                          }
                        }
                        
                        return CircleAvatar(
                          radius: 20, 
                          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null, 
                          child: photoUrl == null ? const Icon(Icons.person, size: 22) : null,
                        );
                      },
                    );
                  }
                ),
                const SizedBox(height: 3),
                Text(widget.receiverEmail, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal), overflow: TextOverflow.ellipsis,),
              ],
            ),
            const SizedBox(width: 8),
            _ActivityIndicator(activityStream: _activityStream),
            const Spacer(),
          ],
        ),
      ),
      actions: [
        StreamBuilder<DocumentSnapshot>(
          stream: _currentUserStream,
          builder: (context, snapshot) {
            bool isReceiverBlocked = false;
            if (snapshot.hasData && snapshot.data!.exists) {
              final userData = snapshot.data!.data() as Map<String, dynamic>?;
              final blockedUsers = userData?['blockedUsers'] as List<dynamic>? ?? [];
              isReceiverBlocked = blockedUsers.contains(widget.receiverID);
            }
            return PopupMenuButton<String>(
              onSelected: (value) => _handleMenuSelection(value, isReceiverBlocked: isReceiverBlocked),
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(value: 'view_contact', child: Text('Ibimuranga')),
                const PopupMenuItem<String>(value: 'wallpaper', child: Text("Ifoto y'inyuma")),
                const PopupMenuItem<String>(value: 'clear_chat', child: Text('Futa ibiganiro')),
                PopupMenuItem<String>(value: 'block', child: Text(isReceiverBlocked ? 'Mufungure' : 'Mubloke')),
              ],
            );
          },
        ),
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
    
    return gameWidget ?? const SizedBox.shrink(key: ValueKey('no_game'));
  }
}

class _PresenceIndicator extends StatefulWidget {
  final Stream<DatabaseEvent>? presenceStream;
  const _PresenceIndicator({required this.presenceStream});

  @override
  State<_PresenceIndicator> createState() => _PresenceIndicatorState();
}

class _PresenceIndicatorState extends State<_PresenceIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: widget.presenceStream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          try {
            final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
            final state = data['state'];
            if (state == 'online') {
              return FadeTransition(
                opacity: _animation,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              );
            }
          } catch(e) { /* ignore */ }
        }
        return const SizedBox(width: 16);
      },
    );
  }
}

class _ActivityIndicator extends StatefulWidget {
  final Stream<DatabaseEvent>? activityStream;
  const _ActivityIndicator({required this.activityStream});

  @override
  State<_ActivityIndicator> createState() => _ActivityIndicatorState();
}

class _ActivityIndicatorState extends State<_ActivityIndicator> {
  late Timer _timer;
  late String _timeString;

  @override
  void initState() {
    super.initState();
    _timeString = _formatDateTime(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
  
  void _updateTime() {
    if (mounted) {
      setState(() {
        _timeString = _formatDateTime(DateTime.now());
      });
    }
  }

  String _formatDateTime(DateTime dateTime) {
    // Iyi sura ituma (:) inyeganyega buri segonda
    String separator = dateTime.second.isEven ? ':' : ' ';
    return DateFormat('HH${separator}mm').format(dateTime);
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StreamBuilder<DatabaseEvent>(
      stream: widget.activityStream,
      builder: (context, snapshot) {
        String activity = "idle";
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          activity = snapshot.data!.snapshot.value as String;
        }

        Widget content;
        
        switch(activity) {
          case 'typing':
            content = _buildActivityContent(
              key: 'typing',
              icon: Icons.edit,
              text: "Ariko arandika...",
              theme: theme
            );
            break;
          case 'recording':
            content = _buildActivityContent(
              key: 'recording',
              icon: Icons.mic,
              text: "Ariko afat'ijwi...",
              theme: theme
            );
            break;
          default: // idle
            content = _buildClockContent(
              key: 'idle',
              theme: theme
            );
            break;
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axis: Axis.horizontal,
                child: child,
              ),
            );
          },
          child: content,
        );
      },
    );
  }

  Widget _buildClockContent({required String key, required ThemeData theme}) {
    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time, size: 14, color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
          const SizedBox(width: 6),
          Text(
            _timeString,
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActivityContent({required String key, required IconData icon, required String text, required ThemeData theme}) {
    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSecondaryContainer,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
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
  const ImageBubble({super.key, required this.messageData});

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
    final oldPath = oldWidget.messageData[DatabaseHelper.columnLocalPath];
    final newPath = widget.messageData[DatabaseHelper.columnLocalPath];
    if (newPath != oldPath) {
      _checkIfFileExists();
    }
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

  void _handleDownloadTap() {
    if (_isDownloading) {
      _cancelDownload();
    } else {
      _startDownload();
    }
  }
  
  void _cancelDownload() {
    _httpClient?.close();
    _httpClient = null;
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = null;
      });
    }
  }

  Future<void> _startDownload() async {
    final onlineUrl = widget.messageData[DatabaseHelper.columnFileUrl];
    final messageId = widget.messageData[DatabaseHelper.columnId];

    if (onlineUrl == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ifoto ntiragera kuri server. Tegereza gato.")));
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
        final documentsDir = await getApplicationDocumentsDirectory();
        final chatMediaDir = Directory(path.join(documentsDir.path, 'chat_media'));
        if (!await chatMediaDir.exists()) {
          await chatMediaDir.create(recursive: true);
        }

        final fileName = path.basename(Uri.parse(onlineUrl).path);
        final file = File(path.join(chatMediaDir.path, fileName));
        
        final sink = file.openWrite();
        final totalBytes = response.contentLength ?? -1;
        int receivedBytes = 0;

        await response.stream.listen((List<int> chunk) {
          if(!mounted || !_isDownloading) {
            sink.close();
            _httpClient?.close();
            return;
          }
          receivedBytes += chunk.length;
          if (totalBytes != -1) {
            setState(() => _downloadProgress = receivedBytes / totalBytes);
          }
          sink.add(chunk);
        }).asFuture();

        await sink.close();
        
        await DatabaseHelper.instance.updateMessageLocalPath(messageId, file.path);
        
        if (mounted) {
           _localPath = file.path;
           setState(() {
             _localFileExists = true;
             _isDownloading = false;
             _downloadProgress = null;
           });
        }

      } else {
        throw Exception('Gukurura byanze: Status Code ni ${response.statusCode}');
      }
    } catch (e) {
      if (e is http.ClientException) {
        debugPrint("Gukurura ifoto byahagaritswe.");
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gukurura ifoto byanze: $e")));
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

  @override
  Widget build(BuildContext context) {
    final caption = widget.messageData[DatabaseHelper.columnMessage] as String?;
    final isMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser!.uid;
    final textColor = isMe ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurface;
    final remoteUrl = widget.messageData[DatabaseHelper.columnFileUrl];
    
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
                if (_localFileExists && _localPath != null)
                  GestureDetector(
                    onTap: () {
                       if (remoteUrl != null) {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => FullPhotoScreen(
                              imageUrl: remoteUrl,
                              heroTag: remoteUrl, 
                            ),
                            transitionDuration: const Duration(milliseconds: 700),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return FadeTransition(opacity: animation, child: child);
                            },
                          ),
                        );
                       }
                    },
                    child: Image.file(
                      File(_localPath!),
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
                
                if (!_localFileExists)
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

class VoiceBubble extends StatelessWidget {
  final Map<String, dynamic> messageData;

  const VoiceBubble({super.key, required this.messageData});

  String _formatDuration(Duration d) {
    if (d.inMilliseconds < 0) return "00:00";
    return "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<AudioPlayerService>();
    final isCurrentMessage = playerService.currentMessageId == messageData['id'];
    final isPlaying = isCurrentMessage && playerService.isPlaying;
    
    final position = isCurrentMessage ? playerService.position : Duration.zero;
    final totalDurationValue = messageData['duration'] ?? 0;
    final totalDuration = isCurrentMessage && playerService.duration.inSeconds > 0 
        ? playerService.duration 
        : Duration(seconds: totalDurationValue > 0 ? totalDurationValue : 1);

    final audioSource = messageData[DatabaseHelper.columnLocalPath] ?? messageData[DatabaseHelper.columnFileUrl];
    final messageType = messageData[DatabaseHelper.columnMessageType];
    final isVoiceNote = messageType == 'voice_note';
    final fileName = messageData[DatabaseHelper.columnFileName] as String?;
    
    final isMe = messageData['senderID'] == FirebaseAuth.instance.currentUser!.uid;
    final textColor = isMe 
        ? Theme.of(context).colorScheme.onPrimaryContainer 
        : Theme.of(context).colorScheme.onSurface;

    void handlePlayPause() {
      if (audioSource != null) {
        final isLocal = !(audioSource as String).startsWith('http');
        playerService.loadAudio(messageData['id'], audioSource, isLocal);
      }
    }

    if (isVoiceNote) {
      final List<double> waveform = (messageData['waveform'] != null && messageData['waveform'].isNotEmpty) ? List<double>.from(jsonDecode(messageData['waveform'])) : List.filled(60, 0.1);
      return SizedBox(width: 200, child: Row(children: [IconButton(icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Theme.of(context).colorScheme.primary), onPressed: handlePlayPause), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(height: 30, child: WaveformPainter(waveform: waveform, progress: (totalDuration.inMilliseconds == 0) ? 0 : position.inMilliseconds / totalDuration.inMilliseconds,),), Row(children: [Text(_formatDuration(position), style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.8))), const Spacer(), if (isPlaying) TextButton(child: Text("${playerService.playbackSpeed}x", style: TextStyle(color: Theme.of(context).colorScheme.secondary)), onPressed: () => playerService.toggleSpeed(),)],),],),)],),);
    } else {
      return SizedBox(
        width: 250,
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
                    fileName ?? "Audio File",
                    style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: textColor),
                  onPressed: handlePlayPause,
                ),
                Expanded(
                  child: SliderTheme(
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
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position), style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7))),
                  Text(_formatDuration(totalDuration), style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7))),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }
}

class VideoPlayerBubble extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final String? caption;

  const VideoPlayerBubble({super.key, required this.messageData, this.caption});

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
    final oldPath = oldWidget.messageData[DatabaseHelper.columnLocalPath];
    final newPath = widget.messageData[DatabaseHelper.columnLocalPath];

    if (newPath != oldPath) {
      log("[VideoPlayerBubble] Inzira yahindutse. Dutangiye gusubiramo controller.");
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
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
    await _checkIfFileExistsAndInitialize();
  }

  Future<void> _checkIfFileExistsAndInitialize() async {
    _localPath = widget.messageData[DatabaseHelper.columnLocalPath];
    if (_localPath != null && await File(_localPath!).exists()) {
      if (mounted) {
        setState(() {
          _localFileExists = true;
        });
        _initializeController();
      }
    } else {
      if (mounted) {
        setState(() {
          _localFileExists = false;
        });
      }
    }
  }

  Future<void> _initializeController() async {
    if (_localPath == null) {
      log("[VideoPlayerBubble] GUTEGURA BYANZE: _localPath ni null.");
      return;
    }
    if (_controller != null) {
       log("[VideoPlayerBubble] GUTEGURA BYAHAGAZE: Controller isanzwe ihari.");
      return;
    }

    log("[VideoPlayerBubble] DUTANGIYE GUTEGURA CONTROLLER ku nzira: $_localPath");
    final newController = VideoPlayerController.file(File(_localPath!));
    _controller = newController;

    try {
      await newController.initialize();
      
      if (mounted && _controller == newController) {
        log("[VideoPlayerBubble] CONTROLLER YATEGUWE NEZA.");
        setState(() {}); 
        _startHideControlsTimer();
        newController.addListener(() {
          if (mounted && newController.value.position >= newController.value.duration) {
            _hideControlsTimer?.cancel();
            setState(() {
              _showControls = true;
            });
          }
        });
      } else {
        log("[VideoPlayerBubble] Controller nshya yaje mu gihe indi yategurwaga. Iya kera turayifunze.");
        newController.dispose();
      }
    } catch (e) {
      log("!!!!!! [VideoPlayerBubble] IKOSA RIKOMEYE mu gutegura video controller: $e");
      if(mounted && _controller == newController) {
        setState(() {
          _controller = null;
        });
      }
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if(!_showControls) return;
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _handleDownloadTap() {
    if (_isDownloading) {
      _cancelDownload();
    } else {
      _startDownload();
    }
  }
  
  void _cancelDownload() {
    _httpClient?.close();
    _httpClient = null;
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = null;
      });
    }
  }

  Future<void> _startDownload() async {
    final onlineUrl = widget.messageData[DatabaseHelper.columnFileUrl];
    final messageId = widget.messageData[DatabaseHelper.columnId];

    log("[DOWNLOAD] Dutangiye gukurura videwo y'ubutumwa $messageId. URL: $onlineUrl");

    if (onlineUrl == null) {
      log("[DOWNLOAD] IKOSA: onlineUrl ni null. Nta videwo yo gukurura ihari.");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Videwo ntiragera kuri server. Tegereza gato.")));
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
      
      log("[DOWNLOAD] Twakiriye igisubizo. Status code: ${response.statusCode}");

      if (response.statusCode == 200) {
        final documentsDir = await getApplicationDocumentsDirectory();
        final chatMediaDir = Directory(path.join(documentsDir.path, 'chat_media'));
        if (!await chatMediaDir.exists()) {
          await chatMediaDir.create(recursive: true);
        }

        final fileName = path.basename(Uri.parse(onlineUrl).path);
        final file = File(path.join(chatMediaDir.path, fileName));
        log("[DOWNLOAD] Tugiye kubika dosiye muri: ${file.path}");

        final sink = file.openWrite();
        final totalBytes = response.contentLength ?? -1;
        int receivedBytes = 0;

        await response.stream.listen((List<int> chunk) {
          if(!mounted || !_isDownloading) {
            sink.close();
            _httpClient?.close();
            return;
          }
          receivedBytes += chunk.length;
          if (totalBytes != -1) {
            setState(() => _downloadProgress = receivedBytes / totalBytes);
          }
          sink.add(chunk);
        }).asFuture();

        await sink.close();
        log("[DOWNLOAD] Dosiye yanditswe neza. Ubunini: $receivedBytes bytes.");
        
        await DatabaseHelper.instance.updateMessageLocalPath(messageId, file.path);
        log("[DOWNLOAD] Inzira y'imbere (local path) yavuguruwe muri Database.");
        
        if (mounted) {
           log("[DOWNLOAD] Tugiye kuvugurura UI. Dosiye irahari, dutangiye gutegura controller...");
           _localPath = file.path;
           _localFileExists = true;
           _isDownloading = false;
           _downloadProgress = null;
           _initializeController();
        }

      } else {
        throw Exception('Gukurura byanze: Status Code ni ${response.statusCode}');
      }
    } catch (e) {
      log("!!!!!! [DOWNLOAD] IKOSA RIKOMEYE: Gukurura videwo byanze: $e");
      if (e is http.ClientException) {
        debugPrint("Gukurura videwo vyahagaritswe.");
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gukurura videwo byanze: $e")));
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
                  Image(
                      image: thumbnailProvider,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Container(color: Colors.black87, child: const Icon(Icons.videocam, color: Colors.white54, size: 50)),
                  )
                else
                  Container(color: Colors.black87, child: const Icon(Icons.videocam, color: Colors.white54, size: 50)),
                
                if (_localFileExists) ...[
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
                  ] else ...[
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _handleDownloadTap,
                        child: Container(
                          width: 40,
                          height: 40,
                          padding: _isDownloading ? const EdgeInsets.all(4) : EdgeInsets.zero,
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: _isDownloading
                              ? CircularProgressIndicator(
                                  value: _downloadProgress,
                                  color: Colors.white,
                                  backgroundColor: Colors.white30,
                                  strokeWidth: 3,
                                )
                              : const Icon(
                                  Icons.download_for_offline,
                                  color: Colors.white,
                                  size: 30,
                                ),
                        ),
                      ),
                    ),
                  ]
              ],
            ),
          ),
        ),
        if (widget.caption != null && widget.caption!.isNotEmpty)
          Padding(
              padding:
                  const EdgeInsets.only(top: 6.0, left: 4.0, right: 4.0),
              child:
                  Text(widget.caption!, style: TextStyle(color: textColor))),
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
  final VoidCallback? onDeclineInvitation;

  const MessageBubble({
    super.key,
    required this.messageData,
    required this.isMe,
    required this.isSelected,
    this.uploadProgress,
    this.onAcceptInvitation,
    this.onDeclineInvitation,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _actionTaken = false;

  Widget _buildStatusIcon(String? status, ThemeData theme) {
    IconData icon;
    Color color;
    switch (status) {
      case 'seen':
        icon = Icons.visibility;
        color = Colors.cyan.shade300;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = theme.textTheme.bodyMedium?.color ?? Colors.grey;
        break;
      case 'sent':
        icon = Icons.done;
        color = theme.textTheme.bodyMedium?.color ?? Colors.grey;
        break;
      case 'failed':
        icon = Icons.error_outline;
        color = Colors.red.shade400;
        break;
      case 'pending':
      case 'uploading':
      case 'paused':
      default:
        icon = Icons.watch_later_outlined;
        color = theme.textTheme.bodyMedium?.color ?? Colors.grey;
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
    final isLargeEmoji = widget.messageData['messageType'] == 'large_emoji';
    final bubbleColor = isLargeEmoji ? Colors.transparent : (widget.isSelected ? Colors.blue.withAlpha(128) : (widget.isMe ? theme.colorScheme.primaryContainer : theme.colorScheme.surface));
    final textColor = widget.isMe ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface;

    final bool isUploading = widget.uploadProgress != null && (widget.messageData['status'] == 'uploading' || widget.messageData['status'] == 'paused');

    int? timestampValue;
    if (widget.messageData['timestamp'] is int) {
      timestampValue = widget.messageData['timestamp'];
    }

    Widget messageContent = isLargeEmoji ? _buildMessageContent(context, widget.messageData, textColor, isUploading)
        : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMessageContent(context, widget.messageData, textColor, isUploading),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_formatMessageTimestamp(timestampValue), style: TextStyle(fontSize: 10, color: textColor.withAlpha(179)),),
            if (widget.isMe) const SizedBox(width: 4),
            if (widget.isMe) _buildStatusIcon(widget.messageData['status'], theme),
          ],
        )
      ],
    );

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: isLargeEmoji ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(12)),
            child: messageContent,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context, Map<String, dynamic> data, Color textColor, bool isUploading) {
    final type = data[DatabaseHelper.columnMessageType];
    Widget content;
    switch (type) {
      case 'dame_invitation_declined':
        content = Text(data['message'] ?? 'Ubutumire bwanzwe.', style: TextStyle(color: textColor, fontStyle: FontStyle.italic));
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
                      widget.onDeclineInvitation?.call();
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
                    child: const Text("Oya"),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _actionTaken = true);
                      widget.onAcceptInvitation?.call();
                    },
                    child: const Text("Ego"),
                  ),
                ],
              ),

            if (!widget.isMe && isExpired)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  "Ubutumire bwarasaje.",
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
        content = Text(data['message'] ?? '', style: TextStyle(color: textColor));
        break;
      case 'image':
        content = ImageBubble(messageData: data);
        break;
      case 'video':
        content = VideoPlayerBubble(
            messageData: data, 
            caption: data[DatabaseHelper.columnMessage],
        );
        break;
      case 'voice_note':
      case 'audio_file':
        content = VoiceBubble(messageData: data);
        break;
      case 'document':
        content = Row(children: [const Icon(Icons.insert_drive_file, color: Colors.blueAccent), const SizedBox(width: 8), Expanded(child: Text(data['fileName'] ?? 'Document', style: TextStyle(color: textColor)))]);
        break;
      case 'contact':
        try {
          final contactJson = jsonDecode(data['message']);
          return Row(children: [const Icon(Icons.person, color: Colors.green), const SizedBox(width: 8), Text(contactJson['name'] ?? 'Contact', style: TextStyle(color: textColor))]);
        } catch (e) {
          content = Text('[Contact error]', style: TextStyle(color: textColor));
        }
        break;
      default:
        content = Text("[Ubutumwa ntibusobanutse]", style: TextStyle(color: textColor));
    }
    if (isUploading) {
      return Stack(alignment: Alignment.center, children: [
        content,
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(color: Colors.black.withAlpha(128), borderRadius: BorderRadius.circular(8)),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  if (data['status'] == 'paused') {
                    syncService.resumeUpload(data[DatabaseHelper.columnId]);
                  } else {
                    syncService.pauseUpload(data[DatabaseHelper.columnId]);
                  }
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: widget.uploadProgress,
                        backgroundColor: Colors.white.withAlpha(77),
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                      Center(
                        child: Icon(
                          data['status'] == 'paused' ? Icons.play_arrow : Icons.pause,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    }
    return content;
  }
}

class WaveformPainter extends StatelessWidget {
  final List<double> waveform;
  final double progress;

  const WaveformPainter({super.key, required this.waveform, required this.progress});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _WaveformCustomPainter(waveData: waveform, progress: progress, theme: Theme.of(context),),);
}

class _WaveformCustomPainter extends CustomPainter {
  final List<double> waveData;
  final double progress;
  final ThemeData theme;

  _WaveformCustomPainter({required this.waveData, required this.progress, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final paintBg = Paint()..color = Colors.grey.shade400;
    final paintFg = Paint()..color = theme.colorScheme.secondary;
    
    final barWidth = 3.0;
    final barGap = 2.0;
    final totalBars = (size.width / (barWidth + barGap)).floor();
    for (int i = 0; i < totalBars; i++) {
      final barHeight = waveData[(i * waveData.length / totalBars).floor()].clamp(0.05, 1.0) * size.height;
      final x = i * (barWidth + barGap);
      final y = (size.height - barHeight) / 2;
      final currentBarProgress = (i + 1) / totalBars;
      final paint = currentBarProgress <= progress ? paintFg : paintBg;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barWidth, barHeight), const Radius.circular(2)), paint);
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
                Expanded(child: Container(decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(24),), child: TextField(controller: _captionController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Ongerako amajambo...", hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),),),),),
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
      print("Video player init error: $e");
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _isLoading ? const CircularProgressIndicator()
                : (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized)
                ? Chewie(controller: _chewieController!)
                : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.error, color: Colors.red, size: 40), SizedBox(height: 16), Text('Ntibishoboye gukina iyi video.', style: TextStyle(color: Colors.white))]),
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