-- Profile self-edit hardening: users may edit their own info,
-- but can never change their own status or role. Re-runnable.
drop policy if exists "update own profile (not status)"      on public.profiles;
drop policy if exists "update own profile (not status/role)" on public.profiles;

create policy "update own profile (not status/role)"
  on public.profiles for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    and status = (select p.status from public.profiles p where p.id = auth.uid())
    and role   = (select p.role   from public.profiles p where p.id = auth.uid())
  );

select policyname from pg_policies
where tablename = 'profiles' and cmd = 'UPDATE';
