# wallp API binding: plan

How the app moves from the bundled mock catalog to the real backend described in [app-client.md](app-client.md): the public catalog, optional accounts with synced favourites, and anonymous events.

**Status (18 Oct 2026): Phase 1 (env files, Android/iOS network config) and Phase 2 (`HttpCatalogSource`) done, except the manifest ETag and the in-app server switch: the server is picked per build with `env/*.json`. The app reads the catalog from `https://wallp-api.justym.me` by default. Phase 4 (`ApiClient`, `ApiException`, the `ApiAuth` hook for Phase 5) done. Phase 5 (accounts: `AuthSession`, `AccountService`, secure token storage, Sign in / Account screens in Me) done; `AccountController` became `AccountService` (stateless `/v1/me` calls) next to the stateful `AuthSession`. Phase 6 (favourites sync) done, with a three-way merge against the last synced list instead of the dirty flag, so un-hearts on another phone carry over. Phase 7 (install id, install link, event queue and its hooks) done; refused batches are dropped rather than halved, and wallp Home queues its own `theme_applied` (duplicates are dropped in the queue). Phase 8 done: the mock catalog is out of the APK (tests read it from disk), the `mock` env is gone, and Developer settings' pretend network now sits in front of the real server. Phase 3 done: `CatalogPoller` checks every 5 minutes while the store is visible (stops when hidden, checks on return if stale) and `UpdateBanner` on the store home says when a newer app is needed. Left: the manifest ETag (optional) and the privacy policy line.**

Related: [app-client.md](app-client.md) (the backend contract), [theme-api.md](theme-api.md) (the JSON format), [store-redesign-plan.md](store-redesign-plan.md) §11 (this is its first "What's next" item), [how-the-app-works.md](how-the-app-works.md).

---

## 1. What already exists

The store redesign built the catalog side so that only the source changes. Already done and reused as is:

| Piece | File | Covers app-client.md |
|---|---|---|
| `CatalogSource` interface, `FetchFailure`, `CatalogFetchException` | [catalog_source.dart](../lib/data/catalog/catalog_source.dart) | the seam for HTTP |
| Cache-first start, built-in fallback, manifest → catalog, sha256 + `catalogVersion` check, catalog saved before manifest, unknown `schemaVersion`, `minAppVersion`, theme `id`/`rev` check, size limits, single-flight refresh | [catalog_repository.dart](../lib/data/catalog/catalog_repository.dart) | §2 steps 1, 3–7, 9, 10 |
| Asset download with progress, sha256 check, pins | [download_manager.dart](../lib/data/assets/download_manager.dart), [asset_cache.dart](../lib/data/assets/asset_cache.dart) | §2 step 8 |
| Local favourites (themes, wallpapers) | [user_store.dart](../lib/store/state/user_store.dart) | source of truth for §3 Favourites |
| App version + compare | [app_version.dart](../lib/core/app_version.dart) | `appVersion` for events and installs |

What's missing: an HTTP catalog source, ETag, the 5-minute manifest poll, everything under `/v1` (client, errors, auth, favourites sync, installs, events), and the Android/network config.

---

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| HTTP library | `package:http` (one `http.Client`, `send()` for streaming) | Small; streaming keeps download progress working; easy to fake with `MockClient` in tests. `dio` adds nothing we need |
| Secure storage | `flutter_secure_storage` for the refresh token only | Doc §3: Keychain / Keystore, never shared prefs or logs |
| Access token | Memory only | Doc §3 |
| `installId` | UUID v4 from `Random.secure()`, saved in shared prefs | Doc §4: random, not tied to the device. No `uuid` package needed for one function |
| Base URL | `--dart-define=WALLP_API_BASE=...`, default `https://wallp-api.justym.me` (catalog and `/v1` on one host, see §7); Developer settings can switch **Mock / Local server / Production** in debug builds | Emulator needs `http://10.0.2.2:8080`, a real phone needs the Mac's LAN IP |
| Mock catalog | Stays for tests and Developer settings; leaves the release APK in the last phase | Saves ~2.3 MB, keeps the offline test bench |
| Favourites sync | Local stays the truth. On sign-in: merge local + remote, then `PUT`. While signed in: each heart is a fire-and-forget `POST`/`DELETE` | Doc §3 Favourites |
| Event queue storage | One JSON list in shared prefs, capped at 500 events | Small, survives restarts; no database needed |
| State management | Same as today: `ChangeNotifier` + `provider` | Matches the app |

