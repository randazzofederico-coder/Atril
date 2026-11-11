import 'dart:async';

import 'background_io.dart' if (dart.library.js_interop) 'background_web.dart' as impl;

/// Ejecuta trabajo pesado (CPU) fuera del hilo de la UI cuando la plataforma
/// lo permite.
///
/// - Nativo: `Isolate.run` (el [computation] no puede capturar objetos que no
///   se puedan enviar entre isolates).
/// - Web: no hay isolates; se ejecuta en el mismo hilo, cediendo antes un
///   frame para que la UI llegue a mostrar el progreso.
Future<R> runHeavy<R>(FutureOr<R> Function() computation) => impl.runHeavy(computation);

/// Igual que [runHeavy], pero el trabajo puede informar progreso (0.0–1.0)
/// llamando a `report`; cada valor llega a [onProgress] en el hilo de la UI.
///
/// En nativo, si el isolate muere sin terminar (p. ej. sin memoria), el
/// future termina con error en lugar de quedar colgado.
Future<R> runHeavyWithProgress<R>(
  R Function(void Function(double progress) report) computation, {
  void Function(double progress)? onProgress,
}) =>
    impl.runHeavyWithProgress(computation, onProgress: onProgress);
