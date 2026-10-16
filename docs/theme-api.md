# wallp Theme API

How wallp gets its themes, wallpapers and fonts from a server instead of shipping them inside the app, and what has to change in the app to support it.

Companion document: [theme-dashboard.md](theme-dashboard.md), the web tool the team uses to create and publish themes into this API.

---

## 1. Why, and what it will (and won't) save

### 1.1 Goals

1. **Add or update themes without an app update.** A new Christmas theme goes live from the dashboard, and every phone sees it on the next app launch.
2. **Keep the app small as the catalog grows.** Theme images, animations and fonts are downloaded only when a user opens or applies that theme.
3. **One source of truth.** The dashboard, the API and the app all use the same theme format (section 4).

### 1.2 Where the app size actually goes today

Measured from `build/app/outputs/flutter-apk/app-release.apk` (15 Oct 2026):

| Part | Size | Notes |
|---|---|---|
| Native code for 3 CPU types (`libapp.so` + `libflutter.so` for arm64, arm32, x86_64) | ~77 MB | 98% of the APK |
| Flutter assets (fonts, shaders, icons) | 0.4 MB | |
| The 3 built-in themes | < 1 MB | Painted by Dart code, no image files |
| **Total APK** | **78 MB** | |

**Conclusion:** moving today's three themes to an API saves almost nothing, because they are code, not files. The size wins come from:

| Action | Expected result | Effort |
|---|---|---|
| Publish an **App Bundle** (`flutter build appbundle`) instead of a universal APK. Google Play sends each phone only its own CPU's code. | ~78 MB → ~26 MB installed, about 10–12 MB to download | Small |
| For direct APK sharing, build per CPU: `flutter build apk --split-per-abi` | One ~26 MB APK per CPU type | Small |
| Shrink the Dart code (`libapp.so`, ~14 MB per CPU): `--obfuscate --split-debug-info=build/symbols`, remove unused packages, check with `flutter build apk --analyze-size --target-platform android-arm64` | A few MB | Medium |
| Replace the `google_fonts` package with the API's font delivery (section 7.4). The package carries a large list of every Google font; check the size report to confirm how much. | Possibly several MB | Medium (part of this project) |
| **Theme API (this document)** | Stops future growth: images, Lottie animations and fonts for new themes never enter the APK | Large (this project) |

Do the App Bundle step first; it is a one-line change and gives the biggest win.

---

## 2. Big picture

```
 ┌─────────────┐   publish    ┌──────────────────────┐   HTTPS + CDN   ┌──────────────┐
 │  Dashboard  │ ───────────▶ │  Catalog files + CDN │ ──────────────▶ │  wallp app   │
 │ (team only) │              │  (read-only, public) │                 │ (every phone)│
 └──────┬──────┘              └──────────────────────┘                 └──────┬───────┘
        │ admin API (auth)                                                    │ optional
        ▼                                                                     ▼
 ┌─────────────┐                                                       ┌──────────────┐
 │  Database   │◀──────────────── popularity numbers ◀──────────────── │ Events API   │
 └─────────────┘                                                       └──────────────┘
```

**Recommended approach: a "static catalog".** The dashboard stores drafts in a database. When someone presses **Publish**, it writes plain JSON files and asset files to object storage behind a CDN. The app only reads those files.

Why this approach:
- **Cheap and fast:** no server code runs when millions of phones read the catalog; the CDN serves files.
- **Reliable:** if the dashboard or database is down, the app still works.
- **Simple app code:** the app downloads JSON and files; no complex queries.

Search, filtering and sorting happen **on the phone** over the downloaded catalog. With hundreds of themes the catalog is still only tens of KB.

A small dynamic **Events API** (section 6) is optional and only collects "applied" and "favourited" counts for popularity sorting.

**Suggested hosting** (any of these work):

| Piece | Option A (simple) | Option B (all-in-one) |
|---|---|---|
| Files + CDN | Cloudflare R2 + Cloudflare CDN | Firebase Hosting / Storage |
| Database + login for the dashboard | Supabase (Postgres + Auth) | Firebase Firestore + Auth |
| Events API | Cloudflare Worker | Firebase Cloud Function |

