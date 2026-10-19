import 'package:flutter_test/flutter_test.dart';
import 'package:tablero_app/app/settings.dart';
import 'package:tablero_app/data/export.dart';
import 'package:tablero_app/data/game_store.dart';
import 'package:tablero_app/match/adapters/chess_adapter.dart';
import 'package:tablero_app/match/adapters/match_adapter.dart';
import 'package:tablero_app/match/match_config.dart';
import 'package:tablero_engine/tablero_engine.dart';

void main() {
  test('MatchConfig ida y vuelta por JSON', () {
    const cfg = MatchConfig(
      kind: GameKind.draughts,
      draughtsVariant: DraughtsVariant.international,
      opponent: Opponent.local,
      aiLevel: 4,
      humanSeat: 1,
      clock: TimeControl(10, 5),
    );
    final back = MatchConfig.fromJson(cfg.toJson());
    expect(back.kind, GameKind.draughts);
    expect(back.draughtsVariant.id, 'international');
    expect(back.opponent, Opponent.local);
    expect(back.clock?.label, '10 + 5');
  });

  test('SavedGame ida y vuelta por fila SQLite', () {
    final g = SavedGame(
      id: 3,
      config: const MatchConfig(kind: GameKind.chess),
      moves: const ['e2e4', 'e7e5'],
      log: const ['e4', 'e5'],
      clocksMs: const [1000, 2000],
      finished: true,
      winner: 0,
      reason: 'jaque mate',
      startedAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17, 1),
    );
    final back = SavedGame.fromRow(g.toRow());
    expect(back.moves, g.moves);
    expect(back.clocksMs, [1000, 2000]);
    expect(back.winner, 0);
  });

  test('las jugadas guardadas se reproducen', () {
    final a = ChessAdapter();
    for (final san in ['e4', 'e5', 'Nf3']) {
      final m = ChessEngine.fromSan(a.state.position, san)!;
      a.play(m.from, m.to);
    }
    final b = MatchAdapter.create(const MatchConfig(kind: GameKind.chess));
    for (final code in a.moveCodes) {
      expect(b.replay(code), isTrue);
    }
    expect(b.moveLog, ['e4', 'e5', 'Nf3']);
  });

  test('PGN con cabeceras y resultado', () {
    final g = SavedGame(
      config: const MatchConfig(kind: GameKind.chess, opponent: Opponent.local),
      moves: const [],
      log: const ['f3', 'e5', 'g4', 'Qh4#'],
      finished: true,
      winner: 1,
      reason: 'jaque mate',
      startedAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
    );
    final pgn = toPgn(g);
    expect(pgn, contains('[Date "2026.10.17"]'));
    expect(pgn, contains('[Result "0-1"]'));
    expect(pgn.trim().endsWith('1. f3 e5 2. g4 Qh4# 0-1'), isTrue);
  });

  test('PDN internacional usa GameType 20 y 2-0', () {
    final g = SavedGame(
      config: const MatchConfig(kind: GameKind.draughts, draughtsVariant: DraughtsVariant.international),
      moves: const [],
      log: const ['32-28'],
      finished: true,
      winner: 0,
      reason: 'el rival no puede mover',
      startedAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
    );
    final pdn = toPdn(g);
    expect(pdn, contains('[GameType "20"]'));
    expect(pdn, contains('[Result "2-0"]'));
  });

  test('notación española', () {
    expect(spanishSan('Nf3'), 'Cf3');
    expect(spanishSan('Bxe5+'), 'Axe5+');
    expect(spanishSan('e8=Q#'), 'e8=D#');
    expect(spanishSan('O-O'), 'O-O');
    expect(spanishSan('Rbd1'), 'Tbd1');
  });
}
