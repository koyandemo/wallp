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
  "catalogVersion": "2026-10-15.1",
  "festivals":  [ /* Festival, section 4.2 */ ],
  "themes":     [ /* ThemeSummary, section 4.4 */ ],
  "wallpapers": [ /* Wallpaper, section 4.5 */ ],
  "fonts":      [ /* Font, section 4.6 */ ],
  "iconPacks":  [ /* IconPack, section 4.7 */ ],
  "banners":    [ /* Banner, section 4.8 */ ],
  "accentPresets": { "solids": [ /* Accent */ ], "gradients": [ /* Accent */ ] },
  "searchSuggestions": ["Halloween", "moon", "snow", "Thingyan", "handwritten", "minimal", "live"]
}
```

The summary is everything the store home, Themes list, festival pages, icon pack screens and search need. The app downloads a theme's **full** file only when the user opens its detail page.

- **`accentPresets`:** the Solid and Gradient tabs of the accent picker, offered on every theme after the theme's own accents.
- **`searchSuggestions`:** "Popular searches" on the Search screen.

---

## 4. Data format

The Dart models for every object below are in [lib/catalog/](../lib/catalog/). They are pure Dart, so the app, the tests and the seed generator share one parser. A working example of every object is in the mock catalog (section 4.11).

Format rules:
- **Colours:** strings `"#RRGGBB"`. This maps to Flutter's `Color(0xFFRRGGBB)`.
- **IDs:** lowercase `kebab-case`, never reused, e.g. `halloween-night`. Each list (themes, wallpapers, fonts…) has its own IDs, so a theme and a wallpaper may both be `pumpkin-patch`.
- **Text people read:** a localized object, `{ "en": "Water Festival", "my": "သင်္ကြန်" }`. `en` is required. The app picks the phone's language, falling back to `en`.
- **Dates:** `YYYY-MM-DD`; impossible dates like `2027-02-31` are rejected, not rolled over. **Times:** ISO 8601 UTC with `Z`.
- **Derived fields** such as `isLive` are written for people reading the JSON, but the app computes them itself and ignores the written value.
- **Unknown fields are ignored**, so adding an optional field never breaks old apps (section 9).

### 4.1 Asset

Every downloadable file (images, icon pictures, fonts) is an Asset object:

```json
{ "url": "assets/9a359a28….png", "sha256": "9a359a28…", "bytes": 15577, "format": "png" }
```

- **`url`** is relative to the catalog base URL and must be exactly `assets/<sha256>.<format>`. A file can't be swapped without its name changing, so every asset is cached forever.
- **`format`**: `png`, `webp`, `jpg`, `ttf`, `otf`, `woff2` or `json`.
- **`bytes`** at most 10 MB (section 8). The app checks size and hash after downloading and throws the file away if either is wrong.

### 4.2 Festival

A festival with dates (Halloween, Thingyan) or an undated collection (Minimal).

```json
{
  "id": "thingyan",
  "name": { "en": "Thingyan", "my": "သင်္ကြန်" },
  "kind": "festival",
  "tags": ["myanmar"],
  "sort": 30,
  "occurrences": ["2027-04-13", "2028-04-13", "2029-04-13"],
  "fallbackDate": { "month": 4, "day": 13 },
  "durationDays": 4,
  "unit": "day",
  "look": {
    "background": "#062848", "surface": "#0C375F", "surface2": "#124570",
    "outline": "#1E5A8C", "nav": "#083054", "muted": "#B6D0E8",
    "brand": "#FFC21A", "displayFont": "baloo-2"
  },
  "coverThemeId": "thingyan-water"
}
```

| Field | Meaning |
|---|---|
| `kind` | `festival` (has a countdown) or `collection` (no date, shows "Any time") |
| `tags` | Filter tags. `myanmar` puts it under the Themes "Myanmar" chip |
| `comingSoon` | Optional, `true` = a tab with a "coming soon" message and no themes |
| `sort` | Order where there's no date to sort by |
| `occurrences` | Real first-day dates, in order. Required for Myanmar-calendar festivals, whose Gregorian date moves |
| `fallbackDate` | Used for fixed-date festivals, and once `occurrences` runs out. 29 February is not allowed |
| `durationDays` | How long it lasts (default 1). Every day of it shows "Happy Thingyan!" |
| `unit` | Countdown word: `day` or `night` |
| `look` | The app's colours while browsing this festival ("Match app to my theme"). `muted` must be at least 4.5:1 on `background` |
| `coverThemeId` | Optional theme used as the festival's picture |

**Countdown rule.** The next run is the first occurrence whose *last* day is on or after today. When the list runs out, `fallbackDate` is used, but never in a year the list already covered. A dated festival needs at least one of `occurrences` and `fallbackDate`.

### 4.3 Theme (full): `themes/<id>.<rev>.json`

```json
{
  "id": "cozy-cabin",
  "rev": 1,
  "festivalId": "christmas",
  "name": { "en": "Cozy Cabin" },
  "style": "cozy",
  "tags": ["cabin", "warm", "snow"],
  "publishedAt": "2026-10-10T14:00:00Z",
  "popularity": 2,
  "minAppVersion": "1.0.0",
  "scene": { "engine": "layers", "params": { "layers": [ /* section 4.9 */ ] } },
  "palette": {
    "background": "#3A2318", "deep": "#F1E9DE", "surface": "#4A352A",
    "text": "#F5F1EA", "textMuted": "#BDB3AB", "motif": "#7A4A2E"
  },
  "accents": [
    { "id": "amber", "name": { "en": "Amber" }, "type": "solid", "colors": ["#FFB547"] },
    { "id": "frost", "name": { "en": "Frost" }, "type": "gradient", "colors": ["#F5F1EA", "#7CC6FF"], "angle": 180 }
  ],
  "variants": [
    { "id": "warm", "name": { "en": "Warm" }, "accentId": "amber" },
    { "id": "snowed-in", "name": { "en": "Snowed in" },
      "palette": { "background": "#2A3440", "deep": "#E9EFEC", "surface": "#3C4652", "motif": "#5A6B7E" },
      "accentId": "snow" }
  ],
  "fonts": { "display": "caveat", "body": "dm-sans", "labels": "dm-sans" },
  "clock": { "useAccent": false },
  "eventIcon": "card_giftcard_rounded",
  "iconPackId": "candy-cane",
  "wallpaperIds": ["snowy-cabin"],
  "downloadBytes": 786432
}
```

| Field | Meaning in the app |
|---|---|
| `rev` | Increases on every publish of this theme. The app re-downloads when it changes |
| `style` | Festival page filter: `classic`, `cozy`, `minimal`, `cute` |
| `publishedAt` | The **NEW** badge shows for 14 days after this |
| `popularity` | Rank, 1 = most applied. 0 = no data yet, sorts last. Seed values until the Events API exists (section 6) |
| `scene` | Which engine draws the wallpaper (section 5). Live = the scene animates; the app works this out from the scene |
| `palette` | The five `ThemePalette` colours plus optional `motif`, the scene's main shape colour |
| `accents` | Solid (1 colour) or gradient (2–3 colours, `angle` in CSS degrees: 90 = left to right, 180 = top to bottom). The first is the default. Where a gradient can't be drawn, the first colour is used |
| `variants` | Colour variants. `palette` lists only the fields it changes; `accentId` is the accent it starts with and must exist in `accents` |
| `fonts` | Font IDs (section 4.6). `labels` is the font for app names on wallp Home |
| `clock.useAccent` | Draw the lock clock in the accent colour |
| `eventIcon` | A name from the app's icon allowlist (section 7.3) |
| `iconPackId` | The pack a whole-theme apply also applies (section 4.7) |
| `wallpaperIds` | Related stand-alone wallpapers, shown on the detail page |
| `downloadBytes` | Size of every file a whole-theme apply needs (below). Shown as "Apply · 0.8 MB" |
| `previewImage` | Optional Asset: a small picture for app versions that can't draw `scene` |

**What a whole-theme apply downloads.** The scene's image layers, every picture of its icon pack, and every file of its display, body and labels fonts, each counted once. The publish step computes `downloadBytes` this way (`Catalog.assetsFor` in the models). The app downloads the same list, and applies nothing until all of it is on disk.

### 4.4 ThemeSummary (inside the catalog)

The full theme minus `accents`, `variants`, `fonts`, `clock`, `eventIcon` and `wallpaperIds`, plus:

```json
{
  "accent": { "id": "amber", "name": { "en": "Amber" }, "type": "solid", "colors": ["#FFB547"] },
  "displayFont": "caveat",
  "variantSwatches": ["#3A2318", "#2A3440"]
}
```

The summary includes `scene` and `palette`, so cards can draw the real scene, not just a colour, without downloading the full file. **The publish step builds the summary from the full theme** (`ThemeDetail.toSummary()`), so the two can never disagree.

### 4.5 Wallpaper

```json
{
  "id": "snowy-cabin",
  "festivalId": "christmas",
  "name": { "en": "Snowy Cabin" },
  "kind": "scene",
  "scene": { "engine": "layers", "params": { "layers": [ /* literal colours only */ ] } },
  "tags": ["cabin", "snow", "warm"],
  "publishedAt": "2026-10-10T14:00:00Z",
  "popularity": 3
}
```

`kind` is one of:
- **`scene`:** drawn by a scene engine, and can be a live wallpaper. A wallpaper has no palette, so its layers use `#RRGGBB` colours, never `@tokens` (section 4.9).
- **`image`:** a still picture in several sizes. The app picks the smallest size at least as wide as the screen:

