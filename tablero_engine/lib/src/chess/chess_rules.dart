/// Reglas de ajedrez según las Leyes del Ajedrez FIDE: generación de jugadas
/// legales, enroque, captura al paso, coronación, finales de partida y SAN.
library;

import 'dart:math';

import '../core/game.dart';
import 'chess_position.dart';

enum MoveFlag { normal, doublePush, enPassant, castle }

class ChessMove {
  final int from;
  final int to;

  /// Tipo de pieza de coronación ([Piece.knight] … [Piece.queen]) o 0.
  final int promotion;
  final MoveFlag flag;

  const ChessMove(this.from, this.to,
      {this.promotion = 0, this.flag = MoveFlag.normal});

  /// Notación UCI: `e2e4`, `e7e8q`.
  String get uci =>
      '${squareName(from)}${squareName(to)}'
      '${promotion != 0 ? 'nbrq'[promotion - Piece.knight] : ''}';

  @override
  bool operator ==(Object other) =>
      other is ChessMove &&
      other.from == from &&
      other.to == to &&
      other.promotion == promotion &&
      other.flag == flag;

  @override
  int get hashCode => Object.hash(from, to, promotion, flag);

  @override
  String toString() => uci;
}

/// Tablas que un jugador puede reclamar (no automáticas).
enum DrawClaim { threefoldRepetition, fiftyMoves }

class ChessState implements GameState {
  final ChessPosition position;

  /// Estado anterior (para repeticiones y deshacer); `null` en el inicial.
  final ChessState? parent;

  ChessState(this.position, [this.parent]);

  /// Hash Zobrist de la posición a efectos de repetición (art. 9.2.2).
  late final int hash = ChessEngine.positionHash(position);

  @override
  int get toMove => position.side == ChessColor.white ? 0 : 1;

  @override
  int get playerCount => 2;

  /// Veces que ha aparecido la posición actual. Solo se recorren las medias
  /// jugadas desde la última captura o movimiento de peón: antes no puede
  /// repetirse.
  int get repetitions {
    var count = 1;
    var s = parent;
    for (var back = 1; s != null && back <= position.halfmove; back++) {
      if (back.isEven && s.hash == hash) count++;
      s = s.parent;
    }
    return count;
  }
}

class ChessRules implements GameRules<ChessState, ChessMove> {
  const ChessRules();

  @override
  ChessState initialState() => fromPosition(ChessPosition.start);

  ChessState fromPosition(ChessPosition p) => ChessState(p);

  ChessState fromFen(String fen) => fromPosition(ChessPosition.fromFen(fen));

  @override
  List<ChessMove> legalMoves(ChessState state) =>
      ChessEngine.legalMoves(state.position);

  @override
  ChessState apply(ChessState state, ChessMove move) {
    if (!legalMoves(state).contains(move)) {
      throw ArgumentError('Jugada ilegal: ${move.uci}');
    }
    return applyUnchecked(state, move);
  }

  /// Igual que [apply] sin validar; para la IA, que solo usa jugadas legales.
  ChessState applyUnchecked(ChessState state, ChessMove move) {
    return ChessState(ChessEngine.makeMove(state.position, move), state);
  }

  @override
  GameResult? result(ChessState state) =>
      resultWith(state, ChessEngine.legalMoves(state.position));

  /// Como [result], reutilizando las jugadas legales ya calculadas (la IA
  /// las necesita de todos modos).
  GameResult? resultWith(ChessState state, List<ChessMove> moves) {
    final p = state.position;
    final winnerIfMate = p.side == ChessColor.white ? 1 : 0;
    if (moves.isEmpty) {
      return ChessEngine.inCheck(p)
          ? GameResult.win(winnerIfMate, 'jaque mate')
          : const GameResult.draw('rey ahogado');
    }
    if (ChessEngine.insufficientMaterial(p.board)) {
      return const GameResult.draw('posición muerta: material insuficiente');
    }
    // Art. 9.6: automáticas. El mate ya se comprobó antes (tiene prioridad).
    if (state.repetitions >= 5) {
      return const GameResult.draw('quíntuple repetición');
    }
    if (p.halfmove >= 150) {
      return const GameResult.draw('regla de los 75 movimientos');
    }
    return null;
  }

