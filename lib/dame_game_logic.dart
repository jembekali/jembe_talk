// lib/dame_game_logic.dart (YAKOSOWE KURI 10x10)

import 'dart:math';

enum DamePieceType { man, king }

class DamePiece {
  final int player;
  DamePieceType type;
  DamePiece({required this.player, this.type = DamePieceType.man});
}

class DameMove {
  final int fromRow, fromCol, toRow, toCol;
  final int? jumpedRow, jumpedCol;
  DameMove(this.fromRow, this.fromCol, this.toRow, this.toCol, [this.jumpedRow, this.jumpedCol]);
}

class DameGameLogic {
  List<List<DamePiece?>> board = [];
  int? selectedRow, selectedCol;
  bool isMultiJump = false;
  List<DameMove> possibleMoves = [];
  List<DameMove> forcedCaptureMoves = [];
  
  final int myPlayerNumber;
  final int boardSize; 

  DameGameLogic({required this.myPlayerNumber, this.boardSize = 10});

  void initializeBoard(dynamic boardData) {
    List<List<dynamic>> tempList = List.generate(boardSize, (_) => List.filled(boardSize, null));

    if (boardData is List) {
      for (int i = 0; i < boardData.length && i < boardSize; i++) {
        if (boardData[i] is List) { tempList[i] = List.from(boardData[i]); }
      }
    } else if (boardData is Map) {
      for (int i = 0; i < boardSize; i++) {
        if (boardData[i.toString()] is List) { tempList[i] = List.from(boardData[i.toString()]); }
      }
    }

    board = tempList.map((row) => 
      row.map((pieceData) {
        if (pieceData is Map<String, dynamic>) {
          return DamePiece(
            player: pieceData['player'],
            type: DamePieceType.values.firstWhere( (e) => e.name == pieceData['type'], orElse: () => DamePieceType.man ),
          );
        }
        return null;
      }).toList()
    ).toList();
    
    checkForcedMoves();
  }

