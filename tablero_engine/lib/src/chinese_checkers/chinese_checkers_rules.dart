/// Damas chinas con el reglamento estándar (no hay federación oficial):
/// 2, 3, 4 o 6 jugadores, 10 fichas cada uno, paso a casilla vecina o cadena
/// de saltos sobre fichas individuales, sin capturas.
library;

import '../core/game.dart';
import 'star_board.dart';

/// Qué cuenta como meta completa cuando un rival deja fichas en ella.
enum GoalRule {
  /// Hay que tener las 10 fichas propias en la punta opuesta.
  allOwnPieces,

  /// Basta con que la punta opuesta esté llena y tenga al menos una ficha
  /// propia (evita que un rival bloquee la meta para siempre).
  fullWithOwnPiece,
}

class CCMove {
  final int from;
  final int to;

  /// Casillas recorridas, origen incluido.
  final List<int> path;

  CCMove(this.from, this.to, List<int> path) : path = List.unmodifiable(path);

  /// Pasar turno: solo cuando no hay ninguna jugada posible.
  CCMove.pass()
      : from = -1,
        to = -1,
        path = const [];

  bool get isPass => from < 0;
  bool get isJump =>
      !isPass && !StarBoard.instance.neighbors[from].contains(to);

  @override
  bool operator ==(Object other) =>
      other is CCMove && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => isPass ? 'pasa' : 'CCMove($from → $to)';
}

class CCState implements GameState {
  /// Ocupación de las 121 casillas: índice de jugador o -1.
  final List<int> occupant;

  /// Punta de salida de cada jugador (0 … 5).
  final List<int> seats;

  @override
  final int toMove;

  final int ply;

  CCState({
    required List<int> occupant,
    required List<int> seats,
    required this.toMove,
    required this.ply,
  })  : occupant = List.unmodifiable(occupant),
        seats = List.unmodifiable(seats);

  @override
  int get playerCount => seats.length;

  int targetCorner(int player) => (seats[player] + 3) % 6;
}

class ChineseCheckersRules implements GameRules<CCState, CCMove> {
  final int players;
  final GoalRule goalRule;

  static const seatsByPlayers = {
    2: [0, 3],
    3: [0, 2, 4],
    4: [0, 1, 3, 4],
    6: [0, 1, 2, 3, 4, 5],
  };

  ChineseCheckersRules({this.players = 2, this.goalRule = GoalRule.fullWithOwnPiece}) {
    if (!seatsByPlayers.containsKey(players)) {
      throw ArgumentError('Damas chinas admite 2, 3, 4 o 6 jugadores');
    }
  }

  StarBoard get board => StarBoard.instance;

  @override
  CCState initialState() {
    final seats = seatsByPlayers[players]!;
    final occ = List<int>.filled(board.cells.length, -1);
    for (var p = 0; p < seats.length; p++) {
      for (final i in board.corners[seats[p]]) {
        occ[i] = p;
      }
    }
    return CCState(occupant: occ, seats: seats, toMove: 0, ply: 0);
  }

  /// Destinos alcanzables por una ficha: pasos simples y cadenas de saltos.
  List<CCMove> movesFrom(CCState s, int from) {
    final occ = s.occupant;
    final moves = <CCMove>[];
    final destinations = <int>{};
    for (final n in board.neighbors[from]) {
      if (occ[n] < 0) {
        moves.add(CCMove(from, n, [from, n]));
        destinations.add(n);
      }
    }
    final visited = {from};
    final stack = <List<int>>[
      [from]
    ];
    while (stack.isNotEmpty) {
      final path = stack.removeLast();
      for (final (over, land) in board.jumps[path.last]) {
        if (occ[over] < 0 || occ[land] >= 0 || visited.contains(land)) continue;
        visited.add(land);
        final next = [...path, land];
        // Un destino ya alcanzable con un paso no se repite como salto.
        if (destinations.add(land)) moves.add(CCMove(from, land, next));
        stack.add(next);
      }
    }
    return moves;
  }

  @override
  List<CCMove> legalMoves(CCState s) {
    final moves = <CCMove>[];
    for (var i = 0; i < s.occupant.length; i++) {
      if (s.occupant[i] == s.toMove) moves.addAll(movesFrom(s, i));
    }
    return moves.isEmpty ? [CCMove.pass()] : moves;
  }

  @override
  CCState apply(CCState s, CCMove m) {
    if (!m.isPass) {
      if (s.occupant[m.from] != s.toMove) {
        throw ArgumentError('La casilla de origen no es del jugador en turno');
      }
      if (!movesFrom(s, m.from).contains(m)) {
        throw ArgumentError('Jugada ilegal: $m');
      }
    }
    return applyUnchecked(s, m);
  }

  CCState applyUnchecked(CCState s, CCMove m) {
    final occ = List<int>.of(s.occupant);
    if (!m.isPass) {
      occ[m.to] = occ[m.from];
      occ[m.from] = -1;
    }
    return CCState(
      occupant: occ,
      seats: s.seats,
      toMove: (s.toMove + 1) % s.playerCount,
      ply: s.ply + 1,
    );
  }

  bool hasFinished(CCState s, int player) {
    final target = board.corners[s.targetCorner(player)];
    return switch (goalRule) {
      GoalRule.allOwnPieces => target.every((i) => s.occupant[i] == player),
      GoalRule.fullWithOwnPiece => target.every((i) => s.occupant[i] >= 0) &&
          target.any((i) => s.occupant[i] == player),
    };
  }

  @override
  GameResult? result(CCState s) {
    // Gana el primero en completar su meta; el último en mover se comprueba
    // primero porque es el único cuya situación acaba de cambiar a su favor.
    final last = (s.toMove - 1 + s.playerCount) % s.playerCount;
    if (s.ply > 0 && hasFinished(s, last)) {
      return GameResult.win(last, 'completó la punta opuesta');
    }
    for (var p = 0; p < s.playerCount; p++) {
      if (hasFinished(s, p)) return GameResult.win(p, 'completó la punta opuesta');
    }
    return null;
  }

  /// Suma de distancias de las fichas de [player] a la punta de su meta.
  /// Menor es mejor; base de las heurísticas de la IA.
  int distanceToGoal(CCState s, int player) {
    final tip = board.cells[board.tips[s.targetCorner(player)]];
    var total = 0;
    for (var i = 0; i < s.occupant.length; i++) {
      if (s.occupant[i] == player) total += board.cells[i].distanceTo(tip);
    }
    return total;
  }

  /// IA sencilla para partidas de 3 a 6 jugadores: la jugada que más acerca
  /// a la meta (desempate: la que deja menos fichas atrás).
  CCMove greedyMove(CCState s) {
    final moves = legalMoves(s);
    CCMove best = moves.first;
    var bestScore = 1 << 30;
    for (final m in moves) {
      final score = distanceToGoal(applyUnchecked(s, m), s.toMove);
      if (score < bestScore) {
        bestScore = score;
        best = m;
      }
    }
    return best;
  }
}
