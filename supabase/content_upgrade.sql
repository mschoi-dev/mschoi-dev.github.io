-- ============================================================
-- Dynamic content upgrade: Notes & Projects in DB, view counts,
-- download counters, sorting support. NON-destructive, re-runnable.
-- Requires: full_reset_install.sql + admin_upgrade.sql (+ photos_upgrade.sql).
-- Paste into Supabase > SQL Editor > Run.
-- ============================================================

-- 1. Notes
create table if not exists public.notes_posts (
  id          bigint generated always as identity primary key,
  title       text not null,
  category    text not null check (category in ('journal', 'paper', 'insight', 'idea')),
  content     text not null,
  views       integer not null default 0,
  created_at  timestamptz not null default now()
);

alter table public.notes_posts enable row level security;

drop policy if exists "anyone reads notes"  on public.notes_posts;
drop policy if exists "admin inserts notes" on public.notes_posts;
drop policy if exists "admin updates notes" on public.notes_posts;
drop policy if exists "admin deletes notes" on public.notes_posts;

create policy "anyone reads notes"  on public.notes_posts for select using (true);
create policy "admin inserts notes" on public.notes_posts for insert with check (public.is_admin());
create policy "admin updates notes" on public.notes_posts for update using (public.is_admin());
create policy "admin deletes notes" on public.notes_posts for delete using (public.is_admin());

-- 2. Projects
create table if not exists public.projects_posts (
  id          bigint generated always as identity primary key,
  title       text not null,
  meta        text,                    -- e.g. "Desktop App · PySide6 · Offline"
  description text not null,
  views       integer not null default 0,
  created_at  timestamptz not null default now()
);

alter table public.projects_posts enable row level security;

drop policy if exists "anyone reads projects"  on public.projects_posts;
drop policy if exists "admin inserts projects" on public.projects_posts;
drop policy if exists "admin updates projects" on public.projects_posts;
drop policy if exists "admin deletes projects" on public.projects_posts;

create policy "anyone reads projects"  on public.projects_posts for select using (true);
create policy "admin inserts projects" on public.projects_posts for insert with check (public.is_admin());
create policy "admin updates projects" on public.projects_posts for update using (public.is_admin());
create policy "admin deletes projects" on public.projects_posts for delete using (public.is_admin());

-- 3. Counters on existing tables
alter table public.photo_posts    add column if not exists views integer not null default 0;
alter table public.download_items add column if not exists downloads_count integer not null default 0;

-- 4. Counter RPCs (security definer so anyone can bump)
create or replace function public.bump_note_views(p_id bigint)
returns void language sql security definer set search_path = public
as $$ update public.notes_posts set views = views + 1 where id = p_id; $$;

create or replace function public.bump_photo_views(p_id bigint)
returns void language sql security definer set search_path = public
as $$ update public.photo_posts set views = views + 1 where id = p_id; $$;

create or replace function public.bump_download_count(p_id bigint)
returns void language sql security definer set search_path = public
as $$ update public.download_items set downloads_count = downloads_count + 1 where id = p_id; $$;

grant execute on function public.bump_note_views(bigint),
                          public.bump_photo_views(bigint),
                          public.bump_download_count(bigint)
  to anon, authenticated;

-- 5. Seed existing content (only when tables are empty)
insert into public.notes_posts (title, category, content, created_at)
select 'This site is live', 'journal',
'Today this site went online. It started as a digital business card and portfolio, but I want it to grow into something more personal — a place that holds my work, the things I study, my experiences, and photos worth keeping.

오늘부터 이 공간에 작업물과 공부, 경험을 하나씩 쌓아갑니다.',
'2026-07-19T12:00:00+09:00'
where not exists (select 1 from public.notes_posts);

insert into public.projects_posts (title, meta, description)
select * from (values
  ('Drone Stability Test', 'Desktop App · PySide6 · Simulation',
   'A wind-stability simulator for hovering drones. Ships with presets for 8 DJI models and a real-time risk gauge.'),
  ('SynapseMap', 'Web App',
   'A relationship-mapping app that visualizes personal networks as an interactive graph, organized by closeness between people.'),
  ('FARADAY', 'Web · License Platform',
   'A distribution and licensing platform for productizing my software. Users sign up and download; an admin approval flow (pending → approved) keeps execution under control.'),
  ('Gear Studio', 'Desktop App · PySide6 · Offline',
   'A native desktop application for gear train design. Draw a circle of the size you want and Gear Studio auto-fits the module and tooth count. Supports 8 gear types, gear mating, and automatic profile-shift calculation — all fully offline.')
) as v(title, meta, description)
where not exists (select 1 from public.projects_posts);

-- 6. Self-check
select
  to_regclass('public.notes_posts')    as notes_posts,
  to_regclass('public.projects_posts') as projects_posts,
  (select count(*) from public.notes_posts)    as notes_seeded,
  (select count(*) from public.projects_posts) as projects_seeded,
  exists(select 1 from pg_proc where proname = 'bump_photo_views') as rpcs_ready;
