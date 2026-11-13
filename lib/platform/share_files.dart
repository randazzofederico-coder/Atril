import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'fs/atril_fs.dart';
import 'share_blob_stub.dart' if (dart.library.js_interop) 'share_blob_web.dart';

/// Archivo de [AtrilFs] a compartir.
class ShareFile {
  final String path;
  final String? mimeType;
  const ShareFile(this.path, {this.mimeType});
}

/// Abre el menú nativo de compartir con archivos de [AtrilFs].
///
/// En nativo pasa las rutas; en web lee los bytes (las rutas son virtuales).
Future<void> shareFiles(List<ShareFile> files, {String? subject, String? text}) async {
  // Web: un resultado grande armado como Blob (ZIP) se comparte directo.
  if (!fs.isNative && files.length == 1 &&
      await shareRegisteredBlob(files.single.path, mimeType: files.single.mimeType, subject: subject, text: text)) {
    return;
  }
  final xfiles = <XFile>[];
  for (final f in files) {
    if (fs.isNative) {
      xfiles.add(XFile(f.path, mimeType: f.mimeType));
    } else {
      xfiles.add(XFile.fromData(
        await fs.readBytes(f.path),
        name: p.basename(f.path),
        mimeType: f.mimeType,
      ));
    }
  }
  await Share.shareXFiles(xfiles, subject: subject, text: text);
}
