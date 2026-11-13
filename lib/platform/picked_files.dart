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
/// - [onChosen]: llegaron [count] archivos.
/// - [onPrepared]: se guardó el archivo i de n.
///
/// En web usa un selector propio con `accept` explícito: sin él, Android
/// ofrece solo cámara y fotos.
Future<List<String>> pickFilesToFs(
  PickKind kind, {
  void Function()? onWaiting,
  void Function(int count)? onChosen,
  void Function(int done, int total)? onPrepared,
}) async {
  final multiple = kind == PickKind.pdfs;
  if (!fs.isNative) {
    final accept = kind == PickKind.pdfs
        ? '.pdf,application/pdf'
        : '.atril,.setlist,.atrilfolder,.zip,application/zip,'
            'application/x-zip-compressed,application/octet-stream';
    final picked = await pickFilesWeb(
      accept: accept,
      multiple: multiple,
      onWaiting: onWaiting,
      onChosen: onChosen,
    );
    final out = <String>[];
    for (final (name, bytes) in picked) {
      out.add(await _writeTemp(name, bytes));
      onPrepared?.call(out.length, picked.length);
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
  onChosen?.call(result.files.length);
  return [for (final f in result.files) if (f.path != null) f.path!];
}

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
