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

- [ ] 0.0 Create feature branch
- [x] 0.1 Fetch latest default branch
- [x] 0.2 Create and checkout branch (e.g., `feature/agapshift-mvp`)
- [ ] 0.3 Push branch to origin (if using remote)

- [ ] 1.0 Define domain model + API contracts (users, verification, gigs, applications, shift, escrow, wallet)
  - [ ] 1.1 Confirm MVP architecture: “Flutter app + mocked services” vs “Flutter app + backend now”
  - [ ] 1.2 Define core entities + fields (Worker, Business, Gig, Application, ShiftSession, Attendance, Wallet, Transaction, Rating, Notification)
  - [ ] 1.3 Define enums/statuses (AccountStatus, GigStatus, ApplicationStatus, PayoutStatus, VerificationStatus)
  - [ ] 1.4 Draft API contracts (request/response) for:
    - [ ] 1.4.1 Email OTP send/verify
    - [ ] 1.4.2 Create/update profile + upload KYC docs + liveness result
    - [ ] 1.4.3 Admin approve/reject verification
    - [ ] 1.4.4 Create gig, list gigs nearby, get gig details
    - [ ] 1.4.5 Apply to gig, list applicants, hire worker
    - [ ] 1.4.6 Escrow fund/release/refund events + ledger
    - [ ] 1.4.7 Shift start/end + attendance record
    - [ ] 1.4.8 Wallet balance + withdraw + payout status
    - [ ] 1.4.9 Ratings create/list
    - [ ] 1.4.10 Notifications list/mark-read + push payloads
  - [ ] 1.5 Define location matching approach (radius filtering, sorting, pagination)
  - [ ] 1.6 Define privacy rules: which profile fields are visible to Workers vs Businesses

- [ ] 2.0 Implement role-based first launch + authentication (email OTP) + session handling
  - [ ] 2.1 Add app routing structure (auth/onboarding vs dashboards)
  - [ ] 2.2 Implement Getting Started screen + role selection (persist role locally)
  - [ ] 2.3 Implement email OTP UI (enter email → enter OTP + resend timer)
  - [ ] 2.4 Implement session state (logged out / onboarding / pending verification / verified)
  - [ ] 2.5 Implement role-based dashboard shell (Worker vs Business navigation)
  - [ ] 2.6 Add basic error states (invalid OTP, network errors, rate limits)
  - [ ] 2.7 Add tests for routing/session transitions

- [ ] 3.0 Build onboarding + verification flows (Worker + Business) with pending/verified gating
  - [ ] 3.1 Worker onboarding screens:
    - [ ] 3.1.1 Personal info (name, birthdate, contact, address, emergency contact)
    - [ ] 3.1.2 Resume/profile (skills multi-select, experience, bio, education)
    - [ ] 3.1.3 Payout setup (GCash/Maya/bank form)
    - [ ] 3.1.4 KYC upload (government ID) + selfie capture (liveness placeholder)
  - [ ] 3.2 Business onboarding screens:
    - [ ] 3.2.1 Business type selection
    - [ ] 3.2.2 Document upload (permits/certificates/IDs)
    - [ ] 3.2.3 Location pin setup (map picker + manual fallback)
    - [ ] 3.2.4 Payment setup (GCash/Maya/bank)
  - [ ] 3.3 Account status screens (Pending / Rejected w/ reason + resubmit / Verified badge)
  - [ ] 3.4 Enforce gating: Worker cannot apply; Business cannot post/hire unless Verified
  - [ ] 3.5 Add upload handling (pick, progress, retry) and storage notes
  - [ ] 3.6 Add tests for gating and onboarding completion

- [ ] 4.0 Build marketplace discovery + gig lifecycle (post, apply, review applicants, hire, status transitions)
  - [ ] 4.1 Worker: nearby gigs feed (list, distance, empty states, filters, gig details)
  - [ ] 4.2 Worker: apply flow + application status UI
  - [ ] 4.3 Business: create gig form + manage gigs list (Open/Filled/Ongoing/Completed/Cancelled)
  - [ ] 4.4 Business: applicant list + hire action
  - [ ] 4.5 Enforce status transitions and cancellation rules (MVP)
  - [ ] 4.6 Add notifications for application/hire/status changes (in-app inbox minimum)
  - [ ] 4.7 Add tests for gig CRUD + apply/hire flows

- [ ] 5.0 Implement shift session + QR attendance (generate, scan, validate, record)
  - [ ] 5.1 Worker: Active Shift UI (status + timer)
  - [ ] 5.2 Business: generate Check-in and Check-out QR (time-bound token)
  - [ ] 5.3 Worker: QR scanner UI (camera permission + scan UX)
  - [ ] 5.4 Validate QR rules (match gig/shift, expiry, prevent double check-in/out)
  - [ ] 5.5 Attendance record views for Worker and Business
  - [ ] 5.6 Add tests for QR payload validation (pure Dart) + basic widget tests

- [ ] 6.0 Implement escrow ledger + wallet + payouts (GCash/Maya/bank placeholders if provider not integrated)
  - [ ] 6.1 Define escrow states + ledger events (funded/held/released/refunded)
  - [ ] 6.2 Business: “Fund escrow” UI (mock/provider placeholder)
  - [ ] 6.3 Block hire confirmation until escrow funded (per PRD)
  - [ ] 6.4 On completion, release funds to Worker wallet (available vs pending)
  - [ ] 6.5 Wallet screens (balances + transaction list)
  - [ ] 6.6 Withdrawal flow (request → processing → paid/failed)
  - [ ] 6.7 Add tests for ledger invariants (idempotency, no negative balances)

- [ ] 7.0 Add profiles + ratings + notifications (push + in-app inbox)
  - [ ] 7.1 Worker profile page (resume, rating, completed shifts, verified badge)
  - [ ] 7.2 Business profile page (details, rating, hiring stats, verified badge)
  - [ ] 7.3 Ratings flow (post-shift only, one rating per shift)
  - [ ] 7.4 In-app notifications inbox (list + mark read)
  - [ ] 7.5 Push notifications scaffold (optional MVP): FCM setup + payload mapping
  - [ ] 7.6 Add tests for rating eligibility + notification read/unread behavior

- [ ] 8.0 Build/admin enable verification operations + audit logs (admin web optional)
  - [ ] 8.1 Choose admin approach for MVP (admin web vs internal tool)
  - [ ] 8.2 Implement verification decision actions (approve/reject + reason)
  - [ ] 8.3 Implement audit logs for admin actions
  - [ ] 8.4 Add “suspend user” (optional) and enforce app gating
  - [ ] 8.5 If admin web: pending queues + detail view + action buttons
  - [ ] 8.6 Add tests for verification decision effects (status + notifications)

- [ ] 9.0 QA pass: analytics/success metrics hooks, edge cases, security review, and release checklist
  - [ ] 9.1 Add instrumentation plan for PRD metrics (time-to-hire, completion, no-show, payment success)
  - [ ] 9.2 Verify permissions + privacy (location/camera/KYC storage)
  - [ ] 9.3 Validate key edge cases (location denied, pending gating, cancellations + escrow consistency)
  - [ ] 9.4 Run tests and fix failures
  - [ ] 9.5 Prepare MVP release checklist (branding, icons, build config, env configs)

