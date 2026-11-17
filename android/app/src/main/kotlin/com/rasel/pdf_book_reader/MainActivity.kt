package com.rasel.pdf_book_reader

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Besides hosting Flutter, this takes PDFs another app hands over ("Open
 * with"). The other app only lends a link to the file, so the file is copied
 * into the app's cache right away; the Dart side then asks for it with
 * `takePending` (it is told with `pdfArrived` when one is ready).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "paperleaf/open_pdf",
        ).also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "takePending") {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Not after the system recreated the activity: that intent was
        // handled the first time.
        if (savedInstanceState == null) takePdf(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takePdf(intent)
    }

    private fun takePdf(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return

        Thread {
            try {
                val copy = File(cacheDir, "incoming-${System.currentTimeMillis()}.pdf")
                val input = contentResolver.openInputStream(uri) ?: return@Thread
                input.use { source -> copy.outputStream().use { source.copyTo(it) } }

                val data = mapOf(
                    "path" to copy.absolutePath,
                    "name" to (displayName(uri) ?: "Book.pdf"),
                )
                runOnUiThread {
                    // A PDF that was never picked up is replaced.
                    pending?.get("path")?.let { File(it).delete() }
                    pending = data
                    channel?.invokeMethod("pdfArrived", null)
                }
            } catch (_: Exception) {
                // The link could not be read (permission gone, file removed):
                // the app simply opens on its shelf.
            }
        }.start()
    }

    private fun displayName(uri: Uri): String? {
        try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getString(0)
            }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }
}
