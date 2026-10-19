import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'online_repository.dart';
import '../l10n/l10n.dart';

/// Cliente de la API de tablero_server. Cada petición lleva el token de
/// Firebase Auth y, si está disponible, el de App Check.
class ApiClient {
  /// URL del servicio de Cloud Run, fijada al compilar:
  ///   --dart-define=TABLERO_API=https://tablero-api-xxxx.a.run.app
  static const baseUrl = String.fromEnvironment('TABLERO_API');

  final http.Client _http;
  ApiClient([http.Client? client]) : _http = client ?? http.Client();

  static bool get configured => baseUrl.isNotEmpty;

  Future<Map<String, dynamic>> post(String path, [Map<String, Object?> body = const {}]) async {
    if (!configured) {
      throw OnlineException(tr('El servidor online no está configurado en esta compilación.'));
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw OnlineException(tr('Inicia sesión con tu cuenta para jugar online.'), code: 'account_required');
    }
    final idToken = await user.getIdToken();
    String? appCheck;
    try {
      appCheck = await FirebaseAppCheck.instance.getToken();
    } catch (_) {
      // Sin App Check el servidor decide (en modo «enforce» rechaza).
    }
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $idToken',
              'x-firebase-appcheck': ?appCheck,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw OnlineException(tr('El servidor tarda en responder. Revisa tu conexión.'), code: 'timeout');
    } catch (_) {
      throw OnlineException(tr('Sin conexión con el servidor.'), code: 'network');
    }
    Map<String, dynamic> data;
    try {
      data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      data = {};
    }
    if (res.statusCode >= 400) {
      throw OnlineException(
        serverMessage(data, res.statusCode),
        code: data['error'] as String?,
        serverPly: data['ply'] as int?,
      );
    }
    return data;
  }
}

/// Mensaje del servidor en el idioma de la app. El servidor envía el texto en
/// español (clave de [tr]) y, cuando lleva valores, también los datos.
String serverMessage(Map<String, dynamic> data, int status) {
  final code = data['error'] as String?;
  switch (code) {
    case 'too_many_waiting':
      return tr('Tienes {limit} partidas esperando rival. Cancela alguna antes de crear otra.',
          {'limit': data['limit'] ?? 10});
    case 'username_cooldown':
      final until = DateTime.tryParse(data['until'] as String? ?? '')?.toLocal();
      if (until != null) {
        return tr('Podrás volver a cambiar tu nombre de usuario a partir del {date}.',
            {'date': '${until.day}/${until.month}/${until.year}'});
      }
  }
  final message = data['message'] as String?;
  return message == null ? tr('Error del servidor ({statusCode}).', {'statusCode': status}) : tr(message);
}
