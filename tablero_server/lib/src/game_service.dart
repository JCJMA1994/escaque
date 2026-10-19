import 'dart:math';

import 'errors.dart';
import 'model.dart';
import 'notifier.dart';
import 'replayer.dart';
import 'store.dart';
import 'usernames.dart';

/// Toda la lógica online. El servidor es la única fuente de verdad: reconstruye
/// cada partida con el motor, valida la jugada, calcula el resultado y avisa.
class GameService {
  final GameStore store;
  final Notifier notifier;
  final DateTime Function() now;

  /// Tiempo para mover en partidas por turnos.
  final Duration moveTime;

  /// Antelación del recordatorio antes de que venza el plazo.
  final Duration reminderBefore;

  /// Partidas en espera que se cancelan si nadie se une.
  final Duration waitingTtl;
  final int maxWaitingPerUser;

  /// Medias jugadas mínimas entre dos ofertas de tablas del mismo jugador.
  final int drawOfferGap;

  /// Tiempo mínimo entre dos cambios de nombre de usuario.
  final Duration usernameCooldown;

  final Random _random;
  static const _attempts = 4;
  static final _validId = RegExp(r'^[A-Za-z0-9]{1,40}$');
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  GameService({
    required this.store,
    required this.notifier,
    DateTime Function()? now,
    this.moveTime = const Duration(hours: 72),
    this.reminderBefore = const Duration(hours: 24),
    this.waitingTtl = const Duration(days: 7),
    this.maxWaitingPerUser = 10,
    this.drawOfferGap = 4,
    this.usernameCooldown = const Duration(days: 30),
    Random? random,
  })  : now = now ?? (() => DateTime.now().toUtc()),
        _random = random ?? Random.secure();

  // ---- Crear y unirse ---------------------------------------------------

  Future<({String id, String code})> create(
    String uid, {
    required String kind,
    required String variant,
    required int seat,
  }) async {
    if (!Replayer.kinds.contains(kind)) throw ApiError.badRequest('Juego no disponible online.');
    if (kind == 'draughts' && !Replayer.validVariant(variant)) {
      throw ApiError.badRequest('Variante de damas desconocida.');
    }
    if (seat != 0 && seat != 1) throw ApiError.badRequest('Color no válido.');
    final cleanName = await _requireUsername(uid);
    if (await store.countWaiting(uid) >= maxWaitingPerUser) {
      throw ApiError(429, 'too_many_waiting',
          'Tienes $maxWaitingPerUser partidas esperando rival. Cancela alguna antes de crear otra.',
          {'limit': maxWaitingPerUser});
    }
    final first = Replayer.create(kind, variant).toMove; // inglesa: empiezan las negras
    final t = now();
    for (var i = 0; i < 5; i++) {
      final game = GameRecord(
        id: store.newGameId(),
        kind: kind,
        variant: kind == 'draughts' ? variant : '',
        members: [uid],
        players: seat == 0 ? [uid, ''] : ['', uid],
        names: seat == 0 ? [cleanName, ''] : ['', cleanName],
        code: _newCode(),
        status: 'waiting',
        moves: const [],
        toMove: first,
        createdAt: t,
        updatedAt: t,
      );
      try {
        await store.createGame(game);
        return (id: game.id, code: game.code);
      } on ConflictException {
        continue; // código repetido: otro
      }
    }
    throw const ApiError(503, 'busy', 'No se pudo crear la partida. Inténtalo de nuevo.');
  }

