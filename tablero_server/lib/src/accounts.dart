import 'dart:convert';

import 'package:http/http.dart' as http;

import 'errors.dart';

/// Estado de una cuenta en Firebase Authentication que el token no lleva:
/// desde cuándo son válidos sus tokens (se mueve al cerrar sesión en todos
/// los dispositivos o cambiar la contraseña) y si está desactivada.
class AccountState {
  final DateTime? validSince;
  final bool disabled;
  const AccountState({this.validSince, this.disabled = false});
}

abstract interface class AccountLookup {
  /// `null` si la cuenta no existe.
  Future<AccountState?> lookup(String uid);
}

/// Cuánto se exige de un token según la operación.
enum Sensitivity {
  /// Firma, caducidad y tipo de cuenta (todas las peticiones).
  normal,

  /// Además, que no se haya revocado (cambiar el nombre de usuario).
  checkRevoked,

  /// Además, inicio de sesión reciente (borrar la cuenta).
  recentLogin,
}

/// Reglas de revocación, sin red (se prueban aparte).
abstract final class Revocation {
  static const recentLoginWindow = Duration(minutes: 5);

  static void check({
    required AccountState? account,
    required DateTime issuedAt,
    required DateTime? authTime,
    required Sensitivity sensitivity,
    required DateTime now,
  }) {
    if (sensitivity == Sensitivity.normal) return;
    if (account == null || account.disabled) {
      throw const ApiError(401, 'token_revoked', 'Tu sesión ya no es válida. Vuelve a iniciar sesión.');
    }
    final since = account.validSince;
    // validSince tiene precisión de segundos, igual que iat.
    if (since != null && issuedAt.isBefore(since)) {
      throw const ApiError(401, 'token_revoked', 'Tu sesión se cerró en otro dispositivo. Vuelve a iniciar sesión.');
    }
    if (sensitivity == Sensitivity.recentLogin &&
        (authTime == null || now.difference(authTime) > recentLoginWindow)) {
      throw const ApiError(401, 'recent_login_required', 'Por seguridad, confirma de nuevo tu identidad.');
    }
  }
}

/// `accounts:lookup` de Identity Toolkit con la cuenta de servicio del
/// servidor (rol `roles/firebaseauth.viewer`). Caché de 5 minutos por cuenta.
class IdentityToolkitLookup implements AccountLookup {
  final http.Client client;
  final String projectId;
  final Duration ttl;
  final DateTime Function() now;
  final _cache = <String, (AccountState?, DateTime)>{};

  IdentityToolkitLookup(this.client, this.projectId, {this.ttl = const Duration(minutes: 5), DateTime Function()? now})
      : now = now ?? DateTime.now;

  @override
  Future<AccountState?> lookup(String uid) async {
    final hit = _cache[uid];
    if (hit != null && now().difference(hit.$2) < ttl) return hit.$1;
    final res = await client.post(
      Uri.parse('https://identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:lookup'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'localId': [uid],
      }),
    );
    if (res.statusCode != 200) {
      // Sin respuesta no se puede asegurar nada: se rechaza la operación sensible.
      throw const ApiError(503, 'auth_unavailable', 'No se pudo comprobar tu sesión. Inténtalo en un momento.');
    }
    final users = (jsonDecode(res.body) as Map<String, dynamic>)['users'] as List?;
    final state = users == null || users.isEmpty ? null : parse(users.first as Map<String, dynamic>);
    if (_cache.length > 10000) _cache.clear();
    _cache[uid] = (state, now());
    return state;
  }

  static AccountState parse(Map<String, dynamic> user) {
    final since = int.tryParse('${user['validSince'] ?? ''}');
    return AccountState(
      validSince: since == null ? null : DateTime.fromMillisecondsSinceEpoch(since * 1000, isUtc: true),
      disabled: user['disabled'] == true,
    );
  }
}
