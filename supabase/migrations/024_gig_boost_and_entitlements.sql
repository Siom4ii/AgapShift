-- Per-post boost (feed visibility). Employer verification window already on employer_entitlements.

alter table public.gigs
  add column if not exists boosted_until timestamptz;

comment on column public.gigs.boosted_until is
  'When set and in the future, job appears at top of worker feed with Boosted badge.';

create index if not exists gigs_open_boosted_idx
  on public.gigs (status, boosted_until desc nulls last)
  where status = 'open';
