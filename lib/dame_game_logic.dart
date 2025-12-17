// lib/dame_game_logic.dart
// VERSION 13.9: Logic ikosoye 100% (Strict Capture & Anti-Ghosting)

import 'dart:math';

enum DamePieceType { man, king }

class DamePiece {
  int player; // 1 or 2
  DamePieceType type;
  DamePiece({required this.player, required this.type});
  
  // Dukora kopi kugira ngo simulation itangiza igikinisho nyirizina
  DamePiece copy() => DamePiece(player: player, type: type);
}

class DameMove {
  final int fromRow;
  final int fromCol;
  final int toRow;
  final int toCol;
  final List<List<int>> jumped; // Urutonde rwa [r,c] rw'ibyafashwe

  DameMove({
    required this.fromRow,
    required this.fromCol,
    required this.toRow,
    required this.toCol,
    List<List<int>>? jumped,
  }) : jumped = jumped ?? [];

  bool get isCapture => jumped.isNotEmpty;
  int get captureCount => jumped.length;

  int? get jumpedRow => jumped.isNotEmpty ? jumped.first[0] : null;
  int? get jumpedCol => jumped.isNotEmpty ? jumped.first[1] : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DameMove &&
          runtimeType == other.runtimeType &&
          fromRow == other.fromRow &&
          fromCol == other.fromCol &&
          toRow == other.toRow &&
          toCol == other.toCol &&
          jumped.length == other.jumped.length; // Simplified check for speed

  @override
  int get hashCode => fromRow.hashCode ^ fromCol.hashCode ^ toRow.hashCode ^ toCol.hashCode;
}

class _CaptureSeqResult {
  final List<DameMove> seq; 
  final int totalCaptured; 
  final int capturedKings; 

  _CaptureSeqResult(this.seq, this.totalCaptured, this.capturedKings);
}

class DameGameLogic {
  final int myPlayerNumber;
  final int boardSize;
  late List<List<DamePiece?>> board;

  int? selectedRow;
  int? selectedCol;
  bool isMultiJump = false;

  List<DameMove> possibleMoves = [];
  List<DameMove> forcedCaptureMoves = [];

  final Map<String, List<_CaptureSeqResult>> _memoCaptures = {};

  DameGameLogic({required this.myPlayerNumber, this.boardSize = 10}) {
    board = List.generate(boardSize, (_) => List.generate(boardSize, (_) => null));
  }
  
  void initializeBoard(dynamic boardData) {
    board = List.generate(boardSize, (_) => List.generate(boardSize, (_) => null));
    if (boardData == null) return;

    void parseCell(int r, int c, dynamic cell) {
      if (cell is Map && cell['player'] != null) {
        final player = cell['player'] as int;
        // Strict Type Parsing: Byirinda ko 'King' na 'king' bitera ikibazo
        final typeStr = (cell['type'] ?? 'man').toString().toLowerCase();
        final type = typeStr == 'king' ? DamePieceType.king : DamePieceType.man;
        board[r][c] = DamePiece(player: player, type: type);
      }
    }

    if (boardData is Map) {
      for (int r = 0; r < boardSize; r++) {
        final rowVal = boardData[r.toString()];
        if (rowVal is List) {
          for (int c = 0; c < rowVal.length && c < boardSize; c++) {
            parseCell(r, c, rowVal[c]);
          }
        }
      }
    } else if (boardData is List) {
       for (int r = 0; r < boardData.length && r < boardSize; r++) {
        final rowVal = boardData[r];
        if (rowVal is List) {
          for (int c = 0; c < rowVal.length && c < boardSize; c++) {
            parseCell(r, c, rowVal[c]);
          }
        }
      }
    }
    _recomputeAllMoves();
  }

  void _recomputeAllMoves() {
    forcedCaptureMoves = _allForcedCapturesForPlayer(myPlayerNumber);
    possibleMoves = [];
  }

  DameMove? getMoveTo(int toRow, int toCol) {
    try {
      return possibleMoves.firstWhere((m) => m.toRow == toRow && m.toCol == toCol);
    } catch (e) {
      return null;
    }
  }

