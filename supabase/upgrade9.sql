-- ============================================================
-- Upgrade 9: editable site settings (home hero/profile) +
-- post moderation (hide). NON-destructive, re-runnable.
-- ============================================================

-- 1. Site settings — single row the admin edits from settings.html
create table if not exists public.site_settings (
  id           int primary key default 1 check (id = 1),
  hero_kicker  text,
  hero_name    text,
  hero_sub     text,
  hero_desc    text,
  avatar_path  text,          -- home profile photo (avatars bucket)
  contact_email text,
  updated_at   timestamptz not null default now()
);

alter table public.site_settings enable row level security;

drop policy if exists "settings public read" on public.site_settings;
drop policy if exists "settings admin write" on public.site_settings;
create policy "settings public read" on public.site_settings for select using (true);
create policy "settings admin write" on public.site_settings for all
  using (public.is_admin()) with check (public.is_admin());

-- Seed with the current live copy (only if empty)
insert into public.site_settings (id, hero_kicker, hero_name, hero_sub, hero_desc, contact_email)
select 1, 'Engineer · Builder', 'Minseok Choi',
  '최민석 — Quantum sensor R&D at Arrakis Tech',
  'I work on quantum magnetometers by day and build practical software on the side — desktop tools, simulators, and web apps that solve real problems.',
  'minseok0640@gmail.com'
where not exists (select 1 from public.site_settings);

-- 2. Moderation: admin can HIDE community posts (kept, but invisible to members)
alter table public.community_posts add column if not exists hidden boolean not null default false;

-- Members no longer see hidden posts; admin and the author still do.
drop policy if exists "post select" on public.community_posts;
create policy "post select" on public.community_posts for select
  using (public.is_admin() or author_id = auth.uid()
         or (public.has_category_access(category_id) and not hidden));

-- Keep images/likes/comments of hidden posts locked away from members too
create or replace function public.can_view_post(p_post bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.community_posts p
    where p.id = p_post and (p.author_id = auth.uid()
      or (not p.hidden and exists (select 1 from public.community_access a
          where a.category_id = p.category_id and a.user_id = auth.uid()))));
$$;

-- 3. Self-check
select
  to_regclass('public.site_settings') as settings_table,
  (select count(*) from public.site_settings) as settings_seeded,
  exists(select 1 from information_schema.columns
         where table_name='community_posts' and column_name='hidden') as hidden_col;
