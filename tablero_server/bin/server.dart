import 'dart:io';

import 'package:googleapis/androidpublisher/v3.dart' as ap;
import 'package:googleapis/fcm/v1.dart' as fcm;
import 'package:googleapis/firestore/v1.dart' as fs;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:tablero_server/tablero_server.dart';

/// Variables de entorno (Cloud Run):
///   PROJECT_ID, PROJECT_NUMBER — proyecto de Firebase
///   APP_CHECK = enforce | monitor | off (por defecto monitor)
///   SCHEDULER_SA — email de la cuenta de servicio de Cloud Scheduler
///   SERVICE_URL — URL del servicio (audiencia del token de Scheduler)
///   MOVE_TIME_HOURS — plazo por jugada (por defecto 72)
///   PORT — lo fija Cloud Run
Future<void> main() async {
  final env = Platform.environment;
  String need(String k) => env[k] ?? (throw StateError('Falta la variable de entorno $k'));

  final projectId = need('PROJECT_ID');
  final client = await clientViaApplicationDefaultCredentials(
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  );
  final store = FirestoreStore(fs.FirestoreApi(client), projectId);
  final notifier = FcmNotifier(api: fcm.FirebaseCloudMessagingApi(client), store: store, projectId: projectId);
  final service = GameService(
    store: store,
    notifier: notifier,
    moveTime: Duration(hours: int.tryParse(env['MOVE_TIME_HOURS'] ?? '') ?? 72),
  );
  final google = GoogleAuthenticator(
    projectId: projectId,
    projectNumber: need('PROJECT_NUMBER'),
    appCheck: AppCheckMode.values.byName(env['APP_CHECK'] ?? 'monitor'),
    schedulerEmail: need('SCHEDULER_SA'),
    schedulerAudience: need('SERVICE_URL'),
  )..accounts = IdentityToolkitLookup(client, projectId);
  // Pruebas de carga: solo en dev/qa y con un secreto largo.
  final loadSecret = env['LOAD_TEST_SECRET'] ?? '';
  final Authenticator auth = loadSecret.isEmpty
      ? google
      : LoadTestAuthenticator(google, loadSecret, environment: env['ENVIRONMENT'] ?? '');
  if (loadSecret.isNotEmpty) Log.warning('Modo de pruebas de carga activo', {'environment': env['ENVIRONMENT']});

  // Compras: solo si se configuró el paquete de Play (prod; en qa, el de qa).
  final playPackage = env['PLAY_PACKAGE'] ?? '';
  final purchases = PurchaseService(
    store: store,
    play: playPackage.isEmpty ? null : GooglePlayStore(ap.AndroidPublisherApi(await _playClient()), playPackage),
    productId: env['PRODUCT_REMOVE_ADS'] ?? 'remove_ads',
  );

  final port = int.parse(env['PORT'] ?? '8080');
  final social = SocialService(store: store, notifier: notifier, games: service);
  final server = await shelf_io.serve(
      buildHandler(service, auth, purchases: purchases, social: social), InternetAddress.anyIPv4, port);
  stdout.writeln('tablero_server escuchando en :${server.port}');
}

/// La Play Developer API exige el ámbito androidpublisher: en Cloud Run se pide
/// al servidor de metadatos; en local, a las credenciales por defecto.
Future<http.Client> _playClient() async {
  const scope = 'https://www.googleapis.com/auth/androidpublisher';
  if (Platform.environment.containsKey('K_SERVICE')) return ScopedMetadataClient([scope]);
  return clientViaApplicationDefaultCredentials(scopes: [scope]);
}
