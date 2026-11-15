-- F2M1 SHOP ID V14 - CHAT INBOX FIX
-- Jalankan SETELAH SQL gabungan V11 dan SQL V12/V13 yang sudah dipakai selesai.
-- Backup database terlebih dahulu. Tidak menghapus data chat.

begin;

-- Indeks untuk mengambil pesan terbaru per user dan menampilkan inbox lebih cepat.
create index if not exists support_messages_user_created_v14_idx
  on public.support_messages (user_id, created_at desc);

create index if not exists support_messages_user_sender_created_v14_idx
  on public.support_messages (user_id, sender_role, created_at desc);

-- Pastikan kolom status penutupan percakapan tersedia.
alter table public.support_conversations
  add column if not exists is_closed boolean not null default false;
alter table public.support_conversations
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists support_conversations_user_id_v14_uidx
  on public.support_conversations(user_id);

-- Memastikan chat realtime tersedia jika publication Supabase aktif.
do $$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname='supabase_realtime'
         and schemaname='public' and tablename='support_messages'
     ) then
    alter publication supabase_realtime add table public.support_messages;
  end if;
exception when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';
commit;
