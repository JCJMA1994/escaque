import 'package:flutter/material.dart';

/// Temas del tablero: el color de las casillas y el marco.
enum BoardTheme {
  wood('Madera'),
  felt('Fieltro'),
  contrast('Alto contraste');

  final String label;
  const BoardTheme(this.label);
}

/// Tokens de color de Escaque (tema claro y oscuro). Contrastes comprobados:
/// texto ≥ 4,5:1 y bordes de control ≥ 3:1 en los dos temas.
@immutable
class TableroColors extends ThemeExtension<TableroColors> {
  final Color bg, surface, surfaceRaised, ink, inkMuted, line, lineStrong;
  final Color brand, brandInk, accent, accentInk, danger;

  /// Fieltro: la banda de cabecera de Inicio y del icono.
  final Color felt, feltInk;
  final Color boardLight, boardDark, boardFrame;
  final Color pieceLight, pieceDark, pieceOutline, pieceDetailDark;
  final Color hint, lastMove, check;

  /// Colores de jugador de damas chinas (player-1 … player-6).
  final List<Color> players;

  const TableroColors({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.lineStrong,
    required this.brand,
    required this.brandInk,
    required this.accent,
    required this.accentInk,
    required this.danger,
    required this.felt,
    required this.feltInk,
    required this.boardLight,
    required this.boardDark,
    required this.boardFrame,
    required this.pieceLight,
    required this.pieceDark,
    required this.pieceOutline,
    required this.pieceDetailDark,
    required this.hint,
    required this.lastMove,
    required this.check,
    required this.players,
  });

  static const _players = [
    Color(0xFFC2410C),
    Color(0xFF1D4ED8),
    Color(0xFF15803D),
    Color(0xFFEAB308),
    Color(0xFF1C1917),
    Color(0xFFFAFAF9),
  ];

  /// Claro: blanco mineral con un punto de verde, tinta verde casi negra,
  /// fieltro de mesa de club y latón.
  static const light = TableroColors(
    bg: Color(0xFFEEF1EC),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFE2E7E1),
    ink: Color(0xFF16201C),
    inkMuted: Color(0xFF4F5C56),
    line: Color(0xFFD0D7D0),
    lineStrong: Color(0xFF76837C),
    brand: Color(0xFF17543F),
    brandInk: Color(0xFFFFFFFF),
    accent: Color(0xFFC08A1E),
    accentInk: Color(0xFF16201C),
    danger: Color(0xFFB3261E),
    felt: Color(0xFF17543F),
    feltInk: Color(0xFFF6F3EA),
    boardLight: Color(0xFFE9D8B4),
    boardDark: Color(0xFFA0704A),
    boardFrame: Color(0xFF4E3624),
    pieceLight: Color(0xFFF6F3EA),
    pieceDark: Color(0xFF23201D),
    pieceOutline: Color(0xFF3A2E22),
    pieceDetailDark: Color(0xFFB9AE98),
    hint: Color(0x7317543F),
    lastMove: Color(0x66C08A1E),
    check: Color(0x8CB3261E),
    players: _players,
  );

  /// Oscuro: la mesa de noche; maderas atenuadas para no deslumbrar.
  static const dark = TableroColors(
    bg: Color(0xFF0E1513),
    surface: Color(0xFF161F1C),
    surfaceRaised: Color(0xFF1F2925),
    ink: Color(0xFFE7EDE9),
    inkMuted: Color(0xFF9FADA6),
    line: Color(0xFF29342F),
    lineStrong: Color(0xFF677670),
    brand: Color(0xFF5DBE9A),
    brandInk: Color(0xFF08201A),
    accent: Color(0xFFE2B04E),
    accentInk: Color(0xFF0E1513),
    danger: Color(0xFFF2867D),
    felt: Color(0xFF123F30),
    feltInk: Color(0xFFF3EEDF),
    boardLight: Color(0xFFC9B08A),
    boardDark: Color(0xFF7A5636),
    boardFrame: Color(0xFF2E2016),
    pieceLight: Color(0xFFEFE8DA),
    pieceDark: Color(0xFF1A1714),
    pieceOutline: Color(0xFF2B2219),
    pieceDetailDark: Color(0xFFA89D88),
    hint: Color(0x8C5DBE9A),
    lastMove: Color(0x66E2B04E),
    check: Color(0x99F2867D),
    players: _players,
  );

  /// Mismos tokens con las casillas del tema de tablero elegido.
  TableroColors withBoard(BoardTheme theme) {
    final dark = identical(this, TableroColors.dark) || bg.computeLuminance() < 0.2;
    final (l, d, f) = switch (theme) {
      BoardTheme.wood => (boardLight, boardDark, boardFrame),
      BoardTheme.felt => dark
          ? (const Color(0xFF8FB5A3), const Color(0xFF2C5E4B), const Color(0xFF0B2A20))
          : (const Color(0xFFCFE0D6), const Color(0xFF3E7A62), const Color(0xFF17543F)),
      BoardTheme.contrast => dark
          ? (const Color(0xFFDADFE3), const Color(0xFF4B5A67), const Color(0xFF000000))
          : (const Color(0xFFFFFFFF), const Color(0xFF4A5A68), const Color(0xFF1B2430)),
    };
    return TableroColors(
      bg: bg, surface: surface, surfaceRaised: surfaceRaised, ink: ink, inkMuted: inkMuted,
      line: line, lineStrong: lineStrong, brand: brand, brandInk: brandInk, accent: accent,
      accentInk: accentInk, danger: danger, felt: felt, feltInk: feltInk,
      boardLight: l, boardDark: d, boardFrame: f,
      pieceLight: pieceLight, pieceDark: pieceDark, pieceOutline: pieceOutline,
      pieceDetailDark: pieceDetailDark, hint: hint, lastMove: lastMove, check: check, players: players,
    );
  }

  static TableroColors of(BuildContext context) =>
      Theme.of(context).extension<TableroColors>()!;

  @override
  TableroColors copyWith() => this;

  @override
  TableroColors lerp(ThemeExtension<TableroColors>? other, double t) =>
      other is TableroColors && t >= 0.5 ? other : this;
}

