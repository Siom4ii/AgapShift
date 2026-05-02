-- Denormalized copy of user-submitted onboarding data on `profiles` for easy
-- admin queries. Does NOT include passwords — those exist only as hashes in
-- auth.users (never expose or duplicate in public tables).

alter table public.profiles
  add column if not exists identity_snapshot jsonb not null default '{}'::jsonb;

comment on column public.profiles.identity_snapshot is
  'Non-secret identity/onboarding fields (email, phone, names, etc.). No passwords.';
