package com.cliplink.clip_link_mobile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.cliplink/clipboard"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "writeImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(writeImageToClipboard(bytes))
                    }
                    "writeFileUri" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(writeFileToClipboard(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun writeImageToClipboard(pngBytes: ByteArray): Boolean {
        return try {
            // Save PNG to cache
            val cacheDir = cacheDir
            val file = File(cacheDir, "cliplink_img_${System.currentTimeMillis()}.png")
            file.writeBytes(pngBytes)

            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.clipboard_provider",
                file
            )

            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newUri(contentResolver, "image", uri)
            clipboard.setPrimaryClip(clip)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun writeFileToClipboard(filePath: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) return false

            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.clipboard_provider",
                file
            )

            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newUri(contentResolver, file.name, uri)
            clipboard.setPrimaryClip(clip)
            true
        } catch (e: Exception) {
            false
        }
    }
}
