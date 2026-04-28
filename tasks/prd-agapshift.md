# PRD: AgapShift (Location-Based Gig Marketplace)

## 1. Introduction / Overview

AgapShift is a **location-based gig marketplace** that connects **verified businesses** needing immediate on-site workers with **verified workers** seeking short-term, flexible shifts. The product prioritizes **trust (KYC + admin approval)**, **real-time discovery**, and **secure transactions via escrow** to reduce no-shows, fraud, and payment disputes.

This PRD covers the **MVP** for:
- **Android app** for Workers and Businesses (role-based UX)
- **Admin web (optional)** for manual verification and basic monitoring

## 2. Goals

- **G1: Enable trusted, on-site gig hiring** with verified accounts for both Workers and Businesses.
- **G2: Reduce time-to-hire** by allowing Businesses to post gigs and review applicants quickly.
- **G3: Ensure secure payouts** using an **escrow-style** payment flow (Business pre-pays; release after completion).
- **G4: Provide location-based discovery** so Workers can find nearby gigs and Businesses can discover nearby Workers.
- **G5: Support shift completion with anti-fraud attendance** (QR check-in/check-out).

## 3. User Stories

### Worker (Job Seeker)
- As a Worker, I want to choose “I Want to Work” during first launch so the app shows Worker onboarding and a Worker dashboard.
- As a Worker, I want to sign up with email + OTP so I can securely create an account.
- As a Worker, I want to submit my profile and verification details so I can be reviewed and approved.
- As a Worker, I want to browse nearby gigs and apply so I can earn money.
- As a Worker, I want to see an active shift with a timer and QR check-in/check-out so my attendance is accurately recorded.
- As a Worker, I want to see my wallet balance and withdraw to GCash/Maya/bank so I can access earnings.
- As a Worker, I want to rate a Business after a shift so I can help others decide who to work for.

### Business Owner
- As a Business, I want to choose “I Want to Hire” during first launch so the app shows Business onboarding and a Business dashboard.
- As a Business, I want to sign up with email + OTP so I can securely create an account.
- As a Business, I want to upload business documents and set my location so I can be verified and visible to nearby workers.
- As a Business, I want to post a gig with pay, duration, and location so Workers can apply.
- As a Business, I want to review applicants and select a Worker so I can hire the right person.
- As a Business, I want to pre-pay into escrow so the Worker trusts the shift is funded.
- As a Business, I want to generate QR codes for check-in/check-out so attendance is verifiable.
- As a Business, I want to track expenses and transaction history so I can manage hiring costs.
- As a Business, I want to rate a Worker after a shift so I can encourage quality work and build trust.

### Admin (Platform Operations)
- As an Admin, I want to review Worker KYC submissions so only legitimate workers can apply.
- As an Admin, I want to review Business verification documents so only legitimate businesses can hire.
- As an Admin, I want to view basic platform activity (new signups, pending verifications, disputes/flags if any) so I can keep the marketplace safe.

## 4. Functional Requirements

### 4.1 First Launch & Role Selection

1. The app must show a **Getting Started** screen on first launch with branding and a “Get Started” CTA.
2. The system must require users to choose a role:
   - “I Want to Work” (Worker)
   - “I Want to Hire” (Business)
3. The system must persist the chosen role and use it to:
   - determine registration/onboarding fields
   - show the correct dashboard and navigation
   - enforce role-based permissions (Worker vs Business)
4. The system must allow changing role **only by creating a separate account** (MVP constraint to reduce complexity and fraud). *(See Open Questions if you want dual-role accounts.)*

### 4.2 Authentication (Email + OTP)

5. The system must allow account creation using **email**.
6. The system must send a **6-digit OTP** to the email address for verification.
7. The system must verify the OTP before allowing onboarding to proceed.
8. The system must support login with email and OTP (passwordless) for MVP.
9. The system must prevent unverified emails from accessing dashboards beyond onboarding status screens.

### 4.3 Worker Onboarding & Verification

10. The system must collect Worker personal information:
   - full name
   - birthdate
   - contact details (phone optional if needed)
   - address
   - emergency contact
11. The system must collect Worker identity verification:
   - government ID image upload (front/back if applicable)
   - selfie liveness capture
12. The system must allow Workers to create a profile/resume:
   - skills selection (predefined list; multi-select)
   - work experience (free text and/or structured items)
   - short bio
   - education (optional)
13. The system must collect Worker payout setup:
   - bank account details OR
   - e-wallet (GCash / Maya)
