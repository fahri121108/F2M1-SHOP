-- =============================================================
-- F2M1 SHOP ID V16 - ROLE VIP/RESELLER, RATING PRODUK, PRESENCE
-- Jalankan SETELAH V15. Backup database sebelum migrasi.
-- Tidak menghapus tabel/data V1-V15.
-- =============================================================
begin;

-- Harga dan diskon role dikendalikan dari dashboard admin.
create table if not exists public.f2m1_role_settings (
  role text primary key check (role in ('reseller','vip')),
  price bigint not null default 0 check (price >= 0),
  discount_percent integer not null default 0 check (discount_percent between 0 and 90),
  updated_at timestamptz not null default now()
);
insert into public.f2m1_role_settings(role,price,discount_percent)
values ('reseller',5000,10),('vip',15000,20)
on conflict(role) do nothing;
alter table public.f2m1_role_settings enable row level security;
drop policy if exists f2m1_role_settings_read on public.f2m1_role_settings;
create policy f2m1_role_settings_read on public.f2m1_role_settings
 for select to anon,authenticated using (true);
drop policy if exists f2m1_role_settings_admin_write on public.f2m1_role_settings;
create policy f2m1_role_settings_admin_write on public.f2m1_role_settings
 for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Permintaan upgrade baru. Persetujuan admin langsung mengaktifkan role.
create table if not exists public.f2m1_role_upgrade_requests (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 role text not null check(role in ('reseller','vip')),
 amount bigint not null check(amount >= 0),
 payment_method text not null check(payment_method in ('qris','dana')),
 proof_path text,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references auth.users(id)
);
create index if not exists f2m1_role_upgrade_user_created_idx on public.f2m1_role_upgrade_requests(user_id,created_at desc);
create index if not exists f2m1_role_upgrade_status_created_idx on public.f2m1_role_upgrade_requests(status,created_at);
create unique index if not exists f2m1_one_pending_role_upgrade_per_user
 on public.f2m1_role_upgrade_requests(user_id) where status='pending';
alter table public.f2m1_role_upgrade_requests enable row level security;
drop policy if exists f2m1_role_upgrade_read on public.f2m1_role_upgrade_requests;
create policy f2m1_role_upgrade_read on public.f2m1_role_upgrade_requests
 for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists f2m1_role_upgrade_insert on public.f2m1_role_upgrade_requests;
create policy f2m1_role_upgrade_insert on public.f2m1_role_upgrade_requests
 for insert to authenticated with check(user_id=auth.uid() and status='pending' and role in ('reseller','vip'));
drop policy if exists f2m1_role_upgrade_admin_delete on public.f2m1_role_upgrade_requests;
create policy f2m1_role_upgrade_admin_delete on public.f2m1_role_upgrade_requests
 for delete to authenticated using(public.is_admin());

create or replace function public.f2m1_admin_review_role_upgrade(p_request_id uuid,p_approve boolean)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_role text; v_status text;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 select user_id,role,status into v_user,v_role,v_status
 from public.f2m1_role_upgrade_requests where id=p_request_id for update;
 if v_user is null then raise exception 'Permintaan tidak ditemukan.'; end if;
 if v_status<>'pending' then raise exception 'Permintaan ini sudah diproses.'; end if;
 update public.f2m1_role_upgrade_requests set status=case when p_approve then 'approved' else 'rejected' end,
 reviewed_at=now(),reviewed_by=auth.uid() where id=p_request_id;
 if p_approve then
   update public.profiles set role=v_role where id=v_user;
   insert into public.f2m1_notifications(user_id,message)
   values(v_user,'Selamat! Role akun kamu sekarang menjadi '||upper(v_role)||'. Diskon khusus dan prioritas berlaku sesuai ketentuan toko.');
 else
   insert into public.f2m1_notifications(user_id,message)
   values(v_user,'Permintaan upgrade '||upper(v_role)||' ditolak admin. Silakan hubungi CS jika perlu bantuan.');
 end if;
 return true;
end $$;
grant execute on function public.f2m1_admin_review_role_upgrade(uuid,boolean) to authenticated;

-- Setiap 10 order selesai, role user biasa otomatis menjadi subscriber/langganan.
create or replace function public.f2m1_auto_subscriber_after_order_done()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_done bigint; v_role text;
begin
 if new.status='done' and (tg_op='INSERT' or old.status is distinct from new.status) then
   select role into v_role from public.profiles where id=new.user_id;
   if coalesce(v_role,'user') in ('user','subscriber') then
     select count(*) into v_done from public.orders where user_id=new.user_id and status='done';
     if v_done>=10 then
       update public.profiles set role='subscriber' where id=new.user_id and role='user';
     end if;
   end if;
 end if;
 return new;
end $$;
drop trigger if exists f2m1_auto_subscriber_order_done on public.orders;
create trigger f2m1_auto_subscriber_order_done after insert or update of status on public.orders
 for each row execute function public.f2m1_auto_subscriber_after_order_done();

