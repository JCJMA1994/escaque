import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../match/board_view.dart';

/// Conversión casilla ↔ coordenadas del mundo Flame (un cuadrado de [extent]).
class BoardLayout {
  final BoardShape shape;
  final int size;
  final bool flipped;
  final double extent;

  late final double frame;
  late final double cell;
  late final double pieceRadius;
  late final List<Vector2> _starCenters;

  BoardLayout({
    required this.shape,
    required this.size,
    required this.flipped,
    required this.extent,
  }) {
    if (shape == BoardShape.star) {
      _buildStar();
    } else {
      frame = extent * 0.035;
      cell = (extent - 2 * frame) / size;
      pieceRadius = cell * 0.4;
    }
  }

  bool get isGrid => shape != BoardShape.star;

  void _buildStar() {
    final sqrt3 = math.sqrt(3);
    final unit = [
      for (final h in StarBoard.instance.cells)
        Vector2(sqrt3 * (h.q + h.r / 2), 1.5 * h.r),
    ];
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in unit) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    frame = extent * 0.06;
    final scale = (extent - 2 * frame) / math.max(maxX - minX, maxY - minY);
    final offsetX = (extent - (maxX - minX) * scale) / 2;
    final offsetY = (extent - (maxY - minY) * scale) / 2;
    _starCenters = [
      for (final p in unit)
        Vector2(offsetX + (p.x - minX) * scale, offsetY + (p.y - minY) * scale),
    ];
    cell = sqrt3 * scale; // distancia entre centros vecinos
    pieceRadius = cell * 0.4;
  }

  /// Columna y fila en pantalla (0, 0 arriba a la izquierda).
  (int, int) grid(int index) {
    late int col, row;
    if (shape == BoardShape.chessGrid) {
      col = index % 8;
      row = 7 - index ~/ 8;
    } else {
      col = index % size;
      row = index ~/ size;
    }
    return flipped ? (size - 1 - col, size - 1 - row) : (col, row);
  }

  int fromGrid(int col, int row) {
    if (flipped) {
      col = size - 1 - col;
      row = size - 1 - row;
    }
    return shape == BoardShape.chessGrid ? (7 - row) * 8 + col : row * size + col;
  }

  Vector2 center(int index) {
    if (!isGrid) return _starCenters[index].clone();
    final (col, row) = grid(index);
    return Vector2(frame + (col + 0.5) * cell, frame + (row + 0.5) * cell);
  }

  List<Vector2> get starCenters => _starCenters;

  int? cellAt(Vector2 p) {
    if (isGrid) {
      final col = ((p.x - frame) / cell).floor();
      final row = ((p.y - frame) / cell).floor();
      if (col < 0 || row < 0 || col >= size || row >= size) return null;
      return fromGrid(col, row);
    }
    int? best;
    var bestDist = double.infinity;
    for (var i = 0; i < _starCenters.length; i++) {
      final d = _starCenters[i].distanceTo(p);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return bestDist <= cell * 0.6 ? best : null;
  }
}
