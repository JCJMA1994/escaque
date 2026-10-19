import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'telemetry.dart';

/// Estadísticas de uso con Firebase Analytics, con consentimiento.
///
/// - **Desactivadas hasta que la persona acepta**, en todos los países: la Ley
///   29733 de Perú (reglamento DS 016-2024-JUS) exige consentimiento previo y
///   expreso para todo tratamiento, igual que el RGPD. La app lo pregunta una
///   vez ([needsAnswer]) y se cambia en Ajustes → Privacidad.
/// - Modo de consentimiento v2: solo `analytics_storage`; los permisos de
///   publicidad de Analytics se deniegan siempre (los anuncios los gestiona
///   UMP en AdMob, no Analytics).
/// - Eventos sin datos personales: ni uid, ni nombre de usuario, ni correo.
abstract final class Metrics {
  static const _kPref = 'usageStats';
  static bool _ready = false;
  static bool _enabled = false;

  /// `null` si la persona no ha elegido todavía.
  static Future<bool?> storedChoice() async {
    final v = (await SharedPreferences.getInstance()).getString(_kPref);
    return v == null ? null : v == 'on';
  }

  static bool get enabled => _enabled;

  /// La persona todavía no ha respondido a la pregunta de estadísticas.
  static bool needsAnswer = false;

  static Future<void> init({required bool firebaseReady}) async {
    if (!firebaseReady) return;
    try {
      _ready = true;
      final choice = await storedChoice();
      needsAnswer = choice == null;
      await _apply(choice ?? false);
    } catch (e, st) {
      _ready = false;
      Telemetry.nonFatal(e, st, reason: 'Analytics');
    }
  }

  static Future<void> setEnabled(bool on) async {
    needsAnswer = false;
    await (await SharedPreferences.getInstance()).setString(_kPref, on ? 'on' : 'off');
    if (_ready) await _apply(on);
  }

  static Future<void> _apply(bool on) async {
    final a = FirebaseAnalytics.instance;
    await a.setConsent(
      analyticsStorageConsentGranted: on,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await a.setAnalyticsCollectionEnabled(on && !kDebugMode);
    _enabled = on;
  }

  static void _log(String name, Map<String, Object> params) {
    if (!_ready || !_enabled) return;
    FirebaseAnalytics.instance.logEvent(name: name, parameters: params).catchError((Object _) {});
  }

  // ---- Eventos (PLAN.md, punto 0) --------------------------------------------

  /// [mode]: `ai`, `local` u `online`.
  static void gameStart({required String kind, required String mode, int? aiLevel}) =>
      _log('game_start', {'kind': kind, 'mode': mode, 'ai_level': ?aiLevel});

  /// [result]: `win`, `loss` o `draw` (desde la persona; en local, `end`).
  static void gameEnd({required String kind, required String mode, required String result, required int plies}) =>
      _log('game_end', {'kind': kind, 'mode': mode, 'result': result, 'plies': plies});

  static void puzzleSolved({required int mateIn, required bool daily, required int attempts}) =>
      _log('puzzle_solved', {'mate_in': mateIn, 'daily': daily ? 1 : 0, 'attempts': attempts});

  static void tutorialStep({required String lesson, required bool ok}) =>
      _log('tutorial_step', {'lesson': lesson, 'ok': ok ? 1 : 0});

  static void purchaseRemoveAds() => _log('purchase_remove_ads', const {});

  /// [via]: `code` o `link`.
  static void onlineInvite() => _log('online_invite', const {});
  static void onlineJoin({required String via}) => _log('online_join', {'via': via});
}
