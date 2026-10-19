import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablero_app/app/router.dart';
import 'package:tablero_app/l10n/l10n.dart';
import 'package:tablero_app/main.dart' as app;

/// Capturas de Play Store, por idioma y dispositivo:
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/screenshots_test.dart --flavor dev \
///     --dart-define-from-file=config/dev.json --dart-define=SCREENSHOTS=true \
///     --dart-define=SHOT_LANG=en --dart-define=SHOT_DEVICE=phone
///
/// Salen en `build/screenshots/[dispositivo]_[idioma]_[n]_[pantalla].png`.
void main() {
  const lang = String.fromEnvironment('SHOT_LANG', defaultValue: 'es');
  const device = String.fromEnvironment('SHOT_DEVICE', defaultValue: 'phone');
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
    for (var t = 0; t < ms; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  var n = 0;
  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    n++;
    await binding.takeScreenshot('${device}_${lang}_${n.toString().padLeft(2, '0')}_$name');
  }

  testWidgets('capturas $device $lang', (tester) async {
    // Presentación vista, idioma fijo y estadísticas ya respondidas: pantallas limpias.
    SharedPreferences.setMockInitialValues({'onboardingDone': true, 'language': lang, 'usageStats': 'off'});
    await app.main();
    await binding.convertFlutterSurfaceToImage();
    await settle(tester, 3000);

    await shot(tester, 'inicio');

    appRouter.go('/new/chess');
    await shot(tester, 'nueva_partida');

    await tester.tap(find.text(tr('Jugar')).last);
    await settle(tester, 3000);
    await shot(tester, 'partida_ajedrez');

    appRouter.go('/new/draughts');
    await settle(tester);
    await tester.tap(find.text(tr('Jugar')).last);
    await settle(tester, 3000);
    await shot(tester, 'partida_damas');

    appRouter.go('/puzzles/3');
    await shot(tester, 'problema');

    appRouter.go('/puzzles');
    await shot(tester, 'problemas');

    appRouter.go('/new/chineseCheckers');
    await settle(tester);
    await tester.tap(find.text(tr('Jugar')).last);
    await settle(tester, 3000);
    await shot(tester, 'damas_chinas');

    appRouter.go('/');
    await settle(tester);
    await tester.tap(find.text(tr('Ajustes')).last);
    await shot(tester, 'ajustes');
  });
}
