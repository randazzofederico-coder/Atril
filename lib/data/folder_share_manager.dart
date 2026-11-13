import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/annotation_stroke.dart';
import '../models/folder.dart';
import '../models/score.dart';
import '../platform/fs/atril_fs.dart';
import '../platform/share_files.dart';
import '../platform/zip/zip_tools.dart';
import 'app_data.dart';

/// Formato al compartir una carpeta.
enum FolderExportFormat { zip, atrilFolder }

/// Compartir una carpeta (con sus subcarpetas) e importar `.atrilfolder`.
///
/// - `.zip` universal: el árbol como directorios; anotaciones opcionales
///   "quemadas" en los PDFs.
/// - `.atrilfolder` (ZIP con `folder.json`): recrea el árbol en Atril, con las
///   anotaciones opcionales como datos editables. Los PDFs van limpios.
///
/// Las partituras y carpetas en la papelera no se incluyen.
class FolderShareManager {
  FolderShareManager._();
  static final FolderShareManager instance = FolderShareManager._();

  static const String metadataName = 'folder.json';
  static const String formatId = 'atril_folder_v1';
  static const String extension = '.atrilfolder';

  // ---------------------------------------------------------------------------
  // COMPARTIR
  // ---------------------------------------------------------------------------

  Future<void> shareFolder(
    String folderId, {
    required FolderExportFormat format,
    bool includeAnnotations = false,
  }) async {
    final root = AppData.getFolderById(folderId);
    if (root == null) throw Exception('La carpeta no existe.');

    String? workDir;
    try {
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Preparando carpeta...');
      await Future.delayed(const Duration(milliseconds: 50));

      final tree = _FolderTree.build(root);
      if (tree.scores.isEmpty) throw Exception('La carpeta no contiene partituras.');

      final entries = <ZipEntrySpec>[];
      final safeName = _sanitize(root.name);
      final String outPath;

      if (format == FolderExportFormat.zip) {
        // Rutas legibles: Carpeta/Sub/Título.pdf (sin repetir nombres)
        final sources = <String, String>{}; // docId -> ruta del PDF a usar
        for (final s in tree.scores) {
          if (await fs.fileExists(s.filePath!)) sources[s.docId] = s.filePath!;
        }
        if (includeAnnotations) {
          workDir = await ExportManager.instance.createExportWorkDir();
          final flattened = await ExportManager.instance.flattenAnnotatedDocs(sources, workDir);
          sources.addAll(flattened);
        }
        final used = <String>{};
        for (final s in tree.scores) {
          final src = sources[s.docId];
          if (src == null) continue;
          final dir = tree.zipDirOf(s.folderId);
          var base = _sanitize(s.title);
          if (base.toLowerCase().endsWith('.pdf')) base = base.substring(0, base.length - 4);
          String build(String n) => '$dir/$n.pdf';
          var path = build(base);
          var n = 2;
          while (!used.add(path.toLowerCase())) {
            path = build('$base ($n)');
            n++;
          }
          entries.add(ZipEntrySpec.file(src, path));
        }
        outPath = p.join(await fs.tempPath(), '$safeName.zip');
      } else {
        // .atrilfolder: folder.json + PDFs por docId
        final items = <Map<String, dynamic>>[];
        for (final s in tree.scores) {
          if (!await fs.fileExists(s.filePath!)) continue;
          final filename = '${s.docId}.pdf';
          entries.add(ZipEntrySpec.file(s.filePath!, filename));
          final item = <String, dynamic>{
            'filename': filename,
            'folderKey': tree.keyOf(s.folderId),
            'title': s.title,
            'author': s.author,
          };
          if (includeAnnotations) {
            final strokes = await AnnotationRepository.getAnnotationStrokesForDoc(s.docId);
            if (strokes.isNotEmpty) {
              item['annotations'] = strokes.map((st) {
                final m = st.toDbMap();
                // IDs locales: se regeneran al importar
                m.remove('id');
                m.remove('doc_id');
                return m;
              }).toList();
            }
          }
          items.add(item);
        }
        final json = jsonEncode({
          'format': formatId,
          'version': 1,
          'rootName': root.name,
          'folders': tree.foldersJson(),
          'items': items,
        });
        entries.insert(0, ZipEntrySpec.bytes(utf8.encode(json), metadataName));
        outPath = p.join(await fs.tempPath(), '$safeName$extension');
      }

      if (entries.isEmpty) throw Exception('No se encontraron archivos PDF para exportar.');

      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Comprimiendo...');
      await ZipTools.zipToFile(
        outPath,
        entries,
        onProgress: (v) =>
            AppData.backgroundTaskProgress.value = BackgroundTaskStatus(v, 'Comprimiendo...'),
      );
      AppData.backgroundTaskProgress.value = null;
      await ExportManager.instance.deleteDirQuietly(workDir);

      if (format == FolderExportFormat.zip) {
        await shareFiles([ShareFile(outPath, mimeType: 'application/zip')], subject: root.name);
      } else {
        await shareFiles(
          [ShareFile(outPath, mimeType: 'application/zip')],
          subject: 'Carpeta: ${root.name}',
          text: 'Acá va la carpeta "${root.name}". Abrila usando Atril. '
              'Si no tenés la app, entrá acá: https://federicorandazzo.com.ar/apps/',
        );
      }
    } catch (e) {
      debugPrint('Error compartiendo carpeta: $e');
      rethrow;
    } finally {
      AppData.backgroundTaskProgress.value = null;
      await ExportManager.instance.deleteDirQuietly(workDir);
    }
  }

