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

## Git: pull the latest code

From your project folder (after you have cloned once):

```bash
cd AgapShift
git fetch origin
git checkout feature/agapshift-mvp
git pull origin feature/agapshift-mvp
flutter pub get
```

- Replace `feature/agapshift-mvp` with whatever branch you use (e.g. `main` once you merge).
- If you only care about the current branch and it already tracks `origin`:

```bash
git pull
flutter pub get
```

## Git: push your changes to GitHub

1. **Configure the remote** (only needed once per clone; skip if `git remote -v` already shows your repo):

   ```bash
   git remote add origin https://github.com/Siom4ii/AgapShift.git
   ```

2. **Create or switch to a branch** (example: feature branch):

   ```bash
   git checkout -b feature/agapshift-mvp
   ```

3. **Stage, commit, and push**:

   ```bash
   git status
   git add -A
   git commit -m "Describe your change in one line"
   git push -u origin feature/agapshift-mvp
   ```

   The first push uses `-u` so later you can run just `git push`.

4. **Authentication**: GitHub no longer accepts account passwords for Git over HTTPS. Use one of:
   - [Personal Access Token (classic)](https://github.com/settings/tokens) as the password when Git asks, or  
   - [GitHub CLI](https://cli.github.com/) (`gh auth login`), or  
   - SSH remotes (`git@github.com:Siom4ii/AgapShift.git`) with an SSH key added to your GitHub account.

## Admin web (staff KYC / account review)

Staff use a **separate Vite app** in `admin-web/`. It uses the **same Supabase project** as the Flutter app. Mobile logins with `profiles.role = 'admin'` are blocked; use a **dedicated staff email** in Auth and set that profile’s role to `admin`.

### 1. Apply Supabase migrations

From the repo root, push or run SQL in order (at least through admin/KYC):

- `supabase/migrations/020_admin_portal.sql` — admin role, RLS, `admin_set_account_review`, storage policies  
- `supabase/migrations/021_kyc_per_document_review.sql` — per-document KYC review + `admin_set_kyc_document_review`  
- `supabase/migrations/022_admin_kyc_review_rpc_fix.sql` — RPC signature fix (if PostgREST could not see the function)

Use the Supabase CLI (`supabase db push`) or paste each file in the SQL editor on the hosted project.

### 2. Create a staff admin user

1. In **Supabase → Authentication**, create a user (staff email + password).  
2. Ensure a row exists in `public.profiles` for that user’s `id` (same as in the mobile app flow).  
3. Set the role:

   ```sql
   update public.profiles
   set role = 'admin'
   where id = '<auth_user_uuid>';
   ```

### 3. Run the admin UI locally

```bash
cd admin-web
cp .env.example .env
# Edit .env: VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
# (same values as Flutter’s assets/supabase.env or Dashboard → Settings → API)
npm install
npm run dev
```

Open **http://localhost:5174** (port is set in `admin-web/vite.config.ts`). Sign in with the staff account.

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
| `admin-web/` | Staff portal (Vite): KYC / account review |
| `supabase/migrations/` | Postgres schema, RLS, RPCs for Supabase |

## Demo notes

- **Verification**: After onboarding you may see a pending state; use **“Demo: Mark as Verified”** when shown, or use the **admin web** above if your project is wired to Supabase with migrations applied.
- **Logout**: From Worker/Business dashboards, open the **menu (⋮)** → **Logout** to return to the start.

## License

Private / not published to pub.dev (see `pubspec.yaml`).
