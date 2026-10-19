/// Funciones de valoración para [AlphaBeta] y presets de dificultad.
library;

import 'dart:math';

import '../chess/chess_position.dart';
import '../chess/chess_rules.dart';
import '../chinese_checkers/chinese_checkers_rules.dart';
import '../draughts/draughts_rules.dart';
import 'alpha_beta.dart';

/// Nivel de la IA de 1 a 5: profundidad máxima, error aleatorio y tiempo
/// máximo por jugada (la profundidad real puede ser menor si se agota).
({int depth, double noise, Duration time}) difficulty(int level) => switch (level) {
      1 => (depth: 1, noise: 300.0, time: const Duration(milliseconds: 300)),
      2 => (depth: 2, noise: 150.0, time: const Duration(milliseconds: 600)),
      3 => (depth: 3, noise: 40.0, time: const Duration(milliseconds: 1200)),
      4 => (depth: 5, noise: 10.0, time: const Duration(milliseconds: 2000)),
      _ => (depth: 8, noise: 0.0, time: const Duration(milliseconds: 3000)),
    };

const _chessValues = [0, 100, 320, 330, 500, 900, 0];

/// Material más un pequeño premio por centralizar peones y caballos.
double chessEvaluator(ChessState state, int player) {
  final color = player == 0 ? ChessColor.white : ChessColor.black;
  final b = state.position.board;
  var score = 0.0;
  for (var s = 0; s < 64; s++) {
    final v = b[s];
    if (v == 0) continue;
    final t = v.abs();
    var value = _chessValues[t].toDouble();
    if (t == Piece.knight || t == Piece.pawn) {
      final f = fileOf(s), r = rankOf(s);
      final centre = 7 - ((2 * f - 7).abs() + (2 * r - 7).abs()) / 2;
      value += centre * (t == Piece.knight ? 4 : 2);
    }
    score += v * color > 0 ? value : -value;
  }
  return score;
}

/// Capturas (MVV-LVA) y coronaciones primero: mejora mucho la poda.
List<ChessMove> orderChessMoves(ChessState state, List<ChessMove> moves) {
  final b = state.position.board;
  int key(ChessMove m) =>
      (b[m.to] != 0 ? 10 * _chessValues[b[m.to].abs()] - _chessValues[b[m.from].abs()] : 0) +
      (m.promotion != 0 ? 800 : 0);
  return [...moves]..sort((a, c) => key(c).compareTo(key(a)));
}

/// Capturas y coronaciones, para la búsqueda de quietud.
List<ChessMove> chessNoisyMoves(ChessState state, List<ChessMove> legal) {
  final b = state.position.board;
  return [
    for (final m in legal)
      if (b[m.to] != 0 || m.flag == MoveFlag.enPassant || m.promotion == Piece.queen) m
  ];
}

/// [timeLimit] sustituye al del nivel (p. ej. análisis rápido tras la partida).
AlphaBeta<ChessState, ChessMove> chessAi(int level, {int? seed, Duration? timeLimit}) {
  const rules = ChessRules();
  final d = difficulty(level);
  return AlphaBeta(
    rules: rules,
    evaluate: chessEvaluator,
    depth: d.depth,
    noise: d.noise,
    timeLimit: timeLimit ?? d.time,
    fastApply: rules.applyUnchecked,
    orderMoves: orderChessMoves,
    terminal: rules.resultWith,
    hash: (s) => s.hash,
    noisyMoves: level >= 3 ? chessNoisyMoves : null,
    seed: seed,
  );
}

/// Peón 100 + avance, dama 300.
double draughtsEvaluator(DraughtsState state, int player) {
  final side = player == 0 ? 1 : -1;
  final n = state.variant.size;
  var score = 0.0;
  for (var s = 0; s < state.board.length; s++) {
    final v = state.board[s];
    if (v == 0) continue;
    final row = s ~/ n;
    final advance = v > 0 ? (n - 1 - row) : row;
    final value = v.abs() == 2 ? 300.0 : 100.0 + 3 * advance;
    score += v * side > 0 ? value : -value;
  }
  return score;
}

/// En damas las capturas son obligatorias: si las hay, todas son ruidosas.
List<DraughtsMove> draughtsNoisyMoves(DraughtsState state, List<DraughtsMove> legal) =>
    legal.isNotEmpty && legal.first.isCapture ? legal : const [];

AlphaBeta<DraughtsState, DraughtsMove> draughtsAi(DraughtsRules rules, int level,
    {int? seed, Duration? timeLimit}) {
  final d = difficulty(level);
  return AlphaBeta(
    rules: rules,
    evaluate: draughtsEvaluator,
    depth: d.depth + 1, // las damas ramifican menos que el ajedrez
    noise: d.noise,
    timeLimit: timeLimit ?? d.time,
    fastApply: rules.applyUnchecked,
    terminal: rules.resultWith,
    hash: (s) => s.hash,
    noisyMoves: level >= 2 ? draughtsNoisyMoves : null,
    seed: seed,
  );
}

/// Para damas chinas a dos: diferencia de distancias a la meta.
Evaluator<CCState> chineseCheckersEvaluator(ChineseCheckersRules rules) =>
    (state, player) =>
        (rules.distanceToGoal(state, 1 - player) - rules.distanceToGoal(state, player))
            .toDouble();

/// Jugada de la IA de damas chinas para un nivel (1–5).
///
/// - A dos jugadores y desde el nivel 3: búsqueda alfa-beta con
///   [chineseCheckersEvaluator], más profunda cuanto más alto el nivel.
/// - Si no (más jugadores o niveles bajos): la jugada que más acerca a la
///   meta, eligiendo al azar entre las mejores en los niveles bajos.
CCMove chineseCheckersMove(ChineseCheckersRules rules, CCState s, int level, {Random? random}) {
  final moves = rules.legalMoves(s);
  if (moves.isEmpty) return CCMove.pass();
  if (s.playerCount == 2 && level >= 3) {
    final m = AlphaBeta<CCState, CCMove>(
      rules: rules,
      evaluate: chineseCheckersEvaluator(rules),
      depth: level - 1, // 2, 3 y 4 medias jugadas
      timeLimit: difficulty(level).time,
      fastApply: rules.applyUnchecked,
    ).bestMove(s);
    if (m != null) return m;
  }
  final me = s.toMove;
  final scored = [for (final m in moves) (m, rules.distanceToGoal(rules.applyUnchecked(s, m), me))]
    ..sort((a, b) => a.$2.compareTo(b.$2));
  final pool = switch (level) { 1 => 5, 2 => 3, 3 => 2, _ => 1 };
  return scored[(random ?? Random()).nextInt(min(pool, scored.length))].$1;
}
