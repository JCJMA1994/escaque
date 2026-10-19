import 'package:flutter/widgets.dart';

import 'en.dart';

/// Idiomas de la app. El texto en español es la clave (estilo gettext):
///
///     tr('Juegos')
///     tr('Racha de {n} días', {'n': streak})
///
/// Así funcionan también los textos guardados en datos (etiquetas de enums,
/// reglas, motivos de fin de partida, mensajes del servidor): `tr(variable)`.
/// Las traducciones están en `en.dart`; `test/l10n_test.dart` comprueba que
/// cada clave usada en el código tiene la suya.
abstract final class L10n {
  static const supported = [Locale('es'), Locale('en')];
  static String _lang = 'es';

  static String get lang => _lang;
  static Locale get locale => Locale(_lang);

  /// [choice]: `system`, `es` o `en`. Con `system`, español si el teléfono
  /// está en español y, si no, inglés.
  static void apply(String choice, Locale device) {
    _lang = choice == 'system' ? (device.languageCode == 'es' ? 'es' : 'en') : choice;
  }

  /// Solo para tests.
  static void debugSet(String lang) => _lang = lang;
}

String tr(String es, [Map<String, Object?> args = const {}]) {
  var s = L10n.lang == 'es' ? es : (enStrings[es] ?? es);
  if (args.isNotEmpty) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  }
  return s;
}
