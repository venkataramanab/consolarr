// SPDX-License-Identifier: GPL-3.0-or-later
package org.consolarr.app

import android.view.WindowManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: the platform authenticator (app lock) needs a
// FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
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
    }
}
