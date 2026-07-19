-- ============================================================
-- mschoi-dev.github.io — membership & gated downloads schema
-- Paste this whole file into Supabase Dashboard > SQL Editor > Run
-- ============================================================

-- 1. Member profiles (1 row per auth user)
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

-- Users can see and edit ONLY their own profile; status is admin-only.
create policy "read own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id and status = 'pending');

create policy "update own profile (not status)"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id and status = (select p.status from public.profiles p where p.id = auth.uid()));

-- 1b. Auto-create a profile row when a user signs up.
--     Signup form sends name/country/origin/phone as user metadata.
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

-- 2. Private storage bucket for program files
insert into storage.buckets (id, name, public)
values ('downloads', 'downloads', false);

-- Only APPROVED members can download files.
create policy "approved members can download"
  on storage.objects for select
  using (
    bucket_id = 'downloads'
    and exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.status = 'approved'
    )
  );

-- 3. Download catalog (what shows on the Downloads page)
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

-- Anyone signed-in can SEE the catalog (titles), but files themselves
-- stay locked behind the storage policy above.
create policy "signed-in users can list catalog"
  on public.download_items for select
  using (auth.role() = 'authenticated' and published);
