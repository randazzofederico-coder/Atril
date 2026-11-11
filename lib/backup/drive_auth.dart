import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Token de acceso a la carpeta oculta de la app en el Drive del usuario
/// (permiso `drive.appdata`: Atril solo ve sus propios archivos).
///
/// - Android: Google Sign-In; el token se renueva solo (sin interacción).
/// - Web: popup de Firebase Auth con el permiso extra. El navegador no da
///   tokens de larga duración: vence en ~1 h y para renovarlo hace falta un
///   toque del usuario ("Reconectar").
class DriveAuth {
  DriveAuth._();
  static final DriveAuth instance = DriveAuth._();

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';

  final GoogleSignIn _google = GoogleSignIn(scopes: const ['email', scope]);

  String? _webToken;
  DateTime? _webTokenExpiry;

  /// Email de la cuenta conectada (si se conoce).
  String? email;

  /// Conecta de forma interactiva (requiere un gesto del usuario).
  /// Devuelve false si el usuario canceló.
  Future<bool> connect() async {
    if (kIsWeb) return _connectWeb();
    var account = await _google.signInSilently();
    account ??= await _google.signIn();
    if (account == null) return false;
    if (!await _google.requestScopes(const [scope])) return false;
    email = account.email;
    return true;
  }

  Future<bool> _connectWeb() async {
    final provider = GoogleAuthProvider()
      ..addScope(scope)
      ..setCustomParameters({'prompt': 'select_account'});
    final auth = FirebaseAuth.instance;
    final current = auth.currentUser;
    final UserCredential result;
    try {
      if (current != null && !current.isAnonymous) {
        result = await current.reauthenticateWithPopup(provider);
      } else {
        result = await auth.signInWithPopup(provider);
      }
    } on FirebaseAuthException catch (e) {
      if (const {'popup-closed-by-user', 'cancelled-popup-request'}.contains(e.code)) {
        return false;
      }
      rethrow;
    }
    final token = (result.credential as OAuthCredential?)?.accessToken;
    if (token == null) return false;
    _webToken = token;
    _webTokenExpiry = DateTime.now().add(const Duration(minutes: 55));
    email = result.user?.email;
    return true;
  }

  /// Token vigente sin interacción, o null si hay que reconectar.
  Future<String?> accessToken() async {
    if (kIsWeb) {
      final exp = _webTokenExpiry;
      if (_webToken != null && exp != null && DateTime.now().isBefore(exp)) return _webToken;
      return null;
    }
    try {
      final account = _google.currentUser ?? await _google.signInSilently();
      if (account == null) return null;
      email = account.email;
      final auth = await account.authentication;
      return auth.accessToken;
    } catch (e) {
      debugPrint('DriveAuth: sin token ($e)');
      return null;
    }
  }

  /// En Android pide un token nuevo (el anterior fue rechazado). En web no
  /// se puede sin interacción: invalida el token guardado.
  Future<void> invalidate(String token) async {
    if (kIsWeb) {
      if (_webToken == token) _webToken = null;
      return;
    }
    try {
      await _google.currentUser?.clearAuthCache();
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _webToken = null;
    _webTokenExpiry = null;
    if (!kIsWeb) {
      try {
        await _google.disconnect();
      } catch (_) {}
    }
  }
}
