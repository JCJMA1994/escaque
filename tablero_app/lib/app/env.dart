/// Entorno de la compilación (`--dart-define-from-file=config/<entorno>.json`).
/// dev y qa usan sus propios proyectos de Firebase, servidor e IDs de prueba
/// de AdMob; solo prod usa anuncios reales.
abstract final class AppEnv {
  static const name = String.fromEnvironment('ENV', defaultValue: 'dev');
  static bool get isProd => name == 'prod';

  /// Capturas para Play Store (`--dart-define=SCREENSHOTS=true`): sin anuncios
  /// de prueba ni franja de entorno.
  static const screenshots = bool.fromEnvironment('SCREENSHOTS');

  /// Web de este entorno: los enlaces de invitación son `<web>/j/CÓDIGO`.
  static const inviteBaseUrl =
      String.fromEnvironment('INVITE_BASE_URL', defaultValue: 'https://escaque.system-failed-tech.com');

  static String inviteLink(String code) => '$inviteBaseUrl/j/$code';
}
