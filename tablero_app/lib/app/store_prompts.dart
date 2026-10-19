import 'package:in_app_review/in_app_review.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'telemetry.dart';

/// Reseñas y actualizaciones con las APIs de Google Play.
abstract final class StorePrompts {
  static const _kWins = 'winsForReview', _kAsked = 'reviewAsked';

  /// Tras la tercera victoria, pide una reseña una sola vez. Google decide
  /// si muestra el diálogo (tiene su propia cuota).
  static Future<void> registerWin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kAsked) ?? false) return;
      final wins = (prefs.getInt(_kWins) ?? 0) + 1;
      await prefs.setInt(_kWins, wins);
      if (wins < 3) return;
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await prefs.setBool(_kAsked, true);
        await review.requestReview();
      }
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'In-app review');
    }
  }

  /// Actualización inmediata desde Play. Devuelve `false` si no hay
  /// actualización disponible (instalación fuera de Play, por ejemplo).
  static Future<bool> updateNow() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return false;
      await InAppUpdate.performImmediateUpdate();
      return true;
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'In-app update');
      return false;
    }
  }
}
