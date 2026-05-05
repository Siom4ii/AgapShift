-- Internal wallet balances, gig escrow, ledger, and payouts (MVP — not real PSP money movement).

create table if not exists public.wallets (
  user_id uuid primary key references auth.users (id) on delete cascade,
  available_amount int not null default 0 check (available_amount >= 0),
  pending_amount int not null default 0 check (pending_amount >= 0),
  currency text not null default 'PHP',
  updated_at timestamptz not null default now()
);

create table if not exists public.escrows (
  id uuid primary key default gen_random_uuid(),
  gig_id uuid not null references public.gigs (id) on delete cascade,
  business_id uuid not null references auth.users (id) on delete cascade,
  amount int not null check (amount > 0),
  currency text not null default 'PHP',
  status text not null
    check (status in ('funded', 'held', 'released', 'refunded')),
  updated_at timestamptz not null default now(),
  unique (gig_id)
);

create index if not exists escrows_business_id_idx on public.escrows (business_id);

create table if not exists public.ledger_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null,
  amount int not null,
  currency text not null default 'PHP',
  gig_id uuid references public.gigs (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists ledger_user_created_idx
  on public.ledger_transactions (user_id, created_at desc);

create table if not exists public.payouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  amount int not null check (amount > 0),
  currency text not null default 'PHP',
  status text not null check (status in ('requested', 'processing', 'paid', 'failed')),
  created_at timestamptz not null default now()
);

create index if not exists payouts_user_created_idx on public.payouts (user_id, created_at desc);

alter table public.wallets enable row level security;
alter table public.escrows enable row level security;
alter table public.ledger_transactions enable row level security;
alter table public.payouts enable row level security;

drop policy if exists wallets_select_own on public.wallets;
create policy wallets_select_own
  on public.wallets for select to authenticated
  using (user_id = auth.uid());

drop policy if exists wallets_insert_own_empty on public.wallets;
create policy wallets_insert_own_empty
  on public.wallets for insert to authenticated
  with check (
    user_id = auth.uid()
    and available_amount = 0
    and pending_amount = 0
  );

drop policy if exists escrows_select_related on public.escrows;
create policy escrows_select_related
  on public.escrows for select to authenticated
  using (
    business_id = auth.uid()
    or exists (
      select 1
      from public.gigs g
      where g.id = escrows.gig_id
        and g.hired_worker_id = auth.uid()
    )
  );

drop policy if exists ledger_select_own on public.ledger_transactions;
create policy ledger_select_own
  on public.ledger_transactions for select to authenticated
  using (user_id = auth.uid());

drop policy if exists payouts_select_own on public.payouts;
create policy payouts_select_own
  on public.payouts for select to authenticated
  using (user_id = auth.uid());

