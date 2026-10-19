import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../l10n/l10n.dart';
import '../app/play_games.dart';
import '../match/match_config.dart';
import 'catalog.dart';

/// Problema de ajedrez: mate en 1 o en 2 con solución única.
/// Generados y verificados con el motor (`tool/puzzles/`).
/// Problema: de ajedrez (mate en 1 o en 2) o de damas («golpe»: una jugada
/// que, tras la respuesta forzada, gana al menos 2 de material). Todos con
/// solución única, generados y verificados con el motor (`tool/puzzles/`).
class Puzzle {
  final int id;
  final GameKind kind;

  /// Ajedrez: posición en FEN.
  final String fen;
  final int mateIn;

  /// Ajedrez: primera jugada en UCI. Damas: recorrido «32-28» (casillas internas).
  final String solution;

  /// Damas: variante, tablero (±1 peón, ±2 dama) y bando (1 blancas, -1 negras).
  final DraughtsVariant? variant;
  final List<int> board;
  final int side;

  /// Dificultad 1–3.
  final int rating;

  const Puzzle({
    required this.id,
    required this.solution,
    this.kind = GameKind.chess,
    this.fen = '',
    this.mateIn = 1,
    this.variant,
    this.board = const [],
    this.side = 1,
    this.rating = 1,
  });

  factory Puzzle.fromJson(Map<String, dynamic> j) {
    if (j['kind'] == 'draughts') {
      return Puzzle(
        id: j['id'] as int,
        kind: GameKind.draughts,
        variant: DraughtsVariant.all.firstWhere((v) => v.id == j['variant']),
        board: [for (final x in j['board'] as List) x as int],
        side: j['side'] as int,
        solution: (j['solution'] as List).join('-'),
        rating: (j['rating'] as int?) ?? 2,
      );
    }
    return Puzzle(
      id: j['id'] as int,
      fen: j['fen'] as String,
      mateIn: j['type'] == 'mate2' ? 2 : 1,
      solution: j['solution'] as String,
      rating: (j['rating'] as int?) ?? 1,
    );
  }

  bool get isDraughts => kind == GameKind.draughts;

  /// 0 = juegan blancas.
  int get sideToMove => isDraughts ? (side == 1 ? 0 : 1) : (fen.split(' ')[1] == 'w' ? 0 : 1);

  String get title => isDraughts ? tr('Golpe') : tr('Mate en {mateIn}', {'mateIn': mateIn});

  /// Lo que hay que conseguir, en una frase.
  String get goal => isDraughts
      ? tr('Juega una jugada que obligue a capturar y gana al menos 2 de material (una dama vale 3).')
      : tr('Da mate en {mateIn}.', {'mateIn': mateIn});

  String get sideText => sideToMove == 0 ? tr('Juegan blancas') : tr('Juegan negras');

  String get gameName => isDraughts
      ? switch (variant!.id) {
          'international' => tr('Damas internacionales'),
          'english' => tr('Damas inglesas'),
          _ => tr('Damas españolas'),
        }
      : tr('Ajedrez');
}

/// Problemas incluidos en la app más los del catálogo remoto (PuzzleCatalog).
/// Se muestran al instante (incluidos + caché) y se actualizan si la descarga
/// diaria trae problemas nuevos.
class PuzzlesController extends AsyncNotifier<List<Puzzle>> {
  @override
  Future<List<Puzzle>> build() async {
    final bundled = await _bundled();
    final merged = PuzzleCatalog.merge(bundled, await PuzzleCatalog.cached());
    Future(() async {
      final fresh = await PuzzleCatalog.refresh();
      if (fresh != null) state = AsyncData(PuzzleCatalog.merge(bundled, fresh));
    });
    return merged;
  }

