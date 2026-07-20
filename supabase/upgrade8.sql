-- ============================================================
-- Upgrade 8: thumbnails, edit permissions, missing admin
-- policies for downloads (bug fix). NON-destructive, re-runnable.
-- ============================================================

-- 1. Thumbnail column for photos (grid uses small file, modal uses full)
alter table public.photo_posts add column if not exists thumb_path text;

-- 2. Community posts: allow authors/admin to EDIT (was missing)
drop policy if exists "post update" on public.community_posts;
create policy "post update" on public.community_posts for update
  using (author_id = auth.uid() or public.is_admin())
  with check (author_id = auth.uid() or public.is_admin());

-- 3. BUG FIX: download_items had no insert/update/delete policies,
--    so publishing files from the site would fail.
drop policy if exists "admin manages downloads" on public.download_items;
create policy "admin manages downloads" on public.download_items for all
  using (public.is_admin()) with check (public.is_admin());

-- 4. BUG FIX: downloads bucket had no upload/delete policies either.
drop policy if exists "admin uploads download files" on storage.objects;
drop policy if exists "admin deletes download files" on storage.objects;
create policy "admin uploads download files" on storage.objects for insert
  with check (bucket_id = 'downloads' and public.is_admin());
create policy "admin deletes download files" on storage.objects for delete
  using (bucket_id = 'downloads' and public.is_admin());

-- 5. Self-check
select
  exists(select 1 from information_schema.columns
         where table_name='photo_posts' and column_name='thumb_path') as thumb_col,
  exists(select 1 from pg_policies where policyname='post update')             as community_edit,
  exists(select 1 from pg_policies where policyname='admin manages downloads') as downloads_table_ok,
  exists(select 1 from pg_policies where policyname='admin uploads download files') as downloads_bucket_ok;
