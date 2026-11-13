import 'package:fede_apps_core/fede_apps_core.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/backup_manager.dart';
import '../../data/file_receiver_channel.dart';
import '../../platform/picked_files.dart';
import '../../platform/pwa/pwa_install_service.dart';
import '../../data/app_data.dart';
import '../trash/trash_bin_screen.dart';
import 'diag_log_screen.dart';
import 'drive_backup_screen.dart';
import '../library/export_actions.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = false;

  /// El login con Google (google_sign_in) solo existe en Android, iOS y web.
  static bool get _accountSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    // Sugerencia ocasional de las otras apps (respeta límites del ecosistema).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        EcosystemPrompts.maybeShowAppsPrompt(context, currentApp: FedeApp.atril);
      }
    });
  }

  Future<void> _doBackup() async {
    setState(() => _loading = true);
    try {
      await BackupManager.instance.createBackup();
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

    final paths = await pickFilesToFs(PickKind.atrilFile, onWaiting: _showWaitingDrive);

    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (paths.isEmpty) return;
    
    if (!mounted) return;

    setState(() => _loading = true);

    try {
      await BackupManager.instance.restoreBackup(paths.single);
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
            content: Text('No se pudo restaurar: $e\nTu biblioteca anterior se mantuvo.'), 
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
        // Las tareas largas (backup, exportar...) no bloquean Ajustes: el
        // progreso se muestra arriba y solo se desactiva la sección Datos.
        body: Column(
          children: [
            if (isBusy) _buildBusyBanner(taskStatus),
            Expanded(
              child: ListView(
              children: [
                // Cuenta del ecosistema: OPCIONAL. Sin cuenta todo funciona
                // igual (la biblioteca es local).
                if (_accountSupported) ...[
                  _buildSectionHeader('Cuenta'),
                  const AccountSection(hasLibrary: false, showHeader: false),
                  const Divider(),
                ],

                if (kIsWeb) ...[
                  _buildSectionHeader('App web'),
                  _buildWebAppSection(),
                  const Divider(),
                ],

                _buildSectionHeader('Apariencia'),
                _buildAppearanceSection(),
                const Divider(),

                _buildSectionHeader('Lectura'),
                _buildReadingSection(),
                const Divider(),

                _buildSectionHeader('Datos'),
                IgnorePointer(
                  ignoring: isBusy,
                  child: Opacity(opacity: isBusy ? 0.4 : 1, child: _buildDataSection()),
                ),
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

                _buildSectionHeader('Más apps'),
                const EcosystemSection(
                  currentApp: FedeApp.atril,
                  showHeader: false,
                  showSite: false, // el sitio ya está en "Acerca de"
                ),
                const Divider(),

                _buildSectionHeader('Acerca de'),

                ListTile(

                  leading: const Icon(Icons.bug_report_outlined),

                  title: const Text('Registro de diagnóstico'),

                  subtitle: const Text('Para enviar si algo no funciona bien'),

                  onTap: () => Navigator.push(

                    context,

                    MaterialPageRoute(builder: (_) => const DiagLogScreen()),

                  ),

                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Atril Digital'),
                  subtitle: const Text('federicorandazzo.com.ar/apps/'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () async {
                    final url = Uri.parse('https://federicorandazzo.com.ar/apps/');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    // Versión real del build (la de pubspec.yaml)
                    child: FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snap) {
                        final info = snap.data;
                        final version = info == null
                            ? ''
                            : 'v${info.version} (${info.buildNumber}) - ';
                        return Text(
                          '${version}Atril Digital',
                          style: const TextStyle(color: Colors.grey),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            ),
          ],
        ),
      );
      } 
    );
  }

  Widget _buildBusyBanner(BackgroundTaskStatus? status) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: status == null || status.indeterminate ? null : status.progress,
            minHeight: 3,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              status == null
                  ? 'Trabajando...'
                  : status.indeterminate
                      ? status.message
                      : '${status.message}  ${status.percentage}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
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

  /// El navegador todavía baja el archivo elegido (Drive): avisar.
  void _showWaitingDrive() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(minutes: 5),
      content: const Text('Esperando a Google Drive… los archivos grandes pueden tardar'),
      action: SnackBarAction(label: 'Cancelar', onPressed: cancelPick),
    ));
  }

  /// Abre un .atrilfolder/.setlist/.atril elegido a mano (en web es la única
  /// forma de recibirlos). Lo procesa HomeShell, igual que si llegara desde
  /// otra app.
  Future<void> _openAtrilFile() async {
    final handler = FileReceiverChannel.onFileReceived;
    if (handler == null) return;
    final paths = await pickFilesToFs(PickKind.atrilFile, onWaiting: _showWaitingDrive);
    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (paths.isEmpty || !mounted) return;
    Navigator.pop(context); // volver a la biblioteca: ahí se ve el resultado
    handler(paths.single);
  }

  /// Solo web: instalar la PWA y aviso de almacenamiento en iOS.
  Widget _buildWebAppSection() {
    final pwa = PwaInstallService();
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    return ValueListenableBuilder<bool>(
      valueListenable: pwa.isInstalled,
      builder: (context, installed, _) {
        if (installed) {
          return const ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green),
            title: Text('Atril está instalado'),
            subtitle: Text('Tu biblioteca se guarda en este dispositivo.'),
          );
        }
        return ValueListenableBuilder<bool>(
          valueListenable: pwa.canInstall,
          builder: (context, canInstall, _) {
            if (canInstall) {
              return ListTile(
                leading: const Icon(Icons.install_mobile),
                title: const Text('Instalar Atril'),
                subtitle: const Text('Abrilo como una app y sin conexión'),
                onTap: pwa.promptInstall,
              );
            }
            return ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.orange),
              title: const Text('Instalá Atril en tu dispositivo'),
              subtitle: Text(isIos
                  ? 'En Safari: Compartir → "Agregar a inicio". Si no la instalás, '
                      'Safari puede borrar tu biblioteca tras unos días sin uso.'
                  : 'Desde el menú del navegador: "Instalar app" o "Agregar a la pantalla de inicio".'),
            );
          },
        );
      },
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
          leading: const Icon(Icons.cloud_upload_outlined, color: Colors.blue),
          title: const Text('Backup en Google Drive'),
          subtitle: const Text('Respaldo automático en tu Drive, por dispositivo'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DriveBackupScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('Abrir archivo de Atril'),
          subtitle: const Text('Carpeta (.atrilfolder), setlist (.setlist) o backup (.atril)'),
          onTap: _openAtrilFile,
        ),
        ListTile(
          leading: const Icon(Icons.drive_file_move_outline),
          title: const Text('Exportar para PC'),
          subtitle: const Text('Guardar biblioteca como carpeta ZIP (con o sin anotaciones)'),
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
      final done = await ExportActions.exportLibraryZip(context);
      if (done && mounted) {
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
    final paths = await pickFilesToFs(PickKind.atrilFile, onWaiting: _showWaitingDrive);
    if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (paths.isEmpty) return;
    
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      final report = await BackupManager.instance.importBackup(paths.single);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${report.summary} (carpeta "Backup Importado")')),
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