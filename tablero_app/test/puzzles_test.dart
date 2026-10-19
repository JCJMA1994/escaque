import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablero_app/puzzles/puzzles.dart';
import 'package:tablero_engine/tablero_engine.dart';

/// Cada problema del archivo se comprueba con el motor de Dart: la solución
/// es legal y lleva al mate en el número de jugadas indicado.
void main() {
  const rules = ChessRules();
  final puzzles = [
    for (final j in jsonDecode(File('assets/puzzles_chess.json').readAsStringSync()) as List)
      Puzzle.fromJson(j as Map<String, dynamic>),
  ];

  bool matesNow(ChessState s, int winner) => rules.result(s)?.winner == winner;
  bool hasMateIn1(ChessState s, int winner) =>
      rules.legalMoves(s).any((m) => matesNow(rules.apply(s, m), winner));

  test('al menos 90 problemas, con ids únicos', () {
    expect(puzzles.length, greaterThanOrEqualTo(90));
    expect(puzzles.map((p) => p.id).toSet(), hasLength(puzzles.length));
  });

  for (final p in puzzles) {
    test('problema ${p.id} (${p.title})', () {
      final s = rules.fromFen(p.fen);
      final move = ChessEngine.fromUci(s.position, p.solution);
      expect(move, isNotNull, reason: 'Solución ilegal: ${p.solution}');
      final after = rules.apply(s, move!);
      if (p.mateIn == 1) {
        expect(matesNow(after, p.sideToMove), isTrue);
      } else {
        expect(hasMateIn1(s, p.sideToMove), isFalse, reason: 'Tenía mate en 1');
        final replies = rules.legalMoves(after);
        expect(replies, isNotEmpty);
        for (final r in replies) {
          expect(hasMateIn1(rules.apply(after, r), p.sideToMove), isTrue, reason: 'Defensa ${r.uci} se salva');
        }
      }
    });
  }

  test('racha: días seguidos y reinicio', () {
    const p = PuzzleProgress(streak: 3, lastDailyDay: '2026-10-17');
    expect(p.currentStreak(DateTime(2026, 10, 18)), 3);
    expect(p.currentStreak(DateTime(2026, 10, 20)), 0);
    expect(dailyPuzzle(List.generate(90, (i) => Puzzle(id: i + 1, fen: '', mateIn: 1, solution: '')),
            DateTime(2026, 1, 1)).id, 1);
  });
}