/// Tipografía: una sola familia, Archivo, usada en dos anchos. Expandida y
/// pesada para títulos (marcador de torneo); normal para la interfaz.
/// JetBrains Mono con cifras tabulares para relojes y notación.
/// Las fuentes son variables: el peso y el ancho se fijan con `fontVariations`.
abstract final class TType {
  static TextStyle _archivo(double size, double height, double weight, Color c,
          {double width = 100, double spacing = 0}) =>
      TextStyle(
        fontFamily: 'Archivo',
        fontSize: size,
        height: height / size,
        letterSpacing: spacing,
        color: c,
        fontWeight: _weight(weight),
        fontVariations: [FontVariation('wght', weight), FontVariation('wdth', width)],
      );

  static FontWeight _weight(double w) => FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

  /// 34/38, expandida 125, 800: el nombre de la app y los resultados.
  static TextStyle display(Color c) => _archivo(34, 38, 800, c, width: 125, spacing: -0.3);

  /// 24/30, ancho 112, 700: títulos de pantalla y nombres de juego.
  static TextStyle titleLg(Color c) => _archivo(24, 30, 700, c, width: 112);
  static TextStyle title(Color c) => _archivo(18, 24, 700, c);
  static TextStyle body(Color c) => _archivo(16, 24, 400, c);
  static TextStyle bodySm(Color c) => _archivo(14, 20, 400, c);
  static TextStyle label(Color c) => _archivo(15, 20, 600, c);
  static TextStyle caption(Color c) => _archivo(12.5, 16, 600, c, spacing: 0.2);

  static TextStyle clock(Color c) => TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 26,
        height: 30 / 26,
        color: c,
        fontWeight: FontWeight.w500,
        fontVariations: const [FontVariation('wght', 500)],
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle notation(Color c) => TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 14,
        height: 20 / 14,
        color: c,
        fontVariations: const [FontVariation('wght', 400)],
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? TableroColors.light : TableroColors.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.brand,
    onPrimary: c.brandInk,
    secondary: c.accent,
    onSecondary: c.accentInk,
    error: c.danger,
    onError: c.bg,
    surface: c.surface,
    onSurface: c.ink,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final base = ThemeData(brightness: brightness, fontFamily: 'Archivo').textTheme;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Archivo',
    scaffoldBackgroundColor: c.bg,
    textTheme: base.apply(bodyColor: c.ink, displayColor: c.ink),
    extensions: [c],
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    focusColor: c.accent.withAlpha(90),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.brandInk,
        minimumSize: const Size(64, 52),
        shape: shape,
        textStyle: TType.label(c.brandInk).copyWith(fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        backgroundColor: c.surface,
        minimumSize: const Size(64, 52),
        side: BorderSide(color: c.lineStrong, width: 1.5),
        shape: shape,
        textStyle: TType.label(c.ink).copyWith(fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.brand,
        minimumSize: const Size(48, 48),
        shape: shape,
        textStyle: TType.label(c.brand),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      labelStyle: TType.bodySm(c.inkMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.lineStrong, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.lineStrong, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.brand, width: 2)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brandInk : c.lineStrong),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brand : c.surfaceRaised),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TType.bodySm(c.bg),
      actionTextColor: c.accent,
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.brand),
  );
}
