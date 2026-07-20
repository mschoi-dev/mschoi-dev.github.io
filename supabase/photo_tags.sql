-- Add tags to photo posts. NON-destructive, re-runnable.
alter table public.photo_posts
  add column if not exists tags text[] not null default '{}';

select column_name from information_schema.columns
where table_name = 'photo_posts' and column_name = 'tags';
