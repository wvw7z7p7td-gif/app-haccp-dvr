-- =====================================================================
-- 0010 - Foto a testimonianza della rilevazione di temperatura
-- Percorso: <company_id>/temp/<reading_id>.jpg  (bucket privato, immutabile)
-- =====================================================================
alter table public.temp_readings
  add column photo_path text,
  add column photo_hash text,
  add constraint temp_readings_photo_pair
    check ((photo_path is null) = (photo_hash is null));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('temp-photos', 'temp-photos', false, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy temp_photos_select on storage.objects
  for select to authenticated
  using (bucket_id = 'temp-photos'
         and public.is_member(((storage.foldername(name))[1])::uuid));

create policy temp_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'temp-photos'
              and public.can_write(((storage.foldername(name))[1])::uuid));