  static Future<List<Puzzle>> _bundled() async {
    Future<List<Puzzle>> load(String asset) async {
      final raw = jsonDecode(await rootBundle.loadString(asset)) as List;
      return [for (final j in raw) Puzzle.fromJson(j as Map<String, dynamic>)];
    }

    final chess = await load('assets/puzzles_chess.json');
    final draughts = await load('assets/puzzles_draughts.json');
    // Intercalados para el problema del día: dos de ajedrez y uno de damas.
    final mixed = <Puzzle>[];
    var c = 0, d = 0;
    while (c < chess.length || d < draughts.length) {
      for (var i = 0; i < 2 && c < chess.length; i++) {
        mixed.add(chess[c++]);
      }
      if (d < draughts.length) mixed.add(draughts[d++]);
    }
    return mixed;
  }
}

final puzzlesProvider = AsyncNotifierProvider<PuzzlesController, List<Puzzle>>(PuzzlesController.new);

class PuzzleProgress {
  final Set<int> solved;
  final int streak;
  final String? lastDailyDay; // AAAA-MM-DD del último problema del día resuelto

  const PuzzleProgress({this.solved = const {}, this.streak = 0, this.lastDailyDay});

  bool dailySolvedOn(DateTime day) => lastDailyDay == dayKey(day);

  /// Racha vigente: si ayer no se resolvió el del día (y hoy tampoco), es 0.
  int currentStreak(DateTime now) {
    if (lastDailyDay == dayKey(now)) return streak;
    if (lastDailyDay == dayKey(now.subtract(const Duration(days: 1)))) return streak;
    return 0;
  }

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class PuzzleProgressController extends AsyncNotifier<PuzzleProgress> {
  static const _kSolved = 'puzzlesSolved', _kStreak = 'puzzleStreak', _kDay = 'puzzleDailyDay';

  @override
  Future<PuzzleProgress> build() async {
    final p = await SharedPreferences.getInstance();
    return PuzzleProgress(
      solved: {for (final s in p.getStringList(_kSolved) ?? const <String>[]) int.parse(s)},
      streak: p.getInt(_kStreak) ?? 0,
      lastDailyDay: p.getString(_kDay),
    );
  }

  /// Marca [id] como resuelto. Si es el del día, actualiza la racha.
  Future<void> markSolved(int id, {required bool daily, DateTime? now}) async {
    final today = now ?? DateTime.now();
    final current = state.valueOrNull ?? await future;
    final solved = {...current.solved, id};
    var streak = current.streak;
    var lastDay = current.lastDailyDay;
    if (daily && !current.dailySolvedOn(today)) {
      final yesterday = PuzzleProgress.dayKey(today.subtract(const Duration(days: 1)));
      streak = current.lastDailyDay == yesterday ? streak + 1 : 1;
      lastDay = PuzzleProgress.dayKey(today);
    }
    final next = PuzzleProgress(solved: solved, streak: streak, lastDailyDay: lastDay);
    state = AsyncData(next);
    // Play Games: problemas resueltos, mejor racha y logros de racha.
    PlayGames.submit(PlayLeaderboard.puzzlesSolved, solved.length);
    PlayGames.submit(PlayLeaderboard.bestStreak, streak);
    if (solved.length >= 50) PlayGames.unlock(PlayAchievement.puzzles50);
    if (streak >= 7) PlayGames.unlock(PlayAchievement.streak7);
    if (streak >= 30) PlayGames.unlock(PlayAchievement.streak30);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kSolved, [for (final s in solved) '$s']);
    await p.setInt(_kStreak, streak);
    if (lastDay != null) await p.setString(_kDay, lastDay);
  }
}

final puzzleProgressProvider =
    AsyncNotifierProvider<PuzzleProgressController, PuzzleProgress>(PuzzleProgressController.new);

/// El problema del día: el mismo para todo el mundo ese día (calendario local).
Puzzle dailyPuzzle(List<Puzzle> all, DateTime now) {
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(2026, 1, 1)).inDays;
  return all[days % all.length];
}