-- Rating tetap memakai store_ratings yang sudah ada, ditautkan ke produk/order.
alter table public.store_ratings add column if not exists product_id uuid;
do $$ begin
 if exists(select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='product_id') then
   update public.store_ratings r set product_id=o.product_id from public.orders o where o.id=r.order_id and r.product_id is null;
 end if;
end $$;
create index if not exists store_ratings_product_id_idx on public.store_ratings(product_id);
create or replace function public.f2m1_attach_product_to_rating()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.product_id is null then
   select product_id into new.product_id from public.orders where id=new.order_id;
 end if;
 return new;
end $$;
drop trigger if exists f2m1_attach_product_to_rating on public.store_ratings;
create trigger f2m1_attach_product_to_rating before insert or update of order_id on public.store_ratings
 for each row execute function public.f2m1_attach_product_to_rating();

-- Status admin online/offline berdasarkan heartbeat; online jika ping <90 detik.
create table if not exists public.f2m1_admin_presence (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 is_online boolean not null default false,
 last_seen_at timestamptz not null default now()
);
alter table public.f2m1_admin_presence enable row level security;
drop policy if exists f2m1_admin_presence_read on public.f2m1_admin_presence;
create policy f2m1_admin_presence_read on public.f2m1_admin_presence
 for select to anon,authenticated using(true);
drop policy if exists f2m1_admin_presence_own_write on public.f2m1_admin_presence;
create policy f2m1_admin_presence_own_write on public.f2m1_admin_presence
 for insert to authenticated with check(user_id=auth.uid());
drop policy if exists f2m1_admin_presence_own_update on public.f2m1_admin_presence;
create policy f2m1_admin_presence_own_update on public.f2m1_admin_presence
 for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

-- View posisi antrean pribadi per akun (hanya order pending/approved).
create or replace view public.f2m1_user_order_queue as
select id,user_id,status,created_at,
 row_number() over(partition by user_id order by created_at asc,id asc) as user_queue_position
from public.orders where status in ('pending','approved');
grant select on public.f2m1_user_order_queue to authenticated;


-- Harga upgrade diambil dari tabel setting server, bukan nilai dari browser.
create or replace function public.f2m1_validate_role_upgrade_request()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_price bigint; v_role text;
begin
 if auth.uid() is null or new.user_id<>auth.uid() then raise exception 'Akun tidak valid.'; end if;
 select role into v_role from public.profiles where id=new.user_id;
 if coalesce(v_role,'user') in ('reseller','vip','admin') then raise exception 'Akun sudah memiliki role khusus.'; end if;
 select price into v_price from public.f2m1_role_settings where role=new.role;
 if v_price is null then raise exception 'Harga role belum diatur admin.'; end if;
 if coalesce(new.proof_path,'')='' or split_part(new.proof_path,'/',1)<>auth.uid()::text then raise exception 'Bukti pembayaran tidak valid.'; end if;
 new.amount:=v_price;
 return new;
end $$;
drop trigger if exists f2m1_validate_role_upgrade_request on public.f2m1_role_upgrade_requests;
create trigger f2m1_validate_role_upgrade_request before insert on public.f2m1_role_upgrade_requests
 for each row execute function public.f2m1_validate_role_upgrade_request();

-- Terapkan diskon reseller/VIP di sisi database untuk semua jenis pembayaran.
create or replace function public.create_order_with_balance(
 product_uuid uuid, target_value text, qty_value integer, voucher_code_value text default ''
) returns uuid language plpgsql security definer set search_path=public as $$
declare p public.products%rowtype; v public.vouchers%rowtype; final_amount bigint; new_order uuid; role_value text; disc integer:=0; controls_reason text;
begin
 if auth.uid() is null then raise exception 'Login diperlukan'; end if;
 if exists(select 1 from public.f2m1_store_controls where id=1 and maintenance_enabled=true) and not public.is_admin() then
   select maintenance_reason into controls_reason from public.f2m1_store_controls where id=1; raise exception 'Toko sedang maintenance: %',coalesce(controls_reason,'transaksi dihentikan'); end if;
 if exists(select 1 from public.profiles where id=auth.uid() and banned=true) and not public.is_admin() then raise exception 'Akun dibatasi. Hubungi CS.'; end if;
 if length(trim(coalesce(target_value,'')))=0 or qty_value<=0 then raise exception 'Data pesanan tidak valid'; end if;
 select * into p from public.products where id=product_uuid and active=true;
 if not found then raise exception 'Produk tidak tersedia'; end if;
 if qty_value<p.min_qty then raise exception 'Jumlah di bawah minimum'; end if;
 final_amount=ceil(qty_value::numeric/100*p.price_per_100);
 select role into role_value from public.profiles where id=auth.uid();
 if role_value in ('reseller','vip') then select discount_percent into disc from public.f2m1_role_settings where role=role_value; final_amount=greatest(0,final_amount-floor(final_amount*coalesce(disc,case when role_value='vip' then 20 else 10 end)/100));
 elsif role_value='subscriber' then final_amount=greatest(0,final_amount-floor(final_amount*0.02)); end if;
 if length(trim(coalesce(voucher_code_value,'')))>0 then
  select * into v from public.vouchers where code=upper(trim(voucher_code_value)) and type='discount' and active=true for update;
  if not found or (v.max_uses is not null and v.used_count>=v.max_uses) then raise exception 'Voucher tidak valid'; end if;
  final_amount=greatest(0,final_amount-floor(final_amount*v.value/100)); update public.vouchers set used_count=used_count+1 where id=v.id;
 end if;
 update public.profiles set balance=balance-final_amount where id=auth.uid() and balance>=final_amount;
 if not found then raise exception 'Saldo tidak mencukupi'; end if;
 insert into public.orders(user_id,product_id,product_name,target,quantity,amount,payment_method,voucher_id,status)
 values(auth.uid(),p.id,p.name,trim(target_value),qty_value,final_amount,'balance',case when length(trim(coalesce(voucher_code_value,'')))>0 then v.id else null end,'approved') returning id into new_order;
 insert into public.notifications(user_id,title,message) values(auth.uid(),'Pesanan dibuat','Pembayaran saldo berhasil. Pesanan masuk antrean admin.');
 return new_order;
