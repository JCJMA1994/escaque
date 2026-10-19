import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../online/api_client.dart';
import '../online/online_repository.dart';
import '../online/push_service.dart';
import '../l10n/l10n.dart';

/// Error de cuenta con el mensaje listo para mostrar.
class AuthFailure implements Exception {
  final String message;

  /// Firebase pide un inicio de sesión reciente (borrar cuenta).
  final bool needsRecentLogin;
  const AuthFailure(this.message, {this.needsRecentLogin = false});
  @override
  String toString() => message;
}

/// Estado de la cuenta tal como lo necesita la interfaz.
enum AccountStatus {
  /// Sin cuenta: modo offline.
  none,

  /// Cargando el perfil tras iniciar sesión.
  loading,

  /// Con sesión pero sin nombre de usuario: hay que elegirlo.
  needsUsername,

  /// Cuenta con correo y contraseña aún sin verificar: no puede jugar online.
  unverified,

  /// Lista para jugar online.
  ready,
}

/// Perfil en `users/{uid}`. El nombre de usuario lo escribe solo el servidor.
class UserProfile {
  final String? username;
  final DateTime? usernameChangedAt;
  final bool notify;
  final bool reminders;

  /// Compró «quitar anuncios» (lo escribe el servidor).
  final bool adFree;

  /// Acepta solicitudes de amistad.
  final bool friendRequests;
  const UserProfile(
      {this.username,
      this.usernameChangedAt,
      this.notify = true,
      this.reminders = true,
      this.adFree = false,
      this.friendRequests = true});

  factory UserProfile.fromMap(Map<String, dynamic>? d) => UserProfile(
        username: d?['username'] as String?,
        usernameChangedAt: (d?['usernameChangedAt'] as Timestamp?)?.toDate(),
        notify: d?['notify'] as bool? ?? true,
        reminders: d?['reminders'] as bool? ?? true,
        adFree: d?['adFree'] as bool? ?? false,
        friendRequests: d?['friendRequests'] as bool? ?? true,
      );

  /// `@nombre` para mostrar.
  String? get handle => username == null ? null : '@$username';
}

bool _needsVerification(User u) {
  final usesPassword = u.providerData.any((p) => p.providerId == 'password');
  final usesGoogle = u.providerData.any((p) => p.providerId == 'google.com');
  return usesPassword && !usesGoogle && !u.emailVerified;
}

AccountStatus statusFor(User? u, UserProfile? profile, {bool profileLoading = false}) {
  if (u == null || u.isAnonymous) return AccountStatus.none;
  if (profileLoading) return AccountStatus.loading;
  if (profile?.username == null) return AccountStatus.needsUsername;
  if (_needsVerification(u)) return AccountStatus.unverified;
  return AccountStatus.ready;
}

/// Resultado de comprobar un nombre de usuario en el servidor.
class UsernameCheck {
  final bool available;
  final String username;
  final String? reason;
  const UsernameCheck(this.available, this.username, this.reason);
}

/// Inicio de sesión con Firebase Auth. Análisis y decisiones: tool/accounts.md.
class AuthService {
  final Ref _ref;
  AuthService(this._ref);

  FirebaseAuth get _auth => FirebaseAuth.instance;
  // google_sign_in 7: instancia única que se inicializa una sola vez. En
  // Android usa Credential Manager; con google-services.json no necesita
  // identificadores en Dart.
  static Future<void>? _googleReady;
  GoogleSignIn get _google => GoogleSignIn.instance;
  Future<void> _ensureGoogle() => _googleReady ??= _google.initialize();

  /// Cuenta de Google elegida por la persona; [AuthFailure] si cancela.
  Future<AuthCredential> _googleCredential(String cancelled) async {
    await _ensureGoogle();
    try {
      final account = await _google.authenticate();
      return GoogleAuthProvider.credential(idToken: account.authentication.idToken);
    } on GoogleSignInException catch (e) {
      throw AuthFailure(switch (e.code) {
        GoogleSignInExceptionCode.canceled => cancelled,
        GoogleSignInExceptionCode.clientConfigurationError =>
          tr('El acceso con Google no está bien configurado (huella SHA o google-services.json).'),
        _ => tr('No se pudo entrar con Google. Inténtalo de nuevo.'),
      });
    }
  }

  static const minPasswordLength = 8;

