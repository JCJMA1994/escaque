/// Límite de peticiones por usuario (cubo de fichas en memoria). Cada
/// instancia de Cloud Run lleva su cuenta: con varias instancias el límite
/// real es algo mayor, suficiente para frenar abusos y bucles de una app rota.
class RateLimiter {
  final int capacity;
  final Duration refill;
  final DateTime Function() now;
  final _buckets = <String, (double tokens, DateTime at)>{};
  static const _maxKeys = 50000;

  /// [capacity] peticiones seguidas; se recupera una cada [refill].
  RateLimiter({this.capacity = 60, this.refill = const Duration(seconds: 1), DateTime Function()? now})
      : now = now ?? DateTime.now;

  bool allow(String key) {
    final t = now();
    if (_buckets.length > _maxKeys) _buckets.clear();
    final (tokens, at) = _buckets[key] ?? (capacity.toDouble(), t);
    final refilled = (tokens + t.difference(at).inMicroseconds / refill.inMicroseconds).clamp(0, capacity).toDouble();
    if (refilled < 1) {
      _buckets[key] = (refilled, t);
      return false;
    }
    _buckets[key] = (refilled - 1, t);
    return true;
  }
}
