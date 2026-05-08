-- Ratings & feedback between workers and employers per gig/shift.

create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  gig_id uuid not null references public.gigs(id) on delete cascade,
  rater_user_id uuid not null references public.profiles(id) on delete cascade,
  rated_user_id uuid not null references public.profiles(id) on delete cascade,
  stars integer not null check (stars >= 1 and stars <= 5),
  feedback text,
  created_at timestamptz not null default now()
);

create unique index if not exists ratings_unique_shift_rater_rated
  on public.ratings(gig_id, rater_user_id, rated_user_id);

create index if not exists ratings_rated_user_created_at
  on public.ratings(rated_user_id, created_at desc);

alter table public.ratings enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'ratings' and policyname = 'ratings_select_auth'
  ) then
    create policy "ratings_select_auth"
      on public.ratings
      for select
      to authenticated
      using (true);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'ratings' and policyname = 'ratings_insert_own'
  ) then
    create policy "ratings_insert_own"
      on public.ratings
      for insert
      to authenticated
      with check (auth.uid() = rater_user_id);
  end if;
end $$;

