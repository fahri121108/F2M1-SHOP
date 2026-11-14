-- F2M1 SHOP ID V7 — PENGUMUMAN BERHALAMAN & INDEKS
-- Jalankan setelah database versi V5/V6 yang sudah digunakan toko.
-- V7 tidak mengubah tabel akun, password, order, produk, voucher, atau garansi.
-- Pengaturan konfirmasi email Supabase TIDAK bisa diubah melalui SQL ini.

-- Mempercepat pengambilan pengumuman terbaru terlebih dahulu.
CREATE INDEX IF NOT EXISTS idx_announcements_created_at_desc
ON public.announcements (created_at DESC);

-- Meminta Supabase/PostgREST memuat ulang cache skema.
NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE 'F2M1 SHOP ID V7: indeks pengumuman diperbarui. Tidak ada perubahan struktur akun atau transaksi.';
  RAISE NOTICE 'Untuk daftar tanpa verifikasi email: Supabase Dashboard > Authentication > Providers > Email > matikan Confirm email.';
END
$$;
