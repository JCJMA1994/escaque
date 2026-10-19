import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../match/match_config.dart';
import 'api_client.dart';
import '../l10n/l10n.dart';

class OnlineException implements Exception {
  final String message;

  /// Código estable del servidor: `stale`, `illegal_move`, `not_your_turn`…
  final String? code;

  /// Jugadas que tiene el servidor, cuando la jugada llegó desfasada.
  final int? serverPly;

  const OnlineException(this.message, {this.code, this.serverPly});
  @override
  String toString() => message;
}

/// Partida online tal como está en Firestore (`games/{id}`).
class OnlineGame {
  final String id;
  final GameKind kind;
  final String variantId;

  /// uid por asiento (0 = blancas). Cadena vacía = asiento libre.
  final List<String> players;
  final List<String> names;
  final String code;

  /// `waiting`, `active` o `finished`.
  final String status;
  final List<String> moves;
  final int toMove;
  final int? winner;
  final String? reason;

  /// Asiento que ofrece tablas, o `null`.
  final int? drawOfferBy;
  final DateTime? updatedAt;

  /// Límite para la próxima jugada.
  final DateTime? deadline;

  /// Partida valorada y valoración de cada jugador al empezar.
  final bool rated;

  /// Uid de quien retó, en los retos entre amigos.
  final String? challenger;
  final List<int> ratingsAtStart;

  /// Últimas frases fijas: (asiento, id de frase, cuándo).
  final List<({int seat, String phrase, DateTime? at})> emotes;

  const OnlineGame({
    required this.id,
    required this.kind,
    required this.variantId,
    required this.players,
    required this.names,
    required this.code,
    required this.status,
    required this.moves,
    required this.toMove,
    this.winner,
    this.reason,
    this.drawOfferBy,
    this.updatedAt,
    this.deadline,
    this.rated = false,
    this.challenger,
    this.ratingsAtStart = const [],
    this.emotes = const [],
  });

  bool get waiting => status == 'waiting';
  bool get finished => status == 'finished' || status == 'cancelled';
  bool get cancelled => status == 'cancelled';
  int seatOf(String uid) => players.indexOf(uid);

  factory OnlineGame.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final result = d['result'] as Map<String, dynamic>?;
    return OnlineGame(
      id: doc.id,
      kind: GameKind.values.byName(d['kind'] as String),
      variantId: d['variant'] as String? ?? 'spanish',
      players: List<String>.from(d['players'] as List),
      names: List<String>.from(d['names'] as List),
      code: d['code'] as String,
      status: d['status'] as String,
      moves: List<String>.from(d['moves'] as List),
      toMove: d['toMove'] as int,
      winner: result?['winner'] as int?,
      reason: result?['reason'] as String?,
      drawOfferBy: d['drawOfferBy'] as int?,
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      deadline: (d['deadline'] as Timestamp?)?.toDate(),
      rated: d['rated'] as bool? ?? false,
      challenger: d['challenger'] as String?,
      ratingsAtStart: [for (final r in (d['ratingsAtStart'] as List? ?? const [])) (r as num).toInt()],
      emotes: [
        for (final e in (d['emotes'] as List? ?? const []))
          if (e is Map)
            (seat: (e['seat'] as num?)?.toInt() ?? 0, phrase: e['phrase'] as String? ?? '', at: (e['at'] as Timestamp?)?.toDate()),
      ],
    );
  }
}

/// Partidas online. Las LECTURAS van directas a Firestore (tiempo real); las
/// ESCRITURAS pasan por tablero_server, que valida con el motor y es la única
/// fuente de verdad. Las reglas de Firestore prohíben escribir partidas desde
/// el cliente.
class OnlineRepository {
  final ApiClient api;
  OnlineRepository([ApiClient? api]) : api = api ?? ApiClient();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  CollectionReference<Map<String, dynamic>> get _games =>
      FirebaseFirestore.instance.collection('games');

  String? get uid => _auth.currentUser?.uid;

