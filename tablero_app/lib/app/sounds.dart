import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

/// Sonidos propios (generados para el proyecto, sin licencias de terceros).
abstract final class Sounds {
  static const move = 'move.wav';
  static const capture = 'capture.wav';
  static const check = 'check.wav';
  static const end = 'end.wav';

  static Future<void> preload() async {
    try {
      await FlameAudio.audioCache.loadAll(const [move, capture, check, end]);
    } catch (_) {
      // Sin audio la app sigue funcionando.
    }
  }

  static void play(String file) {
    unawaited(FlameAudio.play(file, volume: 0.7).then((_) {}, onError: (Object _) {}));
  }
}
