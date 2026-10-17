# How wallp Works — A Step-by-Step Guide

This guide explains how the **wallp** app works, from the moment it starts to the moment a themed wallpaper and themed icons show on the phone. Read it from top to bottom the first time; after that you can jump to any section.

**Up to date as of 17 Oct 2026:** the new 5-tab store, running on a mock Theme API ([store-redesign-plan.md](store-redesign-plan.md), phases 1–9 done).

---

## Table of contents

1. [What the app does](#1-what-the-app-does)
2. [The big picture: 3 apps in 1](#2-the-big-picture-3-apps-in-1)
3. [Folder map](#3-folder-map)
4. [Step 1 — The app starts (`main.dart`, `app.dart`)](#4-step-1--the-app-starts-maindart-appdart)
5. [Step 2 — Where themes come from (the catalog)](#5-step-2--where-themes-come-from-the-catalog)
6. [Step 3 — Downloads and the file cache](#6-step-3--downloads-and-the-file-cache)
7. [Step 4 — The applied look (one saved snapshot)](#7-step-4--the-applied-look-one-saved-snapshot)
8. [Step 5 — How a wallpaper is drawn (scenes)](#8-step-5--how-a-wallpaper-is-drawn-scenes)
9. [Step 6 — The store screens](#9-step-6--the-store-screens)
10. [Step 7 — Pressing "Apply" (the most important flow)](#10-step-7--pressing-apply-the-most-important-flow)
11. [Step 8 — Saved data (SharedPreferences and files)](#11-step-8--saved-data-sharedpreferences-and-files)
12. [Step 9 — Talking to Android (MethodChannels)](#12-step-9--talking-to-android-methodchannels)
13. [Step 10 — wallp Home (the launcher)](#13-step-10--wallp-home-the-launcher)
14. [Step 11 — The live wallpaper](#14-step-11--the-live-wallpaper)
15. [Step 12 — Themed app icons and fonts](#15-step-12--themed-app-icons-and-fonts)
16. [Android vs iOS](#16-android-vs-ios)
17. [Developer settings](#17-developer-settings)
18. [Tests](#18-tests)
19. [How to add a new theme](#19-how-to-add-a-new-theme)
20. [Glossary](#20-glossary)
21. [Suggested reading order](#21-suggested-reading-order)

---

## 1. What the app does

wallp is a **seasonal phone theme** app built with **Flutter** (Dart) plus some **Kotlin** code for Android.

A "theme" is a festival look, for example **Halloween**, **Christmas** or **Thingyan (Water Festival)**. One theme changes:

| Part of the phone | What wallp does |
|---|---|
| Wallpaper (home + lock) | Draws the festival scene and sets it as the wallpaper |
| Live wallpaper | Plays the same scene **animated** (bats flying, snow falling, water splashing) |
| Home screen | wallp has its **own home screen app** ("wallp Home") with themed icons, a clock and a countdown |
| App icons | Every app icon is redrawn in the festival style (or replaced by the icon pack's picture) |
| Clock font | The lock and home clock use the theme's font |
| Countdown | Shows "17 nights left" until the festival |

The user can also change each part on its own: a different wallpaper, clock font, icon pack, tile shape, accent colour or app name colour.

**Where themes come from.** Themes are **data**, not code. The app reads a *catalog* of themes in the format described in [theme-api.md](theme-api.md). Today that catalog is a mock bundled in the app; later it comes from a CDN, filled by the [dashboard](theme-dashboard.md). There are two kinds of theme:

| | Built-in | Dashboard-made |
|---|---|---|
| Examples | Halloween, Christmas, Thingyan | Thadingyut, Minimal, Cozy Cabin, … |
| Scene drawn by | A Dart painter written for it | The generic `layers` engine, from JSON layers |
| Icons | Painted by `ThemedIconPainter` | Downloaded pictures, one per app type |
| Download | Nothing | Images and fonts, a few hundred KB to a few MB |

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
          SharedPreferences  "applied_look"  (one JSON snapshot)
          + downloaded files on disk (images, fonts), pinned
```

| Part | What the user sees | Native side | Dart entry |
|---|---|---|---|
| **Theme store** | The app you open from the app icon: browse, preview, apply | [MainActivity.kt](../android/app/src/main/kotlin/com/example/wallp/MainActivity.kt) | `main()` → [app.dart](../lib/app.dart) |
| **wallp Home** | The phone's home screen (after the user picks wallp as default home app) | [LauncherActivity.kt](../android/app/src/main/kotlin/com/example/wallp/LauncherActivity.kt) | `launcherMain()` → [launcher_app.dart](../lib/launcher/launcher_app.dart) |
| **Live wallpaper** | The animated background behind everything | [LiveWallpaperService.kt](../android/app/src/main/kotlin/com/example/wallp/LiveWallpaperService.kt) | `wallpaperMain()` → [live_wallpaper_app.dart](../lib/live_wallpaper/live_wallpaper_app.dart) |

Because they are **separate engines**, they cannot share Dart variables in memory. They communicate only through the **phone's storage**: the store writes the applied look as one JSON snapshot and downloads its files; wallp Home and the live wallpaper read them. **wallp Home and the live wallpaper never use the network**: the live wallpaper can start right after a reboot, before any network or before the store ever ran. Keep this in mind; it explains many design choices later.

All three are registered in [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml):

- `MainActivity` has category `LAUNCHER` → it shows in the app list.
- `LauncherActivity` has category `HOME` → it shows in Android's "Default home app" list.
- `LiveWallpaperService` has action `WallpaperService` → it shows in the live wallpaper picker.

---

## 3. Folder map

```
lib/
├── main.dart                 3 entry points (store, home, live wallpaper)
├── app.dart                  Theme store root: providers + MaterialApp
├── catalog/                  The Theme API format: models + JSON parser (pure Dart)
├── data/
│   ├── catalog/              CatalogRepository, sources (mock), saved copy, built-in catalog
│   └── assets/               AssetCache (downloaded files), DownloadManager, Downloads list
├── look/                     AppliedLook (what's on the phone), LookStore, LookController,
│                             ResolvedLook, accents, event icons
├── store/                    The store UI: 5-tab shell, screens, apply flow, state, widgets
├── render/                   Layers engine painter, downloaded images, fonts, icon shapes
├── scenes/                   Built-in scene painters + SceneView (animation)
├── icons/                    Painted icon painter + app → glyph key matching
├── models/                   PhoneTheme: the drawing model the painters and overlays read
├── widgets/                  Phone previews, lock/home overlays, apply sheet, home dialog
├── services/                 Wallpaper, launcher and icon channels to Android
├── launcher/                 wallp Home (home screen) code
├── live_wallpaper/           Live wallpaper root widget
├── dev/                      Developer settings (debug builds only)
└── core/                     App theme, store colours, clock, app version, date text

android/app/src/main/kotlin/com/example/wallp/
├── MainActivity.kt           Hosts the theme store
├── LauncherActivity.kt       Hosts wallp Home (transparent)
├── LiveWallpaperService.kt   Runs Flutter inside the wallpaper surface
└── NativeBridge.kt           All Android features Dart asks for

assets/
├── builtin/catalog/          The catalog shipped for good: the 3 built-in themes
└── mock/catalog/v1/          The mock Theme API (demo catalog), laid out like the CDN

tool/seed/                    Generates both catalogs (and the test fixture) from Dart
docs/                         Theme API, dashboard, store plan + this guide
test/                         Unit and widget tests; test/fixtures/ has the full 30-theme catalog
```

Packages used ([pubspec.yaml](../pubspec.yaml)):

| Package | Used for |
|---|---|
| `provider` | Share state (catalog, look, user data, downloads) with all store screens |
| `shared_preferences` | Save small data on the phone |
| `path_provider` | Folders for the saved catalog and the file cache |
| `crypto` | sha256 checks of every downloaded file |
| `google_fonts` | Fallback for fonts not downloaded yet (to be removed, see section 15.3) |
| `gal` | iOS only: save the wallpaper image to Photos |

---

## 4. Step 1 — The app starts (`main.dart`, `app.dart`)

Open [main.dart](../lib/main.dart). It has three functions:

```dart
void main()           { _setUp(); runApp(const WallpApp()); }        // theme store
@pragma('vm:entry-point')
void launcherMain()   { _setUp(); runApp(const LauncherApp()); }     // home screen
@pragma('vm:entry-point')
void wallpaperMain()  { ...;      runApp(const LiveWallpaperApp()); } // live wallpaper
```

- `main()` is the normal Flutter entry point.
- `@pragma('vm:entry-point')` tells the Dart compiler: "keep this function, Kotlin will call it by name". Without it, the compiler would remove `launcherMain` and `wallpaperMain` because no Dart code calls them.
- On the Kotlin side, `LauncherActivity` returns `"launcherMain"` from `getDartEntrypointFunctionName()`, and `LiveWallpaperService` starts an engine with `DartEntrypoint(bundle, "wallpaperMain")`.
- `_setUp()` makes the status bar transparent with light icons.

### What `WallpApp` does ([app.dart](../lib/app.dart))

It creates the store's shared objects in a `MultiProvider`, so any screen can `context.watch<…>()` or `context.read<…>()` them:

| Provider | Job |
|---|---|
| `UserStore` | Favourites, history, per-theme accent picks, recent searches, Me settings |
| `DevSettings` + `Clock` | Developer switches; "now" for countdowns and badges (can be faked) |
| `MyAccents` | The user's saved custom accents, shared by every theme |
| `CatalogSource` | **Where catalog files come from.** Today `MockCatalogSource`; later an HTTP source. This is the only line that changes to use the real API |
| `AssetCache` + `DownloadManager` | Downloaded files and the downloads in progress |
| `CatalogRepository` (not lazy) | The catalog: loads at launch and refreshes in the background |
| `LookController` (not lazy) | What the phone looks like and every way to change it; at launch it re-pins the applied look's files and re-downloads any that are missing |
| `LiveWallpaperStatus` | Is wallp's live wallpaper on? Previews animate only then |

Then `MaterialApp` shows `StoreShell` (the 5 tabs), wrapped in:
- `StoreLookScope`: the store wears the applied theme's festival colours ("Match app to my theme").
- `DownloadOverlay`: the download progress card above every screen.

---

## 5. Step 2 — Where themes come from (the catalog)

### 5.1 The format ([lib/catalog/](../lib/catalog/))

The models for the Theme API: `Festival`, `ThemeSummary` / `ThemeDetail`, `Wallpaper`, `CatalogFont`, `IconPack`, `Banner`, `SceneSpec` and its `Layer`s, `Accent`, `AssetRef`, `Manifest`, `Catalog`. They are **pure Dart** (no Flutter), so the app, the tests and the seed generator in [tool/seed/](../tool/seed/) all use the same parser.

Each has `fromJson` (checks every field and says exactly which one broke, e.g. `themes[3].palette.background: expected "#RRGGBB"`) and `toJson`. The full field list is in [theme-api.md](theme-api.md) section 4.

Two things worth knowing:
- **Summary vs full theme.** The catalog lists a `ThemeSummary` per theme (enough for cards, filters and search). The full `ThemeDetail` (all accents, fonts, labels…) is a separate file, fetched when the user opens the theme.
- **Broken data is skipped, not fatal.** One bad theme is dropped and logged in `Catalog.issues`; items pointing at something missing (a theme whose icon pack is gone) are dropped too.

Countdowns live on `Festival`: `nextRun(now)` finds the next (or current) run from its list of real dates (`occurrences`, needed for Myanmar-calendar festivals) or its `fallbackDate`, and `countdown(now)` gives "16 nights left", "Happy Thingyan!" during its 4 days, or "Any time" for undated collections like Minimal.

### 5.2 The repository ([lib/data/catalog/](../lib/data/catalog/))

`CatalogRepository` is what screens read (`repo.catalog`, `repo.theme(id)`):

```
launch
  │
  ├─ saved catalog on disk?  ── yes → show it at once
  │                           └ no  → show the BUILT-IN catalog (works with no internet)
  ▼
background refresh:
  manifest.json → new catalogVersion? → download catalog → check sha256 → save → show
                → same version?       → nothing to do
                → unknown schema?     → keep what we have
```

| Class | Job |
|---|---|
| `CatalogSource` / [MockCatalogSource](../lib/data/catalog/mock_catalog_source.dart) | Reads files. The mock reads [assets/mock/catalog/v1/](../assets/mock/catalog/v1/) through a pretend network that can be slow, offline or flaky (section 17) |
| [CatalogStore](../lib/data/catalog/catalog_store.dart) | The saved copy (manifest, catalog, theme files) in the app's support folder, replaced in one step |
| [BuiltInCatalog](../lib/data/catalog/built_in_catalog.dart) | The catalog in the APK ([assets/builtin/catalog/](../assets/builtin/catalog/)): the 3 built-in themes. Used on first launch, and by wallp Home and the live wallpaper for the default look |

Before showing a catalog, the repository **hides what this app can't draw**: themes on an unknown engine, and themes or wallpapers whose `minAppVersion` is newer than the app.

Theme files are fetched on demand (`repo.theme(id)`) and saved by `rev`, so a theme opened once opens offline afterwards.

---

## 6. Step 3 — Downloads and the file cache

Code: [lib/data/assets/](../lib/data/assets/).

Dashboard-made themes need files: scene images, icon pictures and fonts. Every file is an `AssetRef` named by its **sha256**, so a file can never change under the same name.

| Class | Job |
|---|---|
| [AssetCache](../lib/data/assets/asset_cache.dart) | Files on disk by sha256. Checks hash and size on arrival, writes to a temp file and renames (never half a file). Keeps 50 MB, removing the least recently used, **except pinned files** |
| [DownloadManager](../lib/data/assets/download_manager.dart) | Downloads a list of files: 3 at a time, retries brief failures, progress, Cancel. Two screens asking for the same file share one download |
| [downloads.dart](../lib/data/assets/downloads.dart) | Me › Downloads: which dashboard themes are fully on the phone, and deleting one (keeping files the applied look still needs) |

**Pins** keep files safe from clean-up. There are three owners:
- `applied`: every file of the look on the phone. wallp Home and the live wallpaper need these.
- `pending`: a look waiting for wallp Home to finish applying it (section 10).
- `incoming`: files of an apply in progress, from arrival until the look is saved.

---

## 7. Step 4 — The applied look (one saved snapshot)

Code: [lib/look/](../lib/look/).

### 7.1 `AppliedLook` ([applied_look.dart](../lib/look/applied_look.dart))

Everything the phone shows, as **one object saved as JSON**:

```
AppliedLook
├── theme          the full ThemeDetail (a copy, not just an ID)
├── festival       for the countdown
├── variantId      optional colour variant
├── accent         the user's pick: theme accent, preset, or custom (solid or gradient)
├── clock          ClockStyle { fontId, size S/M/L, colour accent/text/#hex,
│                              places: lock screen / home clock / app labels }
├── icons          IconChoice { pack (full copy), shape, label colour, label font }
├── wallpaper      follow the theme  |  another theme's scene  |  a stand-alone wallpaper
├── fonts          every CatalogFont the look draws with (full copies)
└── appliedAt
```

Why copies instead of IDs? Because wallp Home and the live wallpaper must draw it **with no network and no catalog**, and a theme removed from the catalog must keep working on phones that applied it.

Each change builds a **new** look from the current one, so untouched parts stay: `withWallpaper`, `withClockFont`, `withIconPack`, `withAccent`, `withVariant`. `look.assets` lists every file it needs (scene images, icon pictures, font files).

The theme detail page's Apply sheet has three options (`ApplyOption`): **Whole theme**, **Wallpaper only** (keeps icons and font) and **Clock font only**.

### 7.2 `LookStore` ([look_store.dart](../lib/look/look_store.dart))

Saves the look under the key `applied_look`. If nothing was applied yet, the **default look** is the built-in theme of the soonest festival (not saved, so it moves on by itself). Older saves (`applied_theme_id` + `applied_accent`, from before the redesign) are moved over to a look the first time. A damaged save is deleted and treated as "nothing applied".

It also keeps the **pending look** (`pending_look`) for the home-app switch (section 10).

### 7.3 `LookController` ([look_controller.dart](../lib/look/look_controller.dart))

Every way the store changes the look: `applyTheme`, `applyWallpaper`, `useThemeWallpaper`, `applyClockFont`, `applyIconPack`, `setAccent`, `setVariant`. Each one:

1. Builds the next look.
2. Pins its files as `incoming`, then **downloads everything it needs** (`prepare`). If that fails or is cancelled, it stops here: **the old look stays**.
3. Saves the look, pins its files as `applied`, releases the old pins.

Changes run **one at a time, in order**, so two quick taps can't overwrite each other.

### 7.4 `ResolvedLook` ([resolved_look.dart](../lib/look/resolved_look.dart))

The painters and overlays draw a `PhoneTheme` ([phone_theme.dart](../lib/models/phone_theme.dart)), the app's drawing model. `ResolvedLook.of(look, now)` turns a look into one `PhoneTheme` **per screen**, because they can differ:

| Field | Used by | Can differ because |
|---|---|---|
| `lockTheme` | Live wallpaper's lock clock and countdown | The clock font may be on the lock screen only |
| `homeTheme` | wallp Home: clock, icons, app names | Icon pack, tile shape, label colour and font |
| `wallpaperTheme` | The scene | "Wallpaper only" or a stand-alone wallpaper |

It also works out the colours: accent, clock colour, the accent as a gradient, and a readable colour for text on the accent.

---

## 8. Step 5 — How a wallpaper is drawn (scenes)

This is the "art engine" of the app.

### 8.1 The base painter ([scene_painter.dart](../lib/scenes/scene_painter.dart))

```dart
const kSceneSize = Size(390, 844);   // design size of every scene
const kSceneStillTime = 1.2;         // the moment used for still pictures
```

Every scene is designed on a **390 × 844** canvas. `ScenePainter` is the base class:

1. It gets a `time` value (seconds) and an `accent` colour.
2. In `paint()`, it **scales** the 390×844 design to cover whatever size it is given (a small card, the full screen, or a 1080×2400 wallpaper bitmap): `max(width/390, height/844)`, centred.
3. Then it calls `paintScene(canvas, t)`, which each scene implements.
4. `super(repaint: time)` means: **whenever `time` changes, repaint**. That is how animation works, with no `setState`.

### 8.2 Which painter? (`scenePainterFor` in [scene_view.dart](../lib/scenes/scene_view.dart))

```
PhoneTheme has a layered scene?  → LayersPainter        (dashboard-made themes)
scene == halloween               → HalloweenPainter     (built-in)
scene == christmas               → ChristmasPainter
scene == thingyan                → ThingyanPainter
```

**Built-in painters** ([lib/scenes/](../lib/scenes/)) were ported from an SVG design using the same coordinates, so you'll see `Path()..moveTo(...)..cubicTo(...)`. Small animation helpers in [scene_math.dart](../lib/scenes/scene_math.dart) copy CSS: `phase(t, period)` (where we are in a loop), `pingPong`, `keyframes`, `lerp`.

**The layers engine** ([layers_painter.dart](../lib/render/layers_painter.dart)) draws a scene from JSON, back to front:
- `gradient`: fills the screen.
- `shape`: circle, ellipse, rect or polygon, with optional glow and `float` / `pulse` / `sway` motion.
- `image`: a downloaded picture (hills, a cabin), decoded once by [SceneAssets](../lib/render/scene_assets.dart).
- `particles`: snow, rain, drops, bats, lanterns, petals, sparkles, stars.

Colours can be **palette tokens** (`@background`, `@accent`, …), filled in by `ResolvedLook` from the theme's palette and the user's accent, so one scene follows every accent. Positions are fractions of the screen, so it fits any phone. Full reference: [theme-api.md](theme-api.md) section 4.9.

### 8.3 Making it move (`SceneView`)

```
SceneView
 ├── scenePainterFor(theme, time, accent)
 ├── _time = ValueNotifier<double>(1.2)    → the clock the painter listens to
 └── driver:
       • normal: a Ticker (every display frame)
       • maxFps set (live wallpaper = 30): a Timer instead, cheaper on battery
```

It animates only when asked (`animate: true`), stops when the phone asks for **reduced motion**, and with `maxFps` also stops while the app isn't visible.

Battery-saving rules across the app:
- **Store previews animate only while wallp's live wallpaper is on** (`LiveWallpaperStatus`): a still wallpaper doesn't move, so neither does its preview.
- Hidden tabs are wrapped in `TickerMode(enabled: false)`.
- Grid cards are never animated.

### 8.4 Turning a scene into a PNG ([wallpaper_renderer.dart](../lib/services/wallpaper_renderer.dart))

For a still (non-live) wallpaper:
1. Create the painter at `time = 1.2` (a nice still frame), with the scene's decoded images.
2. Draw it onto a `PictureRecorder` canvas at the **real screen pixel size**.
3. `picture.toImage(width, height)` → PNG bytes → Android sets it.

Only the scene is drawn, no clock or icons: the phone adds its own.

---

## 9. Step 6 — The store screens

Code: [lib/store/](../lib/store/).

```
StoreShell (5 tabs, icons only)
 ├── Store ──────► banner carousel → festival / theme / list pages
 │                 festival rows ──► FestivalScreen ──► ThemeDetailScreen
 │                 icon packs ─────► IconPacksScreen ──► IconPackDetailScreen
 ├── Themes ─────► ThemeDetailScreen ──► AccentPickerScreen
 ├── Wallpapers ─► WallpaperDetailScreen
 ├── Fonts ──────► FontDetailScreen
 └── Me ─────────► current look, favourites, history, downloads, wallp Home, settings
 (search icon) ──► SearchScreen
```

Pages are opened through [routes.dart](../lib/store/routes.dart) (`StoreRoutes.theme(context, id)` etc.). Each page wears its own festival's colours.

| Screen | What it shows |
|---|---|
| [Store home](../lib/store/screens/store_home_screen.dart) | Banner carousel (scheduled banners only), one row per festival (soonest first), icon packs |
| [Themes](../lib/store/screens/themes_screen.dart) | All themes; filters All / Festivals / Myanmar / Minimal / Favourites; Soonest or A–Z |
| [Festival](../lib/store/screens/festival_screen.dart) | One festival's themes: style chips, Popular / New / A–Z, a quick look |
| [Theme detail](../lib/store/screens/theme_detail_screen.dart) | Lock and home previews, accents (+ "Gradients & custom"), what it includes (wallpaper, icons, clock font), Apply with download size |
| [Accent picker](../lib/store/screens/accent_picker_screen.dart) | Solid, Gradient, Custom tabs; "My accents"; a readability check of the clock on the wallpaper |
| [Wallpapers](../lib/store/screens/wallpapers_screen.dart) + [detail](../lib/store/screens/wallpaper_detail_screen.dart) | Stand-alone wallpapers, Live or by festival; full-screen preview, "Set wallpaper" |
| [Fonts](../lib/store/screens/fonts_screen.dart) + [detail](../lib/store/screens/font_detail_screen.dart) | Clock fonts previewing the user's text; size, colour and where it shows, with a lock and home preview |
| [Icon packs](../lib/store/screens/icon_pack_screens.dart) | Packs by New or festival; detail with searchable icons, tile shape, app name colour and font |
| [Pin shortcuts](../lib/store/screens/pin_shortcuts_screen.dart) | For people who keep another launcher: add themed shortcuts to it |
| [Search](../lib/store/screens/search_screen.dart) | Recent and popular searches; results in All / Themes / Wallpapers / Fonts |
| [Me](../lib/store/screens/me_screen.dart) | Current look, favourites (with Undo), recently applied, downloads, wallp Home status, settings |

The rules behind lists (filters, sorts, badges, search) are pure Dart in [queries.dart](../lib/store/logic/queries.dart), so each is unit tested. Badges: a theme shows APPLIED, else NEW (published in the last 14 days), else LIVE; a wallpaper shows IN USE or LIVE.

[previews.dart](../lib/store/logic/previews.dart) builds card and page previews from the catalog summary alone (no download), and applies the user's own wallp Home choices (shape, name colour and font), so a theme looks the way it will on this phone.

**"Match app to my theme"** ([store_look_scope.dart](../lib/store/widgets/store_look_scope.dart), [store_palette.dart](../lib/core/store_palette.dart)): the store's colours and heading font come from the festival's `look` in the catalog. Read them with `context.palette`. Off in Me, or for undated collections, it uses the plain wallp look.

---

## 10. Step 7 — Pressing "Apply" (the most important flow)

Code: [apply_flow.dart](../lib/store/apply_flow.dart) (`ApplyFlow.applyTheme`), then `LookController`.

```
User taps [Apply] → sheet: Whole theme / Wallpaper only / Clock font only
      │
      ▼
① Whole theme only: is wallp the default home app?  (Android only)
      ├── yes ──────────────────────────────────────────────────────┐
      └── no → "Set wallp as your home app?" dialog (with a preview)│
               │ Cancel → stop                                      │
               │ OK:                                                │
               │   looks.applyTheme(asPending: true)  ← downloads   │
               │      everything, saves as PENDING                  │
               │   requestDefaultHome() → Android dialog            │
               │   back here: clearPending()                        │
               │   not default? → snackbar, stop                    │
               ▼                                                    │
      ◄─────────────────────────────────────────────────────────────┘
      ▼
② looks.applyTheme(option)
      │  downloads any missing files (progress card, Cancel)
      │  fails / cancelled → toast "Couldn't download…", OLD LOOK STAYS
      │  saves AppliedLook, pins its files
      ▼
③ Whole theme: user.recordApplied()   (Recently applied)
   Clock font only: toast, done
      ▼
④ "Set wallpaper on" sheet → Home / Lock / Both / Live   (iOS: always "both")
      ├── Live ──► already wallp's live wallpaper? → it redraws itself
      │            else openLiveWallpaper() → Android's preview → "Set wallpaper"
      └── Home/Lock/Both ──► render PNG at screen size → WallpaperManager
                              (iOS: saved to Photos)
      ▼
⑤ Toast: "Snowy Pines applied to wallp Home. Wallpaper set on home screen"
```

### Why the "pending apply" trick?

When the user picks wallp as the default home app, **Android immediately jumps to the new home screen** (wallp Home). The store may be paused or killed and never finish step ②.

Solution:

1. Before asking, the store downloads everything and saves the look as **pending** (`LookStore.savePending`), pinned as `pending`.
2. When **wallp Home** starts, it calls `takePending()`:
   - reads the pending look and deletes it,
   - ignores it if older than **10 minutes** (`pendingMaxAge`),
   - otherwise saves it as the applied look, records it in history, and shows "Snowy Pines applied".
3. If the store *does* come back, it calls `clearPending()` and finishes the apply itself.

When the store comes back to the front it reloads the look and user data (`StoreShell`'s lifecycle listener), in case wallp Home finished the apply meanwhile.

### The other applies

`ApplyFlow` also has `applyWallpaper`, `applyFont` (with size, colour and places) and `applyIconPack` (with shape, label colour and font). They all go through `LookController`, so they're all-or-nothing too. Failures become plain messages through `failureMessage()`: a download failure, a cancel, or "Check your connection".

---

## 11. Step 8 — Saved data (SharedPreferences and files)

| Class | Keys / files | Who reads it |
|---|---|---|
| `LookStore` ([look_store.dart](../lib/look/look_store.dart)) | `applied_look`, `pending_look` (JSON) | Store, wallp Home, live wallpaper |
| `UserStore` ([user_store.dart](../lib/store/state/user_store.dart)) | `fav_themes_v2`, `fav_wallpapers_v2`, `history_v2` (max 10), `theme_accents_v1` (accent per theme), `recent_searches`, the Me switches | Store (wallp Home writes history when finishing a pending apply) |
| `ThemePrefs` ([theme_prefs.dart](../lib/services/theme_prefs.dart)) | `lock_clock` (same key as the Me switch) | Live wallpaper |
| `MyAccents` ([my_accents.dart](../lib/look/my_accents.dart)) | The user's custom accents (6, newest first) | Store |
| `HomeStore` ([home_arrangement.dart](../lib/launcher/home_arrangement.dart)) | `home_arrangement` (JSON pages + dock) | wallp Home |
| `DevSettings` ([dev_settings.dart](../lib/dev/dev_settings.dart)) | Network preset, pretend date | Store (debug) |
| `CatalogStore` | Files: `manifest.json`, the catalog, `themes/<id>.<rev>.json` | Store |
| `AssetCache` | Files: `<sha256>.<ext>` + pin lists | All three engines |

Key points:

- They use **`SharedPreferencesAsync`** (not the older `SharedPreferences`). The async version has **no in-memory cache**, so when one engine writes, another engine reads the fresh value. With a cache, wallp Home would see old data.
- User data is saved **by catalog ID**. An ID that's no longer in the catalog is skipped on screen, never a crash.
- Broken JSON → start fresh instead of crashing.
- Nothing here leaves the phone.

The Me settings (`UserSetting`): **Themed lock screen clock**, **Match app to my theme**, and two that are saved but not built yet: **Festival reminders** and **Follow the next festival**.

---

## 12. Step 9 — Talking to Android (MethodChannels)

Dart cannot set a wallpaper or list installed apps by itself. It asks Kotlin through **MethodChannels**: a named pipe where Dart sends `invokeMethod('name', args)` and Kotlin replies.

All handlers are in [NativeBridge.kt](../android/app/src/main/kotlin/com/example/wallp/NativeBridge.kt). Both `MainActivity` and `LauncherActivity` create their own `NativeBridge`.

### Channel `wallp/wallpaper` — Dart: [wallpaper_service.dart](../lib/services/wallpaper_service.dart)

| Method | Kotlin does |
|---|---|
| `screenSize` | Returns real display `[width, height]` in pixels (portrait) |
| `setWallpaper {bytes, target}` | On a background thread: decode PNG → `WallpaperManager.setBitmap` with `FLAG_SYSTEM` (home), `FLAG_LOCK` (lock) or both |
| `openLiveWallpaper` | Opens Android's live wallpaper preview for `LiveWallpaperService`, and answers whether it was set, cancelled or unavailable. On realme / ColorOS the preview can close itself at once; a picker that closes within 1.5 s is opened once more |
| `isLiveWallpaperActive` | Is wallp's live wallpaper the current wallpaper? |

### Channel `wallp/icons` — Dart: [icon_pack_service.dart](../lib/services/icon_pack_service.dart)

| Method | Kotlin does |
|---|---|
| `listApps` | All launchable apps → `{package, label, icon PNG}`, sorted by label. Icons are **cached** in `cacheDir/app_icons/<pkg>-<lastUpdateTime>.png` |
| `getApp {package}` | One app (used when an app is installed/updated) |
| `canPinShortcuts` | Can the current launcher accept pinned shortcuts? |
| `pinShortcut {id, package, label, icon}` | Creates a home-screen shortcut with the themed icon that opens the real app |

### Channel `wallp/launcher` — Dart: [launcher_service.dart](../lib/services/launcher_service.dart)

| Direction | Method | Meaning |
|---|---|---|
| Dart → Kotlin | `launchApp`, `appInfo` | Open an app / its Settings page |
| Dart → Kotlin | `openThemes` | Open the store (MainActivity) from wallp Home |
| Dart → Kotlin | `goHome` | Go to wallp Home (Me's "Use wallp Home") |
| Dart → Kotlin | `isDefaultHome` | Uses `RoleManager.ROLE_HOME` (Android 10+) or resolves the HOME intent |
| Dart → Kotlin | `requestDefaultHome` | Shows the role dialog or Home settings; answers **after the user comes back** |
| Kotlin → Dart | `homePressed` | Home button pressed while already on wallp Home |
| Kotlin → Dart | `appsChanged {packages, removed}` | An app was installed/removed/updated |

### Channel `wallp/live_wallpaper` — between `LiveWallpaperService.kt` and `LiveWallpaperApp`

| Direction | Method | Meaning |
|---|---|---|
| Dart → Kotlin | `showLockClock` | Should the themed clock show right now? |
| Kotlin → Dart | `lockClock(bool)` | Lock state changed (screen on/off, unlock) |

Dart always catches `MissingPluginException` / `PlatformException` and returns a safe value (`false`/`null`). This keeps tests and iOS from crashing.

---

## 13. Step 10 — wallp Home (the launcher)

Files: [lib/launcher/](../lib/launcher/). Root widget: [launcher_home.dart](../lib/launcher/launcher_home.dart).

### 13.1 How it is shown over the real wallpaper

- `LauncherActivity.kt` uses `BackgroundMode.transparent`.
- `LauncherApp` sets `scaffoldBackgroundColor: Colors.transparent`.
- Result: the **system wallpaper** (which wallp set) shows behind the Flutter icons.

### 13.2 Layout

```
┌──────────────────────────────┐
│          10:42               │  clock (the look's clock font, if "home clock" is on)
│   Thu 15 Oct · 16 nights left│  countdown
│                              │
│   [icon][icon][icon][icon]   │  PageView of pages,
│   [icon][icon][icon][icon]   │  16 slots per page (HomeArrangement.pageSlots)
│   ...                        │
│            • ○ ○             │  page dots
│          ⌃ All apps          │
│  [phone][msgs][web][camera]  │  dock, 4 slots
└──────────────────────────────┘
```

### 13.3 Start-up / resume (`_reload()`)

1. `_applyPending()`: finish a pending apply (section 10). Never throws.
2. `LookStore.load()` → the applied look (or the default), then `ResolvedLook.of(look)` → `homeTheme`.
3. `FontRegistry.ensureAll(look.fonts)`: load the downloaded fonts into this engine; redraw when done. It draws at once in the fallback font, so a slow disk never holds back the home screen.
4. If the app list is older than 30 s: `installedApps()` from Kotlin.
5. Load the saved `HomeArrangement`; if none, build one with `HomeLayout.suggested(apps)`: phone, messages, browser and camera in the dock, then well-known apps, max 12 on the first page.
6. `retainInstalled()` removes uninstalled apps, then save.

It runs again **every time the home screen resumes**, so a newly applied look appears right away.

### 13.4 `HomeArrangement` ([home_arrangement.dart](../lib/launcher/home_arrangement.dart))

Stores only **package names**: `pages: [[pkg, pkg, …], …]` and `dock: [pkg, …]`. It is **immutable**: every change (`move`, `add`, `remove`, `addPage`, `withoutEmptyPages`) returns a **new** object, then `_update(next)` does `setState` + save. If a page gets more than 16 apps, the extras spill onto the next page.

### 13.5 Gestures

| Gesture | Result |
|---|---|
| Tap an icon | `launchApp(package)` |
| Swipe up / flick up | Open the app drawer ([app_drawer.dart](../lib/launcher/app_drawer.dart)) |
| Long-press empty space | Menu: **Edit home screen** / **Change theme** (opens the store) |
| Long-press an app | App menu (add/remove from home, App info) |
| Edit mode: drag icon | Move it between slots, pages, dock; hold at screen edge 600 ms → next page |
| Edit mode bar | Add apps ([add_apps_sheet.dart](../lib/launcher/add_apps_sheet.dart)), Add page, Done |
| Back button | Never leaves home; in edit mode it finishes editing |
| Home button (while home) | Close sheets/drawer, exit edit mode, or go to page 1 |

### 13.6 Icons and names on wallp Home

[launcher_icon.dart](../lib/launcher/launcher_icon.dart) picks, per app:
1. The icon pack has a **picture** for the app's glyph key → the picture, clipped to the user's tile shape.
2. A **painted** pack → `ThemedIcon` in the pack's style and shape (section 15).
3. Otherwise → the app's own icon, tinted.

App names use the look's label colour (Theme / Accent / White / Dark / custom) with a shadow so they read on any wallpaper, in the theme's label font or the phone's own (`PhoneTheme.appNameStyle`).

---

## 14. Step 11 — The live wallpaper

### 14.1 Kotlin side ([LiveWallpaperService.kt](../android/app/src/main/kotlin/com/example/wallp/LiveWallpaperService.kt))

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

- `sendSettings()` sends 24-hour format, font scale and dark mode. Normally a `FlutterView` does this, but a wallpaper has no `FlutterView`.
- `watchLock()` listens for `SCREEN_ON`, `SCREEN_OFF`, `USER_PRESENT` and tells Dart if the lock screen is showing.
- `showLockClock()`: always true in preview; on Android 14+ uses `wallpaperFlags` (lock-only vs home-only engine); otherwise asks `KeyguardManager`.

### 14.2 Dart side ([live_wallpaper_app.dart](../lib/live_wallpaper/live_wallpaper_app.dart))

1. `_load()` reads the look from `LookStore` (**saved data only**, never the network), loads its fonts, and reads the `lock_clock` setting.
2. On every **resume** (wallpaper visible again) it reloads → if the user applied another look in the store, the wallpaper switches by itself.
3. Draws the `wallpaperTheme`'s `SceneView(animate: true, maxFps: 30)` full screen, with its downloaded images.
4. If `lock_clock` is on **and** the phone is locked, draws the themed clock and countdown (`lockTheme`), and redraws it every minute.

Why draw a clock? Apps cannot restyle Android's own lock screen clock, so wallp draws its themed clock inside the wallpaper.

---

## 15. Step 12 — Themed app icons and fonts

### 15.1 Which glyph for which app ([app_glyphs.dart](../lib/icons/app_glyphs.dart))

A list of rules matches an app to a **glyph key** (`phone`, `messages`, `camera`, `browser`, … 20 in all) by package name fragment or exact label:

- `whatsapp`, `telegram`, `viber` → `messages`
- `dialer` or label "phone" → `phone`
- `chrome`, `firefox`, `browser` → `browser`
- …first match wins, so specific rules come first.

No match, or the pack has no picture for that key → the app's own icon, tinted. The same keys name the pictures in a downloaded icon pack.

### 15.2 Two kinds of icon pack

| Kind | Drawn by |
|---|---|
| `painted` (built-in packs) | [ThemedIconPainter](../lib/icons/themed_icon_painter.dart) in the Halloween / Christmas / Thingyan style: glowing tile, decorations (cobweb, snow, padauk flowers), accent ring, and the glyph in the accent only if contrast is at least 3:1 |
| `images` (dashboard packs) | One downloaded picture per glyph key ([image_icons.dart](../lib/render/image_icons.dart)), decoded once by `SceneAssets` |

Both follow the user's **tile shape** (squircle, circle, square, leaf; [icon_shape.dart](../lib/render/icon_shape.dart)). Pictures are clipped to it.

**Two ways icons reach the phone:**

| Way | When | How |
|---|---|---|
| **wallp Home** (main way) | wallp is the default home app | wallp Home draws every icon itself |
| **Pinned shortcuts** ([pin_shortcuts_screen.dart](../lib/store/screens/pin_shortcuts_screen.dart)) | Another launcher that supports pinning | Render a PNG of the icon → `pinShortcut` → the launcher asks "Add to home screen?". The shortcut opens the real app |

### 15.3 Fonts ([font_registry.dart](../lib/render/font_registry.dart))

Catalog fonts are downloaded `.ttf` / `.otf` files. `FontRegistry` loads them into the engine with Flutter's `FontLoader` under the name `wallp-<id>`, and tells listeners when one is ready so previews redraw. **Each engine loads its own fonts** (the store, wallp Home and the live wallpaper each call `ensureAll`).

- Burmese text falls back to **Padauk** for fonts without Myanmar letters.
- `google_fonts` is still the fallback for a font that isn't downloaded yet (e.g. a font page opened before applying). Removing it, and bundling only the UI font and Padauk, is still to do.

---

## 16. Android vs iOS

| Feature | Android | iOS |
|---|---|---|
| Set wallpaper | Directly via `WallpaperManager` | Not allowed by Apple → image saved to **Photos**; user sets it in Settings |
| Home/Lock/Live choice | Yes | No (always "both") |
| Live wallpaper | Yes | No |
| wallp Home / themed icons | Yes | No |

The checks are `WallpaperService.canSetDirectly` and `LauncherService.isSupported` (both = "is Android"). iOS is not a target today ([theme-api.md](theme-api.md) section 11).

---

## 17. Developer settings

Debug builds only: **Me › Developer settings** ([dev_settings_screen.dart](../lib/dev/dev_settings_screen.dart)).

- **Network:** fast, slow, offline or flaky, for the mock source. Lets you see the progress card, retries and offline behaviour without a real server.
- **Pretend date:** moves "now" for countdowns, NEW badges and banners (through the `Clock` provider).
- **Catalog status:** where the catalog came from (built-in, saved, refreshed), its version, skipped items, themes hidden because they need a newer app.
- **Downloads:** what's cached and pinned.

---

## 18. Tests

Folder [test/](../test/). Run with:

```bash
flutter test
```

361 tests, all passing. By folder:

| Folder / file | Checks |
|---|---|
| [test/catalog/](../test/catalog/) | Parsing every object, the mock and built-in catalogs (every hash, size and reference), countdowns, the repository (offline first launch, unknown schema and engines, refresh) |
| [test/assets/](../test/assets/) | The file cache (hashes, atomic writes, LRU, pins) and the download manager (progress, retries, cancel) |
| [test/look/](../test/look/) | `AppliedLook`, `LookStore` (migration, pending), `LookController`, `ResolvedLook`, accents, apply with downloads (failures keep the old look) |
| [test/render/](../test/render/) | The layers painter, image icons and fonts |
| [test/store/](../test/store/) | Store screens, queries (filters, sorts, badges, search), previews, Me, icon shapes, label colours, live status |
| `launcher_test.dart`, `home_arrangement_test.dart` | wallp Home and the arrangement logic |
| `live_wallpaper_test.dart` | Live wallpaper widget from the snapshot alone |
| `scene_test.dart`, `wallpaper_renderer_test.dart`, `themed_icon_test.dart`, `icon_pack_test.dart`, `dev_settings_test.dart` | Painters, PNG rendering, icons, Developer settings |

The tests read the **full 30-theme catalog** in [test/fixtures/catalog/v1/](../test/fixtures/catalog/v1/), not the small demo the app shows.

Many classes accept fake dependencies in their constructors (e.g. `CatalogRepository(source: …, store: …, clock: …)`, `LookController(prepare: …, pin: …)`, `LiveWallpaperApp(clock: …)`). This is **dependency injection**, so tests can pass fakes instead of the network, the disk or Android.

---

## 19. How to add a new theme

### 19.1 A theme on the `layers` engine (the normal way)

No new Dart code. Later the dashboard does this; today:

1. Add the theme (and if needed its festival, wallpaper, icon pack, fonts) to [tool/seed/seed_data.dart](../tool/seed/seed_data.dart). Look at an existing `_layersTheme(...)` for the shape.
2. To show it in the app (not only the tests), add its ID to `demoThemes` in [tool/seed/generate.dart](../tool/seed/generate.dart).
3. Bump `demoRevision` in `seed_data.dart` (and the theme's `rev` if you changed an existing one). Installed apps only fetch a new catalog version and a new `rev` ([theme-api.md](theme-api.md) section 4.11).
4. Run `dart run tool/seed/generate.dart`. If you changed art in [art.dart](../tool/seed/art.dart), run `flutter test tool/seed/render_art_test.dart` first.
5. Run `flutter test`: it checks every hash, reference and summary.

### 19.2 A new built-in painter (needs an app update)

Only when the `layers` engine can't draw what you need. Example: Kpop.

1. **Painter:** create `lib/scenes/kpop_scene.dart` with `class KpopPainter extends ScenePainter`, implementing `paintScene(canvas, t)` in 390×844 coordinates.
2. **Engine ID:** add `kpop` to `EngineIds` and `EngineIds.builtIn` in [scene.dart](../lib/catalog/models/scene.dart) (the repository's `supportedEngines` picks it up), and to `SceneKind` in [phone_theme.dart](../lib/models/phone_theme.dart).
3. **Register:** add `SceneKind.kpop => KpopPainter(...)` in `scenePainterFor()` in [scene_view.dart](../lib/scenes/scene_view.dart).
4. **Icons:** add a painted style for `kpop` to `ThemedIconPainter`, or give the theme an `images` icon pack.
5. **Catalog:** add the engine to `engines` and the theme to `_builtInThemes()` in `seed_data.dart`, then regenerate (19.1 steps 3–5). The built-in catalog in the APK gets it too.

Dart's `switch` on an enum must cover every value, so the compiler will point you to any place you forgot.

---

## 20. Glossary

| Word | Meaning |
|---|---|
| **Flutter engine** | One running copy of Flutter + Dart. wallp can run up to 3 at once. |
| **Entry point** | The Dart function an engine starts with (`main`, `launcherMain`, `wallpaperMain`). |
| **Activity** | An Android screen (`MainActivity`, `LauncherActivity`). |
| **Service** | Android background component; `LiveWallpaperService` draws the wallpaper. |
| **MethodChannel** | Named message pipe between Dart and Kotlin. |
| **Catalog** | The list of festivals, themes, wallpapers, fonts, icon packs and banners, in the Theme API format. |
| **Built-in catalog** | The catalog shipped inside the APK, for first launch with no internet. |
| **Mock source** | Reads the bundled mock catalog through a pretend network, until the real CDN exists. |
| **Asset** | A downloaded file (image, font), named by its sha256. |
| **Pin** | A mark that stops the cache deleting a file the phone still needs. |
| **Applied look** | The saved snapshot of everything on the phone (`AppliedLook`). |
| **Pending look** | A look saved for wallp Home to finish, while Android switches the home app. |
| **Engine (scene)** | What draws a scene: a built-in painter or `layers`. |
| **Glyph key** | A string naming an app type (`phone`, `camera`); links apps to icon pictures. |
| **CustomPainter** | Flutter class that draws on a `Canvas` with code. |
| **Ticker** | Calls a function every display frame; drives animation. |
| **ChangeNotifier / Provider** | Shared state that screens can watch. |
| **SharedPreferences** | Small key-value storage on the phone. |
| **Default home app** | The launcher Android shows when you press Home (ROLE_HOME). |
| **Accent** | The highlight colour: one of the theme's, a preset, or custom; solid or gradient. |

---

## 21. Suggested reading order

Read the code in this order to learn fastest:

1. [main.dart](../lib/main.dart) and [app.dart](../lib/app.dart): start-up and the shared objects
2. [theme.dart](../lib/catalog/models/theme.dart), [festival.dart](../lib/catalog/models/festival.dart), [catalog.dart](../lib/catalog/models/catalog.dart): the data, with [theme-api.md](theme-api.md) section 4 open
3. [catalog_repository.dart](../lib/data/catalog/catalog_repository.dart): where the catalog comes from
4. [applied_look.dart](../lib/look/applied_look.dart), [look_controller.dart](../lib/look/look_controller.dart), [resolved_look.dart](../lib/look/resolved_look.dart): what's on the phone and how it changes
5. [apply_flow.dart](../lib/store/apply_flow.dart): the Apply flow end to end
6. [scene_painter.dart](../lib/scenes/scene_painter.dart), [scene_view.dart](../lib/scenes/scene_view.dart), [halloween_scene.dart](../lib/scenes/halloween_scene.dart), [layers_painter.dart](../lib/render/layers_painter.dart): drawing and animation
7. [store_shell.dart](../lib/store/store_shell.dart) → [theme_detail_screen.dart](../lib/store/screens/theme_detail_screen.dart): the UI
8. [asset_cache.dart](../lib/data/assets/asset_cache.dart), [download_manager.dart](../lib/data/assets/download_manager.dart): downloads
9. [wallpaper_service.dart](../lib/services/wallpaper_service.dart) + [NativeBridge.kt](../android/app/src/main/kotlin/com/example/wallp/NativeBridge.kt): Dart ↔ Android
10. [launcher_home.dart](../lib/launcher/launcher_home.dart) + [home_arrangement.dart](../lib/launcher/home_arrangement.dart): wallp Home
11. [LiveWallpaperService.kt](../android/app/src/main/kotlin/com/example/wallp/LiveWallpaperService.kt) + [live_wallpaper_app.dart](../lib/live_wallpaper/live_wallpaper_app.dart): live wallpaper
12. [themed_icon_painter.dart](../lib/icons/themed_icon_painter.dart), [app_glyphs.dart](../lib/icons/app_glyphs.dart), [font_registry.dart](../lib/render/font_registry.dart): icons and fonts

Then read [store-redesign-plan.md](store-redesign-plan.md) for what's built and what's next, and [theme-dashboard.md](theme-dashboard.md) for how themes will be made.