-- Fund escrow from gig pay; idempotent if already funded/held/released.
create or replace function public.payments_fund_escrow(p_gig_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  gig_row record;
  esc_row public.escrows%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select id, business_id, pay_amount, pay_currency, status
  into gig_row
  from public.gigs
  where id = p_gig_id;

  if not found then
    raise exception 'Gig not found';
  end if;
  if gig_row.business_id is distinct from v_uid then
    raise exception 'Not your gig';
  end if;
  if gig_row.status = 'cancelled' then
    raise exception 'Gig cancelled';
  end if;

  select * into esc_row from public.escrows where gig_id = p_gig_id;
  if found then
    if esc_row.status <> 'refunded' then
      return;
    end if;
    update public.escrows
    set
      status = 'funded',
      amount = gig_row.pay_amount,
      currency = coalesce(nullif(trim(gig_row.pay_currency), ''), 'PHP'),
      business_id = gig_row.business_id,
      updated_at = now()
    where id = esc_row.id;
  else
    insert into public.escrows (gig_id, business_id, amount, currency, status)
    values (
      p_gig_id,
      gig_row.business_id,
      gig_row.pay_amount,
      coalesce(nullif(trim(gig_row.pay_currency), ''), 'PHP'),
      'funded'
    );
  end if;

  insert into public.ledger_transactions (user_id, type, amount, currency, gig_id)
  values (
    v_uid,
    'escrowFunding',
    gig_row.pay_amount,
    coalesce(nullif(trim(gig_row.pay_currency), ''), 'PHP'),
    p_gig_id
  );
end;
$$;

create or replace function public.payments_hold_escrow(p_gig_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  n int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  update public.escrows e
  set status = 'held', updated_at = now()
  from public.gigs g
  where e.gig_id = p_gig_id
    and e.gig_id = g.id
    and g.business_id = v_uid
    and e.status = 'funded';

  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'Escrow not funded or not your gig';
  end if;
end;
$$;

create or replace function public.payments_release_escrow(p_gig_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  gig_row record;
  esc_row public.escrows%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into esc_row from public.escrows where gig_id = p_gig_id for update;
  if not found then
    raise exception 'No escrow for gig';
  end if;

  select id, business_id, hired_worker_id, status
  into gig_row
  from public.gigs
  where id = p_gig_id;
  if not found then
    raise exception 'Gig not found';
  end if;

  if esc_row.status = 'released' then
    return;
  end if;
  if esc_row.status not in ('funded', 'held') then
    raise exception 'Escrow not releasable';
  end if;
  if gig_row.hired_worker_id is null then
    raise exception 'No hired worker';
  end if;
  if v_uid is distinct from gig_row.hired_worker_id
     and v_uid is distinct from gig_row.business_id then
    raise exception 'Not authorized';
  end if;

  update public.escrows
  set status = 'released', updated_at = now()
  where id = esc_row.id;

  insert into public.wallets (user_id, available_amount, pending_amount, currency)
  values (gig_row.hired_worker_id, esc_row.amount, 0, esc_row.currency)
  on conflict (user_id) do update
  set
    available_amount = public.wallets.available_amount + excluded.available_amount,
    updated_at = now();

  insert into public.ledger_transactions (user_id, type, amount, currency, gig_id)
  values (
    gig_row.hired_worker_id,
    'escrowRelease',
    esc_row.amount,
    esc_row.currency,
    p_gig_id
  );
end;
$$;

create or replace function public.payments_refund_escrow(p_gig_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  esc_row public.escrows%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select * into esc_row from public.escrows where gig_id = p_gig_id for update;
  if not found then
    raise exception 'No escrow to refund';
  end if;
  if esc_row.business_id is distinct from v_uid then
    raise exception 'Not your escrow';
  end if;
  if esc_row.status = 'refunded' then
    return;
  end if;
  if esc_row.status = 'released' then
    raise exception 'Cannot refund released escrow';
  end if;

  update public.escrows
  set status = 'refunded', updated_at = now()
  where id = esc_row.id;

  insert into public.ledger_transactions (user_id, type, amount, currency, gig_id)
  values (v_uid, 'escrowRefund', esc_row.amount, esc_row.currency, p_gig_id);
end;
$$;

create or replace function public.payments_request_payout(
  p_amount_cents int,
  p_currency text default 'PHP'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  w public.wallets%rowtype;
  cur text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_amount_cents <= 0 then
    raise exception 'Invalid amount';
  end if;

  cur := coalesce(nullif(trim(p_currency), ''), 'PHP');

  select * into w from public.wallets where user_id = v_uid for update;
  if not found then
    raise exception 'Insufficient available balance';
  end if;
  if w.available_amount < p_amount_cents then
    raise exception 'Insufficient available balance';
  end if;

  update public.wallets
  set
    available_amount = available_amount - p_amount_cents,
    updated_at = now()
  where user_id = v_uid;

  insert into public.payouts (user_id, amount, currency, status)
  values (v_uid, p_amount_cents, cur, 'requested');

  insert into public.ledger_transactions (user_id, type, amount, currency, gig_id)
  values (v_uid, 'withdrawalDebit', p_amount_cents, cur, null);
end;
$$;

revoke all on function public.payments_fund_escrow(uuid) from public;
revoke all on function public.payments_hold_escrow(uuid) from public;
revoke all on function public.payments_release_escrow(uuid) from public;
revoke all on function public.payments_refund_escrow(uuid) from public;
revoke all on function public.payments_request_payout(int, text) from public;

grant execute on function public.payments_fund_escrow(uuid) to authenticated;
grant execute on function public.payments_hold_escrow(uuid) to authenticated;
grant execute on function public.payments_release_escrow(uuid) to authenticated;
grant execute on function public.payments_refund_escrow(uuid) to authenticated;
grant execute on function public.payments_request_payout(int, text) to authenticated;