  // ---------------------------------------------------------------------------
  // IMPORTAR .atrilfolder
  // ---------------------------------------------------------------------------

  /// Importa un `.atrilfolder` dentro de [targetParentId] ('root' = raíz).
  /// Siempre crea copias nuevas. Devuelve el id de la carpeta creada.
  Future<String> importAtrilFolder(String filePath, String targetParentId) async {
    String? extractDir;
    final copiedFiles = <String>[];
    try {
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Importando carpeta...');
      await Future.delayed(const Duration(milliseconds: 50));

      extractDir = p.join(
        await fs.tempPath(),
        'import_extraction_${DateTime.now().millisecondsSinceEpoch}',
      );
      await fs.createDir(extractDir);
      await ZipTools.unzipToDir(
        filePath,
        extractDir,
        onProgress: (v) => AppData.backgroundTaskProgress.value =
            BackgroundTaskStatus(v * 0.3, 'Descomprimiendo...'),
      );

      final metaPath = p.join(extractDir, metadataName);
      if (!await fs.fileExists(metaPath)) {
        throw Exception('Archivo $extension inválido: falta $metadataName');
      }
      final data = jsonDecode(await fs.readString(metaPath)) as Map<String, dynamic>;
      if (data['format'] != formatId) throw Exception('Formato de carpeta no reconocido.');

      final folders = (data['folders'] as List? ?? const []).whereType<Map>().toList();
      final items = (data['items'] as List? ?? const []).whereType<Map>().toList();
      final rootName = (data['rootName'] as String?)?.trim();

      // Claves de carpeta -> ids nuevos (la clave raíz es la que no tiene padre)
      final newIds = <String, String>{};
      String? rootKey;
      for (final f in folders) {
        final key = f['key'] as String?;
        if (key == null) continue;
        newIds[key] = AppData.newFolderId();
        if (f['parentKey'] == null) rootKey ??= key;
      }
      if (rootKey == null) throw Exception('La carpeta compartida está vacía.');

      // 1. Copiar PDFs (fuera de la transacción), registrando cada copia
      final docsDir = await AppData.storage.getDocsPath();
      final pending = <_PendingDoc>[];
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        // Solo nombres simples .pdf dentro del paquete (sin rutas ni "..")
        final raw = item['filename'] as String? ?? '';
        final filename = p.basename(raw);
        if (filename != raw || !filename.toLowerCase().endsWith('.pdf')) continue;
        final source = p.join(extractDir, filename);
        if (!await fs.fileExists(source)) continue;

        final docId = AppData.newDocId();
        final dest = p.join(docsDir, '$docId.pdf');
        // Web: mover desde el temporal de extracción (no duplica los bytes).
        await (fs.isNative ? fs.copy(source, dest) : fs.rename(source, dest));
        copiedFiles.add(dest);
        pending.add(_PendingDoc(
          docId: docId,
          relPath: p.join('docs', '$docId.pdf'),
          title: item['title'] as String? ?? 'Sin título',
          author: item['author'] as String? ?? '',
          folderId: newIds[item['folderKey']] ?? newIds[rootKey]!,
          annotations: item['annotations'] is List ? item['annotations'] as List : const [],
        ));
        AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
          0.3 + 0.6 * (i + 1) / items.length,
          'Importando partituras (${i + 1}/${items.length})...',
        );
      }
      if (pending.isEmpty) throw Exception('No se pudieron importar partituras de la carpeta.');

      // 2. Carpetas + partituras + anotaciones en UNA transacción
      final rootId = newIds[rootKey]!;
      final uniqueRoot = LibraryRepository.uniqueFolderName(
        rootName?.isNotEmpty == true ? rootName! : 'Carpeta importada',
        targetParentId,
      );
      final siblings =
          AppData.folders.where((f) => (f.parentId ?? 'root') == targetParentId).length;