  User? get user => _auth.currentUser;

  Future<void> signInWithGoogle() => _guard(() async {
        final cred = await _googleCredential(tr('Inicio de sesión cancelado.'));
        await _replaceAnonymous(() => _auth.signInWithCredential(cred));
        await _afterSignIn();
      });

  Future<void> register({required String email, required String password}) => _guard(() async {
        if (password.length < minPasswordLength) {
          throw AuthFailure(tr('La contraseña necesita al menos {minPasswordLength} caracteres.', {'minPasswordLength': minPasswordLength}));
        }
        final cred = await _replaceAnonymous(
            () => _auth.createUserWithEmailAndPassword(email: email.trim(), password: password));
        await cred.user!.sendEmailVerification();
        await cred.user!.reload();
        await _afterSignIn();
      });

  Future<void> signInWithEmail({required String email, required String password}) => _guard(() async {
        await _replaceAnonymous(() => _auth.signInWithEmailAndPassword(email: email.trim(), password: password));
        await _afterSignIn();
      });

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> resendVerification() => _guard(() async {
        await _auth.currentUser?.sendEmailVerification();
      });

  /// Comprueba si el correo ya está verificado. Si lo está, fuerza un ID
  /// token nuevo: el guardado en caché seguiría diciendo que no hasta 1 hora.
  Future<bool> refreshVerification() => _guard(() async {
        final u = _auth.currentUser;
        if (u == null) return false;
        await u.reload();
        final fresh = _auth.currentUser!;
        if (fresh.emailVerified) await fresh.getIdToken(true);
        return fresh.emailVerified;
      });

  /// Comprueba si un nombre de usuario está libre (y es válido).
  Future<UsernameCheck> checkUsername(String raw) => _guard(() async {
        final r = await _ref.read(onlineRepositoryProvider).api.post('/v1/usernames/check', {'username': raw});
        final reason = r['reason'] as String?;
        return UsernameCheck(r['available'] as bool, r['username'] as String, reason == null ? null : tr(reason));
      });

  /// Elige o cambia el nombre de usuario. Lo valida y reserva el servidor.
  Future<String> setUsername(String raw) => _guard(() async {
        final r = await _ref.read(onlineRepositoryProvider).api.post('/v1/me/username', {'username': raw});
        final username = r['username'] as String;
        // Copia de cortesía en Firebase Auth; la fuente de verdad es users/{uid}.
        try {
          await _auth.currentUser?.updateDisplayName(username);
        } catch (_) {}
        return username;
      });

  /// Siguiente pantalla tras iniciar sesión: elegir nombre de usuario,
  /// verificar el correo o volver a [next]. Lee el perfil directamente para
  /// no depender de que el stream ya se haya actualizado.
  Future<String> nextStep(String next) async {
    final u = _auth.currentUser;
    if (u == null) return '/account?next=${Uri.encodeComponent(next)}';
    final snap = await FirebaseFirestore.instance.doc('users/${u.uid}').get();
    final profile = UserProfile.fromMap(snap.data());
    final encoded = Uri.encodeComponent(next);
    return switch (statusFor(u, profile)) {
      AccountStatus.needsUsername => '/account/username?next=$encoded',
      AccountStatus.unverified => '/account/verify?next=$encoded',
      _ => next,
    };
  }

