import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablero_app/main.dart' as app;

/// Flujo completo sin cuenta en un dispositivo o emulador:
///   flutter test integration_test --flavor dev --dart-define-from-file=config/dev.json
///
/// El tablero (Flame) y el reloj nunca «se asientan», así que se avanza el
/// tiempo con [pumpFor] en lugar de `pumpAndSettle`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < total; t += step) {
      await tester.pump(step);
    }
  }

  Future<void> tapText(WidgetTester tester, String text, {bool last = false}) async {
    final finder = find.text(text);
    expect(finder, findsWidgets, reason: 'No aparece «$text»');
    await tester.tap(last ? finder.last : finder.first);
    await pumpFor(tester, const Duration(milliseconds: 800));
  }

  testWidgets('presentación → partida de ajedrez contra la IA → rendirse → resultado', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await app.main();
    await pumpFor(tester, const Duration(seconds: 2));

    // Presentación
    expect(find.text('Escaque'), findsWidgets);
    await tapText(tester, 'Saltar');
    await tapText(tester, 'Jugar sin cuenta');

    // Inicio → Nueva partida
    expect(find.text('Juegos'), findsOneWidget);
    await tapText(tester, 'Ajedrez');
    expect(find.text('Nueva partida'), findsOneWidget);
    await tapText(tester, 'Jugar');

    // Partida
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Rendirse'), findsOneWidget);
    expect(find.byType(GestureDetector), findsWidgets);

    // Rendirse: botón de la barra y confirmación del diálogo
    await tapText(tester, 'Rendirse');
    await tapText(tester, 'Rendirse', last: true);
    await pumpFor(tester, const Duration(seconds: 2));

    // Resultado
    expect(find.textContaining('abandono'), findsOneWidget);
    expect(find.text('Revancha'), findsOneWidget);
  });
}
