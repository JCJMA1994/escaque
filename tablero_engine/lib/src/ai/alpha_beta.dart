/// Búsqueda minimax con poda alfa-beta (negamax) para juegos de dos jugadores
/// de suma cero, con profundización iterativa, límite de tiempo, tabla de
/// transposición y búsqueda de quietud opcionales.
library;

import 'dart:math';

import '../core/game.dart';

/// Valoración de [state] desde el punto de vista de [player]. Positivo = bueno.
typedef Evaluator<S> = double Function(S state, int player);

class _Timeout implements Exception {
  const _Timeout();
}

enum _Bound { exact, lower, upper }

class _Entry<M> {
  final int depth;
  final double score;
  final _Bound bound;
  final M? move;
  const _Entry(this.depth, this.score, this.bound, this.move);
}

class AlphaBeta<S extends GameState, M> {
  final GameRules<S, M> rules;
  final Evaluator<S> evaluate;

  /// Profundidad máxima en medias jugadas.
  final int depth;

  /// Error aleatorio máximo sumado a cada jugada candidata en la raíz.
  /// 0 = juega siempre la mejor; valores altos = niveles fáciles.
  final double noise;

  /// Tiempo máximo por jugada. Se devuelve la mejor jugada de la última
  /// profundidad completada. `null` = sin límite.
  final Duration? timeLimit;

  /// Aplicación sin validar (más rápida); por defecto, [GameRules.apply].
  final S Function(S state, M move)? fastApply;

  /// Ordenación (capturas primero, etc.) para podar más.
  final List<M> Function(S state, List<M> moves)? orderMoves;

  /// Resultado reutilizando las jugadas legales ya calculadas; evita generar
  /// las jugadas dos veces por nodo. Por defecto, [GameRules.result].
  final GameResult? Function(S state, List<M> legal)? terminal;

  /// Hash de la posición para la tabla de transposición. `null` = sin tabla.
  final int Function(S state)? hash;

  /// Jugadas «ruidosas» (capturas, coronaciones) que se siguen explorando en
  /// las hojas para no cortar a mitad de un intercambio. `null` = sin quietud.
  final List<M> Function(S state, List<M> legal)? noisyMoves;

  /// Profundidad máxima de la búsqueda de quietud.
  final int quiescenceDepth;

  final Random _random;
  final Map<int, _Entry<M>> _table = {};
  static const _tableLimit = 200000;
  final Stopwatch _clock = Stopwatch();
  int _nodes = 0;

  /// Nodos visitados en la última búsqueda (para medir rendimiento).
  int get nodes => _nodes;

  /// Profundidad completada en la última búsqueda.
  int completedDepth = 0;

  static const winScore = 1e6;

  AlphaBeta({
    required this.rules,
    required this.evaluate,
    this.depth = 3,
    this.noise = 0,
    this.timeLimit,
    this.fastApply,
    this.orderMoves,
    this.terminal,
    this.hash,
    this.noisyMoves,
    this.quiescenceDepth = 6,
    int? seed,
  }) : _random = Random(seed);

  S _apply(S s, M m) => (fastApply ?? rules.apply)(s, m);
  GameResult? _terminal(S s, List<M> legal) =>
      terminal != null ? terminal!(s, legal) : rules.result(s);

  List<M> _ordered(S s, List<M> legal, M? first) {
    final moves = orderMoves == null ? List.of(legal) : orderMoves!(s, legal);
    if (first != null) {
      final i = moves.indexOf(first);
      if (i > 0) {
        moves.removeAt(i);
        moves.insert(0, first);
      }
    }
    return moves;
  }

  void _tick() {
    _nodes++;
    if ((_nodes & 255) == 0 && timeLimit != null && _clock.elapsed > timeLimit!) {
      throw const _Timeout();
    }
  }

  /// Mejor jugada y su puntuación desde el bando en turno, sin ruido
  /// aleatorio (análisis tras la partida). `null` si la partida terminó.
  ({M move, double score})? analyse(S state) {
    final legal = rules.legalMoves(state);
    if (legal.isEmpty || _terminal(state, legal) != null) return null;
    final (order, scores) = _iterate(state, legal);
    return (move: order.first, score: scores?[order.first] ?? evaluate(state, state.toMove));
  }

  /// Mejor jugada para el jugador en turno, o `null` si la partida terminó.
  M? bestMove(S state) {
    final legal = rules.legalMoves(state);
    if (legal.isEmpty || _terminal(state, legal) != null) return null;
    if (legal.length == 1) return legal.first;
    final (order, scores) = _iterate(state, legal);
    if (scores == null) return order.first;
    if (noise <= 0) return order.first;
    M? best;
    var bestScore = double.negativeInfinity;
    for (final m in order) {
      final s = scores[m]! + _random.nextDouble() * noise;
      if (s > bestScore) {
        bestScore = s;
        best = m;
      }
    }
    return best;
  }