  /// Tablas que el jugador con el turno puede reclamar (art. 9.2 y 9.3).
  /// Simplificación: se reclama sobre la posición actual, no sobre la jugada
  /// que se anuncia.
  DrawClaim? claimableDraw(ChessState state) {
    if (state.repetitions >= 3) return DrawClaim.threefoldRepetition;
    if (state.position.halfmove >= 100) return DrawClaim.fiftyMoves;
    return null;
  }

  /// Resultado cuando cae la bandera de [flaggedPlayer] (art. 6.9): pierde,
  /// salvo que el rival no pueda dar mate con ninguna serie de jugadas legales.
  GameResult onTimeout(ChessState state, int flaggedPlayer) {
    final opponent = 1 - flaggedPlayer;
    final oppColor = opponent == 0 ? ChessColor.white : ChessColor.black;
    if (!ChessEngine.canEverCheckmate(state.position.board, oppColor)) {
      return const GameResult.draw('tiempo agotado, rival sin material para dar mate');
    }
    return GameResult.win(opponent, 'tiempo agotado');
  }
}

/// Funciones puras de bajo nivel.
abstract final class ChessEngine {
  static const _knight = [
    [1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]
  ];
  static const _king = [
    [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]
  ];
  static const _diagonal = [[1, 1], [1, -1], [-1, 1], [-1, -1]];
  static const _orthogonal = [[1, 0], [-1, 0], [0, 1], [0, -1]];
  static const _all = [..._diagonal, ..._orthogonal];
  static const _promotions = [Piece.queen, Piece.rook, Piece.bishop, Piece.knight];

  /// Derechos que se pierden si una pieza sale de (o es capturada en) la casilla.
  static const _rightsLost = {
    0: Castling.whiteQueen, // a1
    7: Castling.whiteKing, // h1
    4: Castling.whiteKing | Castling.whiteQueen, // e1
    56: Castling.blackQueen, // a8
    63: Castling.blackKing, // h8
    60: Castling.blackKing | Castling.blackQueen, // e8
  };

  static bool _on(int f, int r) => f >= 0 && f < 8 && r >= 0 && r < 8;

  /// ¿Ataca el color [by] la casilla [sq]?
  static bool isAttacked(List<int> b, int sq, int by) {
    final f = fileOf(sq), r = rankOf(sq);
    final pawnRank = by == ChessColor.white ? r - 1 : r + 1;
    for (final df in const [-1, 1]) {
      if (_on(f + df, pawnRank) && b[square(f + df, pawnRank)] == by * Piece.pawn) {
        return true;
      }
    }
    for (final d in _knight) {
      if (_on(f + d[0], r + d[1]) &&
          b[square(f + d[0], r + d[1])] == by * Piece.knight) {
        return true;
      }
    }
    for (final d in _king) {
      if (_on(f + d[0], r + d[1]) &&
          b[square(f + d[0], r + d[1])] == by * Piece.king) {
        return true;
      }
    }
    if (_slides(b, f, r, by, _diagonal, Piece.bishop)) return true;
    if (_slides(b, f, r, by, _orthogonal, Piece.rook)) return true;
    return false;
  }

  static bool _slides(
      List<int> b, int f, int r, int by, List<List<int>> dirs, int slider) {
    for (final d in dirs) {
      var ff = f + d[0], rr = r + d[1];
      while (_on(ff, rr)) {
        final v = b[square(ff, rr)];
        if (v != 0) {
          if (v * by > 0 && (v.abs() == slider || v.abs() == Piece.queen)) {
            return true;
          }
          break;
        }
        ff += d[0];
        rr += d[1];
      }
    }
    return false;
  }

  static int kingSquare(List<int> b, int color) => b.indexOf(color * Piece.king);

