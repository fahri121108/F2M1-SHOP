-- FAHRI STORE: jalankan di Supabase > SQL Editor > New query.
-- Aman dijalankan untuk memperbaiki profil pengguna lama yang belum tersinkron.

-- 1) Isi profiles untuk akun Auth yang belum mempunyai baris profil.
insert into public.profiles (id, email, role)
select u.id, u.email, 'customer'
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
on conflict (id) do nothing;

-- 2) Perbarui RPC pembuatan pesanan agar memastikan profil tersedia
--    sebelum memasukkan baris ke tabel orders.
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
  if uid is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;

  insert into public.profiles (id, email, role)
  values (uid, auth.jwt() ->> 'email', 'customer')
  on conflict (id) do nothing;

  if length(trim(coalesce(p_username, ''))) < 3
     or length(trim(p_username)) > 50 then
    raise exception 'Username Roblox tidak valid';
  end if;

  select * into p
  from public.products
  where code = p_product_code and active = true;

  if not found then
    raise exception 'Produk tidak tersedia';
  end if;

  if p_quantity < p.min_qty or p_quantity > p.max_qty then
    raise exception 'Jumlah di luar batas order';
  end if;

  if p.price_per_100 <= 0 then
    raise exception 'Harga produk belum diatur admin';
  end if;

  insert into public.orders (
    user_id, product_id, roblox_username, quantity, total_amount
  ) values (
    uid, p.id, trim(p_username), p_quantity,
    round(p_quantity * p.price_per_100 / 100)
  )
  returning id into new_id;

  return new_id;
end;
$$;

grant execute on function public.create_store_order(text, text, integer) to authenticated;

-- 3) Pastikan tabel profil tetap memakai RLS.
alter table public.profiles enable row level security;
