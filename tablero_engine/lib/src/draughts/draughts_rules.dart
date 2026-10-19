/// Motor de damas parametrizado por [DraughtsVariant].
///
/// Tablero de `size × size`, fila 0 arriba. Las piezas viven en casillas
/// oscuras, `(fila + columna) % 2 == 1`. Blancas abajo, avanzan hacia la fila 0.
/// Códigos: 1 peón blanco, 2 dama blanca, -1 peón negro, -2 dama negra.
library;

import 'dart:math';

import '../core/game.dart';
import 'draughts_variant.dart';

class DraughtsMove {
  /// Casillas recorridas: origen, aterrizajes intermedios y destino.
  final List<int> path;

  /// Casillas de las piezas capturadas, en orden.
  final List<int> captured;

  DraughtsMove(List<int> path, [List<int> captured = const []])
      : path = List.unmodifiable(path),
        captured = List.unmodifiable(captured);

  int get from => path.first;
  int get to => path.last;
  bool get isCapture => captured.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is DraughtsMove &&
      _listEq(other.path, path) &&
      _listEq(other.captured, captured);

  @override
  int get hashCode => Object.hash(Object.hashAll(path), Object.hashAll(captured));

  @override
  String toString() => 'DraughtsMove(${path.join('>')}, x${captured.length})';
}

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class DraughtsState implements GameState {
  final DraughtsVariant variant;
  final List<int> board;

  /// 1 = mueven blancas, -1 = mueven negras.
  final int side;

  /// Medias jugadas seguidas sin captura ni movimiento de peón.
  final int quietPlies;

  /// Estado anterior; `null` en el inicial.
  final DraughtsState? parent;

  DraughtsState({
    required this.variant,
    required List<int> board,
    required this.side,
    required this.quietPlies,
    this.parent,
  }) : board = List.unmodifiable(board);

  /// Hash Zobrist de piezas y turno.
  late final int hash = _hash(board, side);

  static final List<int> _zobrist = () {
    final r = Random(17102026);
    return List<int>.generate(4 * 100 + 1, (_) => (r.nextInt(1 << 32) << 32) ^ r.nextInt(1 << 32));
  }();

  static int _hash(List<int> b, int side) {
    var h = side == -1 ? _zobrist[400] : 0;
    for (var s = 0; s < b.length; s++) {
      final v = b[s];
      if (v == 0) continue;
      final idx = switch (v) { 1 => 0, 2 => 1, -1 => 2, _ => 3 };
      h ^= _zobrist[idx * 100 + s];
    }
    return h;
  }

  @override
  int get toMove => side == 1 ? 0 : 1;

  @override
  int get playerCount => 2;

  /// Veces que ha aparecido la posición actual. Solo pueden repetirse
  /// posiciones desde el último movimiento de peón o captura.
  int get repetitions {
    var count = 1;
    var s = parent;
    for (var back = 1; s != null && back <= quietPlies; back++) {
      if (back.isEven && s.hash == hash) count++;
      s = s.parent;
    }
    return count;
  }

  int pieceAt(int row, int col) => board[row * variant.size + col];
}

class DraughtsRules implements GameRules<DraughtsState, DraughtsMove> {
  final DraughtsVariant variant;

  const DraughtsRules(this.variant);

  static const _dirs = [[-1, -1], [-1, 1], [1, -1], [1, 1]];

  int get _n => variant.size;