  bool handleTap(int tappedRow, int tappedCol) {
    if (isMultiJump && selectedRow != null && selectedCol != null) {
      final move = getMoveTo(tappedRow, tappedCol);
      if (move != null) {
        _applyMove(move, promoteOnLand: false);
        
        final afterCaptures = _captureSequencesFromSquare(move.toRow, move.toCol, board[move.toRow][move.toCol]!, visitedJumps: []);
        
        if (afterCaptures.isNotEmpty) {
          possibleMoves = afterCaptures.map((seqRes) => seqRes.seq.first).toList();
          selectedRow = move.toRow;
          selectedCol = move.toCol;
          isMultiJump = true;
          return false; 
        } else {
          _promoteIfNeeded(move.toRow, move.toCol);
          _resetSelection();
          return true; 
        }
      }
      return false; 
    }

    final tappedPiece = board[tappedRow][tappedCol];

    if (tappedPiece != null && tappedPiece.player == myPlayerNumber) {
      selectedRow = tappedRow;
      selectedCol = tappedCol;
      _computePossibleMovesForSelection(tappedRow, tappedCol);
      return false;
    }

    if (selectedRow != null) {
      final move = getMoveTo(tappedRow, tappedCol);
      if (move != null) {
        final wasCapture = move.isCapture;
        _applyMove(move, promoteOnLand: !wasCapture);

        if (wasCapture) {
          final afterCaptures = _captureSequencesFromSquare(move.toRow, move.toCol, board[move.toRow][move.toCol]!, visitedJumps: []);
          if (afterCaptures.isNotEmpty) {
            isMultiJump = true;
            selectedRow = move.toRow;
            selectedCol = move.toCol;
            possibleMoves = afterCaptures.map((seqRes) => seqRes.seq.first).toList();
            return false;
          } else {
             _promoteIfNeeded(move.toRow, move.toCol);
          }
        }
        
        _resetSelection();
        return true; 
      }
    }
    
    _resetSelection();
    return false;
  }

  void _resetSelection() {
    selectedRow = null;
    selectedCol = null;
    isMultiJump = false;
    possibleMoves = [];
  }

  void _applyMove(DameMove move, {bool promoteOnLand = true}) {
    final piece = board[move.fromRow][move.fromCol];
    if (piece == null) return;
    
    board[move.fromRow][move.fromCol] = null;
    for (final j in move.jumped) {
      board[j[0]][j[1]] = null;
    }
    board[move.toRow][move.toCol] = piece;

    if (promoteOnLand) {
      _promoteIfNeeded(move.toRow, move.toCol);
    }
  }

  void _promoteIfNeeded(int r, int c) {
    final piece = board[r][c];
    if (piece == null || piece.type == DamePieceType.king) return;
    if ((piece.player == 1 && r == 0) || (piece.player == 2 && r == boardSize - 1)) {
      piece.type = DamePieceType.king;
    }
  }

  void _computePossibleMovesForSelection(int r, int c) {
    final piece = board[r][c];
    if (piece == null) return;
    
    _memoCaptures.clear();
    
    final allPlayerCaptures = _allCaptureSequencesForPlayer(myPlayerNumber);

    if (allPlayerCaptures.isNotEmpty) {
      int globalMaxCaptured = 0;
      int globalMaxCapturedKings = 0;
      for (final seq in allPlayerCaptures) {
        if (seq.totalCaptured > globalMaxCaptured) {
          globalMaxCaptured = seq.totalCaptured;
          globalMaxCapturedKings = seq.capturedKings;
        } else if (seq.totalCaptured == globalMaxCaptured && seq.capturedKings > globalMaxCapturedKings) {
          globalMaxCapturedKings = seq.capturedKings;
        }
      }

      final selectedPieceSeqs = allPlayerCaptures.where((s) => s.seq.first.fromRow == r && s.seq.first.fromCol == c).toList();
      
      final allowedSeqs = selectedPieceSeqs.where((s) => s.totalCaptured == globalMaxCaptured && s.capturedKings == globalMaxCapturedKings).toList();
      
      possibleMoves = allowedSeqs.map((s) => s.seq.first).toSet().toList();
      
      forcedCaptureMoves = allPlayerCaptures
          .where((s) => s.totalCaptured == globalMaxCaptured && s.capturedKings == globalMaxCapturedKings)
          .map((s) => s.seq.first)
          .toSet()
          .toList();

    } else {
      possibleMoves = _normalMovesForPiece(r, c, piece);
      forcedCaptureMoves = [];
    }
  }

  List<DameMove> _normalMovesForPiece(int r, int c, DamePiece piece) {
    final moves = <DameMove>[];
    if (piece.type == DamePieceType.man) {
      final forwardDir = piece.player == 1 ? -1 : 1;
      for (final dc in [-1, 1]) {
        final nr = r + forwardDir;
        final nc = c + dc;
        if (_inBounds(nr, nc) && board[nr][nc] == null) {
          moves.add(DameMove(fromRow: r, fromCol: c, toRow: nr, toCol: nc));
        }
      }
    } else { // King
      final dirs = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
      for (final d in dirs) {
        int nr = r + d[0];
        int nc = c + d[1];
        while (_inBounds(nr, nc) && board[nr][nc] == null) {
          moves.add(DameMove(fromRow: r, fromCol: c, toRow: nr, toCol: nc));
          nr += d[0];
          nc += d[1];
        }
      }
    }
    return moves;
  }

  bool _inBounds(int r, int c) => r >= 0 && c >= 0 && r < boardSize && c < boardSize;

  List<DameMove> _allForcedCapturesForPlayer(int player) {
    return _allCaptureSequencesForPlayer(player).map((s) => s.seq.first).toSet().toList();
  }

