// lib/dame_game_widget.dart (VERSION 16.2 - FIXED LOCALIZATION & LAYOUT)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:jembe_talk/language_provider.dart';
import 'dame_game_logic.dart';

// ===========================================================================
// 1. TICKER WIDGET (Slower flow & distinct space)
// ===========================================================================
class _DameTickerWidget extends StatefulWidget {
  const _DameTickerWidget();
  @override
  State<_DameTickerWidget> createState() => _DameTickerWidgetState();
}

class _DameTickerWidgetState extends State<_DameTickerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final DatabaseReference _tickerRef = FirebaseDatabase.instance.ref('dame_ticker');

  @override
  void initState() {
    super.initState();
    // ✅ SPEED: 45 seconds for a very calm reading experience
    _controller = AnimationController(duration: const Duration(seconds: 45), vsync: this)..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _tickerRef.onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const SizedBox.shrink();
        final data = snapshot.data!.snapshot.value as Map;
        if (!(data['isActive'] ?? false)) return const SizedBox.shrink();
        final String message = data['message'] ?? "";
        if (message.isEmpty) return const SizedBox.shrink();

        return LayoutBuilder(builder: (context, constraints) {
          double screenWidth = constraints.maxWidth;
          return Container(
            height: 24, width: double.infinity, clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: const Color(0xFF1A0A26),
              border: Border(bottom: BorderSide(color: Colors.purple.shade900, width: 0.8))
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                double xPos = screenWidth - (_controller.value * (screenWidth + 1500));
                return Stack(children: [
                  Positioned(left: xPos, top: 0, bottom: 0, child: Center(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)))),
                ]);
              },
            ),
          );
        });
      },
    );
  }
}

// ===========================================================================
// 2. PIECE WIDGET (Premium 3D Visuals preserved)
// ===========================================================================
class DamePieceWidget extends StatelessWidget {
  final DamePiece piece;
  final double squareSize;
  final bool isSelected;
  final bool mustPlay;
  final VoidCallback? onTap;

  const DamePieceWidget({required Key key, required this.piece, required this.squareSize, this.isSelected = false, this.mustPlay = false, this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isPlayer1 = piece.player == 1;
    final lightPieceGradient = const RadialGradient(colors: [Color(0xFFF5DEB3), Color(0xFFDEB887)], center: Alignment(-0.3, -0.3), radius: 0.8);
    final darkPieceGradient = const RadialGradient(colors: [Color(0xFF8B5A2B), Color(0xFF654321)], center: Alignment(-0.3, -0.3), radius: 0.8);

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: mustPlay ? Colors.red.shade900 : (isSelected ? Colors.yellowAccent : Colors.black54), width: isSelected || mustPlay ? 3.5 : 2),
            gradient: isPlayer1 ? lightPieceGradient : darkPieceGradient,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 3, offset: const Offset(2, 2))]
          ),
          child: Stack(alignment: Alignment.center, children: [
            if (piece.type == DamePieceType.king) Icon(Icons.star, color: isPlayer1 ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.8), size: squareSize * 0.6),
          ]),
        ),
      ),
    );
  }
}

// ===========================================================================
// 3. MAIN GAME WIDGET
// ===========================================================================
class DameGameWidget extends StatefulWidget {
  final String chatRoomID;
  final Map<String, dynamic> gameData;
  final String? opponentDisplayName;
  final bool isInvitation, isWaiting;
  final VoidCallback? onSendInvitation, onCancel, onGameStopped;

  const DameGameWidget({super.key, required this.chatRoomID, required this.gameData, this.opponentDisplayName, this.isInvitation = false, this.isWaiting = false, this.onSendInvitation, this.onCancel, this.onGameStopped});

  @override
  State<DameGameWidget> createState() => _DameGameWidgetState();
}

