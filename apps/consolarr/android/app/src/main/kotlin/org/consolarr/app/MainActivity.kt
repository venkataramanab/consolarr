// SPDX-License-Identifier: GPL-3.0-or-later
package org.consolarr.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.view.WindowManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: the platform authenticator (app lock) needs a
// FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    companion object {
        // Must equal `shareTextMaxBytes` in Dart (a test compares them). The
        // text travels in a Binder transaction (about 1 MB for the process).
        const val MAX_SHARE_TEXT_BYTES = 150 * 1024
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Tapjacking: ignore touches while another window obscures this one.
        window.decorView.filterTouchesWhenObscured = true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lets Dart mark the window secure (no screenshots, blanked in the
        // recents list) while a secret is revealed on screen.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "consolarr/secure_screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val secure = call.argument<Boolean>("secure") ?: false
                    if (secure) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        // The Android API level, for the diagnostics bundle. Nothing else.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "consolarr/platform_info")
            .setMethodCallHandler { call, result ->
                if (call.method == "apiLevel") {
                    result.success(Build.VERSION.SDK_INT)
                } else {
                    result.notImplemented()
                }
            }
        // Shares plain text through the system chooser, on an explicit tap.
        // No file, no FileProvider: the text goes in EXTRA_TEXT (the Dart side
        // caps its size because of the Binder transaction limit).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "consolarr/share")
            .setMethodCallHandler { call, result ->
                if (call.method == "shareText") {
                    val text = call.argument<String>("text")
                    if (text == null) {
                        result.error("bad_args", "text is required", null)
                        return@setMethodCallHandler
                    }
                    // Native guard: Dart caps the text first; this refuses
                    // anything above the same cap instead of building the intent.
                    if (text.toByteArray(Charsets.UTF_8).size > MAX_SHARE_TEXT_BYTES) {
                        result.error("too_large", "text exceeds the share cap", null)
                        return@setMethodCallHandler
                    }
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                        call.argument<String>("subject")?.let {
                            putExtra(Intent.EXTRA_SUBJECT, it)
                        }
                    }
                    try {
                        startActivity(Intent.createChooser(send, null))
                        result.success(null)
                    } catch (e: ActivityNotFoundException) {
                        result.error("unavailable", "no share target", null)
                    } catch (e: RuntimeException) {
                        result.error("failed", "share failed", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
