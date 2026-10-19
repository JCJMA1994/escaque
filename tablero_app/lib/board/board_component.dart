import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../app/theme.dart';
import '../match/board_view.dart';
import '../match/match_controller.dart';
import 'board_game.dart';
import 'board_layout.dart';

/// Dibuja casillas, marcas (último movimiento, selección, destinos, jaque) y
/// recibe los toques. Las piezas son componentes aparte para poder animarlas.
class BoardComponent extends PositionComponent
    with TapCallbacks, DragCallbacks, HasGameReference<BoardGame> {
  BoardLayout layout;
  TableroColors colors;
  MatchView? view;

  BoardComponent({required this.layout, required this.colors})
      : super(size: Vector2.all(layout.extent));

  @override
  void onTapUp(TapUpEvent event) {
    final cell = layout.cellAt(event.localPosition);
    if (cell != null) game.onCellTap(cell);
  }

  // Arrastrar y soltar: misma lógica que tocar origen y destino.
  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    final cell = layout.cellAt(event.localPosition);
    if (cell != null) game.beginDrag(cell, event.localPosition);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) => game.updateDrag(event.localDelta);

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    game.endDrag();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    game.endDrag(cancelled: true);
  }

  @override
  void render(Canvas canvas) {
    final v = view;
    if (v == null) return;
    if (layout.isGrid) {
      _renderGrid(canvas, v);
    } else {
      _renderStar(canvas, v);
    }
  }

  Rect _rect(int index) {
    final c = layout.center(index);
    return Rect.fromCenter(center: Offset(c.x, c.y), width: layout.cell, height: layout.cell);
  }

  void _renderGrid(Canvas canvas, MatchView v) {
    final n = layout.size;
    canvas.drawRect(Offset.zero & Size(layout.extent, layout.extent), Paint()..color = colors.boardFrame);
    final light = Paint()..color = colors.boardLight;
    final dark = Paint()..color = colors.boardDark;
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final r = Rect.fromLTWH(layout.frame + col * layout.cell,
            layout.frame + row * layout.cell, layout.cell, layout.cell);
        canvas.drawRect(r, (col + row) % 2 == 0 ? light : dark);
      }
    }
    final b = v.board;
    final tint = Paint()..color = colors.lastMove;
    if (b.lastPath.length >= 2) {
      canvas.drawRect(_rect(b.lastPath.first), tint);
      canvas.drawRect(_rect(b.lastPath.last), tint);
    }
    if (b.checkCell != null) {
      final r = _rect(b.checkCell!);
      canvas.drawRect(
        r,
        Paint()
          ..shader = RadialGradient(colors: [colors.check, colors.check.withAlpha(0)])
              .createShader(r),
      );
    }
    if (v.selected != null) {
      final r = _rect(v.selected!);
      canvas.drawRect(r, tint);
      canvas.drawRect(
        r.deflate(layout.cell * 0.035),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layout.cell * 0.07
          ..color = colors.accent,
      );
    }
    _renderTargets(canvas, v);
    if (b.shape == BoardShape.chessGrid && game.showCoordinates) _renderCoordinates(canvas, v);
  }

  void _renderTargets(Canvas canvas, MatchView v) {
    final hint = Paint()..color = colors.hint;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = layout.cell * 0.09
      ..color = colors.hint;
    final capturing = v.mustCapture;
    for (final t in v.targets) {
      final c = layout.center(t);
      final o = Offset(c.x, c.y);
      final occupied = v.board.pieceAt(t) != null;
      if (occupied || (capturing && layout.isGrid)) {
        canvas.drawCircle(o, layout.cell * 0.42, ring);
      } else {
        canvas.drawCircle(o, layout.cell * 0.15, hint);
      }
    }
  }

  void _renderCoordinates(Canvas canvas, MatchView v) {
    for (var i = 0; i < 64; i++) {
      final (col, row) = layout.grid(i);
      if (row != 7 && col != 0) continue;
      final r = _rect(i);
      final onLight = (col + row) % 2 == 0;
      final style = TextStyle(
        fontSize: layout.cell * 0.2,
        fontWeight: FontWeight.w700,
        color: onLight ? colors.boardFrame : colors.pieceLight,
      );
      if (col == 0) {
        _text(canvas, '${i ~/ 8 + 1}', style, Offset(r.left + layout.cell * 0.06, r.top + layout.cell * 0.04));
      }
      if (row == 7) {
        final tp = _layout(String.fromCharCode(97 + i % 8), style);
        tp.paint(canvas, Offset(r.right - tp.width - layout.cell * 0.06, r.bottom - tp.height - layout.cell * 0.02));
      }
    }
  }

  void _renderStar(Canvas canvas, MatchView v) {
    final centers = layout.starCenters;
    final board = StarBoard.instance;
    // Fondo: las seis puntas y el hexágono, como dos triángulos.
    final tips = [for (final t in board.tips) centers[t]];
    final pad = layout.cell * 0.9;
    Path triangle(List<int> ids) {
      final pts = [for (final k in ids) tips[k]];
      final mid = (pts[0] + pts[1] + pts[2]) / 3;
      final path = Path();
      for (var i = 0; i < 3; i++) {
        final dir = (pts[i] - mid).normalized();
        final p = pts[i] + dir * pad;
        i == 0 ? path.moveTo(p.x, p.y) : path.lineTo(p.x, p.y);
      }
      return path..close();
    }

    final fill = Paint()..color = colors.boardLight;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = layout.cell * 0.08
      ..strokeJoin = StrokeJoin.round
      ..color = colors.boardFrame;
    final star = Path.combine(PathOperation.union, triangle([0, 2, 4]), triangle([1, 3, 5]));
    canvas.drawPath(star, fill);
    canvas.drawPath(star, edge);

    final hole = Paint()..color = colors.boardDark;
    for (final c in centers) {
      canvas.drawCircle(Offset(c.x, c.y), layout.pieceRadius * 0.62, hole);
    }
    final b = v.board;
    final tint = Paint()..color = colors.lastMove;
    for (final i in b.lastPath) {
      final c = centers[i];
      canvas.drawCircle(Offset(c.x, c.y), layout.pieceRadius * 1.15, tint);
    }
    if (v.selected != null) {
      final c = centers[v.selected!];
      canvas.drawCircle(
        Offset(c.x, c.y),
        layout.pieceRadius * 1.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layout.cell * 0.08
          ..color = colors.accent,
      );
    }
    final hint = Paint()..color = colors.hint;
    for (final t in v.targets) {
      final c = centers[t];
      canvas.drawCircle(Offset(c.x, c.y), layout.pieceRadius * 0.62, hint);
    }
  }

  static TextPainter _layout(String text, TextStyle style) =>
      TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)
        ..layout();

  static void _text(Canvas canvas, String text, TextStyle style, Offset at) =>
      _layout(text, style).paint(canvas, at);
}
