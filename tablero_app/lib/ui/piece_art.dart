import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/theme.dart';

/// Piezas de ajedrez propias (assets/pieces/*.svg). Cada SVG es una plantilla
/// con FILL, LINE y DETAIL que se sustituyen por los colores del tema.
enum PieceKind { king, queen, rook, bishop, knight, pawn }

abstract final class PieceArt {
  static final _templates = <PieceKind, String>{};
  static final _images = <String, ui.Image>{};

  /// Carga las seis plantillas (una vez).
  static Future<void> preload() async {
    for (final k in PieceKind.values) {
      _templates[k] ??= await rootBundle.loadString('assets/pieces/${k.name}.svg');
    }
  }

  static String svg(PieceKind kind, {required bool white, required TableroColors colors}) {
    final t = _templates[kind];
    if (t == null) throw StateError('PieceArt.preload() no se ha llamado');
    final fill = white ? colors.pieceLight : colors.pieceDark;
    final line = white ? colors.pieceOutline : const Color(0xFF0E0C0A);
    final detail = white ? colors.pieceOutline : colors.pieceDetailDark;
    return t.replaceAll('FILL', _hex(fill)).replaceAll('LINE', _hex(line)).replaceAll('DETAIL', _hex(detail));
  }

  /// Imagen rasterizada al tamaño exacto en píxeles, en caché (para Flame).
  static Future<ui.Image> image(PieceKind kind,
      {required bool white, required TableroColors colors, required int px}) async {
    await preload();
    final source = svg(kind, white: white, colors: colors);
    final key = '${kind.name}|$white|$px|${source.hashCode}';
    final cached = _images[key];
    if (cached != null) return cached;
    final info = await vg.loadPicture(SvgStringLoader(source), null);
    final scale = px / info.size.width;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawPicture(info.picture);
    final image = await recorder.endRecording().toImage(px, px);
    info.picture.dispose();
    return _images[key] = image;
  }

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// Pieza como widget (onboarding, coronación, tarjetas).
class PieceIcon extends StatelessWidget {
  final PieceKind kind;
  final bool white;
  final double size;
  const PieceIcon(this.kind, {super.key, this.white = true, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final colors = TableroColors.of(context);
    return FutureBuilder<void>(
      future: PieceArt.preload(),
      builder: (context, snap) => snap.connectionState != ConnectionState.done
          ? SizedBox.square(dimension: size)
          : SvgPicture.string(PieceArt.svg(kind, white: white, colors: colors), width: size, height: size),
    );
  }
}
