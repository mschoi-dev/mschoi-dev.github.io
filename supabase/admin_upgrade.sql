-- ============================================================
-- Admin role upgrade — NON-destructive, run after full install.
-- Adds a 'role' column, admin policies, and makes the owner admin.
-- Paste into Supabase > SQL Editor > Run.
-- ============================================================

-- 1. Role column on profiles
alter table public.profiles
  add column if not exists role text not null default 'member'
  check (role in ('member', 'admin'));

-- 2. Helper: is the current user an admin?
--    (security definer avoids RLS recursion on profiles)
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- 3. Admin policies on profiles
drop policy if exists "admins read all profiles"   on public.profiles;
drop policy if exists "admins update all profiles" on public.profiles;

create policy "admins read all profiles"
  on public.profiles for select
  using (public.is_admin());

create policy "admins update all profiles"
  on public.profiles for update
  using (public.is_admin())
  with check (public.is_admin());

-- 4. Admins can also moderate community posts
drop policy if exists "admins delete any post" on public.community_posts;
create policy "admins delete any post"
  on public.community_posts for delete
  using (public.is_admin());

-- 5. Make the site owner admin + approved
update public.profiles
set role = 'admin', status = 'approved'
where email = 'minseok0640@gmail.com';

-- 6. Self-check: shows your admin row
select email, full_name, status, role from public.profiles
where email = 'minseok0640@gmail.com';
