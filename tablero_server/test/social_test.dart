import 'dart:convert';
import 'dart:io';

import 'package:tablero_server/tablero_server.dart';
import 'package:test/test.dart';


Matcher apiError(String code) => throwsA(isA<ApiError>().having((e) => e.code, 'code', code));

void main() {
  late InMemoryStore store;
  late RecordingNotifier notifier;
  late GameService games;
  late SocialService social;
  late DateTime clock;
  final moves = [for (final m in jsonDecode(File('../tool/load/moves.json').readAsStringSync()) as List) m as String];

  setUp(() async {
    store = InMemoryStore();
    notifier = RecordingNotifier();
    clock = DateTime.utc(2026, 10, 18, 12);
    games = GameService(store: store, notifier: notifier, now: () => clock);
    social = SocialService(store: store, notifier: notifier, games: games, now: () => clock);
    for (final u in ['ana', 'joao', 'luis']) {
      await games.setUsername(u, u);
    }
  });

  Future<void> befriend(String a, String b) async {
    await social.request(a, b);
    await social.respond(b, a, accept: true);
  }

  group('Glicko-2', () {
    test('ejemplo del artículo de Glickman', () {
      final r = Glicko2.update(const Rating(rating: 1500, deviation: 200, volatility: 0.06), [
        (rating: 1400, deviation: 30, score: 1),
        (rating: 1550, deviation: 100, score: 0),
        (rating: 1700, deviation: 300, score: 0),
      ]);
      expect(r.rating, closeTo(1464.06, 0.01));
      expect(r.deviation, closeTo(151.52, 0.01));
      expect(r.volatility, closeTo(0.05999, 0.00001));
      expect(r.games, 3);
    });
  });

  group('amistades', () {
    test('solicitud, aviso y aceptación', () async {
      expect(await social.request('ana', '@Joao'), 'pending');
      expect(notifier.to('joao').last.kind, NoticeKind.friendRequest);
      await social.respond('joao', 'ana', accept: true);
      final f = (await store.friendshipsOf('ana')).single;
      expect(f.status, 'accepted');
      expect(f.names, {'ana': 'ana', 'joao': 'joao'});
      expect(notifier.to('ana').last.kind, NoticeKind.friendAccepted);
      await expectLater(social.request('ana', 'joao'), apiError('already_friends'));
    });

    test('si los dos se la piden, queda aceptada', () async {
      await social.request('ana', 'joao');
      expect(await social.request('joao', 'ana'), 'accepted');
    });

    test('errores: inexistente, a sí mismo, repetida, rechazada', () async {
      await expectLater(social.request('ana', 'nadie'), apiError('user_not_found'));
      await expectLater(social.request('ana', 'ana'), apiError('bad_request'));
      await social.request('ana', 'joao');
      await expectLater(social.request('ana', 'joao'), apiError('request_pending'));
      await social.respond('joao', 'ana', accept: false);
      expect(await store.friendshipsOf('ana'), isEmpty);
    });

    test('bloquear impide solicitudes y retos, en los dos sentidos', () async {
      await befriend('ana', 'joao');
      await social.block('joao', 'ana');
      await expectLater(social.request('ana', 'joao'), apiError('blocked'));
      await expectLater(social.challenge('ana', 'joao', kind: 'chess', seat: 0), apiError('not_friends'));
      await social.remove('ana', 'joao'); // quien está bloqueado no puede deshacerlo
      expect((await store.friendshipsOf('ana')).single.status, 'blocked');
      await social.unblock('joao', 'ana');
      expect(await store.friendshipsOf('ana'), isEmpty);
    });

    test('límite diario de solicitudes', () async {
      for (var i = 0; i < SocialService.maxRequestsPerDay; i++) {
        await games.setUsername('u$i', 'user_$i');
        await social.request('ana', 'user_$i');
      }
      await expectLater(social.request('ana', 'luis'), apiError('too_many_requests'));
      clock = clock.add(const Duration(days: 1, minutes: 1));
      expect(await social.request('ana', 'luis'), 'pending');
    });

    test('borrar la cuenta elimina sus amistades', () async {
      await befriend('ana', 'joao');
      await games.deleteAccount('ana');
      await store.deleteUserData('ana');
      expect(await store.friendshipsOf('joao'), isEmpty);
    });

    test('el nombre nuevo llega a las amistades', () async {
      await befriend('ana', 'joao');
      clock = clock.add(const Duration(days: 31));
      final name = await games.setUsername('ana', 'ana_nueva');
      await social.rename('ana', name);
      expect((await store.friendshipsOf('joao')).single.names['ana'], 'ana_nueva');
    });
  });

  group('retos y valoraciones', () {
    Future<String> playRated({required String white, required String black, required int plies, String? resigner}) async {
      final c = await social.challenge(white, black, kind: 'chess', seat: 0, rated: true);
      for (var i = 0; i < plies; i++) {
        await games.move(i.isEven ? white : black, c.id, ply: i, move: moves[i]);
      }
      await games.resign(resigner ?? black, c.id);
      await social.rateGame(c.id);
      return c.id;
    }

    test('el reto crea la partida activa y avisa', () async {
      await befriend('ana', 'joao');
      final c = await social.challenge('ana', 'joao', kind: 'draughts', variant: 'spanish', seat: 1);
      final g = (await store.getGame(c.id))!.value;
      expect((g.status, g.code, g.rated), ('active', '', false));
      expect(g.players, ['joao', 'ana']);
      expect(notifier.to('joao').last.kind, NoticeKind.challenge);
    });

    test('el retado puede rechazar el reto antes de mover; quien reta, no', () async {
      await befriend('ana', 'joao');
      final c = await social.challenge('ana', 'joao', kind: 'chess', seat: 1, rated: true); // joao juega blancas
      await expectLater(games.declineChallenge('ana', c.id), apiError('not_a_challenge'));
      await games.declineChallenge('joao', c.id);
      final g = (await store.getGame(c.id))!.value;
      expect((g.status, g.reason, g.winner), ('cancelled', 'reto rechazado', null));
      expect(notifier.to('ana').last.title, contains('rechazó tu reto'));
      expect(await social.sweepRatings(), 0); // cancelada: no hay valoración que aplicar
    });

    test('tras su primera jugada ya no se puede rechazar', () async {
      await befriend('ana', 'joao');
      final c = await social.challenge('ana', 'joao', kind: 'chess', seat: 0); // ana blancas, joao negras
      await games.declineChallenge('joao', c.id).then((_) {}); // aún no ha movido: se puede
      final c2 = await social.challenge('ana', 'joao', kind: 'chess', seat: 0);
      await games.move('ana', c2.id, ply: 0, move: moves[0]);
      await games.move('joao', c2.id, ply: 1, move: moves[1]);
      await expectLater(games.declineChallenge('joao', c2.id), apiError('already_moved'));
    });

    test('una partida con código no es un reto', () async {
      final g = await games.create('ana', kind: 'chess', variant: '', seat: 0);
      await games.join('joao', g.code);
      await expectLater(games.declineChallenge('joao', g.id), apiError('not_a_challenge'));
    });

    test('solo entre amigos', () async {
      await expectLater(social.challenge('ana', 'luis', kind: 'chess', seat: 0), apiError('not_friends'));
    });

    test('partida valorada: gana sube, pierde baja, una sola vez', () async {
      await befriend('ana', 'joao');
      final id = await playRated(white: 'ana', black: 'joao', plies: 20);
      final ana = (await store.getRatings('ana'))!.value.of('chess');
      final joao = (await store.getRatings('joao'))!.value.of('chess');
      expect(ana.rating, greaterThan(1500));
      expect(joao.rating, lessThan(1500));
      expect((ana.games, joao.games), (1, 1));
      await social.rateGame(id); // idempotente
      expect((await store.getRatings('ana'))!.value.of('chess').games, 1);
      expect((await store.getGame(id))!.value.ratingApplied, isTrue);
    });

    test('demasiado corta: se marca pero no cuenta', () async {
      await befriend('ana', 'joao');
      final id = await playRated(white: 'ana', black: 'joao', plies: 6);
      expect((await store.getGame(id))!.value.ratingApplied, isTrue);
      expect(await store.getRatings('ana'), isNull);
    });

    test('anti-abuso: la cuarta valorada del día contra el mismo rival no cuenta', () async {
      await befriend('ana', 'joao');
      for (var i = 0; i < 4; i++) {
        await playRated(white: 'ana', black: 'joao', plies: 20);
      }
      expect((await store.getRatings('ana'))!.value.of('chess').games, 3);
    });

    test('barrido: recoge las que quedaron sin aplicar', () async {
      await befriend('ana', 'joao');
      final c = await social.challenge('ana', 'joao', kind: 'chess', seat: 0, rated: true);
      for (var i = 0; i < 20; i++) {
        await games.move(i.isEven ? 'ana' : 'joao', c.id, ply: i, move: moves[i]);
      }
      await games.resign('joao', c.id); // sin rateGame: como si el servidor hubiera caído
      expect(await social.sweepRatings(), 1);
      expect((await store.getRatings('ana'))!.value.of('chess').games, 1);
      expect(await social.sweepRatings(), 0);
    });

    test('clasificación: solo valoraciones no provisionales, con nombre', () async {
      store.ratingsDocs['ana'] = const Versioned(RatingsDoc(ratings: {'chess': Rating(rating: 1700, deviation: 80, games: 30)}), '1');
      store.ratingsDocs['joao'] = const Versioned(RatingsDoc(ratings: {'chess': Rating(rating: 1800, deviation: 300, games: 2)}), '2');
      store.ratingsDocs['luis'] = const Versioned(RatingsDoc(ratings: {'chess': Rating(rating: 1600, deviation: 90, games: 12)}), '3');
      await social.updateLeaderboards();
      expect(store.leaderboards['chess']!.map((e) => (e.username, e.rating)), [('ana', 1700), ('luis', 1600)]);
    });
  });

  group('frases fijas', () {
    test('se guardan con el asiento; ritmo y frases conocidas', () async {
      await befriend('ana', 'joao');
      final c = await social.challenge('ana', 'joao', kind: 'chess', seat: 0);
      await games.emote('ana', c.id, 'hello');
      await expectLater(games.emote('ana', c.id, 'good_luck'), apiError('emote_too_fast'));
      clock = clock.add(const Duration(seconds: 6));
      await games.emote('ana', c.id, 'good_luck');
      await games.emote('joao', c.id, 'thanks');
      await expectLater(games.emote('ana', c.id, 'insulto'), apiError('bad_request'));
      await expectLater(games.emote('luis', c.id, 'hello'), apiError('not_member'));
      final e = (await store.getGame(c.id))!.value.emotes;
      expect(e.map((x) => (x['seat'], x['phrase'])), [(0, 'hello'), (0, 'good_luck'), (1, 'thanks')]);
    });

    test('se conservan las 10 últimas', () async {
      await befriend('ana', 'joao');
      final c = await social.challenge('ana', 'joao', kind: 'chess', seat: 0);
      for (var i = 0; i < 12; i++) {
        clock = clock.add(const Duration(seconds: 6));
        await games.emote('ana', c.id, 'wow');
      }
      expect((await store.getGame(c.id))!.value.emotes, hasLength(10));
    });
  });
}
