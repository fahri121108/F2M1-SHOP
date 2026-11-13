-- F2M1 SHOP ID: perbaiki constraint status orders tanpa menghapus data.
-- Jalankan sekali di Supabase > SQL Editor > New query.
-- Status standar website: pending, approved, processing, done, rejected.
-- Nilai status lama yang sudah tersimpan juga tetap diizinkan.

DO $$
DECLARE
  allowed_values text;
BEGIN
  -- Kumpulkan status lama yang benar-benar sudah ada, lalu gabungkan
  -- dengan semua status yang dipakai website F2M1 SHOP ID.
  SELECT string_agg(quote_literal(status_value), ', ' ORDER BY status_value)
    INTO allowed_values
  FROM (
    SELECT DISTINCT status::text AS status_value
    FROM public.orders
    WHERE status IS NOT NULL
    UNION
    SELECT unnest(ARRAY['pending','approved','processing','done','rejected'])
  ) AS statuses;

  -- Hapus hanya constraint bernama ini, bukan data atau constraint lain.
  ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;

  EXECUTE format(
    'ALTER TABLE public.orders ADD CONSTRAINT orders_status_check CHECK (status::text IN (%s))',
    allowed_values
  );
END $$;

NOTIFY pgrst, 'reload schema';
