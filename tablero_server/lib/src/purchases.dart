import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:googleapis/androidpublisher/v3.dart' as ap;

import 'errors.dart';
import 'log.dart';
import 'store.dart';

/// Estado de una compra según Google Play.
class PlayPurchase {
  /// 0 comprada, 1 cancelada, 2 pendiente.
  final int? state;

  /// 0 sin reconocer, 1 reconocida.
  final int? acknowledged;
  final String? orderId;

  /// Identificador de cuenta ofuscado que la app envió al comprar.
  final String? accountId;
  const PlayPurchase({this.state, this.acknowledged, this.orderId, this.accountId});
}

abstract interface class PlayStore {
  /// `null` si el token no existe para ese producto.
  Future<PlayPurchase?> get(String productId, String token);
  Future<void> acknowledge(String productId, String token);
}

/// Google Play Developer API con la cuenta de servicio del servidor (en Play
/// Console: permiso «Ver información financiera» y «Gestionar pedidos»).
class GooglePlayStore implements PlayStore {
  final ap.AndroidPublisherApi api;
  final String packageName;
  GooglePlayStore(this.api, this.packageName);

  @override
  Future<PlayPurchase?> get(String productId, String token) async {
    try {
      final p = await api.purchases.products.get(packageName, productId, token);
      return PlayPurchase(
        state: p.purchaseState,
        acknowledged: p.acknowledgementState,
        orderId: p.orderId,
        accountId: p.obfuscatedExternalAccountId,
      );
    } on ap.DetailedApiRequestError catch (e) {
      if (e.status == 404 || e.status == 400 || e.status == 410) return null;
      rethrow;
    }
  }

  @override
  Future<void> acknowledge(String productId, String token) =>
      api.purchases.products.acknowledge(ap.ProductPurchasesAcknowledgeRequest(), packageName, productId, token);
}

/// Compra «quitar anuncios» (PLAN.md, fase D).
class PurchaseService {
  final GameStore store;
  final PlayStore? play;
  final String productId;
  final DateTime Function() now;

  PurchaseService({required this.store, required this.play, this.productId = 'remove_ads', DateTime Function()? now})
      : now = now ?? DateTime.now;

  /// Lo que la app envía como `applicationUserName` al comprar: liga la compra
  /// a la cuenta sin revelar el uid a Google Play.
  static String accountHash(String uid) => sha256.convert(utf8.encode('escaque:$uid')).toString().substring(0, 40);

  static String tokenKey(String token) => sha256.convert(utf8.encode(token)).toString();

  /// Verifica la compra en Google Play, la reconoce (si no, Play la reembolsa
  /// a los 3 días) y activa «sin anuncios» en la cuenta.
  Future<void> verify(String uid, String product, String token) async {
    final p = play ?? (throw const ApiError(503, 'purchases_unavailable', 'Las compras no están disponibles ahora.'));
    if (product != productId) throw const ApiError(400, 'wrong_product', 'Producto desconocido.');
    if (token.isEmpty || token.length > 4096) throw ApiError.badRequest('Token de compra no válido.');
    final info = await p.get(product, token);
    if (info == null) throw const ApiError(404, 'invalid_purchase', 'Google Play no reconoce esa compra.');
    if (info.state == 2) throw const ApiError(409, 'purchase_pending', 'La compra está pendiente de pago.');
    if (info.state != 0) throw const ApiError(409, 'purchase_cancelled', 'La compra se canceló o se reembolsó.');
    if (info.accountId != null && info.accountId != accountHash(uid)) {
      throw const ApiError(403, 'purchase_other_account', 'Esa compra pertenece a otra cuenta.');
    }
    final key = tokenKey(token);
    final owner = await store.purchaseOwner(key);
    if (owner != null && owner != uid) {
      throw const ApiError(403, 'purchase_other_account', 'Esa compra pertenece a otra cuenta.');
    }
    if (info.acknowledged == 0) await p.acknowledge(product, token);
    await store.recordPurchase(key, uid: uid, orderId: info.orderId, at: now());
    await store.setAdFree(uid, true);
  }

  /// Notificaciones en tiempo real de Play (Pub/Sub, envío push): un reembolso
  /// o una anulación retiran «sin anuncios».
  Future<void> handleNotification(Map<String, Object?> body) async {
    final message = body['message'];
    if (message is! Map || message['data'] is! String) throw ApiError.badRequest('Mensaje de Pub/Sub no válido.');
    final Map<String, dynamic> n;
    try {
      n = jsonDecode(utf8.decode(base64.decode(message['data'] as String))) as Map<String, dynamic>;
    } catch (_) {
      throw ApiError.badRequest('Notificación de Play no válida.');
    }
    String? token;
    final voided = n['voidedPurchaseNotification'];
    final oneTime = n['oneTimeProductNotification'];
    if (voided is Map) token = voided['purchaseToken'] as String?;
    // notificationType 2 = ONE_TIME_PRODUCT_CANCELED
    if (oneTime is Map && oneTime['notificationType'] == 2) token = oneTime['purchaseToken'] as String?;
    if (token == null) return; // pruebas de Play Console y otros tipos: nada que hacer
    final key = tokenKey(token);
    final owner = await store.purchaseOwner(key);
    if (owner == null) return;
    await store.revokePurchase(key, at: now());
    await store.setAdFree(owner, false);
    Log.info('Compra anulada: «sin anuncios» retirado', {'uid': owner});
  }
}
