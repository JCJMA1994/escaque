/// IDs de AdMob. Por defecto, los IDs de prueba oficiales de Google.
/// En producción se pasan al compilar:
///
///   flutter build appbundle \
///     --dart-define=ADMOB_BANNER=ca-app-pub-XXX/YYY \
///     --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-XXX/YYY \
///     --dart-define=ADMOB_REWARDED=ca-app-pub-XXX/YYY
abstract final class AdIds {
  static const banner = String.fromEnvironment(
    'ADMOB_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/9214589741',
  );
  static const interstitial = String.fromEnvironment(
    'ADMOB_INTERSTITIAL',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
  static const rewarded = String.fromEnvironment(
    'ADMOB_REWARDED',
    defaultValue: 'ca-app-pub-3940256099942544/5224354917',
  );

  static bool get usingTestIds => banner.startsWith('ca-app-pub-3940256099942544');
}