```json
"image": {
  "sizes": [
    { "width": 1080, "height": 2340, "asset": { /* Asset */ } },
    { "width": 1440, "height": 3120, "asset": { /* Asset */ } }
  ],
  "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
  "dominant": "#160C24"
}
```

### 4.6 Font

```json
{
  "id": "playfair-display",
  "family": "Playfair Display",
  "category": "display",
  "scripts": ["latin"],
  "tags": ["christmas", "serif", "elegant"],
  "license": "OFL-1.1",
  "files": [
    { "weight": 400, "maxWeight": 900, "style": "normal", "asset": { /* Asset, format ttf */ } }
  ],
  "fallbackFor": { "my": "padauk" }
}
```

- **`category`:** the Fonts screen filter: `display`, `handwritten`, `clean`, `myanmar`.
- **`files`:** `ttf` or `otf` only, because Flutter's `FontLoader` reads those. A variable font is one file with `weight` and `maxWeight`.
- **`fallbackFor`:** which font draws text in scripts this font lacks. Creepster has no Myanmar letters, so Burmese app names use Padauk.
- **`license`:** `OFL-1.1` or `Apache-2.0`. Anything else is rejected.
- **`sampleText`:** optional preview text; the default is the clock, "19:47".

### 4.7 IconPack

```json
{
  "id": "candy-cane",
  "festivalId": "christmas",
  "name": { "en": "Candy Cane" },
  "style": { "en": "Filled" },
  "kind": "images",
  "shape": "squircle",
  "tile": "#F5F1EA", "glyph": "#B0182F", "ring": "#B0182F",
  "glyphs": { "phone": { /* Asset, png */ }, "messages": { /* Asset */ }, "…": {} },
  "publishedAt": "2026-10-11T14:00:00Z",
  "popularity": 5
}
```