  static bool inCheck(ChessPosition p) =>
      isAttacked(p.board, kingSquare(p.board, p.side), -p.side);

  /// Jugadas pseudo-legales (pueden dejar al rey propio en jaque).
  /// El enroque ya se filtra aquí por casillas atacadas (art. 3.8.2).
  static List<ChessMove> pseudoMoves(ChessPosition p) {
    final b = p.board, side = p.side;
    final moves = <ChessMove>[];
    for (var s = 0; s < 64; s++) {
      final v = b[s];
      if (v * side <= 0) continue;
      final type = v.abs(), f = fileOf(s), r = rankOf(s);
      switch (type) {
        case Piece.pawn:
          final start = side == ChessColor.white ? 1 : 6;
          final last = side == ChessColor.white ? 7 : 0;
          final r1 = r + side;
          if (!_on(f, r1)) break;
          final one = square(f, r1);
          if (b[one] == 0) {
            if (r1 == last) {
              for (final pr in _promotions) {
                moves.add(ChessMove(s, one, promotion: pr));
              }
            } else {
              moves.add(ChessMove(s, one));
              final two = square(f, r + 2 * side);
              if (r == start && b[two] == 0) {
                moves.add(ChessMove(s, two, flag: MoveFlag.doublePush));
              }
            }
          }
          for (final df in const [-1, 1]) {
            if (!_on(f + df, r1)) continue;
            final to = square(f + df, r1);
            if (b[to] * side < 0) {
              if (r1 == last) {
                for (final pr in _promotions) {
                  moves.add(ChessMove(s, to, promotion: pr));
                }
              } else {
                moves.add(ChessMove(s, to));
              }
            } else if (to == p.ep) {
              moves.add(ChessMove(s, to, flag: MoveFlag.enPassant));
            }
          }
        case Piece.knight:
        case Piece.king:
          for (final d in type == Piece.knight ? _knight : _king) {
            final ff = f + d[0], rr = r + d[1];
            if (_on(ff, rr) && b[square(ff, rr)] * side <= 0) {
              moves.add(ChessMove(s, square(ff, rr)));
            }
          }
          if (type == Piece.king) _addCastling(p, s, moves);
        default:
          final dirs = switch (type) {
            Piece.bishop => _diagonal,
            Piece.rook => _orthogonal,
            _ => _all,
          };
          for (final d in dirs) {
            var ff = f + d[0], rr = r + d[1];
            while (_on(ff, rr)) {
              final to = square(ff, rr);
              if (b[to] * side > 0) break;
              moves.add(ChessMove(s, to));
              if (b[to] != 0) break;
              ff += d[0];
              rr += d[1];
            }
          }
      }
    }
    return moves;
  }

  static void _addCastling(ChessPosition p, int s, List<ChessMove> moves) {
    final b = p.board, c = p.castling, opp = -p.side;
    bool safe(List<int> squares) => squares.every((q) => !isAttacked(b, q, opp));
    bool empty(List<int> squares) => squares.every((q) => b[q] == 0);
    if (p.side == ChessColor.white && s == 4) {
      if (c & Castling.whiteKing != 0 &&
          b[7] == Piece.rook &&
          empty(const [5, 6]) &&
          safe(const [4, 5, 6])) {
        moves.add(const ChessMove(4, 6, flag: MoveFlag.castle));
      }
      if (c & Castling.whiteQueen != 0 &&
          b[0] == Piece.rook &&
          empty(const [1, 2, 3]) &&
          safe(const [4, 3, 2])) {
        moves.add(const ChessMove(4, 2, flag: MoveFlag.castle));
      }
    } else if (p.side == ChessColor.black && s == 60) {
      if (c & Castling.blackKing != 0 &&
          b[63] == -Piece.rook &&
          empty(const [61, 62]) &&
          safe(const [60, 61, 62])) {
        moves.add(const ChessMove(60, 62, flag: MoveFlag.castle));
      }
      if (c & Castling.blackQueen != 0 &&
          b[56] == -Piece.rook &&
          empty(const [57, 58, 59]) &&
          safe(const [60, 59, 58])) {
        moves.add(const ChessMove(60, 58, flag: MoveFlag.castle));
      }
    }
  }

