package com.example.wallp

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine

/**
 * The home screen. Runs the Dart `launcherMain` entry point on a transparent
 * Flutter view, so the real system wallpaper shows behind the icons.
 */
class LauncherActivity : FlutterActivity() {
    private val bridge by lazy { NativeBridge(this) }

    override fun getDartEntrypointFunctionName(): String = "launcherMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge.register(flutterEngine.dartExecutor.binaryMessenger)
        bridge.watchPackages()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Home pressed while already home: close the app drawer, etc.
        if (intent.hasCategory(Intent.CATEGORY_HOME)) bridge.notifyHomePressed()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (!bridge.onActivityResult(requestCode)) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        bridge.dispose()
        super.onDestroy()
    }
}
