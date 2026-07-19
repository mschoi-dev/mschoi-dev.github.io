-- ============================================================
-- mschoi-dev.github.io — FULL RESET + INSTALL (all-in-one)
-- Safe to run repeatedly: tears down everything, then rebuilds.
-- Paste the WHOLE file into Supabase > SQL Editor > Run.
-- ============================================================

-- ---------- 0. TEAR DOWN ----------
drop trigger if exists on_auth_user_created on auth.users;

drop policy if exists "approved members can download"            on storage.objects;
drop policy if exists "approved members upload community images" on storage.objects;
drop policy if exists "approved members view community images"   on storage.objects;

drop table if exists public.community_posts cascade;
drop table if exists public.download_items  cascade;
drop table if exists public.profiles        cascade;

drop function if exists public.handle_new_user();
drop function if exists public.is_approved();

delete from storage.objects where bucket_id in ('downloads', 'community');
delete from storage.buckets  where id        in ('downloads', 'community');

-- ---------- 1. MEMBER PROFILES ----------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  full_name   text not null,
  country     text not null,
  origin      text not null,          -- 출신 (school / hometown / affiliation)
  phone       text,                   -- optional
  status      text not null default 'pending'
              check (status in ('pending', 'approved', 'blocked')),
  created_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "read own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "update own profile (not status)"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id and status = (select p.status from public.profiles p where p.id = auth.uid()));

-- Auto-create a profile row on signup (metadata comes from the signup form)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, country, origin, phone)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'country', ''),
    coalesce(new.raw_user_meta_data ->> 'origin', ''),
    nullif(new.raw_user_meta_data ->> 'phone', '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Backfill profiles for any users who signed up before this install
insert into public.profiles (id, email, full_name, country, origin, phone)
select
  u.id, u.email,
  coalesce(u.raw_user_meta_data ->> 'full_name', ''),
  coalesce(u.raw_user_meta_data ->> 'country', ''),
  coalesce(u.raw_user_meta_data ->> 'origin', ''),
  nullif(u.raw_user_meta_data ->> 'phone', '')
from auth.users u
on conflict (id) do nothing;

-- Helper: is the current user an approved member?
create or replace function public.is_approved()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'approved'
  );
$$;

-- ---------- 2. GATED DOWNLOADS ----------
insert into storage.buckets (id, name, public)
values ('downloads', 'downloads', false);

create policy "approved members can download"
  on storage.objects for select
  using (bucket_id = 'downloads' and public.is_approved());

create table public.download_items (
  id          bigint generated always as identity primary key,
  title       text not null,
  description text,
  file_path   text not null,          -- path inside the 'downloads' bucket
  version     text,
  published   boolean not null default true,
  created_at  timestamptz not null default now()
);

alter table public.download_items enable row level security;

create policy "signed-in users can list catalog"
  on public.download_items for select
  using (auth.role() = 'authenticated' and published);

-- ---------- 3. COMMUNITY ----------
create table public.community_posts (
  id          bigint generated always as identity primary key,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  author_name text not null,
  content     text not null check (char_length(content) between 1 and 2000),
  image_path  text,
  created_at  timestamptz not null default now()
);

alter table public.community_posts enable row level security;

create policy "approved members read posts"
  on public.community_posts for select
  using (public.is_approved());

create policy "approved members write own posts"
  on public.community_posts for insert
  with check (auth.uid() = author_id and public.is_approved());

create policy "authors delete own posts"
  on public.community_posts for delete
  using (auth.uid() = author_id);

insert into storage.buckets (id, name, public)
values ('community', 'community', false);

create policy "approved members upload community images"
  on storage.objects for insert
  with check (
    bucket_id = 'community'
    and public.is_approved()
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "approved members view community images"
  on storage.objects for select
  using (bucket_id = 'community' and public.is_approved());

-- ---------- 4. DONE — quick self-check ----------
select
  to_regclass('public.profiles')        as profiles_table,
  to_regclass('public.download_items')  as download_items_table,
  to_regclass('public.community_posts') as community_posts_table,
  exists(select 1 from storage.buckets where id = 'downloads') as downloads_bucket,
  exists(select 1 from storage.buckets where id = 'community') as community_bucket,
  exists(select 1 from pg_proc where proname = 'is_approved')  as is_approved_fn,
  exists(select 1 from pg_trigger where tgname = 'on_auth_user_created') as signup_trigger;
