-- F2M1 SHOP - Supabase SQL setup
-- Jalankan seluruh isi file ini di Supabase Dashboard > SQL Editor.
-- Setelah akun admin dibuat, jalankan perintah UPDATE admin di bagian paling bawah.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text default '',
  role text not null default 'user' check (role in ('user','admin')),
  balance bigint not null default 0 check (balance >= 0),
  created_at timestamptz not null default now()
);
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text default 'Layanan',
  description text default '',
  price_per_unit bigint not null check(price_per_unit > 0),
  unit_label text default 'unit',
  min_qty integer not null default 1 check(min_qty > 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.vouchers (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  discount_type text not null check(discount_type in ('percent','fixed')),
  discount_value bigint not null check(discount_value > 0),
  max_uses integer,
  used_count integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  product_id uuid not null references public.products(id),
  roblox_username text not null,
  quantity integer not null check(quantity > 0),
  unit_price bigint not null,
  subtotal bigint not null,
  discount bigint not null default 0,
  total_amount bigint not null,
  payment_method text not null check(payment_method in ('qris','balance')),
  status text not null default 'pending' check(status in ('pending','process','done','rejected','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  proof_path text not null,
  amount bigint not null default 0,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);
create table if not exists public.wallet_deposits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  amount bigint not null check(amount >= 5000),
  proof_path text not null,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);
create table if not exists public.warranty_codes (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  order_id uuid references public.orders(id),
  user_id uuid references public.profiles(id),
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.warranty_claims (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  code text not null,
  roblox_username text not null,
  initial_followers integer not null,
  dropped_followers integer not null,
  origin text not null check(origin in ('website','admin')),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  order_id uuid references public.orders(id),
  rating integer not null check(rating between 1 and 5),
  comment text default '',
  visible boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  message text not null,
  created_at timestamptz not null default now()
);


-- MIGRASI KOMPATIBILITAS: menambahkan kolom yang mungkin belum ada
-- pada tabel lama. CREATE TABLE IF NOT EXISTS tidak mengubah tabel lama.
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists full_name text default '';
alter table public.profiles add column if not exists role text not null default 'user';
alter table public.profiles add column if not exists balance bigint not null default 0;
alter table public.profiles add column if not exists created_at timestamptz not null default now();

alter table public.products add column if not exists category text default 'Layanan';
alter table public.products add column if not exists description text default '';
alter table public.products add column if not exists price_per_unit bigint;
alter table public.products add column if not exists unit_label text default 'unit';
alter table public.products add column if not exists min_qty integer not null default 1;
alter table public.products add column if not exists active boolean not null default true;
alter table public.products add column if not exists created_at timestamptz not null default now();

alter table public.orders add column if not exists user_id uuid references public.profiles(id);
alter table public.orders add column if not exists product_id uuid references public.products(id);
alter table public.orders add column if not exists roblox_username text default '';
alter table public.orders add column if not exists quantity integer not null default 1;
alter table public.orders add column if not exists unit_price bigint not null default 0;
alter table public.orders add column if not exists subtotal bigint not null default 0;
alter table public.orders add column if not exists discount bigint not null default 0;
alter table public.orders add column if not exists total_amount bigint not null default 0;
alter table public.orders add column if not exists payment_method text not null default 'qris';
alter table public.orders add column if not exists status text not null default 'pending';
alter table public.orders add column if not exists created_at timestamptz not null default now();
alter table public.orders add column if not exists updated_at timestamptz not null default now();
update public.orders set payment_method='qris' where payment_method is null;
update public.orders set status='pending' where status is null;

alter table public.payments add column if not exists order_id uuid references public.orders(id) on delete cascade;
alter table public.payments add column if not exists user_id uuid references public.profiles(id);
alter table public.payments add column if not exists proof_path text default '';
alter table public.payments add column if not exists amount bigint not null default 0;
alter table public.payments add column if not exists status text not null default 'pending';
alter table public.payments add column if not exists created_at timestamptz not null default now();

alter table public.wallet_deposits add column if not exists user_id uuid references public.profiles(id);
alter table public.wallet_deposits add column if not exists amount bigint not null default 5000;
alter table public.wallet_deposits add column if not exists proof_path text default '';
alter table public.wallet_deposits add column if not exists status text not null default 'pending';
alter table public.wallet_deposits add column if not exists created_at timestamptz not null default now();

alter table public.warranty_claims add column if not exists user_id uuid references public.profiles(id);
alter table public.warranty_claims add column if not exists code text default '';
alter table public.warranty_claims add column if not exists roblox_username text default '';
alter table public.warranty_claims add column if not exists initial_followers integer not null default 0;
alter table public.warranty_claims add column if not exists dropped_followers integer not null default 1;
alter table public.warranty_claims add column if not exists origin text not null default 'website';
alter table public.warranty_claims add column if not exists status text not null default 'pending';
alter table public.warranty_claims add column if not exists created_at timestamptz not null default now();

alter table public.ratings add column if not exists user_id uuid references public.profiles(id);
alter table public.ratings add column if not exists order_id uuid references public.orders(id);
alter table public.ratings add column if not exists rating integer not null default 5;
alter table public.ratings add column if not exists comment text default '';
alter table public.ratings add column if not exists visible boolean not null default true;
alter table public.ratings add column if not exists created_at timestamptz not null default now();

alter table public.support_messages add column if not exists user_id uuid references public.profiles(id);
alter table public.support_messages add column if not exists message text default '';
alter table public.support_messages add column if not exists created_at timestamptz not null default now();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,email,full_name)
 values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',''))
 on conflict(id) do nothing;
 return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.vouchers enable row level security;
alter table public.orders enable row level security;
alter table public.payments enable row level security;
alter table public.wallet_deposits enable row level security;
alter table public.warranty_codes enable row level security;
alter table public.warranty_claims enable row level security;
alter table public.ratings enable row level security;
alter table public.support_messages enable row level security;

drop policy if exists "profile read own or admin" on public.profiles;
create policy "profile read own or admin" on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
drop policy if exists "profile update own" on public.profiles;
create policy "profile update own" on public.profiles for update to authenticated using(id=auth.uid() or public.is_admin()) with check(id=auth.uid() or public.is_admin());

drop policy if exists "products read active" on public.products;
create policy "products read active" on public.products for select to anon,authenticated using(active=true or public.is_admin());
drop policy if exists "products admin manage" on public.products;
create policy "products admin manage" on public.products for all to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists "vouchers admin manage" on public.vouchers;
create policy "vouchers admin manage" on public.vouchers for all to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists "orders read own or admin" on public.orders;
create policy "orders read own or admin" on public.orders for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "payments read own or admin" on public.payments;
create policy "payments read own or admin" on public.payments for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "payments insert own" on public.payments;
create policy "payments insert own" on public.payments for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid() and o.payment_method='qris'));
drop policy if exists "deposits read own or admin" on public.wallet_deposits;
create policy "deposits read own or admin" on public.wallet_deposits for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "deposits insert own" on public.wallet_deposits;
create policy "deposits insert own" on public.wallet_deposits for insert to authenticated with check(user_id=auth.uid() and status='pending');
drop policy if exists "warranty claims read own or admin" on public.warranty_claims;
create policy "warranty claims read own or admin" on public.warranty_claims for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "warranty claims insert own" on public.warranty_claims;
create policy "warranty claims insert own" on public.warranty_claims for insert to authenticated with check(user_id=auth.uid() and status='pending');
drop policy if exists "warranty admin update" on public.warranty_claims;
create policy "warranty admin update" on public.warranty_claims for update to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "ratings public read" on public.ratings;
create policy "ratings public read" on public.ratings for select to anon,authenticated using(visible=true or user_id=auth.uid() or public.is_admin());
drop policy if exists "support own insert" on public.support_messages;
create policy "support own insert" on public.support_messages for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "support own/admin read" on public.support_messages;
create policy "support own/admin read" on public.support_messages for select to authenticated using(user_id=auth.uid() or public.is_admin());

