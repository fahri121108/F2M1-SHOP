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
