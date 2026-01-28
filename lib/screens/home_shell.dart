import 'package:flutter/material.dart';

import 'setlists/create_setlist_screen.dart';
import 'library/library_screen.dart';
import 'setlists/setlists_screen.dart';
import 'settings/settings_screen.dart';
import '../data/app_data.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _setlistsRevision = 0;

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