# wallp store redesign: plan

How the new store design ("wallp Store Flow" canvas, 12 screens) gets built on mock data that already has the exact shape of the Theme API, so binding the real API later only swaps the data source.

**Status (18 Oct 2026): all 9 phases done.** The new store runs end to end on the mock catalog (five themes, the latest being Neon Night); 357 tests pass. What's left before the real API is in section 11.

Related: [theme-api.md](theme-api.md) (the JSON format), [theme-dashboard.md](theme-dashboard.md) (where themes are made), [how-the-app-works.md](how-the-app-works.md) (a walk through the code as built).

---

## 1. Decisions

| Question | Decision |
|---|---|
| Where mock data lives | JSON files under `assets/mock/`, in the exact `theme-api.md` format |
| Old Explore / My Themes / Settings screens | Replaced by the new 5-tab store (Store, Themes, Wallpapers, Fonts, Me) |
| Themes the app has no painter for | Made in the dashboard as **downloadable themes**: tap Apply → download with progress → applied automatically (wallpaper, icons, font) → works offline afterwards |

---

## 2. Architecture

```
Screens
  │
  ├─► CatalogRepository ── one implementation, mock or real
  │     saved → built-in fallback, manifest check, sha256, size limits,
  │     hides unknown engines / too-new themes, theme files on demand
  │           │
  │           ├─► CatalogSource ─┬─ MockCatalogSource  (now: bundled files through a pretend network)
  │           │                  └─ HttpCatalogSource  (later: the CDN; the only new code)
  │           ├─► CatalogStore (app support dir: manifest, catalog, theme files)
  │           └─► BuiltInCatalog (in the APK: first launch with no internet)
  │
  ├─► LookController ──► LookStore ("applied_look", "pending_look")
  │     │  every apply, all or nothing
  │     └─► DownloadManager ──► same CatalogSource ──► AssetCache (pins)
  │
  └─► UserStore (local only)
        favourites, history, accent per theme, settings, recent searches

wallp Home engine ─┐
Live wallpaper   ──┴─► read AppliedLook snapshot + pinned files from disk. Never the network.
```

As planned, except that downloads became the `DownloadManager` driven by `LookController` (no separate `ThemeDownloader`), and the applied look lives in its own `LookStore`, not in `UserStore`.

The mock is only the **source**: caching, checks and fallbacks are the real code, tested now. The mock writes to the real disk, so offline behaviour, pinning and "downloaded" state are real too. Only the place the bytes come from is fake.

---

## 3. Two kinds of theme

