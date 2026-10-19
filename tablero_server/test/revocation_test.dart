import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:tablero_server/tablero_server.dart';
import 'package:test/test.dart';

Matcher apiError(String code) => throwsA(isA<ApiError>().having((e) => e.code, 'code', code));

void main() {
  final now = DateTime.utc(2026, 10, 18, 12);
  void check(AccountState? a, {required DateTime iat, DateTime? authTime, required Sensitivity s}) =>
      Revocation.check(account: a, issuedAt: iat, authTime: authTime ?? iat, sensitivity: s, now: now);

  group('reglas', () {
    test('normal no consulta nada', () {
      check(null, iat: now, s: Sensitivity.normal);
    });

    test('token emitido antes de validSince: revocado', () {
      final a = AccountState(validSince: now);
      expect(() => check(a, iat: now.subtract(const Duration(seconds: 1)), s: Sensitivity.checkRevoked),
          apiError('token_revoked'));
      check(a, iat: now, s: Sensitivity.checkRevoked); // mismo segundo: válido
    });

    test('cuenta desactivada o inexistente: revocado', () {
      expect(() => check(const AccountState(disabled: true), iat: now, s: Sensitivity.checkRevoked),
          apiError('token_revoked'));
      expect(() => check(null, iat: now, s: Sensitivity.checkRevoked), apiError('token_revoked'));
    });

    test('inicio de sesión reciente: 5 minutos', () {
      const a = AccountState();
      check(a, iat: now, authTime: now.subtract(const Duration(minutes: 4)), s: Sensitivity.recentLogin);
      expect(() => check(a, iat: now, authTime: now.subtract(const Duration(minutes: 6)), s: Sensitivity.recentLogin),
          apiError('recent_login_required'));
      // Para cambiar el nombre basta con que no esté revocado.
      check(a, iat: now, authTime: now.subtract(const Duration(days: 30)), s: Sensitivity.checkRevoked);
    });
  });

  group('Identity Toolkit', () {
    test('lee validSince y disabled, y guarda en caché 5 minutos', () async {
      var calls = 0;
      var t = now;
      final client = MockClient((req) async {
        calls++;
        expect(req.url.path, '/v1/projects/escaque-qa/accounts:lookup');
        expect(jsonDecode(req.body), {
          'localId': ['ana'],
        });
        return http.Response(jsonEncode({
          'users': [
            {'localId': 'ana', 'validSince': '1792324800', 'disabled': true},
          ],
        }), 200);
      });
      final lookup = IdentityToolkitLookup(client, 'escaque-qa', now: () => t);
      final a = await lookup.lookup('ana');
      expect(a!.disabled, isTrue);
      expect(a.validSince, DateTime.fromMillisecondsSinceEpoch(1792324800 * 1000, isUtc: true));
      await lookup.lookup('ana');
      expect(calls, 1);
      t = t.add(const Duration(minutes: 6));
      await lookup.lookup('ana');
      expect(calls, 2);
    });

    test('cuenta inexistente: null; error del servicio: 503', () async {
      final empty = IdentityToolkitLookup(MockClient((_) async => http.Response('{}', 200)), 'p');
      expect(await empty.lookup('x'), isNull);
      final down = IdentityToolkitLookup(MockClient((_) async => http.Response('', 500)), 'p');
      expect(down.lookup('x'), apiError('auth_unavailable'));
    });
  });

  group('API', () {
    late Handler handler;
    setUp(() async {
      final service = GameService(store: InMemoryStore(), notifier: NoopNotifier());
      await service.setUsername('ana', 'ana');
      handler = buildHandler(service, FakeAuthenticator());
    });

    Future<(int, Map<String, dynamic>)> post(String path, Map<String, String> headers, [Object? body]) async {
      final r = await handler(Request('POST', Uri.parse('http://localhost$path'),
          body: jsonEncode(body ?? {}), headers: {'x-test-user': 'ana', ...headers}));
      return (r.statusCode, jsonDecode(await r.readAsString()) as Map<String, dynamic>);
    }

    test('borrar la cuenta exige inicio de sesión reciente', () async {
      final (s1, b1) = await post('/v1/me/delete', {'x-test-login-age': '900'});
      expect((s1, b1['error']), (401, 'recent_login_required'));
      final (s2, _) = await post('/v1/me/delete', {'x-test-login-age': '30'});
      expect(s2, 200);
    });

    test('cambiar el nombre con un token revocado: 401', () async {
      final (s, b) = await post('/v1/me/username', {'x-test-revoked': 'yes'}, {'username': 'ana_2'});
      expect((s, b['error']), (401, 'token_revoked'));
    });
  });

  group('modo de pruebas de carga', () {
    test('no arranca en producción ni con un secreto corto', () {
      expect(() => LoadTestAuthenticator(FakeAuthenticator(), 'x' * 30, environment: 'prod'), throwsStateError);
      expect(() => LoadTestAuthenticator(FakeAuthenticator(), 'x' * 30, environment: ''), throwsStateError);
      expect(() => LoadTestAuthenticator(FakeAuthenticator(), 'corto', environment: 'qa'), throwsStateError);
    });

    test('con el secreto acepta usuarios load_*; sin él usa el autenticador real', () async {
      final auth = LoadTestAuthenticator(FakeAuthenticator(), 's' * 30, environment: 'qa');
      Request req(Map<String, String> h) => Request('POST', Uri.parse('http://localhost/'), headers: h);
      expect(await auth.userId(req({'x-load-test': 's' * 30, 'x-test-user': 'load_7'})), 'load_7');
      expect(auth.userId(req({'x-load-test': 's' * 30, 'x-test-user': 'ana'})), throwsA(isA<ApiError>()));
      // Sin secreto: el real (aquí, el falso de tests) decide.
      expect(await auth.userId(req({'x-test-user': 'ana'})), 'ana');
    });
  });
}
