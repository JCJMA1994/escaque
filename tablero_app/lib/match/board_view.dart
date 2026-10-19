/// Instantánea del tablero, independiente del juego, que la capa Flame dibuja.
library;

enum BoardShape {
  /// Ajedrez: casilla 0 = a1, abajo a la izquierda.
  chessGrid,

  /// Damas: casilla 0 arriba a la izquierda, por filas.
  draughtsGrid,

  /// Damas chinas: índices de `StarBoard.instance.cells`.
  star,
}

enum PieceStyle { chessGlyph, disc, stone }

class PieceView {
  final int cell;

  /// Índice del jugador dueño.
  final int owner;
  final PieceStyle style;

  /// Ajedrez: nombre de la pieza (`king`, `knight`…). Damas: `crown` si es dama.
  final String? glyph;

  const PieceView({required this.cell, required this.owner, required this.style, this.glyph});
}

class BoardSnapshot {
  final BoardShape shape;

  /// Lado del tablero en casillas (no aplica a la estrella).
  final int size;

  /// Número de jugadas aplicadas. La capa Flame anima cuando sube en 1.
  final int version;
  final List<PieceView> pieces;

  /// Recorrido de la última jugada (origen, saltos, destino).
  final List<int> lastPath;

  /// Casillas cuyas piezas cayeron en la última jugada.
  final List<int> lastCaptured;

  /// Casilla del rey en jaque.
  final int? checkCell;

  const BoardSnapshot({
    required this.shape,
    required this.size,
    required this.version,
    required this.pieces,
    this.lastPath = const [],
    this.lastCaptured = const [],
    this.checkCell,
  });

  PieceView? pieceAt(int cell) {
    for (final p in pieces) {
      if (p.cell == cell) return p;
    }
    return null;
  }
}
