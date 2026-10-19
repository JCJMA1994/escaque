import 'errors.dart';
import 'game_service.dart';
import 'glicko.dart';
import 'model.dart';
import 'notifier.dart';
import 'replayer.dart';
import 'social_model.dart';
import 'store.dart';
import 'usernames.dart';

/// Amistades, retos directos y valoraciones (PLAN.md, fase E).
class SocialService {
  final GameStore store;
  final Notifier notifier;
  final GameService games;
  final DateTime Function() now;

  static const maxFriends = 200, maxRequestsPerDay = 20;

  /// Medias jugadas mínimas para que una partida valorada cuente (10 por bando).
  static const minRatedPlies = 20;

  /// Partidas valoradas contra el mismo rival en 24 h a partir de las cuales ya no cuentan.
  static const maxRatedPerOpponentPerDay = 3;

  SocialService({required this.store, required this.notifier, required this.games, DateTime Function()? now})
      : now = now ?? DateTime.now;

  // ---- Amistades ---------------------------------------------------------------

  Future<String> _usernameOf(String uid) async =>
      (await store.userProfile(uid)).username ??
      (throw const ApiError(403, 'username_required', 'Elige un nombre de usuario para jugar online.'));

  /// Solicitud por nombre de usuario exacto. Si la otra persona ya te la
  /// había enviado, queda aceptada.
  Future<String> request(String uid, String rawUsername) async {
    final me = await _usernameOf(uid);
    final target = await store.usernameOwner(Usernames.normalize(rawUsername));
    if (target == null) throw const ApiError(404, 'user_not_found', 'No hay nadie con ese nombre de usuario.');
    if (target == uid) throw ApiError.badRequest('No puedes añadirte a ti.');
    final key = Friendship.keyFor(uid, target);
    final current = await store.getFriendship(key);
    final f = current?.value;
    if (f != null) {
      if (f.status == 'blocked') throw const ApiError(403, 'blocked', 'No puedes enviar una solicitud a esta persona.');
      if (f.status == 'accepted') throw const ApiError(409, 'already_friends', 'Ya sois amigos.');
      if (f.requestedBy == uid) throw const ApiError(409, 'request_pending', 'Ya le enviaste una solicitud.');
      return _accept(uid, current!); // te la había enviado
    }
    final targetProfile = await store.userProfile(target);
    if (!targetProfile.friendRequests) {
      throw const ApiError(403, 'requests_off', 'Esta persona no acepta solicitudes de amistad.');
    }
    if (await store.countRequestsSince(uid, now().subtract(const Duration(days: 1))) >= maxRequestsPerDay) {
      throw const ApiError(429, 'too_many_requests', 'Has enviado muchas solicitudes hoy. Prueba mañana.');
    }
    await _checkLimit(uid);
    final t = now();
    try {
      await store.putFriendship(
        null,
        Friendship(
          users: Friendship.sorted(uid, target),
          status: 'pending',
          requestedBy: uid,
          names: {uid: me, target: targetProfile.username ?? ''},
          createdAt: t,
          updatedAt: t,
        ),
      );
    } on ConflictException {
      throw const ApiError(409, 'request_pending', 'Ya hay una solicitud entre vosotros.');
    }
    await notifier.notify(
      target,
      Notice(NoticeKind.friendRequest, '', '${GameService.handle(me)} quiere ser tu amigo', 'Acéptalo en Jugar online → Amigos.',
          titleEn: '${GameService.handle(me)} wants to be your friend', bodyEn: 'Accept it in Play online → Friends.'),
    );
    return 'pending';
  }

  Future<void> _checkLimit(String uid) async {
    final n = (await store.friendshipsOf(uid)).where((f) => f.status == 'accepted').length;
    if (n >= maxFriends) throw const ApiError(409, 'too_many_friends', 'Has llegado al máximo de 200 amigos.');
  }

  Future<String> _accept(String uid, Versioned<Friendship> v) async {
    await _checkLimit(uid);
    final f = v.value;
    try {
      await store.putFriendship(v, f.copyWith(status: 'accepted', updatedAt: now()));
    } on ConflictException {
      throw const ApiError(409, 'stale', 'La solicitud cambió. Vuelve a intentarlo.');
    }
    final requester = f.requestedBy;
    final me = f.names[uid] ?? '';
    await notifier.notify(
      requester,
      Notice(NoticeKind.friendAccepted, '', '${GameService.handle(me)} aceptó tu solicitud', 'Ya podéis retaros directamente.',
          titleEn: '${GameService.handle(me)} accepted your request', bodyEn: 'You can now challenge each other directly.'),
    );
    return 'accepted';
  }