-- Batasi kolom profil yang boleh diubah user biasa.
revoke update on public.profiles from authenticated;
grant update(full_name) on public.profiles to authenticated;
grant select on public.profiles to authenticated;
grant select on public.products to anon,authenticated;
grant select,insert on public.payments to authenticated;
grant select,insert on public.wallet_deposits to authenticated;
grant select,insert on public.warranty_claims to authenticated;
grant select,insert on public.support_messages to authenticated;
grant select on public.orders to authenticated;
grant select on public.ratings to anon,authenticated;

create or replace function public.create_order(
 p_product_id uuid,p_roblox_username text,p_quantity integer,
 p_payment_method text,p_voucher_code text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare pr public.products%rowtype; v public.vouchers%rowtype; sub bigint; disc bigint:=0; total bigint; oid uuid;
begin
 if auth.uid() is null then raise exception 'Silakan login.'; end if;
 if length(trim(coalesce(p_roblox_username,'')))<2 then raise exception 'Username Roblox wajib diisi.'; end if;
 if p_quantity<1 then raise exception 'Jumlah tidak valid.'; end if;
 if p_payment_method not in ('qris','balance') then raise exception 'Metode pembayaran tidak valid.'; end if;
 select * into pr from public.products where id=p_product_id and active=true;
 if not found then raise exception 'Produk tidak tersedia.'; end if;
 if p_quantity<pr.min_qty then raise exception 'Jumlah minimal produk adalah %.',pr.min_qty; end if;
 sub:=pr.price_per_unit*p_quantity;
 if p_voucher_code is not null and trim(p_voucher_code)<>'' then
  select * into v from public.vouchers where upper(code)=upper(trim(p_voucher_code)) and active=true for update;
  if not found then raise exception 'Voucher tidak valid.'; end if;
  if v.max_uses is not null and v.used_count>=v.max_uses then raise exception 'Kuota voucher habis.'; end if;
  if v.discount_type='percent' then disc:=least(sub,(sub*v.discount_value)/100); else disc:=least(sub,v.discount_value); end if;
  update public.vouchers set used_count=used_count+1 where id=v.id;
 end if;
 total:=greatest(0,sub-disc);
 if p_payment_method='balance' then
  update public.profiles set balance=balance-total where id=auth.uid() and balance>=total;
  if not found then raise exception 'Saldo tidak mencukupi.'; end if;
 end if;
 insert into public.orders(user_id,product_id,roblox_username,quantity,unit_price,subtotal,discount,total_amount,payment_method,status)
 values(auth.uid(),pr.id,trim(p_roblox_username),p_quantity,pr.price_per_unit,sub,disc,total,p_payment_method,
 case when p_payment_method='balance' then 'pending' else 'pending' end) returning id into oid;
 return jsonb_build_object('order_id',oid,'total_amount',total);
end; $$;

create or replace function public.admin_set_order_status(p_order_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 if p_status not in ('process','done','rejected') then raise exception 'Status tidak valid.'; end if;
 update public.orders set status=p_status,updated_at=now() where id=p_order_id;
 if not found then raise exception 'Pesanan tidak ditemukan.'; end if;
 if p_status in ('process','done') then
  update public.payments set status='approved' where order_id=p_order_id and status='pending';
 elsif p_status='rejected' then
  update public.payments set status='rejected' where order_id=p_order_id and status='pending';
 end if;
end; $$;

create or replace function public.review_wallet_deposit(p_deposit_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path=public as $$
declare d public.wallet_deposits%rowtype;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 select * into d from public.wallet_deposits where id=p_deposit_id for update;
 if not found then raise exception 'Permintaan tidak ditemukan.'; end if;
 if d.status<>'pending' then raise exception 'Permintaan sudah diproses.'; end if;
 update public.wallet_deposits set status=case when p_approve then 'approved' else 'rejected' end where id=d.id;
 if p_approve then update public.profiles set balance=balance+d.amount where id=d.user_id; end if;
end; $$;

create or replace function public.admin_adjust_balance(p_user_id uuid,p_amount bigint)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 update public.profiles set balance=balance+p_amount where id=p_user_id and balance+p_amount>=0;
 if not found then raise exception 'Pengguna tidak ditemukan atau saldo akan negatif.'; end if;
end; $$;

grant execute on function public.create_order(uuid,text,integer,text,text) to authenticated;
grant execute on function public.admin_set_order_status(uuid,text) to authenticated;
grant execute on function public.review_wallet_deposit(uuid,boolean) to authenticated;
grant execute on function public.admin_adjust_balance(uuid,bigint) to authenticated;

-- Storage: bucket bukti pembayaran privat.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
drop policy if exists "proof upload own folder" on storage.objects;
create policy "proof upload own folder" on storage.objects for insert to authenticated
with check(bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "proof read own or admin" on storage.objects;
create policy "proof read own or admin" on storage.objects for select to authenticated
using(bucket_id='payment-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- Realtime untuk update pesanan dan saldo/deposit.
do $$ begin
 alter publication supabase_realtime add table public.orders;
exception when duplicate_object then null; when others then null; end $$;
do $$ begin
 alter publication supabase_realtime add table public.wallet_deposits;
exception when duplicate_object then null; when others then null; end $$;
do $$ begin
 alter publication supabase_realtime add table public.profiles;
exception when duplicate_object then null; when others then null; end $$;

-- CONTOH PRODUK AWAL: harga Rp5.000 per paket 300 followers.
insert into public.products(name,category,description,price_per_unit,unit_label,min_qty,active)
select 'Followers Roblox Permanen','Followers Roblox','Paket followers Roblox permanen. Proses sesuai antrean.',5000,'paket 300 followers',1,true
where not exists(select 1 from public.products where name='Followers Roblox Permanen');

-- PENTING: setelah akun admin selesai daftar, ubah email di bawah lalu jalankan:
-- update public.profiles set role='admin' where email='email-admin-kamu@contoh.com';
-- Jangan berikan role admin dari form pendaftaran publik.
