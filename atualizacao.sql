-- Atualização do Zapzap: foto de perfil e edição de mensagens.
-- Cole no SQL Editor do Supabase e clique em Run (uma única vez).

alter table public.profiles add column if not exists avatar_url text;
alter table public.messages add column if not exists edited boolean default false;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='profiles') then
    alter publication supabase_realtime add table public.profiles;
  end if;
end $$;

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;
drop policy if exists "avatars leitura" on storage.objects;
create policy "avatars leitura" on storage.objects for select using (bucket_id = 'avatars');
drop policy if exists "avatars enviar" on storage.objects;
create policy "avatars enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars atualizar" on storage.objects;
create policy "avatars atualizar" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars apagar" on storage.objects;
create policy "avatars apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
