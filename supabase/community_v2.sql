-- ============================================================
-- COMMUNITY V2 — secret categories, per-user access & posting,
-- multi-image posts with per-image captions, likes, comments,
-- profile avatars. Re-runnable.
-- Requires: full_reset_install.sql + admin_upgrade.sql already run.
-- ============================================================

-- 0. Drop the old (unused) community table
drop table if exists public.community_posts cascade;

-- 0b. Avatar column must exist before public_profiles() below
alter table public.profiles add column if not exists avatar_path text;

-- 1. Categories (existence hidden unless you have access)
create table if not exists public.community_categories (
  id          bigint generated always as identity primary key,
  name        text not null,
  description text,
  created_at  timestamptz not null default now()
);

-- 2. Per-user access grants (view + optional posting right)
create table if not exists public.community_access (
  category_id bigint not null references public.community_categories (id) on delete cascade,
  user_id     uuid   not null references public.profiles (id) on delete cascade,
  can_post    boolean not null default true,
  created_at  timestamptz not null default now(),
  primary key (category_id, user_id)
);

-- 3. Posts (content optional text; images optional)
create table if not exists public.community_posts (
  id          bigint generated always as identity primary key,
  category_id bigint not null references public.community_categories (id) on delete cascade,
  author_id   uuid   not null references public.profiles (id) on delete cascade,
  author_name text not null,
  content     text,
  created_at  timestamptz not null default now()
);

-- 4. Post images — each image has its own caption + order
create table if not exists public.community_post_images (
  id          bigint generated always as identity primary key,
  post_id     bigint not null references public.community_posts (id) on delete cascade,
  image_path  text not null,
  caption     text,
  position    int not null default 0
);

