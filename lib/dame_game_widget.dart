// lib/dame_game_widget.dart (YAKOSOWE BURUNDU KURI 10x10)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dame_game_logic.dart';

class DamePieceWidget extends StatelessWidget {
  final DamePiece piece;
  final double squareSize;
  final bool isSelected;
  final bool mustPlay;
  final VoidCallback onTap;

  const DamePieceWidget({
    required Key key,
    required this.piece,
    required this.squareSize,
    required this.isSelected,
    required this.mustPlay,
    required this.onTap,
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
      gradient: RadialGradient(
        colors: [const Color(0xFFF5DEB3), const Color(0xFFDEB887)], // Wheat -> BurlyWood
        center: const Alignment(-0.3, -0.3),
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

class _DameGameWidgetState extends State<DameGameWidget> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late DameGameLogic _gameLogic;
  bool _isPlayer1 = true;
  DameMove? _lastMove;
  bool _isSubmittingMove = false;

  late AudioPlayer _movePlayer;
  late AudioPlayer _capturePlayer;
  late AudioPlayer _promotePlayer;
  late AudioPlayer _winPlayer;
  late AudioPlayer _losePlayer;

  @override
  void initState() {
    super.initState();
    _initializeGame();
    _checkForGameEnd();

    _movePlayer = AudioPlayer();
    _capturePlayer = AudioPlayer();
    _promotePlayer = AudioPlayer();
    _winPlayer = AudioPlayer();
    _losePlayer = AudioPlayer();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    try {
      await _movePlayer.setAsset('assets/audio/move.mp3');
      await _capturePlayer.setAsset('assets/audio/capture.mp3');
      await _promotePlayer.setAsset('assets/audio/promote.mp3');
      await _winPlayer.setAsset('assets/audio/win.mp3');
      await _losePlayer.setAsset('assets/audio/lose.mp3');
    } catch (e) {
      debugPrint("Habaye ikosa mu gutanguza amajwi: $e");
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
    _movePlayer.dispose();
    _capturePlayer.dispose();
    _promotePlayer.dispose();
    _winPlayer.dispose();
    _losePlayer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DameGameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gameData != oldWidget.gameData) {
      setState(() {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (widget.isInvitation || widget.gameData['status'] != 'finished') return;

      final winnerId = widget.gameData['winnerId'];
      final reason = widget.gameData['endReason'] ?? 'Umukino warangiye.';
      final amIWinner = winnerId == _auth.currentUser!.uid;
      
      String dialogTitle;
      
      if (winnerId == null) {
        dialogTitle = "Umukino Wahagaritswe";
      } else {
        if (amIWinner) {
          dialogTitle = "Watsinze! 🎉";
          _playSound(_winPlayer);
        } else {
          dialogTitle = "Watsinzwe.";
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
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                if (reason.contains("yatanze umukono")) {
                  if (amIWinner) {
                    _resetGameForNewMatch();
                  }
                } else {
                   if(amIWinner) {
                    _firestore.collection('games').doc(widget.chatRoomID).delete();
                  }
                }
              },
            ),
          ],
        ),
      );
    });
  }

  bool get _isMyTurn => !_isSubmittingMove && !widget.isInvitation && widget.gameData['turn'] == _auth.currentUser!.uid && widget.gameData['status'] == 'active';

  void _handleTap(int tappedRow, int tappedCol) {
    if (!_isMyTurn) return;

    int actualRow = _isPlayer1 ? tappedRow : 9 - tappedRow;
    int actualCol = _isPlayer1 ? tappedCol : 9 - tappedCol;

    final move = _gameLogic.getMoveTo(actualRow, actualCol);
    
    if (move != null) {
      final wasCapture = move.jumpedRow != null;
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
      
      setState(() {
        _lastMove = move;
      }); 

      if (turnEnded) {
        _endTurn();
      }
    } else {
       _gameLogic.handleTap(actualRow, actualCol);
       setState(() {});
    }
  }

  Future<void> _endTurn() async {
    setState(() { _isSubmittingMove = true; });
    final newBoard = _gameLogic.board;
    final nextPlayerId = widget.gameData['turn'] == widget.gameData['player1Id'] ? widget.gameData['player2Id'] : widget.gameData['player1Id'];
    final int nextPlayerNumber = (nextPlayerId == widget.gameData['player1Id']) ? 1 : 2;

    DameGameLogic tempLogic = DameGameLogic(myPlayerNumber: nextPlayerNumber, boardSize: 10);
    final List<dynamic> boardAsListOfMaps = newBoard.map((row) => row.map((piece) => piece == null ? null : {'player': piece.player, 'type': piece.type.name}).toList()).toList();
    tempLogic.initializeBoard(boardAsListOfMaps);
    if (!tempLogic.hasAnyValidMoves(nextPlayerNumber)) {
      await _declareWinner(_auth.currentUser!.uid, "Yatsinze kuko uwo bakina ata mwanya agifise wo gukina.");
    } else {
      await _updateGameInFirestore(newBoard);
    }
  }

  Future<void> _handleResign() async {
    if (widget.isInvitation) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Tanga Umukino?"),
        content: const Text("Wemeye gutsindwa? Ibi bizoha mugenzi wawe intsinzi."),
        actions: <Widget>[
          TextButton( child: const Text("Oya"), onPressed: () => Navigator.of(context).pop(false), ),
          TextButton( child: const Text("Ego, Natsinzwe"), onPressed: () => Navigator.of(context).pop(true), style: TextButton.styleFrom(foregroundColor: Colors.red), ),
        ],
      ),
    );
    if (confirm == true) {
      final opponentId = _isPlayer1 ? widget.gameData['player2Id'] : widget.gameData['player1Id'];
      await _declareWinner(opponentId, "Yatsinze kuko uwo bakina yatanze umukono.");
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
    if (widget.isInvitation) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Hagarika Umukino?"),
        content: const Text("Vyukuri uhagaritse umukino?"),
        actions: <Widget>[
          TextButton( child: const Text("Oya"), onPressed: () => Navigator.of(context).pop(false), ),
          TextButton( child: const Text("Ego"), onPressed: () => Navigator.of(context).pop(true), style: TextButton.styleFrom(foregroundColor: Colors.red), ),
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
    await _firestore.collection('games').doc(widget.chatRoomID).update({
      'status': 'finished', 'winnerId': winnerId, 'endReason': reason,
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
    String currentTurnPlayerId = widget.gameData['turn'] ?? '';
    String opponentName = widget.opponentDisplayName ?? 'Uwo mukina';
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
        final piece = _gameLogic.board[r][c];
        if (piece != null) {
          final visualRow = _isPlayer1 || widget.isInvitation ? r : 9 - r;
          final visualCol = _isPlayer1 || widget.isInvitation ? c : 9 - c;
          bool isSelected = (_gameLogic.selectedRow == r && _gameLogic.selectedCol == c);
          bool mustPlay = _gameLogic.forcedCaptureMoves.any((m) => m.fromRow == r && m.fromCol == c) && !_gameLogic.isMultiJump;
          
          pieces.add(
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
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
    for (final move in _gameLogic.possibleMoves) {
      final visualRow = _isPlayer1 || widget.isInvitation ? move.toRow : 9 - move.toRow;
      final visualCol = _isPlayer1 || widget.isInvitation ? move.toCol : 9 - move.toCol;
      indicators.add( Positioned( top: visualRow * squareSize, left: visualCol * squareSize, child: GestureDetector( onTap: () => _handleTap(visualRow, visualCol), child: SizedBox( width: squareSize, height: squareSize, child: Center( child: Container( width: squareSize * 0.4, height: squareSize * 0.4, decoration: BoxDecoration( color: Colors.green.withOpacity(0.5), shape: BoxShape.circle, ), ), ), ), ), ), );
    }
    return indicators;
  }

  Widget _buildActiveGameHeader(String currentTurnPlayerId, String opponentName) {
    final bool isMyTurn = currentTurnPlayerId == _auth.currentUser?.uid;
    String displayText;
    if (isMyTurn) { displayText = "Ni wewe ukina."; } else { displayText = "Rindira, $opponentName niwe akina."; }
    return SizedBox( height: 48, child: Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Center( child: Text( displayText, style: TextStyle( fontSize: 16, fontWeight: FontWeight.bold, color: isMyTurn ? Colors.green.shade700 : Colors.orange.shade800), overflow: TextOverflow.ellipsis, ), ), ), );
  }
  
  Widget _buildActiveGameFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          OutlinedButton.icon(
            onPressed: _handleStopGame,
            icon: const Icon(Icons.close),
            label: const Text("Hagarika Umukino"),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade800,
              side: BorderSide(color: Colors.grey.shade400),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _handleResign,
            icon: const Icon(Icons.flag),
            label: const Text("Ndatsinzwe"),
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
    return SizedBox( height: 48, child: widget.isWaiting ? const Row( mainAxisAlignment: MainAxisAlignment.center, children: [ SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text("Ubutumire bwarungitswe. Rindira...", style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic)), ], ) 
    : const Center( child: Text("Rungika Ubutumire bw'umukino", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), ), );
  }

  Widget _buildInvitationButtons() {
    return Padding( padding: const EdgeInsets.only(top: 10, bottom: 10), child: Row( mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [ ElevatedButton.icon( onPressed: widget.onCancel, icon: const Icon(Icons.close), label: Text(widget.isWaiting ? "Hagarika Ubutumire" : "Hagarika"), style: ElevatedButton.styleFrom( backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)) ), ), 
    if (!widget.isWaiting) ElevatedButton.icon( onPressed: widget.onSendInvitation, icon: const Icon(Icons.send), 
    label: const Text("Mubwire mukine"), style: ElevatedButton.styleFrom( backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)) ), ), ], ), );
  }
}