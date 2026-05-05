-- Extend worker_display_names_for_ids to also return business trade / corporate
-- names from identity_snapshot (DM inbox peers can be worker or business).

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
          p.identity_snapshot #>> '{personal,full_name}',
          p.identity_snapshot #>> '{data,details,sole_proprietorship,trade_name}',
          p.identity_snapshot #>> '{data,details,partnership,partnership_name}',
          p.identity_snapshot #>> '{data,details,corporation,corporate_name}'
        )
      ),
      ''
    ) as full_name
  from public.profiles p
  where p.id = any(p_ids);
$$;

comment on function public.worker_display_names_for_ids(uuid[]) is
  'Returns profile id + display name from identity_snapshot (worker full_name or business legal/trade name).';
