-- F2M1 SHOP ID: isi title notifikasi otomatis agar insert lama tidak gagal.
-- Tidak menghapus data notifikasi.
-- Jalankan sekali di Supabase Dashboard > SQL Editor > New query.

create or replace function public.fill_notification_title()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Banyak fungsi lama hanya mengirim kolom message.
  -- Isi title dengan nilai aman jika title kosong atau tidak dikirim.
  if new.title is null or btrim(new.title) = '' then
    new.title := 'Notifikasi F2M1 SHOP';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_fill_notification_title on public.notifications;
create trigger trg_fill_notification_title
before insert on public.notifications
for each row
execute function public.fill_notification_title();

notify pgrst, 'reload schema';
