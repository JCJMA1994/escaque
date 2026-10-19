import 'package:games_services/games_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'telemetry.dart';

/// Logros de Google Play Games (PLAN.md, fase C, punto 2).
enum PlayAchievement {
  firstWinChess,
  firstWinDraughts,
  firstWinChineseCheckers,
  beatLevel5,
  streak7,
  streak30,
  puzzles50,
  firstOnlineGame,
  firstRematch,
  allLessons,
}

/// Clasificaciones.
enum PlayLeaderboard { puzzlesSolved, bestStreak, level5Wins }

/// Envoltorio de `games_services`: los IDs vienen de Play Console por
/// `--dart-define` (`config/<entorno>.json`). Sin IDs, todo queda inactivo. Lo
/// desbloqueado sin sesión de Play Games se guarda y se envía después.
abstract final class PlayGames {
  static const _ach = <PlayAchievement, String>{
    PlayAchievement.firstWinChess: String.fromEnvironment('PG_ACH_FIRST_WIN_CHESS'),
    PlayAchievement.firstWinDraughts: String.fromEnvironment('PG_ACH_FIRST_WIN_DRAUGHTS'),
    PlayAchievement.firstWinChineseCheckers: String.fromEnvironment('PG_ACH_FIRST_WIN_CHINESE'),
    PlayAchievement.beatLevel5: String.fromEnvironment('PG_ACH_BEAT_LEVEL5'),
    PlayAchievement.streak7: String.fromEnvironment('PG_ACH_STREAK7'),
    PlayAchievement.streak30: String.fromEnvironment('PG_ACH_STREAK30'),
    PlayAchievement.puzzles50: String.fromEnvironment('PG_ACH_PUZZLES50'),
    PlayAchievement.firstOnlineGame: String.fromEnvironment('PG_ACH_FIRST_ONLINE'),
    PlayAchievement.firstRematch: String.fromEnvironment('PG_ACH_FIRST_REMATCH'),
    PlayAchievement.allLessons: String.fromEnvironment('PG_ACH_ALL_LESSONS'),
  };
  static const _boards = <PlayLeaderboard, String>{
    PlayLeaderboard.puzzlesSolved: String.fromEnvironment('PG_LB_PUZZLES'),
    PlayLeaderboard.bestStreak: String.fromEnvironment('PG_LB_STREAK'),
    PlayLeaderboard.level5Wins: String.fromEnvironment('PG_LB_LEVEL5'),
  };
  static const _kPending = 'playGamesPending', _kLevel5 = 'playGamesLevel5Wins';
  static bool _signedIn = false;

  static bool get configured => _ach.values.any((id) => id.isNotEmpty);

  /// Inicio de sesión silencioso de Play Games v2 y envío de lo pendiente.
  static Future<void> init() async {
    if (!configured) return;
    try {
      await GamesServices.signIn();
      _signedIn = true;
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_kPending) ?? const <String>[];
      for (final name in pending) {
        await _send(PlayAchievement.values.byName(name));
      }
      await prefs.remove(_kPending);
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Play Games: inicio de sesión');
    }
  }

  static Future<void> unlock(PlayAchievement a) async {
    if ((_ach[a] ?? '').isEmpty) return;
    if (!_signedIn) {
      final prefs = await SharedPreferences.getInstance();
      final pending = {...prefs.getStringList(_kPending) ?? const <String>[], a.name};
      await prefs.setStringList(_kPending, pending.toList());
      return;
    }
    await _send(a);
  }

  static Future<void> _send(PlayAchievement a) async {
    try {
      await GamesServices.unlock(achievement: Achievement(androidID: _ach[a]!));
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Play Games: logro ${a.name}');
    }
  }

  static Future<void> submit(PlayLeaderboard b, int value) async {
    final id = _boards[b] ?? '';
    if (id.isEmpty || !_signedIn) return; // las clasificaciones guardan el máximo: se reenvía en el próximo logro
    try {
      await GamesServices.submitScore(score: Score(androidLeaderboardID: id, value: value));
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Play Games: clasificación ${b.name}');
    }
  }

  /// Victoria contra la IA de nivel 5: logro y clasificación (contador local).
  static Future<void> level5Win() async {
    await unlock(PlayAchievement.beatLevel5);
    final prefs = await SharedPreferences.getInstance();
    final n = (prefs.getInt(_kLevel5) ?? 0) + 1;
    await prefs.setInt(_kLevel5, n);
    await submit(PlayLeaderboard.level5Wins, n);
  }

  static Future<void> showAchievements() async {
    if (!_signedIn) await init();
    if (_signedIn) await GamesServices.showAchievements();
  }

  static Future<void> showLeaderboards() async {
    if (!_signedIn) await init();
    if (_signedIn) await GamesServices.showLeaderboards();
  }
}
