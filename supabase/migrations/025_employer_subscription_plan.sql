-- Employer monthly subscription (₱149/mo in app copy); first job post remains free per [019] counter.
-- Legacy `verification_fee_paid_until` optional migration into new column.

-- Ensure entitlements table exists (fresh DBs / out-of-order migrations).
create table if not exists public.employer_entitlements (
  business_id uuid primary key references auth.users (id) on delete cascade,
  jobs_posted_count int not null default 0,
  verification_fee_paid_until timestamptz,
  boost_active_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.employer_entitlements
  add column if not exists subscription_expires_at timestamptz;

comment on column public.employer_entitlements.subscription_expires_at is
  'Employer paid plan valid through this instant; required for 2nd+ job posts.';

update public.employer_entitlements
set subscription_expires_at = verification_fee_paid_until
where subscription_expires_at is null
  and verification_fee_paid_until is not null;
