-- F2M1 SHOP ID: perbaiki order yang gagal karena kolom roblox_username wajib diisi.
-- Jalankan sekali di Supabase Dashboard > SQL Editor > New query.
-- Trigger ini mengisi roblox_username dari target secara otomatis sebelum INSERT.

create or replace function public.fill_order_roblox_username()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  row_data jsonb;
begin
  row_data := to_jsonb(NEW);

  -- Hanya berlaku jika kolom roblox_username memang ada pada tabel orders.
  if row_data ? 'roblox_username' then
    NEW := jsonb_populate_record(
      NEW,
      jsonb_build_object(
        'roblox_username',
        coalesce(
          nullif(row_data ->> 'roblox_username', ''),
          nullif(row_data ->> 'target', ''),
          'N/A'
        )
      )
    );
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_fill_orders_roblox_username on public.orders;
create trigger trg_fill_orders_roblox_username
before insert on public.orders
for each row
execute function public.fill_order_roblox_username();

-- Minta PostgREST memuat ulang metadata schema.
notify pgrst, 'reload schema';
