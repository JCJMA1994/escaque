import 'dart:math';

import 'package:googleapis/firestore/v1.dart' as fs;

import 'errors.dart';
import 'glicko.dart';
import 'model.dart';
import 'social_model.dart';
import 'store.dart';

/// [GameStore] sobre la API REST de Firestore con la cuenta de servicio de
/// Cloud Run. Las escrituras llevan precondición de `updateTime`: si otro
/// proceso escribió antes, Firestore rechaza y se lanza [ConflictException].
class FirestoreStore implements GameStore {
  final fs.FirestoreApi api;
  final String projectId;
  final _random = Random.secure();

  FirestoreStore(this.api, this.projectId);

  String get _database => 'projects/$projectId/databases/(default)';
  String get _documents => '$_database/documents';
  String _game(String id) => '$_documents/games/$id';
  String _invite(String code) => '$_documents/invites/$code';

  fs.ProjectsDatabasesDocumentsResource get _docs => api.projects.databases.documents;

  @override
  String newGameId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(20, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  @override
  Future<Versioned<GameRecord>?> getGame(String id) async {
    final doc = await _get(_game(id));
    return doc == null ? null : _versioned(doc);
  }

  @override
  Future<void> createGame(GameRecord game) => _commit([
        // Los retos entre amigos y las revanchas no tienen código de invitación.
        if (game.code.isNotEmpty)
          fs.Write(
            update: fs.Document(name: _invite(game.code), fields: _encodeMap({'gameId': game.id, 'createdAt': game.createdAt})),
            currentDocument: fs.Precondition(exists: false),
          ),
        fs.Write(
          update: fs.Document(name: _game(game.id), fields: _encodeMap(game.toFields())),
          currentDocument: fs.Precondition(exists: false),
        ),
      ]);

  @override
  Future<String?> gameIdForCode(String code) async {
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) return null;
    final doc = await _get(_invite(code));
    return doc?.fields?['gameId']?.stringValue;
  }

  @override
  Future<void> createRematch(Versioned<GameRecord> current, GameRecord next) {
    final old = current.value.copyWith(rematchId: next.id, updatedAt: next.createdAt);
    return _commit([
      fs.Write(
        update: fs.Document(name: _game(old.id), fields: _encodeMap(old.toFields())),
        currentDocument: fs.Precondition(updateTime: current.version),
      ),
      fs.Write(
        update: fs.Document(name: _game(next.id), fields: _encodeMap(next.toFields())),
        currentDocument: fs.Precondition(exists: false),
      ),
    ]);
  }

  @override
  Future<void> updateGame(Versioned<GameRecord> current, GameRecord next, {String? deleteInvite}) => _commit([
        fs.Write(
          update: fs.Document(name: _game(next.id), fields: _encodeMap(next.toFields())),
          currentDocument: fs.Precondition(updateTime: current.version),
        ),
        if (deleteInvite != null && deleteInvite.isNotEmpty) fs.Write(delete: _invite(deleteInvite)),
      ]);

  @override
  Future<int> countWaiting(String uid) async => (await _query([
        _filter('members', 'ARRAY_CONTAINS', uid),
        _filter('status', 'EQUAL', 'waiting'),
      ], limit: 50))
          .length;

  @override
  Future<List<Versioned<GameRecord>>> activeDueBefore(DateTime t) => _query([
        _filter('status', 'EQUAL', 'active'),
        _filter('deadline', 'LESS_THAN_OR_EQUAL', t),
      ]);

  @override
  Future<List<Versioned<GameRecord>>> waitingCreatedBefore(DateTime t) => _query([
        _filter('status', 'EQUAL', 'waiting'),
        _filter('createdAt', 'LESS_THAN_OR_EQUAL', t),
      ]);

  @override
  Future<List<Versioned<GameRecord>>> gamesOf(String uid) =>
      _query([_filter('members', 'ARRAY_CONTAINS', uid)], limit: 500);

