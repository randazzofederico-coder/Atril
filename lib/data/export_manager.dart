import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_data.dart';
import 'repositories/pdf_annotation_flattener.dart';
import '../models/annotation_stroke.dart';
import '../models/score.dart';
import '../models/setlist.dart';

/// Formato de exportación para setlists.
enum SetlistExportFormat { zip, setlist }

/// Gestiona la exportación y compartición de PDFs y Setlists.
///
/// Sigue el patrón de [BackupManager]: singleton, Isolate workers top-level,
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
    final file = File(score.filePath!);
    if (!await file.exists()) {
      throw Exception('El archivo PDF no se encontró en el dispositivo.');
    }

    // Copiar a temp con el nombre de display para que el destinatario
    // vea "Mi Canción.pdf" en vez de "d_1234567890_1.pdf".
    final tempDir = await getTemporaryDirectory();
    var displayName = _sanitizeFilename(score.title);
    if (!displayName.toLowerCase().endsWith('.pdf')) {
      displayName += '.pdf';
    }
    final tempPath = p.join(tempDir.path, displayName);

    if (includeAnnotations) {
      try {
        AppData.backgroundTaskProgress.value =
            const BackgroundTaskStatus(0.0, 'Aplicando anotaciones...');
        await Future.delayed(const Duration(milliseconds: 50));
        await PdfAnnotationFlattener.flattenToFile(
          docId: score.docId,
          sourcePath: file.path,
          outputPath: tempPath,
        );
      } finally {
        AppData.backgroundTaskProgress.value = null;
      }
    } else {
      await file.copy(tempPath);
    }

    await Share.shareXFiles([XFile(tempPath, mimeType: 'application/pdf')]);
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
    Directory? workDir;
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
        final file = File(score.filePath!);
        if (!await file.exists()) continue;

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
      final tempDir = await getTemporaryDirectory();
      final zipPath = p.join(tempDir.path, '$safeName.zip');

      // 5. Spawn Isolate
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Comprimiendo...');

      final receivePort = ReceivePort();
      await Isolate.spawn(
        _zipSetlistWorker,
        _ZipSetlistWorkerArgs(
          outputPath: zipPath,
          entries: entries,
          metadataJson: null, // ZIP universal no lleva data.json
          sendPort: receivePort.sendPort,
        ),
      );

      // 6. Escuchar progreso
      await for (final message in receivePort) {
        if (message is double) {
          AppData.backgroundTaskProgress.value =
              BackgroundTaskStatus(message, 'Comprimiendo...');
        } else if (message == 'DONE') {
          break;
        } else if (message is String && message.startsWith('ERROR:')) {
          throw Exception(message);
        }
      }

      AppData.backgroundTaskProgress.value = null;
      await _deleteDirQuietly(workDir);

      // 7. Compartir
      await Share.shareXFiles(
        [XFile(zipPath, mimeType: 'application/zip')],
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
        final file = File(score.filePath!);
        if (!await file.exists()) continue;

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
      final tempDir = await getTemporaryDirectory();
      final setlistPath = p.join(tempDir.path, '$safeName.setlist');

      // 5. Spawn Isolate
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Comprimiendo...');

      final receivePort = ReceivePort();
      await Isolate.spawn(
        _zipSetlistWorker,
        _ZipSetlistWorkerArgs(
          outputPath: setlistPath,
          entries: entries,
          metadataJson: dataJson,
          sendPort: receivePort.sendPort,
        ),
      );

      // 6. Escuchar progreso
      await for (final message in receivePort) {
        if (message is double) {
          AppData.backgroundTaskProgress.value =
              BackgroundTaskStatus(message, 'Comprimiendo...');
        } else if (message == 'DONE') {
          break;
        } else if (message is String && message.startsWith('ERROR:')) {
          throw Exception(message);
        }
      }

      AppData.backgroundTaskProgress.value = null;

      // 7. Compartir con mensaje promocional
      await Share.shareXFiles(
        [XFile(setlistPath, mimeType: 'application/zip')],
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
    Directory? extractDir;
    try {
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.0, 'Importando setlist...');
      await Future.delayed(const Duration(milliseconds: 50));

      // 1. Descomprimir en Isolate
      final tempDir = await getTemporaryDirectory();
      extractDir = Directory(
        p.join(tempDir.path, 'setlist_import_${DateTime.now().millisecondsSinceEpoch}'),
      );
      await extractDir.create(recursive: true);

      final receivePort = ReceivePort();
      await Isolate.spawn(
        _unzipSetlistWorker,
        _UnzipSetlistWorkerArgs(
          zipPath: filePath,
          destPath: extractDir.path,
          sendPort: receivePort.sendPort,
        ),
      );

      await for (final message in receivePort) {
        if (message is double) {
          AppData.backgroundTaskProgress.value =
              BackgroundTaskStatus(message, 'Descomprimiendo...');
        } else if (message == 'DONE') {
          break;
        } else if (message is String && message.startsWith('ERROR:')) {
          throw Exception(message);
        }
      }

      // 2. Leer y parsear data.json
      final dataJsonFile = File(p.join(extractDir.path, 'data.json'));
      if (!await dataJsonFile.exists()) {
        throw Exception('Archivo .setlist inválido: falta data.json');
      }

      final jsonStr = await dataJsonFile.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (data['format'] != 'atril_setlist_v1') {
        throw Exception('Formato de setlist no reconocido.');
      }

      final setlistName = data['setlistName'] as String? ?? 'Setlist importado';
      final items = (data['items'] as List).cast<Map<String, dynamic>>();

      // 3. Crear carpeta en la biblioteca con el nombre del setlist
      final folderId = AppData.newFolderId();
      await AppData.db.createFolder(
        id: folderId,
        name: setlistName,
        parentId: null, // Raíz de la biblioteca
        position: 999,  // Al final
      );

      // 4. Importar PDFs dentro de la carpeta
      AppData.backgroundTaskProgress.value =
          const BackgroundTaskStatus(0.5, 'Importando partituras...');

      final newDocIds = <String>[];
      final docsDir = await AppData.storage.getDocsDir();

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final filename = item['filename'] as String;
        final title = item['title'] as String? ?? 'Sin título';
        final author = item['author'] as String? ?? '';

        final sourceFile = File(p.join(extractDir.path, filename));
        if (!await sourceFile.exists()) {
          debugPrint('Warning: PDF no encontrado en el paquete: $filename');
          continue;
        }

        final newDocId = AppData.newDocId();
        final newFilename = '$newDocId.pdf';
        final destFile = File(p.join(docsDir.path, newFilename));
        await sourceFile.copy(destFile.path);

        await AppData.db.upsertDoc(
          id: newDocId,
          displayName: title,
          author: author,
          internalRelPath: p.join('docs', newFilename),
          folderId: folderId, // Dentro de la carpeta del setlist
        );

        // Anotaciones editables (opcionales; formato retrocompatible)
        final annotations = item['annotations'];
        if (annotations is List) {
          for (final raw in annotations) {
            if (raw is! Map) continue;
            try {
              final stroke = AnnotationStroke.fromDbMap({
                ...raw.cast<String, Object?>(),
                'id': AppData.newId(prefix: 'stk'),
                'doc_id': newDocId,
              });
              await AnnotationRepository.insertAnnotationStroke(stroke);
            } catch (e) {
              debugPrint('Warning: anotación inválida en $filename: $e');
            }
          }
        }

        newDocIds.add(newDocId);

        AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
          0.5 + (0.5 * (i + 1) / items.length),
          'Importando partituras (${i + 1}/${items.length})...',
        );
      }

      if (newDocIds.isEmpty) {
        throw Exception('No se pudieron importar partituras del setlist.');
      }

      // 5. Crear setlist
      final uniqueName = AppData.uniqueSetlistName(setlistName);
      final newSetlistId = AppData.newSetlistId();

      await AppData.db.upsertSetlist(id: newSetlistId, name: uniqueName);
      await AppData.db.replaceSetlistItems(
        setlistId: newSetlistId,
        orderedDocIds: newDocIds,
      );

      // 5. Refrescar biblioteca
      await AppData.refreshLibrary();

      AppData.backgroundTaskProgress.value = null;
      return newSetlistId;
    } catch (e) {
      AppData.backgroundTaskProgress.value = null;
      debugPrint('Error importando setlist: $e');
      rethrow;
    } finally {
      // Cleanup temp
      if (extractDir != null && await extractDir.exists()) {
        try {
          await extractDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  /// Crea un directorio temporal de trabajo para copias aplanadas.
  Future<Directory> createExportWorkDir() async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(
      p.join(tempDir.path, 'export_work_${DateTime.now().millisecondsSinceEpoch}'),
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _deleteDirQuietly(Directory? dir) async {
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Borra un directorio de trabajo ignorando errores.
  Future<void> deleteDirQuietly(Directory? dir) => _deleteDirQuietly(dir);

  /// Para cada documento de [sources] (docId → ruta del PDF original) que tenga
  /// anotaciones, genera una copia con las anotaciones aplicadas dentro de
  /// [workDir]. Reporta progreso en [AppData.backgroundTaskProgress].
  ///
  /// Devuelve docId → ruta del PDF aplanado (solo los que tenían anotaciones).
  Future<Map<String, String>> flattenAnnotatedDocs(
    Map<String, String> sources,
    Directory workDir,
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
      final outPath = p.join(workDir.path, '$docId.pdf');
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
    Directory workDir,
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
// ISOLATE WORKER — TOP-LEVEL (requerido por Isolate.spawn)
// =============================================================================

/// Entrada para un archivo a incluir en el ZIP.
class _ExportFileEntry {
  /// Mutable: se reemplaza por la copia aplanada al incluir anotaciones.
  String sourcePath;
  final String zipEntryName;
  final String? docId;
  _ExportFileEntry(this.sourcePath, this.zipEntryName, {this.docId});
}

/// Argumentos para el worker de compresión.
class _ZipSetlistWorkerArgs {
  final String outputPath;
  final List<_ExportFileEntry> entries;

  /// Si no es null, se escribe como `data.json` dentro del ZIP (formato .setlist).
  final String? metadataJson;
  final SendPort sendPort;

  _ZipSetlistWorkerArgs({
    required this.outputPath,
    required this.entries,
    required this.metadataJson,
    required this.sendPort,
  });
}

/// Worker de compresión ejecutado en un Isolate separado.
/// Protocolo de mensajes:
///   - `double` (0.0–1.0): progreso
///   - `'DONE'`: completado con éxito
///   - `'ERROR: ...'`: fallo con descripción
Future<void> _zipSetlistWorker(_ZipSetlistWorkerArgs args) async {
  try {
    final encoder = ZipFileEncoder();
    encoder.create(args.outputPath);

    // 1. Escribir data.json si corresponde (formato .setlist)
    if (args.metadataJson != null) {
      final tempDataFile = File('${args.outputPath}_data.json');
      await tempDataFile.writeAsString(args.metadataJson!, flush: true);
      await encoder.addFile(tempDataFile, 'data.json');
      await tempDataFile.delete();
    }

    // 2. Agregar PDFs con reporte de progreso
    int count = 0;
    final total = args.entries.length;

    for (final entry in args.entries) {
      final file = File(entry.sourcePath);
      if (await file.exists()) {
        await encoder.addFile(file, entry.zipEntryName);
      }
      count++;
      args.sendPort.send(count / total);
    }

    encoder.close();
    args.sendPort.send('DONE');
  } catch (e) {
    args.sendPort.send('ERROR: $e');
  }
}

// =============================================================================
// ISOLATE WORKER — UNZIP (para importación de .setlist)
// =============================================================================

class _UnzipSetlistWorkerArgs {
  final String zipPath;
  final String destPath;
  final SendPort sendPort;
  _UnzipSetlistWorkerArgs({
    required this.zipPath,
    required this.destPath,
    required this.sendPort,
  });
}

/// Worker de descompresión ejecutado en un Isolate separado.
/// Mismo protocolo de mensajes que el worker de compresión.
Future<void> _unzipSetlistWorker(_UnzipSetlistWorkerArgs args) async {
  try {
    final inputStream = InputFileStream(args.zipPath);
    final archive = ZipDecoder().decodeBuffer(inputStream);

    final totalFiles = archive.length;
    int count = 0;

    for (final file in archive) {
      if (file.isFile) {
        final destPath = p.join(args.destPath, file.name);
        final parentDir = Directory(p.dirname(destPath));
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        final outputStream = OutputFileStream(destPath);
        file.writeContent(outputStream);
        outputStream.close();
      }
      count++;
      if (count % 5 == 0 || count == totalFiles) {
        args.sendPort.send(count / totalFiles);
      }
    }

    inputStream.close();
    args.sendPort.send('DONE');
  } catch (e) {
    args.sendPort.send('ERROR: $e');
  }
}
