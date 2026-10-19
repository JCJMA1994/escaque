import 'package:jose/jose.dart';
import 'package:shelf/shelf.dart';

import 'accounts.dart';
import 'errors.dart';
import 'log.dart';

/// Quién llama a la API.
abstract interface class Authenticator {
  /// uid de Firebase del jugador; lanza [ApiError.unauthorized]. Con
  /// [requireVerified], una cuenta de correo debe tenerlo verificado.
  /// [sensitivity] añade la comprobación de revocación o de inicio de sesión
  /// reciente para operaciones delicadas.
  Future<String> userId(Request request, {bool requireVerified = true, Sensitivity sensitivity = Sensitivity.normal});

  /// Solo Cloud Scheduler (token OIDC de su cuenta de servicio).
  Future<void> requireScheduler(Request request);
}

enum AppCheckMode {
  /// Rechaza peticiones sin un token de App Check válido.
  enforce,

  /// Lo comprueba y lo registra, pero deja pasar (para el despliegue inicial).
  monitor,
  off,
}

/// Verificación con las claves públicas de Google (JWKS), sin SDK de Admin.
class GoogleAuthenticator implements Authenticator {
  final String projectId;
  final String projectNumber;
  final AppCheckMode appCheck;

  /// Cuenta de servicio de Cloud Scheduler y audiencia de su token (URL del servicio).
  final String schedulerEmail;
  final String schedulerAudience;