  /// Aceptar o rechazar una solicitud recibida.
  Future<void> respond(String uid, String other, {required bool accept}) async {
    final v = await store.getFriendship(Friendship.keyFor(uid, other));
    if (v == null || v.value.status != 'pending' || v.value.requestedBy != other) {
      throw const ApiError(404, 'no_request', 'No tienes una solicitud de esa persona.');
    }
    if (accept) {
      await _accept(uid, v);
    } else {
      await store.deleteFriendship(v.value.key);
    }
  }

  /// Quitar un amigo o cancelar una solicitud enviada.
  Future<void> remove(String uid, String other) async {
    final v = await store.getFriendship(Friendship.keyFor(uid, other));
    if (v == null) return;
    if (v.value.status == 'blocked' && v.value.blockedBy != uid) return; // no se desvela el bloqueo
    if (v.value.status == 'blocked') return; // desbloquear es otra acción
    await store.deleteFriendship(v.value.key);
  }

  Future<void> block(String uid, String other) async {
    final key = Friendship.keyFor(uid, other);
    final v = await store.getFriendship(key);
    final t = now();
    final names = {...?v?.value.names};
    final f = v?.value.copyWith(status: 'blocked', blockedBy: uid, updatedAt: t) ??
        Friendship(
          users: Friendship.sorted(uid, other),
          status: 'blocked',
          requestedBy: uid,
          blockedBy: uid,
          names: names,
          createdAt: t,
          updatedAt: t,
        );
    try {
      await store.putFriendship(v, f);
    } on ConflictException {
      throw const ApiError(409, 'stale', 'Vuelve a intentarlo.');
    }
  }

  Future<void> unblock(String uid, String other) async {
    final v = await store.getFriendship(Friendship.keyFor(uid, other));
    if (v != null && v.value.status == 'blocked' && v.value.blockedBy == uid) await store.deleteFriendship(v.value.key);
  }

  /// Nombre nuevo en las amistades de [uid] (tras cambiar de nombre de usuario).
  Future<void> rename(String uid, String username) async {
    for (final f in await store.friendshipsOf(uid)) {
      final v = await store.getFriendship(f.key);
      if (v == null) continue;
      try {
        await store.putFriendship(v, v.value.copyWith(names: {...v.value.names, uid: username}, updatedAt: now()));
      } on ConflictException {
        // Mejor esfuerzo: la siguiente vez que cambie, se corrige.
      }
    }
  }

  // ---- Retos directos ----------------------------------------------------------

  /// Partida ya activa contra un amigo (sin código). [rated]: valorada.
  Future<({String id, int seat})> challenge(String uid, String other,
      {required String kind, String variant = '', required int seat, bool rated = false}) async {
    final f = (await store.getFriendship(Friendship.keyFor(uid, other)))?.value;
    if (f == null || f.status != 'accepted') throw const ApiError(403, 'not_friends', 'Solo puedes retar a tus amigos.');
    if (!Replayer.kinds.contains(kind)) throw ApiError.badRequest('Juego no disponible online.');
    if (rated && kind == 'chineseCheckers') throw ApiError.badRequest('Las damas chinas no tienen valoración.');
    if (seat != 0 && seat != 1) throw ApiError.badRequest('Color no válido.');
    final me = await _usernameOf(uid);
    final them = await _usernameOf(other);
    final v = kind == 'draughts' ? variant : '';
    final Replayer replayer;
    try {
      replayer = Replayer.create(kind, v);
    } on Object {
      throw ApiError.badRequest('Variante de damas desconocida.');
    }
    final players = seat == 0 ? [uid, other] : [other, uid];
    final names = seat == 0 ? [me, them] : [them, me];
    final key = ratingKey(kind, v);
    final ratingsAtStart = rated
        ? [for (final p in players) (await store.getRatings(p))?.value.of(key).rating.round() ?? 1500]
        : const <int>[];
    final t = now();
    final game = GameRecord(
      id: store.newGameId(),
      kind: kind,
      variant: v,
      members: players,
      players: players,
      names: names,
      code: '',
      status: 'active',
      moves: const [],
      toMove: replayer.toMove,
      deadline: t.add(games.moveTime),
      rated: rated,
      challenger: uid,
      ratingsAtStart: ratingsAtStart,
      createdAt: t,
      updatedAt: t,
    );
    await store.createGame(game);
    final title = ServerText.gameTitle(kind, v, en: false), titleEn = ServerText.gameTitle(kind, v, en: true);
    await notifier.notify(
      other,
      Notice(NoticeKind.challenge, game.id, '${GameService.handle(me)} te reta${rated ? ' (valorada)' : ''}', title,
          titleEn: '${GameService.handle(me)} challenges you${rated ? ' (rated)' : ''}', bodyEn: titleEn),
    );
    return (id: game.id, seat: seat);
  }

