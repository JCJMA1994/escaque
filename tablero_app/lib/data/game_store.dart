import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../match/match_config.dart';

/// Partida guardada: en curso (para retomarla) o terminada (historial).
class SavedGame {
  final int? id;
  final MatchConfig config;

  /// Jugadas reproducibles (`MatchAdapter.moveCodes`).
  final List<String> moves;

  /// Notación para mostrar (SAN, PDN…).
  final List<String> log;

  /// Tiempo restante de cada jugador en milisegundos, si hay reloj.
  final List<int>? clocksMs;
  final bool finished;
  final int? winner;
  final String? reason;
  final DateTime startedAt;
  final DateTime updatedAt;

  const SavedGame({
    this.id,
    required this.config,
    required this.moves,
    required this.log,
    this.clocksMs,
    required this.finished,
    this.winner,
    this.reason,
    required this.startedAt,
    required this.updatedAt,
  });

  bool get isDraw => finished && winner == null;

  SavedGame withId(int id) => SavedGame(
        id: id,
        config: config,
        moves: moves,
        log: log,
        clocksMs: clocksMs,
        finished: finished,
        winner: winner,
        reason: reason,
        startedAt: startedAt,
        updatedAt: updatedAt,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'config': jsonEncode(config.toJson()),
        'moves': jsonEncode(moves),
        'log': jsonEncode(log),
        'clocks': clocksMs == null ? null : jsonEncode(clocksMs),
        'finished': finished ? 1 : 0,
        'winner': winner,
        'reason': reason,
        'started_at': startedAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory SavedGame.fromRow(Map<String, Object?> r) => SavedGame(
        id: r['id'] as int?,
        config: MatchConfig.fromJson(jsonDecode(r['config']! as String) as Map<String, Object?>),
        moves: (jsonDecode(r['moves']! as String) as List).cast<String>(),
        log: (jsonDecode(r['log']! as String) as List).cast<String>(),
        clocksMs: r['clocks'] == null
            ? null
            : (jsonDecode(r['clocks']! as String) as List).cast<int>(),
        finished: r['finished'] == 1,
        winner: r['winner'] as int?,
        reason: r['reason'] as String?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at']! as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at']! as int),
      );
}

/// Persistencia en SQLite. Una sola partida en curso a la vez.
class GameStore {
  Future<Database>? _db;

  Future<Database> get _database => _db ??= _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'tablero.db');
    return openDatabase(
      path,
      version: 2,
      onUpgrade: (db, from, to) async {
        if (from < 2) await db.execute(_analysisTable);
      },
      onCreate: (db, version) async {
        await db.execute(_analysisTable);
        await db.execute('''
        CREATE TABLE games(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          config TEXT NOT NULL,
          moves TEXT NOT NULL,
          log TEXT NOT NULL,
          clocks TEXT,
          finished INTEGER NOT NULL,
          winner INTEGER,
          reason TEXT,
          started_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )''');
      },
    );
  }

  /// Análisis tras la partida (JSON), aparte para no tocar la tabla principal.
  static const _analysisTable =
      'CREATE TABLE IF NOT EXISTS analysis(game_id INTEGER PRIMARY KEY, json TEXT NOT NULL)';

  Future<String?> loadAnalysis(int gameId) async {
    final rows = await (await _database).query('analysis', where: 'game_id = ?', whereArgs: [gameId]);
    return rows.isEmpty ? null : rows.first['json'] as String;
  }

  Future<void> saveAnalysis(int gameId, String json) async {
    await (await _database).insert('analysis', {'game_id': gameId, 'json': json},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Inserta o actualiza; devuelve el id.
  Future<int> save(SavedGame g) async {
    final db = await _database;
    if (g.id == null) return db.insert('games', g.toRow());
    await db.update('games', g.toRow(), where: 'id = ?', whereArgs: [g.id]);
    return g.id!;
  }

  Future<SavedGame?> inProgress() async {
    final db = await _database;
    final rows = await db.query('games',
        where: 'finished = 0', orderBy: 'updated_at DESC', limit: 1);
    return rows.isEmpty ? null : SavedGame.fromRow(rows.first);
  }

  /// Al empezar una partida nueva se descartan las que quedaron a medias.
  Future<void> discardInProgress({int? except}) async {
    final db = await _database;
    await db.delete('games',
        where: except == null ? 'finished = 0' : 'finished = 0 AND id != ?',
        whereArgs: except == null ? null : [except]);
  }

  Future<List<SavedGame>> finished({int limit = 200}) async {
    final db = await _database;
    final rows = await db.query('games',
        where: 'finished = 1', orderBy: 'updated_at DESC', limit: limit);
    return rows.map(SavedGame.fromRow).toList();
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('games', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearHistory() async {
    final db = await _database;
    await db.delete('games', where: 'finished = 1');
  }
}

final gameStoreProvider = Provider<GameStore>((ref) => GameStore());

final inProgressProvider =
    FutureProvider.autoDispose<SavedGame?>((ref) => ref.watch(gameStoreProvider).inProgress());

final historyProvider =
    FutureProvider.autoDispose<List<SavedGame>>((ref) => ref.watch(gameStoreProvider).finished());

/// Partida guardada que la pantalla de juego debe retomar (o `null`).
final resumeGameProvider = StateProvider<SavedGame?>((ref) => null);