---

## 3. Architecture after binding

```
Screens
  │
  ├─► CatalogRepository (unchanged, plus a 5-min poll)
  │     └─► CatalogSource ─┬─ MockCatalogSource   (tests, Developer settings)
  │                        └─ HttpCatalogSource   NEW: GET /catalog/v1/<path>, streamed, ETag
  │
  ├─► DownloadManager ──► same CatalogSource ──► AssetCache   (unchanged)
  │
  ├─► AccountController   NEW  signed-out / signing-in / signed-in, user, sessions
  │     └─► AuthSession   NEW  access token (memory), refresh token (secure storage),
  │           │                single-flight refresh, sign-out on token_reused / token_expired
  │           └─► ApiClient NEW  /v1 JSON calls, Bearer, ApiException from the error shape
  │
  ├─► FavouritesSync      NEW  listens to UserStore; PUT on sign-in, POST/DELETE after
  │
  ├─► EventQueue          NEW  queue on device, flush on start / every few hours, Retry-After
  │
  └─► UserStore (unchanged API; favourites stay local-first)
```

New folder: `lib/data/api/` for `api_client.dart`, `api_exception.dart`, `api_config.dart`, `auth_session.dart`, `token_store.dart`, `install_id.dart`, `event_queue.dart`, `favourites_sync.dart`, `http_catalog_source.dart` (or the last one in `lib/data/catalog/` next to the mock; it implements `CatalogSource`).

---

## 4. Phases

Each phase ends with tests passing and the app still working fully offline and signed out.

### Phase 1: config and plumbing

- Add `http` and `flutter_secure_storage` to [pubspec.yaml](../pubspec.yaml).
- `ApiConfig`: `catalogBase` (`<base>/catalog/v1/`) and `apiBase` (`<base>/v1/`) from `--dart-define`; Developer settings override in debug.
- Android: `INTERNET` permission in the **main** manifest (today only the debug one has it). Cleartext `http://` allowed only in debug, through a debug-only `network_security_config.xml` for `10.0.2.2` and `localhost`.
- iOS: `NSAppTransportSecurity` exception for local hosts in debug only (if iOS is built at all; the app is Android-first).
- Developer settings: a **Server** row (Mock / Local / Production) next to Network.

### Phase 2: HTTP catalog source

`HttpCatalogSource extends CatalogSource`:

- `open(path)`: `CatalogSource.checkPath`, then `GET <catalogBase><path>` with `client.send()`, yielding the body stream so progress still works.
- Map failures to the existing `FetchFailure`:

  | Case | `FetchFailure` |
  |---|---|
  | `SocketException`, no route | `offline` |
  | connect / first-byte timeout | `timeout` |
  | 404 | `notFound` |
  | 5xx, dropped connection, other 4xx | `server` |
  | `Content-Length` over the limit | `tooLarge` (early, before reading) |

- **ETag for the manifest.** The ETag of a non-asset file is the quoted sha256 of its bytes, so no ETag needs saving: the repository already has the saved manifest bytes. Add an optional `ifNoneMatch` to the source (or a small `fetchManifest` hook in the repository) and treat `304` as "same as saved" → `RefreshOutcome.upToDate` without parsing. Catalog, theme and asset files never need ETag: they're immutable and cached by name.
- Headers: `Accept: application/json` for JSON, `User-Agent: wallp/<appVersion> (Android)`.
- Wire it in [app.dart](../lib/app.dart) in place of `MockCatalogSource`, chosen by `ApiConfig`.

### Phase 3: manifest poll

- In the store engine only: a `Timer.periodic(5 min)` that calls `CatalogRepository.refresh()` while the app is resumed; stop on pause, refresh once on resume if the last check is over 5 minutes old (`lastCheckedAt` already exists).
- Show the existing `updateRecommended` as a soft banner (already listed in store-redesign-plan.md §11).

### Phase 4: `/v1` client and errors

- `ApiException { int status; String code; String message; String? field; List<FieldError> details; Duration? retryAfter; }` parsed from `{"error": {...}}`. Branch on `code` + status only (doc §1).
- Non-JSON or network failures become `ApiException(code: 'offline' | 'timeout' | 'internal')` so callers have one type to catch.
- `ApiClient`: `get/post/patch/put/delete` with JSON bodies, optional `auth: true` that asks `AuthSession` for a token. On `401 token_expired` with auth: refresh once, retry once, then give up.
- An enum of known codes (`ApiErrorCode.validationFailed`, `badCredentials`, `tokenReused`, ...) with an `unknown` fallback.

