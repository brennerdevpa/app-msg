-- MyMsg: cole tudo no SQL Editor do Supabase e clique em Run.

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null,
  emoji text default '🙂',
  color text default '#4c8fd6',
  avatar_url text,
  last_seen timestamptz default now()
);
create table public.chats (
  id uuid primary key default gen_random_uuid(),
  name text,
  is_group boolean default false,
  created_by uuid default auth.uid() references public.profiles(id),
  created_at timestamptz default now()
);
create table public.chat_members (
  chat_id uuid references public.chats on delete cascade,
  user_id uuid references public.profiles on delete cascade,
  last_read_at timestamptz default now(),
  primary key (chat_id, user_id)
);
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles(id),
  body text not null default '' check (char_length(body) <= 4000),
  reply_to uuid references public.messages(id) on delete set null,
  edited_at timestamptz,
  deleted boolean default false,
  created_at timestamptz default now()
);
create index on public.messages (chat_id, created_at);

create function public.is_member(c uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from chat_members where chat_id = c and user_id = auth.uid())
$$;

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name, emoji, color) values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    (array['😀','😎','🦊','🐱','🌻','🚀','🐼','🍀'])[1 + floor(random()*8)::int],
    (array['#e17076','#e8883e','#4caf50','#17a2b8','#4c8fd6','#8e7bd8','#d6568f'])[1 + floor(random()*7)::int]
  );
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.create_chat(p_name text, p_members uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; me uuid := auth.uid(); grp boolean := array_length(p_members, 1) > 1;
begin
  if me is null then raise exception 'não autenticado'; end if;
  if not grp then
    select c.id into cid from chats c
    where not c.is_group
      and (select count(*) from chat_members m where m.chat_id = c.id) = 2
      and exists (select 1 from chat_members where chat_id = c.id and user_id = me)
      and exists (select 1 from chat_members where chat_id = c.id and user_id = p_members[1])
    limit 1;
    if cid is not null then return cid; end if;
  end if;
  insert into chats (name, is_group, created_by) values (case when grp then p_name end, grp, me) returning id into cid;
  insert into chat_members (chat_id, user_id) select cid, u from unnest(p_members || me) u on conflict do nothing;
  return cid;
end $$;

create function public.mark_read(p_chat uuid) returns timestamptz
language sql security definer set search_path = public as $$
  update chat_members set last_read_at = now()
  where chat_id = p_chat and user_id = auth.uid() returning last_read_at
$$;

alter table public.profiles enable row level security;
alter table public.chats enable row level security;
alter table public.chat_members enable row level security;
alter table public.messages enable row level security;

create policy "perfis visíveis" on public.profiles for select to authenticated using (true);
create policy "editar meu perfil" on public.profiles for update to authenticated using (id = auth.uid());
create policy "ver minhas conversas" on public.chats for select to authenticated using (public.is_member(id));
create policy "ver membros" on public.chat_members for select to authenticated using (public.is_member(chat_id));
create policy "ver mensagens" on public.messages for select to authenticated using (public.is_member(chat_id));
create policy "enviar mensagens" on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_member(chat_id));
create policy "apagar minhas mensagens" on public.messages for update to authenticated
  using (sender_id = auth.uid()) with check (sender_id = auth.uid());
create policy "excluir conversa" on public.chats for delete to authenticated
  using (public.is_member(id) and (not is_group or created_by = auth.uid()));

alter publication supabase_realtime add table public.messages, public.chat_members, public.chats, public.profiles;

-- fotos de perfil (Storage). Se algo daqui falhar, um aviso será emitido
-- e o resto do script continua; nesse caso crie bucket e policies no
-- Dashboard > Storage, no bucket "avatars".
do $$ begin
  insert into storage.buckets (id, name, public) values ('avatars','avatars',true) on conflict (id) do nothing;
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
