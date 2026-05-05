-- Find Workers needs to list all worker profiles. If RLS policies only allow
-- `profiles_select_own`, a business user gets zero rows from a normal
-- `select * from profiles where role = 'worker'` and only sees workers who
-- appear in `gig_applications` for their gigs (often a single applicant).
-- This RPC runs as SECURITY DEFINER and returns the same fields the app uses
-- to build the directory (same exposure as migration 008’s directory policy).

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
  where coalesce(p.role, '') = 'worker';
$$;

comment on function public.worker_profiles_for_business_directory() is
  'Worker rows for business Find Workers; bypasses RLS. Grant to authenticated only.';

grant execute on function public.worker_profiles_for_business_directory() to authenticated;
