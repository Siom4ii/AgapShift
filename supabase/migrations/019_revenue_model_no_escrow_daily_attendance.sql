-- Revenue model: remove in-app escrow/wallet; salaries off-app.
-- Daily attendance (per calendar day) for multi-day shifts.
-- Worker subscription + employer posting counters for future billing.

-- -------- Payment tables from 018 (drop if present) --------
drop function if exists public.payments_request_payout(int, text);
drop function if exists public.payments_refund_escrow(uuid);
drop function if exists public.payments_release_escrow(uuid);
drop function if exists public.payments_hold_escrow(uuid);
drop function if exists public.payments_fund_escrow(uuid);

drop table if exists public.escrows cascade;
drop table if exists public.wallets cascade;
drop table if exists public.ledger_transactions cascade;
drop table if exists public.payouts cascade;

-- -------- shift_attendance: per-day scans --------
alter table public.shift_attendance
  add column if not exists work_date date;

update public.shift_attendance
set work_date = ((scanned_at at time zone 'Asia/Manila')::date)
where work_date is null;

alter table public.shift_attendance
  alter column work_date set not null;

drop index if exists shift_attendance_one_scan_per_type;

create unique index if not exists shift_attendance_gig_worker_type_day
  on public.shift_attendance (gig_id, worker_id, scan_type, work_date);

-- -------- Entitlements (billing hooks; app enforces policy) --------
create table if not exists public.worker_entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  subscription_expires_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.employer_entitlements (
  business_id uuid primary key references auth.users (id) on delete cascade,
  jobs_posted_count int not null default 0,
  verification_fee_paid_until timestamptz,
  boost_active_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.worker_entitlements enable row level security;
alter table public.employer_entitlements enable row level security;

drop policy if exists worker_entitlements_select_own on public.worker_entitlements;
create policy worker_entitlements_select_own
  on public.worker_entitlements for select to authenticated
  using (user_id = auth.uid());

drop policy if exists worker_entitlements_upsert_own on public.worker_entitlements;
create policy worker_entitlements_upsert_own
  on public.worker_entitlements for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists worker_entitlements_update_own on public.worker_entitlements;
create policy worker_entitlements_update_own
  on public.worker_entitlements for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists employer_entitlements_select_own on public.employer_entitlements;
create policy employer_entitlements_select_own
  on public.employer_entitlements for select to authenticated
  using (business_id = auth.uid());

drop policy if exists employer_entitlements_upsert_own on public.employer_entitlements;
create policy employer_entitlements_upsert_own
  on public.employer_entitlements for insert to authenticated
  with check (business_id = auth.uid());

drop policy if exists employer_entitlements_update_own on public.employer_entitlements;
create policy employer_entitlements_update_own
  on public.employer_entitlements for update to authenticated
  using (business_id = auth.uid())
  with check (business_id = auth.uid());

create or replace function public.bump_employer_job_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.employer_entitlements (business_id, jobs_posted_count)
  values (new.business_id, 1)
  on conflict (business_id) do update
  set
    jobs_posted_count = public.employer_entitlements.jobs_posted_count + 1,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_gigs_bump_employer on public.gigs;
create trigger trg_gigs_bump_employer
  after insert on public.gigs
  for each row
  execute function public.bump_employer_job_count();

-- Backfill counts for databases that already had gigs before this migration.
insert into public.employer_entitlements (business_id, jobs_posted_count)
select business_id, count(*)::int
from public.gigs
group by business_id
on conflict (business_id) do update
set
  jobs_posted_count = excluded.jobs_posted_count,
  updated_at = now();
