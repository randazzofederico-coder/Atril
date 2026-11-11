import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'drive_auth.dart';

/// Sin conexión o Drive no responde: se reintenta más tarde.
class DriveUnavailableException implements Exception {
  final String message;
  DriveUnavailableException(this.message);
  @override
  String toString() => message;
}

/// Hace falta reconectar la cuenta (token vencido o permiso revocado).
class DriveAuthRequiredException implements Exception {
  @override
  String toString() => 'Hay que volver a conectar Google Drive.';
}

/// Archivo de la carpeta oculta de la app.
class DriveFile {
  final String id;
  final String name;
  final int size;
  final DateTime? modified;
  final Map<String, String> appProperties;

  DriveFile(this.id, this.name, this.size, this.modified, this.appProperties);

  factory DriveFile.fromJson(Map<String, dynamic> j) => DriveFile(
        j['id'] as String,
        j['name'] as String,
        int.tryParse('${j['size'] ?? 0}') ?? 0,
        j['modifiedTime'] == null ? null : DateTime.tryParse(j['modifiedTime'] as String),
        ((j['appProperties'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')),
      );
}

/// Cliente mínimo de la API REST de Drive v3, limitado a `appDataFolder`.
class DriveClient {
  DriveClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const _fields = 'id,name,size,modifiedTime,appProperties';

  /// Todos los archivos de la carpeta oculta.
  Future<List<DriveFile>> listAll() async {
    final out = <DriveFile>[];
    String? pageToken;
    do {
      final uri = Uri.parse('$_api/files').replace(queryParameters: {
        'spaces': 'appDataFolder',
        'pageSize': '1000',
        'fields': 'nextPageToken,files($_fields)',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final res = await _send((h) => _http.get(uri, headers: h));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      for (final f in (j['files'] as List? ?? const [])) {
        out.add(DriveFile.fromJson((f as Map).cast<String, dynamic>()));
      }
      pageToken = j['nextPageToken'] as String?;
    } while (pageToken != null);
    return out;
  }

  /// Crea un archivo (subida "resumable": sirve para PDFs grandes).
  Future<DriveFile> create(
    String name,
    Uint8List bytes, {
    String mimeType = 'application/octet-stream',
    Map<String, String>? appProperties,
  }) async {
    final meta = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
      if (appProperties != null) 'appProperties': appProperties,
    });
    final start = await _send((h) => _http.post(
          Uri.parse('$_upload/files?uploadType=resumable&fields=$_fields'),
          headers: {
            ...h,
            'Content-Type': 'application/json; charset=UTF-8',
            'X-Upload-Content-Type': mimeType,
            'X-Upload-Content-Length': '${bytes.length}',
          },
          body: meta,
        ));
    final location = start.headers['location'];
    if (location == null) throw DriveUnavailableException('Drive no devolvió la URL de subida.');
    final res = await _send((h) => _http.put(
          Uri.parse(location),
          headers: {...h, 'Content-Type': mimeType},
          body: bytes,
        ));
    return DriveFile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Reemplaza el contenido de un archivo existente.
  Future<void> updateContent(String id, Uint8List bytes, {String mimeType = 'application/octet-stream'}) async {
    await _send((h) => _http.patch(
          Uri.parse('$_upload/files/$id?uploadType=media'),
          headers: {...h, 'Content-Type': mimeType},
          body: bytes,
        ));
  }

  /// Cambia nombre y/o appProperties (un valor null borra la propiedad).
  Future<void> updateMetadata(String id, {String? name, Map<String, String?>? appProperties}) async {
    await _send((h) => _http.patch(
          Uri.parse('$_api/files/$id'),
          headers: {...h, 'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode({
            if (name != null) 'name': name,
            if (appProperties != null) 'appProperties': appProperties,
          }),
        ));
  }

  Future<Uint8List> download(String id) async {
    final res = await _send((h) => _http.get(Uri.parse('$_api/files/$id?alt=media'), headers: h));
    return res.bodyBytes;
  }

  Future<void> delete(String id) async {
    await _send((h) => _http.delete(Uri.parse('$_api/files/$id'), headers: h), allow404: true);
  }

  /// Ejecuta la request con el token; si Drive lo rechaza (401) pide uno
  /// nuevo y reintenta una vez.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool allow404 = false,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await DriveAuth.instance.accessToken();
      if (token == null) throw DriveAuthRequiredException();
      final http.Response res;
      try {
        res = await request({'Authorization': 'Bearer $token'});
      } catch (e) {
        throw DriveUnavailableException('Sin conexión con Google Drive ($e)');
      }
      if (res.statusCode == 401) {
        await DriveAuth.instance.invalidate(token);
        continue;
      }
      if (res.statusCode == 403 && res.body.contains('insufficient')) {
        throw DriveAuthRequiredException();
      }
      if (res.statusCode == 404 && allow404) return res;
      if (res.statusCode >= 200 && res.statusCode < 300) return res;
      if (res.statusCode == 403 && res.body.contains('storageQuotaExceeded')) {
        throw DriveUnavailableException('Tu Google Drive no tiene espacio suficiente.');
      }
      if (res.statusCode >= 500 || res.statusCode == 429) {
        throw DriveUnavailableException('Google Drive no responde (${res.statusCode}).');
      }
      throw Exception('Error de Google Drive (${res.statusCode}): ${res.body}');
    }
    throw DriveAuthRequiredException();
  }
}
