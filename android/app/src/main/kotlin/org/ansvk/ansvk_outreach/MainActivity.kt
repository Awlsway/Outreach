package org.ansvk.ansvk_outreach

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        externalCacheDir?.let { root ->
            for (name in listOf("reviewed-test-batch.json", "reviewed-test-batch.metadata.json", "reviewed-test-batch.sha256")) {
                File(root, name).delete()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.ansvk.outreach/synthetic_review")
            .setMethodCallHandler { call, result ->
                if (!BuildConfig.SYNTHETIC_SYNC_TEST) {
                    result.error("disabled", "Test export is disabled", null)
                    return@setMethodCallHandler
                }
                try {
                    val root = externalCacheDir ?: throw IllegalStateException()
                    val target = File(root, "reviewed-test-batch.json")
                    val metadata = File(root, "reviewed-test-batch.metadata.json")
                    val checksum = File(root, "reviewed-test-batch.sha256")
                    when (call.method) {
                        "clear" -> { target.delete(); metadata.delete(); checksum.delete(); result.success(null) }
                        "export" -> {
                            val body = call.argument<String>("body") ?: throw IllegalArgumentException()
                            val bytes = body.toByteArray(Charsets.UTF_8)
                            require(bytes.size in 1..1048576)
                            target.outputStream().use { it.write(bytes) }
                            val hash = MessageDigest.getInstance("SHA-256").digest(bytes)
                                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
                            metadata.writeText(JSONObject().put("version", 1)
                                .put("rawUtf8BodySha256", hash).put("byteLength", bytes.size).toString(), Charsets.UTF_8)
                            checksum.writeText(hash + "\n", Charsets.UTF_8)
                            result.success(target.absolutePath)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("failed", "Test file operation failed", null)
                }
            }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
