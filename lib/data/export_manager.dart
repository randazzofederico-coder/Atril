import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/fs/atril_fs.dart';
import '../platform/share_files.dart';
import '../platform/zip/zip_tools.dart';
import 'app_data.dart';
import 'repositories/pdf_annotation_flattener.dart';
import '../models/annotation_stroke.dart';
import '../models/score.dart';
import '../models/setlist.dart';

/// Formato de exportación para setlists.
enum SetlistExportFormat { zip, setlist }

/// Gestiona la exportación y compartición de PDFs y Setlists.
///
/// Sigue el patrón de [BackupManager]: singleton, compresión vía [ZipTools]
/// y [BackgroundTaskStatus] para feedback de progreso en la UI.
class ExportManager {
  ExportManager._();
  static final ExportManager instance = ExportManager._();

  // ---------------------------------------------------------------------------
  // 0. CONSULTAS DE ANOTACIONES
  // ---------------------------------------------------------------------------

  /// `true` si el documento tiene anotaciones (capa global).
  Future<bool> hasAnnotations(String docId) async {
    final ids = await AnnotationRepository.getAnnotatedDocIds();
    return ids.contains(docId);
  }

  /// `true` si alguno de los documentos tiene anotaciones (capa global).
  Future<bool> anyHasAnnotations(Iterable<String> docIds) async {
    final ids = await AnnotationRepository.getAnnotatedDocIds();
    return docIds.any(ids.contains);
  }

  // ---------------------------------------------------------------------------
  // 1. COMPARTIR PDF INDIVIDUAL
  // ---------------------------------------------------------------------------

  /// Comparte un PDF individual invocando el menú nativo del sistema operativo.
  /// El archivo se comparte con el título de display (no el ID interno).
  ///
  /// Si [includeAnnotations] es `true`, se comparte una copia con las
  /// anotaciones "quemadas" en el PDF (el original no se modifica).
  Future<void> sharePdf(Score score, {bool includeAnnotations = false}) async {
    if (score.filePath == null) {
      throw Exception('El archivo no tiene una ruta asignada.');
    }
    final sourcePath = score.filePath!;
    if (!await fs.fileExists(sourcePath)) {
      throw Exception('El archivo PDF no se encontró en el dispositivo.');
    }

    // Copiar a temp con el nombre de display para que el destinatario
    // vea "Mi Canción.pdf" en vez de "d_1234567890_1.pdf".
    final tempDir = await fs.tempPath();
    var displayName = _sanitizeFilename(score.title);
    if (!displayName.toLowerCase().endsWith('.pdf')) {
      displayName += '.pdf';
    }
    final tempPath = p.join(tempDir, displayName);

    if (includeAnnotations) {
      try {
        AppData.backgroundTaskProgress.value =
            const BackgroundTaskStatus(0.0, 'Aplicando anotaciones...');
        await Future.delayed(const Duration(milliseconds: 50));
        await PdfAnnotationFlattener.flattenToFile(
          docId: score.docId,
          sourcePath: sourcePath,
          outputPath: tempPath,
        );
      } finally {
        AppData.backgroundTaskProgress.value = null;
      }
    } else {
      await fs.copy(sourcePath, tempPath);
    }

    await shareFiles([ShareFile(tempPath, mimeType: 'application/pdf')]);
  }

  // ---------------------------------------------------------------------------
  // 2. COMPARTIR SETLIST — DISPATCHER
  // ---------------------------------------------------------------------------