### Phase 5: accounts

`TokenStore` (secure storage, key `wallp_refresh_token`) and `AuthSession`:

- `register`, `login` → save refresh token, keep access token + `expiresAt` in memory.
- `accessToken()`: returns the token, refreshing first if `expiresAt` is under 60 s away.
- `refresh()`: **single flight** (`_inFlight ??= ...`, like `CatalogRepository.refresh`). Save the new refresh token **before** anything else uses it (rotation).
- `401 token_reused` or `401 token_expired` on refresh → clear tokens, signed-out state, a quiet "You were signed out" snackbar. Network errors on refresh → keep the refresh token, stay "signed in, offline".
- `logout`: `POST /v1/auth/logout`, then delete local tokens whatever the result.

`AccountController` (ChangeNotifier) for the UI: `user`, `isSignedIn`, `updateDisplayName`, `changePassword` (signs out everywhere → log in again with the new password), `deleteAccount(password)`, `sessions()`, `revokeSession(id)` (sends `X-Refresh-Token` so the current one is marked).

UI in the **Me** tab ([me_screen.dart](../lib/store/screens/me_screen.dart)):

- Signed out: one "Sign in to sync favourites" card. Never blocks anything else.
- Sign in / Create account sheets. Show `field` errors under the field; `registration_failed` as one generic line; `rate_limited` as "Too many tries, wait a minute".
- Account page: name, email, change name, change password, sessions list with "This device", sign out, delete account (asks for the password).

Start-up (doc §6 step 3): if a refresh token is saved, refresh in the background after the catalog is on screen.

### Phase 6: favourites sync

`FavouritesSync` listens to `UserStore` and `AccountController`:

