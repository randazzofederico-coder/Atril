import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;

import 'fs/atril_fs.dart';

/// Hay que pedirle los bytes a file_picker solo en web (en nativo hay ruta).
bool get pickerNeedsData => !fs.isNative;

/// Rutas de [AtrilFs] para archivos elegidos con file_picker (llamarlo con
/// `withData: pickerNeedsData`). En web los bytes se copian a temporales.
Future<List<String>> fsPathsForPlatformFiles(List<PlatformFile> files) async {
  final out = <String>[];
  for (final f in files) {
    if (fs.isNative) {
      if (f.path != null) out.add(f.path!);
      continue;
    }
    final bytes = f.bytes;
    if (bytes == null) continue;
    final path = p.join(
      await fs.tempPath(),
      'atril_pick_${DateTime.now().microsecondsSinceEpoch}',
      f.name,
    );
    await fs.writeBytes(path, bytes);
    out.add(path);
  }
  return out;
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
