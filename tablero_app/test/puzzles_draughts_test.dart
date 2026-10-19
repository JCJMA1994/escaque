import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablero_app/puzzles/puzzles.dart';
import 'package:tablero_engine/tablero_engine.dart';

/// Cada golpe de damas se verifica con el motor de Dart: la solución es la
/// única jugada que, tras cualquier respuesta, permite ganar al menos 2 de
/// material; ninguna otra jugada gana nada.
void main() {
  int material(List<int> b, int side) {
    var m = 0;
    for (final x in b) {
      if (x == 0) continue;
      final v = x.abs() == 2 ? 3 : 1;
      m += x * side > 0 ? v : -v;
    }
    return m;
  }

  int gainAfter(DraughtsRules rules, DraughtsState s, DraughtsMove m, int side) {
    final base = material(s.board, side);
    final q = rules.apply(s, m);
    final replies = rules.legalMoves(q);
    if (replies.isEmpty) return 99;
    var worst = 99;
    for (final r in replies) {
      final q2 = rules.apply(q, r);
      final follow = rules.legalMoves(q2);
      final best = follow.isEmpty
          ? material(q2.board, side)
          : follow.map((f) => material(rules.apply(q2, f).board, side)).reduce((a, b) => a > b ? a : b);
      if (best < worst) worst = best;
    }
    return worst - base;
  }

  final puzzles = [
    for (final j in jsonDecode(File('assets/puzzles_draughts.json').readAsStringSync()) as List)
      Puzzle.fromJson(j as Map<String, dynamic>),
  ];

  test('100 golpes con ids desde 1001', () {
    expect(puzzles, hasLength(100));
    expect(puzzles.map((p) => p.id).toSet(), hasLength(100));
    expect(puzzles.every((p) => p.id > 1000 && p.isDraughts), isTrue);
  });

  for (final p in puzzles) {
    test('golpe ${p.id} (${p.variant!.id})', () {
      final rules = DraughtsRules(p.variant!);
      final s = rules.fromBoard(p.board, p.side);
      final moves = rules.legalMoves(s);
      expect(moves.any((m) => m.captured.isNotEmpty), isFalse, reason: 'debe ser una posición tranquila');
      final solution = moves.where((m) => m.path.join('-') == p.solution).toList();
      expect(solution, hasLength(1), reason: 'solución ilegal: ${p.solution}');
      expect(gainAfter(rules, s, solution.single, p.side), greaterThanOrEqualTo(2));
      for (final m in moves) {
        if (identical(m, solution.single)) continue;
        expect(gainAfter(rules, s, m, p.side), lessThanOrEqualTo(0), reason: 'otra jugada también gana: ${m.path}');
      }
    });
  }
}
