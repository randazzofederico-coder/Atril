import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/app_data.dart';
import '../platform/picked_files.dart';

class ScoreImportLogic {
  
  static Future<void> pickAndImportFiles(BuildContext context, String targetFolderId) async {
    // 1. Permisos básicos
    if (!kIsWeb) await [Permission.storage].request();

    try {
      // 2. Selección. "Descargando..." recién cuando el usuario eligió: el
      //    sistema/navegador puede tardar en bajar archivos de Drive.
      final validPaths = await pickFilesToFs(
        PickKind.pdfs,
        // Todo el proceso se muestra en la barra de progreso inferior.
        onWaiting: () => AppData.backgroundTaskProgress.value = BackgroundTaskStatus(
          0,
          'Esperando a Google Drive… los archivos grandes pueden tardar',
          indeterminate: true,
          onCancel: () {
            cancelPick();
            AppData.backgroundTaskProgress.value = null;
          },
        ),
        onPreparing: (msg, progress, item, itemProgress) => AppData.backgroundTaskProgress.value =
            BackgroundTaskStatus(progress, msg, itemLabel: item, itemProgress: itemProgress),
      );

      // Si el usuario cancela, volvemos a IDLE
      if (validPaths.isEmpty) {
        AppData.backgroundTaskProgress.value = null;
        return;
      }

      // 4. INICIAR IMPORTACIÓN EN "BACKGROUND"
      // "Fire and forget": No usamos await para no bloquear la UI.
      // La barra ImportStatusBar se encargará de mostrar el progreso.
      AppData.importBatchBackground(validPaths, targetFolderId).catchError((e) {
        debugPrint("Error en background import: $e");
        AppData.importState.value = const ImportState(stage: ImportStage.idle);
      });

    } catch (e) {
      // En caso de error crítico antes de empezar
      AppData.importState.value = const ImportState(stage: ImportStage.idle);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar importación: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static Future<void> pickAndImportFolder(BuildContext context, String targetFolderId) async {
    if (kIsWeb) {
      // El navegador no da acceso a carpetas: se eligen varios PDFs.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('En la versión web no se pueden importar carpetas: usá "Importar archivos" (podés elegir varios a la vez).'),
      ));
      return;
    }
    // Permiso especial para Android 10+ (Scoped Storage)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
        if (!status.isGranted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Se requiere acceso total a archivos para importar carpetas.'),
          ));
          return;
        }
      }
    }

    // Activamos estado "Descargando/Buscando"
    AppData.importState.value = const ImportState(stage: ImportStage.picking);

    final String? path = await FilePicker.platform.getDirectoryPath();
    
    if (path == null) {
      // Cancelado
      AppData.importState.value = const ImportState(stage: ImportStage.idle);
      return;
    }

    // 4. INICIAR IMPORTACIÓN EN "BACKGROUND"
    // Ya no mostramos diálogo bloqueante, usamos la barra global.
    AppData.importState.value = const ImportState(stage: ImportStage.idle);

    AppData.importFolderBackground(path, targetFolderId).catchError((e) {
      debugPrint("Error en background folder import: $e");
      AppData.importState.value = const ImportState(stage: ImportStage.idle);
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Importación de carpeta iniciada en segundo plano...')),
      );
    }
  }
}