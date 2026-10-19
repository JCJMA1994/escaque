import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'accounts.dart';
import 'auth.dart';
import 'errors.dart';
import 'game_service.dart';
import 'log.dart';
import 'purchases.dart';
import 'social.dart';
import 'rate_limiter.dart';

/// Rutas HTTP. Todas las de `/v1/games` requieren el token de Firebase del
/// jugador; las de `/v1/tasks` solo las llama Cloud Scheduler.
Handler buildHandler(GameService service, Authenticator auth,
    {RateLimiter? limiter, PurchaseService? purchases, SocialService? social}) {
  final limit = limiter ?? RateLimiter();
  // Rutas desconocidas también en JSON, como el resto de errores.
  final r = Router(
    notFoundHandler: (Request _) => _json(404, {'error': 'not_found', 'message': 'Ruta no encontrada.'}),
  );

  r.get('/healthz', (Request _) => Response.ok('ok'));

  r.post('/v1/games', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        final g = await service.create(
          uid,
          kind: _str(body, 'kind'),
          variant: body['variant'] as String? ?? 'spanish',
          seat: _int(body, 'seat'),
        );
        return {'id': g.id, 'code': g.code};
      }));

  r.post('/v1/games/join', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        final j = await service.join(uid, _str(body, 'code'));
        return {'id': j.id, 'seat': j.seat, 'kind': j.kind, 'variant': j.variant};
      }));

  r.post('/v1/games/<id>/moves', (Request req, String id) => _player(req, auth, limiter: limit, (uid, body) async {
        final m = await service.move(uid, id, ply: _int(body, 'ply'), move: _str(body, 'move'));
        if (m.status == 'finished') await _rate(social, id);
        return {
          'ply': m.ply,
          'status': m.status,
          if (m.reason != null) 'result': {'winner': m.winner, 'reason': m.reason},
        };
      }));

  r.post('/v1/games/<id>/rematch', (Request req, String id) => _player(req, auth, limiter: limit, (uid, body) async {
        final m = await service.rematch(uid, id);
        return {'id': m.id, 'seat': m.seat};
      }));

  r.post('/v1/games/<id>/emote', (Request req, String id) => _player(req, auth, limiter: limit, (uid, body) async {
        await service.emote(uid, id, _str(body, 'phrase'));
        return {'ok': true};
      }));

  r.post('/v1/games/<id>/decline', (Request req, String id) => _player(req, auth, limiter: limit, (uid, body) async {
        await service.declineChallenge(uid, id);
        return {'ok': true};
      }));

  r.post('/v1/games/<id>/resign', (Request req, String id) => _player(req, auth, limiter: limit, (uid, body) async {
        await service.resign(uid, id);
        await _rate(social, id);
        return {'ok': true};
      }));

  r.post('/v1/games/<id>/draw', (Request req, String id) => _player(req, auth, limiter: limit, (uid, body) async {
        await service.draw(uid, id, _str(body, 'action'));
        await _rate(social, id);
        return {'ok': true};
      }));

  // Cuenta: se permiten con el correo aún sin verificar (se elige el nombre
  // de usuario antes de verificar, y borrar la cuenta siempre debe poder hacerse).
  r.post('/v1/usernames/check', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        final c = await service.checkUsername(uid, _str(body, 'username'));
        return {'available': c.available, 'username': c.username, if (c.reason != null) 'reason': c.reason};
      }, requireVerified: false));

  r.post('/v1/me/username', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        final name = await service.setUsername(uid, _str(body, 'username'));
        await social?.rename(uid, name);
        return {'username': name};
      }, requireVerified: false, sensitivity: Sensitivity.checkRevoked));

  r.post('/v1/purchases/verify', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        final p = purchases ?? (throw const ApiError(503, 'purchases_unavailable', 'Las compras no están disponibles ahora.'));
        await p.verify(uid, _str(body, 'productId'), _str(body, 'token'));
        return {'adFree': true};
      }, requireVerified: false));

  // Notificaciones de Google Play (Pub/Sub, envío push con el token OIDC de la
  // cuenta de Scheduler): reembolsos y anulaciones.
  r.post('/v1/tasks/play-rtdn', (Request req) => _guard(() async {
        await auth.requireScheduler(req);
        final p = purchases;
        if (p != null) await p.handleNotification(await _body(req));
        return _json(200, {'ok': true});
      }));

  // ---- Amistades, retos y clasificaciones ----------------------------------
  SocialService soc() => social ?? (throw const ApiError(503, 'social_unavailable', 'No disponible ahora.'));

  r.post('/v1/friends/request', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        return {'status': await soc().request(uid, _str(body, 'username'))};
      }));
  r.post('/v1/friends/respond', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        await soc().respond(uid, _str(body, 'uid'), accept: body['accept'] == true);
        return {'ok': true};
      }));
  r.post('/v1/friends/remove', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        await soc().remove(uid, _str(body, 'uid'));
        return {'ok': true};
      }));
  r.post('/v1/friends/block', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        await soc().block(uid, _str(body, 'uid'));
        return {'ok': true};
      }));
  r.post('/v1/friends/unblock', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        await soc().unblock(uid, _str(body, 'uid'));
        return {'ok': true};
      }));
  r.post('/v1/friends/challenge', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        final c = await soc().challenge(uid, _str(body, 'uid'),
            kind: _str(body, 'kind'),
            variant: body['variant'] as String? ?? '',
            seat: _int(body, 'seat'),
            rated: body['rated'] == true);
        return {'id': c.id, 'seat': c.seat};
      }));
  r.post('/v1/tasks/leaderboards', (Request req) => _guard(() async {
        await auth.requireScheduler(req);
        await soc().updateLeaderboards();
        return _json(200, {'ok': true});
      }));

  r.post('/v1/me/delete', (Request req) => _player(req, auth, limiter: limit, (uid, body) async {
        final d = await service.deleteAccount(uid);
        await social?.sweepRatings();
        return {'resigned': d.resigned, 'cancelled': d.cancelled};
      }, requireVerified: false, sensitivity: Sensitivity.recentLogin));

  r.post('/v1/tasks/deadlines', (Request req) => _guard(() async {
        await auth.requireScheduler(req);
        final n = await service.processDeadlines();
        await social?.sweepRatings();
        return _json(200, {'reminded': n.reminded, 'expired': n.expired, 'cancelled': n.cancelled});
      }));

  return const Pipeline().addMiddleware(logRequests()).addHandler(r.call);
}

