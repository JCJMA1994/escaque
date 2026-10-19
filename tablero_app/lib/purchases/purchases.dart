import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ads/ads_service.dart';
import '../app/metrics.dart';
import '../app/telemetry.dart';
import '../l10n/l10n.dart';
import '../online/online_repository.dart';

/// Estado de «quitar anuncios» (PLAN.md, fase D).
class AdFreeState {
  final bool adFree;

  /// Precio del producto en la moneda de la tienda; `null` si no está disponible.
  final String? price;
  final bool busy;
  final String? message;
  const AdFreeState({this.adFree = false, this.price, this.busy = false, this.message});

  AdFreeState copyWith({bool? adFree, String? price, bool? busy, String? message, bool clearMessage = false}) =>
      AdFreeState(
        adFree: adFree ?? this.adFree,
        price: price ?? this.price,
        busy: busy ?? this.busy,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// Compra no consumible `remove_ads` con `in_app_purchase`.
///
/// - Al confirmar Google Play la compra, la ventaja se activa en el teléfono y
///   se completa la compra (la reconoce): así nunca se pierde.
/// - Con cuenta, el servidor la verifica y la guarda en `users/{uid}.adFree`,
///   que es la fuente de verdad (y la retira si hay reembolso). Si la
///   verificación falla por la red, se reintenta en el siguiente arranque.
/// - Sin cuenta, la compra vive en la cuenta de Google: «Restaurar compras».
class AdFreeController extends Notifier<AdFreeState> {
  static const productId = 'remove_ads';
  static const _kLocal = 'adFree', _kPendingToken = 'adFreePendingToken', _kVerifiedUid = 'adFreeVerifiedUid';
  bool _silentRestore = false;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;

  /// Lo mismo que calcula el servidor (PurchaseService.accountHash).
  static String accountHash(String uid) => sha256.convert(utf8.encode('escaque:$uid')).toString().substring(0, 40);

  @override
  AdFreeState build() {
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(_init);
    return const AdFreeState();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kLocal) ?? false) _set(true);
    try {
      final iap = InAppPurchase.instance;
      if (!await iap.isAvailable()) return;
      _sub = iap.purchaseStream.listen(_onPurchases, onError: (Object e, StackTrace st) {
        Telemetry.nonFatal(e, st, reason: 'Compras: flujo');
      });
      final res = await iap.queryProductDetails({productId});
      if (res.productDetails.isNotEmpty) {
        _product = res.productDetails.first;
        state = state.copyWith(price: _product!.price);
      }
      // Verificación pendiente de un arranque anterior (sin red entonces).
      final pending = prefs.getString(_kPendingToken);
      if (pending != null) await _verifyOnServer(pending);
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Compras: inicio');
    }
  }

  /// Estado del perfil en el servidor para la cuenta [uid].
  ///
  /// - `true`: la cuenta compró (en este u otro teléfono).
  /// - `false` tras haberla verificado para esta cuenta: reembolso, se retira.
  /// - `false` con una compra local sin ligar (hecha sin cuenta): se restaura en
  ///   silencio para ligarla a la cuenta; nunca se quita una compra legítima.
  Future<void> syncFromServer(String uid, bool serverAdFree) async {
    final prefs = await SharedPreferences.getInstance();
    if (serverAdFree) {
      await prefs.setString(_kVerifiedUid, uid);
      if (!state.adFree) _set(true);
      return;
    }
    if (prefs.getString(_kVerifiedUid) == uid) {
      await prefs.remove(_kVerifiedUid);
      if (state.adFree) _set(false);
      return;
    }
    if (state.adFree && !_silentRestore) {
      _silentRestore = true;
      try {
        await InAppPurchase.instance.restorePurchases();
      } catch (_) {}
    }
  }

  Future<void> buy() async {
    final product = _product;
    if (product == null) {
      state = state.copyWith(message: tr('La tienda no está disponible ahora. Inténtalo más tarde.'));
      return;
    }
    state = state.copyWith(busy: true, clearMessage: true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          // Liga la compra a la cuenta sin revelar el uid a Google Play.
          applicationUserName: user == null || user.isAnonymous ? null : accountHash(user.uid),
        ),
      );
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Compras: comprar');
      state = state.copyWith(busy: false, message: tr('No se pudo iniciar la compra.'));
    }
  }

  Future<void> restore() async {
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await InAppPurchase.instance.restorePurchases();
      // Si había compra, llega por el flujo como «restored».
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (state.busy) {
          state = state.copyWith(
              busy: false, message: state.adFree ? null : tr('No encontramos compras en esta cuenta de Google.'));
        }
      });
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Compras: restaurar');
      state = state.copyWith(busy: false, message: tr('No se pudieron restaurar las compras.'));
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != productId) continue;
      switch (p.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(busy: true, message: tr('Compra pendiente de pago. Te avisaremos al completarse.'));
        case PurchaseStatus.canceled:
          state = state.copyWith(busy: false, clearMessage: true);
        case PurchaseStatus.error:
          state = state.copyWith(busy: false, message: tr('La compra no se completó.'));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final token = p.verificationData.serverVerificationData;
          await _grant(token, restored: p.status == PurchaseStatus.restored);
      }
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (e, st) {
          Telemetry.nonFatal(e, st, reason: 'Compras: completar');
        }
      }
    }
  }

  Future<void> _grant(String token, {required bool restored}) async {
    _set(true);
    final silent = restored && _silentRestore;
    state = state.copyWith(
      busy: false,
      message: silent ? null : (restored ? tr('Compra restaurada: no verás anuncios.') : tr('¡Gracias! Ya no verás anuncios.')),
    );
    if (!restored) Metrics.purchaseRemoveAds();
    await _verifyOnServer(token);
  }

  Future<void> _verifyOnServer(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return; // sin cuenta: solo en el teléfono
    try {
      await ref.read(onlineRepositoryProvider).api.post('/v1/purchases/verify', {'productId': productId, 'token': token});
      await prefs.remove(_kPendingToken);
      await prefs.setString(_kVerifiedUid, user.uid);
    } on OnlineException catch (e) {
      if (e.code == 'network' || e.code == 'timeout' || e.code == 'purchases_unavailable') {
        await prefs.setString(_kPendingToken, token); // se reintenta en el próximo arranque
      } else {
        await prefs.remove(_kPendingToken);
        state = state.copyWith(message: e.message);
      }
    }
  }

  void _set(bool adFree) {
    state = state.copyWith(adFree: adFree);
    ref.read(adsServiceProvider).setAdFree(adFree);
    SharedPreferences.getInstance().then((p) => p.setBool(_kLocal, adFree));
  }
}

final adFreeProvider = NotifierProvider<AdFreeController, AdFreeState>(AdFreeController.new);