  /// Cierra sesión. Antes borra el token de avisos de este dispositivo para
  /// no recibir notificaciones de una cuenta que ya no está.
  Future<void> signOut() async {
    try {
      await _ref.read(pushServiceProvider).unregisterThisDevice();
    } catch (_) {}
    try {
      await _ensureGoogle();
      await _google.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  /// Borra la cuenta: primero los datos del servidor (abandona partidas,
  /// retira el nombre, borra avisos), luego el usuario de Firebase Auth.
  /// Si Firebase pide un inicio de sesión reciente, lanza [AuthFailure] con
  /// [AuthFailure.needsRecentLogin]: hay que llamar a [reauthenticate] y repetir.
  Future<void> deleteAccount() => _guard(() async {
        final u = _auth.currentUser;
        if (u == null) return;
        if (ApiClient.configured && !u.isAnonymous) {
          // El servidor también libera el nombre de usuario.
          await _ref.read(onlineRepositoryProvider).api.post('/v1/me/delete');
        }
        try {
          await _ref.read(pushServiceProvider).unregisterThisDevice();
        } catch (_) {}
        await u.delete();
        try {
          await _ensureGoogle();
          await _google.signOut();
        } catch (_) {}
      });

  /// Vuelve a confirmar la identidad (con la contraseña o con Google).
  Future<void> reauthenticate({String? password}) => _guard(() async {
        final u = _auth.currentUser!;
        final AuthCredential cred;
        if (password != null) {
          cred = EmailAuthProvider.credential(email: u.email!, password: password);
        } else {
          cred = await _googleCredential(tr('Confirmación cancelada.'));
        }
        await u.reauthenticateWithCredential(cred);
        // Token nuevo con auth_time actual: el servidor lo exige para borrar la cuenta.
        await u.getIdToken(true);
      });

  bool get usesPassword => user?.providerData.any((p) => p.providerId == 'password') ?? false;

  /// Si quedara una sesión anónima de versiones anteriores, se cierra antes.
  Future<UserCredential> _replaceAnonymous(Future<UserCredential> Function() signIn) async {
    if (_auth.currentUser?.isAnonymous ?? false) await _auth.signOut();
    return signIn();
  }

  Future<void> _afterSignIn() async {
    try {
      final push = _ref.read(pushServiceProvider);
      if (await push.hasPermission()) await push.registerToken();
    } catch (_) {}
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(messageFor(e.code), needsRecentLogin: e.code == 'requires-recent-login');
    } on OnlineException catch (e) {
      // El servidor pide confirmar la identidad (borrar la cuenta): mismo
      // camino que el «requires-recent-login» de Firebase.
      if (e.code == 'recent_login_required') {
        throw AuthFailure(e.message, needsRecentLogin: true);
      }
      // Sesión revocada (cerró sesión en todos sus dispositivos o cambió la
      // contraseña en otro): se cierra también aquí.
      if (e.code == 'token_revoked') {
        try {
          await _auth.signOut();
        } catch (_) {}
      }
      throw AuthFailure(e.message);
    }
  }

  /// Mensajes en español. Con la protección contra enumeración de correos,
  /// «no existe» y «contraseña incorrecta» llegan como `invalid-credential`.
  static String messageFor(String code) => switch (code) {
        'invalid-email' => tr('Ese correo no es válido.'),
        'email-already-in-use' => tr('Ya hay una cuenta con ese correo. Inicia sesión o entra con Google.'),
        'weak-password' => tr('Esa contraseña es demasiado fácil. Usa al menos 8 caracteres.'),
        'invalid-credential' || 'wrong-password' || 'user-not-found' => tr('Correo o contraseña incorrectos.'),
        'user-disabled' => tr('Esta cuenta está deshabilitada.'),
        'too-many-requests' => tr('Demasiados intentos. Espera unos minutos y vuelve a probar.'),
        'network-request-failed' => tr('Sin conexión. Revisa tu internet.'),
        'account-exists-with-different-credential' =>
          tr('Ese correo ya usa otro método de acceso. Entra con el que usaste al registrarte.'),
        'requires-recent-login' => tr('Por seguridad, confirma tu identidad para continuar.'),
        'operation-not-allowed' => tr('Ese método de acceso no está activado.'),
        _ => tr('No se pudo completar. Inténtalo de nuevo.'),
      };
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref));

/// Usuario actual; cambia al iniciar o cerrar sesión, verificar el correo o
/// cambiar el nombre.
final authUserProvider = StreamProvider<User?>((ref) {
  // Sin Firebase configurado no hay cuentas: todo es offline.
  if (!ref.watch(firebaseReadyProvider)) return Stream.value(null);
  return FirebaseAuth.instance.userChanges();
});

/// Perfil en tiempo real (nombre de usuario y preferencias).
final profileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null || user.isAnonymous) return Stream.value(null);
  return FirebaseFirestore.instance
      .doc('users/${user.uid}')
      .snapshots()
      .map((d) => UserProfile.fromMap(d.data()));
});

final accountStatusProvider = Provider<AccountStatus>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  final profile = ref.watch(profileProvider);
  return statusFor(user, profile.valueOrNull, profileLoading: profile.isLoading && !profile.hasValue);
});

/// `@nombre` de la cuenta actual, si lo tiene.
final usernameProvider = Provider<String?>((ref) => ref.watch(profileProvider).valueOrNull?.username);
