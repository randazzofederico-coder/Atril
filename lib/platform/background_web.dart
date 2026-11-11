import 'dart:async';

Future<R> runHeavy<R>(FutureOr<R> Function() computation) async {
  // Un frame para que la UI pinte el estado "procesando..." antes de bloquear.
  await Future<void>.delayed(const Duration(milliseconds: 16));
  return await computation();
}

Future<R> runHeavyWithProgress<R>(
  R Function(void Function(double progress) report) computation, {
  void Function(double progress)? onProgress,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 16));
  return computation((v) => onProgress?.call(v));
}