  /// Punto de entrada unificado para compartir un setlist en cualquier formato.
  /// La UI llama a este método con el [format] deseado.
  ///
  /// [includeAnnotations]:
  /// - ZIP: los PDFs se exportan con las anotaciones aplicadas (aplanadas).
  /// - .setlist: las anotaciones viajan como datos editables en `data.json`.
  Future<void> shareSetlist(
    Setlist setlist, {
    required SetlistExportFormat format,
    bool includeAnnotations = false,
  }) async {
    switch (format) {
      case SetlistExportFormat.zip:
        await shareSetlistAsZip(setlist, includeAnnotations: includeAnnotations);
        break;
      case SetlistExportFormat.setlist:
        await shareSetlistAsSetlistFile(setlist, includeAnnotations: includeAnnotations);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 3. COMPARTIR SETLIST COMO ZIP UNIVERSAL
  // ---------------------------------------------------------------------------

  /// Empaqueta los PDFs del setlist en un .zip con nombres ordenados
  /// por zero-padding (ej. "01 - Primer Tema.pdf", "02 - Segundo Tema.pdf").
  Future<void> shareSetlistAsZip(Setlist setlist, {bool includeAnnotations = false}) async {
    String? workDir;
    try {
      // 0. Feedback inmediato
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Preparando setlist...');
      await Future.delayed(const Duration(milliseconds: 50));

      // 1. Materializar scores
      final scores = AppData.materializeSetlist(setlist);
      if (scores.isEmpty) throw Exception('El setlist no contiene partituras.');

      // 2. Calcular zero-padding
      final padWidth = scores.length.toString().length;

      // 3. Construir entradas
      final entries = <_ExportFileEntry>[];
      for (int i = 0; i < scores.length; i++) {
        final score = scores[i];
        if (score.filePath == null) continue;
        if (!await fs.fileExists(score.filePath!)) continue;

        final prefix = (i + 1).toString().padLeft(padWidth, '0');
        final safeTitle = _sanitizeFilename(score.title);
        final zipEntryName = '$prefix - $safeTitle.pdf';
        entries.add(_ExportFileEntry(score.filePath!, zipEntryName, docId: score.docId));
      }

      if (entries.isEmpty) {
        throw Exception('No se encontraron archivos PDF para exportar.');
      }

      // 3b. Aplicar anotaciones (copias temporales)
      if (includeAnnotations) {
        workDir = await createExportWorkDir();
        await _applyAnnotationsToEntries(entries, workDir);
      }

      // 4. Preparar destino temporal
      final safeName = _sanitizeFilename(setlist.name);
      final zipPath = p.join(await fs.tempPath(), '$safeName.zip');

      // 5. Comprimir (en segundo plano) con progreso.
      //    El ZIP universal no lleva data.json.
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Comprimiendo...');
      await ZipTools.zipToFile(
        zipPath,
        [for (final e in entries) ZipEntrySpec.file(e.sourcePath, e.zipEntryName)],
        onProgress: _compressProgress,
      );

      AppData.backgroundTaskProgress.value = null;
      await _deleteDirQuietly(workDir);

      // 7. Compartir
      await shareFiles(
        [ShareFile(zipPath, mimeType: 'application/zip')],
        subject: setlist.name,
      );
    } catch (e) {
      AppData.backgroundTaskProgress.value = null;
      debugPrint('Error compartiendo setlist como ZIP: $e');
      rethrow;
    } finally {
      await _deleteDirQuietly(workDir);
    }
  }

  // ---------------------------------------------------------------------------
  // 4. COMPARTIR SETLIST COMO .SETLIST (FORMATO PROPIO)
  // ---------------------------------------------------------------------------

  /// Empaqueta los PDFs y un `data.json` con la metadata del setlist
  /// en un archivo con extensión `.setlist` (internamente un ZIP).
  ///
  /// Si [includeAnnotations] es `true`, cada item lleva sus anotaciones como
  /// datos (`annotations`), de modo que quien lo importe en Atril las recibe
  /// editables. Los PDFs viajan siempre limpios (originales).
  Future<void> shareSetlistAsSetlistFile(Setlist setlist, {bool includeAnnotations = false}) async {
    try {
      // 0. Feedback inmediato
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Preparando setlist...');
      await Future.delayed(const Duration(milliseconds: 50));

      // 1. Materializar scores
      final scores = AppData.materializeSetlist(setlist);
      if (scores.isEmpty) throw Exception('El setlist no contiene partituras.');

      // 2. Construir entradas y metadata
      final entries = <_ExportFileEntry>[];
      final itemsJson = <Map<String, dynamic>>[];

      for (int i = 0; i < scores.length; i++) {
        final score = scores[i];
        if (score.filePath == null) continue;
        if (!await fs.fileExists(score.filePath!)) continue;

        // Los PDFs se empaquetan con su docId como nombre (el orden lo define data.json)
        final filename = '${score.docId}.pdf';
        entries.add(_ExportFileEntry(score.filePath!, filename));

        final item = <String, dynamic>{
          'index': i,
          ...score.toJsonMap(),
          'filename': filename,
        };

        if (includeAnnotations) {
          final strokes =
              await AnnotationRepository.getAnnotationStrokesForDoc(score.docId);
          if (strokes.isNotEmpty) {
            item['annotations'] = strokes.map((s) {
              final m = s.toDbMap();
              // IDs locales: se regeneran al importar
              m.remove('id');
              m.remove('doc_id');
              return m;
            }).toList();
          }
        }

        itemsJson.add(item);
      }

      if (entries.isEmpty) {
        throw Exception('No se encontraron archivos PDF para exportar.');
      }

      // 3. Serializar data.json
      final dataJson = jsonEncode({
        'format': 'atril_setlist_v1',
        'version': 1,
        'setlistName': setlist.name,
        'items': itemsJson,
      });

      // 4. Preparar destino temporal
      final safeName = _sanitizeFilename(setlist.name);
      final setlistPath = p.join(await fs.tempPath(), '$safeName.setlist');

      // 5. Comprimir (en segundo plano): data.json + PDFs
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Comprimiendo...');
      await ZipTools.zipToFile(
        setlistPath,
        [
          ZipEntrySpec.bytes(utf8.encode(dataJson), 'data.json'),
          for (final e in entries) ZipEntrySpec.file(e.sourcePath, e.zipEntryName),
        ],
        onProgress: _compressProgress,
      );

      AppData.backgroundTaskProgress.value = null;

      // 7. Compartir con mensaje promocional
      await shareFiles(
        [ShareFile(setlistPath, mimeType: 'application/zip')],
        subject: 'Setlist: ${setlist.name}',
        text: 'Acá va el setlist. Abrilo usando Atril. '
            'Si no tenés la app, bajala acá: '
            'https://federicorandazzo.com.ar/apps/',
      );
    } catch (e) {
      AppData.backgroundTaskProgress.value = null;
      debugPrint('Error compartiendo setlist como .setlist: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // 5. IMPORTAR SETLIST DESDE ARCHIVO .setlist
  // ---------------------------------------------------------------------------

  /// Importa un archivo .setlist: descomprime, parsea data.json,
  /// importa los PDFs a la biblioteca y crea el setlist.
  /// Retorna el ID del setlist creado, o null si falló.
  Future<String?> importSetlistFile(String filePath) async {
    String? extractDir;
    final copiedFiles = <String>[];
    try {
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Importando setlist...');
      await Future.delayed(const Duration(milliseconds: 50));

      // 1. Descomprimir en segundo plano
      extractDir = p.join(
        await fs.tempPath(),
        'setlist_import_${DateTime.now().millisecondsSinceEpoch}',
      );
      await fs.createDir(extractDir);

      await ZipTools.unzipToDir(
        filePath,
        extractDir,
        onProgress: (v) => AppData.backgroundTaskProgress.value =
            BackgroundTaskStatus(v, 'Descomprimiendo...'),
      );

      // 2. Leer y parsear data.json
      final dataJsonFile = p.join(extractDir, 'data.json');
      if (!await fs.fileExists(dataJsonFile)) {
        throw Exception('Archivo .setlist inválido: falta data.json');
      }

      final jsonStr = await fs.readString(dataJsonFile);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (data['format'] != 'atril_setlist_v1') {
        throw Exception('Formato de setlist no reconocido.');
      }

      final setlistName = data['setlistName'] as String? ?? 'Setlist importado';
      final items = (data['items'] as List).cast<Map<String, dynamic>>();

      // 3. Copiar los PDFs primero (fuera de la transacción), registrando
      //    cada copia para poder borrarla si algo falla después.
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.3, 'Importando partituras...');

      final docsDir = await AppData.storage.getDocsPath();
      final pending = <_PendingSetlistDoc>[];

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        // `filename` viene de data.json (archivo externo): solo se acepta un
        // nombre simple .pdf dentro del paquete (sin rutas ni "..").
        final rawFilename = item['filename'] as String? ?? '';
        final filename = p.basename(rawFilename);
        if (filename != rawFilename || !filename.toLowerCase().endsWith('.pdf')) {
          debugPrint('Warning: nombre de archivo inválido en el paquete: $rawFilename');
          continue;
        }

        final sourceFile = p.join(extractDir, filename);
        if (!await fs.fileExists(sourceFile)) {
          debugPrint('Warning: PDF no encontrado en el paquete: $filename');
          continue;
        }

        final newDocId = AppData.newDocId();
        final newFilename = '$newDocId.pdf';
        final destFile = p.join(docsDir, newFilename);
        // Web: mover desde el temporal de extracción (no duplica los bytes).
        await (fs.isNative ? fs.copy(sourceFile, destFile) : fs.rename(sourceFile, destFile));
        copiedFiles.add(destFile);

        pending.add(_PendingSetlistDoc(
          docId: newDocId,
          relPath: p.join('docs', newFilename),
          title: item['title'] as String? ?? 'Sin título',
          author: item['author'] as String? ?? '',
          annotations: item['annotations'] is List ? item['annotations'] as List : const [],
          filename: filename,
        ));

        AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
          0.3 + (0.6 * (i + 1) / items.length),
          'Importando partituras (${i + 1}/${items.length})...',
        );
      }

      if (pending.isEmpty) {
        throw Exception('No se pudieron importar partituras del setlist.');
      }

      // 4. Carpeta + partituras + anotaciones + setlist en UNA transacción
      final folderId = AppData.newFolderId();
      final newSetlistId = AppData.newSetlistId();
      final uniqueName = AppData.uniqueSetlistName(setlistName);

      await AppData.db.transaction(() async {
        await AppData.db.createFolder(
          id: folderId,
          name: setlistName,
          parentId: null, // Raíz de la biblioteca
          position: 999,  // Al final
        );

        for (final d in pending) {
          await AppData.db.upsertDoc(
            id: d.docId,
            displayName: d.title,
            author: d.author,
            internalRelPath: d.relPath,
            folderId: folderId, // Dentro de la carpeta del setlist
          );

          // Anotaciones editables (opcionales; formato retrocompatible).
          // Una anotación inválida se omite sin cancelar la importación.
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
              debugPrint('Warning: anotación inválida en ${d.filename}: $e');
              continue;
            }
            await AnnotationRepository.insertAnnotationStroke(stroke);
          }
        }

        await AppData.db.upsertSetlist(id: newSetlistId, name: uniqueName);
        await AppData.db.replaceSetlistItems(
          setlistId: newSetlistId,
          orderedDocIds: [for (final d in pending) d.docId],
        );
      });

      copiedFiles.clear(); // confirmado: los PDFs se quedan

      // 5. Refrescar biblioteca
      await AppData.refreshLibrary();

      AppData.backgroundTaskProgress.value = null;
      return newSetlistId;
    } catch (e) {
      AppData.backgroundTaskProgress.value = null;
      debugPrint('Error importando setlist: $e');
      for (final f in copiedFiles) {
        try { await fs.deleteFile(f); } catch (_) {}
      }
      rethrow;
    } finally {
      // Cleanup temp
      if (extractDir != null) {
        try {
          await fs.deleteDir(extractDir);
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  void _compressProgress(double v) =>
      AppData.backgroundTaskProgress.value = BackgroundTaskStatus(v, 'Comprimiendo...');

  /// Crea un directorio temporal de trabajo para copias aplanadas.
  Future<String> createExportWorkDir() async {
    final dir = p.join(
      await fs.tempPath(),
      'export_work_${DateTime.now().millisecondsSinceEpoch}',
    );
    await fs.createDir(dir);
    return dir;
  }

  Future<void> _deleteDirQuietly(String? dir) async {
    if (dir == null) return;
    try {
      await fs.deleteDir(dir);
    } catch (_) {}
  }

  /// Borra un directorio de trabajo ignorando errores.
  Future<void> deleteDirQuietly(String? dir) => _deleteDirQuietly(dir);

  /// Para cada documento de [sources] (docId → ruta del PDF original) que tenga
  /// anotaciones, genera una copia con las anotaciones aplicadas dentro de
  /// [workDir]. Reporta progreso en [AppData.backgroundTaskProgress].
  ///
  /// Devuelve docId → ruta del PDF aplanado (solo los que tenían anotaciones).
  Future<Map<String, String>> flattenAnnotatedDocs(
    Map<String, String> sources,
    String workDir,
  ) async {
    final annotated = await AnnotationRepository.getAnnotatedDocIds();
    final targets = sources.keys.where(annotated.contains).toList();
    final result = <String, String>{};

    for (int i = 0; i < targets.length; i++) {
      final docId = targets[i];
      AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
        i / targets.length,
        'Aplicando anotaciones (${i + 1}/${targets.length})...',
      );
      final outPath = p.join(workDir, '$docId.pdf');
      try {
        await PdfAnnotationFlattener.flattenToFile(
          docId: docId,
          sourcePath: sources[docId]!,
          outputPath: outPath,
        );
        result[docId] = outPath;
      } catch (e) {
        // Si un PDF falla, exportamos el original en vez de abortar todo.
        debugPrint('Warning: no se pudieron aplicar anotaciones a $docId: $e');
      }
    }
    return result;
  }

  /// Reemplaza el origen de cada entrada por su versión aplanada (si aplica).
  Future<void> _applyAnnotationsToEntries(
    List<_ExportFileEntry> entries,
    String workDir,
  ) async {
    final sources = <String, String>{
      for (final e in entries)
        if (e.docId != null) e.docId!: e.sourcePath,
    };
    final flattened = await flattenAnnotatedDocs(sources, workDir);
    for (final e in entries) {
      final f = flattened[e.docId];
      if (f != null) e.sourcePath = f;
    }
  }

  /// Remueve caracteres ilegales para nombres de archivo.
  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }
}

// =============================================================================
// TIPOS INTERNOS
// =============================================================================

/// Partitura de un .setlist ya copiada, pendiente de registrar en la DB.
class _PendingSetlistDoc {
  final String docId;
  final String relPath;
  final String title;
  final String author;
  final List annotations;
  final String filename;
  _PendingSetlistDoc({
    required this.docId,
    required this.relPath,
    required this.title,
    required this.author,
    required this.annotations,
    required this.filename,
  });
}

/// Entrada para un archivo a incluir en el ZIP.
class _ExportFileEntry {
  /// Mutable: se reemplaza por la copia aplanada al incluir anotaciones.
  String sourcePath;
  final String zipEntryName;
  final String? docId;
  _ExportFileEntry(this.sourcePath, this.zipEntryName, {this.docId});
}