  void checkForcedMoves() {
    List<DameMove> allCaptures = _getAllCaptureMovesForPlayer(myPlayerNumber);

    if (allCaptures.isEmpty) {
      forcedCaptureMoves = [];
      return;
    }

    Map<String, int> captureChainLengths = {};
    Map<String, bool> isKingMap = {};

    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        DamePiece? piece = board[r][c];
        if (piece != null && piece.player == myPlayerNumber) {
          int chainLength = _calculateMaxCaptureChain(r, c, board);
          if (chainLength > 0) {
            String pieceId = "$r-$c";
            captureChainLengths[pieceId] = chainLength;
            isKingMap[pieceId] = piece.type == DamePieceType.king;
          }
        }
      }
    }

    if (captureChainLengths.isEmpty) {
      forcedCaptureMoves = allCaptures;
      return;
    }
    
    int maxKingCaptures = 0;
    int maxManCaptures = 0;

    captureChainLengths.forEach((pieceId, length) {
      if (isKingMap[pieceId] == true) {
        if (length > maxKingCaptures) maxKingCaptures = length;
      } else {
        if (length > maxManCaptures) maxManCaptures = length;
      }
    });

    List<DameMove> finalForcedMoves = [];
    
    if (maxManCaptures > maxKingCaptures) {
      finalForcedMoves = _getMovesForPiecesWithMaxLength(captureChainLengths, maxManCaptures, false, isKingMap);
    } else if (maxKingCaptures > 0) {
      finalForcedMoves = _getMovesForPiecesWithMaxLength(captureChainLengths, maxKingCaptures, true, isKingMap);
    } else {
      finalForcedMoves = _getMovesForPiecesWithMaxLength(captureChainLengths, maxManCaptures, false, isKingMap);
    }

    forcedCaptureMoves = finalForcedMoves;
  }
  
  List<DameMove> _getMovesForPiecesWithMaxLength(Map<String, int> lengths, int maxLength, bool isKing, Map<String, bool> isKingMap) {
      List<DameMove> moves = [];
      lengths.forEach((pieceId, length) {
        if (length == maxLength && isKingMap[pieceId] == isKing) {
          var parts = pieceId.split('-');
          int r = int.parse(parts[0]);
          int c = int.parse(parts[1]);
          moves.addAll(_getCaptureMovesForPiece(r, c, board[r][c]!, myPlayerNumber));
        }
      });
      return moves;
  }
  
  int _calculateMaxCaptureChain(int startRow, int startCol, List<List<DamePiece?>> currentBoard) {
      DamePiece? piece = currentBoard[startRow][startCol];
      if (piece == null) return 0;

      List<DameMove> firstLevelCaptures = _getCaptureMovesForPiece(startRow, startCol, piece, piece.player);
      if (firstLevelCaptures.isEmpty) {
          return 0;
      }

      int maxCaptures = 0;
      for (DameMove move in firstLevelCaptures) {
          List<List<DamePiece?>> nextBoard = currentBoard.map((row) => List<DamePiece?>.from(row)).toList();
          
          nextBoard[move.toRow][move.toCol] = piece;
          nextBoard[move.fromRow][move.fromCol] = null;
          nextBoard[move.jumpedRow!][move.jumpedCol!] = null;
          
          int capturesInThisChain = 1 + _calculateMaxCaptureChain(move.toRow, move.toCol, nextBoard);
          if (capturesInThisChain > maxCaptures) {
              maxCaptures = capturesInThisChain;
          }
      }
      return maxCaptures;
  }

  DameMove? getMoveTo(int row, int col) {
    if (selectedRow == null) return null;
    
    final move = possibleMoves.firstWhere(
      (move) => move.toRow == row && move.toCol == col,
      orElse: () => DameMove(-1, -1, -1, -1),
    );

    return move.fromRow != -1 ? move : null;
  }

  bool handleTap(int row, int col) {
    if (selectedRow == null) {
      if (board[row][col] != null && board[row][col]!.player == myPlayerNumber) {
        if (forcedCaptureMoves.isNotEmpty && !forcedCaptureMoves.any((m) => m.fromRow == row && m.fromCol == col)) {
          return false; 
        }
        selectedRow = row;
        selectedCol = col;
        possibleMoves = _getValidMovesForPiece(row, col);
      }
    } else {
      DameMove? selectedMove = possibleMoves.firstWhere(
          (move) => move.toRow == row && move.toCol == col,
          orElse: () => DameMove(-1, -1, -1, -1),
      );

      if (selectedMove.fromRow != -1) {
        return executeMove(selectedMove);
      } else {
        if (board[row][col] != null && board[row][col]!.player == myPlayerNumber && !isMultiJump) {
           if (forcedCaptureMoves.isNotEmpty && !forcedCaptureMoves.any((m) => m.fromRow == row && m.fromCol == col)) {
             return false;
           }
           selectedRow = row;
           selectedCol = col;
           possibleMoves = _getValidMovesForPiece(row, col);
        } else {
          resetSelection();
        }
      }
    }
    return false;
  }

  bool executeMove(DameMove move) {
    final piece = board[move.fromRow][move.fromCol]!;
    board[move.toRow][move.toCol] = piece;
    board[move.fromRow][move.fromCol] = null;

    bool wasCapture = false;
    if (move.jumpedRow != null) {
      board[move.jumpedRow!][move.jumpedCol!] = null;
      wasCapture = true;
    }

    if ((myPlayerNumber == 1 && move.toRow == 0) || (myPlayerNumber == 2 && move.toRow == boardSize - 1)) {
      piece.type = DamePieceType.king;
    }

    if (wasCapture) {
      List<DameMove> nextCaptures = _getCaptureMovesForPiece(move.toRow, move.toCol, piece, myPlayerNumber);
      
      if (nextCaptures.isNotEmpty) {
        checkForcedMoves();
        
        List<DameMove> nextLegalCaptures = forcedCaptureMoves.where((m) => m.fromRow == move.toRow && m.fromCol == move.toCol).toList();
        
        if (nextLegalCaptures.isNotEmpty) {
          isMultiJump = true;
          selectedRow = move.toRow;
          selectedCol = move.toCol;
          possibleMoves = nextLegalCaptures;
          forcedCaptureMoves = nextLegalCaptures;
          return false;
        }
      }
    }
    
    resetSelection();
    return true;
  }

  void resetSelection() {
    selectedRow = null;
    selectedCol = null;
    possibleMoves = [];
    isMultiJump = false;
    checkForcedMoves();
  }
  
  bool hasAnyValidMoves(int playerNumber) {
    return _getAllMovesForPlayer(playerNumber).isNotEmpty;
  }

  List<DameMove> _getValidMovesForPiece(int row, int col) {
    DamePiece? piece = board[row][col];
    if (piece == null) return [];
    if (forcedCaptureMoves.isNotEmpty) {
      return forcedCaptureMoves.where((m) => m.fromRow == row && m.fromCol == col).toList();
    }
    return (piece.type == DamePieceType.man)
        ? _getStandardMovesForMan(row, col, myPlayerNumber)
        : _getStandardMovesForKing(row, col);
  }
  
  List<DameMove> _getAllMovesForPlayer(int playerNumber) {
    List<DameMove> allMoves = [];
    List<DameMove> captureMoves = _getAllCaptureMovesForPlayer(playerNumber);
    if (captureMoves.isNotEmpty) return captureMoves;
    
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        DamePiece? piece = board[r][c];
        if (piece != null && piece.player == playerNumber) {
          allMoves.addAll(
            (piece.type == DamePieceType.man) 
              ? _getStandardMovesForMan(r, c, playerNumber)
              : _getStandardMovesForKing(r, c)
          );
        }
      }
    }
    return allMoves;
  }

  List<DameMove> _getStandardMovesForMan(int row, int col, int playerNumber) {
    List<DameMove> moves = [];
    int forwardDirection = (playerNumber == 1) ? -1 : 1;
    final deltas = [[forwardDirection, -1], [forwardDirection, 1]];
    
    for (var d in deltas) {
      int toRow = row + d[0];
      int toCol = col + d[1];
      if (toRow >= 0 && toRow < boardSize && toCol >= 0 && toCol < boardSize && board[toRow][toCol] == null) {
        moves.add(DameMove(row, col, toRow, toCol));
      }
    }
    return moves;
  }
  
  List<DameMove> _getStandardMovesForKing(int row, int col) {
    List<DameMove> moves = [];
    final directions = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
    for (var d in directions) {
      int nextRow = row + d[0];
      int nextCol = col + d[1];
      while (nextRow >= 0 && nextRow < boardSize && nextCol >= 0 && nextCol < boardSize) {
        if (board[nextRow][nextCol] == null) {
          moves.add(DameMove(row, col, nextRow, nextCol));
        } else {
          break; 
        }
        nextRow += d[0];
        nextCol += d[1];
      }
    }
    return moves;
  }

  List<DameMove> _getAllCaptureMovesForPlayer(int playerNumber) {
    List<DameMove> allCaptures = [];
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        DamePiece? piece = board[r][c];
        if (piece != null && piece.player == playerNumber) {
          allCaptures.addAll(_getCaptureMovesForPiece(r, c, piece, playerNumber));
        }
      }
    }
    return allCaptures;
  }

  List<DameMove> _getCaptureMovesForPiece(int row, int col, DamePiece piece, int playerNumber) {
    return (piece.type == DamePieceType.man)
        ? _getCaptureMovesForMan(row, col, playerNumber)
        : _getCaptureMovesForKing(row, col, playerNumber);
  }

  List<DameMove> _getCaptureMovesForMan(int row, int col, int playerNumber) {
    List<DameMove> moves = [];
    final directions = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
    for (var d in directions) {
      int opponentRow = row + d[0];
      int opponentCol = col + d[1];
      int landingRow = row + 2 * d[0];
      int landingCol = col + 2 * d[1];

      if (landingRow >= 0 && landingRow < boardSize && landingCol >= 0 && landingCol < boardSize) {
        DamePiece? opponent = board.isNotEmpty && opponentRow >= 0 && opponentRow < boardSize && opponentCol >= 0 && opponentCol < boardSize ? board[opponentRow][opponentCol] : null;
        if (opponent != null && opponent.player != playerNumber && board[landingRow][landingCol] == null) {
          moves.add(DameMove(row, col, landingRow, landingCol, opponentRow, opponentCol));
        }
      }
    }
    return moves;
  }

  List<DameMove> _getCaptureMovesForKing(int row, int col, int playerNumber) {
    List<DameMove> moves = [];
    final directions = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
    for (var d in directions) {
      int opponentRow = -1, opponentCol = -1;
      int nextRow = row + d[0];
      int nextCol = col + d[1];

      while (nextRow >= 0 && nextRow < boardSize && nextCol >= 0 && nextCol < boardSize) {
        if (board[nextRow][nextCol] != null) {
          if (board[nextRow][nextCol]!.player != playerNumber) {
            opponentRow = nextRow;
            opponentCol = nextCol;
          }
          break;
        }
        nextRow += d[0];
        nextCol += d[1];
      }

      if (opponentRow != -1) {
        int landingRow = opponentRow + d[0];
        int landingCol = opponentCol + d[1];
        while (landingRow >= 0 && landingRow < boardSize && landingCol >= 0 && landingCol < boardSize) {
          if (board[landingRow][landingCol] == null) {
            moves.add(DameMove(row, col, landingRow, landingCol, opponentRow, opponentCol));
          } else {
            break;
          }
          landingRow += d[0];
          landingCol += d[1];
        }
      }
    }
    return moves;
  }
}