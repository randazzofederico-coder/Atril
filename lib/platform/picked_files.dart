import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;

import 'fs/atril_fs.dart';
import 'web_file_picker_stub.dart' if (dart.library.js_interop) 'web_file_picker_web.dart';

/// Qué se le pide al usuario que elija.
enum PickKind {
  /// Partituras PDF (varias).
  pdfs,

  /// Archivos de Atril: .atril, .setlist, .atrilfolder.
  atrilFile,
}

/// Abandona una selección web que está esperando a Drive.
void cancelPick() => cancelPendingPick();

/// Abre el selector de archivos y devuelve rutas de [AtrilFs] (lista vacía si
/// canceló).
/// - [onWaiting] (solo web): el usuario volvió del selector y el navegador
///   todavía está bajando los archivos (Drive). No hay avance disponible.
/// - [onPreparing] (solo web): avance real (0..1) de la lectura y guardado
///   de los archivos ya entregados: general + del archivo en curso.
///
/// En web usa un selector propio con `accept` explícito: sin él, Android
/// ofrece solo cámara y fotos.
Future<List<String>> pickFilesToFs(
  PickKind kind, {
  void Function()? onWaiting,
  void Function(String message, double progress, String itemLabel, double itemProgress)? onPreparing,
}) async {
  final multiple = kind == PickKind.pdfs;
  if (!fs.isNative) {
    final accept = kind == PickKind.pdfs
        ? '.pdf,application/pdf'
        : '.atril,.setlist,.atrilfolder,.zip,application/zip,'
            'application/x-zip-compressed,application/octet-stream';
    final picked = await pickFilesWeb(accept: accept, multiple: multiple, onWaiting: onWaiting);
    final totalBytes = picked.fold<int>(0, (a, f) => a + f.size);
    var doneBytes = 0;
    final out = <String>[];
    for (var i = 0; i < picked.length; i++) {
      final f = picked[i];
      final msg = picked.length > 1 ? 'Preparando archivo ${i + 1} de ${picked.length}' : 'Preparando archivo';
      double overall(int read) => totalBytes == 0 ? 1 : (doneBytes + read) / totalBytes;
      String item(int read) => '${f.name} · ${_mb(read)} / ${_mb(f.size)}';
      double itemFrac(int read) => f.size == 0 ? 1 : read / f.size;
      onPreparing?.call(msg, overall(0), item(0), 0);
      final bytes = await f.read(onBytes: (read) => onPreparing?.call(msg, overall(read), item(read), itemFrac(read)));
      onPreparing?.call(msg, overall(f.size), 'Guardando ${f.name}...', 1);
      // Un frame para que se vea "Guardando" antes de la copia pesada.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      out.add(await _writeTemp(f.name, bytes));
      doneBytes += f.size;
    }
    return out;
  }
  final result = kind == PickKind.pdfs
      ? await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
          allowMultiple: true,
        )
      : await FilePicker.platform.pickFiles(type: FileType.any);
  if (result == null) return const [];
  return [for (final f in result.files) if (f.path != null) f.path!];
}

String _mb(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(0)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

Future<String> _writeTemp(String name, List<int> bytes) async {
  final path = p.join(
    await fs.tempPath(),
    'atril_pick_${DateTime.now().microsecondsSinceEpoch}',
    name.isEmpty ? 'archivo' : name,
  );
  await fs.writeBytes(path, bytes);
  return path;
}

/// Ruta de [AtrilFs] para un archivo elegido con image_picker/file_picker.
///
/// En nativo es la ruta real que devuelve el selector. En web el selector
/// devuelve un `blob:` que no es una ruta de AtrilFs: se copian los bytes a
/// un temporal y se devuelve esa ruta.
Future<String> fsPathForXFile(XFile file) async {
  if (fs.isNative) return file.path;
  final name = file.name.isNotEmpty ? file.name : 'archivo';
  final path = p.join(
    await fs.tempPath(),
    'atril_pick_${DateTime.now().microsecondsSinceEpoch}_$name',
  );
  await fs.writeBytes(path, await file.readAsBytes());
  return path;
}
