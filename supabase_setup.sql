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
