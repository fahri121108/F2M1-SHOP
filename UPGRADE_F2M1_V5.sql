-- F2M1 SHOP ID V5 UPDATE
-- Jalankan SETELAH SQL V4 berhasil. Backup database terlebih dahulu.
-- Fungsi hapus permanen hanya dapat dijalankan oleh admin.

-- 1) Hapus produk secara permanen. Order lama tetap disimpan; relasi produk lama
-- dilepas menjadi NULL jika kolom UUID product_id tersedia.
create or replace function public.admin_delete_product_permanently(p_product_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  fk record;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Akses admin diperlukan';
  end if;
  if not exists (select 1 from public.products where id = p_product_id) then
    raise exception 'Produk tidak ditemukan';
  end if;
  -- Lepas foreign key yang menunjuk produk agar riwayat transaksi tidak ikut terhapus.
  for fk in
    select con.conname, rel.relname as table_name, att.attname as column_name, att.attnotnull
      from pg_constraint con
      join pg_class rel on rel.oid=con.conrelid
      join pg_namespace ns on ns.oid=rel.relnamespace
      join unnest(con.conkey) with ordinality ck(attnum,ord) on true
      join pg_attribute att on att.attrelid=rel.oid and att.attnum=ck.attnum
     where con.contype='f' and con.confrelid='public.products'::regclass
       and ns.nspname='public' and cardinality(con.conkey)=1
  loop
    if not fk.attnotnull then
      execute format('update public.%I set %I = null where %I = $1',fk.table_name,fk.column_name,fk.column_name) using p_product_id;
    else
      execute format('alter table public.%I drop constraint %I',fk.table_name,fk.conname);
    end if;
  end loop;
  delete from public.products where id = p_product_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
grant execute on function public.admin_delete_product_permanently(uuid) to authenticated;

-- 2) Hapus voucher/garansi permanen. Riwayat klaim dan order tidak dihapus;
-- foreign key voucher_id dilepas agar catatan lama tetap terbaca.
create or replace function public.admin_delete_voucher_permanently(p_voucher_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  fk record;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Akses admin diperlukan';
  end if;
  if not exists (select 1 from public.vouchers where id = p_voucher_id) then
    raise exception 'Kode voucher tidak ditemukan';
  end if;
  -- Simpan klaim/order lama, lepas relasi FK voucher sebelum penghapusan permanen.
  for fk in
    select con.conname, rel.relname as table_name, att.attname as column_name, att.attnotnull
      from pg_constraint con
      join pg_class rel on rel.oid=con.conrelid
      join pg_namespace ns on ns.oid=rel.relnamespace
      join unnest(con.conkey) with ordinality ck(attnum,ord) on true
      join pg_attribute att on att.attrelid=rel.oid and att.attnum=ck.attnum
     where con.contype='f' and con.confrelid='public.vouchers'::regclass
       and ns.nspname='public' and cardinality(con.conkey)=1
  loop
    if not fk.attnotnull then
      execute format('update public.%I set %I = null where %I = $1',fk.table_name,fk.column_name,fk.column_name) using p_voucher_id;
    else
      execute format('alter table public.%I drop constraint %I',fk.table_name,fk.conname);
    end if;
  end loop;
  delete from public.vouchers where id = p_voucher_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
grant execute on function public.admin_delete_voucher_permanently(uuid) to authenticated;

-- 3) Admin hapus klaim garansi; kembalikan path agar frontend dapat menghapus file bukti.
create or replace function public.admin_delete_warranty_claim(p_claim_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_path text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Akses admin diperlukan';
  end if;
  select proof_path into v_path from public.warranty_claims where id=p_claim_id for update;
  if not found then raise exception 'Klaim garansi tidak ditemukan'; end if;
  delete from public.warranty_claims where id=p_claim_id;
  return coalesce(v_path,'');
end;
$$;
grant execute on function public.admin_delete_warranty_claim(uuid) to authenticated;

-- 4) User boleh menghapus riwayat klaim miliknya sendiri. Bukti ikut dibersihkan di frontend.
create or replace function public.delete_my_warranty_claim(p_claim_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_path text;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  select proof_path into v_path from public.warranty_claims
   where id=p_claim_id and user_id=auth.uid() for update;
  if not found then raise exception 'Klaim tidak ditemukan atau bukan milik akun ini'; end if;
  delete from public.warranty_claims where id=p_claim_id and user_id=auth.uid();
  return coalesce(v_path,'');
end;
$$;
grant execute on function public.delete_my_warranty_claim(uuid) to authenticated;

-- 5) Banyak pengumuman tetap tersimpan; penghapusan hanya melalui admin.
create or replace function public.admin_delete_announcement(p_announcement_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_count integer;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Akses admin diperlukan';
  end if;
  delete from public.announcements where id=p_announcement_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
grant execute on function public.admin_delete_announcement(uuid) to authenticated;

-- 6) Rating toko: satu rating per order yang statusnya done.
create table if not exists public.store_ratings (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  stars integer not null check (stars between 1 and 5),
  comment text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists store_ratings_created_at_idx on public.store_ratings(created_at desc);
alter table public.store_ratings enable row level security;
drop policy if exists "store ratings authenticated read" on public.store_ratings;
drop policy if exists "store ratings public read" on public.store_ratings;
create policy "store ratings public read" on public.store_ratings
  for select to anon, authenticated using (true);
revoke insert, update, delete on public.store_ratings from anon, authenticated;
grant select on public.store_ratings to anon, authenticated;

create or replace function public.submit_store_rating(
  p_order_id uuid,
  p_stars integer,
  p_comment text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_rating_id uuid;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then
    raise exception 'Rating harus antara 1 sampai 5 bintang';
  end if;
  if not exists (
    select 1 from public.orders
    where id=p_order_id and user_id=auth.uid() and status='done'
  ) then raise exception 'Rating hanya bisa diberikan untuk pesanan selesai milik akun ini'; end if;
  insert into public.store_ratings(order_id,user_id,stars,comment)
  values(p_order_id,auth.uid(),p_stars,left(coalesce(p_comment,''),500))
  returning id into v_rating_id;
  return v_rating_id;
exception when unique_violation then
  raise exception 'Pesanan ini sudah pernah diberi rating';
end;
$$;
grant execute on function public.submit_store_rating(uuid,integer,text) to authenticated;

notify pgrst, 'reload schema';
