import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'pwa_install_service.dart';

/// Stores the deferred prompt event from 'beforeinstallprompt'
JSObject? _deferredPrompt;

/// Web-specific PWA install initialization.
/// Captures the beforeinstallprompt event and detects standalone mode.
void initializePwaWeb(PwaInstallService service) {
  // Check if already running as installed PWA (standalone mode)
  final isStandalone = _matchMedia('(display-mode: standalone)');

  if (isStandalone) {
    service.isInstalled.value = true;
    service.canInstall.value = false;
    return;
  }

  // Listen for the beforeinstallprompt event
  _addEventListener('beforeinstallprompt', (JSObject event) {
    // Prevent the default mini-infobar from appearing
    event.callMethod('preventDefault'.toJS);
    _deferredPrompt = event;
    service.canInstall.value = true;
  });

  // Listen for successful installation
  _addEventListener('appinstalled', (JSObject event) {
    _deferredPrompt = null;
    service.canInstall.value = false;
    service.isInstalled.value = true;
  });
}

/// Triggers the native PWA install prompt.
/// Returns true if the prompt was shown, false otherwise.
Future<bool> promptInstallWeb() async {
  final prompt = _deferredPrompt;
  if (prompt == null) return false;

  // Call .prompt() on the BeforeInstallPromptEvent
  prompt.callMethod('prompt'.toJS);

  // The 'appinstalled' event listener will handle state updates
  return true;
}

/// Helper: calls window.matchMedia(query).matches
bool _matchMedia(String query) {
  final window = globalContext;
  final mediaQuery = window.callMethod<JSObject>(
    'matchMedia'.toJS,
    query.toJS,
  );
  return (mediaQuery['matches'] as JSBoolean).toDart;
}

/// Helper: calls window.addEventListener(type, callback)
void _addEventListener(String type, void Function(JSObject event) callback) {
  final window = globalContext;
  window.callMethod<JSAny?>(
    'addEventListener'.toJS,
    type.toJS,
    callback.toJS,
  );
}