- After sign-in (and after each app start while signed in): `GET /v1/me/favourites`, union with local (local order first, then remote-only items), save locally, then `PUT` the merged list. This is what makes favourites follow the user to a new phone.
- While signed in: each heart → `POST /v1/me/favourites`; each un-heart (and Undo's restore) → `DELETE` / `POST`. Fire and forget; on failure mark "dirty" and do a full `PUT` on the next start.
- Item types map: theme → `theme`, wallpaper → `wallpaper`. `font` and `icon-pack` stay unused until the app has those favourites.
- Signing out never deletes local favourites.

Needs a small `UserStore` addition: `replaceFavourites(themes, wallpapers)` for the merge.

### Phase 7: install id, installs and events

- `InstallId.get()`: read or create the UUID (doc §6 step 2).
- After sign-in: `POST /v1/me/installs` with `installId` and `appVersion`; ignore `409 install_linked`.
- `EventQueue`:
  - `add(type, itemId)` stamps `at` with the real UTC time (not the Developer "pretend today" clock, or the server drops it).
  - Drops repeats of the same (type, item) still waiting in the queue, and events older than 7 days.
  - `flush()`: on start (doc §6 step 5), on app pause, and every 3 hours while open. Sends at most 100 events per request, no token (avoids the `401` trap in doc §4). Removes events only after `202`.
  - `429`: save `Retry-After` until-time in prefs and skip flushes until then. `413`/`422`: halve the batch and retry once, then drop that batch (it can never succeed). Network / 5xx: keep everything for next time.
- Hook points:

  | Event | Where |
  |---|---|
  | `theme_applied` | [apply_flow.dart:78](../lib/store/apply_flow.dart#L78), next to `recordApplied` |
  | `font_applied` | `ApplyFlow.applyFont` ([apply_flow.dart:114](../lib/store/apply_flow.dart#L114)) |
  | `icon_pack_applied` | `ApplyFlow.applyIconPack` ([apply_flow.dart:137](../lib/store/apply_flow.dart#L137)) |
  | `wallpaper_applied` | `ApplyFlow.applyWallpaper` ([apply_flow.dart:96](../lib/store/apply_flow.dart#L96)) |
  | `theme_favourited` / `theme_unfavourited` | `UserStore.toggleTheme` / `restoreTheme` callers, or a listener in `EventQueue` |

- Privacy policy line: "a random install ID, not linked to your device" (doc §4).

### Phase 8: release clean-up

- Remove `assets/mock/catalog/v1/` from the release APK (move to a `mock` flavor or test-only assets); keep `assets/builtin/`.
- Default server = Production in release; Developer settings hidden as today.
- Update [how-the-app-works.md](how-the-app-works.md) and mark store-redesign-plan.md §11 "HTTP catalog source" done.

---

## 5. Tests

Same style as `test/catalog/`: fakes, no real network.

| Area | Test |
|---|---|
| `HttpCatalogSource` | `MockClient`: 200 streams in chunks; 404 → `notFound`; 503 → `server`; socket error → `offline`; slow → `timeout`; big `Content-Length` → `tooLarge`; bad path never hits the network |
| ETag | Saved manifest sends `If-None-Match: "<sha256>"`; `304` → `upToDate` with no catalog download |
| Repository on HTTP | The existing `catalog_repository_test.dart` cases run once against a `MockClient` serving the seed files |
| `ApiException` | Parses `code`, `field`, `details`, `Retry-After`; non-JSON 502 → `internal` |
| `AuthSession` | Rotation saves the new token; two calls at once make one refresh; `token_reused` clears tokens; offline refresh keeps the token; early refresh before `expiresAt` |
| `ApiClient` | `401 token_expired` → one refresh, one retry, then error |
| `FavouritesSync` | Merge order; `PUT` after sign-in; dirty flag after a failed `POST`; sign-out keeps local |
| `EventQueue` | Dedupe; 7-day drop; batches of 100; kept on 5xx; removed on 202; `Retry-After` honoured across restarts; no `Authorization` header |
| Manual | `make run` + `make seed` in `backend/`, emulator on `10.0.2.2:8080`, airplane mode mid-download, server restart (random `JWT_SECRET` → signed out cleanly) |

---

## 6. Open questions

| Question | Default if nobody decides |
|---|---|
| ~~Production host name~~ | Settled: `https://wallp-api.justym.me` serves both (§7). A later CDN split is just two `ApiConfig` fields |
| ~~A pending apply finished by wallp Home is a separate engine: count it?~~ | Settled: wallp Home writes `theme_applied` into the shared queue; the store sends it. A second copy from the store's own finish is dropped as a duplicate |
| Email verification / password reset | Not in the backend; not in the app |
| Show "Sign in" anywhere other than Me? | No |

---

## 7. Live server check (18 Oct 2026)

`https://wallp-api.justym.me`, behind nginx, HTTPS with HSTS. Checked with read-only calls and two requests the server rejects without saving anything (no account made, no events stored).

| Check | Result |
|---|---|
| `GET /healthz` | `200 {"status":"ok","database":"pg"}` |
| `GET /catalog/v1/manifest.json` | `200`, `max-age=300`, strong ETag = quoted sha256 of the bytes |
| Same with `If-None-Match` | `304` (the Phase 2 ETag trick works) |
| Catalog `catalog.2026-10-18.3.json` | 45 KB, `immutable`, sha256 = `catalogSha256` |
| Content | 5 themes (`spider-night` is rev 5; the mock has rev 4), 6 wallpapers, 8 fonts, 5 icon packs, 6 banners, 5 festivals |
| App parsers on live JSON | `Catalog.fromJson`: 0 issues; all 5 `ThemeDetail.fromJson` OK, `id`/`rev` match |
| 13 assets referenced | all `200`, every sha256 matches its file name |
| Unknown catalog file | `404` |
| Asset with `Range` | `206`: resuming inside a file (store-redesign-plan §11) is possible |
| `/v1/me` with no token | `401 unauthorized` |
| `POST /v1/events` with a bad UUID | `422 validation_failed`, `field: installId` |
| `POST /v1/auth/login` with `{}` | `422 validation_failed`, `field: body`, two `details` |
| `/admin/v1/releases` | `401`: admin only, not used by the app |
| `/docs` | `404` (dev only, as app-client.md §7 says) |

Notes for the build:

- Error bodies have an extra `"$schema"` key next to `"error"`. `ApiException` parsing must ignore unknown keys.
- Missing required properties come back as `field: "body"`, not as the property name. The sign-in form should show those as a general error, not under a field.
- `catalogVersion` has no `-demo` suffix in production. Nothing depends on it.
- Production is HTTPS only, so the cleartext exception in Phase 1 is only for the local backend in debug builds.
