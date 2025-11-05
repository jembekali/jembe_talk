// lib/chat_screen.dart (VERSION FINAL, YUZUYE, KANDI UMUKINO WA DAME UKORA NEZA)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:developer';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  Stream<DocumentSnapshot>? _gameStream;
  Map<String, dynamic>? _optimisticGameData;

  bool _isPreparingInvitation = false;
  bool _isWaitingForGameAcceptance = false;

  DateTime? _timeWhenPaused;

  final TextEditingController _messageController = TextEditingController();
  bool _isComposing = false;
  final Map<String, double> _uploadProgress = {};
  final FocusNode _focusNode = FocusNode();
  bool _showEmojiPicker = false;
  List<dynamic> _chatItems = [];

  bool _isTextFieldReadOnly = false;

  StreamSubscription? _uploadProgressSubscription;

  VideoEditorController? _videoEditorController;
  File? _selectedVideoFile;
  bool _isProcessingVideo = false;
  double _videoProcessingProgress = 0.0;
  
  String? _optimisticMessageId;
  
  bool _isGameHardStopped = false;

  StreamSubscription? _uiUpdateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final chatRoomID = _getChatRoomID();
    _currentUserStream = _firestore.collection('users').doc(_auth.currentUser!.uid).snapshots();
    _receiverUserStream = _firestore.collection('users').doc(widget.receiverID).snapshots();
    _gameStream = _firestore.collection('games').doc(chatRoomID).snapshots();
    
    _loadInitialMessages();
    _listenForFirebaseMessages();

    _uiUpdateSubscription = syncService.uiMessageUpdateStream.listen((updatedMessageId) {
      final index = _messages.indexWhere((msg) => msg['id'] == updatedMessageId);
      if (index != -1 && mounted) {
        log("UI update received from FCM for message: $updatedMessageId. Reloading messages.");
        _loadInitialMessages();
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
      if (mounted) setState(() => _isComposing = _messageController.text.trim().isNotEmpty);
    });
    
    syncService.triggerSync();
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
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadInitialMessages() async {
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
    _messageController.dispose();
    _focusNode.dispose();
    _videoEditorController?.dispose();
    if (mounted) context.read<AudioPlayerService>().stop();
    _uploadProgressSubscription?.cancel();
    _uiUpdateSubscription?.cancel();
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

  void _listenForFirebaseMessages() {
    final chatRoomID = _getChatRoomID();
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    _messageSubscription?.cancel();
    _messageSubscription = _firestore
        .collection('chat_rooms')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      List<DocumentReference> messagesToMarkAsSeen = [];
      bool needsUIUpdate = false;
      for (var change in snapshot.docChanges) {
        needsUIUpdate = true;
        final doc = change.doc;
        final serverMessage = doc.data() as Map<String, dynamic>;
        if (serverMessage['timestamp'] is! int) {
          serverMessage['timestamp'] = (serverMessage['timestamp'] as Timestamp).millisecondsSinceEpoch;
        }
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          await DatabaseHelper.instance.saveMessage(serverMessage);
        } else if (change.type == DocumentChangeType.removed) {
          await DatabaseHelper.instance.deleteMessage(serverMessage['id']);
        }
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
      if (needsUIUpdate && mounted) {
        final localMessages = await DatabaseHelper.instance.getMessagesForChatRoom(chatRoomID);
        setState(() {
          _messages = List.from(localMessages);
          _chatItems = _getChatItemsWithSeparators(_messages);
        });
        if (snapshot.docChanges.any((c) => c.type == DocumentChangeType.added)) {
          _scrollToBottom();
        }
      }
    });
  }

  void _sendMessage({String? text, String messageType = 'text'}) async {
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
    syncService.triggerSync();
    _loadInitialMessages();
    _scrollToBottom();
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
    final image = await ImagePicker().pickImage(source: source);
    if (image == null) return;
    final imageBytes = await File(image.path).readAsBytes();
    if (!mounted) return;
    final editedImageBytes = await Navigator.push<Uint8List?>(context, MaterialPageRoute(builder: (context) => ImageEditor(image: imageBytes,)),);
    if (editedImageBytes == null) return;
    final tempDir = await getTemporaryDirectory();
    final tempFilePath = path.join(tempDir.path, '${const Uuid().v4()}.png');
    final tempFile = File(tempFilePath);
    await tempFile.writeAsBytes(editedImageBytes);
    if (!mounted) return;
    final result = await Navigator.push<Map<String, String>>(context, MaterialPageRoute(builder: (context) => ImagePreviewScreen(imagePath: tempFile.path),),);
    if (result != null) {
      final pathFromPreview = result['path'];
      final caption = result['caption'];
      if (pathFromPreview != null) {
        final permanentPath = await mediaUploadService.saveFilePermanently(pathFromPreview);
        await mediaUploadService.sendMediaMessage(
          chatRoomID: _getChatRoomID(),
          receiverID: widget.receiverID,
          localPath: permanentPath,
          messageType: 'image',
          text: caption,
          fileName: path.basename(permanentPath),
        );
      }
    }
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
      _addOptimisticVideoMessage(permanentPath, thumbnailPath);
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

  void _addOptimisticVideoMessage(String localPath, String? thumbnailLocalPath) {
    final messageId = "optimistic_${const Uuid().v4()}";
    final optimisticMessage = {
      DatabaseHelper.columnId: messageId,
      DatabaseHelper.columnChatRoomID: _getChatRoomID(),
      DatabaseHelper.columnSenderID: _auth.currentUser!.uid,
      DatabaseHelper.columnReceiverID: widget.receiverID,
      DatabaseHelper.columnMessageType: 'video',
      DatabaseHelper.columnMessage: '',
      DatabaseHelper.columnTimestamp: DateTime.now().millisecondsSinceEpoch,
      DatabaseHelper.columnStatus: 'optimistic',
      DatabaseHelper.columnLocalPath: localPath,
      DatabaseHelper.columnFileName: thumbnailLocalPath,
    };
    setState(() {
      _messages.add(optimisticMessage);
      _chatItems = _getChatItemsWithSeparators(_messages);
      _optimisticMessageId = messageId;
    });
    _scrollToBottom();
  }

  void _sendOptimisticVideo() {
    if (_optimisticMessageId == null) return;
    final optimisticMessageIndex = _messages.indexWhere((m) => m['id'] == _optimisticMessageId);
    if (optimisticMessageIndex == -1) return;
    final optimisticData = _messages[optimisticMessageIndex];
    mediaUploadService.sendMediaMessage(
      chatRoomID: optimisticData[DatabaseHelper.columnChatRoomID],
      receiverID: optimisticData[DatabaseHelper.columnReceiverID],
      localPath: optimisticData[DatabaseHelper.columnLocalPath],
      messageType: 'video',
      thumbnailLocalPath: optimisticData[DatabaseHelper.columnFileName],
      fileName: path.basename(optimisticData[DatabaseHelper.columnLocalPath]),
    );
    setState(() {
      _messages.removeAt(optimisticMessageIndex);
      _chatItems = _getChatItemsWithSeparators(_messages);
      _optimisticMessageId = null;
    });
  }

  void _cancelOptimisticVideo() {
    if (_optimisticMessageId == null) return;
    setState(() {
      _messages.removeWhere((m) => m['id'] == _optimisticMessageId);
      _chatItems = _getChatItemsWithSeparators(_messages);
      _optimisticMessageId = null;
    });
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
    final invitationSenderId = invitationMessage['senderID'];
    final chatRoomID = _getChatRoomID();
    final currentUser = _auth.currentUser!;
    final initialBoard = List.generate(8, (row) {
      return List.generate(8, (col) {
        if ((row + col) % 2 != 0) {
          if (row < 3) return {'player': 2, 'type': 'man'};
          if (row > 4) return {'player': 1, 'type': 'man'};
        }
        return null;
      });
    });
    final Map<String, dynamic> boardForFirestore = {};
    for (int i = 0; i < initialBoard.length; i++) {
      boardForFirestore[i.toString()] = initialBoard[i];
    }
    final player1Id = invitationSenderId;
    final player2Id = currentUser.uid;
    final player1Doc = await _firestore.collection('users').doc(player1Id).get();
    final player1Email = player1Doc.data()?['displayName'] ?? 'Player 1';
    final player2Doc = await _firestore.collection('users').doc(player2Id).get();
    final player2Email = player2Doc.data()?['displayName'] ?? 'Player 2';
    
    final gameData = {
      'boardState': boardForFirestore, 'player1Id': player1Id, 'player2Id': player2Id, 'player1Email': player1Email,
      'player2Email': player2Email, 'turn': player1Id, 'status': 'active',
      'winnerId': null, 'endReason': null,
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

  void _handleMenuSelection(String value) {
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Block/Unblock ntiriko irakora muriki gihe co gusuzuma.")));
        break;
    }
  }

  Future<void> _clearChat() async {
    final chatRoomID = _getChatRoomID();
    await DatabaseHelper.instance.clearChat(chatRoomID);
    setState(() {
      _messages.clear();
      _chatItems.clear();
    });
  }

  void _toggleEmojiPicker() async {
    if (_showEmojiPicker) {
      Navigator.of(context).pop();
    } else {
      if (!_isTextFieldReadOnly) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        setState(() => _isTextFieldReadOnly = true);
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (mounted) _showAnimatedEmojiPicker();
    }
  }

  void _onEmojiSelected(EmojiData emoji) {
    if (_messageController.text.trim().isEmpty) {
      _sendMessage(text: emoji.char, messageType: 'large_emoji');
      if (_showEmojiPicker) Navigator.of(context).pop();
    } else {
      setState(() {
        _messageController.text += emoji.char;
        _messageController.selection = TextSelection.fromPosition(TextPosition(offset: _messageController.text.length));
      });
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isTextFieldReadOnly = false;
          });
          _focusNode.requestFocus();
        }
      });
    }
  }

  void _showAnimatedEmojiPicker() async {
    if (mounted) setState(() => _showEmojiPicker = true);
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
    if (mounted) setState(() => _showEmojiPicker = false);
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
    }
  }

  Future<void> _pickAudio() async {
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
    }
  }

  Future<void> _pickContact() async {
    await mediaUploadService.sendContact(
      context,
      chatRoomID: _getChatRoomID(),
      receiverID: widget.receiverID,
    );
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
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeWallpaperPath = _chatBackgroundImagePath ?? _globalBackgroundImagePath;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if(didPop) return;
        if (_optimisticMessageId != null) {
          _cancelOptimisticVideo();
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
        body: StreamBuilder<DocumentSnapshot>(
          stream: _gameStream,
          builder: (context, gameSnapshot) {
            
            if (gameSnapshot.hasData && gameSnapshot.data!.exists) {
              if (_isWaitingForGameAcceptance) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _isWaitingForGameAcceptance = false;
                      _isPreparingInvitation = false;
                    });
                  }
                });
              }
            }

            bool isGameAvailable = gameSnapshot.hasData && gameSnapshot.data!.exists;
            bool isGameActive = isGameAvailable && (gameSnapshot.data!.data() as Map<String, dynamic>)['status'] == 'active';
            return Stack(
              children: [
                if (activeWallpaperPath != null && File(activeWallpaperPath).existsSync())
                  Image.file(File(activeWallpaperPath), height: double.infinity, width: double.infinity, fit: BoxFit.cover, color: Colors.black.withAlpha(128), colorBlendMode: BlendMode.darken)
                else
                  Container(color: theme.scaffoldBackgroundColor),
                SafeArea(
                  child: Column(
                    children: [
                      _buildLiveGameArea(gameSnapshot),
                      Expanded(
                        child: _buildMessagesContainer(),
                      ),
                      _buildMessageComposerContainer(isGameActive: isGameActive),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessagesContainer() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(200),
        borderRadius: BorderRadius.circular(24.0),
        image: DecorationImage(
          image: const AssetImage('assets/images/star_pattern_dark.png'),
          repeat: ImageRepeat.repeat,
          colorFilter: ColorFilter.mode(Colors.white.withAlpha(26), BlendMode.srcATop),
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
            final isOptimistic = messageData['status'] == 'optimistic';
            return MessageBubble(
              key: ValueKey(messageId),
              messageData: messageData,
              isMe: messageData['senderID'] == _auth.currentUser!.uid,
              isSelected: _selectedMessages.contains(messageId),
              uploadProgress: progress,
              onAcceptInvitation: () => _createGameInFirestore(messageData),
              onDeclineInvitation: _handleDeclineInvitation,
              isOptimistic: isOptimistic,
              onSendOptimistic: _sendOptimisticVideo,
              onCancelOptimistic: _cancelOptimisticVideo,
            );
          }
        },
      ),
    );
  }

  Widget _buildMessageComposerContainer({required bool isGameActive}) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _currentUserStream,
      builder: (context, snapshot) {
        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        final blockedUsers = userData?['blockedUsers'] as List<dynamic>? ?? [];
        final isReceiverBlocked = blockedUsers.contains(widget.receiverID);
        if (isReceiverBlocked) {
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
        } else {
          return _buildMessageComposer(isGameActive: isGameActive);
        }
      },
    );
  }

  Widget _buildMessageComposer({required bool isGameActive}) {
    if (_selectedVideoFile != null) {
      return _buildVideoEditorComposer();
    }
    final theme = Theme.of(context);
    bool isReadOnly = isGameActive || _isTextFieldReadOnly;
    String hintText = "Message...";
    if (isGameActive) {
      hintText = "Koresha ijwi mu mukino...";
    } else if (_optimisticMessageId != null) {
      final optimisticMessageExists = _messages.any((m) => m['id'] == _optimisticMessageId);
      if (optimisticMessageExists) {
        isReadOnly = true;
      }
    }
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
                      icon: Icon(_showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined, color: theme.iconTheme.color?.withAlpha(179)),
                      onPressed: isReadOnly ? null : _toggleEmojiPicker,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: TextField(
                        focusNode: _focusNode,
                        controller: _messageController,
                        readOnly: isReadOnly,
                        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: hintText,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onTap: () {
                          if (isReadOnly) return;
                          if (_showEmojiPicker) Navigator.pop(context);
                          if (_isTextFieldReadOnly) {
                            setState(() {
                              _isTextFieldReadOnly = false;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _focusNode.requestFocus();
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  IconButton(
                      icon: Icon(Icons.attach_file, color: theme.iconTheme.color?.withAlpha(179)),
                      onPressed: isReadOnly ? null : _showAnimatedDialogMenu
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
            child: _isComposing && !isGameActive
                ? FloatingActionButton(key: const ValueKey('send_button'), onPressed: () => _sendMessage(messageType: 'text'), backgroundColor: theme.colorScheme.primary, elevation: 2, child: Icon(Icons.send, color: theme.colorScheme.onPrimary),)
                : SocialMediaRecorder(
                    key: const ValueKey('mic_recorder'), 
                    sendRequestFunction: (File soundFile, String duration) async {
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
                    },
                    recordIcon: FloatingActionButton(key: const ValueKey('mic_button'), onPressed: isReadOnly ? null : () {}, backgroundColor: isReadOnly ? Colors.grey : theme.colorScheme.secondary, elevation: 2, child: Icon(Icons.mic, color: theme.colorScheme.onSecondary),),
            ),
          ),
        ],
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StreamBuilder<DocumentSnapshot>(
                stream: _receiverUserStream,
                builder: (context, snapshot) {
                  String? photoUrl;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final userData = snapshot.data!.data() as Map<String, dynamic>?;
                    photoUrl = userData?['photoUrl'];
                  }
                  return CircleAvatar(radius: 20, backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null, child: photoUrl == null ? const Icon(Icons.person, size: 22) : null);
                }
            ),
            const SizedBox(height: 3),
            Text(widget.receiverEmail, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal), overflow: TextOverflow.ellipsis,),
          ],
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          onSelected: _handleMenuSelection,
          itemBuilder: (context) {
            final isReceiverBlocked = false; 
            return <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'view_contact', child: Text('Ibimuranga')),
              const PopupMenuItem<String>(value: 'wallpaper', child: Text("Ifoto y'inyuma")),
              const PopupMenuItem<String>(value: 'clear_chat', child: Text('Futa ibiganiro')),
              PopupMenuItem<String>(value: 'block', child: Text(isReceiverBlocked ? 'Mufungure' : 'Mubloke'))
            ];
          },
        )
      ],
    );
  }

  Widget _buildLiveGameArea(AsyncSnapshot<DocumentSnapshot<Object?>> gameSnapshot) {
    Widget? gameWidget;
    if (_isGameHardStopped) {
      gameWidget = null;
    } else if (_optimisticGameData != null) {
      gameWidget = DameGameWidget(
          chatRoomID: _getChatRoomID(),
          gameData: _optimisticGameData!,
          key: const ValueKey('optimistic_game')
      );
    } else if (gameSnapshot.hasData && gameSnapshot.data!.exists) {
      final gameData = gameSnapshot.data!.data() as Map<String, dynamic>;
      if (gameData['status'] == 'active') {
        gameWidget = DameGameWidget(
          chatRoomID: _getChatRoomID(),
          gameData: gameData,
          opponentDisplayName: widget.receiverEmail,
          key: const ValueKey('active_game'),
          onGameStopped: () {
            setState(() {
              _isGameHardStopped = true;
            });
          },
        );
      }
    }
    
    if (gameWidget == null && (_isPreparingInvitation || _isWaitingForGameAcceptance)) {
      final initialBoard = List.generate(8, (row) => List.generate(8, (col) {
        if ((row + col) % 2 != 0) {
          if (row < 3) return {'player': 2, 'type': 'man'};
          if (row > 4) return {'player': 1, 'type': 'man'};
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
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1200),
      switchInCurve: Curves.easeOutQuart,
      switchOutCurve: Curves.easeInQuart,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1.0,
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
  const ImageBubble({super.key, required this.messageData});

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  @override
  Widget build(BuildContext context) {
    final localPath = widget.messageData[DatabaseHelper.columnLocalPath];
    final remoteUrl = widget.messageData[DatabaseHelper.columnFileUrl];
    final caption = widget.messageData[DatabaseHelper.columnMessage] as String?;
    
    final isMe = widget.messageData['senderID'] == FirebaseAuth.instance.currentUser!.uid;
    final textColor = isMe ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurface;

    ImageProvider? imageProvider;

    if (localPath != null && File(localPath).existsSync()) {
      imageProvider = FileImage(File(localPath));
    } else if (remoteUrl != null) {
      imageProvider = NetworkImage(remoteUrl);
    }

    if (imageProvider == null) {
      return Container(
        width: 250,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(
            image: imageProvider,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: 250,
                height: 200,
                color: Colors.grey[800],
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 250,
                height: 200,
                color: Colors.grey[800],
                child: const Center(child: Icon(Icons.broken_image, color: Colors.white60)),
              );
            },
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
  final bool isOptimistic;

  const VideoPlayerBubble({super.key, required this.messageData, this.caption, this.isOptimistic = false});

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
        if (!widget.isOptimistic) {
           _initializeController();
        }
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
                if (!widget.isOptimistic && _controller != null && _controller!.value.isInitialized)
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
                
                if (!widget.isOptimistic) ...[
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
  final bool isOptimistic;
  final VoidCallback? onSendOptimistic;
  final VoidCallback? onCancelOptimistic;

  const MessageBubble({
    super.key,
    required this.messageData,
    required this.isMe,
    required this.isSelected,
    this.uploadProgress,
    this.onAcceptInvitation,
    this.onDeclineInvitation,
    this.isOptimistic = false,
    this.onSendOptimistic,
    this.onCancelOptimistic,
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

    final bool isUploading = widget.uploadProgress != null && widget.messageData['status'] == 'pending';

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
            if (widget.isMe && !widget.isOptimistic) const SizedBox(width: 4),
            if (widget.isMe && !widget.isOptimistic) _buildStatusIcon(widget.messageData['status'], theme),
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
          
          if (widget.isOptimistic)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(128),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: widget.onCancelOptimistic,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                          ),
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                        const SizedBox(width: 40),
                        ElevatedButton(
                          onPressed: widget.onSendOptimistic,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(16),
                          ),
                          child: const Icon(Icons.send, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
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
            isOptimistic: widget.isOptimistic,
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
              child: SizedBox(
                width: 40, height: 40,
                child: CircularProgressIndicator(
                  value: widget.uploadProgress,
                  backgroundColor: Colors.white.withAlpha(77),
                  color: Colors.white,
                  strokeWidth: 3,
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