  List<_CaptureSeqResult> _allCaptureSequencesForPlayer(int player) {
    _memoCaptures.clear();
    final results = <_CaptureSeqResult>[];
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        final p = board[r][c];
        if (p != null && p.player == player) {
          results.addAll(_captureSequencesFromSquare(r, c, p, visitedJumps: []));
        }
      }
    }
    return results;
  }

  List<_CaptureSeqResult> _captureSequencesFromSquare(int r, int c, DamePiece piece, {required List<List<int>> visitedJumps}) {
    final key = '$r-$c-${piece.type}-${visitedJumps.map((e) => '${e[0]}-${e[1]}').join(',')}';
    if (_memoCaptures.containsKey(key)) {
      return _memoCaptures[key]!;
    }

    final sequences = <_CaptureSeqResult>[];
    final directions = [[-1, -1], [-1, 1], [1, -1], [1, 1]];

    // --- MAN LOGIC ---
    if (piece.type == DamePieceType.man) {
      for (final d in directions) {
        final jumpedR = r + d[0];
        final jumpedC = c + d[1];
        final landR = r + 2 * d[0];
        final landC = c + 2 * d[1];

        if (visitedJumps.any((j) => j[0] == jumpedR && j[1] == jumpedC)) continue;

        if (_inBounds(landR, landC)) {
          final mid = board[jumpedR][jumpedC];
          if (mid != null && mid.player != piece.player && board[landR][landC] == null) {
            
            // SIMULATION (With Copy to prevent reference mutation bugs)
            final movingPiece = piece.copy(); // Use a copy for simulation!
            
            board[r][c] = null;
            board[jumpedR][jumpedC] = null; 
            board[landR][landC] = movingPiece;
            
            final currentStep = DameMove(fromRow: r, fromCol: c, toRow: landR, toCol: landC, jumped: [[jumpedR, jumpedC]]);
            final capturedKingCount = mid.type == DamePieceType.king ? 1 : 0;
            
            final further = _captureSequencesFromSquare(landR, landC, movingPiece, visitedJumps: [...visitedJumps, [jumpedR, jumpedC]]);

            if (further.isEmpty) {
              sequences.add(_CaptureSeqResult([currentStep], 1, capturedKingCount));
            } else {
              for (final f in further) {
                sequences.add(_CaptureSeqResult(
                  [currentStep, ...f.seq],
                  1 + f.totalCaptured,
                  capturedKingCount + f.capturedKings
                ));
              }
            }
            
            // RESTORE
            board[r][c] = piece; // Restore original
            board[jumpedR][jumpedC] = mid;
            board[landR][landC] = null;
          }
        }
      }
    } 
    // --- KING LOGIC (Strict) ---
    else { 
      for (final d in directions) {
        int scanR = r + d[0];
        int scanC = c + d[1];
        
        DamePiece? enemyFound;
        int enemyR = -1;
        int enemyC = -1;

        // 1. Scan for the first piece
        while (_inBounds(scanR, scanC)) {
          final p = board[scanR][scanC];
          if (p != null) {
            if (p.player == piece.player) {
              break; // Blocked by own piece
            } else {
              enemyFound = p;
              enemyR = scanR;
              enemyC = scanC;
              break; // Found enemy
            }
          }
          scanR += d[0];
          scanC += d[1];
        }

        if (enemyFound == null) continue;

        // 2. Check if already jumped
        if (visitedJumps.any((j) => j[0] == enemyR && j[1] == enemyC)) continue;

        // 3. Scan Landing Spots
        int landR = enemyR + d[0];
        int landC = enemyC + d[1];

        while (_inBounds(landR, landC) && board[landR][landC] == null) {
          // SIMULATION (With Copy)
          final movingPiece = piece.copy(); 

          board[r][c] = null;
          board[enemyR][enemyC] = null;
          board[landR][landC] = movingPiece;

          final currentStep = DameMove(fromRow: r, fromCol: c, toRow: landR, toCol: landC, jumped: [[enemyR, enemyC]]);
          final capturedKingCount = enemyFound.type == DamePieceType.king ? 1 : 0;
          
          final further = _captureSequencesFromSquare(landR, landC, movingPiece, visitedJumps: [...visitedJumps, [enemyR, enemyC]]);

          if (further.isEmpty) {
            sequences.add(_CaptureSeqResult([currentStep], 1, capturedKingCount));
          } else {
            for (final f in further) {
              sequences.add(_CaptureSeqResult(
                [currentStep, ...f.seq],
                1 + f.totalCaptured,
                capturedKingCount + f.capturedKings
              ));
            }
          }

          // RESTORE
          board[r][c] = piece;
          board[enemyR][enemyC] = enemyFound;
          board[landR][landC] = null;

          landR += d[0];
          landC += d[1];
        }
      }
    }

    _memoCaptures[key] = sequences;
    return sequences;
  }

  bool hasAnyValidMoves(int playerNumber) {
    if (_allCaptureSequencesForPlayer(playerNumber).isNotEmpty) return true;
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        final p = board[r][c];
        if (p != null && p.player == playerNumber) {
          if (_normalMovesForPiece(r, c, p).isNotEmpty) return true;
        }
      }
    }
    return false;
  }
}