import 'package:flutter/foundation.dart';

/// Registro de diagnóstico en memoria (últimas líneas), visible en
/// Ajustes → Acerca de → "Registro de diagnóstico" para copiarlo y enviarlo.
///
/// Captura todo lo que pasa por `debugPrint` (también en release) y las
/// marcas explícitas de [diag] con la hora y los ms desde la marca anterior.
class DiagLog {
  DiagLog._();

  static const _max = 600;
  static final List<String> _lines = <String>[];
  static final ValueNotifier<int> revision = ValueNotifier(0);
  static DateTime? _last;
  static bool _installed = false;

  /// Redirige `debugPrint` para que también quede en el registro.
  static void install() {
    if (_installed) return;
    _installed = true;
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      add(message ?? '');
      original(message, wrapWidth: wrapWidth);
    };
  }

  static void add(String message) {
    final now = DateTime.now();
    final delta = _last == null ? 0 : now.difference(_last!).inMilliseconds;
    _last = now;
    final t = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${(now.millisecond ~/ 10).toString().padLeft(2, '0')}';
    _lines.add('$t (+${delta}ms) $message');
    if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
    revision.value++;
  }

  static String get text => _lines.join('\n');

  static void clear() {
    _lines.clear();
    _last = null;
    revision.value++;
  }
}

/// Marca en el registro de diagnóstico (también sale por consola).
void diag(String message) => debugPrint('[diag] $message');
