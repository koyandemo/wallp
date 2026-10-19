# wallp

A new Flutter project.

## Environments

Which backend the app talks to comes from an env file under `env/`
(see `lib/core/api_config.dart`):

| File | Server |
|---|---|
| `env/prod.json` | `https://wallp-api.justym.me` (also the default with no env file) |
| `env/local.json` | the backend on this Mac (`make run` in `backend/`), as `10.0.2.2:8080` from the Android emulator |

In debug builds, Developer settings' pretend network (slow, flaky, offline)
sits in front of whichever server you pick.

```sh
flutter run --dart-define-from-file=env/prod.json
```

In VS Code, pick the matching entry in Run and Debug (`.vscode/launch.json`).
On a real phone with the local backend, set `WALLP_API_BASE` to your Mac's LAN
IP and add that IP to `android/app/src/debug/res/xml/network_security_config.xml`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
