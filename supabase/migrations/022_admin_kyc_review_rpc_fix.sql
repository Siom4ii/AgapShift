-- Recreate KYC document review RPC so PostgREST finds it (schema cache + parameter names).
-- Safe if 021 already ran with an older signature.

drop function if exists public.admin_set_kyc_document_review(uuid, text, text);

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