class _DameGameWidgetState extends State<DameGameWidget> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late DameGameLogic _gameLogic;
  bool _isPlayer1 = true, _isSubmittingMove = false, _isAnimating = false, _hasShownEndDialog = false;
  
  late AudioPlayer _moveP, _capP, _proP, _winP, _loseP;
  late AnimationController _animCtrl;
  late Animation<Offset> _anim;
  DamePiece? _movP; Offset? _movStart; DameMove? _movMove;

  @override
  void initState() {
    super.initState();
    _initGame();
    _moveP = AudioPlayer(); _capP = AudioPlayer(); _proP = AudioPlayer(); _winP = AudioPlayer(); _loseP = AudioPlayer();
    _loadSounds();
    _animCtrl = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    _animCtrl.addStatusListener((s) { if (s == AnimationStatus.completed) _processAfterAnim(); });
  }

  void _initGame() {
    if (!widget.isInvitation) _isPlayer1 = widget.gameData['player1Id'] == _auth.currentUser!.uid;
    _gameLogic = DameGameLogic(myPlayerNumber: _isPlayer1 ? 1 : 2, boardSize: 10);
    final board = widget.gameData['boardState'] ?? widget.gameData['board'];
    if (board != null) _gameLogic.initializeBoard(board);
    _checkEnd();
  }

  Future<void> _loadSounds() async {
    try {
      await _moveP.setAsset('assets/audio/move.mp3'); await _capP.setAsset('assets/audio/capture.mp3');
      await _proP.setAsset('assets/audio/promote.mp3'); await _winP.setAsset('assets/audio/win.mp3');
      await _loseP.setAsset('assets/audio/lose.mp3');
    } catch (_) {}
  }

  @override
  void didUpdateWidget(DameGameWidget old) {
    super.didUpdateWidget(old);
    if (widget.gameData != old.gameData) { setState(() { _isSubmittingMove = false; _initGame(); }); }
  }

  void _checkEnd() {
    if (_hasShownEndDialog || widget.isInvitation || widget.gameData['status'] != 'finished') return;
    _hasShownEndDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lang = Provider.of<LanguageProvider>(context, listen: false);
      final winId = widget.gameData['winnerId'];
      final amIWin = winId == _auth.currentUser!.uid;
      if (winId != null) { if (amIWin) _winP.play(); else _loseP.play(); }
      showDialog(context: context, barrierDismissible: false, builder: (c) => AlertDialog(
        title: Text(winId == null ? lang.t('dame_game_stopped') : (amIWin ? lang.t('dame_you_won') : lang.t('dame_you_lost'))),
        content: Text(widget.gameData['endReason'] ?? ""),
        actions: [TextButton(child: Text(lang.t('btn_ok')), onPressed: () { Navigator.pop(c); _hasShownEndDialog = false; if (amIWin) _resetGameForMatch(); })],
      ));
    });
  }

  bool get _isMyTurn => !_isSubmittingMove && !_isAnimating && !widget.isInvitation && widget.gameData['turn'] == _auth.currentUser!.uid && widget.gameData['status'] == 'active';

  void _onTap(int r, int c) {
    if (!_isMyTurn) return;
    int ar = _isPlayer1 ? r : 9 - r, ac = _isPlayer1 ? c : 9 - c;
    final m = _gameLogic.getMoveTo(ar, ac);
    if (m != null) {
      setState(() {
        _movMove = m; _movP = _gameLogic.board[m.fromRow][m.fromCol]!.copy();
        double sz = (MediaQuery.of(context).size.width - 16) / 10;
        int vfr = _isPlayer1 ? m.fromRow : 9 - m.fromRow, vfc = _isPlayer1 ? m.fromCol : 9 - m.fromCol;
        int vtr = _isPlayer1 ? m.toRow : 9 - m.toRow, vtc = _isPlayer1 ? m.toCol : 9 - m.toCol;
        _movStart = Offset(vfc * sz, vfr * sz);
        _anim = Tween<Offset>(begin: Offset.zero, end: Offset(vtc * sz, vtr * sz) - _movStart!).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
        _isAnimating = true; _animCtrl.forward(from: 0.0);
      });
    } else { _gameLogic.handleTap(ar, ac); setState(() {}); }
  }

  void _processAfterAnim() {
    if (_movMove == null) return;
    final m = _movMove!; final wasCap = m.isCapture;
    final isKing = (_movP!.type == DamePieceType.man) && ((_gameLogic.myPlayerNumber == 1 && m.toRow == 0) || (_gameLogic.myPlayerNumber == 2 && m.toRow == 9));
    bool end = _gameLogic.handleTap(m.toRow, m.toCol);
    if (isKing) _proP.play(); else if (wasCap) _capP.play(); else _moveP.play();
    setState(() { _isAnimating = false; _movP = null; _movMove = null; });
    if (end) _submitTurn();
  }

  Future<void> _submitTurn() async {
    setState(() => _isSubmittingMove = true);
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final nextId = widget.gameData['turn'] == widget.gameData['player1Id'] ? widget.gameData['player2Id'] : widget.gameData['player1Id'];
    DameGameLogic temp = DameGameLogic(myPlayerNumber: (nextId == widget.gameData['player1Id'] ? 1 : 2), boardSize: 10);
    temp.initializeBoard(_gameLogic.board.map((r) => r.map((p) => p == null ? null : {'player': p.player, 'type': p.type.name}).toList()).toList());
    if (!temp.hasAnyValidMoves(temp.myPlayerNumber)) { _declareWinner(_auth.currentUser!.uid, lang.t('dame_win_reason_no_moves')); }
    else {
       final boardMaps = {};
       for (int i = 0; i < 10; i++) boardMaps[i.toString()] = _gameLogic.board[i].map((p) => p == null ? null : {'player': p.player, 'type': p.type.name}).toList();
       await _firestore.collection('games').doc(widget.chatRoomID).update({'boardState': boardMaps, 'turn': nextId});
    }
  }

  Future<void> _declareWinner(String wid, String res) async {
    int s1 = widget.gameData['player1Score'] ?? 0, s2 = widget.gameData['player2Score'] ?? 0;
    if (wid == widget.gameData['player1Id']) s1++; else if (wid == widget.gameData['player2Id']) s2++;
    await _firestore.collection('games').doc(widget.chatRoomID).update({'status': 'finished', 'winnerId': wid, 'endReason': res, 'player1Score': s1, 'player2Score': s2});
  }

  Future<void> _resetGameForMatch() async {
    final b = {};
    for (int r = 0; r < 10; r++) b[r.toString()] = List.generate(10, (c) => ((r + c) % 2 != 0) ? (r < 4 ? {'player': 2, 'type': 'man'} : (r > 5 ? {'player': 1, 'type': 'man'} : null)) : null);
    await _firestore.collection('games').doc(widget.chatRoomID).update({'boardState': b, 'status': 'active', 'turn': widget.gameData['winnerId'] ?? widget.gameData['player1Id'], 'winnerId': null, 'endReason': null});
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    bool active = widget.gameData['status'] == 'active';
    
    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        children: [
          // 1. TICKER (At the top, push everything else down)
          if (!widget.isInvitation) const _DameTickerWidget(),

          // 2. HEADER (Names/Score)
          if (!widget.isInvitation && active) 
            _buildHeader(widget.gameData['turn'] ?? '', widget.opponentDisplayName ?? "Opponent")
          else if (widget.isInvitation)
            const SizedBox(height: 10)
          else 
            const SizedBox(height: 55),

          // 3. BOARD
          AspectRatio(aspectRatio: 1.0, child: Container(margin: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2.5)), child: LayoutBuilder(builder: (ctx, cons) {
            double sz = cons.maxWidth / 10;
            return Stack(children: [
              for (int i = 0; i < 100; i++) Positioned(top: (i ~/ 10) * sz, left: (i % 10) * sz, child: Container(width: sz, height: sz, color: ((i ~/ 10) + (i % 10)) % 2 == 0 ? const Color(0xFFD2B48C) : const Color(0xFF8B4513))),
              ..._indicators(sz), ..._pieces(sz),
              if (_isAnimating && _movP != null && _movStart != null) Positioned(top: _movStart!.dy, left: _movStart!.dx, child: AnimatedBuilder(animation: _anim, builder: (c, ch) => Transform.translate(offset: _anim.value, child: ch), child: DamePieceWidget(key: const ValueKey('anim_piece'), piece: _movP!, squareSize: sz))),
            ]);
          }))),

          // 4. FOOTER
          if (!widget.isInvitation && active) _buildFooter(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  List<Widget> _pieces(double sz) {
    final List<Widget> p = [];
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 10; c++) {
        if (_isAnimating && r == _movMove?.fromRow && c == _movMove?.fromCol) continue;
        final pc = _gameLogic.board[r][c];
        if (pc != null) {
          final vr = _isPlayer1 || widget.isInvitation ? r : 9 - r, vc = _isPlayer1 || widget.isInvitation ? c : 9 - c;
          p.add(Positioned(top: vr * sz, left: vc * sz, child: SizedBox(width: sz, height: sz, child: DamePieceWidget(key: ValueKey('p$r$c'), piece: pc, squareSize: sz, isSelected: (_gameLogic.selectedRow == r && _gameLogic.selectedCol == c), mustPlay: _gameLogic.forcedCaptureMoves.any((m) => m.fromRow == r && m.fromCol == c) && !_gameLogic.isMultiJump, onTap: () => _onTap(vr, vc)))));
        }
      }
    }
    return p;
  }

  List<Widget> _indicators(double sz) {
    if (_isAnimating) return [];
    return _gameLogic.possibleMoves.map((m) {
      final vr = _isPlayer1 || widget.isInvitation ? m.toRow : 9 - m.toRow, vc = _isPlayer1 || widget.isInvitation ? m.toCol : 9 - m.toCol;
      return Positioned(top: vr * sz, left: vc * sz, child: GestureDetector(onTap: () => _onTap(vr, vc), child: SizedBox(width: sz, height: sz, child: Center(child: Container(width: sz * 0.4, height: sz * 0.4, decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.6), shape: BoxShape.circle))))));
    }).toList();
  }

  Widget _buildHeader(String tid, String oppName) {
    final lang = Provider.of<LanguageProvider>(context);
    bool myT = tid == _auth.currentUser!.uid, amI1 = widget.gameData['player1Id'] == _auth.currentUser!.uid;
    int sM = amI1 ? (widget.gameData['player1Score'] ?? 0) : (widget.gameData['player2Score'] ?? 0);
    int sO = amI1 ? (widget.gameData['player2Score'] ?? 0) : (widget.gameData['player1Score'] ?? 0);
    return Padding(padding: const EdgeInsets.fromLTRB(10, 5, 10, 8), child: Column(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(children: [const Text("YOU", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), Text("$sM", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: myT ? Colors.green.shade800 : Colors.black87))]),
        const Text("-", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Column(children: [Text(oppName.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), Text("$sO", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: !myT ? Colors.orange.shade900 : Colors.black54))]),
      ])),
      const SizedBox(height: 4),
      Text(myT ? lang.t('dame_your_turn') : lang.t('dame_opponent_turn').replaceFirst('{opponentName}', oppName), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: myT ? Colors.green.shade700 : Colors.orange.shade800)),
    ]));
  }

  Widget _buildFooter() {
    final lang = Provider.of<LanguageProvider>(context);
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      TextButton.icon(onPressed: () async {
        final b = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: Text(lang.t('dame_stop_game_title')), 
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(lang.t('dialog_no'))), 
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(lang.t('dialog_yes')))
          ]));
        if (b == true) { widget.onGameStopped?.call(); await _firestore.collection('games').doc(widget.chatRoomID).delete(); }
      }, icon: const Icon(Icons.close, size: 18), label: Text(lang.t('dame_stop_game_button'))),
      ElevatedButton.icon(onPressed: () async {
        final b = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: Text(lang.t('dame_resign_title')), 
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(lang.t('dialog_no'))), 
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(lang.t('dialog_yes'))) // ✅ Updated label
          ]));
        if (b == true) await _declareWinner(_isPlayer1 ? widget.gameData['player2Id'] : widget.gameData['player1Id'], lang.t('dame_win_reason_resign'));
      }, icon: const Icon(Icons.flag, size: 18), label: Text(lang.t('dame_resign_button')), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white)),
    ]);
  }

  @override
  void dispose() { _animCtrl.dispose(); _moveP.dispose(); _capP.dispose(); _proP.dispose(); _winP.dispose(); _loseP.dispose(); super.dispose(); }
}