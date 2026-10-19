import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:tablero_server/tablero_server.dart';
import 'package:test/test.dart';

void main() {
  late Handler handler;

  setUp(() async {
    final service = GameService(store: InMemoryStore(), notifier: NoopNotifier());
    await service.setUsername('ana', 'ana');
    await service.setUsername('joao', 'joao');
    handler = buildHandler(service, FakeAuthenticator());
  });

  Future<(int, Map<String, Object?>)> post(String path, Map<String, Object?> body, {String? user}) async {
    final res = await handler(Request('POST', Uri.parse('http://localhost$path'),
        body: jsonEncode(body), headers: {'x-test-user': ?user}));
    return (res.statusCode, jsonDecode(await res.readAsString()) as Map<String, Object?>);
  }

  test('sin sesión: 401', () async {
    final (status, body) = await post('/v1/games', {'kind': 'chess', 'seat': 0});
    expect(status, 401);
    expect(body['error'], 'unauthorized');
  });

  test('flujo completo por HTTP', () async {
    final (s1, created) = await post('/v1/games', {'kind': 'chess', 'seat': 0}, user: 'ana');
    expect(s1, 200);
    final (s2, joined) = await post('/v1/games/join', {'code': created['code']}, user: 'joao');
    expect((s2, joined['seat'], joined['kind']), (200, 1, 'chess'));
    final id = created['id'];
    final (s3, moved) = await post('/v1/games/$id/moves', {'ply': 0, 'move': 'e2e4'}, user: 'ana');
    expect((s3, moved['ply']), (200, 1));
    final (s4, illegal) = await post('/v1/games/$id/moves', {'ply': 1, 'move': 'e7e4'}, user: 'joao');
    expect((s4, illegal['error']), (422, 'illegal_move'));
    final (s5, stale) = await post('/v1/games/$id/moves', {'ply': 0, 'move': 'e7e5'}, user: 'joao');
    expect((s5, stale['error'], stale['ply']), (409, 'stale', 1));
  });

  test('JSON mal formado: 400', () async {
    final res = await handler(Request('POST', Uri.parse('http://localhost/v1/games'),
        body: '{nope', headers: {'x-test-user': 'ana'}));
    expect(res.statusCode, 400);
  });

  test('tareas: solo Scheduler', () async {
    final denied = await handler(Request('POST', Uri.parse('http://localhost/v1/tasks/deadlines')));
    expect(denied.statusCode, 401);
    final ok = await handler(Request('POST', Uri.parse('http://localhost/v1/tasks/deadlines'),
        headers: {'x-test-scheduler': 'yes'}));
    expect(ok.statusCode, 200);
  });

  test('cuentas: anónima y correo sin verificar rechazados', () {
    expect(() => GoogleAuthenticator.checkAccount({'sign_in_provider': 'anonymous'}, false),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'account_required')));
    expect(() => GoogleAuthenticator.checkAccount(null, true),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'account_required')));
    expect(() => GoogleAuthenticator.checkAccount({'sign_in_provider': 'password'}, false),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'email_not_verified')));
    GoogleAuthenticator.checkAccount({'sign_in_provider': 'password'}, true);
    GoogleAuthenticator.checkAccount({'sign_in_provider': 'google.com'}, null);
  });

  test('nombre de usuario por HTTP', () async {
    final (s1, check) = await post('/v1/usernames/check', {'username': 'Ana'}, user: 'luis');
    expect((s1, check['available'], check['reason']), (200, false, 'Ese nombre ya está en uso.'));
    final (s2, set) = await post('/v1/me/username', {'username': '@Luis_7'}, user: 'luis');
    expect((s2, set['username']), (200, 'luis_7'));
    final (s3, bad) = await post('/v1/me/username', {'username': 'x'}, user: 'otro');
    expect((s3, bad['error']), (422, 'invalid_username'));
  });

  test('verificación opcional solo en rutas de cuenta', () {
    GoogleAuthenticator.checkAccount({'sign_in_provider': 'password'}, false, requireVerified: false);
  });

  test('id de partida con caracteres raros: 404, no 500', () async {
    final (status, body) = await post('/v1/games/..%2Fusers/moves', {'ply': 0, 'move': 'e2e4'}, user: 'ana');
    expect(status, anyOf(404, 400));
    expect(body['error'], isNot('internal'));
  });

  test('demasiadas peticiones: 429', () async {
    final service = GameService(store: InMemoryStore(), notifier: NoopNotifier());
    final h = buildHandler(service, FakeAuthenticator(), limiter: RateLimiter(capacity: 2));
    Future<int> hit() async => (await h(Request('POST', Uri.parse('http://localhost/v1/usernames/check'),
            body: jsonEncode({'username': 'ana'}), headers: {'x-test-user': 'x'})))
        .statusCode;
    expect([await hit(), await hit(), await hit()], [200, 200, 429]);
  });
}
