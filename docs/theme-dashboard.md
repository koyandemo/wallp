# wallp Theme Dashboard

The web tool the wallp team uses to create, generate, preview and publish themes, wallpapers, fonts and store banners. What it publishes is exactly the catalog described in [theme-api.md](theme-api.md), which the app reads.

---

## 1. What the dashboard must do

1. **Create** festivals, themes, wallpapers, fonts and store banners.
2. **Generate** a new theme from a few choices (festival, mood, base colour), then let a person adjust it.
3. **Preview** a theme exactly as the phone will draw it: lock screen, wallp Home with icons, and live wallpaper.
4. **Check** it before publishing: readable colours, fonts with the right letters, file sizes, supported app versions.
5. **Publish** a new catalog version to the CDN, on a schedule if needed, with one-click rollback.

Out of scope for v1: paid themes, user accounts in the app, user-submitted themes.

---

## 2. Staying in sync with the app

The dashboard, the API and the app must never disagree about what a theme is. Four rules keep them in sync:

| Rule | How |
|---|---|
| **One schema** | The JSON Schema files for the catalog (from phase 1 of the API plan) live in one place, e.g. a `schema/` folder in the app repo. The dashboard validates against them on every save and publish; the app's parsing tests use the same files. |
| **One engines list** | `engines.json` (API doc section 5) lists every scene engine, its params, and the app version that added it. The dashboard only offers engines in this list, and sets `minAppVersion` automatically. |
| **Same painters for preview** | The preview is the app's own Flutter scene and icon painters, built for the web (section 5.4). What you see in the dashboard is what the phone draws. |
| **Fixtures both ways** | Any theme can be exported as JSON. Exported themes become test fixtures in the app repo, and the app's built-in themes can be imported into the dashboard. |

---

## 3. People and permissions

| Role | Can do |
|---|---|
| **Admin** | Everything, including users, publishing and rollback |
| **Designer** | Create and edit drafts, generate themes, upload files, request review |
| **Reviewer** | Approve or reject drafts, schedule publishing |
| **Viewer** | Read only, see statistics |

Login uses email + password with 2-step verification, or Google sign-in limited to the team's domain. Every change goes into the **audit log** (section 5.10).

---

## 4. Screens

```
Login
└─ Overview
   ├─ Festivals ─ Festival editor
   ├─ Themes ─── Theme editor ── Generate theme (wizard)
   ├─ Wallpapers ─ Wallpaper editor
   ├─ Fonts ──── Font editor
   ├─ Banners ── Banner editor (store carousel)
   ├─ Publish ── Release history / Rollback
   ├─ Statistics
   └─ Settings ─ Users, Engines, Audit log
```

### 4.1 Overview

- **Next festivals** with countdowns and theme counts, e.g. "Halloween in 16 nights · 4 themes". A warning shows when a festival within 30 days has fewer than 3 published themes.
- **Drafts waiting for review.**
- **Last publish:** version, time, who published it, and a **Roll back** button.
- **Top themes this week** (from the Events API, once it exists).

### 4.2 Festivals

List columns: name, next date, countdown, number of themes (published / drafts), "coming soon" flag, sort order (drag to reorder).

**Festival editor fields:**
- Name per language, ID (fixed after the first publish).
- Countdown unit: day or night.
- **Dates per year**: a table of years and dates. A "Fill next 5 years" button for fixed-date festivals (Halloween, Christmas). Myanmar-calendar festivals (Thingyan, Thadingyut) are entered by hand. A warning shows when fewer than 2 future dates remain.
- "Coming soon" switch.
- **App look** while browsing this festival: background, cards, outline, muted text, brand colour, heading font. A contrast check runs live (section 6).
- Cover theme.

### 4.3 Themes

**List:** cards like the app's own grid, with status (Draft / In review / Scheduled / Published / Archived), festival, style, LIVE flag and last editor. Filters by festival, status, style and engine; search by name or tag.

**Theme editor:** a form on the left, a live phone preview on the right.

