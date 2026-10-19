import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablero_engine/tablero_engine.dart';

import 'telemetry.dart';
import 'theme.dart';

class AppSettings {
  final ThemeMode themeMode;

  /// Idioma: `system`, `es` o `en`.
  final String language;
  final bool showCoordinates;

  /// Notación de ajedrez con letras en español (R, D, T, A, C).
  final bool spanishNotation;
  final String defaultDraughtsVariant;
  final bool sound;

  /// Avisos de partidas online (los respeta el servidor).
  final bool onlineAlerts;
  final bool onlineReminders;

  final BoardTheme boardTheme;

  /// Enviar informes de errores (Crashlytics).
  final bool crashReports;

  /// Arrastrar piezas además de tocar origen y destino.
  final bool dragPieces;

  /// Mostrar las frases fijas del rival en las partidas online.
  final bool showPhrases;

  const AppSettings({
    this.showPhrases = true,
    this.boardTheme = BoardTheme.wood,
    this.crashReports = true,
    this.dragPieces = true,
    this.sound = true,
    this.onlineAlerts = true,
    this.onlineReminders = true,
    this.themeMode = ThemeMode.system,
    this.language = 'system',
    this.showCoordinates = true,
    this.spanishNotation = false,
    this.defaultDraughtsVariant = 'spanish',
  });

  DraughtsVariant get draughtsVariant => DraughtsVariant.all.firstWhere(
        (v) => v.id == defaultDraughtsVariant,
        orElse: () => DraughtsVariant.spanish,
      );

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? language,
    bool? showCoordinates,
    bool? spanishNotation,
    String? defaultDraughtsVariant,
    bool? sound,
    bool? onlineAlerts,
    bool? onlineReminders,
    BoardTheme? boardTheme,
    bool? dragPieces,
    bool? crashReports,
    bool? showPhrases,
  }) =>
      AppSettings(
        showPhrases: showPhrases ?? this.showPhrases,
        crashReports: crashReports ?? this.crashReports,
        boardTheme: boardTheme ?? this.boardTheme,
        dragPieces: dragPieces ?? this.dragPieces,
        sound: sound ?? this.sound,
        onlineAlerts: onlineAlerts ?? this.onlineAlerts,
        onlineReminders: onlineReminders ?? this.onlineReminders,
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
        showCoordinates: showCoordinates ?? this.showCoordinates,
        spanishNotation: spanishNotation ?? this.spanishNotation,
        defaultDraughtsVariant: defaultDraughtsVariant ?? this.defaultDraughtsVariant,
      );
}

class SettingsController extends Notifier<AppSettings> {
  static const _kTheme = 'theme', _kCoords = 'coords', _kSpanish = 'spanishSan', _kVariant = 'variant', _kSound = 'sound', _kAlerts = 'onlineAlerts', _kReminders = 'onlineReminders', _kBoard = 'boardTheme', _kDrag = 'dragPieces', _kCrash = 'crashReports', _kLang = 'language', _kPhrases = 'showPhrases';

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString(_kTheme),
        orElse: () => ThemeMode.system,
      ),
      showCoordinates: prefs.getBool(_kCoords) ?? true,
      spanishNotation: prefs.getBool(_kSpanish) ?? false,
      defaultDraughtsVariant: prefs.getString(_kVariant) ?? 'spanish',
      sound: prefs.getBool(_kSound) ?? true,
      onlineAlerts: prefs.getBool(_kAlerts) ?? true,
      onlineReminders: prefs.getBool(_kReminders) ?? true,
      boardTheme: BoardTheme.values.firstWhere(
        (t) => t.name == prefs.getString(_kBoard),
        orElse: () => BoardTheme.wood,
      ),
      dragPieces: prefs.getBool(_kDrag) ?? true,
      showPhrases: prefs.getBool(_kPhrases) ?? true,
      crashReports: prefs.getBool(_kCrash) ?? true,
      language: prefs.getString(_kLang) ?? 'system',
    );
  }

  Future<void> _write(AppSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, next.themeMode.name);
    await prefs.setBool(_kCoords, next.showCoordinates);
    await prefs.setBool(_kSpanish, next.spanishNotation);
    await prefs.setString(_kVariant, next.defaultDraughtsVariant);
    await prefs.setBool(_kSound, next.sound);
    await prefs.setBool(_kAlerts, next.onlineAlerts);
    await prefs.setBool(_kReminders, next.onlineReminders);
    await prefs.setString(_kBoard, next.boardTheme.name);
    await prefs.setBool(_kDrag, next.dragPieces);
    await prefs.setBool(_kPhrases, next.showPhrases);
    await prefs.setBool(_kCrash, next.crashReports);
    await prefs.setString(_kLang, next.language);
  }

  void setThemeMode(ThemeMode m) => _write(state.copyWith(themeMode: m));
  void setShowCoordinates(bool v) => _write(state.copyWith(showCoordinates: v));
  void setSpanishNotation(bool v) => _write(state.copyWith(spanishNotation: v));
  void setDefaultVariant(String id) => _write(state.copyWith(defaultDraughtsVariant: id));
  void setSound(bool v) => _write(state.copyWith(sound: v));
  void setOnlineAlerts(bool v) => _write(state.copyWith(onlineAlerts: v));
  void setOnlineReminders(bool v) => _write(state.copyWith(onlineReminders: v));
  void setBoardTheme(BoardTheme t) => _write(state.copyWith(boardTheme: t));
  void setDragPieces(bool v) => _write(state.copyWith(dragPieces: v));
  void setShowPhrases(bool v) => _write(state.copyWith(showPhrases: v));
  void setLanguage(String v) => _write(state.copyWith(language: v));
  void setCrashReports(bool v) {
    _write(state.copyWith(crashReports: v));
    Telemetry.setEnabled(v);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Convierte SAN inglés (estándar FIDE) a letras en español:
/// K→R, Q→D, R→T, B→A, N→C. Columnas y enroques no cambian.
String spanishSan(String san) {
  const map = {'K': 'R', 'Q': 'D', 'R': 'T', 'B': 'A', 'N': 'C'};
  final sb = StringBuffer();
  for (final ch in san.split('')) {
    sb.write(map[ch] ?? ch);
  }
  return sb.toString();
}
