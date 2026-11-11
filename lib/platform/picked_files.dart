import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;

import 'fs/atril_fs.dart';

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
