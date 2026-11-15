-- F2M1 SHOP ID - SQL GABUNGAN V11
-- Menggabungkan SQL V8 + V9 + V10 secara berurutan.
-- PENTING: Jalankan hanya jika database sudah memakai struktur dasar V7,
-- tetapi SQL V8, V9, dan V10 BELUM pernah dijalankan.
-- Backup database Supabase terlebih dahulu.
-- Jangan jalankan V11 jika V8/V9/V10 sudah pernah berhasil dipasang.
-- SQL ini tetap menjalankan transaksi per versi agar urutan dan batas commit
-- migrasi asli tetap terjaga.


-- ============================================================
-- BAGIAN V8 (dipertahankan urutannya dari SQL asli)
-- ============================================================
-- F2M1 SHOP ID V8
-- Jalankan SETELAH SQL V7. Backup database sebelum menjalankan.
-- Password pengguna tidak dapat dibaca melalui SQL. Penghapusan Auth user memerlukan Edge Function terpisah.

begin;

alter table public.profiles
  add column if not exists referral_code text,
  add column if not exists referred_by uuid references public.profiles(id) on delete set null,
  add column if not exists referral_balance bigint not null default 0,
  add column if not exists device_key text,
  add column if not exists banned boolean not null default false,
  add column if not exists banned_reason text;

update public.profiles set referral_code = upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)) where referral_code is null or referral_code = '';
-- Role reseller perlu diizinkan bila project V7 memiliki CHECK constraint role.
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid='public.profiles'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%role%'
  loop execute format('alter table public.profiles drop constraint %I',c.conname); end loop;
end $$;
alter table public.profiles add constraint profiles_role_v8_check check (role in ('user','admin','subscriber','reseller'));
create or replace function public.f2m1_profile_referral_code()
returns trigger language plpgsql set search_path=public as $$
begin
 if new.referral_code is null or new.referral_code='' then new.referral_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)); end if;
 return new;
end; $$;
drop trigger if exists f2m1_profile_referral_code_trg on public.profiles;
create trigger f2m1_profile_referral_code_trg before insert on public.profiles for each row execute function public.f2m1_profile_referral_code();
create unique index if not exists profiles_referral_code_v8_uq on public.profiles(referral_code);

create table if not exists public.f2m1_store_controls (
  id integer primary key default 1 check (id = 1),
  maintenance_enabled boolean not null default false,
  maintenance_reason text not null default '',
  reseller_discount_percent integer not null default 10 check (reseller_discount_percent between 0 and 50),
  referral_reward bigint not null default 1000 check (referral_reward >= 0),
  updated_at timestamptz not null default now()
);
insert into public.f2m1_store_controls(id) values(1) on conflict(id) do nothing;
alter table public.f2m1_store_controls enable row level security;
drop policy if exists f2m1_controls_public_read on public.f2m1_store_controls;
create policy f2m1_controls_public_read on public.f2m1_store_controls for select to anon, authenticated using (true);

create table if not exists public.f2m1_reseller_requests (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null default 5000 check (amount = 5000), payment_method text not null check (payment_method in ('qris','dana')),
  proof_path text not null, status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(), reviewed_at timestamptz
);
create index if not exists f2m1_reseller_requests_created_idx on public.f2m1_reseller_requests(created_at desc);
create unique index if not exists f2m1_one_pending_reseller_request on public.f2m1_reseller_requests(user_id) where status='pending';
alter table public.f2m1_reseller_requests enable row level security;
drop policy if exists f2m1_reseller_request_read on public.f2m1_reseller_requests;
create policy f2m1_reseller_request_read on public.f2m1_reseller_requests for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists f2m1_reseller_request_insert on public.f2m1_reseller_requests;
create policy f2m1_reseller_request_insert on public.f2m1_reseller_requests for insert to authenticated with check (user_id=auth.uid() and status='pending' and amount=5000);

