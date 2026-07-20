-- ============================================================
-- Photos (Instagram-style feed) — NON-destructive upgrade.
-- Requires: full_reset_install.sql + admin_upgrade.sql already run.
-- Paste into Supabase > SQL Editor > Run.
-- ============================================================

-- 0. Clean re-run guard (these tables are new/empty; safe to recreate)
drop table if exists public.photo_comments cascade;
drop table if exists public.photo_likes    cascade;
drop table if exists public.photo_posts    cascade;

-- 1. Photo posts (admin-only publishing)
create table public.photo_posts (
  id          bigint generated always as identity primary key,
  image_path  text not null,           -- path inside the 'photos' bucket
  caption     text,
  created_at  timestamptz not null default now()
);

alter table public.photo_posts enable row level security;

create policy "anyone can view photo posts"
  on public.photo_posts for select using (true);

create policy "admins create photo posts"
  on public.photo_posts for insert with check (public.is_admin());

create policy "admins update photo posts"
  on public.photo_posts for update using (public.is_admin());

create policy "admins delete photo posts"
  on public.photo_posts for delete using (public.is_admin());

-- 2. Likes (approved members)
create table public.photo_likes (
  photo_id    bigint not null references public.photo_posts (id) on delete cascade,
  user_id     uuid   not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (photo_id, user_id)
);

alter table public.photo_likes enable row level security;

create policy "anyone can view likes"
  on public.photo_likes for select using (true);

create policy "approved members like"
  on public.photo_likes for insert
  with check (auth.uid() = user_id and public.is_approved());

create policy "members unlike own"
  on public.photo_likes for delete using (auth.uid() = user_id);

-- 3. Comments (approved members; admin can moderate)
create table public.photo_comments (
  id          bigint generated always as identity primary key,
  photo_id    bigint not null references public.photo_posts (id) on delete cascade,
  author_id   uuid   not null references public.profiles (id) on delete cascade,
  author_name text not null,
  content     text not null check (char_length(content) between 1 and 1000),
  created_at  timestamptz not null default now()
);

alter table public.photo_comments enable row level security;

create policy "anyone can view comments"
  on public.photo_comments for select using (true);

create policy "approved members comment"
  on public.photo_comments for insert
  with check (auth.uid() = author_id and public.is_approved());

create policy "authors or admin delete comments"
  on public.photo_comments for delete
  using (auth.uid() = author_id or public.is_admin());

-- 4. Public bucket for photos, max file size 50 MB
--    (50 MB is the per-file ceiling on the Supabase free plan)
insert into storage.buckets (id, name, public, file_size_limit)
values ('photos', 'photos', true, 52428800)
on conflict (id) do update set public = true, file_size_limit = 52428800;

drop policy if exists "public read photos"   on storage.objects;
drop policy if exists "admin upload photos"  on storage.objects;
drop policy if exists "admin delete photos"  on storage.objects;

create policy "public read photos"
  on storage.objects for select using (bucket_id = 'photos');

create policy "admin upload photos"
  on storage.objects for insert
  with check (bucket_id = 'photos' and public.is_admin());

create policy "admin delete photos"
  on storage.objects for delete
  using (bucket_id = 'photos' and public.is_admin());

-- 5. Self-check
select
  to_regclass('public.photo_posts')    as photo_posts,
  to_regclass('public.photo_likes')    as photo_likes,
  to_regclass('public.photo_comments') as photo_comments,
  exists(select 1 from storage.buckets where id = 'photos' and public) as photos_bucket_public;
