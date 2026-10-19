import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../app/remote_flags.dart';
import '../app/env.dart';
import 'ad_ids.dart';

/// Consentimiento (UMP) y anuncios. Reglas de producto:
/// - Nunca hay anuncios durante una partida.
/// - Intersticial solo entre partidas: cada 2 partidas terminadas y como
///   mínimo 3 minutos desde el anterior.
/// - Recompensado solo si la persona lo pide (pista).
class AdsService {
  /// Remote Config `interstitial_every_games` (2 por defecto).
  int get _gamesPerInterstitial => RemoteFlagsService.flags.value.interstitialEveryGames;
  static const _minGap = Duration(minutes: 3);

  bool _canRequestAds = false;
  bool _initialized = false;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  int _finishedSinceAd = 0;
  DateTime? _lastInterstitial;

  final ValueNotifier<bool> ready = ValueNotifier(false);

  bool get canRequestAds => _canRequestAds && !adFree;

  /// Compró «quitar anuncios»: no se carga ni se muestra ninguno.
  bool adFree = false;

  void setAdFree(bool value) {
    adFree = value;
    if (value) {
      _interstitial?.dispose();
      _interstitial = null;
      _rewarded?.dispose();
      _rewarded = null;
    } else if (_initialized && _canRequestAds) {
      _loadInterstitial();
      _loadRewarded();
    }
  }

  /// Pide el consentimiento si hace falta y arranca el SDK. Llamar una vez
  /// al abrir la app; no bloquea la interfaz.
  Future<void> init() async {
    if (AppEnv.screenshots) return; // capturas de Play: sin anuncios
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
          if (!done.isCompleted) done.complete();
        });
      },
      (FormError error) {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    await _startIfAllowed();
  }

  Future<void> _startIfAllowed() async {
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    if (!_canRequestAds || _initialized) return;
    _initialized = true;
    await MobileAds.instance.initialize();
    ready.value = true;
    _loadInterstitial();
    _loadRewarded();
  }

  /// ¿Debe mostrarse «Privacidad de anuncios» en Ajustes?
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    await _startIfAllowed();
  }

  void _loadInterstitial() {
    if (adFree) return;
    if (!_canRequestAds) return;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (error) => _interstitial = null,
      ),
    );
  }

  void _loadRewarded() {
    if (adFree) return;
    if (!_canRequestAds) return;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (error) => _rewarded = null,
      ),
    );
  }

  /// Llamar cuando termina una partida.
  void gameFinished() => _finishedSinceAd++;

  /// Muestra un intersticial si toca según la frecuencia. Espera a que se cierre.
  Future<void> maybeShowInterstitial() async {
    final ad = _interstitial;
    if (adFree || ad == null || _finishedSinceAd < _gamesPerInterstitial) return;
    final last = _lastInterstitial;
    if (last != null && DateTime.now().difference(last) < _minGap) return;
    _interstitial = null;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    _finishedSinceAd = 0;
    _lastInterstitial = DateTime.now();
    await ad.show();
    await closed.future;
    _loadInterstitial();
  }

  /// Sin anuncios, no hay recompensado: la pista se da directamente.
  bool get rewardedAvailable => !adFree && _rewarded != null;

  /// Muestra un recompensado. Devuelve `true` si se ganó la recompensa.
  /// Si no hay anuncio disponible devuelve `null`: la app decide (la pista
  /// se da igual, para no castigar a quien no tiene anuncios).
  Future<bool?> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) return null;
    _rewarded = null;
    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.show(onUserEarnedReward: (ad, reward) => earned = true);
    await closed.future;
    _loadRewarded();
    return earned;
  }
}

final adsServiceProvider = Provider<AdsService>((ref) => AdsService());
