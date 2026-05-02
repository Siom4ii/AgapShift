-- Lets the client distinguish "no account" vs "wrong password" after a failed
-- login. Called by anon (before auth). Email enumeration is a trade-off.

create or replace function public.profile_exists_for_email(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where lower(trim(p.email)) = lower(trim(p_email))
      and length(trim(coalesce(p.email, ''))) > 0
  );
$$;

grant execute on function public.profile_exists_for_email(text) to anon, authenticated;
