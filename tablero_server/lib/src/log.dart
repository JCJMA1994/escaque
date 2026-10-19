import 'dart:convert';
import 'dart:io';

/// Registro estructurado para Cloud Logging. Las líneas con severidad ERROR y
/// el tipo `ReportedErrorEvent` aparecen agrupadas en Cloud Error Reporting,
/// con alertas por correo cuando surge un error nuevo.
abstract final class Log {
  static const _service = 'tablero-api';

  static void info(String message, [Map<String, Object?> fields = const {}]) =>
      _write('INFO', message, fields);

  static void warning(String message, [Map<String, Object?> fields = const {}]) =>
      _write('WARNING', message, fields);

  static void error(String message, Object error, StackTrace stack, [Map<String, Object?> fields = const {}]) =>
      _write('ERROR', '$message: $error\n$stack', {
        '@type': 'type.googleapis.com/google.devtools.clouderrorreporting.v1beta1.ReportedErrorEvent',
        'serviceContext': {'service': _service, 'version': Platform.environment['K_REVISION'] ?? 'local'},
        ...fields,
      });

  static void _write(String severity, String message, Map<String, Object?> fields) {
    stdout.writeln(jsonEncode({'severity': severity, 'message': message, ...fields}));
  }
}
