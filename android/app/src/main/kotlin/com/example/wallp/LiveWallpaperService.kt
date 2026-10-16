package com.example.wallp

import android.app.KeyguardManager
import android.app.WallpaperManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.service.wallpaper.WallpaperService
import android.text.format.DateFormat
import android.view.SurfaceHolder
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.embedding.engine.systemchannels.SettingsChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Animated wallpaper: each wallpaper engine runs the Dart `wallpaperMain`
 * entry point on its own Flutter engine and renders it straight into the
 * wallpaper surface, so the same scene painters as the app are used.
 */
class LiveWallpaperService : WallpaperService() {
    // Engines in a group share code and resources (the preview and the real
    // wallpaper can run at the same time).
    private lateinit var engines: FlutterEngineGroup

    override fun onCreate() {
        super.onCreate()
        engines = FlutterEngineGroup(this)
    }

    override fun onCreateEngine(): Engine = FlutterWallpaperEngine()

    private inner class FlutterWallpaperEngine : Engine() {
        private var flutter: FlutterEngine? = null
        private var channel: MethodChannel? = null
        private var lockReceiver: BroadcastReceiver? = null

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            setTouchEventsEnabled(false)
            val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            val engine = engines.createAndRunEngine(
                this@LiveWallpaperService,
                DartExecutor.DartEntrypoint(bundle, "wallpaperMain"),
            )
            flutter = engine
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "showLockClock" -> result.success(showLockClock())
                        else -> result.notImplemented()
                    }
                }
            }
            sendSettings()
            watchLock()
        }

        /**
         * Whether to draw the themed lock screen clock: while the phone is
         * locked, always in the picker's preview (so the user sees it), and
         * never on a home-screen-only wallpaper (Android 14+ can run separate
         * engines for the home and lock screens).
         */
        private fun showLockClock(): Boolean {
            if (isPreview) return true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                when (wallpaperFlags) {
                    WallpaperManager.FLAG_LOCK -> return true
                    WallpaperManager.FLAG_SYSTEM -> return false
                }
            }
            val keyguard = getSystemService(KeyguardManager::class.java)
            return keyguard?.isKeyguardLocked == true
        }

        /**
         * FlutterView normally sends these; without one, Dart would always
         * use a 12-hour clock and the default text scale.
         */
        private fun sendSettings() {
            val engine = flutter ?: return
            val config = resources.configuration
            engine.settingsChannel.startMessage()
                .setUse24HourFormat(DateFormat.is24HourFormat(this@LiveWallpaperService))
                .setTextScaleFactor(config.fontScale)
                .setPlatformBrightness(
                    if (config.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK ==
                        android.content.res.Configuration.UI_MODE_NIGHT_YES
                    ) {
                        SettingsChannel.PlatformBrightness.dark
                    } else {
                        SettingsChannel.PlatformBrightness.light
                    },
                )
                .send()
        }

        private fun sendLockState() {
            channel?.invokeMethod("lockClock", showLockClock())
        }

        /** Screen on/off and unlock change whether the lock screen shows. */
        private fun watchLock() {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) = sendLockState()
            }
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
            lockReceiver = receiver
        }

        override fun onWallpaperFlagsChanged(which: Int) {
            super.onWallpaperFlagsChanged(which)
            sendLockState()
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            flutter?.renderer?.startRenderingToSurface(holder.surface, false)
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            flutter?.renderer?.apply {
                surfaceChanged(width, height)
                setViewportMetrics(
                    FlutterRenderer.ViewportMetrics().apply {
                        this.width = width
                        this.height = height
                        // The layout constraints default to 0, which makes
                        // Flutter lay the scene out at 0x0 and draw nothing.
                        // Pin them to the surface size like FlutterView does.
                        minWidth = width
                        maxWidth = width
                        minHeight = height
                        maxHeight = height
                        devicePixelRatio = resources.displayMetrics.density
                    },
                )
            }
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            // Paused = no frames, so the animation costs nothing while an app
            // covers the wallpaper or the screen is off. Resuming also makes
            // Dart re-read the applied theme.
            if (visible) {
                sendSettings()
                sendLockState()
            }
            flutter?.lifecycleChannel?.let {
                if (visible) it.appIsResumed() else it.appIsPaused()
            }
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            flutter?.renderer?.stopRenderingToSurface()
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            lockReceiver?.let { unregisterReceiver(it) }
            lockReceiver = null
            channel?.setMethodCallHandler(null)
            channel = null
            flutter?.destroy()
            flutter = null
            super.onDestroy()
        }
    }

    companion object {
        private const val CHANNEL = "wallp/live_wallpaper"
    }
}
