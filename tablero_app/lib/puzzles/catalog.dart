import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../app/env.dart';
import '../app/telemetry.dart';
import 'puzzles.dart';

/// Catálogo remoto de problemas: `https://<web del entorno>/puzzles/catalog.json`
/// (lo publica la compilación de la landing). Permite añadir problemas sin
/// publicar una versión de la app.
///
/// - Se descarga como mucho una vez al día y se guarda en el teléfono.
/// - Cada problema se valida con el motor antes de usarlo; los inválidos se
///   descartan. Sin red o con un catálogo roto, la app usa los suyos.
abstract final class PuzzleCatalog {
  static const _kJson = 'puzzleCatalogJson', _kAt = 'puzzleCatalogAt';
  static const maxAge = Duration(days: 1);

  static Uri get url => Uri.parse('${AppEnv.inviteBaseUrl}/puzzles/catalog.json');

  /// Problemas remotos válidos de la caché, sin red (para mostrar al instante).
  static Future<List<Puzzle>> cached() async {
    final body = (await SharedPreferences.getInstance()).getString(_kJson);
    return body == null ? const [] : validate(body);
  }

  /// Descarga el catálogo si la copia tiene más de un día. Devuelve los
  /// problemas nuevos válidos, o `null` si no hubo descarga útil.
  static Future<List<Puzzle>?> refresh({http.Client? client, DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final t = now ?? DateTime.now();
    final at = DateTime.tryParse(prefs.getString(_kAt) ?? '');
    if (prefs.getString(_kJson) != null && at != null && t.difference(at) <= maxAge) return null;
    try {
      final res = await (client ?? http.Client()).get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final valid = await validate(res.body);
      if (valid.isEmpty) return null;
      await prefs.setString(_kJson, res.body);
      await prefs.setString(_kAt, t.toIso8601String());
      return valid;
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Catálogo de problemas');
      return null;
    }
  }

  /// Problemas válidos del catálogo (en otro isolate: son cientos de posiciones).
  static Future<List<Puzzle>> validate(String body) => Isolate.run(() => parseAndValidate(body));

  static List<Puzzle> parseAndValidate(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['format'] != 1) return const [];
      final out = <Puzzle>[];
      for (final raw in j['puzzles'] as List) {
        try {
          final p = Puzzle.fromJson(raw as Map<String, dynamic>);
          if (isValid(p)) out.add(p);
        } catch (_) {
          // Entrada mal formada: se ignora.
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// La solución es legal (y, en mate en 1, da mate). La unicidad la garantiza
  /// el generador y los tests; aquí se protege la app de datos corruptos.
  static bool isValid(Puzzle p) {
    if (p.isDraughts) {
      final rules = DraughtsRules(p.variant!);
      final n = p.variant!.size * p.variant!.size;
      if (p.board.length != n || (p.side != 1 && p.side != -1)) return false;
      final s = rules.fromBoard(p.board, p.side);
      return rules.legalMoves(s).any((m) => m.path.join('-') == p.solution);
    }
    const rules = ChessRules();
    final s = rules.fromFen(p.fen);
    final m = ChessEngine.fromUci(s.position, p.solution);
    if (m == null) return false;
    if (p.mateIn == 1) return rules.result(rules.apply(s, m))?.winner == p.sideToMove;
    return true;
  }

  /// Los incluidos en la app primero (mismo orden: el problema del día no
  /// cambia); después, los remotos con ids nuevos.
  static List<Puzzle> merge(List<Puzzle> bundled, List<Puzzle> remote) {
    final ids = {for (final p in bundled) p.id};
    return [...bundled, for (final p in remote) if (ids.add(p.id)) p];
  }
}
