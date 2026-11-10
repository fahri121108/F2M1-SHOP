-- Fahri Store: dukungan katalog multi-produk dan harga Followers Roblox
-- Jalankan di Supabase > SQL Editor > New query.

alter table public.products add column if not exists description text;

-- Harga dasar proporsional: 300 followers = Rp5.000
update public.products
set price_per_100 = 1666.6666667,
    min_qty = 300,
    max_qty = greatest(coalesce(max_qty, 100000), 300),
    description = coalesce(description, 'Followers Roblox permanen')
where code = 'roblox-followers';

-- Helper aman untuk memeriksa role admin tanpa membuka tabel profiles ke publik.
create or replace function public.is_store_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.is_store_admin() from public;
grant execute on function public.is_store_admin() to authenticated;

alter table public.products enable row level security;

-- Pengunjung hanya dapat membaca produk aktif; admin dapat membaca semuanya.
drop policy if exists "products_public_active_read" on public.products;
create policy "products_public_active_read"
on public.products for select
to anon, authenticated
using (active = true or public.is_store_admin());

-- Semua perubahan katalog hanya boleh dilakukan akun admin.
drop policy if exists "products_admin_insert" on public.products;
create policy "products_admin_insert"
on public.products for insert
to authenticated
with check (public.is_store_admin());

drop policy if exists "products_admin_update" on public.products;
create policy "products_admin_update"
on public.products for update
to authenticated
using (public.is_store_admin())
with check (public.is_store_admin());

drop policy if exists "products_admin_delete" on public.products;
create policy "products_admin_delete"
on public.products for delete
to authenticated
using (public.is_store_admin());

-- Pastikan fungsi order menghitung harga dengan unit Rupiah per 100 followers.
create or replace function public.create_store_order(
  p_product_code text,
  p_username text,
  p_quantity integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.products%rowtype;
  new_id uuid;
  uid uuid;
begin
  uid := auth.uid();
  if uid is null then raise exception 'Silakan login terlebih dahulu'; end if;

  insert into public.profiles (id, email, role)
  values (uid, auth.jwt() ->> 'email', 'customer')
  on conflict (id) do nothing;

  if length(trim(coalesce(p_username, ''))) < 3 or length(trim(p_username)) > 50 then
    raise exception 'Username Roblox tidak valid';
  end if;

  select * into p from public.products
  where code = p_product_code and active = true;
  if not found then raise exception 'Produk tidak tersedia'; end if;
  if p_quantity < p.min_qty or p_quantity > p.max_qty then
    raise exception 'Jumlah di luar batas order';
  end if;
  if p.price_per_100 <= 0 then raise exception 'Harga produk belum diatur admin'; end if;

  insert into public.orders (user_id, product_id, roblox_username, quantity, total_amount)
  values (uid, p.id, trim(p_username), p_quantity,
          round(p_quantity * p.price_per_100 / 100))
  returning id into new_id;
  return new_id;
end;
$$;

grant execute on function public.create_store_order(text, text, integer) to authenticated;
