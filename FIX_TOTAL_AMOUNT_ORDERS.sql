-- F2M1 SHOP ID: isi total_amount otomatis untuk semua jenis pesanan.
-- Penyebab: fungsi checkout mengisi kolom amount, sedangkan database lama
-- masih memiliki kolom total_amount yang NOT NULL.
-- Jalankan sekali di Supabase Dashboard > SQL Editor > New query.

create or replace function public.fill_order_total_amount()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  row_data jsonb;
  amount_value text;
begin
  row_data := to_jsonb(NEW);

  -- Ambil nominal yang sudah dihitung aman oleh fungsi checkout di server.
  amount_value := nullif(btrim(coalesce(row_data ->> 'amount', '')), '');

  -- Isi kolom lama total_amount hanya jika kolom tersebut memang ada.
  if row_data ? 'total_amount' then
    NEW := jsonb_populate_record(
      NEW,
      jsonb_build_object(
        'total_amount',
        coalesce(
          nullif(btrim(row_data ->> 'total_amount'), ''),
          amount_value,
          '0'
        )::numeric
      )
    );
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_fill_orders_total_amount on public.orders;
create trigger trg_fill_orders_total_amount
before insert on public.orders
for each row
execute function public.fill_order_total_amount();

notify pgrst, 'reload schema';
