-- Fix 42P17 infinite RLS recursion on dm_conversation_members (already fixed in 013
-- for new installs). Safe to re-run: replaces helper + policies.

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

drop policy if exists "dm_members_select_self" on public.dm_conversation_members;
drop policy if exists "dm_members_select_member" on public.dm_conversation_members;
create policy "dm_members_select_member"
  on public.dm_conversation_members for select to authenticated
  using (public.dm_user_in_conversation(conversation_id, auth.uid()));

drop policy if exists "dm_conversations_select_member" on public.dm_conversations;
create policy "dm_conversations_select_member"
  on public.dm_conversations for select to authenticated
  using (public.dm_user_in_conversation(id, auth.uid()));

drop policy if exists "dm_messages_select_member" on public.dm_messages;
create policy "dm_messages_select_member"
  on public.dm_messages for select to authenticated
  using (public.dm_user_in_conversation(conversation_id, auth.uid()));

drop policy if exists "dm_messages_insert_member" on public.dm_messages;
create policy "dm_messages_insert_member"
  on public.dm_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.dm_user_in_conversation(conversation_id, auth.uid())
  );
