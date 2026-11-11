import 'package:flutter/foundation.dart';

// Conditional imports for web-only JS interop
import 'pwa_install_stub.dart'
    if (dart.library.js_interop) 'pwa_install_web.dart';

/// Cross-platform PWA install service.
/// On web, it captures the beforeinstallprompt event and allows triggering the install.
/// On other platforms, it simply reports that install is not available.
class PwaInstallService {
  static final PwaInstallService _instance = PwaInstallService._();
  factory PwaInstallService() => _instance;
  PwaInstallService._();

  final ValueNotifier<bool> canInstall = ValueNotifier(false);
  final ValueNotifier<bool> isInstalled = ValueNotifier(false);

  void initialize() {
    if (kIsWeb) {
      initializePwaWeb(this);
    }
  }

  Future<bool> promptInstall() async {
    if (!kIsWeb) return false;
    return promptInstallWeb();
  }
}
