import 'package:flutter/material.dart';

import '../platform/fs/atril_fs.dart';
import 'fs_image_provider_io.dart' if (dart.library.js_interop) 'fs_image_provider_web.dart'
    as provider;

/// `Image.file` para rutas de [AtrilFs].
///
/// En nativo usa un `FileImage` (igual que antes); en web carga los bytes del
/// almacenamiento del navegador y los muestra con `Image.memory`.
class FsImage extends StatelessWidget {
  final String path;
  final BoxFit? fit;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;

  const FsImage(
    this.path, {
    super.key,
    this.fit,
    this.cacheWidth,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final native = provider.fileImageProvider(path);
    if (native != null) {
      return Image(
        image: ResizeImage.resizeIfNeeded(cacheWidth, null, native),
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }
    return FutureBuilder(
      future: fs.readBytes(path),
      builder: (context, snap) {
        if (snap.hasError) {
          return errorBuilder?.call(context, snap.error!, snap.stackTrace) ??
              const SizedBox.shrink();
        }
        final bytes = snap.data;
        if (bytes == null) return const SizedBox.shrink();
        return Image.memory(
          bytes,
          fit: fit,
          cacheWidth: cacheWidth,
          errorBuilder: errorBuilder,
        );
      },
    );
  }
}
