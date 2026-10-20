import 'package:tablero_engine/tablero_engine.dart';
import '../l10n/l10n.dart';

enum GameKind { chess, draughts, chineseCheckers }

enum Opponent { ai, local, online }

class TimeControl {
  final int minutes;
  final int incrementSeconds;
  const TimeControl(this.minutes, this.incrementSeconds);

  String get label => '$minutes + $incrementSeconds';

  static const presets = [TimeControl(5, 0), TimeControl(10, 5), TimeControl(15, 10)];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeControl &&
          runtimeType == other.runtimeType &&
          minutes == other.minutes &&
          incrementSeconds == other.incrementSeconds;

  @override
  int get hashCode => Object.hash(minutes, incrementSeconds);
}

/// Configuración elegida en «Nueva partida».
class MatchConfig {
  final GameKind kind;
  final DraughtsVariant draughtsVariant;
  final Opponent opponent;

  /// Nivel de la IA, 1 a 5.
  final int aiLevel;

  /// Jugador que controla la persona en partidas contra la IA (0 = blancas).
  final int humanSeat;

  /// `null` = sin reloj. Damas chinas nunca usa reloj.
  final TimeControl? clock;

  /// Solo damas chinas: 2, 3, 4 o 6.
  final int players;

  /// Id del documento de Firestore en partidas online.
  final String? onlineGameId;

  const MatchConfig({
    required this.kind,
    this.draughtsVariant = DraughtsVariant.spanish,
    this.opponent = Opponent.ai,
    this.aiLevel = 3,
    this.humanSeat = 0,
    this.clock,
    this.players = 2,
    this.onlineGameId,
  });

  bool get isOnline => opponent == Opponent.online;

  int get playerCount => kind == GameKind.chineseCheckers ? players : 2;

  bool isHuman(int player) => opponent == Opponent.local || player == humanSeat;

  String get title => switch (kind) {
        GameKind.chess => tr('Ajedrez'),
        GameKind.draughts => switch (draughtsVariant.id) {
            'international' => tr('Damas internacionales'),
            'english' => tr('Damas inglesas'),
            _ => tr('Damas españolas'),
          },
        GameKind.chineseCheckers => tr('Damas chinas'),
      };

  String get subtitle {
    final who = switch (opponent) {
      Opponent.ai => tr('Contra IA · nivel {aiLevel}', {'aiLevel': aiLevel}),
      Opponent.local => tr('Partida local'),
      Opponent.online => tr('Partida online'),
    };
    return clock == null ? who : '$who · ${clock!.label}';
  }

  static const _colorNames = ['naranja', 'azul', 'verde', 'amarillo', 'negro', 'blanco'];

  String playerName(int player) {
    if (kind == GameKind.chineseCheckers) {
      if (opponent == Opponent.ai) {
        return player == humanSeat ? tr('Tú') : tr('IA {color}', {'color': tr(_colorNames[player])});
      }
      return tr('Jugador {p0}', {'p0': tr(_colorNames[player])});
    }
    if (opponent == Opponent.ai) {
      return player == humanSeat ? tr('Tú') : tr('IA · nivel {aiLevel}', {'aiLevel': aiLevel});
    }
    if (opponent == Opponent.online) return player == humanSeat ? tr('Tú') : tr('Rival');
    return player == 0 ? tr('Blancas') : tr('Negras');
  }

  /// «Ganan las blancas», «Gana el jugador azul», etc.
  String winnerText(int player) {
    if (kind == GameKind.chineseCheckers) {
      return opponent == Opponent.ai && player == humanSeat
          ? tr('Has ganado')
          : tr('Gana el jugador {p0}', {'p0': tr(_colorNames[player])});
    }
    if (opponent == Opponent.online) {
      return player == humanSeat ? tr('Has ganado') : tr('Ha ganado tu rival');
    }
    return player == 0 ? tr('Ganan las blancas') : tr('Ganan las negras');
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'variant': draughtsVariant.id,
        'opponent': opponent.name,
        'aiLevel': aiLevel,
        'humanSeat': humanSeat,
        'clock': clock == null ? null : [clock!.minutes, clock!.incrementSeconds],
        'players': players,
        if (onlineGameId != null) 'onlineGameId': onlineGameId,
      };

  factory MatchConfig.fromJson(Map<String, Object?> j) {
    final clock = j['clock'] as List<Object?>?;
    return MatchConfig(
      kind: GameKind.values.byName(j['kind']! as String),
      draughtsVariant: DraughtsVariant.all.firstWhere(
        (v) => v.id == j['variant'],
        orElse: () => DraughtsVariant.spanish,
      ),
      opponent: Opponent.values.byName(j['opponent']! as String),
      aiLevel: j['aiLevel']! as int,
      humanSeat: j['humanSeat']! as int,
      clock: clock == null ? null : TimeControl(clock[0]! as int, clock[1]! as int),
      players: j['players']! as int,
      onlineGameId: j['onlineGameId'] as String?,
    );
  }

  MatchConfig copyWith({int? humanSeat}) => MatchConfig(
        kind: kind,
        draughtsVariant: draughtsVariant,
        opponent: opponent,
        aiLevel: aiLevel,
        humanSeat: humanSeat ?? this.humanSeat,
        clock: clock,
        players: players,
        onlineGameId: onlineGameId,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchConfig &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          draughtsVariant.id == other.draughtsVariant.id &&
          opponent == other.opponent &&
          aiLevel == other.aiLevel &&
          humanSeat == other.humanSeat &&
          clock == other.clock &&
          players == other.players &&
          onlineGameId == other.onlineGameId;

  @override
  int get hashCode => Object.hash(
        kind,
        draughtsVariant.id,
        opponent,
        aiLevel,
        humanSeat,
        clock,
        players,
        onlineGameId,
      );
}
