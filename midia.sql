-- Mídia (imagens e áudios): cole no SQL Editor do Supabase e clique em Run.
alter table public.messages add column if not exists media_path text;
alter table public.messages add column if not exists media_type text check (media_type in ('image','audio'));
alter table public.messages add column if not exists media_dur int;

-- Bucket privado: só quem participa da conversa consegue ver os arquivos (limite de 10 MB por arquivo).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', false, 10485760, array['image/*','audio/*']) on conflict (id) do nothing;
drop policy if exists "media ler" on storage.objects;
create policy "media ler" on storage.objects for select to authenticated
  using (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
drop policy if exists "media enviar" on storage.objects;
create policy "media enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
drop policy if exists "media apagar" on storage.objects;
create policy "media apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and owner_id = auth.uid()::text);