- **`kind`:** `painted` = drawn on the phone by `ThemedIconPainter` in the built-in style named by `painter` (`halloween`, `christmas`, `thingyan`). `images` = one downloaded picture per glyph key. Packs made in the dashboard are always `images`.
- **`shape`:** the default tile shape: `squircle`, `circle`, `square` or `leaf`. Users can change it per pack.
- **`tile`, `glyph`, `ring`:** the pack's colours, used for previews and for apps the pack has no picture for. No `tile` = icons sit straight on the wallpaper.
- **Glyph keys:** `phone`, `messages`, `camera`, `maps`, `music`, `mail`, `photos`, `clock`, `calendar`, `settings`, `browser`, `weather`, `notes`, `calculator`, `wallet`, `store`, `video`, `contacts`, `files`, `health`. The app maps installed apps to a key by package name or label ([app_glyphs.dart](../lib/icons/app_glyphs.dart)). Apps with no key, or whose key the pack doesn't draw, keep their own icon, tinted.
- **Pictures:** square PNG or WebP with a transparent background, 256 px or larger.

### 4.8 Banner (store home carousel)

```json
{
  "id": "christmas-2026",
  "tag": { "en": "WALLPAPERS" },
  "title": { "en": "Snowy Christmas" },
  "subtitle": { "en": "Snowy pines, gold ornaments and cozy cabins." },
  "cta": { "en": "Browse" },
  "action": { "type": "wallpapers", "id": "christmas" },
  "look": { "background": "#0F3D2E", "accent": "#F2B33D", "titleColor": "#F5F1EA", "font": "playfair-display", "artThemeId": "christmas-eve" },
  "startsAt": "2026-10-10T00:00:00Z",
  "endsAt": "2026-12-27T00:00:00Z",
  "sort": 20
}
```