  @override
  Future<void> deleteUserData(String uid) async {
    final tokens = await deviceTokens(uid);
    final name = (await userProfile(uid)).username;
    final friends = await friendshipsOf(uid);
    await _commit([
      for (final t in tokens) fs.Write(delete: '$_documents/users/$uid/devices/$t'),
      if (name != null) fs.Write(delete: _username(name)),
      for (final f in friends) fs.Write(delete: _friendship(f.key)),
      fs.Write(delete: _ratings(uid)),
      fs.Write(delete: '$_documents/users/$uid'),
    ]);
  }

  String _username(String name) => '$_documents/usernames/$name';
  String _purchase(String key) => '$_documents/purchases/$key';
  String _friendship(String key) => '$_documents/friendships/$key';
  String _ratings(String uid) => '$_documents/ratings/$uid';

  /// Consulta genérica sobre cualquier colección.
  Future<List<fs.Document>> _queryDocs(String collection, List<fs.Filter> filters,
      {List<fs.Order>? orderBy, int limit = 200}) async {
    final res = await _docs.runQuery(
      fs.RunQueryRequest(
        structuredQuery: fs.StructuredQuery(
          from: [fs.CollectionSelector(collectionId: collection)],
          where: filters.isEmpty
              ? null
              : filters.length == 1
                  ? filters.single
                  : fs.Filter(compositeFilter: fs.CompositeFilter(op: 'AND', filters: filters)),
          orderBy: orderBy,
          limit: limit,
        ),
      ),
      _documents,
    );
    return [for (final r in res) if (r.document != null) r.document!];
  }

  fs.Precondition _pre(String? version) =>
      version == null ? fs.Precondition(exists: false) : fs.Precondition(updateTime: version);

  @override
  Future<Versioned<Friendship>?> getFriendship(String key) async {
    final d = await _get(_friendship(key));
    return d == null ? null : Versioned(Friendship.fromFields(_decodeMap(d.fields ?? const {})), d.updateTime!);
  }

  @override
  Future<void> putFriendship(Versioned<Friendship>? current, Friendship next) => _commit([
        fs.Write(
          update: fs.Document(name: _friendship(next.key), fields: _encodeMap(next.toFields())),
          currentDocument: _pre(current?.version),
        ),
      ]);

  @override
  Future<void> deleteFriendship(String key) => _commit([fs.Write(delete: _friendship(key))]);

  @override
  Future<List<Friendship>> friendshipsOf(String uid) async => [
        for (final d in await _queryDocs('friendships', [_filter('users', 'ARRAY_CONTAINS', uid)], limit: 500))
          Friendship.fromFields(_decodeMap(d.fields ?? const {})),
      ];

  @override
  Future<int> countRequestsSince(String uid, DateTime since) async => (await _queryDocs('friendships', [
        _filter('requestedBy', 'EQUAL', uid),
        _filter('createdAt', 'GREATER_THAN_OR_EQUAL', since),
      ], limit: 100))
          .length;

  @override
  Future<Versioned<RatingsDoc>?> getRatings(String uid) async {
    final d = await _get(_ratings(uid));
    return d == null ? null : Versioned(RatingsDoc.fromFields(_decodeMap(d.fields ?? const {})), d.updateTime!);
  }

  @override
  Future<void> applyRatings(Versioned<GameRecord> current, GameRecord next,
          Map<String, (Versioned<RatingsDoc>?, RatingsDoc)> ratings) =>
      _commit([
        fs.Write(
          update: fs.Document(name: _game(next.id), fields: _encodeMap(next.toFields())),
          currentDocument: fs.Precondition(updateTime: current.version),
        ),
        for (final e in ratings.entries)
          fs.Write(
            update: fs.Document(name: _ratings(e.key), fields: _encodeMap(e.value.$2.toFields())),
            currentDocument: _pre(e.value.$1?.version),
          ),
      ]);

  @override
  Future<List<String>> finishedUnrated({int limit = 50}) async => [
        for (final d in await _queryDocs('games', [
          _filter('status', 'EQUAL', 'finished'),
          _filter('rated', 'EQUAL', true),
          _filter('ratingApplied', 'EQUAL', false),
        ], limit: limit))
          d.name!.split('/').last,
      ];

