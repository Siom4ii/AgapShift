-- Allow authenticated users (e.g. hiring businesses) to read worker profiles for
-- marketplace discovery. Own-row access remains via existing policies (combined with OR).

drop policy if exists "profiles_select_workers_directory" on public.profiles;

create policy "profiles_select_workers_directory"
  on public.profiles for select to authenticated
  using (role = 'worker');
