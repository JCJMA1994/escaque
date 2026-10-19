import 'dart:math';

import 'package:tablero_engine/tablero_engine.dart';
import 'package:test/test.dart';

void main() {
  final board = StarBoard.instance;

  test('121 casillas y seis puntas de 10 sin solaparse', () {
    expect(board.cells, hasLength(121));
    expect(board.corners.map((c) => c.length), everyElement(10));
    expect(board.corners.expand((c) => c).toSet(), hasLength(60));
  });

  test('las puntas opuestas son simétricas', () {
    for (var k = 0; k < 3; k++) {
      final a = board.cells[board.tips[k]], b = board.cells[board.tips[k + 3]];
      expect(Hex(-a.x, -a.y, -a.z), b);
    }
  });

  test('jugadas iniciales a 2 y 3 jugadores', () {
    for (final players in [2, 3]) {
      final rules = ChineseCheckersRules(players: players);
      expect(rules.legalMoves(rules.initialState()), hasLength(14));
    }
  });

  test('los saltos se encadenan', () {
    final rules = ChineseCheckersRules();
    final s = rules.initialState();
    final jumps = rules.legalMoves(s).where((m) => m.isJump);
    expect(jumps, isNotEmpty);
  });

  test('meta llena con ficha propia gana', () {
    final rules = ChineseCheckersRules(goalRule: GoalRule.fullWithOwnPiece);
    final s0 = rules.initialState();
    final occ = List<int>.filled(121, -1);
    final target = board.corners[s0.targetCorner(0)];
    for (final i in target) {
      occ[i] = 1; // la meta del jugador 0 está llena de fichas del rival…
    }
    occ[target.first] = 0; // …salvo una propia
    final s = CCState(occupant: occ, seats: s0.seats, toMove: 1, ply: 1);
    expect(rules.result(s)?.winner, 0);
    final strict = ChineseCheckersRules(goalRule: GoalRule.allOwnPieces);
    expect(strict.result(s), isNull);
  });

  group('IA por nivel', () {
    test('todas las jugadas son legales, a dos y a seis jugadores, en cada nivel', () {
      for (final players in [2, 6]) {
        final rules = ChineseCheckersRules(players: players);
        var s = rules.initialState();
        for (var ply = 0; ply < 12; ply++) {
          final level = ply % 5 + 1;
          final m = chineseCheckersMove(rules, s, level, random: Random(ply));
          expect(rules.legalMoves(s), contains(m), reason: 'nivel $level, jugadores $players');
          s = rules.apply(s, m);
        }
      }
    });

    test('los niveles bajos varían; el 5 a dos jugadores no se aleja de la meta', () {
      final rules = ChineseCheckersRules();
      final s = rules.initialState();
      final easy = {for (var seed = 0; seed < 20; seed++) chineseCheckersMove(rules, s, 1, random: Random(seed))};
      expect(easy.length, greaterThan(1));
      final hard = chineseCheckersMove(rules, s, 5);
      expect(rules.distanceToGoal(rules.apply(s, hard), s.toMove), lessThan(rules.distanceToGoal(s, s.toMove)));
    });
  });
}