  // ---- Valoraciones (Glicko-2) -------------------------------------------------

  static String ratingKey(String kind, String variant) =>
      kind == 'draughts' ? 'draughts_$variant' : (kind == 'chess' ? 'chess' : 'chinese');

  static const ratingKeys = ['chess', 'draughts_international', 'draughts_english', 'draughts_spanish'];

  /// Aplica la valoración de una partida terminada, una sola vez (idempotente).
  /// No cuenta (pero se marca) si es corta, se canceló, el rival eliminó la
  /// cuenta o ya hubo [maxRatedPerOpponentPerDay] partidas valoradas entre ambos hoy.
  Future<void> rateGame(String id) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final v = await store.getGame(id);
      if (v == null) return;
      final g = v.value;
      if (g.status != 'finished' || !g.rated || g.ratingApplied) return;
      final t = now();
      final applied = g.copyWith(ratingApplied: true, updatedAt: t);
      final skip = g.ply < minRatedPlies ||
          g.reason == 'partida cancelada' ||
          g.players.any((p) => p.isEmpty) ||
          g.names.contains(GameService.deletedName);
      try {
        if (skip) {
          await store.applyRatings(v, applied, const {});
          return;
        }
        final key = ratingKey(g.kind, g.variant);
        final docs = [for (final p in g.players) await store.getRatings(p)];
        final cutoff = t.subtract(const Duration(days: 1));
        List<DateTime> recent(int i) =>
            [for (final d in docs[i]?.value.recent[g.players[1 - i]] ?? const <DateTime>[]) if (d.isAfter(cutoff)) d];
        if (recent(0).length >= maxRatedPerOpponentPerDay) {
          await store.applyRatings(v, applied, const {});
          return;
        }
        final before = [for (final d in docs) d?.value.of(key) ?? const Rating()];
        final s0 = g.winner == null ? 0.5 : (g.winner == 0 ? 1.0 : 0.0);
        final after = [
          Glicko2.update(before[0], [(rating: before[1].rating, deviation: before[1].deviation, score: s0)]),
          Glicko2.update(before[1], [(rating: before[0].rating, deviation: before[0].deviation, score: 1 - s0)]),
        ];
        final writes = <String, (Versioned<RatingsDoc>?, RatingsDoc)>{};
        for (var i = 0; i < 2; i++) {
          final old = docs[i]?.value ?? const RatingsDoc();
          writes[g.players[i]] = (
            docs[i],
            RatingsDoc(
              ratings: {...old.ratings, key: after[i]},
              recent: {
                for (final e in old.recent.entries)
                  if (e.value.any((d) => d.isAfter(cutoff))) e.key: [for (final d in e.value) if (d.isAfter(cutoff)) d],
                g.players[1 - i]: [...recent(i), t],
              },
            ),
          );
        }
        await store.applyRatings(v, applied, writes);
        return;
      } on ConflictException {
        continue; // otra partida o escritura a la vez: se reintenta con datos nuevos
      }
    }
  }

  /// Barrido: partidas valoradas terminadas sin aplicar (p. ej. si el servidor
  /// cayó justo después de terminar una). Lo llama el trabajo de plazos.
  Future<int> sweepRatings() async {
    final ids = await store.finishedUnrated();
    for (final id in ids) {
      await rateGame(id);
    }
    return ids.length;
  }

  /// Clasificaciones: las 100 mejores valoraciones no provisionales por juego.
  Future<void> updateLeaderboards() async {
    for (final key in ratingKeys) {
      final top = <LeaderboardEntry>[];
      for (final (uid, r) in await store.topRatings(key)) {
        if (r.provisional) continue;
        final name = (await store.userProfile(uid)).username;
        if (name == null) continue;
        top.add((uid: uid, username: name, rating: r.rating.round(), games: r.games));
        if (top.length == 100) break;
      }
      await store.saveLeaderboard(key, top, now());
    }
  }
}
