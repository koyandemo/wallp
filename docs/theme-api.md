# wallp Theme API

How wallp gets its themes, wallpapers and fonts from a server instead of shipping them inside the app, and how the app uses them.

**Status (17 Oct 2026):** the format is final for v1 and the app is built on it, running on a mock catalog until the CDN exists (section 7). What the user can change on the phone is in section 7.5.

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
| Replace the `google_fonts` package with the API's font delivery (section 7.7). The package carries a large list of every Google font; check the size report to confirm how much. | Possibly several MB | Medium (part of this project) |
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
- **`catalog`** must be exactly `catalog.<catalogVersion>.json`, and that file's own `catalogVersion` must match. The app rejects the manifest or catalog otherwise, and also when the downloaded catalog's sha256 isn't `catalogSha256`.
- **`minAppVersion`:** if the app is older, it keeps working with the new catalog and flags that an update is recommended. Today only Developer settings shows this; a soft "Update wallp to get new themes" banner for users is still to do.

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
  "searchSuggestions": ["Halloween", "Christmas", "Thingyan", "moon", "snow", "spider", "neon", "live"]
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

Every downloadable file (images, icon tiles, fonts) is an Asset object:

```json
{ "url": "assets/9a359a28….png", "sha256": "9a359a28…", "bytes": 15577, "format": "png" }
```

- **`url`** is relative to the catalog base URL and must be exactly `assets/<sha256>.<format>`. A file can't be swapped without its name changing, so every asset is cached forever.
- **`format`**: `png`, `webp`, `jpg`, `ttf`, `otf`, `woff2` or `json`.
- **`bytes`** at most 10 MB (section 8). The app checks size and hash after downloading and throws the file away if either is wrong.

### 4.2 Festival

A festival with dates (Halloween, Thingyan) or an undated collection (Heroes, Neon).

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
| `occurrences` | Real first-day dates, strictly in order with no repeats. Required for Myanmar-calendar festivals, whose Gregorian date moves |
| `fallbackDate` | `{ "month", "day" }`. Used for fixed-date festivals, and once `occurrences` runs out. 29 February is not allowed |
| `durationDays` | How long it lasts, at least 1 (default 1). Every day of it shows "Happy Thingyan!" |
| `unit` | Countdown word: `day` (default) or `night` |
| `look` | The app's colours while browsing this festival ("Match app to my theme"); all eight fields are required. `displayFont` is a font ID and must exist. `muted` must be at least 4.5:1 on `background` |
| `coverThemeId` | Optional theme used as the festival's picture |

**Countdown rule.** The next run is the first occurrence whose *last* day is on or after today. When the list runs out, `fallbackDate` is used, but never in a year the list already covered. A dated festival needs at least one of `occurrences` and `fallbackDate`, unless it's `comingSoon` (no countdown).

### 4.3 Theme (full): `themes/<id>.<rev>.json`

```json
{
  "id": "neon-night",
  "rev": 1,
  "festivalId": "neon",
  "name": { "en": "Neon Night" },
  "subtitle": { "en": "A synthwave sun on a glowing grid" },
  "style": "minimal",
  "tags": ["neon", "synthwave", "retro", "grid", "night"],
  "publishedAt": "2026-10-14T14:00:00Z",
  "popularity": 0,
  "minAppVersion": "1.0.0",
  "scene": { "engine": "layers", "params": { "layers": [ /* section 4.9 */ ] } },
  "palette": {
    "background": "#120326", "deep": "#07010F", "surface": "#3A0B5C",
    "text": "#F8F0FF", "textMuted": "#B3A9BE", "motif": "#FF3EA5"
  },
  "accents": [
    { "id": "neon-cyan", "name": { "en": "Neon cyan" }, "type": "solid", "colors": ["#22E4FF"] },
    { "id": "hot-pink", "name": { "en": "Hot pink" }, "type": "solid", "colors": ["#FF3EA5"] },
    { "id": "synthwave", "name": { "en": "Synthwave" }, "type": "gradient", "colors": ["#FF3EA5", "#22E4FF"], "angle": 90 }
  ],
  "variants": [
    { "id": "midnight", "name": { "en": "Midnight" } },
    { "id": "sunset", "name": { "en": "Sunset" },
      "palette": { "background": "#2A0A2E", "surface": "#6B1747", "motif": "#FF8A3D" },
      "accentId": "hot-pink" }
  ],
  "fonts": { "display": "orbitron", "body": "space-grotesk", "labels": "orbitron" },
  "clock": { "useAccent": true },
  "labels": { "color": "#F8F0FF" },
  "eventIcon": "music_note_rounded",
  "iconPackId": "neon-glow",
  "wallpaperIds": ["neon-horizon"],
  "downloadBytes": 213510
}
```

