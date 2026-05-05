-- Structured gig metadata (avoids relying only on description text).
alter table public.gigs
  add column if not exists workers_needed int;

alter table public.gigs
  add column if not exists is_urgent boolean not null default false;

comment on column public.gigs.workers_needed is 'Openings / headcount for this posting; null if unspecified.';
comment on column public.gigs.is_urgent is 'When true, workers UI may show urgent treatment.';
