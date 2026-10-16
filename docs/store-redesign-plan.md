# wallp store redesign: plan

How the new store design ("wallp Store Flow" canvas, 12 screens) gets built on mock data that already has the exact shape of the Theme API, so binding the real API later only swaps the data source.

Related: [theme-api.md](theme-api.md) (the JSON format), [theme-dashboard.md](theme-dashboard.md) (where themes are made).

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
  │           └─► CatalogStore (app support dir: manifest, catalog, theme files)
  │
  ├─► ThemeDownloader ──► same CatalogSource ──► AssetCache        (phase 5)
  │
  └─► UserStore (local only)                                       (phase 3)
        AppliedLook, favourites, history, accents, settings, recent searches

wallp Home engine ─┐
Live wallpaper   ──┴─► read AppliedLook snapshot + pinned files from disk. Never the network.
```

The mock is only the **source**: caching, checks and fallbacks are the real code, tested now. The mock writes to the real disk, so offline behaviour, pinning and "downloaded" state are real too. Only the place the bytes come from is fake.

---

## 3. Two kinds of theme

| | Built-in | Downloadable (dashboard-made) |
|---|---|---|
| Examples | Halloween, Christmas, Thingyan (today's painters) | Thadingyut, Minimal, Cozy Cabin, Gold Ornaments, … |
| Scene | Dart painter (`halloween`, `christmas`, `thingyan`) | `layers` engine: gradient, image, shape and particle layers from JSON ([theme-api.md §5](theme-api.md), level 2) |
| Icons | `ThemedIconPainter` | Icon pack images, one per glyph key, plus tile style for apps without a glyph |
| Font | Bundled / `google_fonts` today | Font file (`.ttf`), loaded with `FontLoader` |
| Download | 0 MB, apply instantly | ~0.5–3 MB, progress sheet first |

**Apply flow for a downloadable theme**

1. Tap **Apply** → pick Whole theme / Wallpaper only / Clock font only.
2. If any needed file isn't cached: the download sheet shows `Downloading Cozy Cabin · 1.2 of 2.4 MB` with **Cancel**.
3. Every file is checked by sha256 and written to a temp file, then renamed. One bad file fails the whole download.
4. Only when **all** files are on disk: save the theme snapshot, pin its files, apply the wallpaper, live wallpaper, icons and font, then show the toast.
5. Failed or cancelled: show "Couldn't download this theme. Check your connection." and keep the old theme. Files already downloaded stay cached, so a retry continues where it stopped.
6. Afterwards the theme works with no internet, including after a reboot.

---

## 4. Data to add to the API format

Things the design needs that [theme-api.md](theme-api.md) doesn't define yet. Phase 1 adds these to that doc.

| Object / field | Why |
|---|---|
| `IconPack` { id, festivalId, name, style, isNew, shape, tile, ring, glyphs: { phone: asset, chat: asset, … }, bytes } | Icon pack screens; downloadable icons |
| Theme `download` { bytes, assets[] } | The progress total and the "2.4 MB" label before download |
| Theme `iconPackId` | Whole-theme apply also applies its icon pack |
| Font `category`: display / handwritten / clean / myanmar | Fonts filter chips |
| Wallpaper `isNew`, `popularity` | Badges, sort |
| Catalog `searchSuggestions` | "Popular searches" on Search |
| Glyph key list (`phone`, `chat`, `camera`, `browser`, `photos`, `maps`, `mail`, `calendar`, …) | Shared by `app_glyphs.dart`, icon packs and the dashboard |

---

## 5. Seed (mock) data

From the canvas, so every screen has real-looking content:

| Kind | Count | Notes |
|---|---|---|
| Festivals | 5 + 2 coming soon | Halloween, Christmas, Thingyan, Thadingyut, Minimal (no date). Real `occurrences` for the Myanmar-calendar festivals |
| Themes | ~30 | Halloween 8, Christmas 10, Thingyan 6, Thadingyut 3, Minimal 3. 3 built-in, the rest downloadable. Styles, variants, accents, popularity, `publishedAt` |
| Wallpapers | 8+ | Scene and layers kinds, some live |
| Fonts | 9 | Creepster, Playfair Display, Baloo 2, Bebas Neue, Mountains of Christmas, Caveat, Pacifico, Space Grotesk, Padauk |
| Icon packs | ~6 | One or more per festival |
| Banners | 4 | Scheduled windows, actions: festival / theme / wallpapers / fonts |
| Accent presets | 10 solid, 6 gradient | From the accent picker |

`publishedAt` is stored relative to the seed date, and every date check uses an injected clock, so "NEW" badges and countdowns stay testable.

---

## 6. Phases

| # | Work | Done when |
|---|---|---|
| 1 ✅ | **Format.** Add §4 to `theme-api.md`; write the seed JSON; models with `fromJson`; parsing tests use the seed files | Every seed file parses. Models: [lib/catalog/](../lib/catalog/); seed: [tool/seed/](../tool/seed/) → [assets/mock/catalog/v1/](../assets/mock/catalog/v1/); tests: [test/catalog/](../test/catalog/) |
| 2 ✅ | **Repository.** `CatalogRepository` + mock source; a built-in catalog (same format) as the offline first-launch fallback; dev switches for slow / offline / failing network and a pretend date | Screens can read the catalog. Code: [lib/data/catalog/](../lib/data/catalog/), [lib/dev/](../lib/dev/); Developer screen under Settings in debug builds |
| 3 ✅ | **AppliedLook.** Replaces "theme id + accent": theme, festival, variant, accent, wallpaper (follow theme / another theme / stand-alone), clock {font, size, colour, places} and icon pack {pack, shape}, saved as a full snapshot. Old saves move over; the pending apply uses it; wallp Home and the live wallpaper read it | Partial applies reach both other engines. Code: [lib/look/](../lib/look/). Until Phase 6, `ResolvedLook` turns a look into today's `PhoneTheme`; dashboard themes draw a placeholder scene and image icon packs show apps' own icons |
| 4 ✅ | **Accents on screen.** Gradient clock (`ShaderMask`) and countdown badges on the lock screen and wallp Home; CSS angles → Flutter gradients; readability check (3:1 for the clock on the wallpaper sky, worst stop wins); dark/light label on accent fills; "My accents" (6, newest first, no duplicates); the picker's choice list | Gradient accents draw as gradients. Code: [lib/look/accent_*.dart](../lib/look/), [my_accents.dart](../lib/look/my_accents.dart). Scene painters still take one colour: gradients on the wallpaper itself come with the layers engine (Phase 6) |
| 5 ✅ | **Download + cache.** `AssetCache` (sha256-named, checked on arrival, written atomically, pins `applied` / `pending` / `incoming`, LRU 50 MB); `DownloadManager` (progress, 3 at a time, retries brief failures, cancel, shared tasks); apply is all-or-nothing; launch-time repair; Me › Downloads list with Delete; download status in Developer settings | Apply → progress → applied, then works offline. Code: [lib/data/assets/](../lib/data/assets/). Not yet: resuming *inside* a file (HTTP Range; finished files are kept, a half file restarts), a free-space check before starting (a full disk shows as a failed download) |
| 6 ✅ | **Layers engine + image icons + font loading.** `LayersPainter` (gradient, shape with glow and float / pulse / sway, image, 8 particle effects; palette tokens and gradient accents); downloaded pictures decoded once (`SceneAssets`); wallp Home and pinned shortcuts draw icon-pack pictures, clipped to the user's tile shape; `FontRegistry` loads downloaded fonts in all three engines, Padauk as Burmese fallback | Dashboard themes draw for real on lock, home and live wallpaper. Code: [lib/render/](../lib/render/). Still to do: bundle Sora + Padauk and drop `google_fonts` (it's the fallback for fonts not downloaded); on a cold start the clock can show the fallback font for a moment before the downloaded one loads |
| 7 ✅ | **Screens.** 5-tab shell (Store, Themes, Wallpapers, Fonts, Me); Store home (banner carousel, festival rows, icon packs); Themes (5 filters, Soonest / A–Z, festival cards); festival page (style chips, Popular / New / A–Z, quick look with variants); theme detail (Lock / Home preview, variants, accents, includes, Apply sheet with 3 options and download size); accent picker (solid, gradient, custom, My accents, readability); wallpapers + preview; fonts + detail (size, colour, places); icon packs + detail (shapes, search, add to another home screen); search (recent, popular, result tabs); Me (current look, favourites with undo, history, downloads, settings). Download progress card above every screen | The demo flow works end to end. Code: [lib/store/](../lib/store/). Old Explore / My Themes / Settings screens removed |
| 8 ✅ | **Match app to my theme.** The store wears the applied theme's festival look (colours, display font for headings); festival, theme, accent picker, wallpaper and icon pack pages wear their own festival's; undated collections and the switch off in Me keep the plain look; colours fade over 300 ms | Every festival look passes contrast checks (text, muted, brand, button labels). Code: [store_palette.dart](../lib/core/store_palette.dart), [store_look_scope.dart](../lib/store/widgets/store_look_scope.dart) |
| 9 | **Tests** (section 8) | Tests pass |

Phases 3–6 hold most of the risk, so they come before the screens.

---

## 7. Risks

### High

1. **Partial apply changes the core model (phase 3).** Today `ThemePrefs` saves one theme ID and one accent, and three engines read it. Every apply path, including the pending apply when switching the home app, changes. If this goes wrong, wallp Home or the live wallpaper shows the wrong theme or a blank screen.
2. **Downloads must be all-or-nothing (phase 5).** Risks: the app is killed mid-download, half-written files, a hash mismatch, a full disk, or the user leaves the screen. Mitigation: temp file + rename, check the hash before marking a file done, apply only after every file is there, check free space before starting.
3. **Offline after a reboot.** The live wallpaper service can start before the app ever runs. It must find the snapshot and the pinned files at fixed paths, and load fonts itself. The cache must never delete pinned files.
4. **The layers engine's look and battery use.** Dashboard themes only look as good as this engine draws them. Particles on a live wallpaper cost battery, so keep the existing 30 fps cap and the particle limits. Lottie / Rive is a later step.
5. **Icons become images.** `app_glyphs.dart` returns `IconData`. It needs stable string keys so a downloaded pack can map apps to images. Icon images at 432 px can be 1–3 MB per pack, so use WebP.

### Medium

6. **Gradient accents (phase 4):** they touch the clock, icon painter, scenes and saved data.
7. **Myanmar-calendar dates:** `ThemeEvent` uses a fixed month and day. Seed data needs `occurrences`, and the countdown logic needs a fallback when the list runs out.
8. **Fonts:** `google_fonts` downloads at runtime and doesn't work offline on first use. Downloaded `.ttf` files fix this for theme fonts. Bundle Sora and Padauk.
9. **Mock files in the release APK:** bundled mock images and fonts increase the app size. Keep them small and plan a `mock` flavor, or remove them once the API exists.
10. **Navigation rewrite:** the app goes from 3 tabs to 5 plus about 9 pushed screens, and most of the 12 existing test files need rewriting.

### Stubbed in this phase

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

The app shows a small **demo catalog**: three themes (Halloween, Christmas, Thingyan) and three wallpapers, for testing step by step. The full 30-theme catalog lives in `test/fixtures/` for the tests. See [theme-api.md §4.11](theme-api.md).

## 10. Packages to add

- `path_provider`: the cache folder
- `crypto`: sha256
- `http`: only when binding the real API
