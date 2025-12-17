// lib/dame_game_widget.dart (VERSION 14.1: DISTINCT KINGS VISUALS)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'dame_game_logic.dart';

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

    // Player 1: Light Pieces (Wheat/Beige)
    final lightPiece = BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: mustPlay ? Colors.red.shade900 : (isSelected ? Colors.green : Colors.black54),
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

    // Player 2: Dark Pieces (Brown)
    final darkPiece = BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: mustPlay ? Colors.red.shade900 : (isSelected ? Colors.green : Colors.black54),
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
                // LOGIC NSHASHA Y'ABAMI (KINGS)
                if (piece.type == DamePieceType.king)
                  Icon(
                    Icons.star_rounded,
                    // Player 1 (Light): Inyenyeri Y'UMWERU (nkuko wabisabye)
                    // Player 2 (Dark): Inyenyeri ya ZAHABU/UMUKARA (kugira ngo igaragare)
                    color: isPlayer1 ? Colors.white : Colors.amber,
                    size: squareSize * 0.7,
                    shadows: [
                      // Shyiraho igicucu (Shadow) kugira ngo umweru ugaragare ku ibara ryerurutse
                      BoxShadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      )
                    ],
                  ),
                  
                // Optional: Utumenyetso duto twerekana ko ari King niba inyenyeri idahagije
                if (piece.type == DamePieceType.king)
                   Positioned(
                     bottom: 4,
                     child: Container(
                       width: squareSize * 0.3,
                       height: 2,
                       color: isPlayer1 ? Colors.black45 : Colors.white54,
                     ),
                   )
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
    
    if (widget.gameData['status'] == 'active' && _hasShownGameEndDialog) {
      _hasShownGameEndDialog = false;
    }

    if (widget.gameData != oldWidget.gameData) {
      if (mounted) setState(() {
        _isSubmittingMove = false;
        _initializeGame();
      });
      _checkForGameEnd();
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (widget.isInvitation || widget.gameData['status'] != 'finished') return;

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
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(dialogTitle),
          content: Text(reason),
          actions: [
            TextButton(
              child: Text(lang.t('btn_ok')),
              onPressed: () {
                Navigator.of(context).pop();
                if (amIWinner) {
                   _resetGameForNewMatch();
                } 
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
    
    final starterId = widget.gameData['winnerId'] ?? widget.gameData['player1Id'];

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
    final currentUserId = _auth.currentUser!.uid;
    final bool isMyTurn = currentTurnPlayerId == currentUserId;
    
    // 1. Menya niba ndi Player 1 (Wowe)
    bool amIPlayer1 = widget.gameData['player1Id'] == currentUserId;

    // 2. Fata amanota nyayo ava muri Firebase
    int p1Score = widget.gameData['player1Score'] ?? 0;
    int p2Score = widget.gameData['player2Score'] ?? 0;

    // 3. Logic itandukanya amanota
    int myScore = amIPlayer1 ? p1Score : p2Score;
    int opponentScore = amIPlayer1 ? p2Score : p1Score;

    Color myColor = isMyTurn ? Colors.green.shade800 : Colors.black87;
    Color oppColor = !isMyTurn ? Colors.orange.shade900 : Colors.black54;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // URUHANDE RWANJE (WEWE)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.t('chat_you'), // "Wewe"
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.grey.shade700
                      ),
                    ),
                    Text(
                      "$myScore", // Amanota yawe
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.w900, 
                        color: myColor
                      ),
                    ),
                  ],
                ),

                // HAGATI (VS)
                Text(
                  "-", 
                  style: TextStyle(fontSize: 20, color: Colors.grey.shade400)
                ),

                // URUHANDE RWA MUGENZI WAWE
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      opponentName.length > 10 
                          ? "${opponentName.substring(0, 8)}..." 
                          : opponentName,
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.grey.shade700
                      ),
                    ),
                    Text(
                      "$opponentScore", // Amanota ye
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.w900, 
                        color: oppColor
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isMyTurn ? Colors.green.shade100 : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text( 
                isMyTurn ? lang.t('dame_your_turn') : lang.t('dame_opponent_turn').replaceAll('{opponentName}', opponentName), 
                style: TextStyle( 
                  fontSize: 14, 
                  fontWeight: FontWeight.bold, 
                  color: isMyTurn ? Colors.green.shade800 : Colors.orange.shade900
                ), 
                overflow: TextOverflow.ellipsis, 
              ),
            ),
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