  Future<({String id, int seat, String kind, String variant})> join(String uid, String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.length != 6) throw ApiError.badRequest('El código tiene 6 caracteres.');
    final cleanName = await _requireUsername(uid);
    final id = await store.gameIdForCode(normalized);
    if (id == null) {
      throw const ApiError(404, 'code_not_found', 'No hay ninguna partida esperando con ese código.');
    }
    return _retry(id, (v) async {
      final g = v.value;
      if (!g.isWaiting) throw const ApiError(409, 'already_started', 'Esa partida ya empezó.');
      if (g.members.contains(uid)) {
        throw const ApiError(409, 'own_game', 'Es tu propia partida: comparte el código con tu rival.');
      }
      final seat = g.players.indexOf('');
      final t = now();
      final next = g.copyWith(
        members: [...g.members, uid],
        players: [...g.players]..[seat] = uid,
        names: [...g.names]..[seat] = cleanName,
        status: 'active',
        deadline: t.add(moveTime),
        updatedAt: t,
      );
      await store.updateGame(v, next, deleteInvite: g.code);
      final creator = 1 - seat;
      await notifier.notify(
        g.players[creator],
        Notice(NoticeKind.opponentJoined, g.id, '${handle(cleanName)} se unió a tu partida',
            next.toMove == creator ? '${_title(g)}: te toca empezar.' : '${_title(g)}: empieza tu rival.',
            titleEn: '${handle(cleanName)} joined your game',
            bodyEn: next.toMove == creator ? '${_titleEn(g)}: your move first.' : '${_titleEn(g)}: your opponent starts.'),
      );
      return (id: g.id, seat: seat, kind: g.kind, variant: g.variant);
    });
  }

  // ---- Jugadas ------------------------------------------------------------

  /// Valida y aplica una jugada. [ply] = jugadas que el cliente cree que hay
  /// antes de esta: si no coincide, la jugada se rechaza como desfasada.
  Future<({int ply, String status, int? winner, String? reason})> move(
      String uid, String id, {required int ply, required String move}) {
    if (move.isEmpty || move.length > 64) throw ApiError.badRequest('Jugada vacía o demasiado larga.');
    return _retry(id, (v) async {
      final g = v.value;
      final seat = _seatOrThrow(g, uid);
      _requireActive(g);
      if (g.toMove != seat) throw const ApiError(409, 'not_your_turn', 'No es tu turno.');
      if (ply != g.ply) {
        throw ApiError(409, 'stale', 'La partida cambió mientras jugabas. Se ha sincronizado.', {'ply': g.ply});
      }
      final replay = _replay(g);
      if (!replay.apply(move)) {
        throw const ApiError(422, 'illegal_move', 'Esa jugada no es legal según el reglamento.');
      }
      final result = replay.result;
      final t = now();
      final next = g.copyWith(
        moves: [...g.moves, move],
        toMove: replay.toMove,
        drawOfferBy: null,
        status: result == null ? 'active' : 'finished',
        winner: result?.winner,
        reason: result?.reason,
        deadline: result == null ? t.add(moveTime) : null,
        reminderSent: false,
        updatedAt: t,
      );
      await store.updateGame(v, next);
      final opponent = g.players[1 - seat];
      if (result == null) {
        await notifier.notify(
          g.players[next.toMove],
          Notice(NoticeKind.yourTurn, g.id, 'Te toca contra ${handle(g.names[seat])}',
              '${_title(g)} · jugada ${next.ply ~/ 2 + 1}',
              titleEn: 'Your move against ${handle(g.names[seat])}',
              bodyEn: '${_titleEn(g)} · move ${next.ply ~/ 2 + 1}'),
        );
      } else {
        await notifier.notify(opponent, _gameOver(next, 1 - seat));
      }
      return (ply: next.ply, status: next.status, winner: next.winner, reason: next.reason);
    });
  }

  // ---- Revancha ----------------------------------------------------------------

  /// Nueva partida con los mismos jugadores y los colores cambiados, ya
  /// activa (sin código). Si el rival ya la pidió, devuelve esa misma.
  Future<({String id, int seat})> rematch(String uid, String id) => _retry(id, (v) async {
        final g = v.value;
        final seat = _seatOrThrow(g, uid);
        if (g.status != 'finished') {
          throw const ApiError(409, 'not_finished', 'La partida aún no ha terminado.');
        }
        if (g.rematchId != null) return (id: g.rematchId!, seat: 1 - seat);
        if (g.names.contains(deletedName) || g.players.contains('')) {
          throw const ApiError(409, 'opponent_gone', 'Tu rival ya no está disponible.');
        }
        final t = now();
        final first = Replayer.create(g.kind, g.variant).toMove;
        final next = GameRecord(
          id: store.newGameId(),
          kind: g.kind,
          variant: g.variant,
          members: g.members,
          players: [g.players[1], g.players[0]],
          names: [g.names[1], g.names[0]],
          code: '',
          status: 'active',
          moves: const [],
          toMove: first,
          deadline: t.add(moveTime),
          createdAt: t,
          updatedAt: t,
        );
        await store.createRematch(v, next);
        final opponentNewSeat = seat; // el rival pasa al asiento que deja quien pide
        await notifier.notify(
          g.players[1 - seat],
          Notice(NoticeKind.rematch, next.id, '${handle(g.names[seat])} te propone la revancha',
              next.toMove == opponentNewSeat ? '${_title(g)}: te toca empezar.' : '${_title(g)}: empieza tu rival.',
              titleEn: '${handle(g.names[seat])} wants a rematch',
              bodyEn: next.toMove == opponentNewSeat ? '${_titleEn(g)}: your move first.' : '${_titleEn(g)}: your opponent starts.'),
        );
        return (id: next.id, seat: 1 - seat);
      });

  // ---- Frases fijas -----------------------------------------------------------

  /// Identificadores de las frases (la app las traduce): sin texto libre, no
  /// hace falta moderar.
  static const phrases = {
    'hello', 'good_luck', 'good_move', 'oops', 'thinking', 'thanks',
    'well_played', 'rematch', 'sorry', 'wow', 'your_turn', 'bye',
  };
  static const emoteGap = Duration(seconds: 5);

  Future<void> emote(String uid, String id, String phrase) async {
    if (!phrases.contains(phrase)) throw ApiError.badRequest('Frase desconocida.');
    await _retry(id, (v) async {
      final g = v.value;
      final seat = _seatOrThrow(g, uid);
      if (g.isWaiting) throw const ApiError(409, 'not_active', 'La partida aún no ha empezado.');
      final t = now();
      final mine = g.emotes.where((e) => e['seat'] == seat).map((e) => e['at']).whereType<DateTime>();
      if (mine.isNotEmpty && t.difference(mine.last) < emoteGap) {
        throw const ApiError(429, 'emote_too_fast', 'Espera un momento antes de otra frase.');
      }
      final list = [...g.emotes, {'seat': seat, 'phrase': phrase, 'at': t}];
      await store.updateGame(v, g.copyWith(emotes: list.length > 10 ? list.sublist(list.length - 10) : list, updatedAt: t));
    });
  }

  // ---- Abandono y tablas ----------------------------------------------------

  /// Activa: abandona (gana el rival). En espera: el creador la cancela.
  Future<void> resign(String uid, String id) => _retry(id, (v) async {
        final g = v.value;
        final seat = _seatOrThrow(g, uid);
        final t = now();
        if (g.isWaiting) {
          await store.updateGame(v, g.copyWith(status: 'cancelled', updatedAt: t), deleteInvite: g.code);
          return;
        }
        _requireActive(g);
        final next = g.copyWith(
          status: 'finished',
          winner: 1 - seat,
          reason: 'abandono',
          drawOfferBy: null,
          deadline: null,
          updatedAt: t,
        );
        await store.updateGame(v, next);
        await notifier.notify(g.players[1 - seat], _gameOver(next, 1 - seat));
      });

  /// Rechazar un reto de un amigo: solo el retado y antes de su primera
  /// jugada. La partida queda cancelada (sin ganador ni valoración).
  Future<void> declineChallenge(String uid, String id) => _retry(id, (v) async {
        final g = v.value;
        final seat = _seatOrThrow(g, uid);
        if (g.challenger == null || g.challenger == uid) {
          throw const ApiError(409, 'not_a_challenge', 'Esta partida no es un reto que puedas rechazar.');
        }
        _requireActive(g);
        if (g.ply > seat) throw const ApiError(409, 'already_moved', 'Ya has movido: abandona la partida si no quieres seguir.');
        final t = now();
        await store.updateGame(v, g.copyWith(status: 'cancelled', reason: 'reto rechazado', deadline: null, updatedAt: t));
        final me = g.names[seat];
        await notifier.notify(
          g.players[1 - seat],
          Notice(NoticeKind.gameOver, g.id, '${handle(me)} rechazó tu reto', _title(g),
              titleEn: '${handle(me)} declined your challenge', bodyEn: _titleEn(g)),
        );
      });

  Future<void> draw(String uid, String id, String action) => _retry(id, (v) async {
        final g = v.value;
        final seat = _seatOrThrow(g, uid);
        _requireActive(g);
        final opponent = 1 - seat;
        final t = now();
        switch (action) {
          case 'offer':
            if (g.drawOfferBy != null) {
              throw const ApiError(409, 'offer_pending', 'Ya hay una oferta de tablas pendiente.');
            }
            if (g.ply - g.lastDrawOfferPly[seat] < drawOfferGap) {
              throw const ApiError(429, 'draw_too_soon',
                  'Espera a jugar dos jugadas más antes de volver a ofrecer tablas.');
            }
            await store.updateGame(
              v,
              g.copyWith(
                drawOfferBy: seat,
                lastDrawOfferPly: [...g.lastDrawOfferPly]..[seat] = g.ply,
                updatedAt: t,
              ),
            );
            await notifier.notify(
              g.players[opponent],
              Notice(NoticeKind.drawOffered, g.id, '${handle(g.names[seat])} ofrece tablas', _title(g),
                  titleEn: '${handle(g.names[seat])} offers a draw', bodyEn: _titleEn(g)),
            );
          case 'accept':
            if (g.drawOfferBy != opponent) {
              throw const ApiError(409, 'no_offer', 'Tu rival no ha ofrecido tablas.');
            }
            final next = g.copyWith(
              status: 'finished',
              winner: null,
              reason: 'acuerdo mutuo',
              drawOfferBy: null,
              deadline: null,
              updatedAt: t,
            );
            await store.updateGame(v, next);
            await notifier.notify(g.players[opponent], _gameOver(next, opponent));
          case 'decline':
            if (g.drawOfferBy != opponent) {
              throw const ApiError(409, 'no_offer', 'Tu rival no ha ofrecido tablas.');
            }
            await store.updateGame(v, g.copyWith(drawOfferBy: null, updatedAt: t));
          default:
            throw ApiError.badRequest('Acción de tablas desconocida.');
        }
      });

  // ---- Cuenta ---------------------------------------------------------------------

  /// Antes de borrar la cuenta en Firebase Auth: abandona las partidas
  /// activas, cancela las que esperan, retira el nombre de todas y borra las
  /// preferencias y dispositivos. Idempotente: se puede repetir.
  Future<({int resigned, int cancelled})> deleteAccount(String uid) async {
    var resigned = 0, cancelled = 0;
    for (final v in await store.gamesOf(uid)) {
      final id = v.value.id;
      await _retry(id, (cur) async {
        final g = cur.value;
        final seat = g.seatOf(uid);
        if (seat < 0) return;
        final t = now();
        final names = [...g.names]..[seat] = deletedName;
        if (g.isWaiting) {
          await store.updateGame(cur, g.copyWith(status: 'cancelled', names: names, updatedAt: t),
              deleteInvite: g.code);
          cancelled++;
        } else if (g.isActive) {
          final next = g.copyWith(
            status: 'finished',
            winner: 1 - seat,
            reason: 'cuenta eliminada',
            names: names,
            drawOfferBy: null,
            deadline: null,
            updatedAt: t,
          );
          await store.updateGame(cur, next);
          resigned++;
          await notifier.notify(g.players[1 - seat], _gameOver(next, 1 - seat));
        } else if (g.names[seat] != deletedName) {
          await store.updateGame(cur, g.copyWith(names: names, updatedAt: t));
        }
      });
    }
    await store.deleteUserData(uid);
    return (resigned: resigned, cancelled: cancelled);
  }

  static const deletedName = 'Cuenta eliminada';

  // ---- Plazos (llamado por Cloud Scheduler) -----------------------------------

  /// Recordatorios, derrotas por tiempo y limpieza de partidas en espera.
  Future<({int reminded, int expired, int cancelled})> processDeadlines() async {
    final t = now();
    var reminded = 0, expired = 0, cancelled = 0;
    for (final v in await store.activeDueBefore(t.add(reminderBefore))) {
      final g = v.value;
      try {
        if (!g.deadline!.isAfter(t)) {
          final result = _replay(g).timeout(g.toMove);
          final next = g.copyWith(
            status: 'finished',
            winner: result.winner,
            reason: result.reason,
            drawOfferBy: null,
            deadline: null,
            updatedAt: t,
          );
          await store.updateGame(v, next);
          expired++;
          for (var seat = 0; seat < 2; seat++) {
            await notifier.notify(g.players[seat], _gameOver(next, seat));
          }
        } else if (!g.reminderSent) {
          await store.updateGame(v, g.copyWith(reminderSent: true, updatedAt: t));
          reminded++;
          final hours = g.deadline!.difference(t).inHours;
          await notifier.notify(
            g.players[g.toMove],
            Notice(NoticeKind.reminder, g.id, 'Te quedan $hours h para mover',
                '${_title(g)} contra ${handle(g.names[1 - g.toMove])}',
                titleEn: '$hours h left to move',
                bodyEn: '${_titleEn(g)} against ${handle(g.names[1 - g.toMove])}'),
          );
        }
      } on ConflictException {
        // Alguien movió a la vez: se revisa en la próxima pasada.
      }
    }
    for (final v in await store.waitingCreatedBefore(t.subtract(waitingTtl))) {
      try {
        await store.updateGame(v, v.value.copyWith(status: 'cancelled', updatedAt: t),
            deleteInvite: v.value.code);
        cancelled++;
      } on ConflictException {
        // Se unió alguien justo ahora.
      }
    }
    return (reminded: reminded, expired: expired, cancelled: cancelled);
  }

  // ---- Utilidades ---------------------------------------------------------------

  /// Lee, aplica [action] y reintenta si otro proceso escribió entre medias.
  Future<T> _retry<T>(String id, Future<T> Function(Versioned<GameRecord> v) action) async {
    // Ids de Firestore generados por el servidor: cualquier otra cosa no existe.
    if (!_validId.hasMatch(id)) throw ApiError.notFound;
    for (var i = 0; i < _attempts; i++) {
      final v = await store.getGame(id);
      if (v == null) throw ApiError.notFound;
      try {
        return await action(v);
      } on ConflictException {
        continue;
      }
    }
    throw const ApiError(409, 'busy', 'La partida está muy activa. Inténtalo de nuevo.');
  }

  int _seatOrThrow(GameRecord g, String uid) {
    final seat = g.seatOf(uid);
    if (seat < 0) throw ApiError.notMember;
    return seat;
  }

  void _requireActive(GameRecord g) {
    if (!g.isActive) {
      throw ApiError(409, 'not_active', g.isWaiting ? 'Tu rival aún no se ha unido.' : 'La partida ya terminó.');
    }
  }

  Replayer _replay(GameRecord g) {
    final r = Replayer.create(g.kind, g.variant);
    for (final m in g.moves) {
      if (!r.apply(m)) {
        throw ApiError(500, 'corrupt', 'La partida guardada no es válida (jugada ${g.moves.indexOf(m) + 1}).');
      }
    }
    return r;
  }

  String _newCode() =>
      List.generate(6, (_) => _alphabet[_random.nextInt(_alphabet.length)]).join();

  static String _titleEn(GameRecord g) => ServerText.gameTitle(g.kind, g.variant, en: true);

  static String _title(GameRecord g) => switch (g.kind) {
        'chess' => 'Ajedrez',
        'chineseCheckers' => 'Damas chinas',
        _ => switch (g.variant) {
            'international' => 'Damas internacionales',
            'english' => 'Damas inglesas',
            _ => 'Damas españolas',
          },
      };

  /// Aviso de final de partida desde el punto de vista de [seat].
  Notice _gameOver(GameRecord g, int seat) {
    final title = g.winner == null
        ? 'Tablas'
        : g.winner == seat
            ? 'Has ganado'
            : 'Has perdido';
    final titleEn = g.winner == null
        ? 'Draw'
        : g.winner == seat
            ? 'You won'
            : 'You lost';
    return Notice(NoticeKind.gameOver, g.id, '$title contra ${handle(g.names[1 - seat])}',
        '${_title(g)} · ${g.reason}',
        titleEn: '$titleEn against ${handle(g.names[1 - seat])}',
        bodyEn: '${_titleEn(g)} · ${ServerText.reason(g.reason)}');
  }

  /// `@nombre`, salvo cuentas eliminadas o asientos vacíos.
  static String handle(String username) =>
      username.isEmpty || username == deletedName ? username : '@$username';

  // ---- Nombres de usuario -----------------------------------------------------

  Future<({bool available, String username, String? reason})> checkUsername(String uid, String raw) async {
    final u = Usernames.normalize(raw);
    final problem = Usernames.problem(u);
    if (problem != null) return (available: false, username: u, reason: problem);
    final owner = await store.usernameOwner(u);
    if (owner != null && owner != uid) {
      return (available: false, username: u, reason: 'Ese nombre ya está en uso.');
    }
    return (available: true, username: u, reason: null);
  }

  /// Elige o cambia el nombre de usuario. Único (la reserva usa una
  /// precondición en Firestore), con un cambio cada [usernameCooldown].
  Future<String> setUsername(String uid, String raw) async {
    final u = Usernames.normalize(raw);
    final problem = Usernames.problem(u);
    if (problem != null) throw ApiError(422, 'invalid_username', problem);
    final profile = await store.userProfile(uid);
    if (profile.username == u) return u;
    final changed = profile.usernameChangedAt;
    if (profile.username != null && changed != null && now().difference(changed) < usernameCooldown) {
      final when = changed.add(usernameCooldown);
      throw ApiError(429, 'username_cooldown',
          'Podrás volver a cambiar tu nombre de usuario a partir del ${when.day}/${when.month}/${when.year}.',
          {'until': when.toIso8601String()});
    }
    const taken = ApiError(409, 'username_taken', 'Ese nombre ya está en uso.');
    final owner = await store.usernameOwner(u);
    if (owner != null && owner != uid) throw taken;
    try {
      await store.setUsername(uid, u, previous: profile.username, at: now());
    } on ConflictException {
      throw taken;
    }
    if (profile.username != null) await _renameInOpenGames(uid, u);
    return u;
  }

  /// Las partidas en curso o en espera muestran el nombre nuevo; las
  /// terminadas conservan el que tenía al jugarlas.
  Future<void> _renameInOpenGames(String uid, String username) async {
    for (final v in await store.gamesOf(uid)) {
      if (!v.value.isActive && !v.value.isWaiting) continue;
      try {
        await _retry(v.value.id, (cur) async {
          final g = cur.value;
          final seat = g.seatOf(uid);
          if (seat < 0 || (!g.isActive && !g.isWaiting)) return;
          await store.updateGame(cur, g.copyWith(names: [...g.names]..[seat] = username, updatedAt: now()));
        });
      } on ApiError {
        // Mejor esfuerzo: el nombre ya cambió en el perfil.
      }
    }
  }

  Future<String> _requireUsername(String uid) async {
    final u = (await store.userProfile(uid)).username;
    if (u == null) {
      throw const ApiError(403, 'username_required', 'Elige un nombre de usuario para jugar online.');
    }
    return u;
  }
}
