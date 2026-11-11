import 'pwa_install_service.dart';

/// Stub implementation for non-web platforms.
/// These functions do nothing on mobile/desktop.

void initializePwaWeb(PwaInstallService service) {
  // No-op on non-web platforms
}

Future<bool> promptInstallWeb() async {
  return false;
}
