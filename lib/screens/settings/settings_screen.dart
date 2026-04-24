import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/backup_manager.dart';
import '../../data/app_data.dart';
import '../../data/repositories/settings_repository.dart';
import '../trash/trash_bin_screen.dart';

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

                _buildSectionHeader('Papelera'),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.orange),
                  title: const Text('Ver Papelera'),
                  subtitle: const Text('Restaurar elementos eliminados'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TrashBinScreen()),
                    );
                  },
                ),
                const Divider(),

                _buildSectionHeader('Sesión'),
                _buildSessionSection(),
                const Divider(),

                // Logout button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _doLogout,
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text(
                        'Cerrar sesión',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Delete account button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _doDeleteAccount,
                      icon: const Icon(Icons.delete_forever, size: 20),
                      label: const Text(
                        'Eliminar cuenta',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      'v1.0.0 - Atril Digital',
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

  Widget _buildSessionSection() {
    final cache = SettingsRepository.instance.loadPermissionCache();

    if (cache == null) {
      return const ListTile(
        leading: Icon(Icons.cloud_off, color: Colors.grey),
        title: Text('Sin verificación'),
        subtitle: Text('Conectate a internet para verificar tu acceso'),
      );
    }

    final d = cache.lastVerified;
    const meses = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
    final lastDate = '${d.day} de ${meses[d.month - 1]} de ${d.year}';
    final daysLeft = cache.daysUntilExpiry;

    // Status color
    final Color statusColor;
    final IconData statusIcon;
    final String statusText;

    if (daysLeft <= 0) {
      statusColor = Colors.redAccent;
      statusIcon = Icons.error_outline;
      statusText = 'Expirado — conectate a internet';
    } else if (daysLeft <= 5) {
      statusColor = const Color(0xFFF59E0B);
      statusIcon = Icons.warning_amber_rounded;
      statusText = '$daysLeft ${daysLeft == 1 ? 'día' : 'días'} restantes';
    } else {
      statusColor = const Color(0xFF4CAF50);
      statusIcon = Icons.check_circle_outline;
      statusText = '$daysLeft días restantes';
    }

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Última verificación online'),
          subtitle: Text(lastDate),
        ),
        ListTile(
          leading: Icon(statusIcon, color: statusColor),
          title: const Text('Próxima verificación requerida'),
          subtitle: Text(
            statusText,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Future<void> _doLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Estás seguro que querés cerrar sesión?\n\n'
          'Tu biblioteca de partituras NO se borra. '
          'Vas a necesitar iniciar sesión de nuevo para acceder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await SettingsRepository.instance.clearPermissionCache();
    await FirebaseAuth.instance.signOut();

    // Pop back to root — AuthGate will handle the rest
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _doDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          '¿Estás seguro que deseas eliminar tu cuenta de forma permanente?\n\n'
          'Esta acción no se puede deshacer y perderás todos tus datos asociados a esta cuenta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).delete();
        await user.delete();
      }
      await SettingsRepository.instance.clearPermissionCache();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por seguridad, debes volver a iniciar sesión antes de eliminar tu cuenta.'),
            duration: Duration(seconds: 5),
          ),
        );
        await SettingsRepository.instance.clearPermissionCache();
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: ${e.message}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error inesperado: $e')));
      }
    }
  }
}