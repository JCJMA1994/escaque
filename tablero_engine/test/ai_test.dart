import 'package:tablero_engine/tablero_engine.dart';
import 'package:test/test.dart';

void main() {
  test('la IA de ajedrez ve el mate del pasillo', () {
    const rules = ChessRules();
    final s = rules.fromFen('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1');
    final m = AlphaBeta<ChessState, ChessMove>(
      rules: rules,
      evaluate: chessEvaluator,
      depth: 2,
      fastApply: rules.applyUnchecked,
    ).bestMove(s);
    expect(m?.uci, 'a1a8');
  });

  test('la IA de ajedrez respeta el límite de tiempo', () {
    final ai = chessAi(5, seed: 1);
    final s = const ChessRules().initialState();
    final sw = Stopwatch()..start();
    final m = ai.bestMove(s);
    sw.stop();
    expect(m, isNotNull);
    expect(ai.completedDepth, greaterThanOrEqualTo(3));
    // 3 s de presupuesto + margen para la comprobación cada 256 nodos.
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('la IA con tabla de transposición también ve el mate', () {
    const rules = ChessRules();
    final s = rules.fromFen('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1');
    expect(chessAi(5, seed: 1).bestMove(s)?.uci, 'a1a8');
  });

  test('la quietud evita dejar una pieza colgada', () {
    // Las blancas pueden capturar la dama negra indefensa en d5.
    const rules = ChessRules();
    final s = rules.fromFen('4k3/8/8/3q4/8/2N5/8/4K3 w - - 0 1');
    expect(chessAi(5, seed: 1).bestMove(s)?.uci, 'c3d5');
  });

  test('la IA de damas devuelve una jugada legal', () {
    final rules = DraughtsRules(DraughtsVariant.spanish);
    final s = rules.initialState();
    final m = draughtsAi(rules, 2, seed: 7).bestMove(s);
    expect(rules.legalMoves(s), contains(m));
  });

  test('IA voraz de damas chinas avanza hacia la meta', () {
    final rules = ChineseCheckersRules(players: 3);
    final s = rules.initialState();
    final before = rules.distanceToGoal(s, 0);
    final next = rules.apply(s, rules.greedyMove(s));
    expect(rules.distanceToGoal(next, 0), lessThan(before));
  });

  test('analyse: mejor jugada y puntuación (mate en 1 = victoria)', () {
    final ai = chessAi(5);
    final s = const ChessRules().fromFen('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1');
    final r = ai.analyse(s)!;
    expect(r.move.uci, 'a1a8');
    expect(r.score, greaterThan(AlphaBeta.winScore - 1000));
    expect(ai.analyse(const ChessRules().fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1')), isNull); // ahogado: terminada
  });
}
