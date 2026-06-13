package com.saroo.atril

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.saroo.atril/file_receiver"
    private val TAG = "AtrilFileReceiver"
    private var pendingFilePath: String? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                Log.d(TAG, "getInitialFile llamado, pendingFilePath=$pendingFilePath")
                result.success(pendingFilePath)
                pendingFilePath = null
            } else {
                result.notImplemented()
            }
        }

        // Cold start: SIEMPRE guardar como pending
        val path = extractFileFromIntent(intent)
        Log.d(TAG, "configureFlutterEngine - extracted path: $path")
        if (path != null) {
            pendingFilePath = path
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val path = extractFileFromIntent(intent)
        Log.d(TAG, "onNewIntent - extracted path: $path")
        if (path != null) {
            methodChannel?.invokeMethod("onNewFile", path)
        }
    }

    /**
     * Extrae el archivo de un intent ACTION_VIEW o ACTION_SEND.
     */
    private fun extractFileFromIntent(intent: Intent): String? {
        Log.d(TAG, "extractFileFromIntent - action=${intent.action}, data=${intent.data}")

        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            else -> null
        }

        if (uri == null) {
            Log.d(TAG, "No se encontró URI en el intent")
            return null
        }

        Log.d(TAG, "URI encontrada: $uri")

        val tempPath = copyUriToCache(uri)
        Log.d(TAG, "Archivo copiado a cache: $tempPath")

        // Limpiar el intent para no re-procesarlo
        intent.data = null
        intent.action = null

        return tempPath
    }

    /**
     * Copia un content:// URI al cache de la app y devuelve el path absoluto.
     */
    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null

            val fileName = getDisplayName(uri)
            Log.d(TAG, "Display name: $fileName")
            val tempFile = File(cacheDir, fileName)

            tempFile.outputStream().use { output ->
                inputStream.copyTo(output)
            }
            inputStream.close()

            Log.d(TAG, "Archivo guardado: ${tempFile.absolutePath}, size=${tempFile.length()}")
            tempFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Error copiando archivo", e)
            null
        }
    }

    /** Obtiene el nombre de display del archivo desde el ContentResolver. */
    private fun getDisplayName(uri: Uri): String {
        val cursor = contentResolver.query(uri, null, null, null, null)
        cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) {
                    return it.getString(nameIndex)
                }
            }
        }
        return uri.lastPathSegment ?: "received_${System.currentTimeMillis()}"
    }
}
