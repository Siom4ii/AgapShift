-- Fixes: infinite recursion detected in policy for relation "gigs" (42P17).
-- Cause: gigs_select referenced gig_applications, and gig_applications policies
-- referenced gigs — each evaluation re-entered the other table's policies.
-- These SECURITY DEFINER helpers read the tables for existence checks without
-- applying RLS (function runs as definer), breaking the cycle.

create or replace function public.worker_applied_to_gig(p_gig_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.gig_applications ga
    where ga.gig_id = p_gig_id
      and ga.worker_id = (select auth.uid())
  );
$$;

create or replace function public.is_gig_business_owner(p_gig_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.gigs g
    where g.id = p_gig_id
      and g.business_id = (select auth.uid())
  );
$$;

grant execute on function public.worker_applied_to_gig(uuid) to authenticated;
grant execute on function public.is_gig_business_owner(uuid) to authenticated;

drop policy if exists "gigs_select" on public.gigs;
create policy "gigs_select"
  on public.gigs for select to authenticated
  using (
    status = 'open'
    or business_id = (select auth.uid())
    or public.worker_applied_to_gig(id)
  );

drop policy if exists "gig_apps_select" on public.gig_applications;
create policy "gig_apps_select"
  on public.gig_applications for select to authenticated
  using (
    worker_id = (select auth.uid())
    or public.is_gig_business_owner(gig_id)
  );

drop policy if exists "gig_apps_update" on public.gig_applications;
create policy "gig_apps_update"
  on public.gig_applications for update to authenticated
  using (
    worker_id = (select auth.uid())
    or public.is_gig_business_owner(gig_id)
  );
