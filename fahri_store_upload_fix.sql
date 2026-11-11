-- Jalankan SETELAH fahri_store_complete_setup.sql di Supabase SQL Editor.
-- Perbaikan upload bukti, tampilan antrean admin, dan perilaku tombol Tolak.

-- Pastikan bucket privat tersedia dan menerima gambar/PDF.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','application/pdf'];

-- Bersihkan nama policy yang dipakai versi setup ini, lalu buat ulang.
drop policy if exists payment_proofs_upload_own on storage.objects;
create policy payment_proofs_upload_own on storage.objects
for insert to authenticated
with check (
  bucket_id='payment-proofs'
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists payment_proofs_read_own_or_admin on storage.objects;
create policy payment_proofs_read_own_or_admin on storage.objects
for select to authenticated
using (
  bucket_id='payment-proofs'
  and ((storage.foldername(name))[1]=auth.uid()::text or public.is_store_admin())
);

-- Upload hanya diterima jika file memang sudah ada di Storage dan milik pengguna.
create or replace function public.submit_order_payment_proof(p_order_id uuid,p_proof_path text)
returns void
language plpgsql security definer set search_path=public,storage as $$
declare o public.orders%rowtype; object_exists boolean;
begin
  if auth.uid() is null then raise exception 'Sesi login tidak ditemukan'; end if;
  if split_part(coalesce(p_proof_path,''),'/',1)<>auth.uid()::text then
    raise exception 'Path file bukti tidak sesuai dengan akun';
  end if;
  select exists(
    select 1 from storage.objects
    where bucket_id='payment-proofs' and name=p_proof_path
  ) into object_exists;
  if not object_exists then raise exception 'File belum berhasil tersimpan di Storage'; end if;
  select * into o from public.orders
  where id=p_order_id and user_id=auth.uid() for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if o.status not in ('awaiting_payment','waiting_verification') then
    raise exception 'Pesanan tidak dapat menerima bukti pada status ini';
  end if;
  update public.orders
  set proof_path=p_proof_path,status='waiting_verification'
  where id=p_order_id;
end;
$$;
grant execute on function public.submit_order_payment_proof(uuid,text) to authenticated;

-- Tolak = hapus pesanan dari dashboard admin dan riwayat pelanggan.
-- Status selesai tetap disimpan sebagai riwayat.
create or replace function public.admin_set_order_status(p_order_id uuid,p_status text)
returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_store_admin() then raise exception 'Akses admin diperlukan'; end if;
  if p_status not in ('approved','processing','done','rejected') then
    raise exception 'Status tidak valid';
  end if;
  if p_status='rejected' then
    delete from public.orders where id=p_order_id;
    if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  else
    update public.orders set status=p_status where id=p_order_id;
    if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  end if;
end;
$$;
grant execute on function public.admin_set_order_status(uuid,text) to authenticated;
