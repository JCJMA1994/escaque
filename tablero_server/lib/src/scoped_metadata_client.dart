import 'dart:convert';

import 'package:http/http.dart' as http;

/// Cliente HTTP con un token de la cuenta de servicio de Cloud Run para
/// ámbitos concretos. `googleapis_auth` pide el token al servidor de
/// metadatos sin ámbitos (queda `cloud-platform`), y la Google Play Developer
/// API exige `androidpublisher`; Cloud Run acepta `?scopes=` en esa petición.
class ScopedMetadataClient extends http.BaseClient {
  final List<String> scopes;
  final http.Client _inner;
  String? _token;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  ScopedMetadataClient(this.scopes, {http.Client? inner}) : _inner = inner ?? http.Client();

  static final _base = Uri.parse('http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token');

  Future<String> token() async {
    final t = _token;
    if (t != null && DateTime.now().isBefore(_expires)) return t;
    final res = await _inner.get(_base.replace(queryParameters: {'scopes': scopes.join(',')}),
        headers: {'Metadata-Flavor': 'Google'});
    if (res.statusCode != 200) throw StateError('Servidor de metadatos: ${res.statusCode}');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    _token = j['access_token'] as String;
    _expires = DateTime.now().add(Duration(seconds: ((j['expires_in'] as num?) ?? 300).toInt() - 60));
    return _token!;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['authorization'] = 'Bearer ${await token()}';
    return _inner.send(request);
  }
}
