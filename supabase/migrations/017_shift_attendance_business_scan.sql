-- Allow the gig owner to insert/update shift attendance and sessions when scanning
-- a hired worker's QR (employer device records check-in / check-out).

drop policy if exists "shift_attendance_insert" on public.shift_attendance;
create policy "shift_attendance_insert"
  on public.shift_attendance for insert to authenticated
  with check (
    (
      worker_id = (select auth.uid())
      and exists (
        select 1
        from public.gigs g
        where g.id = gig_id
          and g.hired_worker_id = (select auth.uid())
          and g.status in ('filled', 'ongoing')
      )
    )
    or
    (
      public.is_gig_business_owner(gig_id)
      and exists (
        select 1
        from public.gigs g
        where g.id = gig_id
          and g.hired_worker_id = shift_attendance.worker_id
          and g.status in ('filled', 'ongoing')
      )
    )
  );

drop policy if exists "shift_sessions_insert" on public.shift_sessions;
create policy "shift_sessions_insert"
  on public.shift_sessions for insert to authenticated
  with check (
    (
      worker_id = (select auth.uid())
      and public.can_worker_scan_shift(gig_id, business_id)
    )
    or
    (
      public.is_gig_business_owner(gig_id)
      and exists (
        select 1
        from public.gigs g
        where g.id = gig_id
          and g.hired_worker_id = worker_id
          and g.business_id = business_id
          and g.status in ('filled', 'ongoing')
      )
    )
  );

drop policy if exists "shift_sessions_update" on public.shift_sessions;
create policy "shift_sessions_update"
  on public.shift_sessions for update to authenticated
  using (
    (
      worker_id = (select auth.uid())
      and public.can_worker_scan_shift(gig_id, business_id)
    )
    or
    (
      public.is_gig_business_owner(gig_id)
      and exists (
        select 1
        from public.gigs g
        where g.id = gig_id
          and g.hired_worker_id = worker_id
          and g.status in ('filled', 'ongoing')
      )
    )
  )
  with check (
    (
      worker_id = (select auth.uid())
      and public.can_worker_scan_shift(gig_id, business_id)
    )
    or
    (
      public.is_gig_business_owner(gig_id)
      and exists (
        select 1
        from public.gigs g
        where g.id = gig_id
          and g.hired_worker_id = worker_id
          and g.status in ('filled', 'ongoing')
      )
    )
  );