14. The system must set Worker account status to **Pending Verification** after submission.
15. The system must restrict Workers with Pending Verification from applying to gigs.
16. The system must support Admin actions to approve/reject Worker verification.
17. The system must set Worker account status to **Verified** after approval and enable applying to gigs.
18. The system must notify Workers when their verification status changes (approved/rejected).

### 4.4 Business Onboarding & Verification

19. The system must collect Business type selection:
   - Sole Proprietorship
   - Partnership
   - Corporation
20. The system must collect Business verification documents:
   - business permits
   - registration certificates
   - authorized representative government ID(s)
21. The system must allow the Business to set location by dropping a pin on a map (and store lat/long).
22. The system must collect Business payment setup:
   - bank account OR
   - e-wallet (GCash / Maya)
23. The system must set Business account status to **Pending Verification** after submission.
24. The system must restrict Pending Verification businesses from posting gigs or hiring.
25. The system must support Admin actions to approve/reject Business verification.
26. The system must set Business account status to **Verified** after approval and enable job posting/hiring.
27. The system must notify Businesses when their verification status changes (approved/rejected).

### 4.5 Discovery (Location-Based)

28. The system must show Workers a feed of **nearby gigs** sorted by distance and/or recency.
29. The system must allow Workers to filter gigs by:
   - distance radius
   - pay range
   - job type/category
30. The system must show Businesses a list of **nearby Workers** (Verified only) with summary info (skills, rating, distance).
31. The system must allow Businesses to filter Workers by:
   - skills
   - availability status (see Open Questions)
   - distance radius
32. The system must request and handle location permission and provide a fallback if denied (manual location selection).

### 4.6 Gig / Job System (Posting, Applying, Hiring)

33. The system must allow Verified Businesses to create a gig with:
   - title
   - description
   - location (pin + address)
   - duration (start time/end time or hours)
   - salary (total or hourly)
   - job type/category
34. The system must show Workers a gig details screen with all fields and Business profile summary.
35. The system must allow Verified Workers to apply to an open gig.
36. The system must allow Businesses to view applicants for a gig (Applicant list).
37. The system must allow Businesses to select/hire a Worker from the applicants.
38. The system must enforce gig status transitions, at minimum:
   - Draft (optional)
   - Open (accepting applications)
   - Filled (worker selected)
   - Ongoing (shift started)
   - Completed (shift ended)
   - Cancelled
39. The system must notify Workers about:
   - application received (optional)
   - hired / not selected
   - gig status changes (start/complete/cancel)

### 4.7 Escrow Payments (MVP)

40. The system must require Verified Businesses to **fund the gig (escrow)** before confirming the hire.
41. The system must show Businesses the required escrow amount and fees (if any) before payment confirmation.
42. The system must hold the funded amount in escrow until shift completion conditions are met.
43. The system must release escrow to the Worker’s wallet after shift completion.
44. The system must support partial/failed flows:
   - Business funds escrow but cancels before hire → refund rules apply
   - Worker no-show or cancellation → escrow release/refund rules apply
45. The system must record all payment and escrow events in a transaction ledger.

### 4.8 Shift Session (Active Shift)

46. The system must show Workers an **Active Shift** screen for the currently hired gig.
47. The system must allow shift start via **QR check-in**.
48. The system must show a live timer from check-in until check-out.
49. The system must allow shift end via **QR check-out**.
50. The system must prevent starting or ending a shift without successful QR validation (subject to offline rules; see Open Questions).

### 4.9 Attendance (QR-Based)

51. The system must allow the Business to generate a **check-in QR** and **check-out QR** for a gig/shift.
52. The system must validate QR scans and record:
   - timestamp
   - worker id
   - gig id
   - scan type (in/out)
53. The system must prevent duplicate check-ins or check-outs for the same worker/gig.
54. The system must surface attendance records to both Worker and Business for transparency.

### 4.10 Wallet & Payouts

55. The system must provide Worker wallet views:
   - available balance
   - pending earnings
   - transaction history
56. The system must allow Workers to initiate withdrawals to:
   - GCash
   - Maya
   - bank account
57. The system must support payout processing statuses:
   - requested
   - processing
   - paid
   - failed
58. The system must provide Business financial views:
   - transaction history
   - escrow payments
   - refunds (if any)

### 4.11 Expense Tracking (Business)

59. The system must show Businesses total hiring cost over selectable time ranges (e.g., 7d/30d/custom).
60. The system must show a list of expenses per gig and per worker with payment status.

### 4.12 Profile System

61. The system must display Worker profiles with:
   - resume summary (skills, experience, bio)
   - verification status
   - rating and completed shifts count
62. The system must display Business profiles with:
   - company details
   - verification status
   - hiring stats (e.g., shifts posted/completed)
   - rating