  /// Online exige una cuenta registrada (ver tool/accounts.md).
  Future<String> ensureSignedIn() async {
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw OnlineException(tr('Inicia sesión con tu cuenta para jugar online.'), code: 'account_required');
    }
    return current.uid;
  }

  /// Crea una partida y devuelve su id y código.
  Future<({String id, String code})> create({
    required GameKind kind,
    required String variantId,
    required int seat,
  }) async {
    // El nombre que ve el rival es el nombre de usuario: lo pone el servidor.
    final r = await api.post('/v1/games', {'kind': kind.name, 'variant': variantId, 'seat': seat});
    return (id: r['id'] as String, code: r['code'] as String);
  }

  /// Se une con un código. Devuelve id, asiento, juego y variante.
  Future<({String id, int seat, GameKind kind, String variantId})> joinByCode(String code) async {
    final r = await api.post('/v1/games/join', {'code': code.trim().toUpperCase()});
    return (
      id: r['id'] as String,
      seat: r['seat'] as int,
      kind: GameKind.values.byName(r['kind'] as String),
      variantId: (r['variant'] as String?)?.isNotEmpty == true ? r['variant'] as String : 'spanish',
    );
  }

  Future<OnlineGame?> getGame(String id) async {
    await ensureSignedIn();
    final snap = await _games.doc(id).get();
    return snap.exists ? OnlineGame.fromDoc(snap) : null;
  }

  Stream<OnlineGame> watch(String id) =>
      _games.doc(id).snapshots().where((s) => s.exists).map(OnlineGame.fromDoc);

  /// Partidas donde participo, la más reciente primero.
  Stream<List<OnlineGame>> myGames() async* {
    final me = await ensureSignedIn();
    yield* _games.where('members', arrayContains: me).snapshots().map((q) {
      final list = q.docs.map(OnlineGame.fromDoc).toList();
      list.sort((a, b) => (b.updatedAt ?? DateTime(2100)).compareTo(a.updatedAt ?? DateTime(2100)));
      return list;
    });
  }

  /// Envía una jugada. [expectedPly] = jugadas antes de esta. El servidor la
  /// valida y calcula el resultado; el cliente no declara nada.
  Future<void> submitMove({required String id, required int expectedPly, required String code}) =>
      api.post('/v1/games/$id/moves', {'ply': expectedPly, 'move': code});

  /// Revancha: nueva partida con los colores cambiados, sin código.
  Future<({String id, int seat})> rematch(String id) async {
    final r = await api.post('/v1/games/$id/rematch');
    return (id: r['id'] as String, seat: r['seat'] as int);
  }

  /// Abandona una partida activa o cancela una que espera rival.
  Future<void> resign(String id) => api.post('/v1/games/$id/resign');

  /// Rechazar un reto (solo el retado, antes de su primera jugada).
  Future<void> declineChallenge(String id) => api.post('/v1/games/$id/decline');

  Future<void> emote(String id, String phrase) => api.post('/v1/games/$id/emote', {'phrase': phrase});

  // ---- Amistades y retos
  Future<String> requestFriend(String username) async =>
      (await api.post('/v1/friends/request', {'username': username}))['status'] as String? ?? 'pending';
  Future<void> respondFriend(String uid, {required bool accept}) =>
      api.post('/v1/friends/respond', {'uid': uid, 'accept': accept});
  Future<void> removeFriend(String uid) => api.post('/v1/friends/remove', {'uid': uid});
  Future<void> blockFriend(String uid) => api.post('/v1/friends/block', {'uid': uid});
  Future<void> unblockFriend(String uid) => api.post('/v1/friends/unblock', {'uid': uid});

  /// Reto directo: devuelve el id de la partida (ya activa) y el asiento.
  Future<({String id, int seat})> challenge(String uid,
      {required GameKind kind, String variant = '', required int seat, required bool rated}) async {
    final r = await api.post('/v1/friends/challenge',
        {'uid': uid, 'kind': kind.name, 'variant': variant, 'seat': seat, 'rated': rated});
    return (id: r['id'] as String, seat: (r['seat'] as num).toInt());
  }

  /// Amistades de la cuenta (solicitudes, amigos y bloqueos), en vivo.
  Stream<List<Friend>> friends() {
    final me = uid;
    if (me == null) return Stream.value(const []);
    return FirebaseFirestore.instance
        .collection('friendships')
        .where('users', arrayContains: me)
        .snapshots()
        .map((s) => [for (final d in s.docs) Friend.fromDoc(d.data(), me)]
          ..sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase())));
  }

  /// Valoraciones propias (`ratings/{uid}`), en vivo.
  Stream<Map<String, ({int rating, int games, bool provisional})>> myRatings() {
    final me = uid;
    if (me == null) return Stream.value(const {});
    return FirebaseFirestore.instance.doc('ratings/$me').snapshots().map((s) {
      final r = (s.data()?['ratings'] as Map?) ?? const {};
      return {
        for (final e in r.entries)
          if (e.value is Map)
            e.key as String: (
              rating: ((e.value as Map)['r'] as num? ?? 1500).round(),
              games: ((e.value as Map)['games'] as num? ?? 0).toInt(),
              provisional: ((e.value as Map)['games'] as num? ?? 0) < 5 || ((e.value as Map)['rd'] as num? ?? 350) > 150,
            ),
      };
    });
  }

  /// Clasificación de un juego (`leaderboards/{key}`).
  Future<List<({String username, int rating, int games})>> leaderboard(String key) async {
    final d = await FirebaseFirestore.instance.doc('leaderboards/$key').get();
    return [
      for (final e in (d.data()?['entries'] as List? ?? const []))
        if (e is Map)
          (username: e['username'] as String? ?? '', rating: (e['rating'] as num? ?? 0).toInt(), games: (e['games'] as num? ?? 0).toInt()),
    ];
  }

  Future<void> offerDraw(String id) => api.post('/v1/games/$id/draw', {'action': 'offer'});
  Future<void> declineDraw(String id) => api.post('/v1/games/$id/draw', {'action': 'decline'});
  Future<void> acceptDraw(String id) => api.post('/v1/games/$id/draw', {'action': 'accept'});
}

final onlineRepositoryProvider = Provider<OnlineRepository>((ref) => OnlineRepository());

/// `true` si Firebase arrancó (hay `google-services.json`).
final firebaseReadyProvider = StateProvider<bool>((ref) => false);


/// Una amistad vista desde esta cuenta.
class Friend {
  final String uid;
  final String username;

  /// `friend`, `incoming` (te la envió), `outgoing` (la enviaste) o `blocked` (la bloqueaste).
  final String state;
  const Friend({required this.uid, required this.username, required this.state});

  factory Friend.fromDoc(Map<String, dynamic> d, String me) {
    final users = List<String>.from(d['users'] as List);
    final other = users[0] == me ? users[1] : users[0];
    final status = d['status'] as String;
    final state = switch (status) {
      'accepted' => 'friend',
      'pending' => d['requestedBy'] == me ? 'outgoing' : 'incoming',
      _ => d['blockedBy'] == me ? 'blocked' : 'hidden', // si te bloquearon, no se muestra
    };
    final names = Map<String, dynamic>.from(d['names'] as Map? ?? const {});
    return Friend(uid: other, username: names[other] as String? ?? '', state: state);
  }
}
