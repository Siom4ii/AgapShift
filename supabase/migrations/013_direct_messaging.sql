-- 1:1 direct messages between authenticated users (business ↔ worker).

create table if not exists public.dm_conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.dm_conversation_members (
  conversation_id uuid not null references public.dm_conversations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  last_read_at timestamptz,
  primary key (conversation_id, user_id)
);

create index if not exists dm_conversation_members_user_idx
  on public.dm_conversation_members (user_id);

create table if not exists public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.dm_conversations (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  body text not null check (char_length(body) >= 1 and char_length(body) <= 4000),
  created_at timestamptz not null default now()
);

create index if not exists dm_messages_conversation_created_idx
  on public.dm_messages (conversation_id, created_at desc);

-- Keep parent row fresh for inbox ordering / preview (optional; app may also set).
create or replace function public.dm_touch_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.dm_conversations
  set updated_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists dm_messages_touch on public.dm_messages;
create trigger dm_messages_touch
  after insert on public.dm_messages
  for each row execute function public.dm_touch_conversation();

alter table public.dm_conversations enable row level security;
alter table public.dm_conversation_members enable row level security;
alter table public.dm_messages enable row level security;

-- Membership check without querying members under RLS (prevents 42P17 recursion).
create or replace function public.dm_user_in_conversation(p_conversation uuid, p_user uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform set_config('row_security', 'off', true);
  return exists (
    select 1 from public.dm_conversation_members m
    where m.conversation_id = p_conversation
      and m.user_id = p_user
  );
end;
$$;

revoke all on function public.dm_user_in_conversation(uuid, uuid) from public;
grant execute on function public.dm_user_in_conversation(uuid, uuid) to authenticated;
grant execute on function public.dm_user_in_conversation(uuid, uuid) to service_role;

-- Conversations: visible if member.
drop policy if exists "dm_conversations_select_member" on public.dm_conversations;
create policy "dm_conversations_select_member"
  on public.dm_conversations for select to authenticated
  using (public.dm_user_in_conversation(id, auth.uid()));

-- Members: rows for conversations you belong to (incl. other participant).
drop policy if exists "dm_members_select_self" on public.dm_conversation_members;
drop policy if exists "dm_members_select_member" on public.dm_conversation_members;
create policy "dm_members_select_member"
  on public.dm_conversation_members for select to authenticated
  using (public.dm_user_in_conversation(conversation_id, auth.uid()));

drop policy if exists "dm_members_update_own_read" on public.dm_conversation_members;
create policy "dm_members_update_own_read"
  on public.dm_conversation_members for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Messages: read if member of conversation.
drop policy if exists "dm_messages_select_member" on public.dm_messages;
create policy "dm_messages_select_member"
  on public.dm_messages for select to authenticated
  using (public.dm_user_in_conversation(conversation_id, auth.uid()));

-- Insert message: must be sender and member.
drop policy if exists "dm_messages_insert_member" on public.dm_messages;
create policy "dm_messages_insert_member"
  on public.dm_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.dm_user_in_conversation(conversation_id, auth.uid())
  );

-- Create or return existing 1:1 conversation (two members only).
create or replace function public.dm_get_or_create_conversation(p_other uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_conv uuid;
begin
  if v_me is null then
    raise exception 'not authenticated';
  end if;
  if p_other is null or p_other = v_me then
    raise exception 'invalid peer';
  end if;

  select c.id into v_conv
  from public.dm_conversations c
  where exists (
      select 1 from public.dm_conversation_members m
      where m.conversation_id = c.id and m.user_id = v_me
    )
    and exists (
      select 1 from public.dm_conversation_members m2
      where m2.conversation_id = c.id and m2.user_id = p_other
    )
  limit 1;

  if v_conv is not null then
    return v_conv;
  end if;

  insert into public.dm_conversations default values
  returning id into v_conv;

  insert into public.dm_conversation_members (conversation_id, user_id)
  values (v_conv, v_me), (v_conv, p_other);

  return v_conv;
end;
$$;

revoke all on function public.dm_get_or_create_conversation(uuid) from public;
grant execute on function public.dm_get_or_create_conversation(uuid) to authenticated;

-- Realtime (ignore if publication already contains table).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'dm_messages'
  ) then
    alter publication supabase_realtime add table public.dm_messages;
  end if;
exception
  when undefined_object then null;
end $$;
