-- KYC file metadata for admin review + Storage bucket for actual binaries.
-- Files live in Storage; this table is the queryable index (user, type, path).
-- Admin tools: use the Supabase service_role key or Dashboard Storage browser —
-- RLS on storage.objects and public.kyc_documents restricts normal users to own data only.

-- Private bucket (signed URLs or service role for admin download).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'kyc-documents',
  'kyc-documents',
  false,
  10485760,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf'
  ]::text[]
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.kyc_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  flow text not null check (flow in ('worker', 'business')),
  document_type text not null,
  bucket_id text not null default 'kyc-documents',
  storage_path text not null,
  original_filename text,
  content_type text,
  file_size bigint,
  created_at timestamptz not null default now()
);

create index if not exists kyc_documents_user_created_idx
  on public.kyc_documents (user_id, created_at desc);

create index if not exists kyc_documents_flow_type_idx
  on public.kyc_documents (flow, document_type);

comment on table public.kyc_documents is
  'References uploaded KYC files in storage; join with storage.objects / signed URLs for admin.';

alter table public.kyc_documents enable row level security;

drop policy if exists "kyc_documents_select_own" on public.kyc_documents;
create policy "kyc_documents_select_own"
  on public.kyc_documents for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "kyc_documents_insert_own" on public.kyc_documents;
create policy "kyc_documents_insert_own"
  on public.kyc_documents for insert
  to authenticated
  with check (user_id = (select auth.uid()));

grant select, insert on public.kyc_documents to authenticated;

-- Storage: object path must start with "{auth.uid()}/..."
drop policy if exists "kyc_documents_storage_select_own" on storage.objects;
create policy "kyc_documents_storage_select_own"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'kyc-documents'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "kyc_documents_storage_insert_own" on storage.objects;
create policy "kyc_documents_storage_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'kyc-documents'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "kyc_documents_storage_update_own" on storage.objects;
create policy "kyc_documents_storage_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'kyc-documents'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "kyc_documents_storage_delete_own" on storage.objects;
create policy "kyc_documents_storage_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'kyc-documents'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