  /// Profundización iterativa: jugadas ordenadas de mejor a peor y sus
  /// puntuaciones de la última profundidad completa (`null` si ninguna).
  (List<M>, Map<M, double>?) _iterate(S state, List<M> legal) {
    _clock
      ..reset()
      ..start();
    _nodes = 0;
    completedDepth = 0;
    if (_table.length > _tableLimit) _table.clear();

    var order = _ordered(state, legal, null);
    Map<M, double>? scores;
    for (var d = 1; d <= depth; d++) {
      Map<M, double>? iteration;
      try {
        iteration = _root(state, order, d);
      } on _Timeout {
        break;
      }
      final sc = iteration;
      scores = sc;
      completedDepth = d;
      order = [...order]..sort((a, b) => sc[b]!.compareTo(sc[a]!));
      if (sc[order.first]! >= winScore - 100) break; // mate encontrado
      // Si ya se gastó la mitad del tiempo, la siguiente profundidad no acabaría.
      if (timeLimit != null && _clock.elapsed > timeLimit! * 0.5) break;
    }
    _clock.stop();
    return (order, scores);
  }

  /// Puntúa cada jugada de la raíz. Con ruido, todas con ventana completa
  /// (hacen falta valores exactos para elegir entre ellas).
  Map<M, double> _root(S state, List<M> moves, int d) {
    final scores = <M, double>{};
    var alpha = double.negativeInfinity;
    for (final m in moves) {
      final a = noise > 0 ? double.negativeInfinity : alpha;
      final score = -_search(_apply(state, m), d - 1, double.negativeInfinity, -a, 1);
      scores[m] = score;
      if (score > alpha) alpha = score;
    }
    return scores;
  }

  double _search(S s, int d, double alpha, double beta, int ply) {
    _tick();
    final legal = rules.legalMoves(s);
    final res = _terminal(s, legal);
    if (res != null) {
      if (res.isDraw) return 0;
      // Mate antes (menos ply) puntúa más para quien gana.
      return res.winner == s.toMove ? winScore - ply : -(winScore - ply);
    }
    if (d <= 0) {
      return noisyMoves == null
          ? evaluate(s, s.toMove)
          : _quiesce(s, legal, alpha, beta, ply, quiescenceDepth);
    }

    final key = hash?.call(s);
    M? ttMove;
    if (key != null) {
      final e = _table[key];
      if (e != null) {
        ttMove = e.move;
        if (e.depth >= d) {
          switch (e.bound) {
            case _Bound.exact:
              return e.score;
            case _Bound.lower:
              if (e.score > alpha) alpha = e.score;
            case _Bound.upper:
              if (e.score < beta) beta = e.score;
          }
          if (alpha >= beta) return e.score;
        }
      }
    }

    final alphaStart = alpha;
    var best = double.negativeInfinity;
    M? bestMove;
    for (final m in _ordered(s, legal, ttMove)) {
      final score = -_search(_apply(s, m), d - 1, -beta, -alpha, ply + 1);
      if (score > best) {
        best = score;
        bestMove = m;
      }
      if (score > alpha) alpha = score;
      if (alpha >= beta) break;
    }

    if (key != null) {
      final bound = best <= alphaStart
          ? _Bound.upper
          : best >= beta
              ? _Bound.lower
              : _Bound.exact;
      _table[key] = _Entry(d, best, bound, bestMove);
    }
    return best;
  }

  double _quiesce(S s, List<M> legal, double alpha, double beta, int ply, int qd) {
    final stand = evaluate(s, s.toMove);
    if (qd <= 0 || stand >= beta) return stand;
    if (stand > alpha) alpha = stand;
    final noisy = noisyMoves!(s, legal);
    for (final m in _ordered(s, noisy, null)) {
      _tick();
      final child = _apply(s, m);
      final childLegal = rules.legalMoves(child);
      final res = _terminal(child, childLegal);
      final double score;
      if (res != null) {
        score = res.isDraw ? 0 : (res.winner == s.toMove ? winScore - ply - 1 : -(winScore - ply - 1));
      } else {
        score = -_quiesce(child, childLegal, -beta, -alpha, ply + 1, qd - 1);
      }
      if (score >= beta) return score;
      if (score > alpha) alpha = score;
    }
    return alpha;
  }
}
