import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tablero_app/l10n/en.dart';
import 'package:tablero_app/l10n/l10n.dart';
import 'package:tablero_app/learn/lessons.dart';
import 'package:tablero_app/match/spoken.dart';

/// Todas las claves de tr('…') del código tienen traducción al inglés, con los
/// mismos marcadores {…}. Los textos que llegan por datos (reglas, motivos de
/// fin de partida, mensajes del servidor) se comprueban en la misma lista.
void main() {
  final literal = RegExp(r"tr\(\s*'((?:[^'\\]|\\.)*)'");
  // Sin cruzar otras cadenas antes del «?»: solo ternarios dentro del propio tr().
  final ternary = RegExp(r"tr\(\s*[^;']*?\?\s*'((?:[^'\\]|\\.)*)'\s*:\s*'((?:[^'\\]|\\.)*)'");
  final placeholders = RegExp(r'\{\w+\}');
  String unescape(String s) => s.replaceAll(r"\'", "'").replaceAll(r'\$', r'$').replaceAll(r'\n', '\n');

  final keys = <String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('l10n')) continue;
    final src = f.readAsStringSync();
    for (final m in literal.allMatches(src)) {
      keys.add(unescape(m.group(1)!));
    }
    for (final m in ternary.allMatches(src)) {
      keys
        ..add(unescape(m.group(1)!))
        ..add(unescape(m.group(2)!));
    }
  }

  test('cada clave del código tiene inglés', () {
    final missing = keys.where((k) => !enStrings.containsKey(k)).toList()..sort();
    expect(missing, isEmpty, reason: 'Sin traducir:\n${missing.join('\n')}');
  });

  test('los textos de las lecciones tienen inglés', () {
    final missing = [
      for (final l in lessons)
        for (final t in [l.title, l.text, l.done, ...l.traps.values])
          if (!enStrings.containsKey(t)) '${l.id}: $t',
    ];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('los marcadores coinciden', () {
    for (final e in enStrings.entries) {
      final a = placeholders.allMatches(e.key).map((m) => m[0]).toList()..sort();
      final b = placeholders.allMatches(e.value).map((m) => m[0]).toList()..sort();
      expect(b, a, reason: e.key);
    }
  });

  test('tr sustituye marcadores y cae al español si falta la clave', () {
    L10n.debugSet('en');
    expect(tr('Racha de {n} días', {'n': 5}), '5-day streak');
    expect(tr('Texto sin traducir'), 'Texto sin traducir');
    L10n.debugSet('es');
    expect(tr('Racha de {n} días', {'n': 5}), 'Racha de 5 días');
  });

  test('idioma del sistema: español o, si no, inglés', () {
    L10n.apply('system', const Locale('es', 'PE'));
    expect(L10n.lang, 'es');
    L10n.apply('system', const Locale('pt', 'BR'));
    expect(L10n.lang, 'en');
    L10n.apply('es', const Locale('en'));
    expect(L10n.lang, 'es');
  });

  test('anuncios de jugadas en inglés', () {
    L10n.debugSet('en');
    expect(Spoken.chess('Nf3'), 'Knight to f3');
    expect(Spoken.chess('exd5+'), 'Pawn takes on d5, check');
    expect(Spoken.chess('O-O'), 'Kingside castling');
    expect(Spoken.draughts('28x10', 2), 'Capture from 28 to 10, takes 2 pieces');
    L10n.debugSet('es');
  });
}
