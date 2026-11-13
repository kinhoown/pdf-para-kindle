package com.erick.pdf_kindle

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Ponte nativa com o Flutter:
 *  - recebe PDFs compartilhados/abertos com o app;
 *  - abre o seletor de PDF do sistema;
 *  - apaga o PDF original depois do envio.
 * Sempre entrega ao Flutter: path (cópia no cache), name e uri (arquivo original).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String>? = null
    private var flutterReady = false
    private var pickResult: MethodChannel.Result? = null
    private var deleteResult: MethodChannel.Result? = null

    companion object {
        private const val REQ_PICK = 4101
        private const val REQ_DELETE = 4102
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdf_kindle/share")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPdf" -> {
                    flutterReady = true
                    result.success(pending)
                    pending = null
                }
                "pickPdf" -> pickPdf(result)
                "deletePdf" -> deletePdf(Uri.parse(call.argument<String>("uri")!!), result)
                "pickAndDelete" -> pickAndDelete(result)
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    // ------------------------------------------------------------ receber
    private fun handleIntent(intent: Intent?) {
        val uri = extractUri(intent) ?: return
        intent?.action = null // não reprocessar ao girar a tela
        copyInBackground(uri) { info ->
            if (info == null) return@copyInBackground
            if (flutterReady) channel?.invokeMethod("pdfShared", info) else pending = info
        }
    }

    private fun extractUri(intent: Intent?): Uri? = when (intent?.action) {
        Intent.ACTION_SEND ->
            if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
        Intent.ACTION_VIEW -> intent.data
        else -> null
    }

    // ------------------------------------------------------------ escolher
    private fun pickPdf(result: MethodChannel.Result) {
        pickResult?.success(null)
        pickResult = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(i, REQ_PICK)
    }

    // ------------------------------------------------------------ apagar
    private fun deletePdf(uri: Uri, result: MethodChannel.Result) {
        try {
            if (uri.scheme == "file") {
                result.success(File(uri.path!!).delete()); return
            }
            if (DocumentsContract.isDocumentUri(this, uri)) {
                if (DocumentsContract.deleteDocument(contentResolver, uri)) {
                    result.success(true); return
                }
            }
        } catch (_: Exception) { /* tenta o próximo jeito */ }
        try {
            if (contentResolver.delete(uri, null, null) > 0) {
                result.success(true); return
            }
        } catch (_: Exception) { /* sem permissão direta */ }
        result.success(false)
    }

    /** Sem permissão para apagar: o usuário escolhe o PDF no seletor (isso dá permissão) e apagamos. */
    private fun pickAndDelete(result: MethodChannel.Result) {
        deleteResult?.success(false)
        deleteResult = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(i, REQ_DELETE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_PICK -> {
                val r = pickResult ?: return
                pickResult = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) { r.success(null); return }
                copyInBackground(uri) { info -> r.success(info) }
            }
            REQ_DELETE -> {
                val r = deleteResult ?: return
                deleteResult = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) { r.success(false); return }
                val ok = try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) { false }
                r.success(ok)
            }
        }
    }

    // ------------------------------------------------------------ cópia
    private fun copyInBackground(uri: Uri, done: (Map<String, String>?) -> Unit) {
        Thread {
            val info = try { copyToCache(uri) } catch (e: Exception) { null }
            Handler(Looper.getMainLooper()).post { done(info) }
        }.start()
    }

    private fun copyToCache(uri: Uri): Map<String, String> {
        var name = "Documento.pdf"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
        }
        val out = File(cacheDir, "entrada.pdf")
        contentResolver.openInputStream(uri)!!.use { input ->
            out.outputStream().use { input.copyTo(it) }
        }
        return mapOf("path" to out.absolutePath, "name" to name, "uri" to uri.toString())
    }
}
