# How wallp Works — A Step-by-Step Guide

This guide explains how the **wallp** app works, from the moment it starts to the moment a themed wallpaper and themed icons show on the phone. Read it from top to bottom the first time; after that you can jump to any section.

---

## Table of contents

1. [What the app does](#1-what-the-app-does)
2. [The big picture: 3 apps in 1](#2-the-big-picture-3-apps-in-1)
3. [Folder map](#3-folder-map)
4. [Step 1 — The app starts (`main.dart`)](#4-step-1--the-app-starts-maindart)
5. [Step 2 — Where themes come from (models + catalog)](#5-step-2--where-themes-come-from-models--catalog)
6. [Step 3 — How a wallpaper is drawn (scenes)](#6-step-3--how-a-wallpaper-is-drawn-scenes)
7. [Step 4 — The theme store screens](#7-step-4--the-theme-store-screens)
8. [Step 5 — Pressing "Apply" (the most important flow)](#8-step-5--pressing-apply-the-most-important-flow)
9. [Step 6 — Saving data (SharedPreferences)](#9-step-6--saving-data-sharedpreferences)
10. [Step 7 — Talking to Android (MethodChannels)](#10-step-7--talking-to-android-methodchannels)
11. [Step 8 — wallp Home (the launcher)](#11-step-8--wallp-home-the-launcher)
12. [Step 9 — The live wallpaper](#12-step-9--the-live-wallpaper)
13. [Step 10 — Themed app icons](#13-step-10--themed-app-icons)
14. [Android vs iOS](#14-android-vs-ios)
15. [Tests](#15-tests)
16. [How to add a new theme](#16-how-to-add-a-new-theme)
17. [Glossary](#17-glossary)
18. [Suggested reading order](#18-suggested-reading-order)

---

## 1. What the app does

wallp is a **seasonal phone theme** app built with **Flutter** (Dart) plus some **Kotlin** code for Android.

A "theme" is a festival look, for example **Halloween**, **Christmas** or **Thingyan (Water Festival)**. One theme changes:

| Part of the phone | What wallp does |
|---|---|
| Wallpaper (home + lock) | Draws a picture of the festival scene and sets it as the wallpaper |
| Live wallpaper | Plays the same scene **animated** (bats flying, snow falling, water splashing) |
| Home screen | wallp has its **own home screen app** ("wallp Home") with themed icons, a clock and a countdown |
| App icons | Every app icon is redrawn in the festival style |
| Countdown | Shows "17 nights left" until the festival |

Important idea: **there are no image files for wallpapers.** Every scene is drawn by Dart code using a `Canvas` (like drawing with a pen in code). This is why the app is small and why the user can change the accent color instantly.

---

## 2. The big picture: 3 apps in 1

The single APK contains **three separate entry points**. Each one runs its own Flutter engine:

```
                          ONE APK  (com.example.wallp)
 ┌───────────────────────┬────────────────────────┬──────────────────────────┐
 │  MainActivity.kt      │  LauncherActivity.kt   │  LiveWallpaperService.kt │
 │  (normal app icon)    │  (Android "Home" app)  │  (Android live wallpaper)│
 │          │            │           │            │            │             │
 │          ▼            │           ▼            │            ▼             │
 │   Dart: main()        │   Dart: launcherMain() │   Dart: wallpaperMain()  │
 │   WallpApp            │   LauncherApp          │   LiveWallpaperApp       │
 │   = THEME STORE       │   = wallp HOME         │   = ANIMATED WALLPAPER   │
 └──────────┬────────────┴───────────┬────────────┴────────────┬─────────────┘
            │                        │                         │
            └──────────── share data through ──────────────────┘
                     SharedPreferences (phone storage)
                "applied_theme_id", "applied_accent", ...
```

| Part | What the user sees | Native side | Dart entry |
|---|---|---|---|
| **Theme store** | The app you open from the app icon: browse, preview, apply | [MainActivity.kt](../android/app/src/main/kotlin/com/example/wallp/MainActivity.kt) | `main()` → [app.dart](../lib/app.dart) |
| **wallp Home** | The phone's home screen (after the user picks wallp as default home app) | [LauncherActivity.kt](../android/app/src/main/kotlin/com/example/wallp/LauncherActivity.kt) | `launcherMain()` → [launcher_app.dart](../lib/launcher/launcher_app.dart) |
| **Live wallpaper** | The animated background behind everything | [LiveWallpaperService.kt](../android/app/src/main/kotlin/com/example/wallp/LiveWallpaperService.kt) | `wallpaperMain()` → [live_wallpaper_app.dart](../lib/live_wallpaper/live_wallpaper_app.dart) |

Because they are **separate engines**, they cannot share Dart variables in memory. They communicate only by **writing and reading the phone's storage** (SharedPreferences). Keep this in mind — it explains many design choices later.

All three are registered in [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml):

- `MainActivity` has category `LAUNCHER` → it shows in the app list.
- `LauncherActivity` has category `HOME` → it shows in Android's "Default home app" list.
- `LiveWallpaperService` has action `WallpaperService` → it shows in the live wallpaper picker.

---

## 3. Folder map

```
lib/
├── main.dart                 3 entry points (store, home, live wallpaper)
├── app.dart                  Theme store root widget
├── core/                     Colors, app theme (dark Material theme), date text
├── models/                   Data classes: PhoneTheme, ThemePalette, ThemeEvent, ...
├── data/theme_catalog.dart   THE LIST of all themes and categories
├── scenes/                   Painters that draw each festival scene
├── icons/                    Themed app icon painter + app → symbol matching
├── screens/                  Theme store screens (Explore, Detail, My Themes, Settings, Icons)
├── widgets/                  Reusable pieces (cards, buttons, sheets, overlays)
├── services/                 Logic: save data, set wallpaper, talk to Android
├── launcher/                 wallp Home (home screen) code
└── live_wallpaper/           Live wallpaper root widget

android/app/src/main/kotlin/com/example/wallp/
├── MainActivity.kt           Hosts the theme store
├── LauncherActivity.kt       Hosts wallp Home (transparent)
├── LiveWallpaperService.kt   Runs Flutter inside the wallpaper surface
└── NativeBridge.kt           All Android features Dart asks for

docs/                         Design docs (future Theme API, dashboard) + this guide
test/                         Widget and unit tests
```

Packages used ([pubspec.yaml](../pubspec.yaml)):

| Package | Used for |
|---|---|
| `provider` | Share the `MyThemes` state with all store screens |
| `shared_preferences` | Save data on the phone |
| `google_fonts` | Theme fonts (Creepster, Playfair Display, Baloo 2, Padauk…) |
| `gal` | iOS only: save the wallpaper image to Photos |

---

## 4. Step 1 — The app starts (`main.dart`)

Open [main.dart](../lib/main.dart). It has three functions:

```dart
void main()           { _setUp(); runApp(const WallpApp()); }       // theme store
@pragma('vm:entry-point')
void launcherMain()   { _setUp(); runApp(const LauncherApp()); }    // home screen
@pragma('vm:entry-point')
void wallpaperMain()  { ...;      runApp(const LiveWallpaperApp()); } // live wallpaper
```

- `main()` is the normal Flutter entry point.
- `@pragma('vm:entry-point')` tells the Dart compiler: "keep this function, Kotlin will call it by name". Without it, the compiler would remove `launcherMain` and `wallpaperMain` because no Dart code calls them.
- On the Kotlin side, `LauncherActivity` returns `"launcherMain"` from `getDartEntrypointFunctionName()`, and `LiveWallpaperService` starts an engine with `DartEntrypoint(bundle, "wallpaperMain")`.
- `_setUp()` makes the status bar transparent with light icons.

### What `WallpApp` does ([app.dart](../lib/app.dart))

```dart
ChangeNotifierProvider(
  create: (_) => MyThemes()..load(),   // load favourites + history from storage
  child: MaterialApp(theme: AppTheme.dark(), home: const HomeShell()),
)
```

1. Creates **one** `MyThemes` object (favourites, history, accents) and loads it from storage.
2. Puts it in a `Provider`, so any screen can call `context.watch<MyThemes>()` or `context.read<MyThemes>()`.
3. Shows `HomeShell` — the screen with the bottom navigation bar.

---

## 5. Step 2 — Where themes come from (models + catalog)

### 5.1 The models ([lib/models/](../lib/models/))

[phone_theme.dart](../lib/models/phone_theme.dart) defines what a theme *is*:

```
PhoneTheme
├── id             'halloween-night'
├── categoryId     'halloween'          → which tab it belongs to
├── name           'Halloween'
├── subtitle       optional, e.g. 'သင်္ကြန်'
├── scene          SceneKind.halloween → which painter draws it
├── palette        ThemePalette
│   ├── background, deep, surface, text, textMuted
│   └── accentOptions [orange, green, purple]   (first = default)
├── displayFont    'Creepster'          (Google Font for big text/clock)
├── bodyFont       'Space Grotesk'
├── event          ThemeEvent(name 'Halloween', month 10, day 31, unit 'night')
├── eventIcon      icon on the countdown card
├── accentClock    draw the clock in the accent color?
└── hasIconPack    has themed app icons?
```

`ThemeEvent` contains the countdown math:

- `nextDate(now)` → the next 31 Oct (this year, or next year if already passed).
- `daysUntil(now)` → whole days left (uses UTC dates so daylight-saving time doesn't break the count).
- `countdownLabel(now)` → `"17 nights left"`, `"1 day left"` or `"Happy Halloween!"`.

[theme_category.dart](../lib/models/theme_category.dart) is a tab (`Halloween`, `Christmas`, …). `comingSoon: true` means the tab shows "Coming soon".

[wallpaper_target.dart](../lib/models/wallpaper_target.dart) is where to apply: `home`, `lock`, `both`, `live`.

### 5.2 The catalog ([theme_catalog.dart](../lib/data/theme_catalog.dart))

This file is the **database** of the app — a hard-coded list:

- 5 categories: Halloween, Christmas, Thingyan, Kpop *(coming soon)*, Mid-Autumn *(coming soon)*.
- 3 themes: `halloween-night`, `christmas-eve`, `thingyan-water`.

Helper functions:

| Function | What it returns |
|---|---|
| `themesIn(categoryId)` | Themes for one tab |
| `nextUp(now)` | The theme whose festival is **soonest** (used for the "Next up" card and as the default theme) |
| `byId(id)` | Find a theme by its id (used when reading saved data) |

> Note: [docs/theme-api.md](theme-api.md) describes a future plan to load themes from a server instead of this hard-coded list.

---

## 6. Step 3 — How a wallpaper is drawn (scenes)

This is the "art engine" of the app. Files are in [lib/scenes/](../lib/scenes/).

### 6.1 The base painter ([scene_painter.dart](../lib/scenes/scene_painter.dart))

```dart
const kSceneSize = Size(390, 844);   // design size of every scene
const kSceneStillTime = 1.2;         // the moment used for still pictures
```

Every scene is designed on a **390 × 844** canvas (a phone-sized design). `ScenePainter` is the base class:

1. It gets a `time` value (seconds) and an `accent` color.
2. In `paint()`, it **scales** the 390×844 design to cover whatever size it is given (a small grid card, the full screen, or a 1080×2400 wallpaper bitmap). It uses "cover" scaling: `max(width/390, height/844)`, then centers it.
3. Then it calls `paintScene(canvas, t)`, which each festival implements.
4. `super(repaint: time)` means: **whenever `time` changes, repaint**. That is how animation works — no `setState` needed.

### 6.2 The three festival painters

| File | Draws |
|---|---|
| [halloween_scene.dart](../lib/scenes/halloween_scene.dart) | Moon, twinkling stars, flying bats, ghost, graveyard, jack-o'-lantern |
| [christmas_scene.dart](../lib/scenes/christmas_scene.dart) | Christmas night scene (tree, snow, star…) |
| [thingyan_scene.dart](../lib/scenes/thingyan_scene.dart) | Water festival scene (water, padauk flowers…) |

They were **ported from an SVG design** ("Main.dc.html") using the same coordinates. You will see `Path()..moveTo(...)..cubicTo(...)` — these are SVG paths rewritten in Dart.

### 6.3 Animation math ([scene_math.dart](../lib/scenes/scene_math.dart))

Small helpers that copy how CSS animations work:

| Helper | Meaning |
|---|---|
| `phase(t, period, delay)` | Where we are (0..1) in a repeating loop. E.g. a bat flies a 7-second loop. |
| `pingPong(p)` | Smooth 0 → 1 → 0 (for twinkling/glowing). |
| `keyframes(p, stops, values)` | Move through several values, like CSS `@keyframes`. |
| `lerp(a, b, t)` | Mix between a and b. |

Example: a bat's position = `keyframes(phase(t, 7), [0, .25, .5, .75, 1], [0, -16, -30, -12, 0])`.

### 6.4 Making it move ([scene_view.dart](../lib/scenes/scene_view.dart))

`SceneView` is the widget that shows a scene.

```
SceneView
 ├── scenePainterFor(theme, time, accent)  → picks Halloween/Christmas/Thingyan painter
 ├── _time = ValueNotifier<double>(1.2)    → the clock the painter listens to
 └── driver:
       • normal: a Ticker (every display frame, ~60–120 fps)
       • maxFps set (live wallpaper = 30): a Timer instead, cheaper on battery
```

Rules in `_syncTicker()`:

- Animate only if `animate: true`.
- **Stop** if the user turned on "reduce motion" in phone accessibility settings.
- With `maxFps`, also stop while the app is not visible.

Battery-saving tricks used across the app:

- `HomeShell` wraps hidden tabs in `TickerMode(enabled: false)` → hidden tabs stop animating.
- `ThemeDetailScreen` animates **only the visible page**.
- Grid cards are not animated.

### 6.5 Turning a scene into a PNG ([wallpaper_renderer.dart](../lib/services/wallpaper_renderer.dart))

To set a normal (non-live) wallpaper we need an image file:

1. Create a painter with `time = 1.2` (a nice still frame: bats mid-flight).
2. Draw it onto a `PictureRecorder` canvas at the **real screen pixel size**.
3. `picture.toImage(width, height)` → `toByteData(png)` → bytes.

Only the scene is drawn — no clock or icons, because the phone adds its own.

---

## 7. Step 4 — The theme store screens

```
HomeShell (bottom nav)
 ├── Explore ───────────► ThemeDetailScreen ──► IconPackScreen
 ├── My Themes ─────────► ThemeDetailScreen
 └── Settings  ─────────► ThemeDetailScreen
```

### 7.1 `HomeShell` ([home_shell.dart](../lib/screens/home_shell.dart))

- Bottom `NavigationBar` with 3 tabs. Uses `IndexedStack` so each tab keeps its scroll position.
- On **resume** (user comes back to the app) it calls `MyThemes.load()` again — because wallp Home (another engine) may have changed the saved data.

### 7.2 Explore ([explore_screen.dart](../lib/screens/explore_screen.dart))

From top to bottom:

1. Title "wallp / Seasonal themes".
2. **Next up card** ([next_up_card.dart](../lib/widgets/next_up_card.dart)) — the festival coming soonest, with countdown.
3. **Category chips** ([category_chips.dart](../lib/widgets/category_chips.dart)). The selected chip starts on the next-up festival's category.
4. Either **"Coming soon"** ([empty_state.dart](../lib/widgets/empty_state.dart)) or a 2-column **grid of `ThemeCard`s** ([theme_card.dart](../lib/widgets/theme_card.dart)). Card height is computed from the 390:844 ratio so previews are never stretched.

Tapping any card → `Navigator.push(ThemeDetailScreen(theme))`.

### 7.3 Theme detail ([theme_detail_screen.dart](../lib/screens/theme_detail_screen.dart))

```
┌──────────────────────────────┐
│ ←       Halloween         ♡  │  AppBar + FavoriteButton
│   ┌──────┐ ┌──────┐ ┌──────┐ │
│   │ Lock │ │ Home │ │ Live │ │  PageView of 3 phone previews (swipe)
│   └──────┘ └──────┘ └──────┘ │
│     [ Lock | Home | Live ]   │  _ScreenTabs
│   Accent  ● ● ●              │  _AccentPicker
│   ⊞ Halloween app icons      │  → IconPackScreen (Android, hasIconPack)
│   [        Apply          ]  │  PrimaryButton
└──────────────────────────────┘
```

- Each preview is a `ThemePreview` ([theme_preview.dart](../lib/widgets/theme_preview.dart)): the `SceneView` + an overlay from [screen_overlays.dart](../lib/widgets/screen_overlays.dart):
  - `LockScreenOverlay` — big clock, date, countdown card.
  - `HomeScreenOverlay` — fake home screen with themed icons.
  - `LiveWallpaperOverlay` — shows it is the animated version.
- `LiveNow` ([live_now.dart](../lib/widgets/live_now.dart)) rebuilds with the current time so the preview clock is correct.
- Picking an accent calls `MyThemes.rememberAccent()` → next time you open this theme, that accent is selected.

### 7.4 My Themes ([my_themes_screen.dart](../lib/screens/my_themes_screen.dart))

Reads `MyThemes` with `context.watch` and shows: **current theme** (last applied), **favourites**, and **recently applied** (history without the first one). Empty → "Nothing here yet".

### 7.5 Settings ([settings_screen.dart](../lib/screens/settings_screen.dart))

- **Current theme** card.
- **Home screen card**: shows if wallp is the default home app; a button calls `LauncherService.requestDefaultHome()`.
- **Lock clock switch**: should the live wallpaper draw the themed clock on the lock screen? Saved by `ThemePrefs.saveLockClock()`.
- On iOS these Android-only cards are replaced with a message.

---

## 8. Step 5 — Pressing "Apply" (the most important flow)

Code: `_apply()` and `_ensureHomeApp()` in [theme_detail_screen.dart](../lib/screens/theme_detail_screen.dart).

```
User taps [Apply]
      │
      ▼
① _ensureHomeApp()
      │  Is wallp the default home app?  (Android only)
      ├── yes ──────────────────────────────────────────────┐
      └── no → show "Set wallp as your home app?" dialog     │
               │ Cancel → stop                               │
               │ OK:                                         │
               │   savePending(theme, accent)  ← safety net  │
               │   requestDefaultHome() → Android dialog     │
               │   clearPending()                            │
               │   not default? → snackbar, stop             │
               ▼                                             │
      ◄──────────────────────────────────────────────────────┘
      ▼
② showApplySheet()  → Home / Lock / Both / Live   (iOS: always "both")
      │
      ├── Live ──► recordApplied(theme, accent)       (save FIRST)
      │            openLiveWallpaper() → Android preview → user taps "Set wallpaper"
      │            snackbar 'Tap "Set wallpaper"…'
      │
      └── Home/Lock/Both ──►
             WallpaperService.apply()
               ├ ask Android for real screen size ("screenSize")
               ├ WallpaperRenderer.renderPng()    → PNG bytes
               ├ Android: "setWallpaper" {bytes, target}  → WallpaperManager.setBitmap
               └ iOS: Gal.putImageBytes()  → saved to Photos
             recordApplied(theme, accent)
             snackbar "Wallpaper set on home screen"
```

### Why the "pending apply" trick?

When the user picks wallp as the default home app, **Android immediately jumps to the new home screen** (wallp Home). The theme store may be paused or killed, so it might never finish step ②.

Solution:

1. Before asking, the store saves `pending_apply = {theme, accent, at: time}` ([theme_prefs.dart](../lib/services/theme_prefs.dart) → `savePending`).
2. When **wallp Home** starts, it calls `MyThemes.applyPending()` → `takePending()`:
   - reads the pending entry and deletes it,
   - ignores it if older than **10 minutes** (`pendingMaxAge`),
   - otherwise records it as applied and shows "Halloween applied".
3. If the store *does* come back normally, it calls `clearPending()` and continues itself.

### What `recordApplied()` saves ([my_themes.dart](../lib/services/my_themes.dart))

1. Puts the theme at the top of **history** (one entry per theme, max 10).
2. Remembers the **accent** for that theme.
3. Calls `ThemePrefs.save(theme, accent)` → writes `applied_theme_id` + `applied_accent`. **This is what wallp Home and the live wallpaper read.**

---

## 9. Step 6 — Saving data (SharedPreferences)

There are two classes that save data:

| Class | Keys | Who reads it |
|---|---|---|
| `MyThemes` ([my_themes.dart](../lib/services/my_themes.dart)) — a `ChangeNotifier` | `my_favorites` (list of ids), `my_history` (JSON), `my_accents` (JSON map id → ARGB int) | Theme store screens |
| `ThemePrefs` ([theme_prefs.dart](../lib/services/theme_prefs.dart)) | `applied_theme_id`, `applied_accent`, `lock_clock`, `pending_apply` | Store, wallp Home, live wallpaper |
| `HomeStore` ([home_arrangement.dart](../lib/launcher/home_arrangement.dart)) | `home_arrangement` (JSON pages + dock) | wallp Home |

Key points:

- They use **`SharedPreferencesAsync`** (not the older `SharedPreferences`). The async version has **no in-memory cache**, so when one engine writes, another engine reads the fresh value. With a cache, wallp Home would see old data.
- Colors are saved as ARGB integers (`color.toARGB32()`).
- Saved ids are checked with `ThemeCatalog.byId()`; unknown ids are dropped (safe if a theme is removed later).
- Broken JSON → start fresh instead of crashing.
- `ThemePrefs.load()` falls back to `ThemeCatalog.nextUp(now)` if nothing was ever applied.

`MyThemes` calls `notifyListeners()` after each change, so all screens that `watch` it rebuild (for example the ♡ button and My Themes tab).

---

## 10. Step 7 — Talking to Android (MethodChannels)

Dart cannot set a wallpaper or list installed apps by itself. It asks Kotlin through **MethodChannels**: a named pipe where Dart sends `invokeMethod('name', args)` and Kotlin replies.

All handlers are in [NativeBridge.kt](../android/app/src/main/kotlin/com/example/wallp/NativeBridge.kt). Both `MainActivity` and `LauncherActivity` create their own `NativeBridge`.

### Channel `wallp/wallpaper` — Dart: [wallpaper_service.dart](../lib/services/wallpaper_service.dart)

| Method | Kotlin does |
|---|---|
| `screenSize` | Returns real display `[width, height]` in pixels (portrait) |
| `setWallpaper {bytes, target}` | On a background thread: decode PNG → `WallpaperManager.setBitmap(bitmap, flags)` with `FLAG_SYSTEM` (home), `FLAG_LOCK` (lock) or both |
| `openLiveWallpaper` | Opens Android's live wallpaper preview for `LiveWallpaperService` (or the general chooser as a fallback) |

### Channel `wallp/icons` — Dart: [icon_pack_service.dart](../lib/services/icon_pack_service.dart)

| Method | Kotlin does |
|---|---|
| `listApps` | All launchable apps → `{package, label, icon PNG}`, sorted by label. Icons are **cached** in `cacheDir/app_icons/<pkg>-<lastUpdateTime>.png` so the second load is fast |
| `getApp {package}` | One app (used when an app is installed/updated) |
| `canPinShortcuts` | Can the current launcher accept pinned shortcuts? |
| `pinShortcut {id, package, label, icon}` | Creates a home-screen shortcut with the themed icon that opens the real app |

### Channel `wallp/launcher` — Dart: [launcher_service.dart](../lib/services/launcher_service.dart)

| Direction | Method | Meaning |
|---|---|---|
| Dart → Kotlin | `launchApp`, `appInfo` | Open an app / its Settings page |
| Dart → Kotlin | `openThemes` | Open the theme store (MainActivity) from wallp Home |
| Dart → Kotlin | `isDefaultHome` | Uses `RoleManager.ROLE_HOME` (Android 10+) or resolves the HOME intent |
| Dart → Kotlin | `requestDefaultHome` | Shows the role dialog or Home settings; answers **after the user comes back** (`onActivityResult`) |
| Kotlin → Dart | `homePressed` | Home button pressed while already on wallp Home |
| Kotlin → Dart | `appsChanged {packages, removed}` | An app was installed/removed/updated (`LauncherApps.Callback`) |

### Channel `wallp/live_wallpaper` — between `LiveWallpaperService.kt` and `LiveWallpaperApp`

| Direction | Method | Meaning |
|---|---|---|
| Dart → Kotlin | `showLockClock` | Should the themed clock show right now? |
| Kotlin → Dart | `lockClock(bool)` | Lock state changed (screen on/off, unlock) |

Dart always catches `MissingPluginException` / `PlatformException` and returns a safe value (`false`/`null`). This keeps tests and iOS from crashing.

---

## 11. Step 8 — wallp Home (the launcher)

Files: [lib/launcher/](../lib/launcher/). Root widget: [launcher_home.dart](../lib/launcher/launcher_home.dart).

### 11.1 How it is shown over the real wallpaper

- `LauncherActivity.kt` uses `BackgroundMode.transparent`.
- `LauncherApp` sets `scaffoldBackgroundColor: Colors.transparent`.
- Result: the **system wallpaper** (which wallp set) shows behind the Flutter icons.

### 11.2 Layout

```
┌──────────────────────────────┐
│          10:42               │  _ClockHeader (theme font, accent)
│   Thu 15 Oct · 16 nights left│  countdown
│                              │
│   [icon][icon][icon][icon]   │  PageView of pages,
│   [icon][icon][icon][icon]   │  16 slots per page (HomeArrangement.pageSlots)
│   ...                        │
│            • ○ ○             │  _PageDots
│          ⌃ All apps          │  _AllAppsHint
│  [phone][msgs][web][camera]  │  dock, 4 slots
└──────────────────────────────┘
```

### 11.3 Start-up / resume (`_reload()`)

1. `_applyPending()` — finish a pending apply (see Step 5). Never throws.
2. `ThemePrefs.load()` → which theme + accent to use.
3. If the app list is older than 30 s: `installedApps()` from Kotlin.
4. Load the saved `HomeArrangement`; if none, build one with `HomeLayout.suggested(apps)`:
   - Dock: phone, messages, browser, camera (found by their glyph).
   - Home: well-known apps first (chat, photos, YouTube, maps, …), then alphabetical, max 12.
5. `retainInstalled()` removes apps that were uninstalled, then save.

It runs again **every time the home screen resumes**, so a newly applied theme appears right away.

### 11.4 `HomeArrangement` ([home_arrangement.dart](../lib/launcher/home_arrangement.dart))

Stores only **package names**: `pages: [[pkg, pkg, …], …]` and `dock: [pkg, …]`.

It is **immutable**: every change (`move`, `add`, `remove`, `addPage`, `withoutEmptyPages`) returns a **new** object. Then `_update(next)` does `setState` + save. If a page gets more than 16 apps, the extras "spill" onto the next page.

### 11.5 Gestures

| Gesture | Result |
|---|---|
| Tap an icon | `launchApp(package)` |
| Swipe up / flick up | Open the app drawer ([app_drawer.dart](../lib/launcher/app_drawer.dart)) |
| Long-press empty space | Menu: **Edit home screen** / **Change theme** (opens store) |
| Long-press an app | App menu (add/remove from home, App info) |
| Edit mode: drag icon | Move it between slots, pages, dock; hold at screen edge 600 ms → next page |
| Edit mode bar | Add apps ([add_apps_sheet.dart](../lib/launcher/add_apps_sheet.dart)), Add page, Done |
| Back button | Never leaves home; in edit mode it finishes editing |
| Home button (while home) | Close sheets/drawer, exit edit mode, or go to page 1 |

### 11.6 Icons on wallp Home

[launcher_icon.dart](../lib/launcher/launcher_icon.dart): if the theme `hasIconPack`, draw `ThemedIcon` (see Step 10); otherwise show the app's own icon.

---

## 12. Step 9 — The live wallpaper

### 12.1 Kotlin side ([LiveWallpaperService.kt](../android/app/src/main/kotlin/com/example/wallp/LiveWallpaperService.kt))

Android calls `onCreateEngine()` for each wallpaper instance (the real one and the preview can run together; they share code through a `FlutterEngineGroup`).

```
onCreate         → start a Flutter engine at "wallpaperMain", open channel, send settings
onSurfaceCreated → renderer.startRenderingToSurface(surface)   (Flutter draws into wallpaper)
onSurfaceChanged → set viewport size + min/max constraints (else Flutter draws 0×0!)
onVisibilityChanged(visible)
                 → visible:  appIsResumed()  + resend settings + lock state
                 → hidden:   appIsPaused()   → no frames → no battery used
onDestroy        → unregister receiver, destroy engine
```

Extra details:

- `sendSettings()` sends 24-hour format, font scale and dark mode — normally a `FlutterView` does this, but a wallpaper has no `FlutterView`.
- `watchLock()` listens for `SCREEN_ON`, `SCREEN_OFF`, `USER_PRESENT` and tells Dart if the lock screen is showing.
- `showLockClock()`: always true in preview; on Android 14+ uses `wallpaperFlags` (lock-only vs home-only engine); otherwise asks `KeyguardManager`.

### 12.2 Dart side ([live_wallpaper_app.dart](../lib/live_wallpaper/live_wallpaper_app.dart))

1. `_load()` reads the applied theme + `lock_clock` setting from `ThemePrefs`.
2. On every **resume** (wallpaper visible again) it reloads → if the user applied another theme in the store, the wallpaper switches.
3. Draws `SceneView(animate: true, maxFps: 30)` full screen.
4. If `lock_clock` is on **and** the phone is locked, draws `LockScreenOverlay` (themed clock + countdown) at 30% height, and a timer redraws it every minute.

Why draw a clock? Apps cannot restyle Android's own lock screen clock, so wallp draws its themed clock inside the wallpaper.

---

## 13. Step 10 — Themed app icons

### 13.1 Which symbol for which app ([app_glyphs.dart](../lib/icons/app_glyphs.dart))

A list of rules matches an app by **package name fragment** or **exact label**:

- `whatsapp`, `telegram`, `viber` → chat bubbles icon
- `dialer` or label "phone" → phone icon
- `chrome`, `firefox`, `browser` → globe icon
- …first match wins, so specific rules come first.

No match → the app's own icon is used, recolored.

### 13.2 Drawing the icon ([themed_icon_painter.dart](../lib/icons/themed_icon_painter.dart))

`ThemedIconPainter` draws an **Android adaptive icon** (108×108 units; the important part stays inside 18..90 because launchers mask the edges):

- Glowing tile in festival colors.
- Decorations: Halloween = cobweb + moon; Christmas = snow + ornament + flakes; Thingyan = padauk flowers + wave.
- Accent ring.
- The glyph, in the accent color **only if contrast ≥ 3:1**, otherwise the festival's light text color (accessibility).

`ThemedIcon` is the widget version used in previews and wallp Home.

### 13.3 Two ways icons reach the phone

| Way | When | How |
|---|---|---|
| **wallp Home** (main way) | wallp is the default home app | wallp Home draws every icon itself with `ThemedIcon` |
| **Pinned shortcuts** ([icon_pack_screen.dart](../lib/screens/icon_pack_screen.dart)) | Another launcher is used and it supports pinning | Render 432×432 PNG → `pinShortcut` → launcher shows its own "Add to home screen?" dialog. The shortcut opens the real app |

---

## 14. Android vs iOS

| Feature | Android | iOS |
|---|---|---|
| Set wallpaper | Directly via `WallpaperManager` | Not allowed by Apple → image saved to **Photos**; user sets it in Settings |
| Button text | "Apply" | "Save to Photos" |
| Home/Lock/Live choice | Yes | No (always "both") |
| Live wallpaper | Yes | No |
| wallp Home / themed icons | Yes | No (Settings shows a message) |

The checks are `WallpaperService.canSetDirectly` and `LauncherService.isSupported` (both = "is Android").

---

## 15. Tests

Folder [test/](../test/). Run with:

```bash
flutter test
```

| Test file | Checks |
|---|---|
| `theme_catalog_test.dart` | Catalog data, `nextUp`, countdown math |
| `scene_test.dart` | Painters draw without errors |
| `wallpaper_renderer_test.dart` | PNG rendering |
| `theme_detail_test.dart` | Detail screen and apply flow |
| `my_themes_test.dart` | Favourites, history, pending apply |
| `settings_test.dart` | Settings screen |
| `launcher_test.dart`, `home_arrangement_test.dart` | wallp Home and arrangement logic |
| `live_wallpaper_test.dart` | Live wallpaper widget |
| `icon_pack_test.dart`, `themed_icon_test.dart` | Icons |

Many classes accept fake dependencies in their constructors (e.g. `LauncherHome(appsService: ..., prefs: ..., store: ...)`, `LiveWallpaperApp(clock: ...)`). This is **dependency injection**, so tests can pass fakes instead of real Android calls.

---

## 16. How to add a new theme

Example: a Kpop theme.

1. **Painter** — create `lib/scenes/kpop_scene.dart` with `class KpopPainter extends ScenePainter` and implement `paintScene(canvas, t)` in 390×844 coordinates.
2. **Scene kind** — add `kpop` to `enum SceneKind` in [phone_theme.dart](../lib/models/phone_theme.dart).
3. **Register** — add `SceneKind.kpop => KpopPainter(...)` in `scenePainterFor()` in [scene_view.dart](../lib/scenes/scene_view.dart).
4. **Icons** — add tile colors for `SceneKind.kpop` in `ThemedIconPainter._tiles` and its decorations (or set `hasIconPack: false`).
5. **Catalog** — add a `PhoneTheme(...)` to `ThemeCatalog.themes` and remove `comingSoon: true` from the Kpop category in [theme_catalog.dart](../lib/data/theme_catalog.dart).
6. **Test** — run `flutter test` and look at the preview on a phone.

Dart's `switch` on an enum must cover every value, so the compiler will point you to any place you forgot.

---

## 17. Glossary

| Word | Meaning |
|---|---|
| **Flutter engine** | One running copy of Flutter + Dart. wallp can run up to 3 at once. |
| **Entry point** | The Dart function an engine starts with (`main`, `launcherMain`, `wallpaperMain`). |
| **Activity** | An Android screen (`MainActivity`, `LauncherActivity`). |
| **Service** | Android background component; `LiveWallpaperService` draws the wallpaper. |
| **MethodChannel** | Named message pipe between Dart and Kotlin. |
| **CustomPainter** | Flutter class that draws on a `Canvas` with code. |
| **Ticker** | Calls a function every display frame; drives animation. |
| **ValueNotifier** | Holds a value and tells listeners when it changes (`_time`). |
| **ChangeNotifier / Provider** | Shared state (`MyThemes`) that screens can watch. |
| **SharedPreferences** | Small key-value storage on the phone. |
| **Default home app** | The launcher Android shows when you press Home (ROLE_HOME). |
| **Adaptive icon** | Android icon format (108dp square, edges masked by the launcher). |
| **Accent** | The highlight color the user picks for a theme (3 options each). |

---

## 18. Suggested reading order

Read the code in this order to learn fastest:

1. [main.dart](../lib/main.dart) and [app.dart](../lib/app.dart) — start-up
2. [phone_theme.dart](../lib/models/phone_theme.dart) and [theme_catalog.dart](../lib/data/theme_catalog.dart) — the data
3. [scene_painter.dart](../lib/scenes/scene_painter.dart), [scene_math.dart](../lib/scenes/scene_math.dart), [scene_view.dart](../lib/scenes/scene_view.dart) — drawing + animation
4. [halloween_scene.dart](../lib/scenes/halloween_scene.dart) — one complete scene
5. [explore_screen.dart](../lib/screens/explore_screen.dart) → [theme_detail_screen.dart](../lib/screens/theme_detail_screen.dart) — the UI and the Apply flow
6. [my_themes.dart](../lib/services/my_themes.dart) and [theme_prefs.dart](../lib/services/theme_prefs.dart) — saving data
7. [wallpaper_service.dart](../lib/services/wallpaper_service.dart) + [NativeBridge.kt](../android/app/src/main/kotlin/com/example/wallp/NativeBridge.kt) — Dart ↔ Android
8. [launcher_home.dart](../lib/launcher/launcher_home.dart) + [home_arrangement.dart](../lib/launcher/home_arrangement.dart) — wallp Home
9. [LiveWallpaperService.kt](../android/app/src/main/kotlin/com/example/wallp/LiveWallpaperService.kt) + [live_wallpaper_app.dart](../lib/live_wallpaper/live_wallpaper_app.dart) — live wallpaper
10. [themed_icon_painter.dart](../lib/icons/themed_icon_painter.dart) + [app_glyphs.dart](../lib/icons/app_glyphs.dart) — themed icons

Then read [theme-api.md](theme-api.md) and [theme-dashboard.md](theme-dashboard.md) for the future plans.
