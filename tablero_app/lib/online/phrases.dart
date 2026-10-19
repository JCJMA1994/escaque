import '../l10n/l10n.dart';

/// Frases fijas de las partidas online (el servidor solo acepta estos ids).
/// Sin texto libre: nada que moderar.
const phraseIds = [
  'hello', 'good_luck', 'good_move', 'oops', 'thinking', 'thanks',
  'well_played', 'rematch', 'sorry', 'wow', 'your_turn', 'bye',
];

String phraseText(String id) => switch (id) {
      'hello' => tr('¡Hola!'),
      'good_luck' => tr('¡Suerte!'),
      'good_move' => tr('¡Buena jugada!'),
      'oops' => tr('¡Uy!'),
      'thinking' => tr('Déjame pensar…'),
      'thanks' => tr('¡Gracias!'),
      'well_played' => tr('Bien jugado'),
      'rematch' => tr('¿Revancha?'),
      'sorry' => tr('Perdón'),
      'wow' => tr('¡Vaya!'),
      'your_turn' => tr('Te toca'),
      'bye' => tr('¡Hasta luego!'),
      _ => '…',
    };
