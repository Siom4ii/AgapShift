-- Run in Supabase SQL Editor (Dashboard → SQL). Safe to re-run only on empty DB;
-- adjust if tables already exist.

create table if not exists public.gigs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  description text not null,
  lat double precision not null,
  lng double precision not null,
  address_label text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  pay_amount int not null,
  pay_currency text not null default 'PHP', 
  category text not null,
  status text not null
    check (status in ('open', 'filled', 'ongoing', 'completed', 'cancelled')),
  hired_worker_id uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create index if not exists gigs_business_id_idx on public.gigs (business_id);
create index if not exists gigs_status_idx on public.gigs (status);

create table if not exists public.gig_applications (
  id uuid primary key default gen_random_uuid(),
  gig_id uuid not null references public.gigs (id) on delete cascade,
  worker_id uuid not null references auth.users (id) on delete cascade,
  status text not null
    check (status in ('applied', 'withdrawn', 'rejected', 'hired')),
  created_at timestamptz not null default now(),
  unique (gig_id, worker_id)
);

create index if not exists gig_applications_gig_id_idx
  on public.gig_applications (gig_id);

alter table public.gigs enable row level security;
alter table public.gig_applications enable row level security;

-- Avoid RLS recursion (gigs <-> gig_applications): use SECURITY DEFINER helpers.
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

drop policy if exists "gigs_insert" on public.gigs;
create policy "gigs_insert"
  on public.gigs for insert to authenticated
  with check (business_id = auth.uid());

drop policy if exists "gigs_update" on public.gigs;
create policy "gigs_update"
  on public.gigs for update to authenticated
  using (business_id = auth.uid());

drop policy if exists "gig_apps_select" on public.gig_applications;
create policy "gig_apps_select"
  on public.gig_applications for select to authenticated
  using (
    worker_id = (select auth.uid())
    or public.is_gig_business_owner(gig_id)
  );

drop policy if exists "gig_apps_insert" on public.gig_applications;
create policy "gig_apps_insert"
  on public.gig_applications for insert to authenticated
  with check (worker_id = auth.uid());

drop policy if exists "gig_apps_update" on public.gig_applications;
create policy "gig_apps_update"
  on public.gig_applications for update to authenticated
  using (
    worker_id = (select auth.uid())
    or public.is_gig_business_owner(gig_id)
  );