---

## 3. Public endpoints (read by the app)

Base URL: `https://cdn.<your-domain>/catalog/v1/`

All responses are JSON (UTF-8), served with `ETag` and `Cache-Control`. The app sends `If-None-Match` and gets `304 Not Modified` when nothing changed.

| Endpoint | What it returns | Cache |
|---|---|---|
| `GET /manifest.json` | Catalog version, file list with hashes, minimum app version | `max-age=300` (5 min) |
| `GET /catalog.<version>.json` | All festivals, theme summaries, wallpapers, fonts, banners | `max-age=31536000, immutable` |
| `GET /themes/<themeId>.<rev>.json` | One theme's full definition | immutable |
| `GET /assets/<sha256>.<ext>` | Images, Lottie files, font files | immutable |

Every file except `manifest.json` has its version or hash in the name, so it never changes and can be cached forever. Publishing writes new files and then updates `manifest.json` last.

### 3.1 `manifest.json`

```json
{
  "schemaVersion": 1,
  "catalogVersion": "2026-10-15.3",
  "catalog": "catalog.2026-10-15.3.json",
  "catalogSha256": "9f2c…",
  "minAppVersion": "1.0.0",
  "publishedAt": "2026-10-15T14:00:00Z"
}
```

- **`schemaVersion`:** the JSON format version (section 9). The app ignores catalogs whose `schemaVersion` it doesn't know and keeps its cached catalog instead.
- **`minAppVersion`:** if the app is older, show a soft "Update wallp to get new themes" banner, but keep working with the cached catalog.

### 3.2 `catalog.<version>.json`

```json
{
  "catalogVersion": "2026-10-15.3",
  "festivals": [ /* Festival, section 4.1 */ ],
  "themes":    [ /* ThemeSummary, section 4.3 */ ],
  "wallpapers":[ /* Wallpaper, section 4.5 */ ],
  "fonts":     [ /* Font, section 4.6 */ ],
  "banners":   [ /* Banner, section 4.7 */ ]
}
```

The summary is everything the store home, Themes list, festival pages and search need. The app downloads a theme's **full** file only when the user opens its detail page.

---

## 4. Data format

Format rules:
- **Colours:** strings `"#RRGGBB"`; an optional opacity goes in a separate `opacity` field (0–1). This maps to Flutter's `Color(0xFFRRGGBB)`.
- **IDs:** lowercase `kebab-case`, never reused, e.g. `halloween-night`.
- **Text people read:** a localized object, `{ "en": "Water Festival", "my": "သင်္ကြန်" }`. The app picks the phone's language, falling back to `en`.
- **Dates:** `YYYY-MM-DD`. Times are ISO 8601 UTC.

### 4.1 Festival

A festival is a collection, matching `ThemeCategory` in [theme_category.dart](../lib/models/theme_category.dart).

```json
{
  "id": "thingyan",
  "name": { "en": "Thingyan", "my": "သင်္ကြန်" },
  "comingSoon": false,
  "sort": 30,
  "occurrences": ["2027-04-13", "2028-04-13", "2029-04-14"],
  "fallbackDate": { "month": 4, "day": 13 },
  "unit": "day",
  "look": {
    "background": "#062848", "surface": "#0C375F", "outline": "#1E5A8C",
    "muted": "#B6D0E8", "brand": "#FFC21A", "displayFont": "baloo-2"
  },
  "coverThemeId": "thingyan-water"
}
```

- **`occurrences`:** real festival dates per year. Thingyan and Thadingyut follow the Myanmar calendar, so a fixed month and day is wrong some years. The countdown uses the first occurrence on or after today, and falls back to `fallbackDate` when the list runs out.
- **`unit`:** the countdown word, `"day"` or `"night"`.
- **`look`:** the app colours used while browsing this festival (the "Match app to my theme" feature).

### 4.2 Theme (full), matching `PhoneTheme`

