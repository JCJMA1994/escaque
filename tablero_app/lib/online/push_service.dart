import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n.dart';

/// Avisos de partidas online con Firebase Cloud Messaging. Los envía
/// tablero_server; aquí se gestionan el permiso, el token y la apertura.
class PushService {
  static const channelId = 'turnos';
  static const _askedKey = 'pushPermissionAsked';

  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  final _subs = <StreamSubscription<Object?>>[];
  bool _started = false;

  /// Prepara el canal, escucha mensajes y registra el token si ya hay permiso.
  /// [onOpen]: el usuario tocó una notificación de la partida `gameId`.
  /// [onForeground]: llegó un aviso con la app abierta.
  Future<void> start({
    required void Function(String gameId) onOpen,
    required void Function(RemoteMessage message) onForeground,
    void Function()? onFriends,
  }) async {
    if (_started) return;
    _started = true;
    await _createChannel();
    _subs.add(FirebaseMessaging.onMessage.listen(onForeground));
    // Avisos de partida → la partida; de amistad (sin partida) → Amigos.
    void open(RemoteMessage m) {
      final id = m.data['gameId'];
      final type = m.data['type'];
      if (id is String && id.isNotEmpty) {
        onOpen(id);
      } else if (type is String && type.startsWith('friend')) {
        onFriends?.call();
      }
    }

    _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(open));
    final initial = await _fm.getInitialMessage();
    if (initial != null) open(initial);
    _subs.add(_fm.onTokenRefresh.listen(_saveToken));
    if (await hasPermission()) await registerToken();
  }

  /// Canal «Turnos» con importancia alta (Android 8+).
  Future<void> _createChannel() async {
    final channel = AndroidNotificationChannel(
      channelId,
      tr('Turnos'),
      description: tr('Te avisa cuando te toca jugar, cuando tu rival se une o propone tablas.'),
      importance: Importance.high,
    );
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<bool> hasPermission() async {
    final s = await _fm.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// ¿Toca preguntar? Solo una vez y solo si aún no hay permiso.
  Future<bool> shouldAsk() async {
    if (await hasPermission()) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_askedKey) ?? false);
  }

  /// Pide el permiso del sistema (Android 13+). Devuelve si se concedió.
  Future<bool> requestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_askedKey, true);
    final s = await _fm.requestPermission();
    final ok = s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
    if (ok) await registerToken();
    return ok;
  }

  Future<void> registerToken() async {
    final token = await _fm.getToken();
    if (token != null) await _saveToken(token);
  }

  Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    final uid = user.uid;
    await FirebaseFirestore.instance.doc('users/$uid/devices/$token').set({
      'platform': 'android',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Al cerrar sesión: este dispositivo deja de recibir avisos de la cuenta.
  Future<void> unregisterThisDevice() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final token = await _fm.getToken();
    if (uid == null || token == null) return;
    await FirebaseFirestore.instance.doc('users/$uid/devices/$token').delete();
  }

  /// Preferencias que el servidor respeta antes de enviar.
  /// Idioma de la app en el perfil: el servidor redacta los avisos en él.
  Future<void> saveLocale(String lang) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return;
    try {
      await FirebaseFirestore.instance.doc('users/${u.uid}').set(
        {'locale': lang, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Sin conexión: se guardará en el próximo arranque.
    }
  }

  /// Aceptar solicitudes de amistad (lo consulta el servidor).
  Future<void> saveFriendRequests(bool on) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .doc('users/$uid')
        .set({'friendRequests': on, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> savePreferences({required bool notify, required bool reminders}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.doc('users/$uid').set({
      'notify': notify,
      'reminders': reminders,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  final s = PushService();
  ref.onDispose(s.dispose);
  return s;
});
