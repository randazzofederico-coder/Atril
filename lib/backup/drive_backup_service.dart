import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_data.dart';
import '../data/backup_manager.dart';
import '../data/db/db_connection.dart';
import '../platform/background.dart';
import '../platform/fs/atril_fs.dart';
import 'drive_auth.dart';
import 'drive_client.dart';

enum DriveBackupState { disabled, idle, running, needsAuth, error }

class DriveBackupStatus {
  final DriveBackupState state;
  final String? message;
  final double? progress;
  const DriveBackupStatus(this.state, {this.message, this.progress});
}

/// Respaldo de un dispositivo guardado en Drive ("ranura").
class DriveBackupSlot {
  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime? updatedAt;
  final int docCount;
  final int totalBytes;
  final bool hasPrevious;
  final bool isThisDevice;
  const DriveBackupSlot({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.updatedAt,
    required this.docCount,
    required this.totalBytes,
    required this.hasPrevious,
    required this.isThisDevice,
  });
}

/// Backup en la carpeta oculta (`appDataFolder`) del Drive del usuario.
///
/// - **Un solo sentido**: el dispositivo sube; Drive nunca modifica la
///   biblioteca local. Restaurar es siempre una acción manual.
/// - **Una ranura por dispositivo**: `dev_<id>.sqlite` (base) +
///   `dev_<id>.json` (manifiesto), y la versión anterior `*.prev.*`.
/// - **PDFs deduplicados por contenido**: `blob_<sha256>.pdf`, compartidos por
///   todas las ranuras. Un blob que ninguna ranura usa se borra a los 30 días.
/// - Corre con la app abierta: unos minutos después de un cambio, al abrir y
///   cada tanto; nunca durante el modo en vivo; opcionalmente solo con Wi-Fi.
class DriveBackupService {
  DriveBackupService._();
  static final DriveBackupService instance = DriveBackupService._();

  /// Lo activa la pantalla del modo en vivo: mientras sea true no se respalda.
  static final ValueNotifier<bool> liveModeActive = ValueNotifier(false);

  final ValueNotifier<DriveBackupStatus> status =
      ValueNotifier(const DriveBackupStatus(DriveBackupState.disabled));

  final DriveClient _drive = DriveClient();

  static const _kEnabled = 'drive_backup_enabled';
  static const _kPaused = 'drive_backup_paused';
  static const _kWifiOnly = 'drive_backup_wifi_only';
  static const _kDeviceId = 'drive_backup_device_id';
  static const _kDeviceName = 'drive_backup_device_name';
  static const _kLastAt = 'drive_backup_last_at';
  static const _kLastSignature = 'drive_backup_last_signature';
  static const _hashCacheFile = 'backup_hash_cache.json';
  static const _orphanDays = 30;

  SharedPreferences? _prefs;
  Timer? _periodic;
  Timer? _debounce;
  bool _running = false;
  bool _initialized = false;

