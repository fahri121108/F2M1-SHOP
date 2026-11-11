-- FAHRI STORE: jalankan sekali di Supabase > SQL Editor.
-- Buat project Supabase, lalu jalankan seluruh script ini.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,role)
  values(new.id,new.email,'customer')
  on conflict(id) do update set email=excluded.email;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  price_per_100 numeric(14,2) not null default 0 check(price_per_100>=0),
  min_qty integer not null default 100 check(min_qty>0),
  max_qty integer not null default 100000 check(max_qty>=min_qty),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
insert into public.products(code,name,price_per_100,min_qty,max_qty)
values('roblox-followers','Followers Roblox Permanen',0,100,100000)
on conflict(code) do nothing;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_code text unique not null default ('FS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  user_id uuid not null references public.profiles(id),
  product_id uuid not null references public.products(id),
  roblox_username text not null,
  quantity integer not null check(quantity>0),
  total_amount numeric(14,2) not null check(total_amount>=0),
  proof_path text,
  status text not null default 'awaiting_payment' check(status in ('awaiting_payment','waiting_verification','approved','processing','done','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Harga dihitung di database, bukan mempercayai angka dari browser.
create or replace function public.create_store_order(p_product_code text,p_username text,p_quantity integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare p public.products%rowtype; new_id uuid; uid uuid;
begin
  uid:=auth.uid();
  if uid is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if length(trim(p_username))<3 or length(trim(p_username))>50 then raise exception 'Username Roblox tidak valid'; end if;
  select * into p from public.products where code=p_product_code and active=true;
  if not found then raise exception 'Produk tidak tersedia'; end if;
  if p_quantity<p.min_qty or p_quantity>p.max_qty then raise exception 'Jumlah di luar batas order'; end if;
  insert into public.orders(user_id,product_id,roblox_username,quantity,total_amount)
  values(uid,p.id,trim(p_username),p_quantity,round(p_quantity*p.price_per_100/100))
  returning id into new_id;
  return new_id;
end; $$;
grant execute on function public.create_store_order(text,text,integer) to authenticated;

create table if not exists public.claims (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  initial_followers integer not null check(initial_followers>0),
  current_followers integer not null check(current_followers>=0 and current_followers<initial_followers),
  drop_count integer generated always as (initial_followers-current_followers) stored,
  evidence_path text,
  customer_note text,
  status text not null default 'pending' check(status in ('pending','approved','rejected','warranty_processing','warranty_done')),
  admin_note text,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  title text not null,
  message text not null,
  created_at timestamptz not null default now()
);

-- Aktifkan RLS pada semua tabel.
alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.claims enable row level security;
alter table public.notifications enable row level security;

-- Helper admin: role hanya dapat diubah langsung oleh pemilik project melalui SQL.
create or replace function public.is_store_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

drop policy if exists "profiles read own or admin" on public.profiles;
create policy "profiles read own or admin" on public.profiles for select to authenticated
using(id=auth.uid() or public.is_store_admin());

drop policy if exists "products readable" on public.products;
create policy "products readable" on public.products for select to anon,authenticated using(active=true or public.is_store_admin());
drop policy if exists "admin manage products" on public.products;
create policy "admin manage products" on public.products for all to authenticated using(public.is_store_admin()) with check(public.is_store_admin());

drop policy if exists "customer reads own orders or admin" on public.orders;
create policy "customer reads own orders or admin" on public.orders for select to authenticated
using(user_id=auth.uid() or public.is_store_admin());
drop policy if exists "customer updates own payment proof" on public.orders;
create policy "customer updates own payment proof" on public.orders for update to authenticated
using(user_id=auth.uid() and status='awaiting_payment')
with check(user_id=auth.uid() and status='waiting_verification');
drop policy if exists "admin updates orders" on public.orders;
create policy "admin updates orders" on public.orders for update to authenticated
using(public.is_store_admin()) with check(public.is_store_admin());

drop policy if exists "customer reads own claims or admin" on public.claims;
create policy "customer reads own claims or admin" on public.claims for select to authenticated
using(user_id=auth.uid() or public.is_store_admin());
drop policy if exists "customer creates own claim" on public.claims;
create policy "customer creates own claim" on public.claims for insert to authenticated
with check(user_id=auth.uid() and exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid() and o.status in ('approved','processing','done')));
drop policy if exists "admin updates claims" on public.claims;
create policy "admin updates claims" on public.claims for update to authenticated
using(public.is_store_admin()) with check(public.is_store_admin());

drop policy if exists "customer reads own notifications" on public.notifications;
create policy "customer reads own notifications" on public.notifications for select to authenticated
using(user_id=auth.uid() or public.is_store_admin());
drop policy if exists "customer creates own notifications" on public.notifications;
create policy "customer creates own notifications" on public.notifications for insert to authenticated
with check(user_id=auth.uid() or public.is_store_admin());

-- Bucket privat untuk bukti pembayaran dan bukti klaim.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','application/pdf'])
on conflict(id) do nothing;

drop policy if exists "users upload own proof folder" on storage.objects;
create policy "users upload own proof folder" on storage.objects for insert to authenticated
with check(bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "users and admin read proof files" on storage.objects;
create policy "users and admin read proof files" on storage.objects for select to authenticated
using(bucket_id='payment-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_store_admin()));

-- PENTING: setelah akun admin dibuat lewat halaman Daftar, buka Authentication > Users,
-- salin UUID akun admin, lalu jalankan perintah di bawah dengan UUID milikmu:
-- update public.profiles set role='admin' where id='GANTI-DENGAN-UUID-ADMIN';
-- FAHRI STORE COMPLETE SETUP (Supabase SQL Editor)
-- Jalankan setelah setup awal Fahri Store. Jangan pernah menaruh service_role key di index.html.

-- 1. Kolom profil dan produk
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists balance bigint not null default 0;
alter table public.products add column if not exists description text;
update public.products set price_per_100 = 1666.6666667, min_qty=300,
  max_qty=greatest(coalesce(max_qty,100000),300),
  description=coalesce(description,'Followers Roblox permanen')
where code='roblox-followers';

-- 2. Tabel voucher, isi saldo, klaim (klaim dapat tanpa order website)
create table if not exists public.vouchers (
 id uuid primary key default gen_random_uuid(), code text not null unique,
 type text not null check(type in ('discount','warranty')),
 discount_amount bigint not null default 0, description text,
 max_uses integer, used_count integer not null default 0,
 expires_at timestamptz, active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.topups (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 amount bigint not null check(amount>0), proof_path text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(), reviewed_at timestamptz
);
alter table public.claims add column if not exists warranty_code text;
alter table public.claims add column if not exists roblox_username text;
alter table public.claims add column if not exists drop_count integer;
alter table public.claims add column if not exists admin_note text;
alter table public.claims alter column order_id drop not null;

-- 3. Role checker untuk RLS
create or replace function public.is_store_admin()
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;
revoke all on function public.is_store_admin() from public;
grant execute on function public.is_store_admin() to authenticated;

-- 4. RLS: profiles. Customer hanya boleh update nama dan foto, bukan role/saldo.
alter table public.profiles enable row level security;
drop policy if exists profiles_read_self_or_admin on public.profiles;
create policy profiles_read_self_or_admin on public.profiles for select to authenticated
 using(id=auth.uid() or public.is_store_admin());
drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles for insert to authenticated with check(id=auth.uid());
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
 using(id=auth.uid() or public.is_store_admin()) with check(id=auth.uid() or public.is_store_admin());
revoke update on public.profiles from anon, authenticated;
grant update(display_name,avatar_url) on public.profiles to authenticated;

-- 5. RLS katalog produk
alter table public.products enable row level security;
drop policy if exists products_public_active_read on public.products;
create policy products_public_active_read on public.products for select to anon,authenticated
 using(active=true or public.is_store_admin());
drop policy if exists products_admin_insert on public.products;
create policy products_admin_insert on public.products for insert to authenticated with check(public.is_store_admin());
drop policy if exists products_admin_update on public.products;
create policy products_admin_update on public.products for update to authenticated using(public.is_store_admin()) with check(public.is_store_admin());
drop policy if exists products_admin_delete on public.products;
create policy products_admin_delete on public.products for delete to authenticated using(public.is_store_admin());

-- 6. RLS voucher: pengguna dapat membaca voucher aktif, admin mengelola
alter table public.vouchers enable row level security;
drop policy if exists vouchers_read_active on public.vouchers;
create policy vouchers_read_active on public.vouchers for select to authenticated using(active=true or public.is_store_admin());
drop policy if exists vouchers_admin_insert on public.vouchers;
create policy vouchers_admin_insert on public.vouchers for insert to authenticated with check(public.is_store_admin());
drop policy if exists vouchers_admin_update on public.vouchers;
create policy vouchers_admin_update on public.vouchers for update to authenticated using(public.is_store_admin()) with check(public.is_store_admin());
drop policy if exists vouchers_admin_delete on public.vouchers;
create policy vouchers_admin_delete on public.vouchers for delete to authenticated using(public.is_store_admin());

-- 7. RLS topups
alter table public.topups enable row level security;
drop policy if exists topups_read_own_or_admin on public.topups;
create policy topups_read_own_or_admin on public.topups for select to authenticated using(user_id=auth.uid() or public.is_store_admin());
drop policy if exists topups_insert_own on public.topups;
create policy topups_insert_own on public.topups for insert to authenticated with check(user_id=auth.uid() and status='pending');
drop policy if exists topups_admin_update on public.topups;
create policy topups_admin_update on public.topups for update to authenticated using(public.is_store_admin()) with check(public.is_store_admin());

-- 8. RLS claims
alter table public.claims enable row level security;
drop policy if exists claims_read_own_or_admin on public.claims;
create policy claims_read_own_or_admin on public.claims for select to authenticated using(user_id=auth.uid() or public.is_store_admin());
drop policy if exists claims_insert_own on public.claims;
create policy claims_insert_own on public.claims for insert to authenticated with check(user_id=auth.uid());
drop policy if exists claims_admin_update on public.claims;
create policy claims_admin_update on public.claims for update to authenticated using(public.is_store_admin()) with check(public.is_store_admin());

-- 9. RLS notifications
alter table public.notifications enable row level security;
drop policy if exists notifications_read_own_or_admin on public.notifications;
create policy notifications_read_own_or_admin on public.notifications for select to authenticated using(user_id=auth.uid() or public.is_store_admin());
drop policy if exists notifications_insert_own_or_admin on public.notifications;
create policy notifications_insert_own_or_admin on public.notifications for insert to authenticated with check(user_id=auth.uid() or public.is_store_admin());

-- 10. Storage buckets untuk bukti pembayaran dan avatar
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','application/pdf'];
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('profile-avatars','profile-avatars',true,3145728,array['image/jpeg','image/png'])
on conflict(id) do update set public=true,file_size_limit=3145728,allowed_mime_types=array['image/jpeg','image/png'];
drop policy if exists payment_proofs_upload_own on storage.objects;
create policy payment_proofs_upload_own on storage.objects for insert to authenticated
 with check(bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists payment_proofs_read_own_or_admin on storage.objects;
create policy payment_proofs_read_own_or_admin on storage.objects for select to authenticated
 using(bucket_id='payment-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_store_admin()));
drop policy if exists payment_proofs_update_own on storage.objects;
create policy payment_proofs_update_own on storage.objects for update to authenticated
 using(bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text)
 with check(bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatars_upload_own on storage.objects;
create policy avatars_upload_own on storage.objects for insert to authenticated
 with check(bucket_id='profile-avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatars_update_own on storage.objects;
create policy avatars_update_own on storage.objects for update to authenticated
 using(bucket_id='profile-avatars' and (storage.foldername(name))[1]=auth.uid()::text)
 with check(bucket_id='profile-avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatars_public_read on storage.objects;
create policy avatars_public_read on storage.objects for select to public using(bucket_id='profile-avatars');

-- 11. Checkout QRIS / saldo, pemotongan saldo dilakukan atomik di server
create or replace function public.create_store_order_checkout(
 p_product_code text,p_username text,p_quantity integer,p_payment_method text,p_voucher_code text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare p public.products%rowtype; uid uuid; oid uuid; total bigint; v public.vouchers%rowtype;
begin
 uid:=auth.uid(); if uid is null then raise exception 'Silakan login dahulu'; end if;
 if p_payment_method not in ('qris','balance') then raise exception 'Metode pembayaran tidak valid'; end if;
 if length(trim(coalesce(p_username,'')))<3 or length(trim(p_username))>50 then raise exception 'Username Roblox tidak valid'; end if;
 select * into p from public.products where code=p_product_code and active=true;
 if not found then raise exception 'Produk tidak tersedia'; end if;
 if p_quantity<p.min_qty or p_quantity>p.max_qty then raise exception 'Jumlah di luar batas pembelian'; end if;
 total:=round(p_quantity*p.price_per_100/100);
 if p_voucher_code is not null and length(trim(p_voucher_code))>0 then
   select * into v from public.vouchers where code=upper(trim(p_voucher_code)) and type='discount' and active=true for update;
   if not found then raise exception 'Voucher promo tidak valid'; end if;
   if v.expires_at is not null and v.expires_at<now() then raise exception 'Voucher sudah kedaluwarsa'; end if;
   if v.max_uses is not null and v.used_count>=v.max_uses then raise exception 'Kuota voucher habis'; end if;
   total:=greatest(0,total-v.discount_amount);
   update public.vouchers set used_count=used_count+1 where id=v.id;
 end if;
 if p_payment_method='balance' then
   update public.profiles set balance=balance-total where id=uid and balance>=total;
   if not found then raise exception 'Saldo tidak mencukupi'; end if;
 end if;
 insert into public.orders(user_id,product_id,roblox_username,quantity,total_amount,status)
 values(uid,p.id,trim(p_username),p_quantity,total,case when p_payment_method='balance' then 'approved' else 'awaiting_payment' end)
 returning id into oid;
 return oid;
end; $$;
grant execute on function public.create_store_order_checkout(text,text,integer,text,text) to authenticated;

-- 12. Admin approve topup dan tambah saldo
create or replace function public.admin_approve_topup(p_topup_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare t public.topups%rowtype;
begin
 if not public.is_store_admin() then raise exception 'Akses admin diperlukan'; end if;
 select * into t from public.topups where id=p_topup_id for update;
 if not found then raise exception 'Permintaan isi saldo tidak ditemukan'; end if;
 if t.status<>'pending' then raise exception 'Permintaan sudah diproses'; end if;
 update public.topups set status='approved',reviewed_at=now() where id=t.id;
 update public.profiles set balance=balance+t.amount where id=t.user_id;
end; $$;
grant execute on function public.admin_approve_topup(uuid) to authenticated;
create or replace function public.admin_adjust_balance(p_user_id uuid,p_amount bigint)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_store_admin() then raise exception 'Akses admin diperlukan'; end if;
 if p_amount<=0 then raise exception 'Nominal harus lebih dari nol'; end if;
 update public.profiles set balance=balance+p_amount where id=p_user_id;
 if not found then raise exception 'Pelanggan tidak ditemukan'; end if;
end; $$;
grant execute on function public.admin_adjust_balance(uuid,bigint) to authenticated;

-- 13. Harga Followers Roblox: 300 followers = Rp5.000
update public.products set price_per_100=1666.6666667,min_qty=300,
 description=coalesce(description,'Followers Roblox permanen') where code='roblox-followers';

-- 14. Klaim garansi terverifikasi di server (tidak perlu order website)
create or replace function public.submit_store_warranty_claim(
 p_code text,p_username text,p_initial integer,p_current integer,p_evidence_path text default null,p_note text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid; v public.vouchers%rowtype; cid uuid;
begin
 uid:=auth.uid(); if uid is null then raise exception 'Silakan login dahulu'; end if;
 if length(trim(coalesce(p_username,'')))<3 or p_initial<=0 or p_current<0 or p_current>=p_initial then raise exception 'Data followers tidak valid'; end if;
 select * into v from public.vouchers where code=upper(trim(p_code)) and type='warranty' and active=true for update;
 if not found then raise exception 'Kode garansi tidak valid'; end if;
 if v.expires_at is not null and v.expires_at<now() then raise exception 'Kode garansi kedaluwarsa'; end if;
 if v.max_uses is not null and v.used_count>=v.max_uses then raise exception 'Kuota kode garansi habis'; end if;
 insert into public.claims(user_id,order_id,warranty_code,roblox_username,initial_followers,current_followers,drop_count,evidence_path,customer_note,status)
 values(uid,null,v.code,trim(p_username),p_initial,p_current,p_initial-p_current,p_evidence_path,p_note,'pending') returning id into cid;
 update public.vouchers set used_count=used_count+1 where id=v.id;
 return cid;
end; $$;
grant execute on function public.submit_store_warranty_claim(text,text,integer,integer,text,text) to authenticated;

-- 15. Rating toko
create table if not exists public.store_reviews(
 id uuid primary key default gen_random_uuid(), user_id uuid not null unique references public.profiles(id) on delete cascade,
 stars integer not null check(stars between 1 and 5), review text not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.store_reviews enable row level security;
drop policy if exists reviews_read_all_auth on public.store_reviews;
create policy reviews_read_all_auth on public.store_reviews for select to authenticated using(true);
drop policy if exists reviews_insert_own on public.store_reviews;
create policy reviews_insert_own on public.store_reviews for insert to authenticated with check(user_id=auth.uid());
drop policy if exists reviews_update_own on public.store_reviews;
create policy reviews_update_own on public.store_reviews for update to authenticated using(user_id=auth.uid() or public.is_store_admin()) with check(user_id=auth.uid() or public.is_store_admin());

-- 16. Kebijakan order dan RPC status agar pelanggan tidak dapat mengubah harga/status sesuka hati
alter table public.orders enable row level security;
drop policy if exists orders_read_own_or_admin on public.orders;
create policy orders_read_own_or_admin on public.orders for select to authenticated using(user_id=auth.uid() or public.is_store_admin());
drop policy if exists orders_insert_own_or_admin on public.orders;
create policy orders_insert_own_or_admin on public.orders for insert to authenticated with check(user_id=auth.uid() or public.is_store_admin());
drop policy if exists orders_admin_update on public.orders;
create policy orders_admin_update on public.orders for update to authenticated using(public.is_store_admin()) with check(public.is_store_admin());
revoke update on public.orders from anon,authenticated;
create or replace function public.submit_order_payment_proof(p_order_id uuid,p_proof_path text)
returns void language plpgsql security definer set search_path=public as $$
declare o public.orders%rowtype;
begin
 if auth.uid() is null then raise exception 'Silakan login'; end if;
 if split_part(p_proof_path,'/',1)<>auth.uid()::text then raise exception 'Path bukti tidak valid'; end if;
 select * into o from public.orders where id=p_order_id and user_id=auth.uid() for update;
 if not found then raise exception 'Pesanan tidak ditemukan'; end if;
 if o.status not in ('awaiting_payment','rejected') then raise exception 'Pesanan tidak dapat menerima bukti pada status ini'; end if;
 update public.orders set proof_path=p_proof_path,status='waiting_verification' where id=p_order_id;
end; $$;
grant execute on function public.submit_order_payment_proof(uuid,text) to authenticated;
create or replace function public.admin_set_order_status(p_order_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_store_admin() then raise exception 'Akses admin diperlukan'; end if;
 if p_status not in ('approved','processing','done','rejected') then raise exception 'Status tidak valid'; end if;
 update public.orders set status=p_status where id=p_order_id;
 if not found then raise exception 'Pesanan tidak ditemukan'; end if;
end; $$;
grant execute on function public.admin_set_order_status(uuid,text) to authenticated;
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

-- 17. MIGRASI PENGUATAN UPLOAD BUKTI F2M1 SHOP
-- File ini mencakup schema awal + setup toko + perbaikan upload.
alter table public.orders add column if not exists proof_path text;
alter table public.topups add column if not exists proof_path text;
alter table public.topups add column if not exists reviewed_at timestamptz;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','application/pdf'];

drop policy if exists payment_proofs_upload_own on storage.objects;
create policy payment_proofs_upload_own on storage.objects
for insert to authenticated
with check (bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists payment_proofs_update_own on storage.objects;
create policy payment_proofs_update_own on storage.objects
for update to authenticated
using (bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists payment_proofs_read_own_or_admin on storage.objects;
create policy payment_proofs_read_own_or_admin on storage.objects
for select to authenticated
using (bucket_id='payment-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_store_admin()));

alter table public.topups enable row level security;
drop policy if exists topups_read_own_or_admin on public.topups;
create policy topups_read_own_or_admin on public.topups for select to authenticated
using (user_id=auth.uid() or public.is_store_admin());
drop policy if exists topups_insert_own on public.topups;
create policy topups_insert_own on public.topups for insert to authenticated
with check (user_id=auth.uid() and status='pending');
drop policy if exists topups_admin_update on public.topups;
create policy topups_admin_update on public.topups for update to authenticated
using (public.is_store_admin()) with check (public.is_store_admin());

create or replace function public.submit_order_payment_proof(p_order_id uuid,p_proof_path text)
returns void language plpgsql security definer set search_path=public,storage as $$
declare o public.orders%rowtype; file_exists boolean;
begin
 if auth.uid() is null then raise exception 'Silakan login kembali'; end if;
 if split_part(coalesce(p_proof_path,''),'/',1)<>auth.uid()::text then raise exception 'File bukan milik akun ini'; end if;
 select exists(select 1 from storage.objects where bucket_id='payment-proofs' and name=p_proof_path) into file_exists;
 if not file_exists then raise exception 'File belum ditemukan di Storage'; end if;
 select * into o from public.orders where id=p_order_id and user_id=auth.uid() for update;
 if not found then raise exception 'Pesanan tidak ditemukan'; end if;
 if o.status not in ('awaiting_payment','waiting_verification') then raise exception 'Pesanan tidak dapat menerima bukti pada status ini'; end if;
 update public.orders set proof_path=p_proof_path,status='waiting_verification' where id=p_order_id;
end; $$;
grant execute on function public.submit_order_payment_proof(uuid,text) to authenticated;

create or replace function public.admin_set_order_status(p_order_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_store_admin() then raise exception 'Akses admin diperlukan'; end if;
 if p_status not in ('approved','processing','done','rejected') then raise exception 'Status tidak valid'; end if;
 if p_status='rejected' then
   delete from public.orders where id=p_order_id;
   if not found then raise exception 'Pesanan tidak ditemukan'; end if;
 else
   update public.orders set status=p_status where id=p_order_id;
   if not found then raise exception 'Pesanan tidak ditemukan'; end if;
 end if;
end; $$;
grant execute on function public.admin_set_order_status(uuid,text) to authenticated;
