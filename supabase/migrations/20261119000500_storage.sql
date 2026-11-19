-- =============================================================================
-- 05 · Storage buckets (Supabase Storage)
-- Public read so the website can show the files; only admins with the right
-- module can upload, replace or delete.
--   product-images  → product photos, colour photos, category images
--   banners         → hero banners (desktop + mobile), Instagram tiles
--   videos          → product videos and thumbnails
--   store-assets    → logo, favicon, theme previews
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('product-images', 'product-images', true, 10485760,  array['image/jpeg','image/png','image/webp','image/avif','image/gif']),
  ('banners',        'banners',        true, 10485760,  array['image/jpeg','image/png','image/webp','image/avif']),
  ('videos',         'videos',         true, 104857600, array['video/mp4','video/webm','video/quicktime','image/jpeg','image/png','image/webp']),
  ('store-assets',   'store-assets',   true, 5242880,   array['image/jpeg','image/png','image/webp','image/svg+xml','image/x-icon','image/vnd.microsoft.icon'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Which admin modules may manage files in each bucket.
create or replace function public.can_manage_bucket(p_bucket text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_bucket
    when 'product-images' then public.has_any_permission(array['add-product','product-list','category','sub-category','sub-sub-category']::public.admin_module[])
    when 'banners'        then public.has_any_permission(array['banners','instagram']::public.admin_module[])
    when 'videos'         then public.has_permission('videos')
    when 'store-assets'   then public.has_any_permission(array['store-details','themes']::public.admin_module[])
    else false
  end;
$$;

create policy "public read store buckets" on storage.objects for select
  using (bucket_id in ('product-images', 'banners', 'videos', 'store-assets'));

create policy "admins upload to store buckets" on storage.objects for insert to authenticated
  with check (public.can_manage_bucket(bucket_id));

create policy "admins update store buckets" on storage.objects for update to authenticated
  using (public.can_manage_bucket(bucket_id))
  with check (public.can_manage_bucket(bucket_id));

create policy "admins delete from store buckets" on storage.objects for delete to authenticated
  using (public.can_manage_bucket(bucket_id));
