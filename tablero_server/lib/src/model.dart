/// Partida online tal como se guarda en `games/{id}`.
class GameRecord {
  final String id;
  final String kind; // chess | draughts
  final String variant; // id de DraughtsVariant; ignorado en ajedrez
  final List<String> members;

  /// uid por asiento (0 = blancas). Cadena vacía = libre.
  final List<String> players;
  final List<String> names;
  final String code;

  /// waiting | active | finished | cancelled
  final String status;
  final List<String> moves;
  final int toMove;

  /// Motivo del final; `null` mientras la partida sigue. Con motivo y
  /// [winner] nulo, son tablas.
  final String? reason;
  final int? winner;
  final int? drawOfferBy;

  /// Media jugada en la que cada asiento ofreció tablas por última vez.
  final List<int> lastDrawOfferPly;

  /// Límite para mover; `null` si la partida no está activa.
  final DateTime? deadline;
  final bool reminderSent;

  /// Partida de revancha creada a partir de esta (evita duplicados).
  final String? rematchId;

  /// Partida valorada (Glicko-2): solo en retos entre amigos.
  final bool rated;

  /// Uid de quien retó (retos entre amigos); el retado puede rechazarlo
  /// mientras no haya movido.
  final String? challenger;

  /// La valoración ya se aplicó (operación idempotente tras terminar).
  final bool ratingApplied;

  /// Valoración de cada jugador al empezar (para mostrarla), o vacía.
  final List<int> ratingsAtStart;

  /// Últimas frases fijas: {seat, phrase, at}, como mucho 10.
  final List<Map<String, Object?>> emotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GameRecord({
    required this.id,
    required this.kind,
    required this.variant,
    required this.members,
    required this.players,
    required this.names,
    required this.code,
    required this.status,
    required this.moves,
    required this.toMove,
    this.reason,
    this.winner,
    this.drawOfferBy,
    this.lastDrawOfferPly = const [-100, -100],
    this.deadline,
    this.reminderSent = false,
    this.rematchId,
    this.rated = false,
    this.challenger,
    this.ratingApplied = false,
    this.ratingsAtStart = const [],
    this.emotes = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  int get ply => moves.length;
  bool get isActive => status == 'active';
  bool get isWaiting => status == 'waiting';
  int seatOf(String uid) => players.indexOf(uid);

  static const _keep = Object();

  GameRecord copyWith({
    List<String>? members,
    List<String>? players,
    List<String>? names,
    String? status,
    List<String>? moves,
    int? toMove,
    Object? reason = _keep,
    Object? winner = _keep,
    Object? drawOfferBy = _keep,
    List<int>? lastDrawOfferPly,
    Object? deadline = _keep,
    bool? reminderSent,
    String? rematchId,
    bool? ratingApplied,
    List<Map<String, Object?>>? emotes,
    required DateTime updatedAt,
  }) =>
      GameRecord(
        id: id,
        kind: kind,
        variant: variant,
        members: members ?? this.members,
        players: players ?? this.players,
        names: names ?? this.names,
        code: code,
        status: status ?? this.status,
        moves: moves ?? this.moves,
        toMove: toMove ?? this.toMove,
        reason: identical(reason, _keep) ? this.reason : reason as String?,
        winner: identical(winner, _keep) ? this.winner : winner as int?,
        drawOfferBy: identical(drawOfferBy, _keep) ? this.drawOfferBy : drawOfferBy as int?,
        lastDrawOfferPly: lastDrawOfferPly ?? this.lastDrawOfferPly,
        deadline: identical(deadline, _keep) ? this.deadline : deadline as DateTime?,
        reminderSent: reminderSent ?? this.reminderSent,
        rematchId: rematchId ?? this.rematchId,
        rated: rated,
        challenger: challenger,
        ratingApplied: ratingApplied ?? this.ratingApplied,
        ratingsAtStart: ratingsAtStart,
        emotes: emotes ?? this.emotes,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Campos tal como los lee la app (mismos nombres que en Firestore).
  Map<String, Object?> toFields() => {
        'kind': kind,
        'variant': variant,
        'members': members,
        'players': players,
        'names': names,
        'code': code,
        'status': status,
        'moves': moves,
        'ply': ply,
        'toMove': toMove,
        'result': reason == null ? null : {'winner': winner, 'reason': reason},
        'drawOfferBy': drawOfferBy,
        'lastDrawOfferPly': lastDrawOfferPly,
        'deadline': deadline,
        'reminderSent': reminderSent,
        'rematchId': rematchId,
        'rated': rated,
        'challenger': challenger,
        'ratingApplied': ratingApplied,
        'ratingsAtStart': ratingsAtStart,
        'emotes': emotes,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory GameRecord.fromFields(String id, Map<String, Object?> f) {
    final result = f['result'] as Map<String, Object?>?;
    List<String> strings(String k) => [for (final v in (f[k] as List? ?? const [])) v as String];
    return GameRecord(
      id: id,
      kind: f['kind'] as String,
      variant: f['variant'] as String? ?? 'spanish',
      members: strings('members'),
      players: strings('players'),
      names: strings('names'),
      code: f['code'] as String? ?? '',
      status: f['status'] as String,
      moves: strings('moves'),
      toMove: f['toMove'] as int? ?? 0,
      reason: result?['reason'] as String?,
      winner: result?['winner'] as int?,
      drawOfferBy: f['drawOfferBy'] as int?,
      lastDrawOfferPly: [for (final v in (f['lastDrawOfferPly'] as List? ?? const [-100, -100])) v as int],
      deadline: f['deadline'] as DateTime?,
      reminderSent: f['reminderSent'] as bool? ?? false,
      rematchId: f['rematchId'] as String?,
      rated: f['rated'] as bool? ?? false,
      challenger: f['challenger'] as String?,
      ratingApplied: f['ratingApplied'] as bool? ?? false,
      ratingsAtStart: [for (final v in (f['ratingsAtStart'] as List? ?? const [])) (v as num).toInt()],
      emotes: [for (final e in (f['emotes'] as List? ?? const [])) Map<String, Object?>.from(e as Map)],
      createdAt: f['createdAt'] as DateTime,
      updatedAt: f['updatedAt'] as DateTime,
    );
  }
}

/// Perfil en `users/{uid}`: nombre de usuario (lo escribe solo el servidor)
/// y preferencias de avisos (las escribe la app).
class UserProfile {
  final String? username;
  final DateTime? usernameChangedAt;
  final bool notify;
  final bool reminders;

  /// Idioma de la app (`es` o `en`), para los avisos.
  final String? locale;

  /// Compró «quitar anuncios» (lo escribe solo el servidor).
  final bool adFree;

  /// Acepta solicitudes de amistad (preferencia de la app).
  final bool friendRequests;
  const UserProfile(
      {this.username,
      this.usernameChangedAt,
      this.notify = true,
      this.reminders = true,
      this.locale,
      this.adFree = false,
      this.friendRequests = true});
}

class Versioned<T> {
  final T value;

  /// `updateTime` de Firestore (o un contador en memoria).
  final String version;
  const Versioned(this.value, this.version);
}