  final _firebaseKeys = JsonWebKeyStore()
    ..addKeySetUrl(Uri.parse(
        'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
  final _appCheckKeys = JsonWebKeyStore()
    ..addKeySetUrl(Uri.parse('https://firebaseappcheck.googleapis.com/v1/jwks'));
  final _googleKeys = JsonWebKeyStore()
    ..addKeySetUrl(Uri.parse('https://www.googleapis.com/oauth2/v3/certs'));

  GoogleAuthenticator({
    required this.projectId,
    required this.projectNumber,
    required this.appCheck,
    required this.schedulerEmail,
    required this.schedulerAudience,
  });

  /// Estado de las cuentas para [Sensitivity.checkRevoked] y superiores.
  AccountLookup? accounts;

  @override
  Future<String> userId(Request request,
      {bool requireVerified = true, Sensitivity sensitivity = Sensitivity.normal}) async {
    final token = _bearer(request);
    final jwt = await _verify(token, _firebaseKeys);
    final problems = jwt.claims.validate(
      issuer: Uri.parse('https://securetoken.google.com/$projectId'),
      clientId: projectId,
    );
    final uid = jwt.claims.subject;
    if (problems.isNotEmpty || uid == null || uid.isEmpty) throw ApiError.unauthorized;
    checkAccount(jwt.claims['firebase'], jwt.claims['email_verified'], requireVerified: requireVerified);
    await _checkAppCheck(request);
    if (sensitivity != Sensitivity.normal) {
      final lookup = accounts ?? (throw StateError('GoogleAuthenticator.accounts sin configurar'));
      final authTime = jwt.claims['auth_time'];
      Revocation.check(
        account: await lookup.lookup(uid),
        issuedAt: jwt.claims.issuedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        authTime: authTime is num ? DateTime.fromMillisecondsSinceEpoch(authTime.toInt() * 1000, isUtc: true) : null,
        sensitivity: sensitivity,
        now: DateTime.now().toUtc(),
      );
    }
    return uid;
  }

  /// Online exige cuenta registrada: nada de sesiones anónimas, y con
  /// correo y contraseña, el correo verificado.
  static void checkAccount(Object? firebaseClaim, Object? emailVerified, {bool requireVerified = true}) {
    final provider = firebaseClaim is Map ? firebaseClaim['sign_in_provider'] : null;
    if (provider == null || provider == 'anonymous') {
      throw const ApiError(403, 'account_required', 'Inicia sesión con tu cuenta para jugar online.');
    }
    if (requireVerified && provider == 'password' && emailVerified != true) {
      throw const ApiError(403, 'email_not_verified',
          'Verifica tu correo para jugar online. Revisa tu bandeja de entrada.');
    }
  }

  Future<void> _checkAppCheck(Request request) async {
    if (appCheck == AppCheckMode.off) return;
    final token = request.headers['x-firebase-appcheck'];
    var ok = false;
    if (token != null && token.isNotEmpty) {
      try {
        final jwt = await JsonWebToken.decodeAndVerify(token, _appCheckKeys);
        ok = jwt.claims
            .validate(
              issuer: Uri.parse('https://firebaseappcheck.googleapis.com/$projectNumber'),
              clientId: 'projects/$projectNumber',
            )
            .isEmpty;
      } catch (_) {
        ok = false;
      }
    }
    if (ok) return;
    if (appCheck == AppCheckMode.enforce) {
      throw const ApiError(401, 'app_check', 'Esta versión de la app no está verificada. Actualízala desde Google Play.');
    }
    Log.warning('Petición sin App Check válido (modo monitor)', {'path': request.url.path});
  }

  @override
  Future<void> requireScheduler(Request request) async {
    final jwt = await _verify(_bearer(request), _googleKeys);
    final problems = jwt.claims.validate(
      issuer: Uri.parse('https://accounts.google.com'),
      clientId: schedulerAudience,
    );
    final email = jwt.claims['email'];
    final verified = jwt.claims['email_verified'] == true;
    if (problems.isNotEmpty || email != schedulerEmail || !verified) throw ApiError.unauthorized;
  }

  static String _bearer(Request r) {
    final h = r.headers['authorization'] ?? '';
    if (!h.startsWith('Bearer ')) throw ApiError.unauthorized;
    return h.substring(7).trim();
  }

  static Future<JsonWebToken> _verify(String token, JsonWebKeyStore keys) async {
    try {
      return await JsonWebToken.decodeAndVerify(token, keys);
    } catch (_) {
      throw ApiError.unauthorized;
    }
  }
}

/// Solo para tests y desarrollo local: el uid llega en `X-Test-User`.
class FakeAuthenticator implements Authenticator {
  @override
  Future<String> userId(Request request,
      {bool requireVerified = true, Sensitivity sensitivity = Sensitivity.normal}) async {
    final uid = request.headers['x-test-user'];
    if (uid == null || uid.isEmpty) throw ApiError.unauthorized;
    // Simulación para tests: x-test-revoked y x-test-login-age (segundos).
    final now = DateTime.utc(2026);
    final age = int.tryParse(request.headers['x-test-login-age'] ?? '') ?? 0;
    Revocation.check(
      account: AccountState(
        validSince: request.headers['x-test-revoked'] == 'yes' ? now.add(const Duration(seconds: 1)) : null,
      ),
      issuedAt: now,
      authTime: now.subtract(Duration(seconds: age)),
      sensitivity: sensitivity,
      now: now,
    );
    return uid;
  }

  @override
  Future<void> requireScheduler(Request request) async {
    if (request.headers['x-test-scheduler'] != 'yes') throw ApiError.unauthorized;
  }
}

/// Pruebas de carga en qa: con la cabecera `x-load-test` igual al secreto,
/// acepta `x-test-user` (con prefijo `load_`) sin token. Cualquier otra
/// petición pasa al autenticador real. El servidor se niega a crearlo en prod.
class LoadTestAuthenticator implements Authenticator {
  final Authenticator real;
  final String secret;

  LoadTestAuthenticator(this.real, this.secret, {required String environment}) {
    if (environment == 'prod' || environment.isEmpty) {
      throw StateError('LOAD_TEST_SECRET no se permite en producción (ENVIRONMENT=$environment)');
    }
    if (secret.length < 24) throw StateError('LOAD_TEST_SECRET debe tener al menos 24 caracteres');
  }

  bool _isLoad(Request r) => r.headers['x-load-test'] == secret;

  @override
  Future<String> userId(Request request,
      {bool requireVerified = true, Sensitivity sensitivity = Sensitivity.normal}) async {
    if (!_isLoad(request)) {
      return real.userId(request, requireVerified: requireVerified, sensitivity: sensitivity);
    }
    final uid = request.headers['x-test-user'] ?? '';
    if (!RegExp(r'^load_[a-z0-9_]{1,40}$').hasMatch(uid)) throw ApiError.unauthorized;
    return uid;
  }

  @override
  Future<void> requireScheduler(Request request) => real.requireScheduler(request);
}
