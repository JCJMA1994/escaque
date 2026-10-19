import 'dart:math';

import 'errors.dart';
import 'glicko.dart';
import 'model.dart';
import 'social_model.dart';

/// Persistencia de partidas, invitaciones y dispositivos. Todas las
/// escrituras de partidas son condicionales a la versión leída.
abstract interface class GameStore {
  String newGameId();

  Future<Versioned<GameRecord>?> getGame(String id);

  /// Crea la partida y `invites/{code}`. [ConflictException] si el código ya existe.
  Future<void> createGame(GameRecord game);

  Future<String?> gameIdForCode(String code);

  /// Crea [next] (ya activa, sin invitación) y marca [current] con su id en la
  /// misma escritura. [ConflictException] si [current] cambió.
  Future<void> createRematch(Versioned<GameRecord> current, GameRecord next);

  /// Sustituye la partida si sigue en [current.version] ([ConflictException]
  /// si no). Con [deleteInvite], borra esa invitación en la misma escritura.
  Future<void> updateGame(Versioned<GameRecord> current, GameRecord next, {String? deleteInvite});

  Future<int> countWaiting(String uid);

  /// Partidas activas cuyo plazo vence antes de [t].
  Future<List<Versioned<GameRecord>>> activeDueBefore(DateTime t);

  /// Partidas en espera creadas antes de [t].
  Future<List<Versioned<GameRecord>>> waitingCreatedBefore(DateTime t);

  /// Todas las partidas en las que participa [uid].
  Future<List<Versioned<GameRecord>>> gamesOf(String uid);

  /// Borra `users/{uid}`, sus dispositivos y libera su nombre de usuario.
  Future<void> deleteUserData(String uid);

  /// Perfil del usuario (valores por defecto si no existe).
  Future<UserProfile> userProfile(String uid);

  /// uid dueño de [username], o `null` si está libre.
  Future<String?> usernameOwner(String username);

  // ---- Amistades
  Future<Versioned<Friendship>?> getFriendship(String key);

  /// Crea ([current] `null`) o actualiza con precondición. [ConflictException] si cambió.
  Future<void> putFriendship(Versioned<Friendship>? current, Friendship next);
  Future<void> deleteFriendship(String key);
  Future<List<Friendship>> friendshipsOf(String uid);

  /// Solicitudes enviadas por [uid] desde [since].
  Future<int> countRequestsSince(String uid, DateTime since);

  // ---- Valoraciones
  Future<Versioned<RatingsDoc>?> getRatings(String uid);

  /// Marca la partida como valorada y escribe las valoraciones en la misma
  /// escritura (precondiciones en todo). [ConflictException] si algo cambió.
  Future<void> applyRatings(Versioned<GameRecord> current, GameRecord next,
      Map<String, (Versioned<RatingsDoc>?, RatingsDoc)> ratings);

  /// Partidas valoradas terminadas cuya valoración no se aplicó (barrido).
  Future<List<String>> finishedUnrated({int limit = 50});

  /// Mejores valoraciones de un juego.
  Future<List<(String uid, Rating rating)>> topRatings(String key, {int limit = 300});
  Future<void> saveLeaderboard(String key, List<LeaderboardEntry> entries, DateTime at);

  /// Compras (clave: hash del token de Google Play).
  Future<String?> purchaseOwner(String key);
  Future<void> recordPurchase(String key, {required String uid, String? orderId, required DateTime at});
  Future<void> revokePurchase(String key, {required DateTime at});
  Future<void> setAdFree(String uid, bool adFree);

  /// Reserva [username] para [uid] y libera [previous] en la misma escritura.
  /// [ConflictException] si otro lo reservó antes.
  Future<void> setUsername(String uid, String username, {String? previous, required DateTime at});
  Future<List<String>> deviceTokens(String uid);
  Future<void> deleteDeviceToken(String uid, String token);
}

/// Almacén en memoria para tests y desarrollo local.
class InMemoryStore implements GameStore {
  final _games = <String, Versioned<GameRecord>>{};
  final _invites = <String, String>{};
  final profiles = <String, UserProfile>{};
  final purchases = <String, ({String uid, String? orderId, bool revoked})>{};
  final friendships = <String, Versioned<Friendship>>{};
  final ratingsDocs = <String, Versioned<RatingsDoc>>{};
  final leaderboards = <String, List<LeaderboardEntry>>{};
  final usernames = <String, String>{};
  final devices = <String, Set<String>>{};
  var _version = 0;
  final _random = Random(7);

  Map<String, String> get invites => Map.unmodifiable(_invites);

  @override
  String newGameId() => 'g${_random.nextInt(1 << 30)}';

  @override
  Future<Versioned<GameRecord>?> getGame(String id) async => _games[id];

  @override
  Future<void> createGame(GameRecord game) async {
    if ((game.code.isNotEmpty && _invites.containsKey(game.code)) || _games.containsKey(game.id)) {
      throw const ConflictException();
    }
    if (game.code.isNotEmpty) _invites[game.code] = game.id;
    _games[game.id] = Versioned(game, '${++_version}');
  }

  @override
  Future<String?> gameIdForCode(String code) async => _invites[code];

  @override
  Future<void> createRematch(Versioned<GameRecord> current, GameRecord next) async {
    final old = current.value;
    if (_games[old.id]?.version != current.version || _games.containsKey(next.id)) {
      throw const ConflictException();
    }
    _games[old.id] = Versioned(old.copyWith(rematchId: next.id, updatedAt: next.createdAt), '${++_version}');
    _games[next.id] = Versioned(next, '${++_version}');
  }