  // ---------------------------------------------------------------------------
  // Configuración
  // ---------------------------------------------------------------------------

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  bool get enabled => _prefs?.getBool(_kEnabled) ?? false;
  bool get paused => _prefs?.getBool(_kPaused) ?? false;
  bool get wifiOnly => _prefs?.getBool(_kWifiOnly) ?? true;
  String get deviceName => _prefs?.getString(_kDeviceName) ?? _defaultDeviceName();
  DateTime? get lastBackupAt {
    final ms = _prefs?.getInt(_kLastAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  String get _deviceId => _prefs!.getString(_kDeviceId)!;

  static String _defaultDeviceName() {
    if (kIsWeb) return 'Navegador';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iPhone/iPad',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'Mac',
      _ => 'Dispositivo',
    };
  }

  static String get _platformLabel => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<void> setWifiOnly(bool v) async => (await _p).setBool(_kWifiOnly, v);

  Future<void> setPaused(bool v) async {
    await (await _p).setBool(_kPaused, v);
    _refreshIdleStatus();
    if (!v) schedule(const Duration(seconds: 5));
  }

  Future<void> setDeviceName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    await (await _p).setString(_kDeviceName, n);
    // El nombre viaja en el manifiesto: forzar un respaldo para actualizarlo.
    await (await _p).remove(_kLastSignature);
    schedule(const Duration(seconds: 5));
  }

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  /// Llamar al iniciar la app (después de AppData.init). No falla nunca.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await _p;
    if (prefs.getString(_kDeviceId) == null) {
      await prefs.setString(_kDeviceId, AppData.newId(prefix: 'dev'));
    }
    if (!enabled) return;
    _startScheduler();
    _refreshIdleStatus();
    schedule(const Duration(minutes: 1));
  }

  /// Activa el backup: conecta la cuenta (interactivo) y hace el primero.
  Future<bool> enable() async {
    final ok = await DriveAuth.instance.connect();
    if (!ok) return false;
    final prefs = await _p;
    await prefs.setBool(_kEnabled, true);
    await prefs.setBool(_kPaused, false);
    await prefs.remove(_kLastSignature);
    _startScheduler();
    unawaited(backupNow(manual: true));
    return true;
  }

  /// Reconectar tras un token vencido (web) o revocado.
  Future<bool> reconnect() async {
    final ok = await DriveAuth.instance.connect();
    if (ok) unawaited(backupNow(manual: true));
    return ok;
  }

  /// Desactiva. Si [deleteBackups], borra TODO lo que Atril guardó en Drive
  /// (de todos los dispositivos).
  Future<void> disable({required bool deleteBackups}) async {
    if (deleteBackups) {
      final files = await _drive.listAll();
      for (final f in files) {
        await _drive.delete(f.id);
      }
    }
    _periodic?.cancel();
    _debounce?.cancel();
    final prefs = await _p;
    await prefs.setBool(_kEnabled, false);
    await prefs.remove(_kLastSignature);
    await prefs.remove(_kLastAt);
    await DriveAuth.instance.disconnect();
    status.value = const DriveBackupStatus(DriveBackupState.disabled);
  }

  void _startScheduler() {
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 10), (_) => _autoRun());
    AppData.libraryRevision.removeListener(_onLibraryChanged);
    AppData.setlistsRevision.removeListener(_onLibraryChanged);
    AppData.libraryRevision.addListener(_onLibraryChanged);
    AppData.setlistsRevision.addListener(_onLibraryChanged);
  }

  void _onLibraryChanged() => schedule(const Duration(minutes: 3));

  /// Programa un respaldo automático dentro de [delay] (reinicia la espera).
  void schedule(Duration delay) {
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(delay, _autoRun);
  }

  Future<void> _autoRun() async {
    if (!enabled || paused || _running) return;
    if (liveModeActive.value) {
      schedule(const Duration(minutes: 5));
      return;
    }
    if (wifiOnly && !await _onWifi()) return;
    await backupNow();
  }

  Future<bool> _onWifi() async {
    if (kIsWeb) return true; // el navegador no informa el tipo de red de forma fiable
    try {
      final r = await Connectivity().checkConnectivity();
      return r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return true;
    }
  }

  void _refreshIdleStatus() {
    if (!enabled) {
      status.value = const DriveBackupStatus(DriveBackupState.disabled);
    } else if (status.value.state != DriveBackupState.running) {
      status.value = DriveBackupStatus(
        DriveBackupState.idle,
        message: paused ? 'En pausa' : null,
      );
    }
  }

  void _progress(String message, [double? progress]) =>
      status.value = DriveBackupStatus(DriveBackupState.running, message: message, progress: progress);

  // ---------------------------------------------------------------------------
  // Respaldo
  // ---------------------------------------------------------------------------

  /// Respaldar ahora. [manual]: ignora "solo Wi-Fi" y sube aunque no haya
  /// cambios detectados.
  Future<void> backupNow({bool manual = false}) async {
    if (!enabled || _running) return;
    _running = true;
    String? snapshot;
    try {
      _progress('Preparando respaldo...');
      final prefs = await _p;
      final devId = _deviceId;

      // 1. Base de datos (copia consistente) y PDFs con su hash
      snapshot = p.join(await fs.tempPath(), 'atril_backup_drive_${DateTime.now().millisecondsSinceEpoch}.sqlite');
      await snapshotDatabaseTo(AppData.db, snapshot);
      final dbBytes = await fs.readBytes(snapshot);
      final dbHash = sha256.convert(dbBytes).toString();

      final docs = await AppData.db.getAllDocs(); // incluye la papelera
      final docHashes = <String, String>{}; // internalRelPath -> sha256
      final sizes = <String, int>{};
      final cache = await _loadHashCache();
      for (var i = 0; i < docs.length; i++) {
        final rel = docs[i].internalRelPath.replaceAll('\\', '/');
        final abs = AppData.storage.absPathFromRelPath(docs[i].internalRelPath);
        if (!await fs.fileExists(abs)) continue;
        _progress('Revisando partituras (${i + 1}/${docs.length})...', (i + 1) / docs.length * 0.2);
        final h = await _hashOf(abs, rel, cache);
        docHashes[rel] = h.$1;
        sizes[h.$1] = h.$2;
      }
      await _saveHashCache(cache);

      final signature = sha256
          .convert(utf8.encode('$dbHash|${(docHashes.keys.toList()..sort()).map((k) => '$k=${docHashes[k]}').join(',')}'))
          .toString();
      if (!manual && prefs.getString(_kLastSignature) == signature) {
        _refreshIdleStatus();
        return; // nada cambió
      }

      // 2. Subir los PDFs que falten en Drive
      _progress('Conectando con Google Drive...', 0.2);
      final files = await _drive.listAll();
      final byName = {for (final f in files) f.name: f};
      final missing = docHashes.values.toSet().where((h) => !byName.containsKey(_blobName(h))).toList();
      final relByHash = {for (final e in docHashes.entries) e.value: e.key};
      for (var i = 0; i < missing.length; i++) {
        final h = missing[i];
        _progress('Subiendo partituras (${i + 1}/${missing.length})...', 0.2 + 0.7 * (i + 1) / missing.length);
        final bytes = await fs.readBytes(AppData.storage.absPathFromRelPath(relByHash[h]!));
        await _drive.create(_blobName(h), bytes, mimeType: 'application/pdf', appProperties: {'kind': 'blob'});
      }

      // 3. Rotar: actual -> anterior, y subir la nueva versión
      _progress('Guardando el estado de la biblioteca...', 0.92);
      final manifest = jsonEncode({
        'version': 1,
        'deviceId': devId,
        'deviceName': deviceName,
        'platform': _platformLabel,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'docCount': docs.where((d) => !d.isDeleted).length,
        'totalBytes': sizes.values.fold<int>(0, (a, b) => a + b) + dbBytes.length,
        'docs': docHashes,
      });
      for (final suffix in const ['.sqlite', '.json']) {
        final prev = byName['dev_$devId.prev$suffix'];
        final cur = byName['dev_$devId$suffix'];
        if (cur != null) {
          if (prev != null) await _drive.delete(prev.id);
          await _drive.updateMetadata(cur.id, name: 'dev_$devId.prev$suffix');
        }
      }
      await _drive.create('dev_$devId.sqlite', dbBytes, appProperties: {'kind': 'db', 'device': devId});
      await _drive.create('dev_$devId.json', Uint8List.fromList(utf8.encode(manifest)),
          mimeType: 'application/json', appProperties: {'kind': 'manifest', 'device': devId});

      // 4. Limpieza de PDFs que ya no usa ninguna ranura
      _progress('Ordenando el espacio en Drive...', 0.97);
      await _collectGarbage();

      await prefs.setString(_kLastSignature, signature);
      await prefs.setInt(_kLastAt, DateTime.now().millisecondsSinceEpoch);
      status.value = const DriveBackupStatus(DriveBackupState.idle);
    } on DriveAuthRequiredException {
      status.value = const DriveBackupStatus(
        DriveBackupState.needsAuth,
        message: 'Tocá "Reconectar" para seguir respaldando.',
      );
    } on DriveUnavailableException catch (e) {
      status.value = DriveBackupStatus(DriveBackupState.error, message: e.message);
      schedule(const Duration(minutes: 15));
    } catch (e) {
      debugPrint('Backup en Drive falló: $e');
      status.value = DriveBackupStatus(DriveBackupState.error, message: '$e');
    } finally {
      _running = false;
      if (snapshot != null) {
        try {
          await fs.deleteFile(snapshot);
        } catch (_) {}
      }
    }
  }

  static String _blobName(String hash) => 'blob_$hash.pdf';

  /// (sha256, tamaño), usando un caché por tamaño + fecha de modificación.
  Future<(String, int)> _hashOf(String abs, String rel, Map<String, dynamic> cache) async {
    final len = await fs.length(abs);
    final mod = (await fs.modified(abs))?.millisecondsSinceEpoch ?? 0;
    final c = cache[rel];
    if (c is Map && c['len'] == len && c['mod'] == mod && c['sha'] is String) {
      return (c['sha'] as String, len);
    }
    final bytes = await fs.readBytes(abs);
    final sha = await runHeavy(() => sha256.convert(bytes).toString());
    cache[rel] = {'len': len, 'mod': mod, 'sha': sha};
    return (sha, len);
  }

  Future<String> get _hashCachePath async => p.join(AppData.storage.basePath, _hashCacheFile);

  Future<Map<String, dynamic>> _loadHashCache() async {
    try {
      final path = await _hashCachePath;
      if (!await fs.fileExists(path)) return {};
      return (jsonDecode(await fs.readString(path)) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveHashCache(Map<String, dynamic> cache) async {
    try {
      await fs.writeString(await _hashCachePath, jsonEncode(cache));
    } catch (_) {}
  }

  /// Marca los blobs sin uso y borra los que llevan más de 30 días así.
  Future<void> _collectGarbage() async {
    final files = await _drive.listAll();
    final used = <String>{};
    for (final f in files.where((f) => f.appProperties['kind'] == 'manifest' || f.name.endsWith('.json'))) {
      try {
        final m = jsonDecode(utf8.decode(await _drive.download(f.id))) as Map<String, dynamic>;
        for (final h in ((m['docs'] as Map?) ?? const {}).values) {
          used.add(_blobName('$h'));
        }
      } catch (_) {
        return; // si no se puede leer un manifiesto, no se borra nada
      }
    }
    final now = DateTime.now();
    for (final f in files.where((f) => f.name.startsWith('blob_'))) {
      final since = int.tryParse(f.appProperties['orphanSince'] ?? '');
      if (used.contains(f.name)) {
        if (since != null) await _drive.updateMetadata(f.id, appProperties: {'orphanSince': null});
      } else if (since == null) {
        await _drive.updateMetadata(f.id, appProperties: {'orphanSince': '${now.millisecondsSinceEpoch}'});
      } else if (now.difference(DateTime.fromMillisecondsSinceEpoch(since)).inDays >= _orphanDays) {
        await _drive.delete(f.id);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Ranuras y restauración
  // ---------------------------------------------------------------------------

  /// Respaldos de todos los dispositivos de esta cuenta + espacio total usado.
  Future<(List<DriveBackupSlot>, int)> listSlots() async {
    final files = await _drive.listAll();
    final total = files.fold<int>(0, (a, f) => a + f.size);
    final names = {for (final f in files) f.name};
    final slots = <DriveBackupSlot>[];
    for (final f in files) {
      final m = RegExp(r'^dev_(.+)\.json$').firstMatch(f.name);
      if (m == null || f.name.contains('.prev.')) continue;
      try {
        final j = jsonDecode(utf8.decode(await _drive.download(f.id))) as Map<String, dynamic>;
        final id = m.group(1)!;
        slots.add(DriveBackupSlot(
          deviceId: id,
          deviceName: j['deviceName'] as String? ?? 'Dispositivo',
          platform: j['platform'] as String? ?? '',
          updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toLocal(),
          docCount: (j['docCount'] as num?)?.toInt() ?? 0,
          totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
          hasPrevious: names.contains('dev_$id.prev.json') && names.contains('dev_$id.prev.sqlite'),
          isThisDevice: id == _deviceId,
        ));
      } catch (e) {
        debugPrint('Manifiesto ilegible ${f.name}: $e');
      }
    }
    slots.sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
    return (slots, total);
  }

  /// `true` si en esta plataforma se puede reemplazar la biblioteca.
  bool get canReplace => fs.isNative;

  /// Trae el respaldo de [slot]. [replace]: reemplaza la biblioteca local
  /// (con resguardo y vuelta atrás si falla); si no, la agrega en una carpeta.
  /// [previous]: usa la versión anterior de esa ranura.
  Future<String> restore(DriveBackupSlot slot, {required bool replace, bool previous = false}) async {
    final suffix = previous ? '.prev' : '';
    final work = await fs.createTempDir('restore_extraction_drive_');
    try {
      _progress('Descargando respaldo...', 0);
      final files = await _drive.listAll();
      final byName = {for (final f in files) f.name: f};
      final mf = byName['dev_${slot.deviceId}$suffix.json'];
      final db = byName['dev_${slot.deviceId}$suffix.sqlite'];
      if (mf == null || db == null) throw Exception('El respaldo está incompleto.');

      final manifest = jsonDecode(utf8.decode(await _drive.download(mf.id))) as Map<String, dynamic>;
      await fs.writeBytes(p.join(work, kMainDbFileName), await _drive.download(db.id));

      final docs = ((manifest['docs'] as Map?) ?? const {}).cast<String, dynamic>();
      var i = 0;
      for (final e in docs.entries) {
        i++;
        _progress('Descargando partituras ($i/${docs.length})...', i / docs.length);
        final blob = byName[_blobName('${e.value}')];
        final rel = p.normalize(e.key);
        if (blob == null || rel.startsWith('..') || p.isAbsolute(rel)) continue;
        await fs.writeBytes(p.join(work, rel), await _drive.download(blob.id));
      }

      status.value = const DriveBackupStatus(DriveBackupState.idle);
      if (replace) {
        await BackupManager.instance.restoreBackup(work, extracted: true);
        // La biblioteca cambió: el próximo respaldo de esta ranura sube todo.
        await (await _p).remove(_kLastSignature);
        return 'Biblioteca restaurada desde "${slot.deviceName}".';
      }
      final report = await BackupManager.instance.importBackup(
        work,
        extracted: true,
        folderName: 'Backup de ${slot.deviceName}',
      );
      return report.summary;
    } finally {
      _refreshIdleStatus();
      try {
        await fs.deleteDir(work);
      } catch (_) {}
    }
  }

  /// Borra la ranura de otro dispositivo (sus PDFs se liberan a los 30 días).
  Future<void> deleteSlot(DriveBackupSlot slot) async {
    final files = await _drive.listAll();
    for (final f in files.where((f) => f.name.startsWith('dev_${slot.deviceId}.'))) {
      await _drive.delete(f.id);
    }
    await _collectGarbage();
  }
}