### 4.13 Rating System

63. The system must allow Businesses to rate Workers after a completed shift (1–5 + optional short feedback).
64. The system must allow Workers to rate Businesses after a completed shift (1–5 + optional short feedback).
65. The system must prevent ratings unless the shift is Completed.
66. The system must display aggregate ratings in profiles and relevant list cards (with anti-spam safeguards, e.g., one rating per shift).

### 4.14 Notifications

67. The system must send notifications for:
   - verification status changes
   - new gig posted (Worker alerts by location + category if opted-in)
   - application/hiring updates
   - shift reminders (optional)
   - payment/escrow events and payout updates
68. The system must provide an in-app notifications inbox for viewing recent notifications.

### 4.15 Admin System (MVP)

69. The system must provide an Admin capability to:
   - view pending Worker verifications
   - approve/reject Worker verifications with reason
   - view pending Business verifications
   - approve/reject Business verifications with reason
70. The system must log admin actions (who/when/what).
71. The system must allow admins to view basic platform activity metrics:
   - new users (workers/businesses)
   - pending verifications
   - gigs posted/filled/completed
72. The system must support a basic “flag” mechanism (manual) to suspend accounts (optional for MVP; see Open Questions).

## 5. Non-Goals (Out of Scope)

- Automated, instant KYC approvals (manual admin review only in MVP).
- Complex dispute resolution workflows (chargebacks, arbitration, multi-step case management).
- Dynamic surge pricing or bidding marketplace.
- Multi-worker gigs (one gig hiring multiple workers) unless explicitly added later.
- Offline-first attendance with delayed sync (unless explicitly required).
- Multi-country compliance (tax forms, localized ID types beyond PH).
- In-app chat/messaging between Worker and Business (unless explicitly required).

## 6. Design Considerations (Optional)

- **Role-based navigation**: Worker and Business dashboards should have separate bottom navigation and terminology.
- **Trust cues**: Display verification badges prominently (Verified Worker/Verified Business).
- **Map UX**:
  - Worker: gig cards with distance + “View on map”
  - Business: pin location setup and “workers near you”
- **Critical states**:
  - Pending Verification should show a clear status screen and what’s missing.
  - Payment/escrow should show clear statuses and receipts.

## 7. Technical Considerations (Optional)

- **Platform**: Android app (two roles) + optional Admin web.
- **Geo**: Use lat/long indexing for “nearby” queries (e.g., geohash or PostGIS).
- **Security**:
  - Store KYC documents securely (private bucket, signed URLs).
  - PII encryption at rest where feasible.
  - Audit logs for admin actions and payment events.
- **Payments**:
  - Escrow typically requires a payment provider or a platform-controlled wallet model; define provider integration early.
- **QR attendance**:
  - QR payload should be time-bound and signed to prevent reuse.
  - Consider rotating QR codes for check-in/check-out windows.
- **Notifications**:
  - Push notifications (FCM) + in-app inbox.

## 8. Success Metrics

- **Time-to-hire**: median time from gig posted → worker selected \(target: < 30 minutes in active areas\).
- **Verification throughput**: median time from submission → admin decision \(target: < 24 hours\).
- **Fill rate**: % of posted gigs that get a hire \(target: > 60% after initial ramp\).
- **Completion rate**: % of hired shifts completed successfully \(target: > 85%\).
- **No-show rate**: % of hired shifts with worker no-show \(target: < 10%\).
- **Payment success**: % of escrow fundings and releases that succeed without manual intervention \(target: > 98%\).
- **Safety**: # of fraud incidents per 1,000 shifts (track baseline; target continuous reduction).

## 9. Open Questions

1. **Admin web vs backoffice**: Do you want an actual admin UI shipped in MVP, or will admins use a temporary internal tool/DB console?
2. **Payment provider**: Which provider will support PH escrow-like flows (or what alternative “platform wallet” model will be used)?
3. **Fees**: Will AgapShift charge a platform fee (per shift %, fixed fee, both)? Who pays it?
4. **Cancellations & refunds**: Exact rules for:
   - business cancels after funding but before hire
   - worker cancels after being hired
   - no-show scenarios
5. **Availability model**: How does a Worker declare availability (toggle “Available now”, schedule, or inferred)?
6. **QR constraints**: Should QR scanning require the Business device to generate the code in real-time, and should scanning require being within GPS radius of gig location?
7. **Disputes**: If Business disputes attendance or performance, what is the MVP handling (hold escrow, admin decision, partial payout)?
8. **Dual-role accounts**: Should a single account be able to switch between Worker and Business roles, or keep separate accounts permanently?

