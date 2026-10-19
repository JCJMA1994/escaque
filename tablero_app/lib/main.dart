import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account/auth_service.dart';
import 'ads/ads_service.dart';
import 'app/app_flags.dart';
import 'app/env.dart';
import 'app/metrics.dart';
import 'app/play_games.dart';
import 'purchases/purchases.dart';
import 'app/remote_flags.dart';
import 'app/store_prompts.dart';
import 'app/telemetry.dart';
import 'app/router.dart';
import 'app/settings.dart';
import 'app/sounds.dart';
import 'app/theme.dart';
import 'match/match_controller.dart';
import 'online/online_repository.dart';
import 'online/push_service.dart';
import 'ui/piece_art.dart';
import 'l10n/l10n.dart';

/// Para mostrar avisos desde fuera de un Scaffold (notificaciones en primer plano).
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppFlags.load();
  // Firebase es opcional: sin google-services.json la app funciona sin online.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (_) {}
  // Informes de errores (Ajustes → Privacidad permite apagarlos).
  final prefs = await SharedPreferences.getInstance();
  await Telemetry.init(firebaseReady: firebaseReady, enabled: prefs.getBool('crashReports') ?? true);
  if (firebaseReady) {
    // Aparte: si App Check falla, el resto de Firebase sigue funcionando (el
    // servidor decide según su modo). Play Integrity en la versión de tienda;
    // token de depuración en desarrollo (se registra en Firebase → App Check).
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kReleaseMode ? const AndroidPlayIntegrityProvider() : const AndroidDebugProvider(),
      );
    } catch (_) {}
  }
  runApp(ProviderScope(
    overrides: [firebaseReadyProvider.overrideWith((ref) => firebaseReady)],
    child: const TableroApp(),
  ));
}

/// Tareas de arranque que no deben retrasar el primer fotograma.
class _Startup extends ConsumerStatefulWidget {
  final Widget child;
  const _Startup({required this.child});

  @override
  ConsumerState<_Startup> createState() => _StartupState();
}

class _StartupState extends ConsumerState<_Startup> {
  bool _orientationSet = false;

  /// Anuncios (con UMP) y estadísticas (desactivadas hasta que se acepten).
  Future<void> _initAdsAndMetrics() async {
    await ref.read(adsServiceProvider).init();
    await Metrics.init(firebaseReady: ref.read(firebaseReadyProvider));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Teléfonos: solo vertical (el tablero ocupa el ancho). Tablets y plegables
    // abiertos: cualquier orientación, con el diseño a dos columnas.
    if (_orientationSet) return;
    _orientationSet = true;
    final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    SystemChrome.setPreferredOrientations(tablet ? DeviceOrientation.values : [DeviceOrientation.portraitUp]);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PieceArt.preload();
      ref.read(adFreeProvider); // compras: estado guardado, producto y pendientes
      PlayGames.init(); // inicio de sesión silencioso (si hay IDs configurados)
      // Idioma actual en el perfil (también tras un cambio de idioma, que recrea este widget).
      if (ref.read(firebaseReadyProvider) && ref.read(authUserProvider).valueOrNull != null) {
        ref.read(pushServiceProvider).saveLocale(L10n.lang);
      }
      RemoteFlagsService.init(firebaseReady: ref.read(firebaseReadyProvider));
      Sounds.preload();
      _initAdsAndMetrics();
      if (ref.read(firebaseReadyProvider)) _startPush();
    });
  }

  Future<void> _startPush() async {
    try {
      await ref.read(pushServiceProvider).start(
            onOpen: (gameId) => appRouter.push('/online/game/$gameId'),
            onFriends: () => appRouter.push('/friends'),
            onForeground: (m) {
              final gameId = m.data['gameId'];
              // Si ya estás en esa partida, el tablero se actualiza solo.
              final onGame = appRouter.routerDelegate.currentConfiguration.uri.path == '/game';
              if (onGame && gameId == ref.read(matchConfigProvider)?.onlineGameId) return;
              final title = m.notification?.title ?? tr('Partida online');
              messengerKey.currentState?.showSnackBar(SnackBar(
                content: Text(title),
                action: gameId is String
                    ? SnackBarAction(label: tr('Abrir'), onPressed: () => appRouter.push('/online/game/$gameId'))
                    : null,
              ));
            },
          );
    } catch (_) {
      // Sin notificaciones la app sigue funcionando.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Crashlytics: el uid (seudónimo) para agrupar errores de una misma cuenta.
    // «Sin anuncios» del perfil de la cuenta (y compras sin cuenta por ligar).
    ref.listen(profileProvider, (_, next) {
      final profile = next.valueOrNull;
      final uid = ref.read(authUserProvider).valueOrNull?.uid;
      if (profile != null && uid != null) ref.read(adFreeProvider.notifier).syncFromServer(uid, profile.adFree);
    });
    ref.listen(authUserProvider, (prev, next) {
      // Crashlytics no recibe el uid: los informes de errores no identifican a nadie.
      final uid = next.valueOrNull?.uid;
      // Al iniciar sesión (o al reconstruirse por un cambio de idioma), el
      // servidor aprende en qué idioma enviar los avisos.
      if (uid != null && uid != prev?.valueOrNull?.uid && ref.read(firebaseReadyProvider)) {
        ref.read(pushServiceProvider).saveLocale(L10n.lang);
      }
    });
    final app = ValueListenableBuilder<RemoteFlags>(
      valueListenable: RemoteFlagsService.flags,
      builder: (context, flags, child) => flags.updateRequired ? const _UpdateRequired() : child!,
      child: widget.child,
    );
    return _withEnvBanner(app);
  }

  Widget _withEnvBanner(Widget child) {
    if (AppEnv.isProd || AppEnv.screenshots) return child;
    // Fuera de producción, una franja indica el entorno: nadie confunde QA con la app real.
    return Banner(
      message: AppEnv.name.toUpperCase(),
      location: BannerLocation.topEnd,
      color: const Color(0xFFC08A1E),
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF16201C)),
      child: child,
    );
  }
}

/// Versión demasiado antigua para el servidor actual (Remote Config
/// `min_supported_build`): se bloquea hasta actualizar.
class _UpdateRequired extends StatefulWidget {
  const _UpdateRequired();

  @override
  State<_UpdateRequired> createState() => _UpdateRequiredState();
}

class _UpdateRequiredState extends State<_UpdateRequired> {
  bool _noUpdate = false;

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Actualiza Escaque'), style: TType.titleLg(c.ink)),
                  const SizedBox(height: 8),
                  Text(
                    _noUpdate
                        ? tr('No encontramos la actualización desde aquí. Ábrela en Google Play y actualiza.')
                        : tr('Esta versión ya no es compatible con el modo online. La actualización tarda menos de un minuto.'),
                    style: TType.body(c.inkMuted),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final ok = await StorePrompts.updateNow();
                        if (!ok && mounted) setState(() => _noUpdate = true);
                      },
                      child: Text(tr('Actualizar')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TableroApp extends ConsumerWidget {
  const TableroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final language = ref.watch(settingsProvider.select((s) => s.language));
    L10n.apply(language, WidgetsBinding.instance.platformDispatcher.locale);
    return MaterialApp.router(
      themeMode: themeMode,
      title: 'Escaque',
      locale: L10n.locale,
      supportedLocales: L10n.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: appRouter,
      scaffoldMessengerKey: messengerKey,
      // Al cambiar de idioma se reconstruye toda la interfaz (tr() no es un
      // InheritedWidget); la ruta actual se conserva.
      builder: (context, child) => KeyedSubtree(
        key: ValueKey(L10n.lang),
        child: _Startup(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
