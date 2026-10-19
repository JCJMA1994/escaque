import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:tablero_server/tablero_server.dart';
import 'package:test/test.dart';

class FakePlay implements PlayStore {
  final purchases = <String, PlayPurchase>{};
  final acknowledged = <String>[];

  @override
  Future<PlayPurchase?> get(String productId, String token) async => purchases[token];

  @override
  Future<void> acknowledge(String productId, String token) async => acknowledged.add(token);
}

Matcher apiError(String code) => throwsA(isA<ApiError>().having((e) => e.code, 'code', code));

void main() {
  late InMemoryStore store;
  late FakePlay play;
  late PurchaseService service;

  setUp(() {
    store = InMemoryStore();
    play = FakePlay();
    service = PurchaseService(store: store, play: play);
  });

  test('compra válida: se reconoce y activa «sin anuncios»', () async {
    play.purchases['t1'] = PlayPurchase(state: 0, acknowledged: 0, orderId: 'GPA.1', accountId: PurchaseService.accountHash('ana'));
    await service.verify('ana', 'remove_ads', 't1');
    expect(play.acknowledged, ['t1']);
    expect((await store.userProfile('ana')).adFree, isTrue);
    // Repetir (restaurar compras) no vuelve a reconocerla
    play.purchases['t1'] = PlayPurchase(state: 0, acknowledged: 1, accountId: PurchaseService.accountHash('ana'));
    await service.verify('ana', 'remove_ads', 't1');
    expect(play.acknowledged, ['t1']);
  });

  test('pendiente, cancelada, inexistente o de otro producto: no', () async {
    play.purchases['p'] = const PlayPurchase(state: 2);
    play.purchases['c'] = const PlayPurchase(state: 1);
    await expectLater(service.verify('ana', 'remove_ads', 'p'), apiError('purchase_pending'));
    await expectLater(service.verify('ana', 'remove_ads', 'c'), apiError('purchase_cancelled'));
    await expectLater(service.verify('ana', 'remove_ads', 'nada'), apiError('invalid_purchase'));
    await expectLater(service.verify('ana', 'otro', 'p'), apiError('wrong_product'));
    expect((await store.userProfile('ana')).adFree, isFalse);
  });

  test('una compra no sirve para otra cuenta', () async {
    play.purchases['t'] = PlayPurchase(state: 0, acknowledged: 1, accountId: PurchaseService.accountHash('ana'));
    await expectLater(service.verify('joao', 'remove_ads', 't'), apiError('purchase_other_account'));
    // Sin identificador ofuscado (comprada sin cuenta): la primera cuenta que la reclama se la queda
    play.purchases['libre'] = const PlayPurchase(state: 0, acknowledged: 1);
    await service.verify('ana', 'remove_ads', 'libre');
    await expectLater(service.verify('joao', 'remove_ads', 'libre'), apiError('purchase_other_account'));
  });

  Map<String, Object?> pubsub(Map<String, Object?> n) => {
        'message': {'data': base64.encode(utf8.encode(jsonEncode(n)))},
      };

  test('un reembolso retira «sin anuncios»', () async {
    play.purchases['t'] = PlayPurchase(state: 0, acknowledged: 1, accountId: PurchaseService.accountHash('ana'));
    await service.verify('ana', 'remove_ads', 't');
    await service.handleNotification(pubsub({
      'voidedPurchaseNotification': {'purchaseToken': 't', 'productType': 2, 'refundType': 1},
    }));
    expect((await store.userProfile('ana')).adFree, isFalse);
  });

  test('notificaciones de prueba o de tokens desconocidos no fallan', () async {
    await service.handleNotification(pubsub({'testNotification': {'version': '1.0'}}));
    await service.handleNotification(pubsub({
      'oneTimeProductNotification': {'notificationType': 2, 'purchaseToken': 'desconocido'},
    }));
    await expectLater(service.handleNotification({'message': 'x'}), apiError('bad_request'));
  });

  test('API: verificar y notificación de Play', () async {
    play.purchases['t'] = PlayPurchase(state: 0, acknowledged: 0, accountId: PurchaseService.accountHash('ana'));
    final h = buildHandler(GameService(store: store, notifier: NoopNotifier()), FakeAuthenticator(), purchases: service);
    final r = await h(Request('POST', Uri.parse('http://localhost/v1/purchases/verify'),
        body: jsonEncode({'productId': 'remove_ads', 'token': 't'}), headers: {'x-test-user': 'ana'}));
    expect(r.statusCode, 200);
    expect(jsonDecode(await r.readAsString()), {'adFree': true});
    final unauth = await h(Request('POST', Uri.parse('http://localhost/v1/tasks/play-rtdn'), body: '{}'));
    expect(unauth.statusCode, 401);
    final rtdn = await h(Request('POST', Uri.parse('http://localhost/v1/tasks/play-rtdn'),
        body: jsonEncode(pubsub({'voidedPurchaseNotification': {'purchaseToken': 't'}})),
        headers: {'x-test-scheduler': 'yes'}));
    expect(rtdn.statusCode, 200);
    expect((await store.userProfile('ana')).adFree, isFalse);
  });

  test('token con ámbitos del servidor de metadatos, en caché', () async {
    var calls = 0;
    final inner = MockClient((req) async {
      if (req.url.host == 'metadata.google.internal') {
        calls++;
        expect(req.headers['metadata-flavor'], 'Google');
        expect(req.url.queryParameters['scopes'], 'https://www.googleapis.com/auth/androidpublisher');
        return http.Response(jsonEncode({'access_token': 'tok', 'expires_in': 3600}), 200);
      }
      expect(req.headers['authorization'], 'Bearer tok');
      return http.Response('{}', 200);
    });
    final c = ScopedMetadataClient(['https://www.googleapis.com/auth/androidpublisher'], inner: inner);
    await c.get(Uri.parse('https://androidpublisher.googleapis.com/x'));
    await c.get(Uri.parse('https://androidpublisher.googleapis.com/y'));
    expect(calls, 1);
  });

  test('identificador de cuenta ofuscado (el mismo que calcula la app)', () {
    expect(PurchaseService.accountHash('ana'), 'b4d31b99ce2a24f26f45134ed73eb4051125746c');
  });
}
