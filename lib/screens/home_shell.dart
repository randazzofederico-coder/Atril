import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'setlists/create_setlist_screen.dart';
import 'setlists/setlist_detail_screen.dart';
import 'library/library_screen.dart';
import 'setlists/setlists_screen.dart';
import 'settings/settings_screen.dart';
import '../backup/drive_backup_service.dart';
import '../data/app_data.dart';
import '../data/backup_manager.dart';
import '../data/db/db_connection.dart' show kMainDbFileName;
import '../data/file_receiver_channel.dart';
import '../data/folder_share_manager.dart';
import 'library/folder_picker_screen.dart';
import '../platform/busy_indicator.dart';
import '../widgets/background_task_bar.dart';
import '../platform/zip/zip_tools.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _setlistsRevision = 0;

  @override
  void initState() {
    super.initState();
    _setupFileReceiver();
    // Backup en Drive (si está activado). HomeShell se muestra con AppData listo.
    DriveBackupService.instance.init();
    // Web: indicador CSS que no se congela mientras haya una tarea en curso.
    AppData.backgroundTaskProgress.addListener(_syncWebBusy);
  }

  // ---------------------------------------------------------------------------
  // RECEPCIÓN DE ARCHIVOS EXTERNOS (.setlist, .atril)
  // ---------------------------------------------------------------------------

  void _syncWebBusy() => setWebBusy(AppData.backgroundTaskProgress.value != null);

  @override
  void dispose() {
    AppData.backgroundTaskProgress.removeListener(_syncWebBusy);
    super.dispose();
  }

  void _setupFileReceiver() {
    FileReceiverChannel.onFileReceived = _handleIncomingFile;
    // Esperar un frame para que el context esté listo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FileReceiverChannel.init();
    });
  }

  Future<void> _handleIncomingFile(String path) async {
    if (!mounted) return;

    final ext = p.extension(path).toLowerCase();
    debugPrint('[HomeShell] Archivo recibido: $path (ext: $ext)');

    // Detectar tipo por CONTENIDO, no por extensión.
    // WhatsApp y otros content providers pueden cambiar la extensión.
    final fileType = await _detectFileType(path);
    debugPrint('[HomeShell] Tipo detectado: $fileType');

    if (fileType == 'atrilfolder') {
      await _importAtrilFolderFile(path);
    } else if (fileType == 'setlist') {
      await _importSetlistFile(path);
    } else if (fileType == 'atril' || ext == '.atril') {
      if (!mounted) return;
      await _importReceivedBackup(path);
    } else {
      debugPrint('[HomeShell] Tipo no reconocido (ext: $ext)');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tipo de archivo no reconocido: ${p.basename(path)}')),
      );
    }
  }

  /// Detecta el tipo de archivo por su contenido.
  /// Retorna 'setlist' si es un ZIP con data.json,
  /// 'atril' si parece un backup, o null si no se reconoce.
  Future<String?> _detectFileType(String path) async {
    try {
      // null = no existe o no es un ZIP
      final names = await ZipTools.listEntryNames(path);
      if (names == null) return null;

      // Es un ZIP — carpeta compartida (folder.json) o setlist (data.json)
      if (names.contains(FolderShareManager.metadataName)) return 'atrilfolder';
      if (names.contains('data.json')) return 'setlist';
      // Solo es un backup si trae la base de datos de Atril
      if (!names.contains(kMainDbFileName)) return null;

      // Es un ZIP pero sin data.json — podría ser un .atril backup
      return 'atril';
    } catch (e) {
      debugPrint('[HomeShell] Error detectando tipo: $e');
      return null;
    }
  }

  /// Backup .atril recibido desde otra app: se confirma antes de importar.
  Future<void> _importReceivedBackup(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar backup'),
        content: const Text(
          'Se va a agregar el contenido de este backup a tu biblioteca, en una '
          'carpeta nueva "Backup Importado". No se borra ni reemplaza nada.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = await BackupManager.instance.importBackup(path);
      messenger.showSnackBar(SnackBar(content: Text(report.summary)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error importando backup: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Carpeta compartida (.atrilfolder): el usuario elige dónde ubicarla.
  Future<void> _importAtrilFolderFile(String filePath) async {
    final messenger = ScaffoldMessenger.of(context);
    final targetId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const FolderPickerScreen(
          ignoreFolderIds: [],
          actionTitle: 'Importar carpeta',
          confirmLabel: 'Importar aquí',
        ),
      ),
    );
    if (targetId == null || !mounted) return;
    try {
      final folderId = await FolderShareManager.instance.importAtrilFolder(filePath, targetId);
      if (!mounted) return;
      setState(() => _index = 0); // tab Biblioteca
      final name = AppData.getFolderById(folderId)?.name ?? 'Carpeta';
      messenger.showSnackBar(SnackBar(content: Text('Carpeta "$name" importada.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error importando carpeta: $e')));
    }
  }

  Future<void> _importSetlistFile(String filePath) async {
    try {
      final setlistId = await ExportManager.instance.importSetlistFile(filePath);
      if (!mounted || setlistId == null) return;

      // Cambiar a la tab Setlists
      setState(() {
        _index = 1;
        _setlistsRevision++;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('¡Setlist importado correctamente!'),
          action: SnackBarAction(
            label: 'Ver',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SetlistDetailScreen(setlistId: setlistId),
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error importando setlist: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // CREAR SETLIST
  // ---------------------------------------------------------------------------

  Future<void> _createSetlistFlow() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateSetlistScreen()),
    );
    if (!mounted) return;
    if (created == true) {
      setState(() => _setlistsRevision++);
    }
  }

  AppBar? _buildAppBar() {
    if (_index == 0) {
      return null;
    }

    return AppBar(
      title: const Text('Setlists'),
      centerTitle: false, 
      actions: [
        IconButton(
          tooltip: 'Configuración',
          icon: const Icon(Icons.settings),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Crear setlist',
          onPressed: _createSetlistFlow,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // CAMBIO IMPORTANTE:
    // Usamos IndexedStack para mantener el estado de las pantallas vivo
    // aunque no las estemos viendo.
    final pages = [
      const LibraryScreen(),
      SetlistsScreen(key: ValueKey(_setlistsRevision)),
    ];

    return Scaffold(
      appBar: _buildAppBar(),
      // ANTES: body: pages[_index], 
      // AHORA:
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progreso global (misma barra en toda la app)
          const BackgroundTaskBar(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music),
                label: 'Biblioteca',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music),
                label: 'Setlists',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