create table if not exists public.f2m1_referral_withdrawals (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount >= 10000), method text not null check (method in ('DANA','GoPay','SeaBank')),
  account text not null, status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(), reviewed_at timestamptz
);
create index if not exists f2m1_referral_withdrawals_created_idx on public.f2m1_referral_withdrawals(created_at desc);
alter table public.f2m1_referral_withdrawals enable row level security;
drop policy if exists f2m1_referral_withdrawal_read on public.f2m1_referral_withdrawals;
create policy f2m1_referral_withdrawal_read on public.f2m1_referral_withdrawals for select to authenticated using (user_id=auth.uid() or public.is_admin());

create table if not exists public.f2m1_referral_rewards (
  id uuid primary key default gen_random_uuid(), referrer_id uuid not null references public.profiles(id) on delete cascade,
  referred_user_id uuid not null references public.profiles(id) on delete cascade, order_id uuid not null unique,
  amount bigint not null, created_at timestamptz not null default now()
);
alter table public.f2m1_referral_rewards enable row level security;
drop policy if exists f2m1_referral_rewards_read on public.f2m1_referral_rewards;
create policy f2m1_referral_rewards_read on public.f2m1_referral_rewards for select to authenticated using (referrer_id=auth.uid() or public.is_admin());

create table if not exists public.f2m1_notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  message text not null, created_at timestamptz not null default now(), read_at timestamptz
);
alter table public.f2m1_notifications enable row level security;
drop policy if exists f2m1_notifications_own_read on public.f2m1_notifications;
create policy f2m1_notifications_own_read on public.f2m1_notifications for select to authenticated using (user_id=auth.uid());
drop policy if exists f2m1_notifications_admin_insert on public.f2m1_notifications;
create policy f2m1_notifications_admin_insert on public.f2m1_notifications for insert to authenticated with check (public.is_admin());

create table if not exists public.f2m1_admin_notifications (
  id uuid primary key default gen_random_uuid(), message text not null, created_at timestamptz not null default now(), read_at timestamptz
);
create or replace function public.admin_mark_f2m1_notification_read(p_id uuid) returns boolean
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 update public.f2m1_admin_notifications set read_at=now() where id=p_id; return found;
end; $$;
grant execute on function public.admin_mark_f2m1_notification_read(uuid) to authenticated;

alter table public.f2m1_admin_notifications enable row level security;
drop policy if exists f2m1_admin_notifications_admin_read on public.f2m1_admin_notifications;
create policy f2m1_admin_notifications_admin_read on public.f2m1_admin_notifications for select to authenticated using (public.is_admin());

alter table public.support_messages add column if not exists attachment_path text;

create or replace function public.register_f2m1_device(p_device_key text) returns boolean
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or coalesce(length(p_device_key),0)<8 then return false; end if;
  update public.profiles set device_key=coalesce(device_key,p_device_key) where id=auth.uid();
  return true;
end; $$;
grant execute on function public.register_f2m1_device(text) to authenticated;

create or replace function public.apply_f2m1_referral(p_referral_code text,p_device_key text) returns boolean
language plpgsql security definer set search_path=public as $$
declare v_referrer uuid; v_role text; v_own_ref uuid; v_ref_device text;
begin
  if auth.uid() is null then raise exception 'Silakan login terlebih dahulu.'; end if;
  select role,referred_by into v_role,v_own_ref from public.profiles where id=auth.uid() for update;
  if v_own_ref is not null then raise exception 'Akun ini sudah terhubung dengan referral.'; end if;
  select id,device_key into v_referrer,v_ref_device from public.profiles where upper(referral_code)=upper(trim(p_referral_code)) limit 1;
  if v_referrer is null then raise exception 'Kode referral tidak ditemukan.'; end if;
  if v_referrer=auth.uid() then raise exception 'Tidak bisa memakai kode referral sendiri.'; end if;
  if coalesce(v_role,'user')<>'admin' and v_ref_device is not null and v_ref_device=p_device_key then raise exception 'Referral dari perangkat yang sama tidak dapat digunakan.'; end if;
  if coalesce(v_role,'user')<>'admin' and exists(select 1 from public.profiles x where x.id<>auth.uid() and coalesce(x.role,'user')<>'admin' and x.device_key=p_device_key) then
    raise exception 'Perangkat ini sudah terhubung dengan akun lain dan tidak memenuhi syarat referral.';
  end if;
  update public.profiles set referred_by=v_referrer,device_key=coalesce(device_key,p_device_key) where id=auth.uid() and referred_by is null;
  if not found then raise exception 'Referral tidak dapat dipasang pada akun ini.'; end if;
  return true;
