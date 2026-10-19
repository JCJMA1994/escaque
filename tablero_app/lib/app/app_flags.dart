import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Indicadores que el router necesita de forma síncrona.
abstract final class AppFlags {
  static const _kOnboarding = 'onboardingDone';

  /// `false` hasta que la persona elige cómo jugar en la presentación.
  static final onboardingDone = ValueNotifier<bool>(true);

  /// Se llama en `main` antes de `runApp`.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    onboardingDone.value = prefs.getBool(_kOnboarding) ?? false;
  }

  static Future<void> completeOnboarding() async {
    onboardingDone.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboarding, true);
  }
}
