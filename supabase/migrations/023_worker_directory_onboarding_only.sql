-- Find Workers should list only workers who finished registration (onboarding).
-- Incomplete accounts may still have auth + profiles row from handle_new_user;
-- they must not appear as hireable workers until onboarding_done is true.

create or replace function public.worker_profiles_for_business_directory()
returns table (
  profile_id uuid,
  identity_snapshot jsonb,
  account_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.identity_snapshot, p.account_status
  from public.profiles p
  where coalesce(p.role, '') = 'worker'
    and p.onboarding_done = true;
$$;

comment on function public.worker_profiles_for_business_directory() is
  'Worker rows for business Find Workers (onboarding complete only); bypasses RLS.';

-- Stale rows from older clients that wrote role before onboarding finished.
update public.profiles
set role = null, updated_at = now()
where onboarding_done = false
  and role is not null;