  @override
  DraughtsState initialState() {
    final n = _n;
    final b = List<int>.filled(n * n, 0);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if ((r + c) % 2 == 0) continue;
        if (r < variant.rowsPerSide) b[r * n + c] = -1;
        if (r >= n - variant.rowsPerSide) b[r * n + c] = 1;
      }
    }
    return fromBoard(b, variant.firstToMove);
  }

  /// Estado desde una posición arbitraria (tests, problemas, partidas guardadas).
  DraughtsState fromBoard(List<int> board, int side, {int quietPlies = 0}) {
    if (board.length != _n * _n) throw ArgumentError('Tablero de tamaño incorrecto');
    return DraughtsState(
      variant: variant,
      board: board,
      side: side,
      quietPlies: quietPlies,
    );
  }

  @override
  List<DraughtsMove> legalMoves(DraughtsState state) {
    final b = state.board, side = state.side, n = _n;
    var captures = <DraughtsMove>[];
    for (var s = 0; s < n * n; s++) {
      if (b[s] * side <= 0) continue;
      final work = List<int>.of(b);
      final piece = work[s];
      work[s] = 0; // la pieza que se mueve deja libre su casilla de origen
      _searchCaptures(work, s, piece, side, [], [s], captures);
    }
    if (captures.isNotEmpty) {
      if (variant.captureRule != CaptureRule.free) {
        final most = captures.map((m) => m.captured.length).reduce(_max);
        captures = captures.where((m) => m.captured.length == most).toList();
      }
      if (variant.captureRule == CaptureRule.maxPiecesThenKings) {
        int kings(DraughtsMove m) => m.captured.where((q) => b[q].abs() == 2).length;
        final most = captures.map(kings).reduce(_max);
        captures = captures.where((m) => kings(m) == most).toList();
      }
      return captures;
    }
    return _simpleMoves(b, side);
  }

  static int _max(int a, int b) => a > b ? a : b;

  bool _on(int r, int c) => r >= 0 && r < _n && c >= 0 && c < _n;

  /// Búsqueda en profundidad de secuencias de captura completas. Las piezas
  /// capturadas siguen en el tablero (bloquean) hasta el final de la jugada y
  /// ninguna se salta dos veces.
  void _searchCaptures(List<int> b, int s, int piece, int side,
      List<int> captured, List<int> path, List<DraughtsMove> out) {
    final n = _n, r = s ~/ n, c = s % n;
    final isKing = piece.abs() == 2;
    final forward = side == 1 ? -1 : 1;
    final lastRow = side == 1 ? 0 : n - 1;
    var found = false;
    for (final d in _dirs) {
      final dr = d[0], dc = d[1];
      if (!isKing && !variant.menCaptureBackward && dr != forward) continue;
      if (isKing && variant.flyingKings) {
        var rr = r + dr, cc = c + dc;
        while (_on(rr, cc) && b[rr * n + cc] == 0) {
          rr += dr;
          cc += dc;
        }
        if (!_on(rr, cc)) continue;
        final victim = rr * n + cc;
        if (b[victim] * side >= 0 || captured.contains(victim)) continue;
        var lr = rr + dr, lc = cc + dc;
        while (_on(lr, lc) && b[lr * n + lc] == 0) {
          final land = lr * n + lc;
          found = true;
          _searchCaptures(b, land, piece, side, [...captured, victim],
              [...path, land], out);
          lr += dr;
          lc += dc;
        }
      } else {
        final lr = r + 2 * dr, lc = c + 2 * dc;
        if (!_on(lr, lc)) continue;
        final victim = (r + dr) * n + (c + dc);
        final land = lr * n + lc;
        if (b[victim] * side < 0 && !captured.contains(victim) && b[land] == 0) {
          found = true;
          final crowns = !isKing && lr == lastRow;
          if (crowns && variant.midCapture == MidCapturePromotion.endsTurn) {
            out.add(DraughtsMove([...path, land], [...captured, victim]));
          } else {
            _searchCaptures(b, land, piece, side, [...captured, victim],
                [...path, land], out);
          }
        }
      }
    }
    if (!found && captured.isNotEmpty) out.add(DraughtsMove(path, captured));
  }

  List<DraughtsMove> _simpleMoves(List<int> b, int side) {
    final n = _n, forward = side == 1 ? -1 : 1;
    final moves = <DraughtsMove>[];
    for (var s = 0; s < n * n; s++) {
      if (b[s] * side <= 0) continue;
      final r = s ~/ n, c = s % n, isKing = b[s].abs() == 2;
      for (final d in _dirs) {
        if (!isKing && d[0] != forward) continue;
        var rr = r + d[0], cc = c + d[1];
        while (_on(rr, cc) && b[rr * n + cc] == 0) {
          moves.add(DraughtsMove([s, rr * n + cc]));
          if (!(isKing && variant.flyingKings)) break;
          rr += d[0];
          cc += d[1];
        }
      }
    }
    return moves;
  }

  @override
  DraughtsState apply(DraughtsState state, DraughtsMove move) {
    if (!legalMoves(state).contains(move)) {
      throw ArgumentError('Jugada ilegal: $move');
    }
    return applyUnchecked(state, move);
  }

  DraughtsState applyUnchecked(DraughtsState state, DraughtsMove move) {
    final n = _n, side = state.side;
    final b = List<int>.of(state.board);
    var piece = b[move.from];
    final wasMan = piece.abs() == 1;
    b[move.from] = 0;
    for (final q in move.captured) {
      b[q] = 0;
    }
    final lastRow = side == 1 ? 0 : n - 1;
    if (wasMan && move.to ~/ n == lastRow) piece = 2 * side;
    b[move.to] = piece;
    final progress = wasMan || move.isCapture;
    return DraughtsState(
      variant: variant,
      board: b,
      side: -side,
      quietPlies: progress ? 0 : state.quietPlies + 1,
      parent: state,
    );
  }

  @override
  GameResult? result(DraughtsState state) => resultWith(state, legalMoves(state));

  /// Como [result], reutilizando las jugadas legales ya calculadas.
  GameResult? resultWith(DraughtsState state, List<DraughtsMove> legal) {
    if (legal.isEmpty) {
      return GameResult.win(1 - state.toMove, 'el rival no puede mover');
    }
    if (state.repetitions >= variant.repetitionsForDraw) {
      return const GameResult.draw('repetición de posición');
    }
    final limit = variant.quietPliesForDraw;
    if (limit != null && state.quietPlies >= limit) {
      return const GameResult.draw('jugadas sin progreso');
    }
    return null;
  }

  /// Número de casilla oscura en notación PDN (1 … size²/2), contando desde
  /// la fila superior. Confirmar la orientación de cada variante antes de
  /// exportar partidas.
  int squareNumber(int index) => index ~/ 2 + 1;

  /// `32-28` para un movimiento, `28x19` para una captura.
  String notation(DraughtsMove m) =>
      '${squareNumber(m.from)}${m.isCapture ? 'x' : '-'}${squareNumber(m.to)}';

  /// Cuenta nodos legales a [depth]; sirve para verificar el generador.
  int perft(DraughtsState state, int depth) {
    final moves = legalMoves(state);
    if (depth == 1) return moves.length;
    var total = 0;
    for (final m in moves) {
      total += perft(applyUnchecked(state, m), depth - 1);
    }
    return total;
  }
}