  /// Aplica una jugada sin validarla.
  static ChessPosition makeMove(ChessPosition p, ChessMove m) {
    final b = List<int>.of(p.board);
    final side = p.side;
    final moving = b[m.from];
    final captured = b[m.to];
    _movePieces(b, m, side);
    final castling = p.castling &
        ~(_rightsLost[m.from] ?? 0) &
        ~(_rightsLost[m.to] ?? 0);
    final ep = m.flag == MoveFlag.doublePush ? m.from + 8 * side : -1;
    final irreversible = moving.abs() == Piece.pawn || captured != 0;
    return ChessPosition.unsafe(
      board: b,
      side: -side,
      castling: castling,
      ep: ep,
      halfmove: irreversible ? 0 : p.halfmove + 1,
      fullmove: p.fullmove + (side == ChessColor.black ? 1 : 0),
    );
  }

  /// Mueve las piezas de [m] sobre [b] (incluye torre del enroque y peón
  /// capturado al paso).
  static void _movePieces(List<int> b, ChessMove m, int side) {
    final moving = b[m.from];
    b[m.to] = m.promotion != 0 ? side * m.promotion : moving;
    b[m.from] = 0;
    if (m.flag == MoveFlag.enPassant) b[m.to - 8 * side] = 0;
    if (m.flag == MoveFlag.castle) {
      final (rookFrom, rookTo) = switch (m.to) {
        6 => (7, 5),
        2 => (0, 3),
        62 => (63, 61),
        _ => (56, 59),
      };
      b[rookTo] = b[rookFrom];
      b[rookFrom] = 0;
    }
  }

  static List<ChessMove> legalMoves(ChessPosition p) {
    final result = <ChessMove>[];
    final side = p.side;
    final king = kingSquare(p.board, side);
    final scratch = List<int>.filled(64, 0);
    for (final m in pseudoMoves(p)) {
      scratch.setAll(0, p.board);
      _movePieces(scratch, m, side);
      final k = m.from == king ? m.to : king;
      if (!isAttacked(scratch, k, -side)) result.add(m);
    }
    return result;
  }

  /// Cuenta nodos legales a [depth]; sirve para verificar el generador.
  static int perft(ChessPosition p, int depth) {
    if (depth == 0) return 1;
    final moves = legalMoves(p);
    if (depth == 1) return moves.length;
    var n = 0;
    for (final m in moves) {
      n += perft(makeMove(p, m), depth - 1);
    }
    return n;
  }

  static final List<int> _zobrist = _buildZobrist();

  static List<int> _buildZobrist() {
    final r = Random(20261017);
    return List<int>.generate(
        12 * 64 + 1 + 16 + 8, (_) => (r.nextInt(1 << 32) << 32) ^ r.nextInt(1 << 32));
  }

  /// Hash Zobrist para repeticiones y tabla de transposición: piezas, turno,
  /// derechos de enroque y captura al paso solo si es realmente posible.
  static int positionHash(ChessPosition p) {
    var h = 0;
    final b = p.board;
    for (var s = 0; s < 64; s++) {
      final v = b[s];
      if (v == 0) continue;
      final idx = v > 0 ? v - 1 : 5 - v;
      h ^= _zobrist[idx * 64 + s];
    }
    if (p.side == ChessColor.black) h ^= _zobrist[768];
    h ^= _zobrist[769 + p.castling];
    if (p.ep >= 0 && _epPossible(p)) h ^= _zobrist[785 + fileOf(p.ep)];
    return h;
  }

  static bool _epPossible(ChessPosition p) {
    final pawnRank = rankOf(p.ep) - p.side; // fila del peón que capturaría
    final f = fileOf(p.ep);
    var adjacent = false;
    for (final df in const [-1, 1]) {
      if (_on(f + df, pawnRank) && p.board[square(f + df, pawnRank)] == p.side * Piece.pawn) {
        adjacent = true;
      }
    }
    return adjacent && legalMoves(p).any((m) => m.flag == MoveFlag.enPassant);
  }

