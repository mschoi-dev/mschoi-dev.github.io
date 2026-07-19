-- ============================================================
-- Community (member feed with images) — run AFTER setup.sql
-- Paste into Supabase Dashboard > SQL Editor > Run
-- ============================================================

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

-- Posts
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

-- Private bucket for shared images
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
