-- Let authenticated clients resolve worker display names for arbitrary user ids
-- (e.g. gig applicants) without opening full profile SELECT to all users.
-- Uses SECURITY DEFINER to bypass RLS; returns only extracted full_name text.

create or replace function public.worker_display_names_for_ids(p_ids uuid[])
returns table (id uuid, full_name text)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    nullif(
      btrim(
        coalesce(
          p.identity_snapshot #>> '{data,personal,full_name}',
          p.identity_snapshot #>> '{personal,full_name}'
        )
      ),
      ''
    ) as full_name
  from public.profiles p
  where p.id = any(p_ids);
$$;

comment on function public.worker_display_names_for_ids(uuid[]) is
  'Returns worker profile id + full_name from identity_snapshot (wrapped or unwrapped).';

grant execute on function public.worker_display_names_for_ids(uuid[]) to authenticated;
