-- FIX F2M1 SHOP: kolom products.code wajib diisi pada database lama.
-- Jalankan file ini SENDIRI terlebih dahulu di Supabase SQL Editor.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'products'
      AND column_name = 'code'
  ) THEN
    EXECUTE $sql$
      ALTER TABLE public.products
      ALTER COLUMN code SET DEFAULT (
        'PRD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
      )
    $sql$;
  END IF;
END $$;

-- Pastikan produk lama yang mungkin belum memiliki kode mendapat kode otomatis.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'products'
      AND column_name = 'code'
  ) THEN
    EXECUTE $sql$
      UPDATE public.products
      SET code = 'PRD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
      WHERE code IS NULL OR btrim(code) = ''
    $sql$;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
