-- Per-file KYC review so admins can approve or reject documents one at a time.

alter table public.kyc_documents
  add column if not exists review_status text default 'pending';

update public.kyc_documents
set review_status = 'pending'
where review_status is null;

alter table public.kyc_documents
  alter column review_status set not null;

alter table public.kyc_documents drop constraint if exists kyc_documents_review_status_check;
alter table public.kyc_documents add constraint kyc_documents_review_status_check
  check (review_status in ('pending', 'approved', 'rejected'));

alter table public.kyc_documents
  add column if not exists reviewed_at timestamptz;

alter table public.kyc_documents
  add column if not exists review_note text;

comment on column public.kyc_documents.review_status is
  'Admin review: pending | approved | rejected (per upload row).';

create index if not exists kyc_documents_user_review_idx
  on public.kyc_documents (user_id, review_status);

-- Arg order p_kyc_document_id, p_note, p_status matches PostgREST / supabase-js JSON expectations.
create or replace function public.admin_set_kyc_document_review(
  p_kyc_document_id uuid,
  p_note text,
  p_status text
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
  if p_status is null or p_status not in ('pending', 'approved', 'rejected') then
    raise exception 'invalid document review status';
  end if;

  update public.kyc_documents k
  set
    review_status = p_status,
    review_note = case when p_status = 'pending' then null else p_note end,
    reviewed_at = case when p_status = 'pending' then null else now() end
  where k.id = p_kyc_document_id
    and exists (
      select 1
      from public.profiles p
      where p.id = k.user_id
        and p.role in ('worker', 'business')
    );

  if not FOUND then
    raise exception 'document not found or invalid user';
  end if;
end;
$$;

grant execute on function public.admin_set_kyc_document_review(uuid, text, text) to authenticated;
