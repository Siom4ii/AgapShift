## AgapShift API Contracts (Draft for MVP)

### Notes
- This is a **draft contract** to guide backend/provider integration later.
- For MVP (until backend exists), the Flutter app can implement these as **mock services** with the same method signatures.
- IDs are strings (UUID/ULID) unless otherwise noted.
- Money is represented in **minor units** (PHP centavos) as `amount`.

## Common Types

### Money

```json
{ "amount": 150000, "currency": "PHP" }
```

### GeoPoint

```json
{ "lat": 14.5995, "lng": 120.9842 }
```

### AccountStatus
- `pending_verification`
- `verified`
- `rejected`
- `suspended`

### VerificationStatus
- `not_submitted`
- `pending`
- `approved`
- `rejected`

### GigStatus
- `open`
- `filled`
- `ongoing`
- `completed`
- `cancelled`

## 1) Auth (Email OTP)

### POST /auth/otp/send
Request:

```json
{ "email": "worker@example.com" }
```

Response:

```json
{ "otp_id": "otp_123", "cooldown_seconds": 60 }
```

### POST /auth/otp/verify
Request:

```json
{ "otp_id": "otp_123", "code": "123456", "role": "worker" }
```

Response:

```json
{
  "access_token": "jwt_or_session_token",
  "user": {
    "id": "usr_1",
    "email": "worker@example.com",
    "role": "worker",
    "account_status": "pending_verification"
  }
}
```

## 2) Worker Profile + KYC

### PUT /worker/profile
Request:

```json
{
  "full_name": "Juan Dela Cruz",
  "birthdate": "1999-01-31",
  "address": "Quezon City, NCR",
  "emergency_contact": { "name": "Maria", "phone": "+63..." },
  "skills": ["Waiter", "Cashier"],
  "bio": "Short bio",
  "education": "Optional text",
  "experience": "Optional text"
}
```

Response:

```json
{ "worker_profile": { "user_id": "usr_1", "verification_status": "not_submitted" } }
```

### POST /worker/kyc/id-document (multipart)
- Upload government ID images (front/back).
Response:

```json
{ "document_id": "doc_1", "verification_status": "pending" }
```

### POST /worker/kyc/liveness (multipart)
- Upload selfie video/image(s) OR provider reference.
Response:

```json
{ "liveness_id": "live_1", "verification_status": "pending" }
```

## 3) Business Profile + Verification

### PUT /business/profile
Request:

```json
{
  "business_name": "ABC Store",
  "business_type": "sole_proprietorship",
  "location": { "lat": 14.5995, "lng": 120.9842 },
  "address_label": "Manila, NCR"
}
```

Response:

```json
{ "business_profile": { "user_id": "biz_1", "verification_status": "not_submitted" } }
```

### POST /business/verification/documents (multipart)
- Upload permits/certificates/IDs.
Response:

```json
{ "verification_status": "pending" }
```

## 4) Admin Verification Decisions

### POST /admin/verify/worker
Request:

```json
{ "user_id": "usr_1", "decision": "approve", "reason": null }
```

Response:

```json
{ "user_id": "usr_1", "account_status": "verified" }
```

### POST /admin/verify/business
Request:

```json
{ "user_id": "biz_1", "decision": "reject", "reason": "Document mismatch" }
```

Response:

```json
{ "user_id": "biz_1", "account_status": "rejected" }
```

## 5) Gigs (Create, List Nearby, Details)

### POST /gigs
Request:

```json
{
  "title": "Kitchen Helper",
  "description": "Assist kitchen staff",
  "location": { "lat": 14.6, "lng": 121.0 },
  "address_label": "QC, NCR",
  "start_at": "2026-05-01T09:00:00Z",
  "end_at": "2026-05-01T17:00:00Z",
  "pay": { "amount": 80000, "currency": "PHP" },
  "category": "Food Service"
}
```

Response:

```json
{ "gig_id": "gig_1", "status": "open" }
```

### GET /gigs/nearby?lat=...&lng=...&radius_m=...&min_pay=...&category=...
Response:

```json
{
  "items": [
    {
      "id": "gig_1",
      "title": "Kitchen Helper",
      "location": { "lat": 14.6, "lng": 121.0 },
      "distance_m": 1200,
      "pay": { "amount": 80000, "currency": "PHP" },
      "status": "open"
    }
  ],
  "next_cursor": null
}
```

### GET /gigs/{gig_id}
Response:

```json
{
  "gig": {
    "id": "gig_1",
    "business_id": "biz_1",
    "title": "Kitchen Helper",
    "description": "Assist kitchen staff",
    "location": { "lat": 14.6, "lng": 121.0 },
    "address_label": "QC, NCR",
    "start_at": "2026-05-01T09:00:00Z",
    "end_at": "2026-05-01T17:00:00Z",
    "pay": { "amount": 80000, "currency": "PHP" },
    "category": "Food Service",
    "status": "open"
  }
}
```

## 6) Applications + Hiring

### POST /gigs/{gig_id}/apply
Response:

```json
{ "application_id": "app_1", "status": "applied" }
```

### GET /gigs/{gig_id}/applicants
Response:

```json
{ "items": [{ "application_id": "app_1", "worker_id": "usr_1", "status": "applied" }] }
```

### POST /gigs/{gig_id}/hire
Request:

```json
{ "application_id": "app_1" }
```

Response:

```json
{ "gig_id": "gig_1", "status": "filled", "worker_id": "usr_1" }
```

## 7) Escrow (Fund / Release / Refund) + Ledger

### POST /gigs/{gig_id}/escrow/fund
Request:

```json
{ "payment_method_id": "pm_1" }
```

Response:

```json
{ "escrow_id": "esc_1", "status": "funded" }
```

### POST /gigs/{gig_id}/escrow/release
Response:

```json
{ "escrow_id": "esc_1", "status": "released" }
```

### POST /gigs/{gig_id}/escrow/refund
Response:

```json
{ "escrow_id": "esc_1", "status": "refunded" }
```

### GET /wallet/ledger
Response:

```json
{ "items": [{ "id": "txn_1", "type": "earning_credit", "amount": { "amount": 80000, "currency": "PHP" } }] }
```

## 8) Shift + Attendance (QR)

### POST /gigs/{gig_id}/shift/check-in
Request:

```json
{ "qr_token": "signed_token" }
```

Response:

```json
{ "shift_id": "shift_1", "check_in_at": "2026-05-01T09:01:10Z" }
```

### POST /gigs/{gig_id}/shift/check-out
Request:

```json
{ "qr_token": "signed_token" }
```

Response:

```json
{ "shift_id": "shift_1", "check_out_at": "2026-05-01T17:00:05Z" }
```

## 9) Wallet + Payouts

### GET /wallet
Response:

```json
{
  "available": { "amount": 80000, "currency": "PHP" },
  "pending": { "amount": 0, "currency": "PHP" }
}
```

### POST /wallet/withdraw
Request:

```json
{ "amount": { "amount": 50000, "currency": "PHP" }, "destination_id": "gcash_1" }
```

Response:

```json
{ "payout_id": "po_1", "status": "requested" }
```

## 10) Ratings

### POST /ratings
Request:

```json
{
  "gig_id": "gig_1",
  "rated_user_id": "biz_1",
  "stars": 5,
  "feedback": "Great experience"
}
```

Response:

```json
{ "rating_id": "rate_1" }
```

## 11) Notifications

### GET /notifications
Response:

```json
{ "items": [{ "id": "n_1", "title": "You were hired", "body": "Gig Kitchen Helper", "read_at": null }] }
```

### POST /notifications/{id}/read
Response:

```json
{ "ok": true }
```

