import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'env.dart';
import 'telemetry.dart';

/// Ajustes remotos (Firebase Remote Config), sin publicar otra versión:
///
/// | Clave | Para qué |
/// | --- | --- |
/// | `min_supported_build` | Versiones más antiguas deben actualizar (cambios incompatibles del servidor) |
/// | `online_enabled` | Interruptor de emergencia del modo online |
/// | `online_message` | Texto que se muestra si el online está apagado |
/// | `interstitial_every_games` | Frecuencia del intersticial entre partidas |
@immutable
class RemoteFlags {
  final int minSupportedBuild;
  final bool onlineEnabled;
  final String onlineMessage;
  final int interstitialEveryGames;
  final int currentBuild;

  const RemoteFlags({
    this.minSupportedBuild = 0,
    this.onlineEnabled = true,
    this.onlineMessage = '',
    this.interstitialEveryGames = 2,
    this.currentBuild = 0,
  });

  bool get updateRequired => currentBuild > 0 && currentBuild < minSupportedBuild;
}

abstract final class RemoteFlagsService {
  static final flags = ValueNotifier<RemoteFlags>(const RemoteFlags());

  static const _defaults = <String, dynamic>{
    'min_supported_build': 0,
    'online_enabled': true,
    'online_message': 'El modo online está en mantenimiento. Vuelve en un rato.',
    'interstitial_every_games': 2,
  };

  static Future<void> init({required bool firebaseReady}) async {
    final build = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    flags.value = RemoteFlags(currentBuild: build);
    if (!firebaseReady) return;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setDefaults(_defaults);
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: AppEnv.isProd ? const Duration(hours: 1) : const Duration(minutes: 1),
      ));
      await rc.fetchAndActivate();
      _publish(rc, build);
      // Cambios en tiempo real (por ejemplo, apagar el online durante un incidente).
      rc.onConfigUpdated.listen((_) async {
        await rc.activate();
        _publish(rc, build);
      }, onError: (Object _) {});
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Remote Config');
    }
  }

  static void _publish(FirebaseRemoteConfig rc, int build) {
    flags.value = RemoteFlags(
      minSupportedBuild: rc.getInt('min_supported_build'),
      onlineEnabled: rc.getBool('online_enabled'),
      onlineMessage: rc.getString('online_message'),
      interstitialEveryGames: rc.getInt('interstitial_every_games').clamp(1, 10),
      currentBuild: build,
    );
  }
}
