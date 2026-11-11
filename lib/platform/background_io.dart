import 'dart:async';
import 'dart:isolate';

Future<R> runHeavy<R>(FutureOr<R> Function() computation) => Isolate.run(computation);

Future<R> runHeavyWithProgress<R>(
  R Function(void Function(double progress) report) computation, {
  void Function(double progress)? onProgress,
}) async {
  final port = ReceivePort();
  final completer = Completer<R>();

  port.listen((message) {
    if (completer.isCompleted) return;
    if (message is double) {
      onProgress?.call(message);
    } else if (message is _Done) {
      completer.complete(message.value as R);
      port.close();
    } else if (message is _Failed) {
      completer.completeError(Exception(message.error));
      port.close();
    } else if (message is List) {
      // [error, stack] de onError
      completer.completeError(Exception(message.first));
      port.close();
    } else if (message == null) {
      // onExit sin resultado
      completer.completeError(Exception('El procesamiento terminó inesperadamente.'));
      port.close();
    }
  });

  try {
    await Isolate.spawn(
      _entry<R>,
      _Job<R>(computation, port.sendPort),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
  } catch (e) {
    port.close();
    rethrow;
  }
  return completer.future;
}

class _Job<R> {
  final R Function(void Function(double) report) computation;
  final SendPort sendPort;
  const _Job(this.computation, this.sendPort);
}

class _Done {
  final Object? value;
  const _Done(this.value);
}

class _Failed {
  final String error;
  const _Failed(this.error);
}

void _entry<R>(_Job<R> job) {
  try {
    final result = job.computation(job.sendPort.send);
    job.sendPort.send(_Done(result));
  } catch (e) {
    job.sendPort.send(_Failed(e.toString()));
  }
}
