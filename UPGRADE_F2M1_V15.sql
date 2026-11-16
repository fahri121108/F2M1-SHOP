-- ============================================================
-- F2M1 SHOP ID V15 - UANG GRATIS / CHAT EARNING
-- Jalankan SETELAH seluruh migrasi yang saat ini sudah dipakai
-- (termasuk V14) berhasil. Backup Supabase terlebih dahulu.
-- Tidak menghapus data versi sebelumnya.
--
-- Model verifikasi: admin memverifikasi jumlah chat valid dan memasukkan
-- jumlahnya saat ACC. Kredit = jumlah chat x Rp700, hanya satu kali.
-- Jangan meminta OTP / kode pairing perangkat WhatsApp pengguna.
-- Integrasi pesan WhatsApp otomatis memerlukan WhatsApp Business Platform
-- resmi dan backend webhook tersendiri.
-- ============================================================

begin;

create table if not exists public.f2m1_chat_earning_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  whatsapp_number text not null,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  valid_chats bigint not null default 0 check (valid_chats >= 0),
  rate_per_chat bigint not null default 700 check (rate_per_chat = 700),
  credited_amount bigint not null default 0 check (credited_amount >= 0),
  admin_note text not null default '',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create index if not exists f2m1_earning_requests_user_created_idx
  on public.f2m1_chat_earning_requests(user_id, created_at desc);
create index if not exists f2m1_earning_requests_status_created_idx
  on public.f2m1_chat_earning_requests(status, created_at desc);
create unique index if not exists f2m1_earning_one_pending_per_user
  on public.f2m1_chat_earning_requests(user_id) where status='pending';

