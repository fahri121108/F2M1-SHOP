-- F2M1 SHOP ID — Upgrade dashboard, chat, garansi, voucher, dan riwayat
-- Jalankan SEKALI di Supabase > SQL Editor > New query.
-- Tidak menghapus data. Penghapusan riwayat hanya terjadi jika admin menekan tombol hapus di dashboard.

-- Chat satu ruang antara user dan admin
create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  sender_role text not null check (sender_role in ('user','admin')),
  message text not null check (length(trim(message)) > 0),
  created_at timestamptz not null default now()
);
alter table public.support_messages enable row level security;
drop policy if exists "chat read own or admin" on public.support_messages;
create policy "chat read own or admin" on public.support_messages
 for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "chat user send" on public.support_messages;
create policy "chat user send" on public.support_messages
 for insert to authenticated with check (user_id = auth.uid() and sender_role = 'user');
drop policy if exists "chat admin reply" on public.support_messages;
create policy "chat admin reply" on public.support_messages
 for insert to authenticated with check (public.is_admin() and sender_role = 'admin');
grant select, insert on public.support_messages to authenticated;

-- Klaim garansi tervalidasi di server; cek kode, tipe, status, dan batas pemakaian.
create or replace function public.claim_warranty_with_code(
  warranty_code text, target_value text, drop_value integer,
  initial_value integer, note_value text default ''
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v public.vouchers%rowtype; new_claim uuid;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if nullif(trim(warranty_code),'') is null or nullif(trim(target_value),'') is null then
    raise exception 'Kode garansi dan tujuan wajib diisi';
  end if;
  if coalesce(drop_value,0) < 1 or coalesce(initial_value,-1) < 0 then
    raise exception 'Jumlah garansi tidak valid';
  end if;
  select * into v from public.vouchers
   where upper(trim(code)) = upper(trim(warranty_code))
   for update;
  if not found or v.type <> 'warranty' or v.active is not true then
    raise exception 'Kode garansi tidak valid atau sudah nonaktif';
  end if;
  if v.max_uses is not null and v.max_uses > 0 and v.used_count >= v.max_uses then
    raise exception 'Batas penggunaan kode garansi sudah habis';
  end if;
  insert into public.warranty_claims(user_id,voucher_id,target,drop_count,initial_count,note,status)
  values(auth.uid(),v.id,trim(target_value),drop_value,initial_value,coalesce(note_value,''),'pending')
  returning id into new_claim;
  update public.vouchers set used_count = coalesce(used_count,0) + 1 where id = v.id;
  return new_claim;
end;
$$;
grant execute on function public.claim_warranty_with_code(text,text,integer,integer,text) to authenticated;

-- User dapat menghapus riwayat pesanannya sendiri (bukan pesanan orang lain).
create or replace function public.delete_my_order_history()
returns integer language plpgsql security definer set search_path=public
as $$
declare affected integer;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  delete from public.orders where user_id = auth.uid();
  get diagnostics affected = row_count;
  return affected;
end;
$$;
grant execute on function public.delete_my_order_history() to authenticated;

-- Admin dapat memulai ulang data transaksi seluruh toko. Tidak menghapus user, saldo, produk, voucher, atau chat.
create or replace function public.admin_clear_order_history()
returns jsonb language plpgsql security definer set search_path=public
as $$
declare order_count integer; topup_count integer;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  delete from public.orders;
  get diagnostics order_count = row_count;
  delete from public.topups;
  get diagnostics topup_count = row_count;
  return jsonb_build_object('orders_deleted',order_count,'topups_deleted',topup_count);
end;
$$;
grant execute on function public.admin_clear_order_history() to authenticated;

-- Pastikan tabel chat masuk ke Supabase Realtime (aman jika sudah ada).
do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'support_messages'
  ) then
    alter publication supabase_realtime add table public.support_messages;
  end if;
exception when undefined_object then null;
end $$;

notify pgrst, 'reload schema';

-- Hapus satu riwayat milik user tanpa menghapus pesanan milik user lain.
create or replace function public.delete_my_order_history_item(order_uuid uuid)
returns boolean language plpgsql security definer set search_path=public
as $$
declare affected integer;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  delete from public.orders where id = order_uuid and user_id = auth.uid();
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;
grant execute on function public.delete_my_order_history_item(uuid) to authenticated;

notify pgrst, 'reload schema';

-- Izinkan operasi hapus pada produk/voucher; RLS admin-manage tetap membatasi ke admin.
grant delete on public.products, public.vouchers to authenticated;
notify pgrst, 'reload schema';
