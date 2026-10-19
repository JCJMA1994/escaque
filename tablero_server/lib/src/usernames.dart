/// Nombres de usuario: únicos, sin distinguir mayúsculas, de 3 a 20
/// caracteres; letras sin tilde, números y guion bajo; empiezan por letra.
abstract final class Usernames {
  static final _pattern = RegExp(r'^[a-z][a-z0-9_]{2,19}$');

  /// Nombres que podrían hacerse pasar por la app o el equipo.
  static const reserved = {
    'admin', 'administrador', 'administrator', 'root', 'sistema', 'system', 'soporte', 'support',
    'ayuda', 'help', 'moderador', 'moderator', 'mod', 'staff', 'equipo', 'oficial', 'official',
    'tablero', 'tableroapp', 'tablero_app', 'ia', 'ai', 'bot', 'rival', 'jugador', 'player',
    'anonimo', 'anonymous', 'null', 'undefined', 'me', 'yo', 'tu', 'cuenta_eliminada',
  };

  /// Filtro básico de insultos (subcadenas). Ampliable sin cambiar la app.
  static const _blocked = [
    'puta', 'puto', 'mierda', 'pendej', 'cabron', 'concha', 'verga', 'culero', 'marica',
    'nazi', 'hitler', 'fuck', 'shit', 'bitch', 'nigg', 'fag',
  ];

  /// Quita espacios y una @ inicial y pasa a minúsculas.
  static String normalize(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.startsWith('@')) s = s.substring(1);
    return s;
  }

  /// `null` si es válido; si no, el motivo en español.
  static String? problem(String username) {
    if (username.length < 3 || username.length > 20) return 'Usa de 3 a 20 caracteres.';
    if (!_pattern.hasMatch(username)) {
      return 'Solo letras sin tilde, números y guion bajo (_), empezando por una letra.';
    }
    if (username.contains('__')) return 'No uses dos guiones bajos seguidos.';
    if (reserved.contains(username)) return 'Ese nombre está reservado.';
    if (_blocked.any(username.contains)) return 'Elige otro nombre.';
    return null;
  }
}
