import '../l10n/l10n.dart';
/// Jugadas en lenguaje natural para lectores de pantalla (TalkBack).
abstract final class Spoken {
  static const _pieces = {'K': 'rey', 'Q': 'dama', 'R': 'torre', 'B': 'alfil', 'N': 'caballo'};
  static final _san = RegExp(r'^([KQRBN])?[a-h]?[1-8]?(x)?([a-h][1-8])(?:=([QRBN]))?([+#])?$');

  /// «Caballo a f3», «Peón captura en e5, jaque», «Enroque corto»…
  static String chess(String san) {
    final suffix = san.endsWith('#')
        ? tr(', jaque mate')
        : san.endsWith('+')
            ? tr(', jaque')
            : '';
    final core = san.replaceAll(RegExp(r'[+#!?]'), '');
    if (core == 'O-O') return tr('Enroque corto{suffix}', {'suffix': suffix});
    if (core == 'O-O-O') return tr('Enroque largo{suffix}', {'suffix': suffix});
    final m = _san.firstMatch(core);
    if (m == null) return san;
    final piece = tr(_pieces[m.group(1)] ?? 'peón');
    final action = m.group(2) != null ? tr('captura en') : tr('a');
    final promo = m.group(4) != null ? tr(', corona en {p0}', {'p0': tr(_pieces[m.group(4)]!)}) : '';
    final text = '$piece $action ${m.group(3)}$promo$suffix';
    return text[0].toUpperCase() + text.substring(1);
  }

  /// «De 32 a 28» o «Captura de 28 a 19, toma 2 piezas».
  static String draughts(String notation, int captured) {
    final capture = notation.contains('x');
    final parts = notation.split(RegExp('[-x]'));
    if (parts.length != 2) return notation;
    if (!capture) return tr('De {p0} a {p1}', {'p0': parts[0], 'p1': parts[1]});
    final pieces = captured == 1 ? tr('1 pieza') : tr('{n} piezas', {'n': captured});
    return tr('Captura de {p0} a {p1}, toma {pieces}', {'p0': parts[0], 'p1': parts[1], 'pieces': pieces});
  }
}