```json
{
  "id": "halloween-night",
  "rev": 4,
  "festivalId": "halloween",
  "name": { "en": "Halloween" },
  "subtitle": null,
  "style": "classic",
  "tags": ["spooky", "moon", "bats"],
  "isLive": true,
  "publishedAt": "2026-09-20T00:00:00Z",
  "minAppVersion": "1.0.0",

  "scene": {
    "engine": "halloween",
    "params": {}
  },

  "palette": {
    "background": "#160C24",
    "deep": "#0D0717",
    "surface": "#2A1840",
    "text": "#F4E9C9",
    "textMuted": "#CDBFA0"
  },

  "accents": [
    { "id": "pumpkin", "name": { "en": "Pumpkin" }, "type": "solid", "colors": ["#FF8A2A"] },
    { "id": "slime",   "name": { "en": "Slime" },   "type": "solid", "colors": ["#9BE15D"] },
    { "id": "witch",   "name": { "en": "Witch" },   "type": "solid", "colors": ["#B57BFF"] },
    { "id": "glow",    "name": { "en": "Pumpkin glow" }, "type": "gradient", "colors": ["#FFB547", "#FF4D2E"], "angle": 135 }
  ],

  "variants": [
    { "id": "night", "name": { "en": "Night" }, "palette": null },
    { "id": "blood-moon", "name": { "en": "Blood moon" },
      "palette": { "background": "#1A0A10", "deep": "#0D0508", "surface": "#3A1420" } }
  ],

  "fonts": { "display": "creepster", "body": "space-grotesk", "labels": "space-grotesk" },

  "clock": { "useAccent": true },
  "eventIcon": "nightlight_round",

  "iconPack": { "style": "halloween" },

  "wallpaperIds": ["harvest-moon"],
  "previewImage": "assets/4b1e….webp"
}
```

| Field | Meaning in the app |
|---|---|
| `rev` | Increases on every publish of this theme. The app re-downloads when it changes. |
| `style` | Festival page filter: `classic`, `cozy`, `minimal`, `cute`. |
| `isLive` | Has animation, which shows the LIVE badge. |
| `scene.engine` | Which built-in scene painter draws the wallpaper (section 5). |
| `palette` | Same five colours as `ThemePalette`. `accentOptions` moves to `accents`. |
| `accents` | Solid or gradient accent choices. The first one is the default. |
| `variants` | Colour variants of the same theme. A variant only lists the palette fields it changes. |
| `fonts` | Font IDs from the font list (section 4.6). `labels` is the font for app names on wallp Home. |
| `clock.useAccent` | Same as `accentClock`: draw the lock clock in the accent colour. |
| `eventIcon` | A name from the app's built-in icon list (section 7.3). |
| `iconPack.style` | Which themed icon style `ThemedIconPainter` uses. |
| `previewImage` | Optional small WebP thumbnail. Lets old app versions show a theme they cannot draw. |

### 4.3 ThemeSummary (inside the catalog)

```json
{
  "id": "halloween-night", "rev": 4, "festivalId": "halloween",
  "name": { "en": "Halloween" }, "style": "classic", "tags": ["spooky", "moon"],
  "isLive": true, "isNew": false, "popularity": 1,
  "engine": "halloween",
  "background": "#160C24", "accent": "#FF8A2A",
  "displayFont": "creepster",
  "variantSwatches": ["#160C24", "#1A0A10"],
  "previewImage": "assets/4b1e….webp",
  "minAppVersion": "1.0.0"
}
```

That's enough to draw cards, badges, variant dots, countdowns and search results without downloading the full theme.

### 4.4 Scene parameters

`scene.params` is an object whose keys depend on the engine. It starts empty for today's three painters. In the future, each engine can expose tweaks, for example:

```json
{ "engine": "christmas", "params": { "snowAmount": 0.6, "treeCount": 3, "showStar": true } }
```

The dashboard reads the allowed params for each engine from the engines list (section 5).

### 4.5 Wallpaper

```json
{
  "id": "harvest-moon",
  "festivalId": "halloween",
  "name": { "en": "Harvest Moon" },
  "kind": "scene",
  "scene": { "engine": "halloween", "params": {} },
  "image": null,
  "isLive": true,
  "tags": ["moon", "bats"]
}
```