end; $$;
grant execute on function public.apply_f2m1_referral(text,text) to authenticated;

create or replace function public.get_f2m1_public_order_stats() returns jsonb
language sql security definer set search_path=public as $$
 select jsonb_build_object('total_orders',(select count(*) from public.orders where coalesce(admin_hidden,false)=false),
 'queue_count',(select count(*) from public.orders where status in ('pending','approved') and coalesce(admin_hidden,false)=false));
$$;
grant execute on function public.get_f2m1_public_order_stats() to anon,authenticated;

create or replace function public.admin_set_store_maintenance(p_enabled boolean,p_reason text) returns boolean
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 insert into public.f2m1_store_controls(id,maintenance_enabled,maintenance_reason,updated_at) values(1,p_enabled,coalesce(p_reason,''),now())
 on conflict(id) do update set maintenance_enabled=excluded.maintenance_enabled,maintenance_reason=excluded.maintenance_reason,updated_at=now();
 return true;
end; $$;
grant execute on function public.admin_set_store_maintenance(boolean,text) to authenticated;

create or replace function public.admin_set_f2m1_user_ban(p_user_id uuid,p_banned boolean,p_reason text default '') returns boolean
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 if exists(select 1 from public.profiles where id=p_user_id and role='admin') then raise exception 'Akun admin tidak dapat diblokir.'; end if;
 update public.profiles set banned=p_banned,banned_reason=case when p_banned then coalesce(p_reason,'') else null end where id=p_user_id;
 if not found then raise exception 'Pengguna tidak ditemukan.'; end if; return true;
end; $$;
grant execute on function public.admin_set_f2m1_user_ban(uuid,boolean,text) to authenticated;

create or replace function public.admin_review_reseller_request(p_request_id uuid,p_approve boolean) returns boolean
language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_status text;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 select user_id,status into v_user,v_status from public.f2m1_reseller_requests where id=p_request_id for update;
 if v_user is null then raise exception 'Permintaan tidak ditemukan.'; end if;
 if v_status<>'pending' then raise exception 'Permintaan sudah diproses.'; end if;
 update public.f2m1_reseller_requests set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now() where id=p_request_id;
 if p_approve then update public.profiles set role='reseller' where id=v_user; end if;
 insert into public.f2m1_notifications(user_id,message) values(v_user,case when p_approve then 'Upgrade Reseller disetujui. Diskon reseller sudah aktif.' else 'Permintaan upgrade Reseller ditolak. Hubungi CS jika perlu.' end);
 return true;
end; $$;
grant execute on function public.admin_review_reseller_request(uuid,boolean) to authenticated;