| Field | Meaning in the app |
|---|---|
| `rev` | Increases whenever **anything** in this file changes, even one colour. The app caches theme files by `rev` and never re-reads a `rev` it already has, so an edit published under the same `rev` never reaches phones that opened the theme before |
| `subtitle` | Optional one-line description. Search matches it as well as the name and tags |
| `style` | Festival page filter: `classic`, `cozy`, `minimal`, `cute` |
| `publishedAt` | The **NEW** badge shows for 14 days after this |
| `popularity` | Rank, 1 = most applied. 0 = no data yet, sorts last. Seed values until the Events API exists (section 6) |
| `minAppVersion` | Optional, default `1.0.0`. Older apps hide the theme (section 5) |
| `scene` | Which engine draws the wallpaper (section 5). Live = the scene animates; the app works this out from the scene |
| `palette` | The five `ThemePalette` colours plus optional `motif`, the scene's main shape colour |
| `accents` | At least one, IDs unique within the theme. Solid (1 colour, no `angle`) or gradient (2–3 colours, `angle` 0–359 in CSS degrees, default 90: 90 = left to right, 180 = top to bottom). The first is the default. Gradients are drawn as gradients on the lock clock, the countdown icon and the theme name; where one can't be (app names, icon rings), the first colour is used. The phone remembers the user's pick per theme (section 7.5) |
| `variants` | Colour variants. `palette` lists only the fields it changes; `accentId` is the accent it starts with and must exist in `accents`. **The store doesn't offer variants at the moment** (the "Colours" row was removed for a simpler detail page): the app still parses and validates them, and draws the theme in its own palette. Keep them optional |
| `fonts` | Font IDs (section 4.6). `display` is the clock and headline font. `labels` is the font for app names on wallp Home: the **"Theme font"** choice on the icon pack page (the other choice is "System font", the phone's own). Use the theme's own character font here (Halloween: Creepster) so "Theme font" looks themed; a font without Myanmar letters falls back to Padauk for Burmese names |
| `clock.useAccent` | Draw the lock clock in the accent colour |
| `labels.color` | Optional. App names everywhere on wallp Home (home grid, dock, app drawer, app lists) and in the "Add icons to your home screen" list; omitted = white. The app adds a shadow (dark behind light names, light behind dark ones). It's the **"Theme"** choice on the icon pack page; the user can pick Accent, White, Dark or any custom colour instead |
| `eventIcon` | Optional, default `event`. A name from the app's icon allowlist (section 7.3) |
| `iconPackId` | The pack a whole-theme apply also applies (section 4.7) |
| `wallpaperIds` | Related stand-alone wallpapers, shown on the detail page |
| `downloadBytes` | Size of every file a whole-theme apply needs (below). Shown as "Apply · 0.8 MB" |
| `previewImage` | Optional Asset: a small picture for app versions that can't draw `scene` |

**What a whole-theme apply downloads.** The scene's image layers, its icon pack's `background` tile, and every file of its display, body and labels fonts, each counted once. The publish step computes `downloadBytes` this way (`Catalog.assetsFor` in the models). The app downloads the same list, and applies nothing until all of it is on disk.

### 4.4 ThemeSummary (inside the catalog)

The full theme minus `accents`, `variants`, `fonts`, `clock`, `labels`, `eventIcon` and `wallpaperIds`, plus:

```json
{
  "accent": { "id": "neon-cyan", "name": { "en": "Neon cyan" }, "type": "solid", "colors": ["#22E4FF"] },
  "displayFont": "orbitron",
  "variantSwatches": ["#120326", "#2A0A2E"]
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

`minAppVersion` is optional here too (default `1.0.0`); older apps hide the wallpaper. Wallpaper cards show IN USE or LIVE, never NEW; `publishedAt` only sorts them. (Icon packs do use it: "New ·" and the New filter, 14 days.)

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
- **`scripts`:** required: the scripts the font has letters for, `latin` and/or `myanmar`.
- **`files`:** at least one, `ttf` or `otf` only, because Flutter's `FontLoader` reads those. `weight` is 100–900 (default 400), `style` is `normal` (default) or `italic`. A variable font is one file with `weight` and `maxWeight` (at least `weight`).
- **`fallbackFor`:** which font draws text in scripts this font lacks. Creepster has no Myanmar letters, so Burmese app names use Padauk.
- **`license`:** `OFL-1.1` or `Apache-2.0`. Anything else is rejected.
- **`sampleText`:** optional preview text in the Fonts list; the default is "Welcome".
- **`listed`:** optional, default `true`. `false` hides the font from the store (Fonts tab, search, a theme's "clock font" row and its "Clock font only" apply option) while themes that use it still draw with it.

### 4.7 IconPack

```json
{
  "id": "web-slinger",
  "festivalId": "heroes",
  "name": { "en": "Web Slinger" },
  "style": { "en": "Comic" },
  "kind": "images",
  "shape": "squircle",
  "tile": "#D3202A", "glyph": "#FFFFFF", "ring": "#0A0A12",
  "background": { /* Asset, png */ },
  "publishedAt": "2026-10-14T14:00:00Z",
  "popularity": 0
}
```

- **`kind`:** `painted` = drawn on the phone by `ThemedIconPainter` in the built-in style named by `painter` (`halloween`, `christmas`, `thingyan`; required for this kind). `images` = one downloaded `background` tile (required for this kind). Packs made in the dashboard are always `images`.
- **An `images` pack never replaces an app's logo.** On wallp Home every app keeps its own logo (an adaptive icon's foreground layer; older icons whole), drawn on the pack's `background`. The store's previews show the phone's own apps the same way, and a symbol per kind of app (Phone, Messages…) where there are no real apps to show. There are no per-app pictures.
- **`shape`:** the default tile shape: `squircle`, `circle`, `square` or `leaf`. Users can change it on the icon pack page, where the picker shows one of their apps in each shape; tapping a shape puts the pack on wallp Home at once (the page has no Apply step). Every icon follows the chosen shape: painted packs are drawn in it, and the `background` is clipped to it. So **draw the background edge to edge on a square canvas, with no rim, border or rounded corners**. The app draws the rim itself, in `ring`, along whichever shape the user picked (packs with a `tile`; packs without one get no rim). A pinned home-screen shortcut gets the same square, masked by the launcher's own shape.
- **`tile`, `glyph`, `ring`:** the pack's colours. `tile` stands in for the `background` while it downloads; `glyph` colours the sample apps' symbols in previews; `ring` is the rim the app draws around every tile. No `tile` = icons sit straight on the wallpaper.
- **`background`:** `images` packs only, required. The pack's tile picture: every app's own logo goes in the middle of it, so all apps match the pack and stay recognisable. Keep the middle half calm, and the whole tile dark or busy enough that white logos still read. It's the only file the pack downloads (a few dozen KB), fetched as soon as the user opens the pack's page.
- **The `background` file:** square PNG or WebP, 256 px or larger.

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

- **Required:** `id`, `title`, `subtitle`, `tag`, `cta`, `action`, `look` (all five colours and fonts below except `artThemeId`) and `sort` (lower first).
- **`action.type`:** `festival` or `theme` (with `id`); `wallpapers`, `icon-packs` or `fonts` (optional festival `id` as a filter; it must exist); or `url` (with an `https` `url`). Note the spelling `icon-packs`: like every multi-word value in the format, it's kebab-case.
- **`look.accent`** is the button colour. **`look.font`** is a font ID for the title. **`look.artThemeId`** (optional) draws that theme's scene as the banner picture.
- **`startsAt` / `endsAt`** are both optional; `endsAt` must be after `startsAt`. The app hides banners outside the window, so they can be scheduled ahead.

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
| `shape` | `shape`: `circle`, `ellipse`, `rect`, `polygon`. `x`, `y`: centre, -0.5–1.5. `width`: above 0, up to 3; height = width × `aspect` (above 0, up to 10, default 1). `color` (required). `points`: polygon corners inside the shape's box, each `[x, y]` in 0–1, at least 3. `glow` (default false). `motion`: `none` (default), `float`, `pulse`, `sway` |
| `image` | `image`: an Asset. `fit`: `width` (default), `cover`, `contain`. `anchor`: `top`, `center`, `bottom` (default) |
| `particles` | `effect`: `snow`, `rain`, `drops`, `bats`, `lanterns`, `petals`, `sparkles`, `stars`. `count`: 1–150. `color` (required). `speed`: 0–1, default 0.5 (0 = still). `size`: above 0, up to 1, default 0.5 |

Every layer also takes `opacity` (0–1, default 1).

**Colours** are `#RRGGBB` or a **palette token**: `@background`, `@deep`, `@surface`, `@text`, `@motif`, `@accent`. Tokens follow the theme's palette, the chosen variant and the user's accent, so one scene serves every variant. Only themes can use tokens; wallpapers have no palette.

**Live** = at least one moving shape, or particles with `speed` above 0. Scenes on the built-in engines (`halloween`, `christmas`, `thingyan`) always count as live. Live themes get the LIVE badge and can be set as the live wallpaper.

**Limits** keep a live wallpaper cheap to run for hours: at most 150 particles per layer, positions between -0.5 and 1.5, widths up to 3 screen widths.

### 4.10 Broken data: what the app does

The app never trusts the catalog to be perfect:

- **One broken item is skipped**, not the whole catalog: a theme with a bad colour disappears, the rest still show. The app keeps a list of what it skipped (`Catalog.issues`) for logs.
- **Unknown values:** a required field with an unknown value (e.g. `style: "retro"`) breaks that item. An *optional* one with a default falls back to the default without a warning (e.g. `unit: "week"` reads as `day`, an unknown `motion` as `none`), so the publish checks must catch typos there.
- **Hard references:** an item that points at something missing is dropped. Examples: a theme whose festival, icon pack or display font is gone; a banner whose theme is gone. This repeats until stable, so dropping a theme also drops the banner that opens it.
- **Soft references** keep the item and use a fallback: a festival's `coverThemeId`, a banner's `artThemeId`, a font's `fallbackFor`.
- **Unknown engines are hidden** (section 5), including `painted` icon packs whose painter this build lacks. So are themes and wallpapers whose `minAppVersion` is above this app's version.

The publish step must be stricter: the dashboard refuses to publish while `Catalog.validate()` reports anything, soft references included.

### 4.11 The mock catalog

Until the real API exists, the app reads a mock catalog laid out exactly like the CDN: `manifest.json`, `catalog.<version>.json`, `themes/<id>.<rev>.json`, `engines.json` and `assets/<sha256>.<ext>`.

**The demo catalog** at [assets/mock/catalog/v1/](../assets/mock/catalog/v1/) is what the app shows and what the tests check: three complete themes (Haunted Moon for Halloween, Snowy Pines for Christmas, Water Splash for Thingyan) and one wallpaper per festival, with their painted icon packs, fonts and banners, plus two themes made entirely from script, each with its own collection, wallpapers, icon pack and banner: **Spider Night** (live `layers` scene with picture layers; [tool/seed/spider_night.dart](../tool/seed/spider_night.dart)) and **Neon Night** (a scene drawn only from shapes and particles, two colour variants, a gradient accent and its own Orbitron font; [tool/seed/neon_night.dart](../tool/seed/neon_night.dart)). Run `tool/seed/spider_night.sh` to rebuild both. 5 festivals, 5 themes, 6 wallpapers, 8 fonts, 5 icon packs, 6 banners and 13 asset files (2.7 MB).

**Versions in the demo catalog.** Installed apps only fetch a catalog whose `catalogVersion` is new, and only re-read a theme file whose `rev` is new (section 9). So every change to the demo data needs both bumps, or phones that already have it keep the old data:
- `demoRevision` in [seed_data.dart](../tool/seed/seed_data.dart) → the demo's `catalogVersion` becomes `2026-10-15.1-demo.<demoRevision>` (now `demo.11`).
- The changed theme's `rev` (now Haunted Moon 3, Snowy Pines 2, Water Splash 2, Spider Night 4, Neon Night 1).

The `rev` comments in `seed_data.dart` say what each bump changed.

**To change it:** edit [tool/seed/seed_data.dart](../tool/seed/seed_data.dart), then run `dart run tool/seed/generate.dart`. The generator builds everything through the models above, fills in hashes, sizes and `downloadBytes`, and reads its own output back through the app's parser. If icon or scene art in [tool/seed/art.dart](../tool/seed/art.dart) changes, first run `flutter test tool/seed/render_art_test.dart`. Fonts are fetched once from Google Fonts (OFL / Apache) into `tool/seed/source/fonts/`, with their licences.

[test/catalog/](../test/catalog/) checks the mock catalog the way the app's download code will: every hash, size and reference, no unused files, and each summary equal to its full theme.

The generator also writes the **built-in catalog** at [assets/builtin/catalog/](../assets/builtin/catalog/), which the app keeps after the mock is removed. It holds the three painted themes, the festivals they belong to, their banners and only the painted icon packs, so a first launch with no internet still has a working store. Its `catalogVersion` is `built-in`, so it never matches a published version and the first successful refresh always replaces it.

**Dates in the mock catalog are placeholders.** The Thingyan dates are not checked against the Myanmar calendar. "Published" dates are counted back from 15 October 2026, so NEW badges expire in real time; tests use a fixed clock.

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
- **App:** hides themes whose engine it doesn't know, or whose `minAppVersion` is above its own (Developer settings shows how many were hidden). Not built yet: showing a theme's `previewImage` as "Update wallp to use this theme" instead of hiding it. The app parses `previewImage` but doesn't use it yet.

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

## 7. The wallp app side (built)

This section started as a plan; it now describes what the app does. Phases 1–8 of [store-redesign-plan.md](store-redesign-plan.md) are done, and the app runs on the mock catalog (section 4.11) through the same code path the real API will use.

### 7.1 Where things are

| Planned as | Built as | Job |
|---|---|---|
| `ThemeRepository` | `CatalogRepository` ([lib/data/catalog/](../lib/data/catalog/)) | Festivals, themes, wallpapers, fonts, icon packs, banners. Cached catalog first, refresh in the background, full theme files on demand |
| `CatalogClient` | `CatalogSource`: `MockCatalogSource` today (reads `assets/mock/catalog/v1/`, can pretend to be slow, offline or flaky from Developer settings); an HTTP source pointed at the CDN later. **Binding the real API = adding that one class** | Reads `manifest.json`, catalogs, theme files and assets |
| | `CatalogStore` (file, memory) and `BuiltInCatalog` | The saved catalog on disk; the first-launch catalog in the APK |
| `AssetCache` | `AssetCache` + `DownloadManager` ([lib/data/assets/](../lib/data/assets/)) | Files by sha256 with hash and size checks, atomic writes, 50 MB LRU, pins. 3 downloads at once, retries, cancel, progress card |
| `FontRegistry` | `FontRegistry` ([lib/render/font_registry.dart](../lib/render/font_registry.dart)) | Loads downloaded `ttf`/`otf` as `wallp-<id>`, with Padauk for Burmese. Tells listeners when a font loads, so previews redraw in it. `google_fonts` is still the fallback (section 7.7) |
| Snapshot in `ThemePrefs` | `AppliedLook` + `LookStore` + `LookController` ([lib/look/](../lib/look/)) | The applied look as one saved snapshot (section 7.4) |
| `SceneRegistry` | `scenePainterFor` + `LayersPainter` ([lib/scenes/](../lib/scenes/), [lib/render/](../lib/render/)) | Built-in painters by engine ID, and the `layers` engine (section 4.9) |
| | `ResolvedLook` | Turns a look into what each screen draws (lock screen, wallp Home, live wallpaper) |

### 7.2 Startup and offline behaviour

As planned, and tested:
1. **First launch:** the built-in catalog, so the store works with no internet.
2. **Every launch:** the saved catalog at once, then `manifest.json` in the background; a new `catalogVersion` is downloaded, checked against `catalogSha256`, saved and shown.
3. **Opening a theme:** its file is fetched if this `rev` isn't saved yet; the summary shows meanwhile.
4. **Applying:** every file the look needs is downloaded first, with a progress card ("Apply · 0.8 MB"). Nothing changes until all of it is on disk; a failure keeps the old look and says why.
5. **Pinned:** the applied look's files are never evicted. wallp Home and the live wallpaper run as separate engines and read the snapshot and files from disk only.

### 7.3 Event icons

`eventIcon` is a string from an allowlist ([lib/look/event_icons.dart](../lib/look/event_icons.dart)); unknown names show `Icons.event`. Flutter drops unused icons from the build, so the list is fixed in the app, and adding a name needs an app update:

`event`, `nightlight_round`, `card_giftcard_rounded`, `water_drop_rounded`, `light_mode_rounded`, `celebration_rounded`, `local_florist_rounded`, `ac_unit_rounded`, `star_rounded`, `favorite_rounded`, `music_note_rounded`.

### 7.4 The applied look (one snapshot)

`AppliedLook` saves everything the phone shows, so the other engines and a removed theme keep working: the theme file, festival, accent, clock font with size and places, icon pack with the user's shape and app name colour and font, the wallpaper choice, and every font used. Older saves still load: fields added later read as their defaults.

### 7.5 What the user chooses on the phone (not in the API)

The API gives each theme its defaults; these choices are the user's and live only on the phone:

| Choice | Where | Default from the API |
|---|---|---|
| Accent, remembered **per theme** | Theme page; "Gradients & custom" for any colour or gradient | The theme's first accent |
| Tile shape | Icon pack page (one of the phone's own apps in each shape) | The pack's `shape` |
| App name colour: Theme / Accent / White / Dark / Custom | Icon pack page, with a live preview | The theme's `labels.color`, else white |
| App name font: Theme font / System font | Icon pack page | The theme's `fonts.labels` |

The icon pack page has **no Apply button**: tapping a shape, name colour or font puts that pack on wallp Home with the choice at once. Its previews show the phone's own apps (each logo on the pack's tile), and the page downloads the pack's `background` as soon as it opens.
| Clock font, size, and where it shows (lock clock, wallp Home clock, app labels) | Font page, with a lock and home preview that follows the switches | The theme's `fonts.display` |
| Wallpaper: home, lock, both (a still picture) or the live wallpaper | The "Set wallpaper on" sheet when applying | — |

The theme page previews use these choices too (shape, name colour, name font), so a theme looks the way it will on this phone.

### 7.6 Live wallpaper

- One Android `WallpaperService` runs the `wallpaperMain` Flutter entry point and draws the applied look's scene at 30 fps, with the themed lock clock while the phone is locked. It pauses while hidden.
- **Applying:** "Live wallpaper (animated)" in the sheet opens Android's preview for wallp's live wallpaper straight away. If wallp's live wallpaper is already on, nothing opens: it redraws with the new look by itself.
- **realme UI / ColorOS:** the system preview closes itself at once when its app wasn't running yet, and the system list of live wallpapers doesn't show other apps' wallpapers. The app detects a picker that closes within 1.5 s and opens it once more. Seen on a realme RMX5253, Android 16.
- **Previews animate only while wallp's live wallpaper is on** (`LiveWallpaperStatus`, checked on every return to the app). With a still wallpaper, the theme page, Me and festival previews are still.

### 7.7 Fonts and `google_fonts`

Theme fonts come from the catalog and load with `FontLoader`; their files are pinned with the applied look. `google_fonts` is still in the app as a fallback for fonts not downloaded yet (for example a font page opened before applying). Removing it, and bundling only the UI font and Padauk, is the remaining step of the plan's phase 3 (section 10).

### 7.8 Request headers

Not sent yet: the mock source makes no HTTP requests. The HTTP source should send `User-Agent: wallp/<version> (Android <sdk>)` and `X-Wallp-Engines: halloween,christmas,thingyan,layers`.

### 7.9 Tests

361 tests cover parsing of every example here, the mock catalog's hashes and references, offline first launch, unknown schemas and engines, failed downloads keeping the old look, the snapshot in the other engines, countdowns, and the store screens. Run `flutter test`.

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
| **Any publish** | A new `catalogVersion` (and file name). Phones fetch the catalog only when the version in `manifest.json` differs from theirs, so re-uploading a changed catalog under the old version reaches no one who already has it |
| **Edit a theme** | Increase its `rev`, for the same reason (section 4.3) |
| Add an optional field | Same `schemaVersion`; old apps ignore it |
| Add a new engine | Same `schemaVersion`; set the theme's `minAppVersion` to the version that added the engine |
| Rename or remove a field, or change its meaning | New `schemaVersion` (2), publish both v1 and v2 catalogs side by side (`/catalog/v1/`, `/catalog/v2/`) until old app versions are rare |
| Remove a theme | Remove it from the catalog. Phones that applied it keep their snapshot. |

---

## 10. Build plan

| Phase | Work | Status |
|---|---|---|
| **0. Size quick win** | Ship an App Bundle; add `--obfuscate --split-debug-info` | To do |
| **1. Catalog format** | Models and parser for every object in section 4; parsing tests over the mock catalog; JSON Schema files for the dashboard | Done, except the JSON Schema files (the Dart models are the schema for now) |
| **2. Repository + cache** | `CatalogRepository`, `CatalogSource`, `AssetCache`, downloads, the look snapshot | Done on the mock source. **Next: the HTTP source for the real CDN** |
| **3. Fonts** | `FontRegistry`; remove `google_fonts`; bundle Sora + Myanmar font | `FontRegistry` done; removing `google_fonts` to do |
| **4. Dashboard v1** | Festivals, themes with existing engines, fonts, icon packs, banners, Publish | To do ([theme-dashboard.md](theme-dashboard.md)) |
| **5. Layers engine** | `layers` engine in the app plus the scene editor in the dashboard | App side done (Spider Night and Neon Night use it); dashboard editor to do |
| **6. Popularity** | Events API + nightly job | To do; `popularity` is seed data |

---

## 11. Open questions for the team

1. Which hosting option (section 2)?
2. Which languages besides English and Myanmar?
3. Should some themes be paid later? If so, add an `access` field now (`free` / `premium`) so old apps don't show premium themes for free.
4. Is an iOS version planned? iOS can't be a home-screen app, so only wallpapers and previews would apply there.
