## Relevant Files

- `tasks/prd-agapshift.md` - Source PRD for all requirements and scope decisions.
- `pubspec.yaml` - Flutter dependencies (auth, maps, storage, state mgmt, networking).
- `lib/main.dart` - App bootstrap, routing, theme, and initial screen selection.
- `lib/**` - Flutter app source (features, models, services, UI).
- `test/**` - Widget/unit tests.
- `android/app/src/main/AndroidManifest.xml` - Location/camera permissions (maps, KYC, QR scanning).
- `android/app/build.gradle.kts` - Android plugin config (e.g., Google services if Firebase is added).
- `android/build.gradle.kts` - Project-level Android config.
- `android/settings.gradle.kts` - Android module wiring.
- `backend/**` (if you add one) - API, database, payments, QR/attendance, admin endpoints (optional).
- `admin/**` (if you add one) - Admin verification UI (optional).

### Notes

- This task list is **MVP-oriented** and follows the PRD assumptions: **Android-first (PH)**, **business reviews applicants**, **escrow**, **full KYC + manual admin approval**.
- This repo is a **Flutter** app; tasks below assume implementation primarily in `lib/`.
- OTP email, escrow, and liveness/KYC usually require backend + providers; for MVP you can build UI/flows + stub services first, then integrate once providers are chosen.

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`.

## Tasks

- [x] 0.0 Create feature branch
- [x] 0.1 Fetch latest default branch
- [x] 0.2 Create and checkout branch (e.g., `feature/agapshift-mvp`)
  - [x] 0.3 Push branch to origin (if using remote)

- [x] 1.0 Define domain model + API contracts (users, verification, gigs, applications, shift, escrow, wallet)
  - [x] 1.1 Confirm MVP architecture: “Flutter app + mocked services” vs “Flutter app + backend now”
  - [x] 1.2 Define core entities + fields (Worker, Business, Gig, Application, ShiftSession, Attendance, Wallet, Transaction, Rating, Notification)
  - [x] 1.3 Define enums/statuses (AccountStatus, GigStatus, ApplicationStatus, PayoutStatus, VerificationStatus)
  - [x] 1.4 Draft API contracts (request/response) for:
    - [x] 1.4.1 Email OTP send/verify
    - [x] 1.4.2 Create/update profile + upload KYC docs + liveness result
    - [x] 1.4.3 Admin approve/reject verification
    - [x] 1.4.4 Create gig, list gigs nearby, get gig details
    - [x] 1.4.5 Apply to gig, list applicants, hire worker
    - [x] 1.4.6 Escrow fund/release/refund events + ledger
    - [x] 1.4.7 Shift start/end + attendance record
    - [x] 1.4.8 Wallet balance + withdraw + payout status
    - [x] 1.4.9 Ratings create/list
    - [x] 1.4.10 Notifications list/mark-read + push payloads
  - [x] 1.5 Define location matching approach (radius filtering, sorting, pagination)
  - [x] 1.6 Define privacy rules: which profile fields are visible to Workers vs Businesses

- [x] 2.0 Implement role-based first launch + authentication (email OTP) + session handling
  - [x] 2.1 Add app routing structure (auth/onboarding vs dashboards)
  - [x] 2.2 Implement Getting Started screen + role selection (persist role locally)
  - [x] 2.3 Implement email OTP UI (enter email → enter OTP + resend timer)
  - [x] 2.4 Implement session state (logged out / onboarding / pending verification / verified)
  - [x] 2.5 Implement role-based dashboard shell (Worker vs Business navigation)
  - [x] 2.6 Add basic error states (invalid OTP, network errors, rate limits)
  - [x] 2.7 Add tests for routing/session transitions

- [x] 3.0 Build onboarding + verification flows (Worker + Business) with pending/verified gating
  - [x] 3.1 Worker onboarding screens:
    - [x] 3.1.1 Personal info (name, birthdate, contact, address, emergency contact)
    - [x] 3.1.2 Resume/profile (skills multi-select, experience, bio, education)
    - [x] 3.1.3 Payout setup (GCash/Maya/bank form)
    - [x] 3.1.4 KYC upload (government ID) + selfie capture (liveness placeholder)
  - [x] 3.2 Business onboarding screens:
    - [x] 3.2.1 Business type selection
    - [x] 3.2.2 Document upload (permits/certificates/IDs)
    - [x] 3.2.3 Location pin setup (map picker + manual fallback)
    - [x] 3.2.4 Payment setup (GCash/Maya/bank)
  - [x] 3.3 Account status screens (Pending / Rejected w/ reason + resubmit / Verified badge)
  - [x] 3.4 Enforce gating: Worker cannot apply; Business cannot post/hire unless Verified
  - [x] 3.5 Add upload handling (pick, progress, retry) and storage notes
  - [x] 3.6 Add tests for gating and onboarding completion

- [x] 4.0 Build marketplace discovery + gig lifecycle (post, apply, review applicants, hire, status transitions)
  - [x] 4.1 Worker: nearby gigs feed (list, distance, empty states, filters, gig details)
  - [x] 4.2 Worker: apply flow + application status UI
  - [x] 4.3 Business: create gig form + manage gigs list (Open/Filled/Ongoing/Completed/Cancelled)
  - [x] 4.4 Business: applicant list + hire action
  - [x] 4.5 Enforce status transitions and cancellation rules (MVP)
  - [x] 4.6 Add notifications for application/hire/status changes (in-app inbox minimum)
  - [x] 4.7 Add tests for gig CRUD + apply/hire flows

- [x] 5.0 Implement shift session + QR attendance (generate, scan, validate, record)
  - [x] 5.1 Worker: Active Shift UI (status + timer)
  - [x] 5.2 Business: generate Check-in and Check-out QR (time-bound token)
  - [x] 5.3 Worker: QR scanner UI (camera permission + scan UX)
  - [x] 5.4 Validate QR rules (match gig/shift, expiry, prevent double check-in/out)
  - [x] 5.5 Attendance record views for Worker and Business
  - [x] 5.6 Add tests for QR payload validation (pure Dart) + basic widget tests

- [x] 6.0 Implement escrow ledger + wallet + payouts (GCash/Maya/bank placeholders if provider not integrated)
  - [x] 6.1 Define escrow states + ledger events (funded/held/released/refunded)
  - [x] 6.2 Business: “Fund escrow” UI (mock/provider placeholder)
  - [x] 6.3 Block hire confirmation until escrow funded (per PRD)
  - [x] 6.4 On completion, release funds to Worker wallet (available vs pending)
  - [x] 6.5 Wallet screens (balances + transaction list)
  - [x] 6.6 Withdrawal flow (request → processing → paid/failed)
  - [x] 6.7 Add tests for ledger invariants (idempotency, no negative balances)

- [x] 7.0 Add profiles + ratings + notifications (push + in-app inbox)
  - [x] 7.1 Worker profile page (resume, rating, completed shifts, verified badge)
  - [x] 7.2 Business profile page (details, rating, hiring stats, verified badge)
  - [x] 7.3 Ratings flow (post-shift only, one rating per shift)
  - [x] 7.4 In-app notifications inbox (list + mark read)
  - [x] 7.5 Push notifications scaffold (optional MVP): FCM setup + payload mapping
  - [x] 7.6 Add tests for rating eligibility + notification read/unread behavior

- [ ] 8.0 Build/admin enable verification operations + audit logs (admin web optional) **(deferred: web admin later)**
  - [ ] 8.1 Choose admin approach for MVP (admin web vs internal tool) **(deferred)**
  - [ ] 8.2 Implement verification decision actions (approve/reject + reason) **(deferred)**
  - [ ] 8.3 Implement audit logs for admin actions **(deferred)**
  - [ ] 8.4 Add “suspend user” (optional) and enforce app gating **(deferred)**
  - [ ] 8.5 If admin web: pending queues + detail view + action buttons **(deferred)**
  - [ ] 8.6 Add tests for verification decision effects (status + notifications) **(deferred)**

- [x] 9.0 QA pass: analytics/success metrics hooks, edge cases, security review, and release checklist
  - [x] 9.1 Add instrumentation plan for PRD metrics (time-to-hire, completion, no-show, payment success)
  - [x] 9.2 Verify permissions + privacy (location/camera/KYC storage)
  - [x] 9.3 Validate key edge cases (location denied, pending gating, cancellations + escrow consistency)
  - [x] 9.4 Run tests and fix failures
  - [x] 9.5 Prepare MVP release checklist (branding, icons, build config, env configs)

