import 'package:flutter_test/flutter_test.dart';
import 'package:tablero_app/learn/lessons.dart';
import 'package:tablero_app/match/match_config.dart';
import 'package:tablero_engine/tablero_engine.dart';

/// Cada lección se comprueba con el motor de Dart: las jugadas aceptadas y las
/// «trampas» son legales en su posición, y ninguna trampa se acepta a la vez.
void main() {
  test('ids únicos y al menos una jugada aceptada', () {
    expect(lessons.map((l) => l.id).toSet(), hasLength(lessons.length));
    for (final l in lessons) {
      expect(l.acceptCodes, isNotEmpty, reason: l.id);
      expect(l.acceptCodes.toSet().intersection(l.traps.keys.toSet()), isEmpty, reason: l.id);
    }
  });

  for (final l in lessons) {
    test('lección ${l.id}: jugadas legales', () {
      final List<String> legal;
      switch (l.kind) {
        case GameKind.chess:
          const rules = ChessRules();
          final s = rules.fromFen(l.fen);
          legal = [for (final m in rules.legalMoves(s)) m.uci];
        case GameKind.draughts:
          final rules = DraughtsRules(l.variant!);
          legal = [for (final m in rules.legalMoves(rules.fromBoard(l.board, l.side))) m.path.join('-')];
        case GameKind.chineseCheckers:
          final rules = ChineseCheckersRules(players: 2);
          legal = [for (final m in rules.legalMoves(l.ccState())) if (!m.isPass) '${m.from}-${m.to}'];
      }
      for (final code in [...l.acceptCodes, ...l.traps.keys]) {
        expect(legal, contains(code), reason: '${l.id}: $code no es legal');
      }
    });
  }

  test('ahogado: las trampas ahogan y las aceptadas dan mate', () {
    const rules = ChessRules();
    final l = lessons.firstWhere((l) => l.id == 'chess-stalemate');
    final s = rules.fromFen(l.fen);
    for (final m in rules.legalMoves(s)) {
      final r = rules.result(rules.apply(s, m));
      if (l.acceptCodes.contains(m.uci)) expect(r?.winner, 0, reason: m.uci);
      if (l.traps.containsKey(m.uci)) expect((r?.winner, r != null), (null, true), reason: m.uci);
    }
  });
}