typedef _Action = Future<Map<String, Object?>> Function(String uid, Map<String, Object?> body);

Future<Response> _player(Request req, Authenticator auth, _Action action,
        {bool requireVerified = true, RateLimiter? limiter, Sensitivity sensitivity = Sensitivity.normal}) =>
    _guard(() async {
      final uid = await auth.userId(req, requireVerified: requireVerified, sensitivity: sensitivity);
      if (limiter != null && !limiter.allow(uid)) {
        throw const ApiError(429, 'rate_limited', 'Demasiadas peticiones seguidas. Espera unos segundos.');
      }
      return _json(200, await action(uid, await _body(req)));
    });

/// Cuerpo JSON (objeto) de la petición, como mucho 8 KB.
Future<Map<String, Object?>> _body(Request req) async {
  final raw = await req.readAsString();
  if (raw.length > 8 * 1024) throw ApiError.badRequest('Petición demasiado grande.');
  Object? decoded;
  try {
    decoded = raw.isEmpty ? <String, Object?>{} : jsonDecode(raw);
  } on FormatException {
    throw ApiError.badRequest('JSON no válido.');
  }
  if (decoded is! Map<String, Object?>) throw ApiError.badRequest('Se esperaba un objeto JSON.');
  return decoded;
}

Future<Response> _guard(Future<Response> Function() body) async {
  try {
    return await body();
  } on ApiError catch (e) {
    return _json(e.status, e.toJson());
  } catch (e, st) {
    Log.error('Error interno', e, st);
    return _json(500, {'error': 'internal', 'message': 'Error del servidor. Inténtalo de nuevo.'});
  }
}

Response _json(int status, Map<String, Object?> body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _str(Map<String, Object?> b, String key) {
  final v = b[key];
  if (v is! String) throw ApiError.badRequest('Falta «$key».');
  return v;
}

int _int(Map<String, Object?> b, String key) {
  final v = b[key];
  if (v is! int) throw ApiError.badRequest('Falta «$key».');
  return v;
}

/// Valora la partida si tocaba (mejor esfuerzo: el barrido lo recoge si falla).
Future<void> _rate(SocialService? social, String id) async {
  if (social == null) return;
  try {
    await social.rateGame(id);
  } catch (e, st) {
    Log.error('Valoración no aplicada (la recogerá el barrido)', e, st, {'gameId': id});
  }
}
