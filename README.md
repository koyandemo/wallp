# wallp

Festival themes, wallpapers, icon packs and clock fonts for Android, with
wallp Home as the launcher.

## Backend

The app talks to the wallp backend (catalog, events, optional accounts;
see [docs/app-api.md](docs/app-api.md)). Its address comes from an env file:

| Env file | `API_BASE_URL` | Use |
|---|---|---|
| `env/prod.json` | `https://wallp-api.justym.me` | production (also the default with no env file) |
| `env/local.json` | `http://10.0.2.2:8080` | `make run && make seed` in `wallp-platform/backend`, Android emulator |

```sh
flutter run --dart-define-from-file=env/prod.json
flutter run --dart-define-from-file=env/local.json
flutter build apk --release --dart-define-from-file=env/prod.json
```

VS Code has both as launch configurations. Debug builds can switch to the
bundled mock catalog in Me → Developer.