  @override
  Future<void> updateGame(Versioned<GameRecord> current, GameRecord next, {String? deleteInvite}) async {
    if (_games[next.id]?.version != current.version) throw const ConflictException();
    _games[next.id] = Versioned(next, '${++_version}');
    if (deleteInvite != null) _invites.remove(deleteInvite);
  }

  @override
  Future<int> countWaiting(String uid) async =>
      _games.values.where((v) => v.value.isWaiting && v.value.members.contains(uid)).length;

  @override
  Future<List<Versioned<GameRecord>>> activeDueBefore(DateTime t) async => [
        for (final v in _games.values)
          if (v.value.isActive && v.value.deadline != null && !v.value.deadline!.isAfter(t)) v
      ];

  @override
  Future<List<Versioned<GameRecord>>> waitingCreatedBefore(DateTime t) async => [
        for (final v in _games.values)
          if (v.value.isWaiting && !v.value.createdAt.isAfter(t)) v
      ];

  @override
  Future<List<Versioned<GameRecord>>> gamesOf(String uid) async =>
      [for (final v in _games.values) if (v.value.members.contains(uid)) v];

  @override
  Future<void> deleteUserData(String uid) async {
    final name = profiles.remove(uid)?.username;
    if (name != null) usernames.remove(name);
    friendships.removeWhere((_, v) => v.value.users.contains(uid));
    ratingsDocs.remove(uid);
    devices.remove(uid);
  }

  @override
  Future<UserProfile> userProfile(String uid) async => profiles[uid] ?? const UserProfile();

  @override
  Future<String?> usernameOwner(String username) async => usernames[username];

  @override
  Future<Versioned<Friendship>?> getFriendship(String key) async => friendships[key];

  @override
  Future<void> putFriendship(Versioned<Friendship>? current, Friendship next) async {
    final now = friendships[next.key];
    if (current == null ? now != null : now?.version != current.version) throw const ConflictException();
    friendships[next.key] = Versioned(next, '${++_version}');
  }

  @override
  Future<void> deleteFriendship(String key) async => friendships.remove(key);

  @override
  Future<List<Friendship>> friendshipsOf(String uid) async =>
      [for (final v in friendships.values) if (v.value.users.contains(uid)) v.value];

  @override
  Future<int> countRequestsSince(String uid, DateTime since) async => friendships.values
      .where((v) => v.value.requestedBy == uid && !v.value.createdAt.isBefore(since))
      .length;

  @override
  Future<Versioned<RatingsDoc>?> getRatings(String uid) async => ratingsDocs[uid];

  @override
  Future<void> applyRatings(Versioned<GameRecord> current, GameRecord next,
      Map<String, (Versioned<RatingsDoc>?, RatingsDoc)> ratings) async {
    if (_games[current.value.id]?.version != current.version) throw const ConflictException();
    for (final e in ratings.entries) {
      final (cur, _) = e.value;
      if (cur == null ? ratingsDocs.containsKey(e.key) : ratingsDocs[e.key]?.version != cur.version) {
        throw const ConflictException();
      }
    }
    _games[next.id] = Versioned(next, '${++_version}');
    for (final e in ratings.entries) {
      ratingsDocs[e.key] = Versioned(e.value.$2, '${++_version}');
    }
  }

  @override
  Future<List<String>> finishedUnrated({int limit = 50}) async => [
        for (final v in _games.values)
          if (v.value.status == 'finished' && v.value.rated && !v.value.ratingApplied) v.value.id,
      ].take(limit).toList();

  @override
  Future<List<(String uid, Rating rating)>> topRatings(String key, {int limit = 300}) async {
    final all = [
      for (final e in ratingsDocs.entries)
        if (e.value.value.ratings.containsKey(key)) (e.key, e.value.value.ratings[key]!),
    ]..sort((a, b) => b.$2.rating.compareTo(a.$2.rating));
    return all.take(limit).toList();
  }

  @override
  Future<void> saveLeaderboard(String key, List<LeaderboardEntry> entries, DateTime at) async =>
      leaderboards[key] = entries;

  @override
  Future<String?> purchaseOwner(String key) async => purchases[key]?.uid;

  @override
  Future<void> recordPurchase(String key, {required String uid, String? orderId, required DateTime at}) async =>
      purchases[key] = (uid: uid, orderId: orderId, revoked: false);

  @override
  Future<void> revokePurchase(String key, {required DateTime at}) async {
    final p = purchases[key];
    if (p != null) purchases[key] = (uid: p.uid, orderId: p.orderId, revoked: true);
  }

  @override
  Future<void> setAdFree(String uid, bool adFree) async {
    final p = profiles[uid] ?? const UserProfile();
    profiles[uid] = UserProfile(
      username: p.username,
      usernameChangedAt: p.usernameChangedAt,
      notify: p.notify,
      reminders: p.reminders,
      locale: p.locale,
      adFree: adFree,
    );
  }

  @override
  Future<void> setUsername(String uid, String username, {String? previous, required DateTime at}) async {
    final owner = usernames[username];
    if (owner != null && owner != uid) throw const ConflictException();
    if (previous != null && previous != username) usernames.remove(previous);
    usernames[username] = uid;
    final p = profiles[uid] ?? const UserProfile();
    profiles[uid] = UserProfile(
      username: username,
      usernameChangedAt: at,
      notify: p.notify,
      reminders: p.reminders,
      locale: p.locale,
      adFree: p.adFree,
    );
  }

  @override
  Future<List<String>> deviceTokens(String uid) async => [...?devices[uid]];

  @override
  Future<void> deleteDeviceToken(String uid, String token) async => devices[uid]?.remove(token);
}
