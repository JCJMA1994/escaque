import '../match/match_config.dart';
import 'game_store.dart';

String _date(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

String _wrap(List<String> tokens, {int width = 80}) {
  final lines = <String>[];
  var line = StringBuffer();
  for (final t in tokens) {
    if (line.isNotEmpty && line.length + 1 + t.length > width) {
      lines.add(line.toString());
      line = StringBuffer();
    }
    if (line.isNotEmpty) line.write(' ');
    line.write(t);
  }
  if (line.isNotEmpty) lines.add(line.toString());
  return lines.join('\n');
}

String _escape(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// Partida de ajedrez en PGN (Seven Tag Roster + ritmo y motivo de final).
String toPgn(SavedGame g) {
  final result = !g.finished
      ? '*'
      : g.winner == null
          ? '1/2-1/2'
          : (g.winner == 0 ? '1-0' : '0-1');
  final cfg = g.config;
  final tags = <String, String>{
    'Event': 'Partida en Escaque',
    'Site': 'Escaque (Android)',
    'Date': _date(g.startedAt),
    'Round': '-',
    'White': cfg.playerName(0),
    'Black': cfg.playerName(1),
    'Result': result,
    if (cfg.clock != null)
      'TimeControl': '${cfg.clock!.minutes * 60}+${cfg.clock!.incrementSeconds}',
    if (g.reason != null) 'Termination': g.reason!,
  };
  final tokens = <String>[];
  for (var i = 0; i < g.log.length; i++) {
    if (i.isEven) tokens.add('${i ~/ 2 + 1}.');
    tokens.add(g.log[i]);
  }
  tokens.add(result);
  final header = tags.entries.map((e) => '[${e.key} "${_escape(e.value)}"]').join('\n');
  return '$header\n\n${_wrap(tokens)}\n';
}

/// Partida de damas en PDN. GameType según el estándar PDN:
/// 20 internacional, 21 inglesa, 24 española.
String toPdn(SavedGame g) {
  final cfg = g.config;
  final v = cfg.draughtsVariant;
  final gameType = switch (v.id) {
    'international' => '20',
    'english' => '21',
    _ => '24',
  };
  final international = v.id == 'international';
  final result = !g.finished
      ? '*'
      : g.winner == null
          ? (international ? '1-1' : '1/2-1/2')
          : g.winner == 0
              ? (international ? '2-0' : '1-0')
              : (international ? '0-2' : '0-1');
  final tags = <String, String>{
    'Event': 'Partida en Escaque',
    'Date': _date(g.startedAt),
    'White': cfg.playerName(0),
    'Black': cfg.playerName(1),
    'Result': result,
    'GameType': gameType,
  };
  // El primer movimiento es de quien empieza en la variante.
  final tokens = <String>[];
  for (var i = 0; i < g.log.length; i++) {
    if (i.isEven) tokens.add('${i ~/ 2 + 1}.');
    tokens.add(g.log[i]);
  }
  tokens.add(result);
  final header = tags.entries.map((e) => '[${e.key} "${_escape(e.value)}"]').join('\n');
  return '$header\n\n${_wrap(tokens)}\n';
}

/// Texto exportable, o `null` si el juego no tiene formato estándar.
String? exportGame(SavedGame g) => switch (g.config.kind) {
      GameKind.chess => toPgn(g),
      GameKind.draughts => toPdn(g),
      GameKind.chineseCheckers => null,
    };
