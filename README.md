# AgapShift (Nexora)

**AgapShift** is a location-based gig marketplace (Flutter app) that connects businesses needing on-site workers with nearby individuals for short-term shifts. This repository contains the **MVP client** with mocked local services (auth, gigs, escrow, QR attendance, wallet, ratings). Product docs live under [`tasks/`](tasks/).

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel), **3.24+** recommended  
  - Verify: `flutter doctor`
- **Chrome** or **Edge** (for web)
- **Android Studio** (optional, for Android device/emulator)

On **Windows**, if `flutter pub get` warns about **symlink support**, enable **Developer Mode** (Settings → Privacy & security → For developers) so plugins can build correctly.

## Clone and install

```bash
git clone https://github.com/Siom4ii/AgapShift.git
cd AgapShift
flutter pub get
```

## Run the app

### Web (quick preview)

```bash
flutter run -d chrome
```

Or pick a fixed port:

```bash
flutter run -d chrome --web-port=52123
```

Then open the URL shown in the terminal (e.g. `http://localhost:52123`).

### Android

Connect a device or start an emulator, then:

```bash
flutter devices
flutter run -d android
```

### Windows desktop

```bash
flutter run -d windows
```

## Tests

```bash
flutter test
```

## Project layout (high level)

| Path | Purpose |
|------|---------|
| `lib/main.dart` | App entry, theme, session + marketplace scope |
| `lib/app/` | Auth, onboarding, marketplace, payments, shift/QR, UI screens |
| `lib/domain/` | Shared enums/models |
| `tasks/prd-agapshift.md` | Product requirements |
| `tasks/tasks-agapshift.md` | Implementation task checklist |
| `tasks/api-contracts-agapshift.md` | Draft API contracts for future backend |

## Demo notes

- **Verification**: After onboarding you may see a pending state; use **“Demo: Mark as Verified”** when shown (real admin will be a separate web app).
- **Logout**: From Worker/Business dashboards, open the **menu (⋮)** → **Logout** to return to the start.

## License

Private / not published to pub.dev (see `pubspec.yaml`).
