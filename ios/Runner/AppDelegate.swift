import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var pendingFilePath: String?
    private var methodChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController

        methodChannel = FlutterMethodChannel(
            name: "com.saroo.atril/file_receiver",
            binaryMessenger: controller.binaryMessenger
        )

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            if call.method == "getInitialFile" {
                result(self?.pendingFilePath)
                self?.pendingFilePath = nil
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// Captura archivos abiertos desde otras apps (e.g. .setlist, .atril).
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if let tempPath = copyFileToTemp(url: url) {
            if let channel = methodChannel {
                // App ya corriendo → enviar directo a Flutter
                channel.invokeMethod("onNewFile", arguments: tempPath)
            } else {
                // Cold start → guardar para cuando Flutter pregunte
                pendingFilePath = tempPath
            }
        }
        return true
    }

    /// Copia el archivo a un directorio temporal accesible por Dart.
    private func copyFileToTemp(url: URL) -> String? {
        let fileName = url.lastPathComponent
        let tempDir = NSTemporaryDirectory()
        let destPath = (tempDir as NSString).appendingPathComponent(fileName)

        do {
            // Acceder al recurso con scope de seguridad (sandboxing iOS)
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destPath) {
                try fileManager.removeItem(atPath: destPath)
            }
            try fileManager.copyItem(at: url, to: URL(fileURLWithPath: destPath))
            return destPath
        } catch {
            print("Error copying file to temp: \(error)")
            return nil
        }
    }
}