      await AppData.db.transaction(() async {
        // Primero todas sin padre (evita FK a carpetas aún no creadas)
        for (final f in folders) {
          final key = f['key'] as String?;
          if (key == null) continue;
          final isRoot = key == rootKey;
          await AppData.db.createFolder(
            id: newIds[key]!,
            name: isRoot ? uniqueRoot : (f['name'] as String? ?? 'Carpeta'),
            parentId: null,
            position: isRoot ? siblings : ((f['position'] as num?)?.toInt() ?? 0),
          );
        }
        for (final f in folders) {
          final key = f['key'] as String?;
          if (key == null) continue;
          final String? parent = key == rootKey
              ? (targetParentId == 'root' ? null : targetParentId)
              : (newIds[f['parentKey']] ?? rootId);
          await AppData.db.setFolderParent(newIds[key]!, parent);
        }

        for (final d in pending) {
          await AppData.db.upsertDoc(
            id: d.docId,
            displayName: d.title,
            author: d.author,
            internalRelPath: d.relPath,
            folderId: d.folderId,
          );
          // Anotaciones editables: una inválida se omite sin cancelar todo
          for (final raw in d.annotations) {
            if (raw is! Map) continue;
            final AnnotationStroke stroke;
            try {
              stroke = AnnotationStroke.fromDbMap({
                ...raw.cast<String, Object?>(),
                'id': AppData.newId(prefix: 'stk'),
                'doc_id': d.docId,
              });
            } catch (e) {
              debugPrint('Warning: anotación inválida: $e');
              continue;
            }
            await AnnotationRepository.insertAnnotationStroke(stroke);
          }
        }
      });

      copiedFiles.clear(); // confirmado: los PDFs se quedan
      await AppData.refreshLibrary();
      return rootId;
    } catch (e) {
      debugPrint('Error importando carpeta: $e');
      for (final f in copiedFiles) {
        try {
          await fs.deleteFile(f);
        } catch (_) {}
      }
      rethrow;
    } finally {
      AppData.backgroundTaskProgress.value = null;
      if (extractDir != null) {
        try {
          await fs.deleteDir(extractDir);
        } catch (_) {}
      }
    }
  }

  static String _sanitize(String name) => name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
}

/// Árbol de una carpeta: subcarpetas activas, claves estables para el JSON y
/// rutas legibles para el ZIP.
class _FolderTree {
  final Folder root;
  final List<Folder> folders; // incluye root
  final Map<String, String> _keys; // folderId -> clave
  final Map<String, String> _zipDirs; // folderId -> ruta en el ZIP
  final List<Score> scores;

  _FolderTree._(this.root, this.folders, this._keys, this._zipDirs, this.scores);

  factory _FolderTree.build(Folder root) {
    final folders = <Folder>[root];
    final keys = <String, String>{root.id: 'f0'};
    final zipDirs = <String, String>{root.id: FolderShareManager._sanitize(root.name)};

    void walk(Folder parent) {
      final children = AppData.folders.where((f) => f.parentId == parent.id).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      final usedNames = <String>{};
      for (final c in children) {
        folders.add(c);
        keys[c.id] = 'f${keys.length}';
        var name = FolderShareManager._sanitize(c.name);
        var n = 2;
        final base = name;
        while (!usedNames.add(name.toLowerCase())) {
          name = '$base ($n)';
          n++;
        }
        zipDirs[c.id] = '${zipDirs[parent.id]}/$name';
        walk(c);
      }
    }

    walk(root);
    final scores = AppData.library
        .where((s) => keys.containsKey(s.folderId) && s.filePath != null)
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return _FolderTree._(root, folders, keys, zipDirs, scores);
  }

  String keyOf(String folderId) => _keys[folderId] ?? 'f0';
  String zipDirOf(String folderId) => _zipDirs[folderId] ?? _zipDirs[root.id]!;

  List<Map<String, dynamic>> foldersJson() => [
        for (final f in folders)
          {
            'key': _keys[f.id],
            'name': f.name,
            'parentKey': f.id == root.id ? null : _keys[f.parentId],
            'position': f.position,
          },
      ];
}

class _PendingDoc {
  final String docId;
  final String relPath;
  final String title;
  final String author;
  final String folderId;
  final List annotations;
  _PendingDoc({
    required this.docId,
    required this.relPath,
    required this.title,
    required this.author,
    required this.folderId,
    required this.annotations,
  });
}