  @override
  Future<List<(String uid, Rating rating)>> topRatings(String key, {int limit = 300}) async => [
        for (final d in await _queryDocs('ratings', const [],
            orderBy: [fs.Order(field: fs.FieldReference(fieldPath: 'ratings.$key.r'), direction: 'DESCENDING')],
            limit: limit))
          (d.name!.split('/').last, RatingsDoc.fromFields(_decodeMap(d.fields ?? const {})).of(key)),
      ];

  @override
  Future<void> saveLeaderboard(String key, List<LeaderboardEntry> entries, DateTime at) => _commit([
        fs.Write(
          update: fs.Document(
            name: '$_documents/leaderboards/$key',
            fields: _encodeMap({
              'updatedAt': at,
              'entries': [
                for (final e in entries) {'uid': e.uid, 'username': e.username, 'rating': e.rating, 'games': e.games},
              ],
            }),
          ),
        ),
      ]);

  @override
  Future<String?> purchaseOwner(String key) async => (await _get(_purchase(key)))?.fields?['uid']?.stringValue;

  @override
  Future<void> recordPurchase(String key, {required String uid, String? orderId, required DateTime at}) => _commit([
        fs.Write(
          update: fs.Document(
            name: _purchase(key),
            fields: _encodeMap({'uid': uid, 'orderId': orderId ?? '', 'createdAt': at, 'revoked': false}),
          ),
        ),
      ]);

  @override
  Future<void> revokePurchase(String key, {required DateTime at}) => _commit([
        fs.Write(
          update: fs.Document(name: _purchase(key), fields: _encodeMap({'revoked': true, 'revokedAt': at})),
          updateMask: fs.DocumentMask(fieldPaths: ['revoked', 'revokedAt']),
        ),
      ]);

  @override
  Future<void> setAdFree(String uid, bool adFree) => _commit([
        fs.Write(
          update: fs.Document(name: '$_documents/users/$uid', fields: _encodeMap({'adFree': adFree})),
          updateMask: fs.DocumentMask(fieldPaths: ['adFree']),
        ),
      ]);

  @override
  Future<UserProfile> userProfile(String uid) async {
    final f = (await _get('$_documents/users/$uid'))?.fields;
    final changed = f?['usernameChangedAt']?.timestampValue;
    return UserProfile(
      username: f?['username']?.stringValue,
      usernameChangedAt: changed == null ? null : DateTime.parse(changed).toUtc(),
      notify: f?['notify']?.booleanValue ?? true,
      reminders: f?['reminders']?.booleanValue ?? true,
      locale: f?['locale']?.stringValue,
      adFree: f?['adFree']?.booleanValue ?? false,
      friendRequests: f?['friendRequests']?.booleanValue ?? true,
    );
  }

  @override
  Future<String?> usernameOwner(String username) async =>
      (await _get(_username(username)))?.fields?['uid']?.stringValue;

  @override
  Future<void> setUsername(String uid, String username, {String? previous, required DateTime at}) => _commit([
        // exists:false garantiza la unicidad aunque dos personas lo pidan a la vez.
        fs.Write(
          update: fs.Document(name: _username(username), fields: _encodeMap({'uid': uid, 'createdAt': at})),
          currentDocument: fs.Precondition(exists: false),
        ),
        if (previous != null && previous != username) fs.Write(delete: _username(previous)),
        // Solo estos campos: las preferencias de avisos de la app se conservan.
        fs.Write(
          update: fs.Document(
            name: '$_documents/users/$uid',
            fields: _encodeMap({'username': username, 'usernameChangedAt': at}),
          ),
          updateMask: fs.DocumentMask(fieldPaths: ['username', 'usernameChangedAt']),
        ),
      ]);

  @override
  Future<List<String>> deviceTokens(String uid) async {
    final res = await _docs.list('$_documents/users/$uid', 'devices', pageSize: 20);
    return [for (final d in res.documents ?? const <fs.Document>[]) d.name!.split('/').last];
  }