| Section | Fields |
|---|---|
| **Basics** | Name and subtitle per language, festival, style (classic / cozy / minimal / cute), tags, ID |
| **Scene** | Engine (from `engines.json`) and its params. For the `layers` engine: a layer list editor (add background, image, shape or particles; drag to reorder; tweak each layer) |
| **Palette** | background, deep, surface, text, textMuted, each with a colour picker and hex field. Contrast results show next to each (section 6). |
| **Accents** | A list of solid or gradient accents, the same builder as the app's accent picker: colours, direction, "set as default", reorder |
| **Variants** | Add a variant: name plus only the palette colours it changes. The preview has a variant switcher. |
| **Fonts** | Display, body and app-label fonts, chosen from the Fonts library. A warning appears if a font has no Myanmar letters and the theme has Myanmar text, and the Myanmar fallback font is shown. |
| **Clock & countdown** | Clock uses accent (yes/no), event icon (from the app's icon list) |
| **Icon pack** | Icon style (from the engines list) |
| **Wallpapers** | Attach wallpapers from the library |
| **Preview image** | Generated automatically on save (section 5.4). You can upload a replacement. |

**Phone preview** (390 × 844, the same size as the app's `kSceneSize`):
- Tabs: **Lock screen** (clock, date, countdown card), **Home screen** (icon grid with sample apps and labels), **Live** (animated scene), **Card** (how it looks in the store grid and festival row).
- Switchers: variant, accent, and the phone language (English / Myanmar).
- A **"Send to my phone"** button shows a QR code. Scanning it opens the theme in a test build of the app (section 8).

**Bottom bar:** Save draft · Request review · Schedule · Publish now (admins) · Duplicate · Export JSON · Archive.

### 4.4 Generate theme (wizard)

The "generate theme from dashboard" feature. It creates a **draft**, never a published theme. A person always reviews it.

**Step 1 – Start from:**
- Festival (required).
- Mood: classic, cozy, minimal or cute.
- Base colour: a picker, or "pick for me".
- Engine: any engine available for that festival.
- Optional: a short description, e.g. "warm cabin at night with soft snow".

**Step 2 – Pick one of 6 options.** The generator makes 6 complete themes from the inputs (section 5.2), shown as phone cards side by side. Each has a **"Shuffle"** button for that one and a **"More like this"** button.

**Step 3 – Adjust.** Opens the normal theme editor with the chosen option filled in. The theme is marked "Generated", and its inputs are kept so it can be regenerated later.

### 4.5 Wallpapers

- **Upload** a PNG or JPG of at least 1440 × 3120. The dashboard makes WebP versions at 1080 and 1440 widths, a blurhash and the dominant colour automatically, and shows the file size of each.
- **Or** create a scene wallpaper from an engine with params, no upload needed.
- Fields: name, festival, tags, LIVE (for scene wallpapers), attached themes.
- **Warnings:** an image over 1 MB after compression, or a picture that's too dark or bright for the white clock text.

### 4.6 Fonts

- **Add from Google Fonts** by searching by name. The dashboard downloads the font files and records the licence automatically.
- **Upload your own** TTF or OTF. A licence choice is required, and publishing is blocked without a licence that allows redistribution.
- **Shown per font:** which scripts it supports (Latin, Myanmar, …), its weights, and a preview of "19:47", app names and Burmese sample text.
- **Fallback font** per script, e.g. Myanmar → Padauk.
- **Subsetting** (optional): keep only the letters needed, e.g. digits and Latin for a clock-only display font, to make the file smaller.

### 4.7 Banners

The store home carousel. Fields: title, subtitle, tag and button text per language; the action (open a festival, theme, Wallpapers, Fonts or a link); look (background, accent, font, engine); start and end time; order.

The preview shows the carousel at phone size with all banners that are active at a chosen date, so you can check "what users see on 20 December".

### 4.8 Publish

**Release history:** version, time, who, what changed ("+2 themes, 1 banner edited"), and the status of each release.

**Publishing has two steps.**

**1. Checks.** Everything in section 6 runs on the whole catalog. Any **error** blocks the publish; **warnings** need a tick to continue.

**2. Release.** The dashboard does these in order:
1. Builds the theme files (`themes/<id>.<rev>.json`) and `catalog.<version>.json` from published and scheduled-now items.
2. Uploads new asset files (named by sha256, so unchanged files are skipped).
3. Uploads the theme and catalog files.
4. Uploads `manifest.json` **last**, so phones never see a catalog whose files are missing.
5. Clears the CDN cache for `manifest.json` only.

**Scheduled publishing:** a timed job runs the same release at the scheduled time.

**Rollback:** re-uploads an older release's `manifest.json`. That release's files are still in storage, so rollback takes seconds. Release files are kept for at least 90 days.

**Release notes** are optional, for the team only.

### 4.9 Statistics (when the Events API exists)

Applies and favourites per theme, per festival and per day, plus the popularity ranking that the next publish will use.

### 4.10 Settings

- **Users and roles.**
- **Engines:** a read-only view of `engines.json` with the app version for each engine.
- **Audit log:** who changed what and when, with the before and after JSON, filterable by item.

---

## 5. How it works inside

### 5.1 Data storage

| Table | Main fields |
|---|---|
| `festivals` | id, name (jsonb), unit, occurrences (date[]), fallback_date, look (jsonb), cover_theme_id, coming_soon, sort |
| `themes` | id, rev, festival_id, status, style, tags, data (jsonb: the full theme JSON from the API doc), generated_from (jsonb), created_by, updated_at |
| `wallpapers` | id, festival_id, kind, data (jsonb), status |
| `fonts` | id, family, license, scripts, data (jsonb), status |
| `banners` | id, data (jsonb), starts_at, ends_at, sort, status |
| `assets` | sha256, kind, bytes, mime, storage_path, created_at |
| `releases` | version, manifest (jsonb), changes (jsonb), published_by, published_at, status |
| `audit_log` | id, user_id, item_type, item_id, before (jsonb), after (jsonb), at |
| `users` | id, email, role |

Each item's main content is stored as **JSON in the API format**, so publishing mostly copies it. Columns outside the JSON are there for search and filtering.

### 5.2 The theme generator

The generator is deterministic code, not AI, so results are predictable and always readable. The optional AI step only suggests text and moods.

**Palette from a base colour.** Work in the OKLCH colour space (perceptual lightness, chroma, hue):

| Colour | Rule |
|---|---|
| background | base hue, lightness 0.18–0.24, chroma low to medium (dark scene sky) |
| deep | same hue, lightness 0.12–0.16 |
| surface | same hue, lightness 0.28–0.34 |
| text | hue +/- 30° (warm white or cool white), lightness 0.94–0.97, very low chroma |
| textMuted | like text, lightness 0.80–0.85 |
| accents | 3 solids: the complementary hue, an analogous hue and the base hue, each at lightness 0.70–0.82 and high chroma; plus 1 gradient between two of them |

After building the palette, the generator runs the contrast checks (section 6). It nudges lightness until every check passes, and throws away the option if it can't.

**Mood changes the numbers:**
- **cozy:** warmer hues, softer accents.
- **minimal:** low chroma, one accent.
- **cute:** higher lightness accents, rounded fonts.
- **classic:** the festival's traditional colours (from the festival's look).

**Fonts:** picked from the Fonts library by tags (display + body pairs that fit the mood), always with a working Myanmar fallback.

**Engine params:** random within each param's allowed range (from `engines.json`), seeded so "Shuffle" gives a new result but the same seed always gives the same theme.

**Optional AI helper:**
- Turns the free-text description into the inputs above (mood, hue range, tags), and suggests names in each language.
- Its output is only **suggestions in the form**. It never publishes, never writes colour values directly, and everything passes the same checks.

### 5.3 Contrast and accessibility maths

Use the WCAG 2 relative luminance and contrast ratio (the same maths as in the prototype's accent picker).

### 5.4 Exact preview with Flutter web

- **Shared package:** move `lib/scenes/`, `lib/icons/themed_icon_painter.dart` and the theme models into a shared Dart package, e.g. `packages/wallp_render/`, used by both the app and a small Flutter web app called **preview**.
- **Embedding:** the dashboard embeds the preview in an `<iframe>` and sends it the theme JSON with `postMessage`. The preview draws the same lock screen, home grid and live scene as the phone.
- **Preview images:** the same preview app renders the theme's thumbnail on save, using the same painters.

This keeps the dashboard and the phone visually identical without writing the painters twice.

### 5.5 Suggested tech stack

| Part | Suggestion | Why |
|---|---|---|
| Dashboard UI | Next.js (React) + TypeScript | Forms, tables and file uploads are quick to build |
| Preview | Flutter web app (`preview`) in an iframe | Reuses the app's painters exactly |
| Database + login + files | Supabase (Postgres, Auth, Storage), or Firebase | Matches the API doc's hosting options |
| Publish and schedule jobs | Supabase Edge Functions / Cloud Functions | Small, timed tasks |
| Image processing | `sharp` (WebP sizes), `blurhash` | Standard, fast |
| Font processing | `fonttools` (subsetting, script detection) in a small job | Reliable font handling |
| Schema validation | JSON Schema with `ajv` | Same schema files the app uses for tests |

---

## 6. Checks before publishing

**Errors block publishing; warnings need a confirmation.**

| Check | Level |
|---|---|
| JSON matches the schema | Error |
| Theme engine exists in `engines.json`; `minAppVersion` is at least the engine's version | Error |
| Clock and text colour vs background and every variant's background: contrast ≥ 4.5:1 | Error |
| Every accent colour (each gradient stop) vs background: ≥ 3:1 (large text and icons) | Error |
| textMuted vs background: ≥ 4.5:1 | Warning |
| Festival look: muted text vs background ≥ 4.5:1, brand colour vs background ≥ 3:1 | Error |
| Fonts have a licence that allows redistribution | Error |
| Myanmar text in names or subtitles, but the fonts have no Myanmar letters and no fallback | Error |
| Every referenced asset exists and its sha256 matches | Error |
| A single asset is over 1 MB | Warning |
| A single asset is over 10 MB (the app rejects it) | Error |
| Catalog over 1 MB | Warning; over 2 MB is an error |
| Festival has fewer than 2 future dates | Warning |
| Banner points to a missing or unpublished festival or theme | Error |
| Theme has no preview image | Warning |
| Theme ID was changed after it was published | Error (IDs are permanent) |

---

## 7. Admin API (used by the dashboard only)

Base URL: `https://api.<your-domain>/admin/v1`. Every request needs the login token (`Authorization: Bearer …`); the role decides what's allowed.

| Method | Path | Purpose |
|---|---|---|
| GET / POST | `/festivals` | List, create |
| GET / PATCH / DELETE | `/festivals/{id}` | Read, edit, archive |
| GET / POST | `/themes` | List (filters: festival, status, style, engine, q), create |
| GET / PATCH | `/themes/{id}` | Read, edit draft |
| POST | `/themes/{id}/duplicate` | Copy as a new draft |
| POST | `/themes/generate` | Body: generator inputs + seed → returns 6 draft options (not saved until chosen) |
| POST | `/themes/{id}/review` | Request review / approve / reject (`{ "action": "approve" }`) |
| POST | `/themes/{id}/schedule` | `{ "at": "2026-11-15T00:00:00Z" }` |
| GET / POST / PATCH | `/wallpapers`, `/fonts`, `/banners` | Same pattern as themes |
| POST | `/assets` | Upload (multipart) → `{ sha256, url, bytes, mime }`. Images also return WebP sizes and blurhash. |
| POST | `/fonts/import` | `{ "googleFamily": "Creepster" }` → font record with files and licence |
| POST | `/releases/check` | Runs every check in section 6 → `{ errors: [], warnings: [] }` |
| POST | `/releases` | Publish now → new release |
| POST | `/releases/{version}/rollback` | Make an older release current |
| GET | `/releases` | History |
| GET | `/engines` | The engines list |
| GET | `/audit?itemType=&itemId=` | Audit log |
| GET | `/stats/themes?from=&to=` | Applies and favourites |

**Errors** use one format: `{ "error": { "code": "contrast_too_low", "message": "Clock colour on Blood moon background is 2.8:1, needs 4.5:1", "field": "variants[1].palette.background" } }`. The `field` lets the form highlight the exact input.

---

## 8. Testing new themes on a real phone

- **Test build:** a debug or staging build of wallp reads a **staging catalog** (`/catalog-staging/v1/`) instead of the live one.
- **Staging publish:** the dashboard can publish to staging at any time, without review.
- **"Send to my phone":** the QR code opens a link like `wallp://preview?theme=<id>&rev=<draftRev>`. The test build downloads that draft from staging and opens it, so designers can check the real lock screen, wallp Home, live wallpaper and fonts before review.
- **Live builds never read staging.**

---

## 9. Build plan

| Phase | Work | Done when |
|---|---|---|
| **1. Foundations** | Shared JSON Schema; database tables; login and roles; Festivals and Themes editors for the 3 existing engines; JSON export/import | Today's three themes are re-created in the dashboard and export identical JSON to the app's built-in catalog |
| **2. Preview** | `wallp_render` shared package; Flutter web preview in the editor; auto preview images | The editor preview matches a phone screenshot of the same theme |
| **3. Publish** | Checks; release, staging, rollback; Fonts and Wallpapers libraries; Banners | A theme published from the dashboard appears in the app without an update; rollback works |
| **4. Generator** | Palette and font generator, wizard, Shuffle; optional AI text helper | A designer makes a passing Christmas theme in under 5 minutes |
| **5. Layers engine** | Layer editor for the `layers` engine (needs the app's `layers` engine, API doc phase 5) | A new scene made only in the dashboard |
| **6. Statistics** | Events API data, popularity in publishes | The "Popular" sort in the app uses real data |

---

## 10. Checklist before the first public launch

- [ ] App Bundle published; size checked in Play Console
- [ ] Schema files shared by the app tests and the dashboard
- [ ] Built-in catalog in the app matches the dashboard export
- [ ] Applied theme works offline in wallp Home and the live wallpaper (snapshot)
- [ ] Staging catalog and test build working; QR preview tested
- [ ] All checks in section 6 enabled
- [ ] Rollback tested on staging
- [ ] Font licences recorded for every font
- [ ] Privacy policy mentions the Events API (if used)
- [ ] Two admins with 2-step verification
