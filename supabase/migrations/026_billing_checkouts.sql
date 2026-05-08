-- Billing checkout tracking for PayMongo (subscriptions + boosts).

create table if not exists public.billing_checkouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  product text not null, -- worker_sub | employer_sub | gig_boost
  gig_id uuid references public.gigs (id) on delete set null,
  paymongo_checkout_session_id text,
  status text not null default 'created', -- created | paid | failed | cancelled
  amount_centavos int not null,
  currency text not null default 'PHP',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists billing_checkouts_user_created_idx
  on public.billing_checkouts (user_id, created_at desc);

create index if not exists billing_checkouts_paymongo_cs_idx
  on public.billing_checkouts (paymongo_checkout_session_id);

alter table public.billing_checkouts enable row level security;

drop policy if exists billing_checkouts_select_own on public.billing_checkouts;
create policy billing_checkouts_select_own
  on public.billing_checkouts for select to authenticated
  using (user_id = auth.uid());

-- Inserts/updates are done by server-side (Edge Function) with service role.