  @override
  Future<void> deleteDeviceToken(String uid, String token) async {
    try {
      await _docs.delete('$_documents/users/$uid/devices/$token');
    } on fs.DetailedApiRequestError catch (e) {
      if (e.status != 404) rethrow;
    }
  }

  // ---- REST ---------------------------------------------------------------

  Future<fs.Document?> _get(String name) async {
    try {
      return await _docs.get(name);
    } on fs.DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> _commit(List<fs.Write> writes) async {
    try {
      await _docs.commit(fs.CommitRequest(writes: writes), _database);
    } on fs.DetailedApiRequestError catch (e) {
      // Precondición fallida (updateTime distinto o el documento ya existe).
      final text = '${e.message} ${e.jsonResponse}'.toUpperCase();
      final conflict = e.status == 409 ||
          (e.status == 400 && (text.contains('FAILED_PRECONDITION') || text.contains('ALREADY_EXISTS'))) ||
          text.contains('PRECONDITION');
      if (conflict) throw const ConflictException();
      rethrow;
    }
  }

  fs.Filter _filter(String field, String op, Object value) => fs.Filter(
        fieldFilter: fs.FieldFilter(field: fs.FieldReference(fieldPath: field), op: op, value: _encode(value)),
      );

  Future<List<Versioned<GameRecord>>> _query(List<fs.Filter> filters, {int limit = 200}) async {
    final res = await _docs.runQuery(
      fs.RunQueryRequest(
        structuredQuery: fs.StructuredQuery(
          from: [fs.CollectionSelector(collectionId: 'games')],
          where: filters.length == 1
              ? filters.single
              : fs.Filter(compositeFilter: fs.CompositeFilter(op: 'AND', filters: filters)),
          limit: limit,
        ),
      ),
      _documents,
    );
    return [for (final r in res) if (r.document != null) _versioned(r.document!)];
  }

  Versioned<GameRecord> _versioned(fs.Document d) => Versioned(
        GameRecord.fromFields(d.name!.split('/').last, _decodeMap(d.fields ?? const {})),
        d.updateTime!,
      );

  // ---- Conversión Dart ↔ Value de Firestore ----------------------------------

  static Map<String, fs.Value> _encodeMap(Map<String, Object?> m) =>
      {for (final e in m.entries) e.key: _encode(e.value)};

  static fs.Value _encode(Object? v) => switch (v) {
        null => fs.Value(nullValue: 'NULL_VALUE'),
        final bool b => fs.Value(booleanValue: b),
        final int i => fs.Value(integerValue: '$i'),
        final double d => fs.Value(doubleValue: d),
        final String s => fs.Value(stringValue: s),
        final DateTime t => fs.Value(timestampValue: t.toUtc().toIso8601String()),
        final List<Object?> l => fs.Value(arrayValue: fs.ArrayValue(values: [for (final x in l) _encode(x)])),
        final Map<String, Object?> m => fs.Value(mapValue: fs.MapValue(fields: _encodeMap(m))),
        _ => throw ArgumentError('Tipo no admitido en Firestore: ${v.runtimeType}'),
      };

  static Map<String, Object?> _decodeMap(Map<String, fs.Value> m) =>
      {for (final e in m.entries) e.key: _decode(e.value)};

  static Object? _decode(fs.Value v) {
    if (v.nullValue != null) return null;
    if (v.booleanValue != null) return v.booleanValue;
    if (v.integerValue != null) return int.parse(v.integerValue!);
    if (v.doubleValue != null) return v.doubleValue;
    if (v.stringValue != null) return v.stringValue;
    if (v.timestampValue != null) return DateTime.parse(v.timestampValue!).toUtc();
    if (v.arrayValue != null) return [for (final x in v.arrayValue!.values ?? const <fs.Value>[]) _decode(x)];
    if (v.mapValue != null) return _decodeMap(v.mapValue!.fields ?? const {});
    return null;
  }
}