end $$;
grant execute on function public.create_order_with_balance(uuid,text,integer,text) to authenticated;

create or replace function public.create_order_payment(
 product_uuid uuid, target_value text, qty_value integer,
 payment_method_value text, proof_path_value text, voucher_code_value text default ''
) returns uuid language plpgsql security definer set search_path=public as $$
declare p public.products%rowtype; v public.vouchers%rowtype; final_amount bigint; new_order uuid; role_value text; disc integer:=0; controls_reason text;
begin
 if auth.uid() is null then raise exception 'Login diperlukan'; end if;
 if exists(select 1 from public.f2m1_store_controls where id=1 and maintenance_enabled=true) and not public.is_admin() then
   select maintenance_reason into controls_reason from public.f2m1_store_controls where id=1; raise exception 'Toko sedang maintenance: %',coalesce(controls_reason,'transaksi dihentikan'); end if;
 if exists(select 1 from public.profiles where id=auth.uid() and banned=true) and not public.is_admin() then raise exception 'Akun dibatasi. Hubungi CS.'; end if;
 if length(trim(coalesce(target_value,'')))=0 or qty_value<=0 then raise exception 'Data pesanan tidak valid'; end if;
 if payment_method_value not in ('qris','dana') then raise exception 'Metode pembayaran tidak valid'; end if;
 if coalesce(proof_path_value,'')='' or split_part(proof_path_value,'/',1)<>auth.uid()::text then raise exception 'Bukti pembayaran tidak valid'; end if;
 select * into p from public.products where id=product_uuid and active=true;
 if not found then raise exception 'Produk tidak tersedia'; end if;
 if qty_value<p.min_qty then raise exception 'Jumlah di bawah minimum'; end if;
 final_amount=ceil(qty_value::numeric/100*p.price_per_100);
 select role into role_value from public.profiles where id=auth.uid();
 if role_value in ('reseller','vip') then select discount_percent into disc from public.f2m1_role_settings where role=role_value; final_amount=greatest(0,final_amount-floor(final_amount*coalesce(disc,case when role_value='vip' then 20 else 10 end)/100));
 elsif role_value='subscriber' then final_amount=greatest(0,final_amount-floor(final_amount*0.02)); end if;
 if length(trim(coalesce(voucher_code_value,'')))>0 then
  select * into v from public.vouchers where code=upper(trim(voucher_code_value)) and type='discount' and active=true for update;
  if not found or (v.max_uses is not null and v.used_count>=v.max_uses) then raise exception 'Voucher tidak valid atau sudah habis'; end if;
  final_amount=greatest(0,final_amount-floor(final_amount*v.value/100)); update public.vouchers set used_count=used_count+1 where id=v.id;
 end if;
 insert into public.orders(user_id,product_id,product_name,target,quantity,amount,payment_method,proof_path,voucher_id,status)
 values(auth.uid(),p.id,p.name,trim(target_value),qty_value,final_amount,payment_method_value,proof_path_value,
 case when length(trim(coalesce(voucher_code_value,'')))>0 then v.id else null end,'pending') returning id into new_order;
 insert into public.notifications(user_id,title,message) values(auth.uid(),'Pesanan dikirim','Pesanan berhasil dikirim. Menunggu verifikasi pembayaran admin.');
 return new_order;
end $$;
grant execute on function public.create_order_payment(uuid,text,integer,text,text,text) to authenticated;

update public.profiles p set role='subscriber' where p.role='user' and (select count(*) from public.orders o where o.user_id=p.id and o.status='done')>=10;

notify pgrst,'reload schema';
commit;