- **`action.type`:** `festival` or `theme` (with `id`); `wallpapers`, `iconPacks` or `fonts` (optional festival `id` as a filter); or `url` (with an `https` `url`).
- **`look.accent`** is the button colour. **`look.artThemeId`** (optional) draws that theme's scene as the banner picture.
- The app hides banners outside their `startsAt`/`endsAt` window, so they can be scheduled ahead.

### 4.9 Layers scene (`engine: "layers"`)

The engine for every dashboard-made theme and wallpaper (section 5, level 2). `params.layers` is a list drawn back to front. Positions are fractions of the screen (0–1, from the top left). Sizes are fractions of the screen **width**, so circles stay round on any phone.

```json
{ "type": "gradient", "colors": ["@surface", "@background"], "angle": 180 }
{ "type": "shape", "shape": "circle", "x": 0.7, "y": 0.28, "width": 0.5, "color": "@motif", "glow": true, "motion": "pulse" }
{ "type": "shape", "shape": "polygon", "x": 0.5, "y": 0.6, "width": 0.62, "aspect": 1.15, "color": "@motif", "points": [[0.5, 0], [1, 1], [0, 1]] }
{ "type": "image", "image": { /* Asset */ }, "fit": "width", "anchor": "bottom" }
{ "type": "particles", "effect": "snow", "count": 70, "speed": 0.3, "size": 0.35, "color": "#FFFFFF", "opacity": 0.9 }
```

| Layer | Fields |
|---|---|
| `gradient` | `colors` (2 or more), `angle` (default 180) |
| `shape` | `shape`: `circle`, `ellipse`, `rect`, `polygon`. `x`, `y`: centre. `width`; height = width × `aspect` (default 1). `points`: polygon corners inside the shape's box, 0–1, at least 3. `glow`. `motion`: `none`, `float`, `pulse`, `sway` |
| `image` | `image`: an Asset. `fit`: `width` (default), `cover`, `contain`. `anchor`: `top`, `center`, `bottom` (default) |
| `particles` | `effect`: `snow`, `rain`, `drops`, `bats`, `lanterns`, `petals`, `sparkles`, `stars`. `count`: 1–150. `speed`: 0–1 (0 = still). `size`: 0–1 |

Every layer also takes `opacity` (0–1, default 1).

**Colours** are `#RRGGBB` or a **palette token**: `@background`, `@deep`, `@surface`, `@text`, `@motif`, `@accent`. Tokens follow the theme's palette, the chosen variant and the user's accent, so one scene serves every variant. Only themes can use tokens; wallpapers have no palette.

**Live** = at least one moving shape, or particles with `speed` above 0. Live themes get the LIVE badge and can be set as the live wallpaper.

**Limits** keep a live wallpaper cheap to run for hours: at most 150 particles per layer, positions between -0.5 and 1.5, widths up to 3 screen widths.

### 4.10 Broken data: what the app does

The app never trusts the catalog to be perfect:

