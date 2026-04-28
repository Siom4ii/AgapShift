## AgapShift QA + Metrics + Release Checklist (MVP)

### 9.1 Instrumentation plan (success metrics)

**Event naming**: `agapshift_<domain>_<action>`

#### Marketplace / Hiring
- `agapshift_gig_posted`
  - props: `gigId`, `businessId`, `category`, `payAmount`, `startAt`
- `agapshift_gig_applied`
  - props: `gigId`, `workerId`
- `agapshift_gig_hired`
  - props: `gigId`, `businessId`, `workerId`
  - derived metric: **time-to-hire** = `hiredAt - postedAt`
- `agapshift_gig_cancelled`
  - props: `gigId`, `reason` (optional)

#### Verification
- `agapshift_verification_submitted`
  - props: `userId`, `role`
- `agapshift_verification_decided` (when admin web exists)
  - props: `userId`, `role`, `decision`
  - derived metric: **verification throughput** = `decidedAt - submittedAt`

#### Shift / Attendance
- `agapshift_shift_checkin`
  - props: `gigId`, `workerId`
- `agapshift_shift_checkout`
  - props: `gigId`, `workerId`
  - derived metric: **completion rate** (check-in + check-out)
- `agapshift_attendance_invalid_scan`
  - props: `gigId`, `workerId`, `reason` (expired/wrong gig/duplicate)

#### Payments
- `agapshift_escrow_funded`
  - props: `gigId`, `businessId`, `amount`
- `agapshift_escrow_released`
  - props: `gigId`, `workerId`, `amount`
  - derived metric: **payment success** = released / funded
- `agapshift_withdrawal_requested`
  - props: `userId`, `amount`

#### Trust / Ratings
- `agapshift_rating_submitted`
  - props: `gigId`, `raterUserId`, `ratedUserId`, `stars`

### 9.2 Permissions + privacy checklist

- Camera permission:
  - Required for QR scanning and selfie/KYC capture.
  - Android: `android.permission.CAMERA` added (placeholder).
- Location permission:
  - Required for nearby gigs and distance filtering.
  - Android: `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` added (placeholder).
- KYC storage:
  - Ensure uploads go to private storage (signed URLs) once backend exists.
  - Never log raw KYC media paths or tokens.
- Secrets:
  - Replace any dev secrets (e.g., QR token signing secret) before production.

### 9.3 Edge cases to validate

- Auth / onboarding:
  - First launch → role selection persists.
  - OTP resend cooldown UX.
  - Pending verification blocks marketplace actions until verified.
- Marketplace:
  - Applying twice → prevented.
  - Hiring without escrow funded → blocked.
  - Cancelled gig is not listed for workers (open-only in nearby list).
- Attendance:
  - Wrong gig QR token → rejected.
  - Expired token → rejected.
  - Double check-in/check-out → rejected.
- Payments:
  - Release escrow without funded escrow → blocked.
  - Withdrawal more than available → blocked.

### 9.4 Test commands (local)

- `flutter test`

### 9.5 MVP release checklist

- Branding:
  - Update app label from `nexora` to `AgapShift` (Android + Flutter `MaterialApp` already uses `AgapShift` title).
  - Update app icons (Android/iOS/web) if needed.
- Build config:
  - Confirm package name / bundle id.
  - Confirm minSdk/targetSdk and signing config for Android.
- Runtime permissions:
  - Add user-facing permission prompts + fallbacks for denied location/camera.
- Environment:
  - Prepare `dev/staging/prod` config strategy (API base URLs, keys).
- Security:
  - Replace mock secrets + enforce secure storage patterns.
  - Add basic logging redaction for PII.