| | Built-in | Downloadable (dashboard-made) |
|---|---|---|
| Examples | Halloween, Christmas, Thingyan (today's painters) | Spider Night, Neon Night (made by script today; the dashboard later) |
| Scene | Dart painter (`halloween`, `christmas`, `thingyan`) | `layers` engine: gradient, image, shape and particle layers from JSON ([theme-api.md §5](theme-api.md), level 2) |
| Icons | `ThemedIconPainter` | One background tile per pack; every app's own logo sits on it (the per-app pictures were dropped) |
| Font | Bundled / `google_fonts` today | Font file (`.ttf`), loaded with `FontLoader` |
| Download | 0 MB, apply instantly | ~0.5–3 MB, progress sheet first |

**Apply flow for a downloadable theme**

1. Tap **Apply** → pick Whole theme / Wallpaper only / Clock font only.
2. If any needed file isn't cached: the download card (above every screen) shows `Downloading Cozy Cabin · 1.2 of 2.4 MB` with **Cancel**.
3. Every file is checked by sha256 and written to a temp file, then renamed. One bad file fails the whole download.
4. Only when **all** files are on disk: save the theme snapshot, pin its files, apply the wallpaper, live wallpaper, icons and font, then show the toast.
5. Failed or cancelled: show "Couldn't download this theme. Check your connection." and keep the old theme. Files already downloaded stay cached, so a retry continues where it stopped.
6. Afterwards the theme works with no internet, including after a reboot.

---

## 4. Data added to the API format

Things the design needed that [theme-api.md](theme-api.md) didn't define. All are in that doc now; where the built format differs from the plan, the right column says how.

| Planned | Built as |
|---|---|
| `IconPack` { id, festivalId, name, style, isNew, shape, tile, ring, glyphs, bytes } | `IconPack` (§4.7) with `kind` (`painted` / `images`), `painter`, `glyph` colour, `background` tile (image packs) and `publishedAt`; no per-app `glyphs`. NEW comes from `publishedAt`, size from the background file, so `isNew` and `bytes` aren't stored |
| Theme `download` { bytes, assets[] } | Theme `downloadBytes` (§4.3). The file list isn't stored: the app works it out from the scene, icon pack and fonts (`Catalog.assetsFor`) |
| Theme `iconPackId` | As planned |
| Font `category` | As planned, plus `sampleText` and `listed` |
| Wallpaper `isNew`, `popularity` | `popularity` and `publishedAt`. Wallpapers show IN USE or LIVE, no NEW badge |
| Catalog `searchSuggestions` | As planned, plus `accentPresets` (the picker's Solid and Gradient tabs) |
| Glyph keys (`phone`, `chat`, `camera`, …) | Built as 20 keys, then dropped: packs are now one `background` tile under each app's own logo (§4.7). Material symbols remain only for painted packs and the store's sample apps |
| | Also added: theme `fonts.labels` and `labels.color` (app names on wallp Home), festival `look` ("Match app to my theme"), `durationDays`, `comingSoon` |

---

## 5. Seed (mock) data

From the canvas, so every screen has real-looking content. Built by [tool/seed/](../tool/seed/). This 30-theme catalog was later removed: the app and the tests now share the five-theme demo catalog (Halloween, Christmas, Thingyan, Spider Night, Neon Night; see [theme-api.md §4.11](theme-api.md)). What it held:

| Kind | Count | Notes |
|---|---|---|
| Festivals | 5 + 2 coming soon | Halloween, Christmas, Thingyan, Thadingyut, Minimal (no date); Kpop and Mid-Autumn coming soon. `occurrences` for the Myanmar-calendar festivals (placeholder dates, not checked against the calendar) |
| Themes | 30 | Halloween 8, Christmas 10, Thingyan 6, Thadingyut 3, Minimal 3. 3 built-in, 27 on the `layers` engine. 12 have colour variants |
| Wallpapers | 12 | All scenes (none are image wallpapers yet), 7 live |
| Fonts | 10 | Creepster, Playfair Display, Baloo 2, Bebas Neue, Mountains of Christmas, Caveat, Pacifico, Space Grotesk, DM Sans, Padauk |
| Icon packs | 9 | 3 painted (built-in), 6 with downloaded pictures |
| Banners | 5 | Actions: festival / theme / wallpapers / fonts; 1 scheduled for later |
| Accent presets | 10 solid, 6 gradient | From the accent picker |

`publishedAt` is stored relative to the seed date, and every date check uses an injected clock, so "NEW" badges and countdowns stay testable.

---

## 6. Phases

| # | Work | Done when |
|---|---|---|
| 1 ✅ | **Format.** Add §4 to `theme-api.md`; write the seed JSON; models with `fromJson`; parsing tests use the seed files | Every seed file parses. Models: [lib/catalog/](../lib/catalog/); seed: [tool/seed/](../tool/seed/) → [assets/mock/catalog/v1/](../assets/mock/catalog/v1/); tests: [test/catalog/](../test/catalog/) |
| 2 ✅ | **Repository.** `CatalogRepository` + mock source; a built-in catalog (same format) as the offline first-launch fallback; dev switches for slow / offline / failing network and a pretend date | Screens can read the catalog. Code: [lib/data/catalog/](../lib/data/catalog/), [lib/dev/](../lib/dev/); Developer screen under Settings in debug builds |
| 3 ✅ | **AppliedLook.** Replaces "theme id + accent": theme, festival, variant, accent, wallpaper (follow theme / another theme / stand-alone), clock {font, size, colour, places} and icon pack {pack, shape}, saved as a full snapshot. Old saves move over; the pending apply uses it; wallp Home and the live wallpaper read it | Partial applies reach both other engines. Code: [lib/look/](../lib/look/). `ResolvedLook` turns a look into a `PhoneTheme` per screen (lock, home, wallpaper), the model the painters and overlays draw; it stayed after Phase 6 as the bridge |
| 4 ✅ | **Accents on screen.** Gradient clock (`ShaderMask`) and countdown badges on the lock screen and wallp Home; CSS angles → Flutter gradients; readability check (3:1 for the clock on the wallpaper sky, worst stop wins); dark/light label on accent fills; "My accents" (6, newest first, no duplicates); the picker's choice list | Gradient accents draw as gradients. Code: [lib/look/accent_*.dart](../lib/look/), [my_accents.dart](../lib/look/my_accents.dart). Scene painters still take one colour: gradients on the wallpaper itself come with the layers engine (Phase 6) |
| 5 ✅ | **Download + cache.** `AssetCache` (sha256-named, checked on arrival, written atomically, pins `applied` / `pending` / `incoming`, LRU 50 MB); `DownloadManager` (progress, 3 at a time, retries brief failures, cancel, shared tasks); apply is all-or-nothing; launch-time repair; Me › Downloads list with Delete; download status in Developer settings | Apply → progress → applied, then works offline. Code: [lib/data/assets/](../lib/data/assets/). Not yet: resuming *inside* a file (HTTP Range; finished files are kept, a half file restarts), a free-space check before starting (a full disk shows as a failed download) |
| 6 ✅ | **Layers engine + image icons + font loading.** `LayersPainter` (gradient, shape with glow and float / pulse / sway, image, 8 particle effects; palette tokens and gradient accents); downloaded pictures decoded once (`SceneAssets`); wallp Home and pinned shortcuts draw icon-pack pictures, clipped to the user's tile shape; `FontRegistry` loads downloaded fonts in all three engines, Padauk as Burmese fallback | Dashboard themes draw for real on lock, home and live wallpaper. Code: [lib/render/](../lib/render/). Still to do: bundle Sora + Padauk and drop `google_fonts` (it's the fallback for fonts not downloaded); on a cold start the clock can show the fallback font for a moment before the downloaded one loads |
| 7 ✅ | **Screens.** 5-tab shell (Store, Themes, Wallpapers, Fonts, Me); Store home (banner carousel, festival rows, icon packs); Themes (5 filters, Soonest / A–Z, festival cards); festival page (style chips, Popular / New / A–Z, quick look); theme detail (Lock / Home preview, accents, includes, Apply sheet with 3 options and download size; the Colours (variants) row was removed later for a simpler page, the format keeps variants); accent picker (solid, gradient, custom, My accents, readability); wallpapers + preview; fonts + detail (size, colour, places); icon packs + detail (shapes, search, add to another home screen); search (recent, popular, result tabs); Me (current look, favourites with undo, history, downloads, settings). Download progress card above every screen | The demo flow works end to end. Code: [lib/store/](../lib/store/). Old Explore / My Themes / Settings screens removed |
| 8 ✅ | **Match app to my theme.** The store wears the applied theme's festival look (colours, display font for headings); festival, theme, accent picker, wallpaper and icon pack pages wear their own festival's; undated collections and the switch off in Me keep the plain look; colours fade over 300 ms | Every festival look passes contrast checks (text, muted, brand, button labels). Code: [store_palette.dart](../lib/core/store_palette.dart), [store_look_scope.dart](../lib/store/widgets/store_look_scope.dart) |
| 9 ✅ | **Tests** (section 8) | All tests pass (`flutter test`). Code: [test/](../test/), reading the mock catalog in [assets/mock/](../assets/mock/) |

Phases 3–6 hold most of the risk, so they come before the screens.

---

## 7. Risks

The risks as written before the work, each followed by where it ended up (**Now:**).

### High

1. **Partial apply changes the core model (phase 3).** Today `ThemePrefs` saves one theme ID and one accent, and three engines read it. Every apply path, including the pending apply when switching the home app, changes. If this goes wrong, wallp Home or the live wallpaper shows the wrong theme or a blank screen.
   **Now:** done. One `AppliedLook` snapshot, old saves migrated, tested in all three engines.
2. **Downloads must be all-or-nothing (phase 5).** Risks: the app is killed mid-download, half-written files, a hash mismatch, a full disk, or the user leaves the screen. Mitigation: temp file + rename, check the hash before marking a file done, apply only after every file is there, check free space before starting.
   **Now:** done, except the free-space check: a full disk shows as a failed download.
3. **Offline after a reboot.** The live wallpaper service can start before the app ever runs. It must find the snapshot and the pinned files at fixed paths, and load fonts itself. The cache must never delete pinned files.
   **Now:** done. Each engine loads its own fonts. On a cold start the clock can show the fallback font for a moment.
4. **The layers engine's look and battery use.** Dashboard themes only look as good as this engine draws them. Particles on a live wallpaper cost battery, so keep the existing 30 fps cap and the particle limits. Lottie / Rive is a later step.
   **Now:** engine built, 30 fps cap and limits (150 particles per layer) kept. Battery use on real phones not measured yet.
5. **Icons become images.** `app_glyphs.dart` returns `IconData`. It needs stable string keys so a downloaded pack can map apps to images. Icon images at 432 px can be 1–3 MB per pack, so use WebP.
   **Now:** done, more simply than planned: a pack is one background tile (a few dozen KB), clipped to the user's tile shape, with each app's own logo (its adaptive icon's foreground) on top. No per-app pictures, so no glyph keys.

### Medium

6. **Gradient accents (phase 4):** they touch the clock, icon painter, scenes and saved data.
   **Now:** done. Where a gradient can't be drawn (app names, icon rings), its first colour is used.
7. **Myanmar-calendar dates:** `ThemeEvent` uses a fixed month and day. Seed data needs `occurrences`, and the countdown logic needs a fallback when the list runs out.
   **Now:** done in `Festival.nextRun`. The seed dates are placeholders, to be checked against the calendar before launch.
8. **Fonts:** `google_fonts` downloads at runtime and doesn't work offline on first use. Downloaded `.ttf` files fix this for theme fonts. Bundle Sora and Padauk.
   **Now:** theme fonts fixed. `google_fonts` still the fallback; bundling Sora and Padauk is still to do.
9. **Mock files in the release APK:** bundled mock images and fonts increase the app size. Keep them small and plan a `mock` flavor, or remove them once the API exists.
   **Now:** the demo catalog is 5 themes (2.7 MB). Removing it with the real API is still to do.
10. **Navigation rewrite:** the app goes from 3 tabs to 5 plus about 9 pushed screens, and most of the 12 existing test files need rewriting.
    **Now:** done; old screens and their tests replaced.

### Stubbed (still)

| Feature | Why it's stubbed |
|---|---|
| Festival reminders | Notification permission (Android 13+) and scheduled alarms |
| Follow the next festival | Needs background work (WorkManager) to switch on the day |
| "Use on one app only" icon swap | Per-app override model in the launcher |
| Popularity from real users | Events API ([theme-api.md §6](theme-api.md)); seed numbers until then |

The switches show in Me and save their value. They don't do anything yet.

---

## 8. Tests

- Every seed file parses; an unknown `schemaVersion` is ignored; a theme with an unknown engine is hidden.
- Countdown: `occurrences`, `fallbackDate`, "Today", night/day wording; past festivals sort last.
- Badges: APPLIED beats NEW beats LIVE; NEW = published within 14 days.
- Filters, sorts (popular / new / A–Z / soonest) and search across themes, wallpapers and fonts.
- Download: progress adds up; cancel keeps the old theme; a hash mismatch fails the download; a retry reuses finished files; nothing is applied until every file is present.
- Offline: a downloaded theme applies and renders with the asset source turned off.
- wallp Home and the live wallpaper start from the snapshot alone.
- Old saved data (theme id + ARGB accent) loads as an `AppliedLook`.
- Removing a favourite and undoing it puts it back at the same position.

---

## 9. Mock data in the app

The app shows a small **demo catalog**: five themes (Haunted Moon, Snowy Pines, Water Splash, Spider Night, Neon Night) and their wallpapers, with their icon packs, fonts and banners, for testing step by step. The tests read the same catalog. Spider Night and Neon Night are script-made kits (one file each in [tool/seed/](../tool/seed/), built with `tool/seed/spider_night.sh`); Neon Night covers colour variants, a gradient accent and a downloaded font on the `layers` engine. Every change to the demo needs a new `demoRevision` and theme `rev`, or installed apps keep the old data. See [theme-api.md §4.11](theme-api.md).

## 10. Packages

- `path_provider`: the cache folder. Added.
- `crypto`: sha256. Added.
- `http`: only when binding the real API. Not added yet.

## 11. What's next

| Work | Notes |
|---|---|
| **HTTP catalog source** | The one new class for the real CDN ([theme-api.md](theme-api.md) §7.1), with the request headers in §7.8. Then remove the mock catalog from the APK |
| **Drop `google_fonts`** | Bundle Sora and Padauk; every other font comes from the catalog |
| **"Update wallp" for users** | The app knows when the server asks for a newer app and how many themes it hid, but only Developer settings shows it. A soft banner, and `previewImage` cards for themes that need a newer app |
| **Download edge cases** | Resume inside a file (HTTP Range); check free space before starting |
| **Stubbed features** | Festival reminders, Follow the next festival, one-app icon swap (section 7) |
| **Myanmar dates** | Check the Thingyan `occurrences` against the calendar (and Thadingyut's, when it comes back to the catalog) |
| **Dashboard** | [theme-dashboard.md](theme-dashboard.md), not started |
