import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Canal de plataforma para recibir archivos .setlist y .atril
/// abiertos desde fuera de la app (ej: toque en WhatsApp, Files, etc.).
///
/// Maneja dos escenarios:
/// - **Cold start**: El SO abre la app con un archivo. Flutter consulta
///   `getInitialFile` al iniciar.
/// - **Hot resume**: La app ya está corriendo. El nativo invoca
///   `onNewFile` con el path.
class FileReceiverChannel {
  static const _channel = MethodChannel('com.saroo.atril/file_receiver');

  /// Callback que se ejecuta cuando se recibe un archivo.
  /// El parámetro es el path absoluto al archivo temporal.
  static void Function(String path)? onFileReceived;

  /// Inicializa el canal. Debe llamarse después de que AppData.init() complete.
  static Future<void> init() async {
    debugPrint('[FileReceiver] init() iniciado');

    // 1. Registrar handler para hot resume (app ya corriendo)
    _channel.setMethodCallHandler((call) async {
      debugPrint('[FileReceiver] MethodCall recibido: ${call.method}, args=${call.arguments}');
      if (call.method == 'onNewFile') {
        final path = call.arguments as String?;
        if (path != null) {
          debugPrint('[FileReceiver] Hot resume - path: $path');
          onFileReceived?.call(path);
        }
      }
    });

    // 2. Consultar si hay un archivo pendiente de cold start
    try {
      debugPrint('[FileReceiver] Consultando getInitialFile...');
      final initialFile = await _channel.invokeMethod<String>('getInitialFile');
      debugPrint('[FileReceiver] getInitialFile respondió: $initialFile');
      if (initialFile != null && initialFile.isNotEmpty) {
        debugPrint('[FileReceiver] Cold start - invocando callback con: $initialFile');
        onFileReceived?.call(initialFile);
      } else {
        debugPrint('[FileReceiver] No hay archivo pendiente de cold start');
      }
    } catch (e) {
      // En desktop/web el canal no existe, es esperado
      debugPrint('[FileReceiver] Canal no disponible: $e');
    }
  }
}
