package com.aurora.mxenc

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import android.net.Uri
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.maoxiao.mxenc/secure"
    private val FILE_UTILS_CHANNEL = "com.maoxiao.mxenc/file_utils"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Secure Screen Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureScreen" -> {
                    try {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ERR", e.message, null)
                    }
                }
                "disableSecureScreen" -> {
                    try {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ERR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // File Utils Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_UTILS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "copyContentUri" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString == null) {
                        result.error("INVALID_ARG", "URI is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(uriString)
                        val contentResolver = contentResolver
                        val inputStream = contentResolver.openInputStream(uri)
                        if (inputStream == null) {
                            result.error("OPEN_FAILED", "Cannot open input stream", null)
                            return@setMethodCallHandler
                        }

                        // Create a temp file in cache directory
                        val cacheDir = cacheDir
                        val fileName = "temp_shared_${System.currentTimeMillis()}.mxenc"
                        val tempFile = File(cacheDir, fileName)
                        val outputStream = FileOutputStream(tempFile)

                        inputStream.use { input ->
                            outputStream.use { output ->
                                input.copyTo(output)
                            }
                        }
                        
                        result.success(tempFile.absolutePath)
                    } catch (e: Exception) {
                        result.error("COPY_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
