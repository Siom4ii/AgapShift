-- In-app notification inbox (list + mark read). Cross-user inserts use notify_user().

create table if not exists public.in_app_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  body text not null,
  data jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists in_app_notifications_user_created_idx
  on public.in_app_notifications (user_id, created_at desc);

alter table public.in_app_notifications enable row level security;

drop policy if exists in_app_notifications_select_own on public.in_app_notifications;
create policy in_app_notifications_select_own
  on public.in_app_notifications for select to authenticated
  using (user_id = auth.uid());

drop policy if exists in_app_notifications_insert_self on public.in_app_notifications;
create policy in_app_notifications_insert_self
  on public.in_app_notifications for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists in_app_notifications_update_own on public.in_app_notifications;
create policy in_app_notifications_update_own
  on public.in_app_notifications for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- SECURITY DEFINER: allow worker→business (applicant) and business→worker (gig owner) notifications.
create or replace function public.notify_user(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_data jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'not authenticated';
  end if;

  if p_user_id = v_actor then
    insert into public.in_app_notifications (user_id, title, body, data)
    values (p_user_id, p_title, p_body, p_data)
    returning id into v_id;
    return v_id;
  end if;

  if exists (
    select 1
    from public.gig_applications ga
    inner join public.gigs g on g.id = ga.gig_id and g.business_id = p_user_id
    where ga.worker_id = v_actor
  ) then
    insert into public.in_app_notifications (user_id, title, body, data)
    values (p_user_id, p_title, p_body, p_data)
    returning id into v_id;
    return v_id;
  end if;

  if exists (
    select 1
    from public.gig_applications ga
    inner join public.gigs g on g.id = ga.gig_id and g.business_id = v_actor
    where ga.worker_id = p_user_id
  ) then
    insert into public.in_app_notifications (user_id, title, body, data)
    values (p_user_id, p_title, p_body, p_data)
    returning id into v_id;
    return v_id;
  end if;

  raise exception 'not authorized to notify this user';
end;
$$;

revoke all on function public.notify_user(uuid, text, text, jsonb) from public;
grant execute on function public.notify_user(uuid, text, text, jsonb) to authenticated;
