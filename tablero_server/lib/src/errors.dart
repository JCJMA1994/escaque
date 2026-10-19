/// Error de la API con su código HTTP, un código estable para el cliente y un
/// mensaje en español listo para mostrar.
class ApiError implements Exception {
  final int status;
  final String code;
  final String message;
  final Map<String, Object?> extra;

  const ApiError(this.status, this.code, this.message, [this.extra = const {}]);

  static ApiError badRequest(String message) => ApiError(400, 'bad_request', message);
  static const unauthorized =
      ApiError(401, 'unauthorized', 'Tu sesión no es válida. Vuelve a abrir la app.');
  static const notFound = ApiError(404, 'not_found', 'Esa partida no existe.');
  static const notMember = ApiError(403, 'not_member', 'No juegas en esta partida.');

  Map<String, Object?> toJson() => {'error': code, 'message': message, ...extra};

  @override
  String toString() => 'ApiError($status, $code): $message';
}

/// Otro proceso cambió el documento entre la lectura y la escritura.
class ConflictException implements Exception {
  const ConflictException();
}
