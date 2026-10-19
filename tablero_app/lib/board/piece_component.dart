import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../match/board_view.dart';
import '../ui/piece_art.dart';

class PieceComponent extends PositionComponent {
  final PieceView view;
  final TableroColors colors;
  final double radius;

  /// Píxeles reales por unidad del mundo (para rasterizar las piezas nítidas).
  final double pixelRatio;
  ui.Image? _sprite;

  PieceComponent({
    required this.view,
    required this.colors,
    required this.radius,
    required Vector2 position,
    this.pixelRatio = 1,
  }) : super(
          position: position,
          size: Vector2.all(radius * 2.4),
          anchor: Anchor.center,
          priority: 1,
        );

  bool get _white => view.owner == 0;

  @override
  Future<void> onLoad() async {
    if (view.style == PieceStyle.chessGlyph && view.glyph != null) {
      final kind = PieceKind.values.byName(view.glyph!);
      final px = (size.x * pixelRatio).ceil().clamp(16, 512);
      _sprite = await PieceArt.image(kind, white: _white, colors: colors, px: px);
    }
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    switch (view.style) {
      case PieceStyle.chessGlyph:
        final sprite = _sprite;
        if (sprite == null) return;
        // Sombra de contacto bajo la base.
        canvas.drawOval(
          Rect.fromCenter(center: c.translate(0, radius * 0.92), width: radius * 1.5, height: radius * 0.32),
          Paint()..color = const Color(0x33000000),
        );
        canvas.drawImageRect(
          sprite,
          Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
          Offset.zero & Size(size.x, size.y),
          Paint()..filterQuality = FilterQuality.medium,
        );
      case PieceStyle.disc:
        _disc(canvas, c, _white ? colors.pieceLight : colors.pieceDark);
        if (view.glyph == 'crown') _crown(canvas, c);
      case PieceStyle.stone:
        final color = colors.players[view.owner % colors.players.length];
        _disc(canvas, c, color);
        _mark(canvas, c, view.owner);
    }
  }

  void _disc(Canvas canvas, Offset c, Color fill) {
    canvas.drawCircle(c.translate(0, radius * 0.12), radius, Paint()..color = const Color(0x40000000));
    canvas.drawCircle(c, radius, Paint()..color = fill);
    // Anillo interior: el relieve de una ficha de damas.
    canvas.drawCircle(
      c,
      radius * 0.68,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, radius * 0.06)
        ..color = (_white ? colors.pieceOutline : colors.pieceDetailDark).withAlpha(110),
    );
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, radius * 0.07)
        ..color = colors.pieceOutline,
    );
  }

  /// Corona propia de la dama de damas: tres puntas sobre una banda, en latón.
  void _crown(Canvas canvas, Offset c) {
    final r = radius * 0.46;
    final path = Path()
      ..moveTo(c.dx - r, c.dy + r * 0.55)
      ..lineTo(c.dx - r, c.dy - r * 0.35)
      ..lineTo(c.dx - r * 0.5, c.dy + r * 0.1)
      ..lineTo(c.dx, c.dy - r * 0.7)
      ..lineTo(c.dx + r * 0.5, c.dy + r * 0.1)
      ..lineTo(c.dx + r, c.dy - r * 0.35)
      ..lineTo(c.dx + r, c.dy + r * 0.55)
      ..close();
    canvas.drawPath(path, Paint()..color = colors.accent);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = math.max(1, radius * 0.06)
        ..color = colors.pieceOutline,
    );
  }

  /// Marca de forma por jugador: distinguibles sin depender del color.
  void _mark(Canvas canvas, Offset c, int owner) {
    final ink = owner == 5 || owner == 3 ? colors.pieceOutline : const Color(0xFFFFFFFF);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.16
      ..strokeCap = StrokeCap.round
      ..color = ink;
    final fill = Paint()..color = ink;
    final r = radius * 0.4;
    switch (owner) {
      case 1:
        canvas.drawCircle(c, r * 0.7, fill);
      case 2:
        canvas.drawCircle(c, r, stroke);
      case 3:
        canvas.drawLine(c.translate(-r, 0), c.translate(r, 0), stroke);
        canvas.drawLine(c.translate(0, -r), c.translate(0, r), stroke);
      case 4:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - r)
              ..lineTo(c.dx + r, c.dy)
              ..lineTo(c.dx, c.dy + r)
              ..lineTo(c.dx - r, c.dy)
              ..close(),
            fill);
      case 5:
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final a = -math.pi / 2 + i * math.pi / 5;
          final rr = i.isEven ? r * 1.1 : r * 0.45;
          final p = c.translate(rr * math.cos(a), rr * math.sin(a));
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path..close(), fill);
      default:
        break;
    }
  }
}
