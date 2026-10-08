-- MyMsg: atualização (foto de perfil + excluir conversa + editar mensagem).
-- Cole no SQL Editor do Supabase e clique em Run. Pode rodar mais de uma vez.

alter table public.profiles add column if not exists avatar_url text;
alter table public.messages add column if not exists edited_at timestamptz;

-- Excluir conversa: grupo só o criador, chat direto qualquer membro
do $$ begin
  create policy "excluir conversa" on public.chats for delete to authenticated
    using (public.is_member(id) and (not is_group or created_by = auth.uid()));
exception when duplicate_object then null; end $$;

-- Tempo real: chats (para a conversa sumir da tela dos outros)
-- e profiles (para a foto atualizar para os outros)
do $$ begin
  alter publication supabase_realtime add table public.chats;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.profiles;
exception when duplicate_object then null; end $$;

-- Bucket público de fotos de perfil.
-- Se algo daqui falhar, um aviso será emitido e o resto do script
-- continua normalmente; nesse caso crie bucket/policies no Dashboard > Storage.
do $$ begin
  insert into storage.buckets (id, name, public) values ('avatars','avatars',true)
    on conflict (id) do nothing;
exception when others then
  raise notice 'Aviso: bucket avatars não pôde ser criado via SQL (%). Crie no Dashboard > Storage.', sqlerrm; end $$;

do $$ begin
  create policy "enviar avatar" on storage.objects for insert to authenticated
    with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
exception when others then
  raise notice 'Aviso: crie a policy "enviar avatar" no Dashboard > Storage (%).', sqlerrm; end $$;

do $$ begin
  create policy "atualizar avatar" on storage.objects for update to authenticated
    using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
exception when others then
  raise notice 'Aviso: crie a policy "atualizar avatar" no Dashboard > Storage (%).', sqlerrm; end $$;

do $$ begin
  create policy "apagar avatar" on storage.objects for delete to authenticated
    using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
exception when others then
  raise notice 'Aviso: crie a policy "apagar avatar" no Dashboard > Storage (%).', sqlerrm; end $$;