`kind` is one of:
- **`scene`:** drawn by a scene engine. 0 MB to download, can be a live wallpaper.
- **`image`:** a still picture:

```json
"image": {
  "sizes": [
    { "width": 1080, "height": 2340, "url": "assets/a1c3….webp", "bytes": 412330 },
    { "width": 1440, "height": 3120, "url": "assets/77de….webp", "bytes": 690112 }
  ],
  "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
  "dominant": "#160C24"
}
```

The app picks the smallest size that is at least the screen's width. `blurhash` shows a blurred placeholder while the image downloads.

### 4.6 Font

```json
{
  "id": "creepster",
  "family": "Creepster",
  "kind": "display",
  "scripts": ["latin"],
  "license": "OFL-1.1",
  "files": [
    { "weight": 400, "style": "normal", "url": "assets/c0ffee….woff2", "format": "woff2", "bytes": 38200, "sha256": "c0ffee…" }
  ],
  "fallbackFor": { "my": "padauk" }
}
```

- **Font files:** use `ttf` or `otf` for the app (Flutter's `FontLoader` reads those), and `woff2` for the dashboard's web preview.
- **`fallbackFor`:** which font draws text in scripts this font doesn't support. Creepster has no Myanmar letters, so Burmese app names use Padauk.
- **`license`:** must be a licence that allows redistribution (Google Fonts are OFL or Apache).

### 4.7 Banner (store home carousel)

```json
{
  "id": "xmas-2026",
  "title": { "en": "Snowy Christmas" },
  "subtitle": { "en": "6 new themes, 2 of them live." },
  "tag": { "en": "NEW · 6 THEMES" },
  "cta": { "en": "Explore" },
  "action": { "type": "festival", "id": "christmas" },
  "look": { "background": "#0F3D2E", "accent": "#F2B33D", "font": "playfair-display", "engine": "christmas" },
  "startsAt": "2026-11-15T00:00:00Z",
  "endsAt": "2026-12-26T00:00:00Z",
  "sort": 10
}
```

`action.type` is one of `festival`, `theme`, `wallpapers`, `fonts` or `url`. The app hides banners outside their `startsAt`/`endsAt` window, so they can be scheduled ahead.

---

## 5. Scene engines: the important limit

Today each wallpaper scene is **Dart code** (`HalloweenPainter`, `ChristmasPainter`, `ThingyanPainter` in [lib/scenes/](../lib/scenes/)). **An app can't download new Dart code.** So a theme from the API can only use painters that the installed app already contains.

That leaves three ways to make new themes:

| Level | How a new theme gets its scene | Download size | Needs an app update? |
|---|---|---|---|
| **1. Reuse an engine** | Pick an existing engine (`halloween`, `christmas`, `thingyan`) and give it new colours, accents, fonts and params | 0 MB | No |
| **2. Generic layered engine** (recommended next step) | Add one new engine to the app, `layers`, that draws a scene from a JSON list of layers: a background image or gradient, shapes, and particle effects (snow, rain, bats, lanterns, petals) | 0.2–1 MB of images | Once, to add the engine |
| **3. Animation files** | A `lottie` or `rive` engine that plays a downloaded animation file | 0.1–2 MB | Once, to add the engine |

Example of a level 2 scene:

```json
{
  "engine": "layers",
  "params": {
    "layers": [
      { "type": "gradient", "colors": ["#0B1A2E", "#173A5C"], "angle": 180 },
      { "type": "image", "url": "assets/9a7….webp", "fit": "cover", "anchor": "bottom" },
      { "type": "particles", "effect": "snow", "count": 80, "speed": 0.4, "color": "#FFFFFF" },
      { "type": "shape", "shape": "circle", "x": 0.7, "y": 0.2, "size": 0.18, "color": "#F2B33D", "glow": true }
    ]
  }
}
```

**The engines list.** Both the app and the dashboard keep the same list of engines and their params:

```json
{
  "engines": [
    { "id": "halloween", "sinceApp": "1.0.0", "params": [] },
    { "id": "christmas", "sinceApp": "1.0.0", "params": [] },
    { "id": "thingyan",  "sinceApp": "1.0.0", "params": [] },
    { "id": "layers",    "sinceApp": "1.2.0", "params": ["layers"] }
  ]
}
```

- **Dashboard:** uses the list to set each theme's `minAppVersion` automatically.
- **App:** hides themes whose engine it doesn't know. If the theme has a `previewImage`, the app can show it as "Update wallp to use this theme" instead of hiding it.

---

## 6. Events API (optional, for popularity)

`POST https://api.<your-domain>/v1/events`

```json
{
  "installId": "random-uuid-created-on-first-launch",
  "appVersion": "1.1.0",
  "events": [
    { "type": "theme_applied", "themeId": "halloween-night", "at": "2026-10-15T13:02:11Z" },
    { "type": "theme_favourited", "themeId": "xmas-pines", "at": "2026-10-15T13:05:40Z" }
  ]
}
```

- Response: `202 Accepted`, empty body.
- **Batching:** the app sends events in batches (on app start or every few hours), never one request per tap.
- **Privacy:** no personal data. `installId` is a random ID, not linked to the user or device. Mention this in the privacy policy.
- **Popularity:** a nightly job adds up the counts and writes `popularity` into the next catalog publish.
- **Limits:** rate-limit per `installId` and per IP; drop unknown event types.

The app must work fully if this API is missing or failing.

---

## 7. Changes in the wallp app

### 7.1 New classes

| New | Replaces / wraps | Job |
|---|---|---|
| `ThemeRepository` | Static `ThemeCatalog` | Gives the app festivals, themes, wallpapers and fonts. Uses the built-in catalog plus the cached remote catalog. |
| `CatalogClient` | | Downloads `manifest.json` and the catalog with ETag; downloads a full theme on demand |
| `AssetCache` | | Stores downloaded images, Lottie files and fonts on disk by sha256; checks hashes; LRU limit |
| `FontRegistry` | `GoogleFonts.getFont` | Loads downloaded font files with `FontLoader` and returns a `TextStyle` by font ID |
| `PhoneTheme.fromJson` / `ThemeCategory.fromJson` | `const` constructors | Parse API JSON into the existing models |
| `SceneRegistry` | `switch (theme.scene)` in [scene_view.dart](../lib/scenes/scene_view.dart) | Maps an engine ID to a painter. Unknown engine means "not supported". |

`PhoneTheme.scene` changes from the `SceneKind` enum to an engine ID string, plus `params`.

### 7.2 Startup and offline behaviour

1. **First launch:** use the **built-in catalog** (today's three themes, kept in the app), so the app works with no internet.
2. **Every launch:** read the cached catalog from disk (instant), then fetch `manifest.json` in the background. If the catalog version changed, download the new catalog, check its sha256, save it, and refresh the UI.
3. **Opening a theme:** download the theme file and its assets if they aren't cached yet. Show the summary (colours, preview image) while it loads.
4. **Applying a theme:** first make sure **every** asset for that theme is on disk (scene images, fonts). Only then save it as applied. If the download fails, show "Couldn't download this theme. Check your connection." and keep the old theme.
5. **The applied theme is pinned:** the cache never deletes its files. wallp Home and the live wallpaper run as separate engines, sometimes with no network (for example after a reboot), so they must be able to load the applied theme from disk alone.
6. **Cache limit:** about 50 MB for everything except pinned files; the least recently used files are deleted first.

### 7.3 Saving the applied theme

Today `ThemePrefs` saves only the theme ID. Change it to also save a **snapshot** of the applied theme's full JSON (a few KB). Then:
- wallp Home and the live wallpaper read the snapshot and never need the network.
- If a theme is later removed from the catalog, the phone keeps working with the snapshot.

`eventIcon` becomes a string. The app keeps an **allowlist** mapping names to `IconData`, e.g. `nightlight_round → Icons.nightlight_round`. Unknown names fall back to `Icons.event`. (Flutter can't create an icon from an arbitrary string at runtime and still remove unused icons from the build.)

### 7.4 Fonts without `google_fonts`

- **Bundled fonts:** keep only the app's own UI font (Sora) and one Myanmar font (Padauk or Noto Sans Myanmar) inside the APK, a few hundred KB.
- **Theme fonts:** download through `AssetCache` and register with `FontLoader('font-<id>')`.
- **While a font downloads:** show the body font, then swap to the theme font when it's ready; never block the UI.
- **Pinned:** fonts of the applied theme are pinned like other assets.
- **Then remove the `google_fonts` package** and measure the size again (section 1.2).

### 7.5 Request headers

Every request sends:
- `User-Agent: wallp/<version> (Android <sdk>)`
- `X-Wallp-Engines: halloween,christmas,thingyan` (the engines this build has), so a dynamic API could filter later. The static catalog doesn't need it; the app filters by itself.

### 7.6 Tests to add

- Parsing: each JSON example in this document parses into the right model. Keep the examples as test fixtures.
- Offline first launch shows the built-in themes.
- A catalog with an unknown `schemaVersion` is ignored.
- A theme with an unknown engine is hidden, or shown as "needs update" when it has a preview image.
- Applying a theme with a failed asset download keeps the old theme.
- wallp Home and the live wallpaper start from the snapshot with the network turned off.
- Countdown uses `occurrences` and falls back to `fallbackDate`.

---

## 8. Security

- **Public catalog:** HTTPS only and read-only. No secrets in the app.
- **Integrity:** every asset is named and checked by sha256. The app throws away files whose hash doesn't match, so a bad CDN file can't break the app.
- **Optional catalog signature:** to protect against a hacked storage bucket, sign `manifest.json` with an Ed25519 key. Ship the public key in the app and verify before trusting a new catalog.
- **Admin API:** behind login, used only by the dashboard (see the dashboard doc). The storage bucket is writable only by the publish job.
- **Size limits:** the app refuses single files over 10 MB and catalogs over 2 MB, to protect phones from mistakes.

---

## 9. Versioning rules

| Change | What to do |
|---|---|
| Add an optional field | Same `schemaVersion`; old apps ignore it |
| Add a new engine | Same `schemaVersion`; set the theme's `minAppVersion` to the version that added the engine |
| Rename or remove a field, or change its meaning | New `schemaVersion` (2), publish both v1 and v2 catalogs side by side (`/catalog/v1/`, `/catalog/v2/`) until old app versions are rare |
| Remove a theme | Remove it from the catalog. Phones that applied it keep their snapshot. |

---

## 10. Build plan

| Phase | Work | Done when |
|---|---|---|
| **0. Size quick win** | Ship an App Bundle; add `--obfuscate --split-debug-info` | Play Console shows the download size; the 78 MB APK is no longer used |
| **1. Catalog format** | Write the JSON Schema for every object in section 4; move today's three themes into `catalog.json`; add fixtures and parsing tests | The app runs from a local `catalog.json` with no behaviour change |
| **2. Repository + cache** | `ThemeRepository`, `CatalogClient`, `AssetCache`, snapshot in `ThemePrefs` | The app loads the catalog from a test CDN; works offline after the first load |
| **3. Fonts** | `FontRegistry`; remove `google_fonts`; bundle Sora + Myanmar font | All theme fonts come from the catalog; APK size re-measured |
| **4. Dashboard v1** | Festivals, themes with existing engines, fonts, banners, Publish | A new theme published from the dashboard appears in the app without an update |
| **5. Layers engine** | `layers` engine in the app plus the scene editor in the dashboard | A new Christmas scene made only in the dashboard |
| **6. Popularity** | Events API + nightly job | The "Popular" sort uses real data |

---

## 11. Open questions for the team

1. Which hosting option (section 2)?
2. Which languages besides English and Myanmar?
3. Should some themes be paid later? If so, add an `access` field now (`free` / `premium`) so old apps don't show premium themes for free.
4. Is an iOS version planned? iOS can't be a home-screen app, so only wallpapers and previews would apply there.
