-- F2M1 SHOP ID — Supabase schema
-- Jalankan di Supabase SQL Editor. Jangan pernah taruh service_role key di index.html.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text,
 role text not null default 'user' check (role in ('user','admin')),
 balance bigint not null default 0 check (balance >= 0),
 created_at timestamptz not null default now()
);
create table if not exists public.products (
 id uuid primary key default gen_random_uuid(),
 name text not null, category text not null, description text default '',
 icon text default '✦', price_per_100 bigint not null check(price_per_100 > 0),
 min_qty integer not null default 100 check(min_qty > 0),
 active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.vouchers (
 id uuid primary key default gen_random_uuid(),
 code text not null unique,
 type text not null check(type in ('discount','warranty')),
 value integer not null default 0 check(value between 0 and 100),
 max_uses integer, used_count integer not null default 0,
 active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.orders (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 product_id uuid references public.products(id),
 product_name text not null, target text not null, quantity integer not null check(quantity > 0),
 amount bigint not null check(amount >= 0),
 payment_method text not null check(payment_method in ('qris','dana','balance')),
 proof_path text,
 voucher_id uuid references public.vouchers(id),
 status text not null default 'pending' check(status in ('pending','approved','processing','done','rejected')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.topups (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 amount bigint not null check(amount >= 5000),
 payment_method text not null check(payment_method in ('qris','dana')),
 proof_path text,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now()
);
create table if not exists public.support_tickets (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 subject text not null, message text not null,
 status text not null default 'pending' check(status in ('pending','processing','done')),
 created_at timestamptz not null default now()
);
create table if not exists public.warranty_claims (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 voucher_id uuid not null references public.vouchers(id),
 target text not null, drop_count integer not null check(drop_count > 0),
 initial_count integer not null check(initial_count >= 0), note text default '',
 status text not null default 'pending' check(status in ('pending','approved','processing','done','rejected')),
 created_at timestamptz not null default now()
);
create table if not exists public.announcements (
 id uuid primary key default gen_random_uuid(), message text not null,
 created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id),
 message text not null, read boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.visits (
 id bigint generated always as identity primary key, visited_on date not null default current_date
);

-- =====================================================================
-- COMPATIBILITY MIGRATION
-- create table if not exists tidak menambah kolom ke tabel lama.
-- Bagian ini memastikan semua kolom yang dipakai index.html tersedia.
-- Aman dijalankan berulang kali; data lama tidak dihapus.
-- =====================================================================

alter table public.profiles
 add column if not exists email text,
 add column if not exists role text not null default 'user',
 add column if not exists balance bigint not null default 0,
 add column if not exists created_at timestamptz not null default now();

alter table public.products
 add column if not exists name text not null default '',
 add column if not exists category text not null default 'Lainnya',
 add column if not exists description text default '',
 add column if not exists icon text not null default '✦',
 add column if not exists price_per_100 bigint not null default 1000,
 add column if not exists min_qty integer not null default 100,
 add column if not exists active boolean not null default true,
 add column if not exists created_at timestamptz not null default now();

alter table public.vouchers
 add column if not exists code text,
 add column if not exists type text not null default 'discount',
 add column if not exists value integer not null default 0,
 add column if not exists max_uses integer,
 add column if not exists used_count integer not null default 0,
 add column if not exists active boolean not null default true,
 add column if not exists created_at timestamptz not null default now();

alter table public.orders
 add column if not exists user_id uuid,
 add column if not exists product_id uuid,
 add column if not exists product_name text not null default '',
 add column if not exists target text not null default '',
 add column if not exists quantity integer not null default 1,
 add column if not exists amount bigint not null default 0,
 add column if not exists payment_method text not null default 'qris',
 add column if not exists proof_path text,
 add column if not exists voucher_id uuid,
 add column if not exists status text not null default 'pending',
 add column if not exists created_at timestamptz not null default now(),
 add column if not exists updated_at timestamptz not null default now();

alter table public.topups
 add column if not exists user_id uuid,
 add column if not exists amount bigint not null default 5000,
 add column if not exists payment_method text not null default 'qris',
 add column if not exists proof_path text,
 add column if not exists status text not null default 'pending',
 add column if not exists created_at timestamptz not null default now();

alter table public.support_tickets
 add column if not exists user_id uuid,
 add column if not exists subject text not null default '',
 add column if not exists message text not null default '',
 add column if not exists status text not null default 'pending',
 add column if not exists created_at timestamptz not null default now();

alter table public.warranty_claims
 add column if not exists user_id uuid,
 add column if not exists voucher_id uuid,
 add column if not exists target text not null default '',
 add column if not exists drop_count integer not null default 1,
 add column if not exists initial_count integer not null default 0,
 add column if not exists note text default '',
 add column if not exists status text not null default 'pending',
 add column if not exists created_at timestamptz not null default now();

alter table public.announcements
 add column if not exists message text not null default '',
 add column if not exists created_by uuid,
 add column if not exists created_at timestamptz not null default now();

alter table public.notifications
 add column if not exists user_id uuid,
 add column if not exists message text not null default '',
 add column if not exists read boolean not null default false,
 add column if not exists created_at timestamptz not null default now();

alter table public.visits
 add column if not exists visited_on date not null default current_date;

-- Pastikan PostgREST memperbarui cache kolom setelah migrasi.
notify pgrst, 'reload schema';

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin') $$;

-- Create profile automatically after signup.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.profiles(id,email) values(new.id,new.email)
 on conflict(id) do update set email=excluded.email;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Notify the owner whenever order status changes.
create or replace function public.order_status_notice()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 if new.status is distinct from old.status then
  insert into public.notifications(user_id,message)
  values(new.user_id,'Status pesanan '||left(new.id::text,8)||' berubah menjadi: '||new.status);
 end if;
 new.updated_at=now();
 return new;
end $$;
drop trigger if exists order_status_notification on public.orders;
create trigger order_status_notification before update on public.orders
for each row execute procedure public.order_status_notice();

create or replace function public.use_voucher(voucher_uuid uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
 update public.vouchers set used_count=used_count+1
 where id=voucher_uuid and active=true and (max_uses is null or used_count<max_uses);
 if not found then raise exception 'Voucher tidak tersedia'; end if;
end $$;
revoke all on function public.use_voucher(uuid) from public, anon, authenticated;

-- Hapus versi lama agar perubahan nama parameter tidak memicu error 42P13.
drop function if exists public.admin_adjust_balance(uuid, bigint);
create function public.admin_adjust_balance(target_user uuid, amount_delta bigint)
returns void language plpgsql security definer set search_path=public
as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 update public.profiles set balance=balance+amount_delta
 where id=target_user and balance+amount_delta>=0;
 if not found then raise exception 'Saldo tidak cukup atau pengguna tidak ditemukan'; end if;
 insert into public.notifications(user_id,message)
 values(target_user,'Saldo akun kamu disesuaikan sebesar '||amount_delta||' oleh admin.');
end $$;

create or replace function public.admin_review_topup(topup_uuid uuid, approve boolean)
returns void language plpgsql security definer set search_path=public
as $$
declare t public.topups%rowtype;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 select * into t from public.topups where id=topup_uuid for update;
 if not found or t.status<>'pending' then raise exception 'Permintaan tidak ditemukan / sudah diproses'; end if;
 update public.topups set status=case when approve then 'approved' else 'rejected' end where id=topup_uuid;
 if approve then update public.profiles set balance=balance+t.amount where id=t.user_id; end if;
 insert into public.notifications(user_id,message) values(t.user_id,
  case when approve then 'Isi saldo berhasil diverifikasi: +'||t.amount else 'Isi saldo ditolak admin.' end);
end $$;

create or replace function public.register_visit()
returns bigint language plpgsql security definer set search_path=public
as $$
declare total bigint;
begin
 insert into public.visits default values;
 select count(*) into total from public.visits;
 return total;
end $$;


-- Secure balance checkout: product price and voucher discount are calculated on the server.
create or replace function public.create_order_with_balance(
 product_uuid uuid, target_value text, qty_value integer, voucher_code_value text default ''
) returns uuid language plpgsql security definer set search_path=public
as $$
declare p public.products%rowtype; v public.vouchers%rowtype; final_amount bigint; new_order uuid;
begin
 if auth.uid() is null then raise exception 'Login diperlukan'; end if;
 if length(trim(target_value))=0 or qty_value<=0 then raise exception 'Data pesanan tidak valid'; end if;
 select * into p from public.products where id=product_uuid and active=true;
 if not found then raise exception 'Produk tidak tersedia'; end if;
 if qty_value<p.min_qty then raise exception 'Jumlah di bawah minimum'; end if;
 final_amount=ceil(qty_value::numeric/100*p.price_per_100);
 if length(trim(coalesce(voucher_code_value,'')))>0 then
  select * into v from public.vouchers where code=upper(trim(voucher_code_value)) and type='discount' and active=true for update;
  if not found or (v.max_uses is not null and v.used_count>=v.max_uses) then raise exception 'Voucher tidak valid'; end if;
  final_amount=greatest(0,final_amount-floor(final_amount*v.value/100));
  update public.vouchers set used_count=used_count+1 where id=v.id;
 end if;
 update public.profiles set balance=balance-final_amount where id=auth.uid() and balance>=final_amount;
 if not found then raise exception 'Saldo tidak mencukupi'; end if;
 insert into public.orders(user_id,product_id,product_name,target,quantity,amount,payment_method,voucher_id,status)
 values(auth.uid(),p.id,p.name,trim(target_value),qty_value,final_amount,'balance',case when length(trim(coalesce(voucher_code_value,'')))>0 then v.id else null end,'approved')
 returning id into new_order;
 insert into public.notifications(user_id,message) values(auth.uid(),'Pembayaran saldo berhasil. Pesanan masuk antrean admin.');
 return new_order;
end $$;
grant execute on function public.create_order_with_balance(uuid,text,integer,text) to authenticated;

-- Create a QRIS/DANA order on the server so the client cannot change its price.
create or replace function public.create_order_payment(
 product_uuid uuid,
 target_value text,
 qty_value integer,
 payment_method_value text,
 proof_path_value text,
 voucher_code_value text default ''
) returns uuid language plpgsql security definer set search_path=public
as $$
declare
 p public.products%rowtype;
 v public.vouchers%rowtype;
 final_amount bigint;
 new_order uuid;
begin
 if auth.uid() is null then raise exception 'Login diperlukan'; end if;
 if length(trim(coalesce(target_value,'')))=0 or qty_value<=0 then raise exception 'Data pesanan tidak valid'; end if;
 if payment_method_value not in ('qris','dana') then raise exception 'Metode pembayaran tidak valid'; end if;
 if coalesce(proof_path_value,'')='' or split_part(proof_path_value,'/',1)<>auth.uid()::text then
  raise exception 'Bukti pembayaran tidak valid';
 end if;
 select * into p from public.products where id=product_uuid and active=true;
 if not found then raise exception 'Produk tidak tersedia'; end if;
 if qty_value<p.min_qty then raise exception 'Jumlah di bawah minimum'; end if;
 final_amount=ceil(qty_value::numeric/100*p.price_per_100);
 if length(trim(coalesce(voucher_code_value,'')))>0 then
  select * into v from public.vouchers
   where code=upper(trim(voucher_code_value)) and type='discount' and active=true
   for update;
  if not found or (v.max_uses is not null and v.used_count>=v.max_uses) then
   raise exception 'Voucher tidak valid atau sudah habis';
  end if;
  final_amount=greatest(0,final_amount-floor(final_amount*v.value/100));
  update public.vouchers set used_count=used_count+1 where id=v.id;
 end if;
 insert into public.orders(user_id,product_id,product_name,target,quantity,amount,payment_method,proof_path,voucher_id,status)
 values(auth.uid(),p.id,p.name,trim(target_value),qty_value,final_amount,payment_method_value,proof_path_value,
  case when length(trim(coalesce(voucher_code_value,'')))>0 then v.id else null end,'pending')
 returning id into new_order;
 insert into public.notifications(user_id,message)
 values(auth.uid(),'Pesanan berhasil dikirim. Menunggu verifikasi pembayaran oleh admin.');
 return new_order;
end $$;

grant execute on function public.create_order_payment(uuid,text,integer,text,text,text) to authenticated;

-- RLS
alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.vouchers enable row level security;
alter table public.orders enable row level security;
alter table public.topups enable row level security;
alter table public.support_tickets enable row level security;
alter table public.warranty_claims enable row level security;
alter table public.announcements enable row level security;
alter table public.notifications enable row level security;
alter table public.visits enable row level security;

drop policy if exists "profile read own or admin" on public.profiles;
create policy "profile read own or admin" on public.profiles for select using(id=auth.uid() or public.is_admin());
drop policy if exists "profile update own safe fields" on public.profiles;
create policy "profile update own safe fields" on public.profiles for update using(id=auth.uid() or public.is_admin()) with check(id=auth.uid() or public.is_admin());
drop policy if exists "products public read" on public.products;
create policy "products public read" on public.products for select using(active=true or public.is_admin());
drop policy if exists "products admin manage" on public.products;
create policy "products admin manage" on public.products for all using(public.is_admin()) with check(public.is_admin());
drop policy if exists "vouchers admin manage" on public.vouchers;
create policy "vouchers admin manage" on public.vouchers for all using(public.is_admin()) with check(public.is_admin());
drop policy if exists "vouchers users read active" on public.vouchers;
create policy "vouchers users read active" on public.vouchers for select using(active=true);
drop policy if exists "orders own or admin read" on public.orders;
create policy "orders own or admin read" on public.orders for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists "orders user create" on public.orders;
revoke insert on public.orders from anon, authenticated;
drop policy if exists "orders admin update" on public.orders;
create policy "orders admin update" on public.orders for update using(public.is_admin()) with check(public.is_admin());
drop policy if exists "topups own or admin read" on public.topups;
create policy "topups own or admin read" on public.topups for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists "topups user create" on public.topups;
create policy "topups user create" on public.topups for insert with check(user_id=auth.uid() and status='pending' and (proof_path is null or split_part(proof_path,'/',1)=auth.uid()::text));
drop policy if exists "topups admin update" on public.topups;
create policy "topups admin update" on public.topups for update using(public.is_admin()) with check(public.is_admin());
drop policy if exists "tickets own or admin read" on public.support_tickets;
create policy "tickets own or admin read" on public.support_tickets for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists "tickets user create" on public.support_tickets;
create policy "tickets user create" on public.support_tickets for insert with check(user_id=auth.uid());
drop policy if exists "tickets admin update" on public.support_tickets;
create policy "tickets admin update" on public.support_tickets for update using(public.is_admin()) with check(public.is_admin());
drop policy if exists "warranty own or admin read" on public.warranty_claims;
create policy "warranty own or admin read" on public.warranty_claims for select using(user_id=auth.uid() or public.is_admin());
drop policy if exists "warranty user create" on public.warranty_claims;
create policy "warranty user create" on public.warranty_claims for insert with check(user_id=auth.uid() and status='pending');
drop policy if exists "warranty admin update" on public.warranty_claims;
create policy "warranty admin update" on public.warranty_claims for update using(public.is_admin()) with check(public.is_admin());
drop policy if exists "announcements public read" on public.announcements;
create policy "announcements public read" on public.announcements for select using(true);
drop policy if exists "announcements admin create" on public.announcements;
create policy "announcements admin create" on public.announcements for insert with check(public.is_admin());
drop policy if exists "notifications own read" on public.notifications;
create policy "notifications own read" on public.notifications for select using(user_id=auth.uid());
drop policy if exists "notifications own update" on public.notifications;
create policy "notifications own update" on public.notifications for update using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists "visits admin read" on public.visits;
create policy "visits admin read" on public.visits for select using(public.is_admin());


-- Explicit API privileges. RLS policies below remain the row-level security boundary.
grant usage on schema public to anon, authenticated;
grant select on public.products, public.announcements to anon, authenticated;
grant select, insert on public.orders to authenticated;
grant select, insert, update on public.topups to authenticated;
grant select, insert, update on public.support_tickets to authenticated;
grant select, insert, update on public.warranty_claims to authenticated;
grant select on public.vouchers to authenticated;
grant select on public.notifications to authenticated;
grant update(read) on public.notifications to authenticated;
grant select on public.profiles to authenticated;
grant insert on public.products, public.vouchers, public.announcements to authenticated;
grant update on public.products, public.orders, public.topups, public.support_tickets, public.warranty_claims, public.vouchers to authenticated;

-- Storage bucket for proof images. Keep it private; UI requests signed URLs.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
drop policy if exists "user upload own proof" on storage.objects;
create policy "user upload own proof" on storage.objects for insert to authenticated
with check(bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "user/admin read proof" on storage.objects;
create policy "user/admin read proof" on storage.objects for select to authenticated
using(bucket_id='payment-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- Seed catalog (adjust prices as needed)
insert into public.products(name,category,description,icon,price_per_100,min_qty)
select v.name,v.category,v.description,v.icon,v.price_per_100,v.min_qty
from (values
 ('Followers Roblox','Roblox','Layanan followers Roblox','🎮',5000::bigint,300),
 ('Followers Instagram','Instagram','Layanan Instagram','📸',15000::bigint,100),
 ('Followers TikTok','TikTok','Layanan TikTok','🎵',15000::bigint,100),
 ('Subscribers YouTube','YouTube','Layanan YouTube','▶️',15000::bigint,100),
 ('Followers Facebook','Facebook','Layanan Facebook','🌐',15000::bigint,100)
) as v(name,category,description,icon,price_per_100,min_qty)
where not exists (select 1 from public.products p where lower(p.name)=lower(v.name));

-- PENTING: promosikan akun admin secara manual setelah mendaftar:
-- update public.profiles set role='admin' where email='EMAIL_ADMIN_KAMU';
-- Hapus akses update langsung ke role/balance dari client. Admin saldo hanya melalui RPC.
revoke update on public.profiles from authenticated;
grant update(email) on public.profiles to authenticated;
grant execute on function public.admin_adjust_balance(uuid,bigint) to authenticated;
grant execute on function public.admin_review_topup(uuid,boolean) to authenticated;
grant execute on function public.register_visit() to anon,authenticated;


-- Aktifkan Realtime untuk tabel yang dipantau website (aman dijalankan ulang).
do $$
declare t text;
begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  foreach t in array array['orders','notifications','support_tickets','topups','warranty_claims'] loop
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
    execute format('alter publication supabase_realtime add table public.%I',t);
   end if;
  end loop;
 end if;
end $$;

-- Reload schema cache setelah seluruh objek selesai dibuat.
notify pgrst, 'reload schema';
