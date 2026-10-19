/// Parámetros de cada variante de damas. Una variante nueva es un objeto de
/// configuración, no un motor nuevo.
library;

enum CaptureRule {
  /// Captura obligatoria, pero el jugador elige cualquier secuencia (inglesa).
  free,

  /// Obligatorio capturar el máximo de piezas (internacional).
  maxPieces,

  /// Máximo de piezas; si hay empate, la que capture más damas (española).
  maxPiecesThenKings,
}

enum MidCapturePromotion {
  /// Un peón que llega a la última fila capturando corona y termina el turno.
  endsTurn,

  /// Sigue capturando como peón; solo corona si termina en la última fila.
  continueAsMan,
}

class DraughtsVariant {
  final String id;
  final String name;

  /// Lado del tablero: 8 o 10.
  final int size;

  /// Filas iniciales ocupadas por cada bando.
  final int rowsPerSide;
  final bool menCaptureBackward;

  /// Dama larga (vuela por la diagonal) o corta (una casilla).
  final bool flyingKings;
  final CaptureRule captureRule;
  final MidCapturePromotion midCapture;

  /// 1 = empiezan blancas, -1 = empiezan negras.
  final int firstToMove;

  /// Medias jugadas sin progreso (sin captura ni movimiento de peón) que dan
  /// tablas. `null` = sin regla automática.
  final int? quietPliesForDraw;

  /// Repeticiones de la misma posición que dan tablas.
  final int repetitionsForDraw;

  const DraughtsVariant({
    required this.id,
    required this.name,
    required this.size,
    required this.rowsPerSide,
    required this.menCaptureBackward,
    required this.flyingKings,
    required this.captureRule,
    required this.midCapture,
    required this.firstToMove,
    required this.quietPliesForDraw,
    required this.repetitionsForDraw,
  });

  /// Reglamento FMJD. Tablas: 25 jugadas por bando solo con damas, sin
  /// capturas; triple repetición. Pendiente: reglas de finales de 16 y 5
  /// jugadas (art. 6 del reglamento).
  static const international = DraughtsVariant(
    id: 'international',
    name: 'Internacional',
    size: 10,
    rowsPerSide: 4,
    menCaptureBackward: true,
    flyingKings: true,
    captureRule: CaptureRule.maxPieces,
    midCapture: MidCapturePromotion.continueAsMan,
    firstToMove: 1,
    quietPliesForDraw: 50,
    repetitionsForDraw: 3,
  );

  /// Reglamento WCDF (inglesa / americana). Empiezan las negras.
  /// Tablas: 40 jugadas por bando sin progreso; triple repetición.
  static const english = DraughtsVariant(
    id: 'english',
    name: 'Inglesa',
    size: 8,
    rowsPerSide: 3,
    menCaptureBackward: false,
    flyingKings: false,
    captureRule: CaptureRule.free,
    midCapture: MidCapturePromotion.endsTurn,
    firstToMove: -1,
    quietPliesForDraw: 80,
    repetitionsForDraw: 3,
  );

  /// Damas españolas. Pendiente de confirmar con el reglamento oficial:
  /// orientación del tablero y reglas de tablas (por eso
  /// [quietPliesForDraw] es `null`).
  static const spanish = DraughtsVariant(
    id: 'spanish',
    name: 'Española',
    size: 8,
    rowsPerSide: 3,
    menCaptureBackward: false,
    flyingKings: true,
    captureRule: CaptureRule.maxPiecesThenKings,
    midCapture: MidCapturePromotion.endsTurn,
    firstToMove: 1,
    quietPliesForDraw: null,
    repetitionsForDraw: 3,
  );

  static const all = [international, english, spanish];
}
