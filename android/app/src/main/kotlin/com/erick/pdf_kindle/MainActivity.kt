package com.erick.pdf_kindle

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Recebe PDFs compartilhados ("Compartilhar > PDF para Kindle") ou abertos com o app,
 * copia para o cache e entrega o caminho ao Flutter.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String>? = null
    private var flutterReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdf_kindle/share")
        channel!!.setMethodCallHandler { call, result ->
            if (call.method == "getInitialPdf") {
                flutterReady = true
                result.success(pending)
                pending = null
            } else {
                result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val uri = extractUri(intent) ?: return
        intent?.action = null // não reprocessar ao girar a tela
        Thread {
            val info = try { copyToCache(uri) } catch (e: Exception) { null }
            Handler(Looper.getMainLooper()).post {
                if (info == null) return@post
                if (flutterReady) channel?.invokeMethod("pdfShared", info) else pending = info
            }
        }.start()
    }

    private fun extractUri(intent: Intent?): Uri? = when (intent?.action) {
        Intent.ACTION_SEND ->
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
        Intent.ACTION_VIEW -> intent.data
        else -> null
    }

    private fun copyToCache(uri: Uri): Map<String, String> {
        var name = "Documento.pdf"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
        }
        val out = File(cacheDir, "compartilhado.pdf")
        contentResolver.openInputStream(uri)!!.use { input ->
            out.outputStream().use { input.copyTo(it) }
        }
        return mapOf("path" to out.absolutePath, "name" to name)
    }
}
