import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../data/backup_manager.dart';
import '../../data/app_data.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = false;

  Future<void> _doBackup() async {
    setState(() => _loading = true);
    try {
      await BackupManager.instance.createBackup(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup generado correctamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doRestore() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Restaurar Backup'),
        content: const Text(
          'Esta acción BORRARÁ TODA tu biblioteca actual y la reemplazará por el backup.\n\n'
          'No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Restaurar y Borrar Todo'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result == null || result.files.single.path == null) return;
    
    if (!mounted) return;

    setState(() => _loading = true);

    try {
      await BackupManager.instance.restoreBackup(context, result.files.single.path!);
      await AppData.refreshLibrary();
      AppData.triggerNavigationReset();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restauración completada.')),
        );
        Navigator.pop(context); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error crítico restaurando: $e\nReinicia la app.'), 
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Escuchamos cambios para que los switches/sliders y el progreso se actualicen
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppData.settings.themeMode,
        AppData.settings.uiScale,
        AppData.settings.keepScreenOn,
        AppData.settings.invertPdfColors,
        AppData.backgroundTaskProgress, // Escuchar progreso global
      ]),
      builder: (context, _) {
        final taskStatus = AppData.backgroundTaskProgress.value;
        final isBusy = _loading || taskStatus != null;

        return Scaffold(
        appBar: AppBar(title: const Text('Configuración')),
        body: isBusy 
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   const CircularProgressIndicator(),
                   const SizedBox(height: 16),
                   if (taskStatus != null) ...[
                      Text(taskStatus.message),
                      const SizedBox(height: 8),
                      Text(taskStatus.percentage),
                   ] else 
                      const Text('Cargando...'),
                ],
              ),
            )
          : ListView(
              children: [
                _buildSectionHeader('Apariencia'),
                _buildAppearanceSection(),
                const Divider(),

                _buildSectionHeader('Lectura'),
                _buildReadingSection(),
                const Divider(),

                _buildSectionHeader('Datos'),
                _buildDataSection(),
                const Divider(),

                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      'v1.2 - Atril Digital',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
      );
      } 
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14, 
          fontWeight: FontWeight.bold, 
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildAppearanceSection() {
    final isDark = AppData.settings.themeMode.value == ThemeMode.dark;
    final scale = AppData.settings.uiScale.value;

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode),
          title: const Text('Modo Oscuro'),
          subtitle: const Text('Interfaz con colores oscuros'),
          value: isDark,
          onChanged: (val) {
            AppData.settings.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
          },
        ),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: const Text('Tamaño de Interfaz'),
          subtitle: Slider(
            value: scale,
            min: 0.8,
            max: 1.5,
            divisions: 7,
            label: '${(scale * 100).round()}%',
            onChanged: (val) {
              AppData.settings.setUiScale(val);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReadingSection() {
    final keepOn = AppData.settings.keepScreenOn.value;
    final invertPdf = AppData.settings.invertPdfColors.value;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.screen_lock_portrait),
          title: const Text('Mantener pantalla encendida'),
          subtitle: const Text('Evita que el dispositivo se bloquee al leer'),
          value: keepOn,
          onChanged: (val) {
            AppData.settings.setKeepScreenOn(val);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.invert_colors),
          title: const Text('Invertir colores de PDF'),
          subtitle: const Text('Simular modo noche en partituras'),
          value: invertPdf,
          onChanged: (val) {
            AppData.settings.setInvertPdfColors(val);
          },
        ),
      ],
    );
  }

  Widget _buildDataSection() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.drive_file_move_outline),
          title: const Text('Exportar para PC'),
          subtitle: const Text('Guardar biblioteca como carpeta ZIP'),
          onTap: _doExportZip,
        ),
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('Crear Backup Completo'),
          subtitle: const Text('Guardar estado actual (.atril)'),
          onTap: _doBackup,
        ),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('Importar Backup'),
          subtitle: const Text('Agregar contenido de un backup a la biblioteca actual'),
          onTap: _doImport,
        ),
        ListTile(
          leading: const Icon(Icons.restore, color: Colors.redAccent),
          title: const Text('Restaurar Backup (Destructivo)'),
          subtitle: const Text('Borrar TODO y reemplazar con backup'),
          onTap: _doRestore,
        ),
      ],
    );
  }

  Future<void> _doExportZip() async {
    setState(() => _loading = true);
    try {
      await BackupManager.instance.exportLibraryToZip(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exportación lista.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exportando: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doImport() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;
    
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      await BackupManager.instance.importBackup(context, result.files.single.path!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contenido, importado en carpeta "Backup Importado".')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importando: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}