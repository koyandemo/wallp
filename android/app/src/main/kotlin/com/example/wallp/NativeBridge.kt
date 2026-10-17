package com.example.wallp

import android.app.Activity
import android.app.WallpaperManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
import android.provider.Settings
import android.util.DisplayMetrics
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Native features shared by the theme store (MainActivity) and the home
 * screen (LauncherActivity): wallpaper, app list + themed shortcuts, and
 * launcher actions. Each activity's Flutter engine gets its own bridge.
 */
class NativeBridge(private val activity: Activity) {
    // Decoding/setting a full-screen bitmap and loading every app icon take
    // a while, so that work runs off the main thread.
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var launcherChannel: MethodChannel? = null
    private var packageCallback: LauncherApps.Callback? = null

    /** Waiting for the "default home app" screen to close. */
    private var pendingHomeResult: MethodChannel.Result? = null

    /** Waiting for the live wallpaper picker to close. */
    private var pendingLiveResult: MethodChannel.Result? = null
    private var liveOpenedAt = 0L
    private var liveRetried = false

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, WALLPAPER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "screenSize" -> result.success(screenSize())
                "openLiveWallpaper" -> openLiveWallpaper(result)
                "isLiveWallpaperActive" -> result.success(isLiveWallpaperActive())
                "setWallpaper" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val target = call.argument<String>("target")
                    if (bytes == null || target == null) {
                        result.error("bad_args", "bytes and target are required", null)
                    } else {
                        setWallpaper(bytes, target, result)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, ICONS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canPinShortcuts" -> result.success(canPinShortcuts())
                "listApps" -> runInBackground(result) { listApps() }
                "getApp" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg == null) {
                        result.error("bad_args", "package is required", null)
                    } else {
                        runInBackground(result) { getApp(pkg) }
                    }
                }
                "pinShortcut" -> {
                    val id = call.argument<String>("id")
                    val pkg = call.argument<String>("package")
                    val label = call.argument<String>("label")
                    val icon = call.argument<ByteArray>("icon")
                    if (id == null || pkg == null || label == null || icon == null) {
                        result.error("bad_args", "id, package, label and icon are required", null)
                    } else {
                        pinShortcut(id, pkg, label, icon, result)
                    }
                }
                else -> result.notImplemented()
            }
        }

        launcherChannel = MethodChannel(messenger, LAUNCHER_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                val pkg = call.argument<String>("package")
                when (call.method) {
                    "launchApp" -> result.success(pkg != null && launchApp(pkg))
                    "appInfo" -> result.success(pkg != null && openAppInfo(pkg))
                    "openThemes" -> {
                        activity.startActivity(Intent(activity, MainActivity::class.java))
                        result.success(true)
                    }
                    "isDefaultHome" -> result.success(isDefaultHome())
                    "goHome" -> result.success(goHome())
                    "requestDefaultHome" -> requestDefaultHome(result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Tells the home screen the Home button was pressed while it's showing. */
    fun notifyHomePressed() {
        launcherChannel?.invokeMethod("homePressed", null)
    }

    /**
     * Home screen only: tells Dart when apps are installed, removed or
     * updated, so icons appear/disappear without reloading everything.
     */
    fun watchPackages() {
        if (packageCallback != null) return
        val launcherApps = activity.getSystemService(LauncherApps::class.java) ?: return
        val callback = object : LauncherApps.Callback() {
            override fun onPackageRemoved(packageName: String, user: UserHandle) =
                notifyAppsChanged(listOf(packageName), removed = true)

            override fun onPackageAdded(packageName: String, user: UserHandle) =
                notifyAppsChanged(listOf(packageName), removed = false)

            override fun onPackageChanged(packageName: String, user: UserHandle) =
                notifyAppsChanged(listOf(packageName), removed = false)

            override fun onPackagesAvailable(
                packageNames: Array<out String>,
                user: UserHandle,
                replacing: Boolean,
            ) = notifyAppsChanged(packageNames.toList(), removed = false)

            override fun onPackagesUnavailable(
                packageNames: Array<out String>,
                user: UserHandle,
                replacing: Boolean,
            ) {
                if (!replacing) notifyAppsChanged(packageNames.toList(), removed = true)
            }
        }
        launcherApps.registerCallback(callback, mainHandler)
        packageCallback = callback
    }

    private fun notifyAppsChanged(packages: List<String>, removed: Boolean) {
        if (packages.contains(activity.packageName)) return
        launcherChannel?.invokeMethod(
            "appsChanged",
            mapOf("packages" to packages, "removed" to removed),
        )
    }

    fun dispose() {
        packageCallback?.let {
            activity.getSystemService(LauncherApps::class.java)?.unregisterCallback(it)
        }
        packageCallback = null
        // Lets a running task finish, then stops the thread.
        worker.shutdown()
        launcherChannel = null
    }

    private fun runInBackground(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("failed", e.message, null) }
            }
        }
    }

    // ---- Wallpaper ----

    /** Full display size in pixels, portrait (width < height). */
    private fun screenSize(): List<Int> {
        val wm = activity.windowManager
        val (w, h) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.maximumWindowMetrics.bounds
            bounds.width() to bounds.height()
        } else {
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(metrics)
            metrics.widthPixels to metrics.heightPixels
        }
        return listOf(minOf(w, h), maxOf(w, h))
    }

    /** True while wallp's live wallpaper is the phone's wallpaper. */
    private fun isLiveWallpaperActive(): Boolean = try {
        WallpaperManager.getInstance(activity).wallpaperInfo?.packageName == activity.packageName
    } catch (e: Exception) {
        false
    }

    /**
     * Opens the system preview for wallp's live wallpaper ("Set wallpaper"
     * finishes it), or the general live wallpaper list if a launcher/skin
     * doesn't support the direct preview. Answers "set", "cancelled" or
     * "unavailable" once the picker closes.
     */
    private fun openLiveWallpaper(result: MethodChannel.Result) {
        pendingLiveResult?.success("cancelled")
        pendingLiveResult = result
        liveRetried = false
        if (!startLivePicker()) {
            pendingLiveResult = null
            result.success("unavailable")
        }
    }

    private fun startLivePicker(): Boolean {
        val direct = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).putExtra(
            WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
            ComponentName(activity, LiveWallpaperService::class.java),
        )
        for (intent in listOf(direct, Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER))) {
            try {
                liveOpenedAt = System.currentTimeMillis()
                activity.startActivityForResult(intent, REQUEST_LIVE_WALLPAPER)
                return true
            } catch (e: ActivityNotFoundException) {
                // Try the next one.
            }
        }
        return false
    }

    /**
     * The picker closed. Some skins (realme UI, ColorOS) close it at once
     * when its app was not running yet, before showing anything: open it
     * once more, now that it's warm.
     */
    private fun onLivePickerClosed() {
        val result = pendingLiveResult ?: return
        if (isLiveWallpaperActive()) {
            pendingLiveResult = null
            result.success("set")
            return
        }
        val closedAtOnce = System.currentTimeMillis() - liveOpenedAt < LIVE_PICKER_GLITCH_MS
        if (closedAtOnce && !liveRetried) {
            liveRetried = true
            if (startLivePicker()) return
        }
        pendingLiveResult = null
        result.success(if (closedAtOnce) "unavailable" else "cancelled")
    }

    /** [target] is "home", "lock" or "both" (Dart's WallpaperTarget names). */
    private fun setWallpaper(bytes: ByteArray, target: String, result: MethodChannel.Result) {
        worker.execute {
            try {
                val manager = WallpaperManager.getInstance(activity.applicationContext)
                if (!manager.isWallpaperSupported || !manager.isSetWallpaperAllowed) {
                    mainHandler.post {
                        result.error("not_allowed", "This device doesn't allow changing the wallpaper", null)
                    }
                    return@execute
                }
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    ?: throw IllegalArgumentException("Could not decode the wallpaper image")
                val flags = when (target) {
                    "home" -> WallpaperManager.FLAG_SYSTEM
                    "lock" -> WallpaperManager.FLAG_LOCK
                    else -> WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK
                }
                manager.setBitmap(bitmap, null, true, flags)
                bitmap.recycle()
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("set_failed", e.message, null) }
            }
        }
    }

    // ---- App list and themed shortcuts ----

    private fun canPinShortcuts(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.getSystemService(ShortcutManager::class.java)?.isRequestPinShortcutSupported == true

    private fun launcherActivities(pkg: String? = null): List<ResolveInfo> {
        val pm = activity.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        if (pkg != null) launcher.setPackage(pkg)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(launcher, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(launcher, 0)
        }
    }

    /**
     * Launchable apps as {package, label, icon PNG, logo PNG?}, by label. Includes wallp
     * itself, so the theme store can be opened from the drawer once wallp is
     * the home app.
     */
    private fun listApps(): List<Map<String, Any>> =
        launcherActivities()
            .asSequence()
            .distinctBy { it.activityInfo.packageName }
            .map(::appEntry)
            .sortedBy { (it["label"] as String).lowercase() }
            .toList()

    /** One app's entry, or null if it has no launcher icon (or is gone). */
    private fun getApp(pkg: String): Map<String, Any>? =
        launcherActivities(pkg).firstOrNull()?.let(::appEntry)

    private fun appEntry(info: ResolveInfo): Map<String, Any> {
        val pm = activity.packageManager
        val pkg = info.activityInfo.packageName
        val (icon, logo) = cachedIconPngs(pkg) { info.loadIcon(pm) }
        return buildMap {
            put("package", pkg)
            put("label", info.loadLabel(pm).toString())
            put("icon", icon)
            if (logo != null) put("logo", logo)
        }
    }

    /**
     * The icon PNG, and for an adaptive icon its foreground layer alone (the
     * logo, without the app's own background) as a full 108dp-square PNG.
     *
     * From the cache, keyed by the app's last update time so an updated app
     * gets its new icon. Rendering ~150 icons is what made the first load
     * slow; reading cached files is quick.
     */
    private fun cachedIconPngs(pkg: String, load: () -> Drawable): Pair<ByteArray, ByteArray?> {
        val updated = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.packageManager
                    .getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0)).lastUpdateTime
            } else {
                @Suppress("DEPRECATION")
                activity.packageManager.getPackageInfo(pkg, 0).lastUpdateTime
            }
        } catch (e: PackageManager.NameNotFoundException) {
            0L
        }
        val dir = File(activity.cacheDir, "app_icons").apply { mkdirs() }
        val file = File(dir, "$pkg-$updated.png")
        // An empty logo file = not an adaptive icon.
        val logoFile = File(dir, "$pkg-$updated.logo.png")
        if (file.exists() && logoFile.exists()) {
            try {
                return file.readBytes() to logoFile.readBytes().takeIf { it.isNotEmpty() }
            } catch (e: Exception) {
                // Fall through and re-render.
            }
        }
        val drawable = load()
        val png = drawableToPng(drawable)
        val logo = logoPng(drawable)
        try {
            dir.listFiles { f -> f.name.startsWith("$pkg-") }?.forEach { it.delete() }
            file.writeBytes(png)
            logoFile.writeBytes(logo ?: ByteArray(0))
        } catch (e: Exception) {
            // A cache miss next time is fine.
        }
        return png to logo
    }

    /** An adaptive icon's foreground layer, or null for other icons. */
    private fun logoPng(drawable: Drawable): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val foreground = (drawable as? AdaptiveIconDrawable)?.foreground ?: return null
        return try {
            drawableToPng(foreground, LOGO_PIXELS)
        } catch (e: Exception) {
            null
        }
    }

    private fun drawableToPng(drawable: Drawable, size: Int = 96): ByteArray {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    /**
     * Asks the launcher to pin a shortcut that opens [pkg] with the themed
     * [icon] (an adaptive-icon PNG). The launcher shows its own confirm dialog.
     */
    private fun pinShortcut(
        id: String,
        pkg: String,
        label: String,
        icon: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", "Themed icons need Android 8 or newer", null)
            return
        }
        val manager = activity.getSystemService(ShortcutManager::class.java)
        if (manager == null || !manager.isRequestPinShortcutSupported) {
            result.error("unsupported", "Your home screen app doesn't support adding icons", null)
            return
        }
        val launch = activity.packageManager.getLaunchIntentForPackage(pkg)
        if (launch == null) {
            result.error("not_found", "$label isn't installed any more", null)
            return
        }
        val bitmap = BitmapFactory.decodeByteArray(icon, 0, icon.size)
        if (bitmap == null) {
            result.error("bad_icon", "Could not decode the icon", null)
            return
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val shortcut = ShortcutInfo.Builder(activity, id)
            .setShortLabel(label)
            .setIcon(Icon.createWithAdaptiveBitmap(bitmap))
            .setIntent(launch)
            .build()
        try {
            // Refresh an icon pinned earlier (e.g. after an accent change).
            manager.updateShortcuts(listOf(shortcut))
            result.success(manager.requestPinShortcut(shortcut, null))
        } catch (e: Exception) {
            result.error("pin_failed", e.message, null)
        }
    }

    // ---- Launcher ----

    private fun launchApp(pkg: String): Boolean {
        val intent = activity.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun openAppInfo(pkg: String): Boolean = try {
        activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", pkg, null)),
        )
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    /** Opens wallp Home (wallp's own home screen), wherever the user is. */
    private fun goHome(): Boolean = try {
        activity.startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .setPackage(activity.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    private fun isDefaultHome(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = activity.getSystemService(RoleManager::class.java)
            if (roles != null && roles.isRoleAvailable(RoleManager.ROLE_HOME)) {
                return roles.isRoleHeld(RoleManager.ROLE_HOME)
            }
        }
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = activity.packageManager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)
        return resolved?.activityInfo?.packageName == activity.packageName
    }

    /**
     * Shows Android's "default home app" dialog (or the Settings page where
     * it's chosen) and answers with whether wallp is the home app once the
     * user comes back. When wallp already is the home app, the role dialog
     * can't switch away from it, so this opens the Settings page instead.
     */
    private fun requestDefaultHome(result: MethodChannel.Result) {
        // Only one request at a time; settle an older one.
        pendingHomeResult?.success(isDefaultHome())
        pendingHomeResult = null

        val intents = mutableListOf<Intent>()
        if (!isDefaultHome() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = activity.getSystemService(RoleManager::class.java)
            if (roles != null && roles.isRoleAvailable(RoleManager.ROLE_HOME)) {
                intents += roles.createRequestRoleIntent(RoleManager.ROLE_HOME)
            }
        }
        intents += Intent(Settings.ACTION_HOME_SETTINGS)
        // Some OEM skins don't have the Home settings page.
        intents += Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
        intents += Intent(Settings.ACTION_SETTINGS)

        for (intent in intents) {
            try {
                @Suppress("DEPRECATION")
                activity.startActivityForResult(intent, REQUEST_HOME_ROLE)
                pendingHomeResult = result
                return
            } catch (e: ActivityNotFoundException) {
                // Try the next one.
            }
        }
        result.success(false)
    }

    /** Forwarded from the activity; true if it was our request. */
    fun onActivityResult(requestCode: Int): Boolean {
        if (requestCode == REQUEST_LIVE_WALLPAPER) {
            onLivePickerClosed()
            return true
        }
        if (requestCode != REQUEST_HOME_ROLE) return false
        pendingHomeResult?.success(isDefaultHome())
        pendingHomeResult = null
        return true
    }

    companion object {
        private const val WALLPAPER_CHANNEL = "wallp/wallpaper"
        private const val ICONS_CHANNEL = "wallp/icons"
        private const val LAUNCHER_CHANNEL = "wallp/launcher"
        private const val REQUEST_HOME_ROLE = 4201
        private const val REQUEST_LIVE_WALLPAPER = 4202

        /** An adaptive icon's foreground is 108dp; this keeps its logo sharp. */
        private const val LOGO_PIXELS = 192

        /** A picker that closes faster than this never showed. */
        private const val LIVE_PICKER_GLITCH_MS = 1500L
    }
}
