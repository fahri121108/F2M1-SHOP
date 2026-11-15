-- F2M1 SHOP ID V12 - PERBAIKAN CHAT, REFERRAL NAVIGATION & NOTIFICATION SUPPORT
-- Jalankan SETELAH SQL gabungan V11 berhasil dipasang.
-- Backup database terlebih dahulu. SQL ini bersifat tambahan (tidak menghapus data).

begin;

-- Mempercepat pengambilan pesan terakhir per pengguna untuk daftar chat admin.
create index if not exists support_messages_user_created_v12_idx
  on public.support_messages(user_id, created_at desc);
create index if not exists support_messages_user_sender_created_v12_idx
  on public.support_messages(user_id, sender_role, created_at desc);

-- Kolom reply_to_id dibuat pada V9. Pastikan ada tanpa mengubah data lama.
alter table public.support_messages
  add column if not exists reply_to_id uuid;

-- Realtime sudah diaktifkan oleh V11; reload schema untuk perubahan tambahan.
notify pgrst, 'reload schema';
commit;
