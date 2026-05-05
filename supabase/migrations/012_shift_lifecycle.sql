-- Shift sessions + attendance persisted in Postgres. Keeps gig lifecycle in sync:
-- filled -> ongoing (first check-in), ongoing -> completed (check-out after check-in).

create table if not exists public.shift_sessions (
  id uuid primary key default gen_random_uuid(),
  gig_id uuid not null references public.gigs (id) on delete cascade,
  worker_id uuid not null references auth.users (id) on delete cascade,
  business_id uuid not null references auth.users (id) on delete cascade,
  check_in_at timestamptz,
  check_out_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (gig_id, worker_id)
);

create index if not exists shift_sessions_gig_id_idx on public.shift_sessions (gig_id);
create index if not exists shift_sessions_worker_id_idx on public.shift_sessions (worker_id);

create table if not exists public.shift_attendance (
  id uuid primary key default gen_random_uuid(),
  gig_id uuid not null references public.gigs (id) on delete cascade,
  worker_id uuid not null references auth.users (id) on delete cascade,
  scan_type text not null
    check (scan_type in ('checkIn', 'checkOut')),
  scanned_at timestamptz not null default now()
);

create index if not exists shift_attendance_gig_id_idx on public.shift_attendance (gig_id);

create unique index if not exists shift_attendance_one_scan_per_type
  on public.shift_attendance (gig_id, worker_id, scan_type);

-- Hired worker may record attendance only while the gig is still active (filled / ongoing).
create or replace function public.can_worker_scan_shift(p_gig_id uuid, p_business_id uuid)
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
      and g.business_id = p_business_id
      and g.hired_worker_id = (select auth.uid())
      and g.status in ('filled', 'ongoing')
  );
$$;

comment on function public.can_worker_scan_shift(uuid, uuid) is
  'True if the current user is the hired worker and the gig allows check-in/out.';

grant execute on function public.can_worker_scan_shift(uuid, uuid) to authenticated;

alter table public.shift_sessions enable row level security;
alter table public.shift_attendance enable row level security;

drop policy if exists "shift_sessions_select" on public.shift_sessions;
create policy "shift_sessions_select"
  on public.shift_sessions for select to authenticated
  using (
    worker_id = (select auth.uid())
    or public.is_gig_business_owner(gig_id)
  );

drop policy if exists "shift_sessions_insert" on public.shift_sessions;
create policy "shift_sessions_insert"
  on public.shift_sessions for insert to authenticated
  with check (
    worker_id = (select auth.uid())
    and public.can_worker_scan_shift(gig_id, business_id)
  );

drop policy if exists "shift_sessions_update" on public.shift_sessions;
create policy "shift_sessions_update"
  on public.shift_sessions for update to authenticated
  using (
    worker_id = (select auth.uid())
    and public.can_worker_scan_shift(gig_id, business_id)
  )
  with check (
    worker_id = (select auth.uid())
    and public.can_worker_scan_shift(gig_id, business_id)
  );

drop policy if exists "shift_attendance_select" on public.shift_attendance;
create policy "shift_attendance_select"
  on public.shift_attendance for select to authenticated
  using (
    worker_id = (select auth.uid())
    or public.is_gig_business_owner(gig_id)
  );

drop policy if exists "shift_attendance_insert" on public.shift_attendance;
create policy "shift_attendance_insert"
  on public.shift_attendance for insert to authenticated
  with check (
    worker_id = (select auth.uid())
    and exists (
      select 1
      from public.gigs g
      where g.id = gig_id
        and g.hired_worker_id = (select auth.uid())
        and g.status in ('filled', 'ongoing')
    )
  );

create or replace function public.set_shift_sessions_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_shift_sessions_updated_at on public.shift_sessions;
create trigger trg_shift_sessions_updated_at
  before update on public.shift_sessions
  for each row
  execute function public.set_shift_sessions_updated_at();

create or replace function public.shift_sessions_sync_gig_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.check_in_at is not null then
    update public.gigs
    set status = 'ongoing'
    where id = new.gig_id
      and status = 'filled';
  end if;

  if new.check_in_at is not null and new.check_out_at is not null then
    update public.gigs
    set status = 'completed'
    where id = new.gig_id
      and status in ('filled', 'ongoing');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_shift_sessions_gig_status on public.shift_sessions;
create trigger trg_shift_sessions_gig_status
  after insert or update of check_in_at, check_out_at on public.shift_sessions
  for each row
  execute function public.shift_sessions_sync_gig_status();

-- Find Workers: global completed-shift counts (RLS on shift_sessions would under-count).
create or replace function public.worker_completed_shift_counts(p_ids uuid[])
returns table (
  worker_id uuid,
  completed_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select s.worker_id, count(*)::bigint
  from public.shift_sessions s
  where s.worker_id = any(p_ids)
    and s.check_out_at is not null
  group by s.worker_id;
$$;

comment on function public.worker_completed_shift_counts(uuid[]) is
  'Completed shifts (check-out recorded) per worker for directory stats.';

grant execute on function public.worker_completed_shift_counts(uuid[]) to authenticated;
