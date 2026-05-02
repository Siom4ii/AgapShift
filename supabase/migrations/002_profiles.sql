-- User profile rows linked to Supabase Auth (run after 001_marketplace.sql).

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  role text check (role is null or role in ('worker', 'business')),
  onboarding_done boolean not null default false,
  account_status text check (
    account_status is null
    or account_status in (
      'pendingVerification',
      'verified',
      'rejected',
      'suspended'
    )
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  identity_snapshot jsonb not null default '{}'::jsonb
);

create index if not exists profiles_email_idx on public.profiles (email);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select to authenticated
  using (id = auth.uid());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert to authenticated
  with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using (id = auth.uid());

-- Auto-create a profile row when a new auth user is created (sign up / OAuth).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (
    new.id,
    coalesce(new.email, '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