- **One broken item is skipped**, not the whole catalog: a theme with a bad colour disappears, the rest still show. The app keeps a list of what it skipped (`Catalog.issues`) for logs.
- **Hard references:** an item that points at something missing is dropped. Examples: a theme whose festival, icon pack or display font is gone; a banner whose theme is gone. This repeats until stable, so dropping a theme also drops the banner that opens it.
- **Soft references** keep the item and use a fallback: a festival's `coverThemeId`, a banner's `artThemeId`, a font's `fallbackFor`.
- **Unknown engines are hidden** (section 5), including `painted` icon packs whose painter this build lacks.

The publish step must be stricter: the dashboard refuses to publish while `Catalog.validate()` reports anything, soft references included.

### 4.11 The mock catalog

Until the real API exists, the app reads a complete catalog bundled at [assets/mock/catalog/v1/](../assets/mock/catalog/v1/), laid out exactly like the CDN: `manifest.json`, `catalog.<version>.json`, `themes/<id>.<rev>.json`, `engines.json` and `assets/<sha256>.<ext>`.

It contains 7 festivals (2 coming soon), 30 themes (3 built-in, 27 using the `layers` engine), 12 wallpapers, 10 fonts, 9 icon packs (6 with downloaded pictures) and 5 banners (1 scheduled for later), with 135 files totalling 4.7 MB.

**To change it:** edit [tool/seed/seed_data.dart](../tool/seed/seed_data.dart), then run `dart run tool/seed/generate.dart`. The generator builds everything through the models above, fills in hashes, sizes and `downloadBytes`, and reads its own output back through the app's parser. If icon or scene art in [tool/seed/art.dart](../tool/seed/art.dart) changes, first run `flutter test tool/seed/render_art_test.dart`. Fonts are fetched once from Google Fonts (OFL / Apache) into `tool/seed/source/fonts/`, with their licences.

[test/catalog/](../test/catalog/) checks the mock catalog the way the app's download code will: every hash, size and reference, no unused files, and each summary equal to its full theme.

The generator also writes the **built-in catalog** at [assets/builtin/catalog/](../assets/builtin/catalog/), which the app keeps after the mock is removed. It holds the three painted themes, with every festival and banner and only the painted icon packs, so a first launch with no internet still has a working store. Its `catalogVersion` is `built-in`, so it never matches a published version and the first successful refresh always replaces it.

**Dates in the mock catalog are placeholders.** The Thingyan and Thadingyut dates are not checked against the Myanmar calendar. "Published" dates are counted back from 15 October 2026, so NEW badges expire in real time; tests use a fixed clock.

---

## 5. Scene engines: the important limit

Today each wallpaper scene is **Dart code** (`HalloweenPainter`, `ChristmasPainter`, `ThingyanPainter` in [lib/scenes/](../lib/scenes/)). **An app can't download new Dart code.** So a theme from the API can only use painters that the installed app already contains.

That leaves three ways to make new themes:

| Level | How a new theme gets its scene | Download size | Needs an app update? |
|---|---|---|---|
| **1. Reuse an engine** | Pick an existing engine (`halloween`, `christmas`, `thingyan`) and give it new colours, accents, fonts and params | 0 MB | No |
| **2. Generic layered engine** (recommended next step) | Add one new engine to the app, `layers`, that draws a scene from a JSON list of layers: a background image or gradient, shapes, and particle effects (snow, rain, bats, lanterns, petals) | 0.2–1 MB of images | Once, to add the engine |
| **3. Animation files** | A `lottie` or `rive` engine that plays a downloaded animation file | 0.1–2 MB | Once, to add the engine |

Example of a level 2 scene (full layer reference in section 4.9):

```json
{
  "engine": "layers",
  "params": {
    "layers": [
      { "type": "gradient", "colors": ["@surface", "@background"], "angle": 180 },
      { "type": "shape", "shape": "circle", "x": 0.7, "y": 0.2, "width": 0.18, "color": "@motif", "glow": true },
      { "type": "image", "image": { "url": "assets/9a35….png", "sha256": "9a35…", "bytes": 15577, "format": "png" }, "fit": "width", "anchor": "bottom" },
      { "type": "particles", "effect": "snow", "count": 80, "speed": 0.4, "color": "#FFFFFF" }
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
    { "id": "layers",    "sinceApp": "1.0.0", "params": ["layers"] }
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
