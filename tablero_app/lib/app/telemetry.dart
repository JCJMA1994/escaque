
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'env.dart';

/// Informes de errores con Firebase Crashlytics.
///
/// - Errores no capturados de Flutter y de Dart: fatales.
/// - Errores esperables pero anómalos (la IA no mueve, el servidor falla):
///   no fatales con [nonFatal].
/// - Desactivado en depuración y cuando la persona lo apaga en Ajustes.
/// - Sin identificadores de persona: ni uid, ni correo, ni nombre de usuario
///   (datos técnicos del fallo y del dispositivo, nada más).
abstract final class Telemetry {
  static bool _ready = false;

  static Future<void> init({required bool firebaseReady, required bool enabled}) async {
    if (!firebaseReady) return;
    try {
      final c = FirebaseCrashlytics.instance;
      await c.setCrashlyticsCollectionEnabled(enabled && !kDebugMode);
      await c.setCustomKey('env', AppEnv.name);
      final previousFlutter = FlutterError.onError;
      FlutterError.onError = (details) {
        c.recordFlutterFatalError(details);
        previousFlutter?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        c.recordError(error, stack, fatal: true);
        return true;
      };
      _ready = true;
    } catch (_) {
      // Sin Crashlytics la app funciona igual.
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    if (_ready) await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled && !kDebugMode);
  }

  /// Rastro de lo que pasó antes de un error (sin datos personales).
  static void log(String message) {
    if (_ready) FirebaseCrashlytics.instance.log(message);
  }

  static void nonFatal(Object error, StackTrace stack, {String? reason}) {
    if (_ready) FirebaseCrashlytics.instance.recordError(error, stack, reason: reason, fatal: false);
    if (kDebugMode) debugPrint('No fatal: $reason $error');
  }
}
