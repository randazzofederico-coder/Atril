import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../backup/drive_auth.dart';
import '../../backup/drive_backup_service.dart';
import '../../data/app_data.dart';

/// Ajustes → Backup en Google Drive.
class DriveBackupScreen extends StatefulWidget {
  const DriveBackupScreen({super.key});

  @override
  State<DriveBackupScreen> createState() => _DriveBackupScreenState();
}

class _DriveBackupScreenState extends State<DriveBackupScreen> {
  final _service = DriveBackupService.instance;
  List<DriveBackupSlot>? _slots;
  int? _totalBytes;
  String? _slotsError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.init().then((_) {
      if (mounted) setState(() {});
      if (_service.enabled) _loadSlots();
    });
  }

  Future<void> _loadSlots() async {
    setState(() => _slotsError = null);
    try {
      final (slots, total) = await _service.listSlots();
      if (mounted) setState(() {
        _slots = slots;
        _totalBytes = total;
      });
    } catch (e) {
      if (mounted) setState(() => _slotsError = '$e');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _date(DateTime? d) =>
      d == null ? 'nunca' : DateFormat('dd/MM/yyyy HH:mm').format(d);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup en Google Drive')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: _service.enabled ? _buildEnabled() : _buildIntro(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Desactivado: explicación + activar
  // ---------------------------------------------------------------------------

  Widget _buildIntro() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.cloud_upload_outlined, size: 64),
        const SizedBox(height: 16),
        Text('Respaldá tu biblioteca en tu Google Drive',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        const _Bullet(Icons.lock_outline,
            'Se guarda en una carpeta oculta de TU Drive que solo Atril puede ver. '
            'No ocupa espacio en ningún servidor nuestro.'),
        const _Bullet(Icons.sync_alt,
            'Es un respaldo en un solo sentido: este dispositivo sube sus cambios. '
            'Nada de lo que pase en Drive borra o modifica tu biblioteca.'),
        const _Bullet(Icons.devices,
            'Cada dispositivo tiene su propio respaldo. Desde uno nuevo podés traer '
            'el de cualquier otro (reemplazando o agregando).'),
        const _Bullet(Icons.data_usage,
            'Usa espacio de tu Drive (los PDFs se guardan una sola vez aunque estén en '
            'varios dispositivos). Podés ver cuánto ocupa y borrarlo cuando quieras.'),
        const _Bullet(Icons.wifi,
            'Corre con la app abierta, unos minutos después de cada cambio, '
            'nunca durante el modo en vivo y, si querés, solo con Wi-Fi.'),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_done_outlined),
          label: const Text('Activar con mi cuenta de Google'),
          onPressed: () => _run(() async {
            final ok = await _service.enable();
            if (!ok || !mounted) return;
            setState(() {});
            await _loadSlots();
          }),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Activado
  // ---------------------------------------------------------------------------

  Widget _buildEnabled() {
    return RefreshIndicator(
      onRefresh: _loadSlots,
      child: ListView(
        children: [
          ValueListenableBuilder<DriveBackupStatus>(
            valueListenable: _service.status,
            builder: (context, st, _) => _buildStatus(st),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Respaldar ahora'),
            onTap: () => _run(() async {
              await _service.backupNow(manual: true);
              await _loadSlots();
            }),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('Solo con Wi-Fi'),
            subtitle: const Text('Los respaldos automáticos esperan una red Wi-Fi'),
            value: _service.wifiOnly,
            onChanged: (v) async {
              await _service.setWifiOnly(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.pause_circle_outline),
            title: const Text('Pausar respaldos automáticos'),
            value: _service.paused,
            onChanged: (v) async {
              await _service.setPaused(v);
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Nombre de este dispositivo'),
            subtitle: Text(_service.deviceName),
            onTap: _renameDevice,
          ),
          const Divider(),
          ListTile(
            title: const Text('Respaldos guardados'),
            subtitle: Text(_totalBytes == null
                ? 'Cargando...'
                : 'Atril usa ${_size(_totalBytes!)} de tu Drive'),
            trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSlots),
          ),
          if (_slotsError != null)
            ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text(_slotsError!),
            ),
          for (final s in _slots ?? const <DriveBackupSlot>[]) _buildSlot(s),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Desactivar y borrar mis respaldos', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Libera el espacio en Drive. Tu biblioteca no se toca.'),
            onTap: _disable,
          ),
          if (DriveAuth.instance.email != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Cuenta: ${DriveAuth.instance.email}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _buildStatus(DriveBackupStatus st) {
    final last = 'Último respaldo: ${_date(_service.lastBackupAt)}';
    switch (st.state) {
      case DriveBackupState.running:
        return ListTile(
          leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text(st.message ?? 'Respaldando...'),
          subtitle: st.progress == null ? null : LinearProgressIndicator(value: st.progress),
        );
      case DriveBackupState.needsAuth:
        return ListTile(
          leading: const Icon(Icons.link_off, color: Colors.orange),
          title: const Text('Hay que reconectar la cuenta'),
          subtitle: Text('${st.message ?? ''}\n$last'),
          isThreeLine: true,
          trailing: FilledButton(
            onPressed: () => _run(() async => _service.reconnect()),
            child: const Text('Reconectar'),
          ),
        );
      case DriveBackupState.error:
        return ListTile(
          leading: const Icon(Icons.cloud_off, color: Colors.red),
          title: const Text('No se pudo respaldar'),
          subtitle: Text('${st.message ?? ''}\n$last'),
          isThreeLine: true,
        );
      case DriveBackupState.idle:
      case DriveBackupState.disabled:
        return ListTile(
          leading: Icon(_service.paused ? Icons.pause_circle : Icons.cloud_done, color: Colors.green),
          title: Text(_service.paused ? 'Respaldo en pausa' : 'Respaldo activo'),
          subtitle: Text(last),
        );
    }
  }

  Widget _buildSlot(DriveBackupSlot s) {
    return ListTile(
      leading: Icon(s.platform == 'web' ? Icons.language : Icons.smartphone),
      title: Text(s.isThisDevice ? '${s.deviceName} (este dispositivo)' : s.deviceName),
      subtitle: Text('${s.docCount} partituras · ${_size(s.totalBytes)} · ${_date(s.updatedAt)}'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'restore') _restore(s, previous: false);
          if (v == 'restore_prev') _restore(s, previous: true);
          if (v == 'delete') _deleteSlot(s);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'restore', child: Text('Traer este respaldo')),
          if (s.hasPrevious)
            const PopupMenuItem(value: 'restore_prev', child: Text('Traer la versión anterior')),
          if (!s.isThisDevice)
            const PopupMenuItem(
              value: 'delete',
              child: Text('Borrar este respaldo', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  Future<void> _renameDevice() async {
    final ctrl = TextEditingController(text: _service.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre de este dispositivo'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Ej: Tablet Samsung')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await _service.setDeviceName(name);
    if (mounted) setState(() {});
  }

  Future<void> _restore(DriveBackupSlot s, {required bool previous}) async {
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Traer "${s.deviceName}"${previous ? ' (versión anterior)' : ''}'),
        children: [
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Agregar a mi biblioteca'),
            subtitle: Text('Todo entra en una carpeta "Backup de ${s.deviceName}"'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          if (_service.canReplace)
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.orange),
              title: const Text('Reemplazar mi biblioteca'),
              subtitle: const Text('Si algo falla, vuelve a la biblioteca actual'),
              onTap: () => Navigator.pop(ctx, true),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ),
        ],
      ),
    );
    if (replace == null || !mounted) return;
    if (replace) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Reemplazar la biblioteca?'),
          content: const Text('La biblioteca de este dispositivo se reemplaza por el respaldo elegido.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reemplazar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(() async {
      final msg = await _service.restore(s, replace: replace, previous: previous);
      if (replace) AppData.triggerNavigationReset();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  Future<void> _deleteSlot(DriveBackupSlot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Borrar el respaldo de "${s.deviceName}"?'),
        content: const Text('Los PDFs que solo usaba ese respaldo se liberan en 30 días.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _service.deleteSlot(s);
      await _loadSlots();
    });
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Desactivar el backup?'),
        content: const Text(
          'Se borran de tu Drive TODOS los respaldos de Atril (de todos tus dispositivos). '
          'La biblioteca de este dispositivo no se toca.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar y borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _service.disable(deleteBackups: true);
      if (mounted) setState(() {});
    });
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Bullet(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
