import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'setlists/create_setlist_screen.dart';
import 'setlists/setlist_detail_screen.dart';
import 'library/library_screen.dart';
import 'setlists/setlists_screen.dart';
import 'settings/settings_screen.dart';
import '../data/app_data.dart';
import '../data/backup_manager.dart';
import '../data/file_receiver_channel.dart';

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
  }

  // ---------------------------------------------------------------------------
  // RECEPCIÓN DE ARCHIVOS EXTERNOS (.setlist, .atril)
  // ---------------------------------------------------------------------------

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

    if (fileType == 'setlist') {
      await _importSetlistFile(path);
    } else if (fileType == 'atril' || ext == '.atril') {
      if (!mounted) return;
      await BackupManager.instance.importBackup(context, path);
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
      final file = File(path);
      if (!await file.exists()) return null;

      // Leer los primeros bytes para verificar si es un ZIP (PK header)
      final bytes = await file.openRead(0, 4).fold<List<int>>(
        [],
        (prev, chunk) => prev..addAll(chunk),
      );
      if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
        return null; // No es un ZIP
      }

      // Es un ZIP — verificar si contiene data.json (= setlist)
      final archive = ZipDecoder().decodeBuffer(InputFileStream(path));
      for (final entry in archive) {
        if (entry.name == 'data.json') return 'setlist';
      }

      // Es un ZIP pero sin data.json — podría ser un .atril backup
      return 'atril';
    } catch (e) {
      debugPrint('[HomeShell] Error detectando tipo: $e');
      return null;
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
          // Global Progress
          ValueListenableBuilder<BackgroundTaskStatus?>(
            valueListenable: AppData.backgroundTaskProgress,
            builder: (context, status, _) {
               if (status == null) return const SizedBox.shrink();
               return Column(
                 mainAxisSize: MainAxisSize.min,
                 crossAxisAlignment: CrossAxisAlignment.stretch,
                 children: [
                   LinearProgressIndicator(value: status.progress, minHeight: 4),
                   Container(
                     color: Theme.of(context).colorScheme.surfaceContainer,
                     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                     child: Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                         Text(
                           status.message,
                           style: Theme.of(context).textTheme.bodySmall,
                         ),
                         Text(
                           status.percentage,
                           style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                         ),
                       ],
                     ),
                   ),
                 ],
               );
            },
          ),
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