  /// Posición muerta por material (art. 5.2.2), casos de rey y piezas menores.
  static bool insufficientMaterial(List<int> b) {
    final minors = <int>[];
    for (var s = 0; s < 64; s++) {
      final t = b[s].abs();
      if (t == 0 || t == Piece.king) continue;
      if (t == Piece.pawn || t == Piece.rook || t == Piece.queen) return false;
      minors.add(s);
    }
    if (minors.length <= 1) return true;
    // Solo alfiles, todos en casillas del mismo color.
    if (minors.every((s) => b[s].abs() == Piece.bishop)) {
      final shade = (fileOf(minors.first) + rankOf(minors.first)) % 2;
      return minors.every((s) => (fileOf(s) + rankOf(s)) % 2 == shade);
    }
    return false;
  }

  /// ¿Puede [color] dar mate con alguna serie de jugadas legales?
  /// Cubre rey solo, y rey + una pieza menor contra rey solo.
  /// No detecta bloqueos de peones (caso raro que se resuelve a mano).
  static bool canEverCheckmate(List<int> b, int color) {
    if (insufficientMaterial(b)) return false;
    final own = <int>[], opp = <int>[];
    for (var s = 0; s < 64; s++) {
      final v = b[s];
      if (v == 0 || v.abs() == Piece.king) continue;
      (v * color > 0 ? own : opp).add(v.abs());
    }
    if (own.isEmpty) return false;
    final singleMinor = own.length == 1 &&
        (own.first == Piece.knight || own.first == Piece.bishop);
    if (singleMinor && opp.isEmpty) return false;
    return true;
  }

  /// Notación algebraica estándar (SAN) en inglés: `Nf3`, `exd5`, `O-O`,
  /// `e8=Q+`, `Qh4#`.
  static String toSan(ChessPosition p, ChessMove m) {
    String san;
    if (m.flag == MoveFlag.castle) {
      san = fileOf(m.to) == 6 ? 'O-O' : 'O-O-O';
    } else {
      final type = p.board[m.from].abs();
      final capture = p.board[m.to] != 0 || m.flag == MoveFlag.enPassant;
      if (type == Piece.pawn) {
        san = capture ? '${squareName(m.from)[0]}x' : '';
        san += squareName(m.to);
        if (m.promotion != 0) san += '=${'NBRQ'[m.promotion - Piece.knight]}';
      } else {
        final rivals = legalMoves(p).where((o) =>
            o.to == m.to && o.from != m.from && p.board[o.from] == p.board[m.from]);
        var disambiguation = '';
        if (rivals.isNotEmpty) {
          final sameFile = rivals.any((o) => fileOf(o.from) == fileOf(m.from));
          final sameRank = rivals.any((o) => rankOf(o.from) == rankOf(m.from));
          final name = squareName(m.from);
          disambiguation = !sameFile
              ? name[0]
              : !sameRank
                  ? name[1]
                  : name;
        }
        san = '${'NBRQK'[type - Piece.knight]}$disambiguation'
            '${capture ? 'x' : ''}${squareName(m.to)}';
      }
    }
    final next = makeMove(p, m);
    if (inCheck(next)) san += legalMoves(next).isEmpty ? '#' : '+';
    return san;
  }

  /// Busca la jugada legal que corresponde a un texto UCI.
  static ChessMove? fromUci(ChessPosition p, String uci) {
    for (final m in legalMoves(p)) {
      if (m.uci == uci) return m;
    }
    return null;
  }

  /// Busca la jugada legal que corresponde a un texto SAN (ignora +, # y !?).
  static ChessMove? fromSan(ChessPosition p, String san) {
    String clean(String s) => s.replaceAll(RegExp(r'[+#!?]'), '');
    final target = clean(san.trim());
    for (final m in legalMoves(p)) {
      if (clean(toSan(p, m)) == target) return m;
    }
    return null;
  }
}