create table if not exists public.f2m1_chat_earning_wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  balance bigint not null default 0 check (balance >= 0),
  total_valid_chats bigint not null default 0 check (total_valid_chats >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.f2m1_chat_earning_messages (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.f2m1_chat_earning_requests(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  sender_role text not null check (sender_role in ('user','admin')),
  message text not null check (length(trim(message)) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists f2m1_earning_messages_request_created_idx
  on public.f2m1_chat_earning_messages(request_id, created_at asc);

create table if not exists public.f2m1_chat_earning_withdrawals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount >= 20000),
  method text not null check (method in ('DANA','GoPay','SeaBank')),
  account_name text not null,
  account_number text not null,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create index if not exists f2m1_earning_withdrawals_user_created_idx
  on public.f2m1_chat_earning_withdrawals(user_id, created_at desc);
create index if not exists f2m1_earning_withdrawals_status_created_idx
  on public.f2m1_chat_earning_withdrawals(status, created_at desc);

alter table public.f2m1_chat_earning_requests enable row level security;
alter table public.f2m1_chat_earning_wallets enable row level security;
alter table public.f2m1_chat_earning_messages enable row level security;
alter table public.f2m1_chat_earning_withdrawals enable row level security;

drop policy if exists f2m1_earning_requests_read on public.f2m1_chat_earning_requests;
create policy f2m1_earning_requests_read on public.f2m1_chat_earning_requests
  for select to authenticated using (user_id=auth.uid() or public.is_admin());

drop policy if exists f2m1_earning_wallet_read on public.f2m1_chat_earning_wallets;
create policy f2m1_earning_wallet_read on public.f2m1_chat_earning_wallets
  for select to authenticated using (user_id=auth.uid() or public.is_admin());

drop policy if exists f2m1_earning_messages_read on public.f2m1_chat_earning_messages;
create policy f2m1_earning_messages_read on public.f2m1_chat_earning_messages
  for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists f2m1_earning_messages_insert on public.f2m1_chat_earning_messages;
create policy f2m1_earning_messages_insert on public.f2m1_chat_earning_messages
  for insert to authenticated with check (
    (sender_role='user' and user_id=auth.uid() and exists (
      select 1 from public.f2m1_chat_earning_requests r
      where r.id=request_id and r.user_id=auth.uid()
    ))
    or (sender_role='admin' and public.is_admin() and exists (
      select 1 from public.f2m1_chat_earning_requests r
      where r.id=request_id and r.user_id=f2m1_chat_earning_messages.user_id
    ))
  );

drop policy if exists f2m1_earning_withdrawals_read on public.f2m1_chat_earning_withdrawals;
create policy f2m1_earning_withdrawals_read on public.f2m1_chat_earning_withdrawals
  for select to authenticated using (user_id=auth.uid() or public.is_admin());

-- User mengirim nomor WhatsApp. Satu permintaan pending per user.
create or replace function public.f2m1_submit_chat_earning_request(p_whatsapp_number text)
returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_number text;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu.'; end if;
  v_number := regexp_replace(coalesce(p_whatsapp_number,''),'[^0-9]','','g');
  if v_number !~ '^62[0-9]{8,13}$' then
    raise exception 'Nomor WhatsApp harus menggunakan format internasional 62xxxxxxxxxx.';
  end if;
  if exists(select 1 from public.f2m1_chat_earning_requests
            where user_id=auth.uid() and status='pending') then
    raise exception 'Kamu masih memiliki permintaan yang menunggu admin.';
  end if;
  insert into public.f2m1_chat_earning_requests(user_id,whatsapp_number)
  values(auth.uid(),v_number) returning id into v_id;
  insert into public.f2m1_chat_earning_wallets(user_id)
  values(auth.uid()) on conflict(user_id) do nothing;
  insert into public.f2m1_admin_notifications(message)
  values('Permintaan UANG GRATIS baru dari user '||auth.uid()::text||'.');
  return v_id;
end;
$$;
grant execute on function public.f2m1_submit_chat_earning_request(text) to authenticated;

-- Admin memutuskan permintaan. Kredit dan jumlah chat disimpan atomik,
-- dan permintaan yang sudah diproses tidak dapat dikreditkan ulang.
create or replace function public.f2m1_admin_review_chat_earning_request(
  p_request_id uuid,
  p_approve boolean,
  p_valid_chats bigint default 0,
  p_admin_note text default ''
) returns boolean
language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_status text; v_credit bigint; v_chats bigint;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
  if coalesce(p_valid_chats,0)<0 then raise exception 'Jumlah chat tidak boleh negatif.'; end if;
  select user_id,status into v_user,v_status
    from public.f2m1_chat_earning_requests where id=p_request_id for update;
  if v_user is null then raise exception 'Permintaan tidak ditemukan.'; end if;
  if v_status<>'pending' then raise exception 'Permintaan sudah pernah diproses.'; end if;
  v_chats := case when p_approve then coalesce(p_valid_chats,0) else 0 end;
  v_credit := v_chats * 700;
  update public.f2m1_chat_earning_requests
    set status=case when p_approve then 'approved' else 'rejected' end,
        valid_chats=v_chats, credited_amount=v_credit,
        admin_note=coalesce(p_admin_note,''), reviewed_at=now()
    where id=p_request_id;
  insert into public.f2m1_chat_earning_wallets(user_id,balance,total_valid_chats,updated_at)
    values(v_user,v_credit,v_chats,now())
    on conflict(user_id) do update set
      balance=public.f2m1_chat_earning_wallets.balance+excluded.balance,
      total_valid_chats=public.f2m1_chat_earning_wallets.total_valid_chats+excluded.total_valid_chats,
      updated_at=now();
  insert into public.f2m1_notifications(user_id,message)
    values(v_user,case when p_approve
      then 'Permintaan UANG GRATIS disetujui: '||v_chats::text||' chat valid. Saldo bertambah Rp'||to_char(v_credit,'FM999G999G999')||'.'
      else 'Permintaan UANG GRATIS ditolak. Catatan admin: '||coalesce(p_admin_note,'Tidak ada catatan') end);
  return true;
end;
$$;
grant execute on function public.f2m1_admin_review_chat_earning_request(uuid,boolean,bigint,text) to authenticated;

-- User mengajukan penarikan. Saldo dikunci dan dipotong dalam transaksi.
create or replace function public.f2m1_request_chat_earning_withdrawal(
  p_amount bigint, p_method text, p_account_name text, p_account_number text
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_name text; v_account text;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu.'; end if;
  if p_amount<20000 then raise exception 'Minimal penarikan Rp20.000.'; end if;
  if p_method not in ('DANA','GoPay','SeaBank') then raise exception 'Metode penarikan tidak valid.'; end if;
  v_name := trim(coalesce(p_account_name,''));
  v_account := trim(coalesce(p_account_number,''));
  if length(v_name)<2 or length(v_account)<5 then raise exception 'Nama dan nomor/rekening tujuan wajib diisi.'; end if;
  update public.f2m1_chat_earning_wallets
    set balance=balance-p_amount, updated_at=now()
    where user_id=auth.uid() and balance>=p_amount;
  if not found then raise exception 'Saldo penghasilan tidak mencukupi.'; end if;
  insert into public.f2m1_chat_earning_withdrawals(user_id,amount,method,account_name,account_number)
    values(auth.uid(),p_amount,p_method,v_name,v_account) returning id into v_id;
  insert into public.f2m1_admin_notifications(message)
    values('Permintaan penarikan UANG GRATIS dari user '||auth.uid()::text||' sebesar Rp'||p_amount::text||'.');
  return v_id;
end;
$$;
grant execute on function public.f2m1_request_chat_earning_withdrawal(bigint,text,text,text) to authenticated;

-- Admin menyetujui pembayaran atau menolak dan mengembalikan saldo.
create or replace function public.f2m1_admin_review_chat_earning_withdrawal(
  p_withdrawal_id uuid, p_approve boolean
) returns boolean
language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_amount bigint; v_status text;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
  select user_id,amount,status into v_user,v_amount,v_status
    from public.f2m1_chat_earning_withdrawals where id=p_withdrawal_id for update;
  if v_user is null then raise exception 'Permintaan penarikan tidak ditemukan.'; end if;
  if v_status<>'pending' then raise exception 'Penarikan sudah pernah diproses.'; end if;
  update public.f2m1_chat_earning_withdrawals
    set status=case when p_approve then 'approved' else 'rejected' end, reviewed_at=now()
    where id=p_withdrawal_id;
  if not p_approve then
    update public.f2m1_chat_earning_wallets
      set balance=balance+v_amount,updated_at=now() where user_id=v_user;
  end if;
  insert into public.f2m1_notifications(user_id,message)
    values(v_user,case when p_approve
      then 'Penarikan UANG GRATIS sebesar Rp'||to_char(v_amount,'FM999G999G999')||' disetujui admin.'
      else 'Penarikan UANG GRATIS ditolak. Saldo dikembalikan.' end);
  return true;
end;
$$;
grant execute on function public.f2m1_admin_review_chat_earning_withdrawal(uuid,boolean) to authenticated;

-- Aktifkan realtime untuk chat, permintaan, wallet, dan penarikan.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='f2m1_chat_earning_requests') then
      alter publication supabase_realtime add table public.f2m1_chat_earning_requests;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='f2m1_chat_earning_messages') then
      alter publication supabase_realtime add table public.f2m1_chat_earning_messages;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='f2m1_chat_earning_wallets') then
      alter publication supabase_realtime add table public.f2m1_chat_earning_wallets;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='f2m1_chat_earning_withdrawals') then
      alter publication supabase_realtime add table public.f2m1_chat_earning_withdrawals;
    end if;
  end if;
exception when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';
commit;