-- 5. Likes / comments
create table if not exists public.community_post_likes (
  post_id     bigint not null references public.community_posts (id) on delete cascade,
  user_id     uuid   not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.community_post_comments (
  id          bigint generated always as identity primary key,
  post_id     bigint not null references public.community_posts (id) on delete cascade,
  author_id   uuid   not null references public.profiles (id) on delete cascade,
  author_name text not null,
  content     text not null check (char_length(content) between 1 and 1000),
  created_at  timestamptz not null default now()
);

-- 6. Helper functions (security definer avoids RLS recursion)
create or replace function public.has_category_access(p_cat bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.community_access
    where category_id = p_cat and user_id = auth.uid());
$$;

create or replace function public.can_post_category(p_cat bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.community_access
    where category_id = p_cat and user_id = auth.uid() and can_post);
$$;

create or replace function public.can_view_post(p_post bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.community_posts p
    where p.id = p_post and (p.author_id = auth.uid()
      or exists (select 1 from public.community_access a
                 where a.category_id = p.category_id and a.user_id = auth.uid())));
$$;

create or replace function public.is_post_author(p_post bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.community_posts
                 where id = p_post and author_id = auth.uid());
$$;

-- Public mini-profile lookup (name + avatar only) for post/comment authors
create or replace function public.public_profiles(p_ids uuid[])
returns table (id uuid, full_name text, avatar_path text)
language sql stable security definer set search_path = public as $$
  select id, full_name, avatar_path from public.profiles where id = any(p_ids);
$$;
grant execute on function public.public_profiles(uuid[]) to authenticated;

-- 7. RLS
alter table public.community_categories    enable row level security;
alter table public.community_access        enable row level security;
alter table public.community_posts         enable row level security;
alter table public.community_post_images   enable row level security;
alter table public.community_post_likes    enable row level security;
alter table public.community_post_comments enable row level security;

drop policy if exists "cat select" on public.community_categories;
drop policy if exists "cat admin"  on public.community_categories;
create policy "cat select" on public.community_categories for select
  using (public.has_category_access(id));
create policy "cat admin" on public.community_categories for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "access select" on public.community_access;
drop policy if exists "access admin"  on public.community_access;
create policy "access select" on public.community_access for select
  using (user_id = auth.uid() or public.is_admin());
create policy "access admin" on public.community_access for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "post select" on public.community_posts;
drop policy if exists "post insert" on public.community_posts;
drop policy if exists "post delete" on public.community_posts;
create policy "post select" on public.community_posts for select
  using (public.is_admin() or author_id = auth.uid()
         or public.has_category_access(category_id));
create policy "post insert" on public.community_posts for insert
  with check (author_id = auth.uid() and public.is_approved()
              and public.can_post_category(category_id));
create policy "post delete" on public.community_posts for delete
  using (author_id = auth.uid() or public.is_admin());

drop policy if exists "img select" on public.community_post_images;
drop policy if exists "img insert" on public.community_post_images;
drop policy if exists "img delete" on public.community_post_images;
create policy "img select" on public.community_post_images for select
  using (public.can_view_post(post_id));
create policy "img insert" on public.community_post_images for insert
  with check (public.is_post_author(post_id) or public.is_admin());
create policy "img delete" on public.community_post_images for delete
  using (public.is_post_author(post_id) or public.is_admin());

drop policy if exists "clike select" on public.community_post_likes;
drop policy if exists "clike insert" on public.community_post_likes;
drop policy if exists "clike delete" on public.community_post_likes;
create policy "clike select" on public.community_post_likes for select
  using (user_id = auth.uid() or public.can_view_post(post_id));
create policy "clike insert" on public.community_post_likes for insert
  with check (user_id = auth.uid() and public.can_view_post(post_id));
create policy "clike delete" on public.community_post_likes for delete
  using (user_id = auth.uid());

drop policy if exists "ccom select" on public.community_post_comments;
drop policy if exists "ccom insert" on public.community_post_comments;
drop policy if exists "ccom delete" on public.community_post_comments;
create policy "ccom select" on public.community_post_comments for select
  using (author_id = auth.uid() or public.can_view_post(post_id));
create policy "ccom insert" on public.community_post_comments for insert
  with check (author_id = auth.uid() and public.is_approved()
              and public.can_view_post(post_id));
create policy "ccom delete" on public.community_post_comments for delete
  using (author_id = auth.uid() or public.is_admin());

-- 8. Storage: community bucket (exists, private) — tighten policies
drop policy if exists "approved members upload community images" on storage.objects;
drop policy if exists "approved members view community images"   on storage.objects;
drop policy if exists "community members view images"            on storage.objects;
drop policy if exists "community posters upload images"          on storage.objects;
drop policy if exists "community image owners delete"            on storage.objects;

create policy "community members view images" on storage.objects for select
  using (bucket_id = 'community' and (public.is_admin()
    or exists (select 1 from public.community_access where user_id = auth.uid())));

create policy "community posters upload images" on storage.objects for insert
  with check (bucket_id = 'community'
    and (storage.foldername(name))[1] = auth.uid()::text
    and (public.is_admin() or exists (
      select 1 from public.community_access
      where user_id = auth.uid() and can_post)));

create policy "community image owners delete" on storage.objects for delete
  using (bucket_id = 'community'
    and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text));

-- 9. Profile avatars (public bucket, own-folder upload)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "avatar public read" on storage.objects;
drop policy if exists "avatar upload own"  on storage.objects;
drop policy if exists "avatar update own"  on storage.objects;
drop policy if exists "avatar delete own"  on storage.objects;

create policy "avatar public read" on storage.objects for select
  using (bucket_id = 'avatars');
create policy "avatar upload own" on storage.objects for insert
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatar update own" on storage.objects for update
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatar delete own" on storage.objects for delete
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- 10. Self-check
select
  to_regclass('public.community_categories')    as categories,
  to_regclass('public.community_access')        as access,
  to_regclass('public.community_posts')         as posts,
  to_regclass('public.community_post_images')   as post_images,
  to_regclass('public.community_post_likes')    as likes,
  to_regclass('public.community_post_comments') as comments,
  exists(select 1 from storage.buckets where id = 'avatars' and public) as avatars_bucket,
  exists(select 1 from pg_proc where proname = 'public_profiles')       as rpc_ready;