create or replace function public.request_f2m1_referral_withdrawal(p_amount bigint,p_method text,p_account text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_balance bigint; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Silakan login.'; end if;
 if exists(select 1 from public.f2m1_store_controls where id=1 and maintenance_enabled=true) and not public.is_admin() then raise exception 'Toko sedang maintenance.'; end if;
 if exists(select 1 from public.profiles where id=auth.uid() and banned=true) and not public.is_admin() then raise exception 'Akun dibatasi. Hubungi CS.'; end if;
 if p_amount<10000 then raise exception 'Minimal penarikan Rp10.000.'; end if;
 if p_method not in ('DANA','GoPay','SeaBank') or length(trim(coalesce(p_account,'')))<5 then raise exception 'Data pencairan tidak valid.'; end if;
 select referral_balance into v_balance from public.profiles where id=auth.uid() for update;
 if coalesce(v_balance,0)<p_amount then raise exception 'Saldo referral tidak mencukupi.'; end if;
 update public.profiles set referral_balance=referral_balance-p_amount where id=auth.uid();
 insert into public.f2m1_referral_withdrawals(user_id,amount,method,account) values(auth.uid(),p_amount,p_method,trim(p_account)) returning id into v_id;
 return v_id;
end; $$;
grant execute on function public.request_f2m1_referral_withdrawal(bigint,text,text) to authenticated;

create or replace function public.admin_review_f2m1_referral_withdrawal(p_withdrawal_id uuid,p_approve boolean) returns boolean
language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_amount bigint; v_status text;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan.'; end if;
 select user_id,amount,status into v_user,v_amount,v_status from public.f2m1_referral_withdrawals where id=p_withdrawal_id for update;
 if v_user is null then raise exception 'Permintaan penarikan tidak ditemukan.'; end if;
 if v_status<>'pending' then raise exception 'Permintaan sudah diproses.'; end if;
 update public.f2m1_referral_withdrawals set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now() where id=p_withdrawal_id;
 if not p_approve then update public.profiles set referral_balance=referral_balance+v_amount where id=v_user; end if;
 insert into public.f2m1_notifications(user_id,message) values(v_user,case when p_approve then 'Penarikan referral ditandai sudah dibayar admin.' else 'Penarikan referral ditolak. Saldo dikembalikan.' end);
 return true;
end; $$;
grant execute on function public.admin_review_f2m1_referral_withdrawal(uuid,boolean) to authenticated;

create or replace function public.f2m1_award_referral_on_done() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_referrer uuid; v_reward bigint; v_inserted uuid; v_changed boolean;
begin
 if tg_op='INSERT' then v_changed:=true; else v_changed:=old.status is distinct from new.status; end if;
 if new.status='done' and v_changed then
  select referred_by into v_referrer from public.profiles where id=new.user_id;
  if v_referrer is not null then
   select referral_reward into v_reward from public.f2m1_store_controls where id=1;
   insert into public.f2m1_referral_rewards(referrer_id,referred_user_id,order_id,amount)
   values(v_referrer,new.user_id,new.id,coalesce(v_reward,1000)) on conflict(order_id) do nothing returning id into v_inserted;
   if v_inserted is not null then
    update public.profiles set referral_balance=referral_balance+coalesce(v_reward,1000) where id=v_referrer;
    insert into public.f2m1_notifications(user_id,message) values(v_referrer,'Hadiah referral Rp'||to_char(coalesce(v_reward,1000),'FM999G999G999')||' masuk karena order teman selesai.');
   end if;
  end if;
 end if; return new;
end; $$;
drop trigger if exists f2m1_referral_reward_order_done on public.orders;
create trigger f2m1_referral_reward_order_done after insert or update of status on public.orders for each row execute function public.f2m1_award_referral_on_done();

create or replace function public.f2m1_support_notification_trigger() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if new.sender_role='admin' then insert into public.f2m1_notifications(user_id,message) values(new.user_id,'Admin membalas pesan CS kamu.');
 elsif new.sender_role='user' then insert into public.f2m1_admin_notifications(message) values('Pesan CS baru dari pengguna '||new.user_id::text||'.'); end if;
 return new;
end; $$;
drop trigger if exists f2m1_support_notify on public.support_messages;
create trigger f2m1_support_notify after insert on public.support_messages for each row execute function public.f2m1_support_notification_trigger();

create or replace function public.f2m1_order_notification_trigger() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_changed boolean;
begin
 if tg_op='INSERT' then v_changed:=true; else v_changed:=old.status is distinct from new.status; end if;
 if new.status='done' and v_changed then
  insert into public.f2m1_notifications(user_id,message) values(new.user_id,'Pesanan kamu sudah selesai.');
 end if;
 if tg_op='INSERT' then insert into public.f2m1_admin_notifications(message) values('Pesanan baru masuk: '||new.id::text||'.'); end if;
 return new;
end; $$;
drop trigger if exists f2m1_order_notify on public.orders;
create trigger f2m1_order_notify after insert or update of status on public.orders for each row execute function public.f2m1_order_notification_trigger();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('chat-attachments','chat-attachments',false,5242880,array['image/jpeg','image/png','image/webp','image/gif']) on conflict(id) do nothing;
drop policy if exists f2m1_chat_upload_own on storage.objects;
create policy f2m1_chat_upload_own on storage.objects for insert to authenticated with check (bucket_id='chat-attachments' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
drop policy if exists f2m1_chat_read_own_admin on storage.objects;
create policy f2m1_chat_read_own_admin on storage.objects for select to authenticated using (bucket_id='chat-attachments' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
drop policy if exists f2m1_storage_admin_delete on storage.objects;
create policy f2m1_storage_admin_delete on storage.objects for delete to authenticated using (bucket_id in ('payment-proofs','profile-photos','chat-attachments') and public.is_admin());
drop policy if exists f2m1_storage_admin_read on storage.objects;
create policy f2m1_storage_admin_read on storage.objects for select to authenticated using (bucket_id in ('payment-proofs','profile-photos','chat-attachments') and public.is_admin());

do $$ begin alter publication supabase_realtime add table public.f2m1_notifications; exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.f2m1_store_controls; exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.f2m1_admin_notifications; exception when duplicate_object then null; when undefined_object then null; end $$;


-- Server-side guard: maintenance and banned users cannot create transactions.
create or replace function public.f2m1_guard_transaction()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_maintenance boolean; v_reason text; v_banned boolean; v_banned_reason text;
begin
  select maintenance_enabled,maintenance_reason into v_maintenance,v_reason from public.f2m1_store_controls where id=1;
  if coalesce(v_maintenance,false) and coalesce(auth.uid()::text,'')<>'' and not public.is_admin() then
    raise exception 'Toko sedang maintenance: %',coalesce(v_reason,'transaksi sementara dihentikan');
  end if;
  if auth.uid() is not null then
    select banned,banned_reason into v_banned,v_banned_reason from public.profiles where id=auth.uid();
    if coalesce(v_banned,false) and not public.is_admin() then raise exception 'Akun dibatasi: %',coalesce(v_banned_reason,'hubungi CS'); end if;
  end if;
  return new;
end; $$;
drop trigger if exists f2m1_guard_topup_insert on public.topups;
create trigger f2m1_guard_topup_insert before insert on public.topups for each row execute function public.f2m1_guard_transaction();
drop trigger if exists f2m1_guard_reseller_request_insert on public.f2m1_reseller_requests;
create trigger f2m1_guard_reseller_request_insert before insert on public.f2m1_reseller_requests for each row execute function public.f2m1_guard_transaction();

-- Upgrade kedua RPC order yang telah dipakai versi V3/V7 agar diskon reseller dihitung di server.
create or replace function public.create_order_with_balance(
 product_uuid uuid, target_value text, qty_value integer, voucher_code_value text default ''
) returns uuid language plpgsql security definer set search_path=public as $$
declare p public.products%rowtype; v public.vouchers%rowtype; final_amount bigint; new_order uuid; role_value text; disc integer:=0; controls_reason text;
begin
 if auth.uid() is null then raise exception 'Login diperlukan'; end if;
 if exists(select 1 from public.f2m1_store_controls where id=1 and maintenance_enabled=true) and not public.is_admin() then
   select maintenance_reason into controls_reason from public.f2m1_store_controls where id=1; raise exception 'Toko sedang maintenance: %',coalesce(controls_reason,'transaksi dihentikan');
 end if;
 if exists(select 1 from public.profiles where id=auth.uid() and banned=true) and not public.is_admin() then raise exception 'Akun dibatasi. Hubungi CS.'; end if;
 if length(trim(target_value))=0 or qty_value<=0 then raise exception 'Data pesanan tidak valid'; end if;
 select * into p from public.products where id=product_uuid and active=true;
 if not found then raise exception 'Produk tidak tersedia'; end if;
 if qty_value<p.min_qty then raise exception 'Jumlah di bawah minimum'; end if;
 final_amount=ceil(qty_value::numeric/100*p.price_per_100);
 select role into role_value from public.profiles where id=auth.uid();
 if role_value='reseller' then select reseller_discount_percent into disc from public.f2m1_store_controls where id=1; final_amount=greatest(0,final_amount-floor(final_amount*coalesce(disc,10)/100));
 elsif role_value='subscriber' then final_amount=greatest(0,final_amount-floor(final_amount*0.02)); end if;
 if length(trim(coalesce(voucher_code_value,'')))>0 then
  select * into v from public.vouchers where code=upper(trim(voucher_code_value)) and type='discount' and active=true for update;
  if not found or (v.max_uses is not null and v.used_count>=v.max_uses) then raise exception 'Voucher tidak valid'; end if;
  final_amount=greatest(0,final_amount-floor(final_amount*v.value/100)); update public.vouchers set used_count=used_count+1 where id=v.id;
 end if;
 update public.profiles set balance=balance-final_amount where id=auth.uid() and balance>=final_amount;
 if not found then raise exception 'Saldo tidak mencukupi'; end if;
 insert into public.orders(user_id,product_id,product_name,target,quantity,amount,payment_method,voucher_id,status)
 values(auth.uid(),p.id,p.name,trim(target_value),qty_value,final_amount,'balance',case when length(trim(coalesce(voucher_code_value,'')))>0 then v.id else null end,'approved') returning id into new_order;
 insert into public.notifications(user_id,title,message) values(auth.uid(),'Pesanan dibuat','Pembayaran saldo berhasil. Pesanan masuk antrean admin.');
 return new_order;
end; $$;
grant execute on function public.create_order_with_balance(uuid,text,integer,text) to authenticated;

create or replace function public.create_order_payment(
 product_uuid uuid, target_value text, qty_value integer,
 payment_method_value text, proof_path_value text, voucher_code_value text default ''
) returns uuid language plpgsql security definer set search_path=public as $$
declare p public.products%rowtype; v public.vouchers%rowtype; final_amount bigint; new_order uuid; role_value text; disc integer:=0; controls_reason text;
begin
 if auth.uid() is null then raise exception 'Login diperlukan'; end if;
 if exists(select 1 from public.f2m1_store_controls where id=1 and maintenance_enabled=true) and not public.is_admin() then
   select maintenance_reason into controls_reason from public.f2m1_store_controls where id=1; raise exception 'Toko sedang maintenance: %',coalesce(controls_reason,'transaksi dihentikan');
 end if;
 if exists(select 1 from public.profiles where id=auth.uid() and banned=true) and not public.is_admin() then raise exception 'Akun dibatasi. Hubungi CS.'; end if;
 if length(trim(coalesce(target_value,'')))=0 or qty_value<=0 then raise exception 'Data pesanan tidak valid'; end if;
 if payment_method_value not in ('qris','dana') then raise exception 'Metode pembayaran tidak valid'; end if;
 if coalesce(proof_path_value,'')='' or split_part(proof_path_value,'/',1)<>auth.uid()::text then raise exception 'Bukti pembayaran tidak valid'; end if;
 select * into p from public.products where id=product_uuid and active=true;
 if not found then raise exception 'Produk tidak tersedia'; end if;
 if qty_value<p.min_qty then raise exception 'Jumlah di bawah minimum'; end if;
 final_amount=ceil(qty_value::numeric/100*p.price_per_100);
 select role into role_value from public.profiles where id=auth.uid();
 if role_value='reseller' then select reseller_discount_percent into disc from public.f2m1_store_controls where id=1; final_amount=greatest(0,final_amount-floor(final_amount*coalesce(disc,10)/100));
 elsif role_value='subscriber' then final_amount=greatest(0,final_amount-floor(final_amount*0.02)); end if;
 if length(trim(coalesce(voucher_code_value,'')))>0 then
  select * into v from public.vouchers where code=upper(trim(voucher_code_value)) and type='discount' and active=true for update;
  if not found or (v.max_uses is not null and v.used_count>=v.max_uses) then raise exception 'Voucher tidak valid atau sudah habis'; end if;
  final_amount=greatest(0,final_amount-floor(final_amount*v.value/100)); update public.vouchers set used_count=used_count+1 where id=v.id;
 end if;
 insert into public.orders(user_id,product_id,product_name,target,quantity,amount,payment_method,proof_path,voucher_id,status)
 values(auth.uid(),p.id,p.name,trim(target_value),qty_value,final_amount,payment_method_value,proof_path_value,
 case when length(trim(coalesce(voucher_code_value,'')))>0 then v.id else null end,'pending') returning id into new_order;
 insert into public.notifications(user_id,title,message) values(auth.uid(),'Pesanan dikirim','Pesanan berhasil dikirim. Menunggu verifikasi pembayaran admin.');
 return new_order;
end; $$;
grant execute on function public.create_order_payment(uuid,text,integer,text,text,text) to authenticated;

notify pgrst, 'reload schema';
commit;


-- ============================================================
-- BAGIAN V9 (dipertahankan urutannya dari SQL asli)
-- ============================================================
-- F2M1 SHOP ID V9 UPDATE
-- Jalankan SETELAH UPGRADE_F2M1_V8.sql berhasil. Backup database terlebih dahulu.
begin;

alter table public.support_messages
  add column if not exists reply_to_id uuid null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='support_messages_reply_to_id_fkey' and conrelid='public.support_messages'::regclass) then
    alter table public.support_messages
      add constraint support_messages_reply_to_id_fkey
      foreign key (reply_to_id) references public.support_messages(id) on delete set null;
  end if;
end $$;

create index if not exists support_messages_reply_to_id_idx
  on public.support_messages(reply_to_id) where reply_to_id is not null;

notify pgrst, 'reload schema';
commit;


-- ============================================================
-- BAGIAN V10 (dipertahankan urutannya dari SQL asli)
-- ============================================================
-- F2M1 SHOP ID V10 - REFERRAL HISTORY & WITHDRAWAL DETAILS
-- Jalankan SETELAH V8 dan V9 berhasil. Backup database terlebih dahulu.
-- V10 tidak menghapus akun, order, atau saldo yang sudah ada.

begin;

-- Tujuan penarikan (nomor DANA / GoPay / rekening SeaBank) sudah disimpan
-- pada kolom account. Tambahkan kolom label opsional agar histori eksplisit.
alter table public.f2m1_referral_withdrawals
  add column if not exists destination_label text;

update public.f2m1_referral_withdrawals
set destination_label = case
  when method = 'DANA' then 'Nomor HP DANA'
  when method = 'GoPay' then 'Nomor HP GoPay'
  when method = 'SeaBank' then 'Nomor rekening SeaBank'
  else 'Akun tujuan'
end
where destination_label is null;

-- Riwayat order referral menyimpan status setiap order dari pengguna yang
-- mendaftar memakai referral. Riwayat tetap tersimpan jika order dihapus.
create table if not exists public.f2m1_referral_order_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique,
  referrer_id uuid not null references public.profiles(id) on delete cascade,
  referred_user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending',
  reward_amount bigint not null default 1000,
  reward_credited boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  credited_at timestamptz
);

create index if not exists f2m1_referral_history_owner_created_idx
  on public.f2m1_referral_order_history(referrer_id, created_at desc);
create index if not exists f2m1_referral_history_status_idx
  on public.f2m1_referral_order_history(status, created_at desc);

alter table public.f2m1_referral_order_history enable row level security;
drop policy if exists f2m1_referral_history_read on public.f2m1_referral_order_history;
create policy f2m1_referral_history_read
on public.f2m1_referral_order_history
for select to authenticated
using (
  referrer_id = auth.uid()
  or referred_user_id = auth.uid()
  or public.is_admin()
);

-- Backfill status order referral yang sudah ada. Backfill tidak memberi saldo
-- retroaktif; hadiah lama hanya ditandai masuk jika tercatat di tabel rewards.
insert into public.f2m1_referral_order_history
  (order_id, referrer_id, referred_user_id, status, reward_amount,
   reward_credited, created_at, updated_at, credited_at)
select
  o.id,
  p.referred_by,
  o.user_id,
  coalesce(o.status, 'pending'),
  coalesce(c.referral_reward, 1000),
  exists(select 1 from public.f2m1_referral_rewards rr where rr.order_id=o.id),
  coalesce(o.created_at, now()),
  now(),
  (select min(rr.created_at) from public.f2m1_referral_rewards rr where rr.order_id=o.id)
from public.orders o
join public.profiles p on p.id=o.user_id
left join public.f2m1_store_controls c on c.id=1
where p.referred_by is not null
on conflict(order_id) do update
set status=excluded.status,
    updated_at=now(),
    reward_credited=public.f2m1_referral_order_history.reward_credited
      or excluded.reward_credited,
    credited_at=coalesce(public.f2m1_referral_order_history.credited_at,excluded.credited_at);

-- Satu trigger mencatat semua perubahan status dan memberi hadiah satu kali
-- saat status order berubah menjadi done. Unique order_id mencegah hadiah ganda.
create or replace function public.f2m1_award_referral_on_done()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_referrer uuid;
  v_reward bigint;
  v_reward_id uuid;
  v_created timestamptz;
  v_status text;
begin
  select referred_by into v_referrer
  from public.profiles
  where id = new.user_id;

  if v_referrer is null then
    return new;
  end if;

  select coalesce(referral_reward,1000) into v_reward
  from public.f2m1_store_controls
  where id=1;
  v_reward := coalesce(v_reward,1000);

  if tg_op = 'INSERT' then
    v_created := coalesce(new.created_at,now());
  else
    v_created := coalesce(old.created_at,new.created_at,now());
  end if;
  v_status := coalesce(new.status,'pending');

  insert into public.f2m1_referral_order_history
    (order_id,referrer_id,referred_user_id,status,reward_amount,created_at,updated_at)
  values
    (new.id,v_referrer,new.user_id,v_status,v_reward,v_created,now())
  on conflict(order_id) do update
  set status=excluded.status,
      updated_at=now(),
      reward_amount=excluded.reward_amount;

  if v_status='done' then
    insert into public.f2m1_referral_rewards
      (referrer_id,referred_user_id,order_id,amount)
    values
      (v_referrer,new.user_id,new.id,v_reward)
    on conflict(order_id) do nothing
    returning id into v_reward_id;

    if v_reward_id is not null then
      update public.profiles
      set referral_balance=coalesce(referral_balance,0)+v_reward
      where id=v_referrer;

      insert into public.f2m1_notifications(user_id,message)
      values(v_referrer,
        'Hadiah referral sebesar Rp'||to_char(v_reward,'FM999G999G999')||
        ' otomatis masuk karena order referral sudah selesai.');
    end if;

    select min(created_at) into v_created
    from public.f2m1_referral_rewards
    where order_id=new.id;

    update public.f2m1_referral_order_history
    set reward_credited=true,
        credited_at=coalesce(credited_at,v_created),
        updated_at=now()
    where order_id=new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists f2m1_referral_reward_order_done on public.orders;
create trigger f2m1_referral_reward_order_done
after insert or update of status on public.orders
for each row
execute function public.f2m1_award_referral_on_done();

-- Pastikan permintaan penarikan tetap menyimpan metode dan nomor tujuan.
-- Constraint metode mencegah salah input kanal pencairan.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='f2m1_referral_withdrawals_method_v10_check'
      and conrelid='public.f2m1_referral_withdrawals'::regclass
  ) then
    alter table public.f2m1_referral_withdrawals
      add constraint f2m1_referral_withdrawals_method_v10_check
      check (method in ('DANA','GoPay','SeaBank')) not valid;
  end if;
end $$;

notify pgrst, 'reload schema';
commit;
