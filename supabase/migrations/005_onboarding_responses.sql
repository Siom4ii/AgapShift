-- Full onboarding answers as JSON (auth + core profile stay in auth.users / profiles).

create table if not exists public.worker_onboarding_responses (
  user_id uuid primary key references auth.users (id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  submitted_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists worker_onboarding_responses_updated_idx
  on public.worker_onboarding_responses (updated_at desc);

alter table public.worker_onboarding_responses enable row level security;

drop policy if exists "worker_onboarding_select_own" on public.worker_onboarding_responses;
create policy "worker_onboarding_select_own"
  on public.worker_onboarding_responses for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "worker_onboarding_insert_own" on public.worker_onboarding_responses;
create policy "worker_onboarding_insert_own"
  on public.worker_onboarding_responses for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "worker_onboarding_update_own" on public.worker_onboarding_responses;
create policy "worker_onboarding_update_own"
  on public.worker_onboarding_responses for update to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.business_onboarding_responses (
  user_id uuid primary key references auth.users (id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  submitted_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists business_onboarding_responses_updated_idx
  on public.business_onboarding_responses (updated_at desc);

alter table public.business_onboarding_responses enable row level security;

drop policy if exists "business_onboarding_select_own" on public.business_onboarding_responses;
create policy "business_onboarding_select_own"
  on public.business_onboarding_responses for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "business_onboarding_insert_own" on public.business_onboarding_responses;
create policy "business_onboarding_insert_own"
  on public.business_onboarding_responses for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "business_onboarding_update_own" on public.business_onboarding_responses;
create policy "business_onboarding_update_own"
  on public.business_onboarding_responses for update to authenticated
  using (user_id = (select auth.uid()));
