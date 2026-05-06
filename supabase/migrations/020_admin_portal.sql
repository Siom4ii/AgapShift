-- Admin web portal: staff role, read-all for verification queues, RPC to set status.
-- Bootstrap: create a dedicated staff user in Supabase Auth (Dashboard) — use an
-- email that is NOT used on the mobile app — then run:
--   update public.profiles set role = 'admin' where id = '<auth user uuid>';
-- The mobile app signs out users with role admin; staff uses this web console only.

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role is null or role in ('worker', 'business', 'admin'));

alter table public.profiles
  add column if not exists account_review_note text;

comment on column public.profiles.account_review_note is
  'Optional note from staff when rejecting or following up (shown in admin UI; app may surface later).';

-- True when the signed-in user is platform staff (bypasses RLS via SECURITY DEFINER).
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select p.role = 'admin'
      from public.profiles p
      where p.id = (select auth.uid())
    ),
    false
  );
$$;

grant execute on function public.is_platform_admin() to authenticated;

drop policy if exists "profiles_select_admin" on public.profiles;
create policy "profiles_select_admin"
  on public.profiles for select
  to authenticated
  using (public.is_platform_admin());

drop policy if exists "worker_onboarding_select_admin" on public.worker_onboarding_responses;
create policy "worker_onboarding_select_admin"
  on public.worker_onboarding_responses for select
  to authenticated
  using (public.is_platform_admin());

drop policy if exists "business_onboarding_select_admin" on public.business_onboarding_responses;
create policy "business_onboarding_select_admin"
  on public.business_onboarding_responses for select
  to authenticated
  using (public.is_platform_admin());

drop policy if exists "kyc_documents_select_admin" on public.kyc_documents;
create policy "kyc_documents_select_admin"
  on public.kyc_documents for select
  to authenticated
  using (public.is_platform_admin());

drop policy if exists "kyc_documents_storage_select_admin" on storage.objects;
create policy "kyc_documents_storage_select_admin"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'kyc-documents'
    and public.is_platform_admin()
  );

-- Centralized status updates (avoids broad admin UPDATE on profiles).
create or replace function public.admin_set_account_review(
  p_user_id uuid,
  p_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not authorized';
  end if;
  if p_status is null
    or p_status not in (
      'pendingVerification',
      'verified',
      'rejected',
      'suspended'
    )
  then
    raise exception 'invalid account status';
  end if;
  update public.profiles
  set
    account_status = p_status,
    account_review_note = p_note,
    updated_at = now()
  where id = p_user_id
    and role in ('worker', 'business');
  if not FOUND then
    raise exception 'profile not found or not a worker/business account';
  end if;
end;
$$;

grant execute on function public.admin_set_account_review(uuid, text, text) to authenticated;
