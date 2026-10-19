import 'package:googleapis/fcm/v1.dart' as fcm;

import 'log.dart';
import 'store.dart';

enum NoticeKind { yourTurn, opponentJoined, drawOffered, gameOver, reminder, rematch, friendRequest, friendAccepted, challenge }

class Notice {
  final NoticeKind kind;
  final String gameId;

  /// Texto en español (por defecto) y en inglés; el aviso sale en el idioma
  /// que la persona tiene en la app (`users/{uid}.locale`).
  final String title;
  final String body;
  final String? titleEn;
  final String? bodyEn;
  const Notice(this.kind, this.gameId, this.title, this.body, {this.titleEn, this.bodyEn});

  String titleFor(String? locale) => locale == 'en' ? (titleEn ?? title) : title;
  String bodyFor(String? locale) => locale == 'en' ? (bodyEn ?? body) : body;

  @override
  String toString() => '$kind($gameId): $title — $body';
}

abstract interface class Notifier {
  /// Mejor esfuerzo: nunca lanza; un fallo de aviso no deshace una jugada.
  Future<void> notify(String uid, Notice notice);
}

class NoopNotifier implements Notifier {
  @override
  Future<void> notify(String uid, Notice notice) async {}
}

/// Para tests: guarda lo enviado.
class RecordingNotifier implements Notifier {
  final sent = <(String, Notice)>[];

  @override
  Future<void> notify(String uid, Notice notice) async => sent.add((uid, notice));

  List<Notice> to(String uid) => [for (final (u, n) in sent) if (u == uid) n];
}

/// Envía con FCM HTTP v1 a todos los dispositivos del usuario.
class FcmNotifier implements Notifier {
  final fcm.FirebaseCloudMessagingApi api;
  final GameStore store;
  final String projectId;

  /// Canal de Android que crea la app («Turnos»).
  static const channelId = 'turnos';

  FcmNotifier({required this.api, required this.store, required this.projectId});

  @override
  Future<void> notify(String uid, Notice notice) async {
    try {
      final prefs = await store.userProfile(uid);
      if (!prefs.notify) return;
      if (notice.kind == NoticeKind.reminder && !prefs.reminders) return;
      for (final token in await store.deviceTokens(uid)) {
        await _send(uid, token, notice, prefs.locale);
      }
    } catch (e, st) {
      Log.error('Aviso no enviado', e, st, {'uid': uid, 'kind': notice.kind.name, 'gameId': notice.gameId});
    }
  }

  Future<void> _send(String uid, String token, Notice n, String? locale) async {
    final message = fcm.Message(
      token: token,
      notification: fcm.Notification(title: n.titleFor(locale), body: n.bodyFor(locale)),
      data: {'gameId': n.gameId, 'type': n.kind.name},
      android: fcm.AndroidConfig(
        // Una sola notificación visible por partida: la nueva sustituye a la anterior.
        collapseKey: n.gameId,
        priority: 'HIGH',
        notification: fcm.AndroidNotification(channelId: channelId, tag: n.gameId),
      ),
    );
    try {
      await api.projects.messages.send(fcm.SendMessageRequest(message: message), 'projects/$projectId');
    } on fcm.DetailedApiRequestError catch (e) {
      // 404 UNREGISTERED: la app se desinstaló o el token caducó.
      final invalid = e.status == 404 ||
          (e.status == 400 && (e.message ?? '').toLowerCase().contains('registration token'));
      if (invalid) {
        await store.deleteDeviceToken(uid, token);
      } else {
        rethrow;
      }
    }
  }
}

/// Textos del servidor en inglés para los avisos.
abstract final class ServerText {
  static String gameTitle(String kind, String variant, {required bool en}) => switch (kind) {
        'chess' => en ? 'Chess' : 'Ajedrez',
        'chineseCheckers' => en ? 'Chinese checkers' : 'Damas chinas',
        _ => switch (variant) {
            'international' => en ? 'International draughts' : 'Damas internacionales',
            'english' => en ? 'English draughts' : 'Damas inglesas',
            _ => en ? 'Spanish draughts' : 'Damas españolas',
          },
      };

  /// Motivos de fin de partida (los guardan el motor y el servidor en español).
  static const _reasons = {
    'reto rechazado': 'challenge declined',
    'jaque mate': 'checkmate',
    'rey ahogado': 'stalemate',
    'tiempo agotado': 'time out',
    'tiempo agotado, rival sin material para dar mate': 'time out, opponent cannot checkmate',
    'abandono': 'resignation',
    'acuerdo mutuo': 'mutual agreement',
    'posición muerta: material insuficiente': 'dead position: insufficient material',
    'quíntuple repetición': 'fivefold repetition',
    'regla de los 75 movimientos': '75-move rule',
    'triple repetición': 'threefold repetition',
    'regla de los 50 movimientos': '50-move rule',
    'repetición de posición': 'repetition',
    'jugadas sin progreso': 'moves without progress',
    'el rival no puede mover': 'opponent cannot move',
    'completó la punta opuesta': 'filled the opposite point',
    'cuenta eliminada': 'account deleted',
    'partida cancelada': 'game cancelled',
  };

  static String reason(String? es) => _reasons[es] ?? es ?? '';
}
