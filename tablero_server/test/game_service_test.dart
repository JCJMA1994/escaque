import 'package:tablero_engine/tablero_engine.dart';
import 'package:tablero_server/tablero_server.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryStore store;
  late RecordingNotifier notifier;
  late DateTime clock;
  late GameService service;

  setUp(() async {
    store = InMemoryStore();
    notifier = RecordingNotifier();
    clock = DateTime.utc(2026, 10, 18, 12);
    service = GameService(store: store, notifier: notifier, now: () => clock);
    for (final u in ['ana', 'joao', 'luis']) {
      await service.setUsername(u, u);
    }
  });

  Future<String> activeChess() async {
    final g = await service.create('ana', kind: 'chess', variant: '', seat: 0);
    await service.join('joao', g.code);
    return g.id;
  }

  Future<GameRecord> game(String id) async => (await store.getGame(id))!.value;

  Matcher apiError(String code) =>
      throwsA(isA<ApiError>().having((e) => e.code, 'code', code));

  group('crear y unirse', () {
    test('crea una partida en espera con código e invitación', () async {
      final g = await service.create('ana', kind: 'chess', variant: '', seat: 0);
      final r = await game(g.id);
      expect(r.status, 'waiting');
      expect(r.names, ['ana', '']);
      expect(g.code, matches(RegExp(r'^[A-Z2-9]{6}$')));
      expect(store.invites[g.code], g.id);
    });

    test('en damas inglesas empiezan las negras', () async {
      final g = await service.create('ana', kind: 'draughts', variant: 'english', seat: 0);
      expect((await game(g.id)).toMove, 1);
    });

    test('rechaza juegos y variantes desconocidos', () async {
      await expectLater(service.create('ana', kind: 'go', variant: '', seat: 0),
          apiError('bad_request'));
      await expectLater(service.create('ana', kind: 'draughts', variant: 'turca', seat: 0),
          apiError('bad_request'));
    });

    test('límite de partidas en espera por usuario', () async {
      for (var i = 0; i < 10; i++) {
        await service.create('ana', kind: 'chess', variant: '', seat: 0);
      }
      await expectLater(service.create('ana', kind: 'chess', variant: '', seat: 0),
          apiError('too_many_waiting'));
    });

    test('unirse activa la partida, borra la invitación y avisa al creador', () async {
      final g = await service.create('ana', kind: 'chess', variant: '', seat: 0);
      final j = await service.join('joao', g.code.toLowerCase());
      expect(j.seat, 1);
      final r = await game(g.id);
      expect(r.status, 'active');
      expect(r.deadline, clock.add(const Duration(hours: 72)));
      expect(store.invites, isEmpty);
      expect(notifier.to('ana').single.kind, NoticeKind.opponentJoined);
    });

    test('no puedes unirte a tu propia partida ni a una empezada', () async {
      final g = await service.create('ana', kind: 'chess', variant: '', seat: 0);
      await expectLater(service.join('ana', g.code), apiError('own_game'));
      await service.join('joao', g.code);
      await expectLater(service.join('luis', g.code), apiError('code_not_found'));
    });
  });

  group('jugadas', () {
    test('jugada legal: avanza, avisa al rival y renueva el plazo', () async {
      final id = await activeChess();
      clock = clock.add(const Duration(hours: 5));
      final m = await service.move('ana', id, ply: 0, move: 'e2e4');
      expect(m.ply, 1);
      final r = await game(id);
      expect(r.toMove, 1);
      expect(r.deadline, clock.add(const Duration(hours: 72)));
      expect(notifier.to('joao').last.kind, NoticeKind.yourTurn);
    });

    test('rechaza jugadas ilegales, fuera de turno y desfasadas', () async {
      final id = await activeChess();
      await expectLater(service.move('ana', id, ply: 0, move: 'e2e5'), apiError('illegal_move'));
      await expectLater(service.move('joao', id, ply: 0, move: 'e7e5'), apiError('not_your_turn'));
      await service.move('ana', id, ply: 0, move: 'e2e4');
      await expectLater(service.move('joao', id, ply: 0, move: 'e7e5'), apiError('stale'));
      await expectLater(service.move('luis', id, ply: 1, move: 'e7e5'), apiError('not_member'));
    });

    test('el servidor calcula el mate; el cliente no puede declararlo', () async {
      final id = await activeChess();
      var ply = 0;
      for (final (uid, m) in [('ana', 'f2f3'), ('joao', 'e7e5'), ('ana', 'g2g4'), ('joao', 'd8h4')]) {
        await service.move(uid, id, ply: ply++, move: m);
      }
      final r = await game(id);
      expect(r.status, 'finished');
      expect(r.winner, 1);
      expect(r.reason, 'jaque mate');
      expect(r.deadline, isNull);
      expect(notifier.to('ana').last.title, startsWith('Has perdido'));
      await expectLater(service.move('ana', id, ply: 4, move: 'e2e3'), apiError('not_active'));
    });

    test('damas: valida el recorrido completo', () async {
      final g = await service.create('ana', kind: 'draughts', variant: 'spanish', seat: 0);
      await service.join('joao', g.code);
      final rules = DraughtsRules(DraughtsVariant.spanish);
      final first = rules.legalMoves(rules.initialState()).first.path.join('-');
      expect((await service.move('ana', g.id, ply: 0, move: first)).ply, 1);
      await expectLater(service.move('joao', g.id, ply: 1, move: '0-99'), apiError('illegal_move'));
    });
  });

  group('abandono y tablas', () {
    test('abandonar da la victoria al rival', () async {
      final id = await activeChess();
      await service.resign('joao', id);
      final r = await game(id);
      expect((r.winner, r.reason), (0, 'abandono'));
    });

    test('cancelar una partida en espera borra la invitación', () async {
      final g = await service.create('ana', kind: 'chess', variant: '', seat: 0);
      await service.resign('ana', g.id);
      expect((await game(g.id)).status, 'cancelled');
      expect(store.invites, isEmpty);
    });

    test('ofrecer, rechazar, esperar y aceptar', () async {
      final id = await activeChess();
      await service.draw('ana', id, 'offer');
      expect(notifier.to('joao').last.kind, NoticeKind.drawOffered);
      await expectLater(service.draw('ana', id, 'accept'), apiError('no_offer'));
      await service.draw('joao', id, 'decline');
      await expectLater(service.draw('ana', id, 'offer'), apiError('draw_too_soon'));
      var ply = 0;
      for (final (uid, m) in [('ana', 'g1f3'), ('joao', 'g8f6'), ('ana', 'f3g1'), ('joao', 'f6g8')]) {
        await service.move(uid, id, ply: ply++, move: m);
      }
      await service.draw('ana', id, 'offer');
      await service.draw('joao', id, 'accept');
      final r = await game(id);
      expect((r.status, r.winner, r.reason), ('finished', null, 'acuerdo mutuo'));
    });

    test('mover retira la oferta de tablas pendiente', () async {
      final id = await activeChess();
      await service.draw('joao', id, 'offer');
      await service.move('ana', id, ply: 0, move: 'e2e4');
      expect((await game(id)).drawOfferBy, isNull);
    });
  });

  group('plazos', () {
    test('recordatorio una sola vez 24 h antes y derrota al vencer', () async {
      final id = await activeChess();
      clock = clock.add(const Duration(hours: 49));
      expect((await service.processDeadlines()).reminded, 1);
      expect(notifier.to('ana').last.kind, NoticeKind.reminder);
      expect((await service.processDeadlines()).reminded, 0);
      clock = clock.add(const Duration(hours: 24));
      expect((await service.processDeadlines()).expired, 1);
      final r = await game(id);
      expect((r.status, r.winner, r.reason), ('finished', 1, 'tiempo agotado'));
    });

    test('las partidas en espera caducan a los 7 días', () async {
      final g = await service.create('ana', kind: 'chess', variant: '', seat: 0);
      clock = clock.add(const Duration(days: 8));
      expect((await service.processDeadlines()).cancelled, 1);
      expect((await game(g.id)).status, 'cancelled');
      expect(store.invites, isEmpty);
    });
  });

  test('concurrencia: dos jugadas simultáneas, solo una entra', () async {
    final id = await activeChess();
    final results = await Future.wait([
      service.move('ana', id, ply: 0, move: 'e2e4').then((_) => 'ok', onError: (Object e) => (e as ApiError).code),
      service.move('ana', id, ply: 0, move: 'd2d4').then((_) => 'ok', onError: (Object e) => (e as ApiError).code),
    ]);
    expect(results.where((r) => r == 'ok'), hasLength(1));
    expect((await game(id)).ply, 1);
  });

  group('borrar cuenta', () {
    test('abandona activas, cancela en espera, retira el nombre y borra datos', () async {
      final active = await activeChess();
      final waiting = await service.create('ana', kind: 'chess', variant: '', seat: 1);
      final finished = await service.create('ana', kind: 'chess', variant: '', seat: 0);
      await service.join('luis', finished.code);
      await service.resign('luis', finished.id);
      store.devices['ana'] = {'t1'};

      final d = await service.deleteAccount('ana');
      expect((d.resigned, d.cancelled), (1, 1));

      final a = await game(active);
      expect((a.status, a.winner, a.reason), ('finished', 1, 'cuenta eliminada'));
      expect(a.names[0], GameService.deletedName);
      expect(notifier.to('joao').last.kind, NoticeKind.gameOver);
      expect((await game(waiting.id)).status, 'cancelled');
      expect((await game(finished.id)).names[0], GameService.deletedName);
      expect(store.invites.containsKey(waiting.code), isFalse);
      expect(await store.deviceTokens('ana'), isEmpty);

      // Repetirlo no falla ni cambia nada.
      expect((await service.deleteAccount('ana')).resigned, 0);
    });
  });

  group('nombres de usuario', () {
    test('validación', () {
      expect(Usernames.problem('ab'), isNotNull);
      expect(Usernames.problem('1ana'), isNotNull);
      expect(Usernames.problem('ana maría'), isNotNull);
      expect(Usernames.problem('ana__88'), isNotNull);
      expect(Usernames.problem('admin'), isNotNull);
      expect(Usernames.problem('ana_88'), isNull);
      expect(Usernames.normalize('  @Ana_88 '), 'ana_88');
    });

    test('únicos sin distinguir mayúsculas', () async {
      expect((await service.checkUsername('nuevo', 'ANA')).available, isFalse);
      await expectLater(service.setUsername('nuevo', '@Ana'), apiError('username_taken'));
      expect((await service.checkUsername('ana', 'ana')).available, isTrue); // el propio
      expect(await service.setUsername('nuevo', 'Nuevo_1'), 'nuevo_1');
    });

    test('sin nombre de usuario no se juega online', () async {
      await expectLater(service.create('sin_nombre', kind: 'chess', variant: '', seat: 0), apiError('username_required'));
    });

    test('cambiarlo libera el anterior, respeta el plazo y renombra partidas abiertas', () async {
      final id = await activeChess();
      clock = clock.add(const Duration(days: 31));
      expect(await service.setUsername('ana', 'ana_nueva'), 'ana_nueva');
      expect(await store.usernameOwner('ana'), isNull);
      expect((await game(id)).names[0], 'ana_nueva');
      await expectLater(service.setUsername('ana', 'ana_otra'), apiError('username_cooldown'));
      await service.move('ana', id, ply: 0, move: 'e2e4');
      expect(notifier.to('joao').last.title, 'Te toca contra @ana_nueva');
    });

    test('borrar la cuenta libera el nombre', () async {
      await service.deleteAccount('luis');
      expect(await store.usernameOwner('luis'), isNull);
      expect((await service.checkUsername('otro', 'luis')).available, isTrue);
    });
  });

  group('revancha', () {
    test('cambia colores, empieza activa y avisa al rival', () async {
      final id = await activeChess();
      await service.resign('joao', id);
      final r = await service.rematch('ana', id);
      expect(r.seat, 1); // ana jugaba con blancas: ahora negras
      final g = await game(r.id);
      expect(g.status, 'active');
      expect(g.players, ['joao', 'ana']);
      expect(g.names, ['joao', 'ana']);
      expect(notifier.to('joao').last.kind, NoticeKind.rematch);
      // El rival la pide también: recibe la misma partida, no otra.
      final again = await service.rematch('joao', id);
      expect((again.id, again.seat), (r.id, 0));
    });

    test('no antes de terminar ni contra una cuenta eliminada', () async {
      final id = await activeChess();
      await expectLater(service.rematch('ana', id), apiError('not_finished'));
      await service.deleteAccount('joao');
      await expectLater(service.rematch('ana', id), apiError('opponent_gone'));
    });
  });

  group('damas chinas online', () {
    test('partida a dos con saltos validados por el servidor', () async {
      final g = await service.create('ana', kind: 'chineseCheckers', variant: '', seat: 0);
      await service.join('joao', g.code);
      final rules = ChineseCheckersRules(players: 2);
      final s0 = rules.initialState();
      final m = rules.legalMoves(s0).firstWhere((m) => !m.isPass);
      expect((await service.move('ana', g.id, ply: 0, move: '${m.from}-${m.to}')).ply, 1);
      await expectLater(service.move('joao', g.id, ply: 1, move: '${m.from}-${m.to}'), apiError('illegal_move'));
      await expectLater(service.move('joao', g.id, ply: 1, move: 'x'), apiError('illegal_move'));
      expect((await game(g.id)).variant, '');
    });
  });

  test('límite de peticiones: cubo de fichas', () {
    var t = DateTime.utc(2026);
    final limiter = RateLimiter(capacity: 3, refill: const Duration(seconds: 1), now: () => t);
    expect([for (var i = 0; i < 4; i++) limiter.allow('ana')], [true, true, true, false]);
    expect(limiter.allow('joao'), isTrue); // por usuario
    t = t.add(const Duration(seconds: 2));
    expect(limiter.allow('ana'), isTrue);
  });

  test('avisos en el idioma de cada persona', () async {
    final id = await activeChess();
    await service.move('ana', id, ply: 0, move: 'e2e4');
    final n = notifier.to('joao').last;
    expect(n.titleFor('es'), 'Te toca contra @ana');
    expect(n.titleFor('en'), 'Your move against @ana');
    expect(n.bodyFor('en'), 'Chess · move 1');
    expect(n.titleFor(null), 'Te toca contra @ana');
    expect(ServerText.reason('jaque mate'), 'checkmate');
  });
}
