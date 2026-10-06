-- =============================================================================
-- AutoWave: complete schema (phases 1-7)
--   1 profiles + roles        4 live tracking + ETA       7 AutoLearn history
--   2 mechanic search/ratings 5 wallet + Paystack escrow
--   3 requests accept/reject  6 recycling
-- Money is stored in kobo (bigint). ₦1 = 100 kobo.
-- Apps never write money, statuses or ratings directly: every change goes
-- through a security-definer function below that checks who is calling.
-- =============================================================================

-- gen_random_uuid() is built into Postgres 13+, no extension needed.

-- ---------------------------------------------------------------------------
-- App settings (one row)
-- ---------------------------------------------------------------------------
create table if not exists public.app_config (
  id                  boolean primary key default true check (id),
  platform_fee_bps    integer not null default 0 check (platform_fee_bps between 0 and 5000),
  request_timeout_sec integer not null default 180 check (request_timeout_sec between 30 and 1800),
  auto_release_hours  integer not null default 48,
  -- Lets testers add wallet money without Paystack. TURN OFF BEFORE LAUNCH:
  --   update public.app_config set allow_test_topups = false;
  allow_test_topups   boolean not null default true
);
insert into public.app_config (id) values (true) on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Phase 1: profiles and roles
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  role         text check (role in ('driver', 'mechanic')),
  full_name    text,
  phone        text,
  country_code text,
  avatar_url   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.wallets (
  user_id       uuid primary key references public.profiles (id) on delete cascade,
  available_kobo bigint not null default 0 check (available_kobo >= 0),
  updated_at    timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, phone, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    coalesce(new.phone, new.raw_user_meta_data ->> 'phone'),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  insert into public.wallets (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- Choose driver or mechanic once. Changing later needs support.
create or replace function public.set_my_role(p_role text, p_full_name text default null,
                                              p_phone text default null, p_country_code text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_current text;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if p_role not in ('driver', 'mechanic') then raise exception 'Choose driver or mechanic'; end if;
  insert into public.profiles (id) values (v_uid) on conflict do nothing;
  insert into public.wallets (user_id) values (v_uid) on conflict do nothing;
  select role into v_current from public.profiles where id = v_uid for update;
  if v_current is not null and v_current <> p_role then
    raise exception 'Your account is already set up as a %', v_current;
  end if;
  update public.profiles set
    role = p_role,
    full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
    phone = coalesce(nullif(trim(p_phone), ''), phone),
    country_code = coalesce(nullif(trim(p_country_code), ''), country_code),
    updated_at = now()
  where id = v_uid;
end $$;

create or replace function public.update_my_profile(p_full_name text, p_phone text, p_country_code text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update public.profiles set
    full_name = nullif(trim(p_full_name), ''),
    phone = nullif(trim(p_phone), ''),
    country_code = nullif(trim(p_country_code), ''),
    updated_at = now()
  where id = auth.uid();
end $$;

-- ---------------------------------------------------------------------------
-- Phase 2: mechanics, search and reviews
-- ---------------------------------------------------------------------------
create table if not exists public.mechanic_profiles (
  id                uuid primary key references public.profiles (id) on delete cascade,
  business_name     text not null,
  bio               text,
  services          text[] not null default '{}',
  min_price_kobo    bigint not null default 0 check (min_price_kobo >= 0),
  base_address      text not null,
  base_lat          double precision not null check (base_lat between -90 and 90),
  base_lng          double precision not null check (base_lng between -180 and 180),
  service_radius_km integer not null default 15 check (service_radius_km between 1 and 200),
  years_experience  integer not null default 0 check (years_experience between 0 and 80),
  is_online         boolean not null default true,
  rating_avg        numeric(3, 2) not null default 0,
  rating_count      integer not null default 0,
  jobs_completed    integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists mechanic_profiles_geo_idx on public.mechanic_profiles (base_lat, base_lng);

create or replace function public.save_mechanic_profile(
  p_business_name text, p_bio text, p_services text[], p_min_price_kobo bigint,
  p_base_address text, p_base_lat double precision, p_base_lng double precision,
  p_service_radius_km integer, p_years_experience integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if (select role from public.profiles where id = v_uid) is distinct from 'mechanic' then
    raise exception 'Only mechanics have a workshop profile';
  end if;
  if coalesce(trim(p_business_name), '') = '' then raise exception 'Add your business name'; end if;
  if coalesce(trim(p_base_address), '') = '' then raise exception 'Add your workshop address'; end if;
  insert into public.mechanic_profiles as m (id, business_name, bio, services, min_price_kobo, base_address,
      base_lat, base_lng, service_radius_km, years_experience)
  values (v_uid, trim(p_business_name), nullif(trim(p_bio), ''), coalesce(p_services, '{}'), greatest(p_min_price_kobo, 0),
      trim(p_base_address), p_base_lat, p_base_lng, coalesce(p_service_radius_km, 15), coalesce(p_years_experience, 0))
  on conflict (id) do update set
    business_name = excluded.business_name, bio = excluded.bio, services = excluded.services,
    min_price_kobo = excluded.min_price_kobo, base_address = excluded.base_address,
    base_lat = excluded.base_lat, base_lng = excluded.base_lng,
    service_radius_km = excluded.service_radius_km, years_experience = excluded.years_experience,
    updated_at = now();
end $$;

create or replace function public.set_online(p_online boolean)
returns void language sql security definer set search_path = public as $$
  update public.mechanic_profiles set is_online = p_online, updated_at = now() where id = auth.uid();
$$;

create or replace function public.distance_km(lat1 double precision, lng1 double precision,
                                              lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)));
$$;

-- Mechanics near the driver who fit the budget, closest and best rated first.
create or replace function public.search_mechanics(
  p_lat double precision, p_lng double precision,
  p_budget_kobo bigint default null, p_service text default null, p_radius_km double precision default 25)
returns table (
  id uuid, business_name text, bio text, services text[], min_price_kobo bigint,
  base_address text, base_lat double precision, base_lng double precision,
  years_experience integer, rating_avg numeric, rating_count integer, jobs_completed integer,
  distance_km double precision, within_budget boolean)
language sql stable security definer set search_path = public as $$
  select m.id, m.business_name, m.bio, m.services, m.min_price_kobo, m.base_address, m.base_lat, m.base_lng,
         m.years_experience, m.rating_avg, m.rating_count, m.jobs_completed,
         round(public.distance_km(p_lat, p_lng, m.base_lat, m.base_lng)::numeric, 2)::double precision as distance_km,
         (p_budget_kobo is null or m.min_price_kobo <= p_budget_kobo) as within_budget
  from public.mechanic_profiles m
  where auth.uid() is not null
    and m.is_online
    and m.id <> auth.uid()
    and public.distance_km(p_lat, p_lng, m.base_lat, m.base_lng) <= least(coalesce(p_radius_km, 25), 100)
    and (p_service is null or p_service = '' or p_service = any (m.services))
  order by within_budget desc, distance_km asc, m.rating_avg desc
  limit 50;
$$;

-- ---------------------------------------------------------------------------
-- Phase 3: service requests
-- ---------------------------------------------------------------------------
create table if not exists public.service_requests (
  id                uuid primary key default gen_random_uuid(),
  customer_id       uuid not null references public.profiles (id) on delete cascade,
  mechanic_id       uuid not null references public.mechanic_profiles (id) on delete cascade,
  service_type      text not null,
  description       text,
  pickup_address    text not null,
  pickup_lat        double precision not null,
  pickup_lng        double precision not null,
  budget_kobo       bigint check (budget_kobo is null or budget_kobo >= 0),
  quoted_price_kobo bigint check (quoted_price_kobo is null or quoted_price_kobo > 0),
  status            text not null default 'requested' check (status in
                      ('requested', 'accepted', 'rejected', 'expired', 'cancelled',
                       'en_route', 'arrived', 'in_progress', 'completed')),
  payment_status    text not null default 'unpaid' check (payment_status in
                      ('unpaid', 'held', 'released', 'refunded', 'disputed')),
  respond_by        timestamptz not null,
  eta_seconds       integer,
  distance_m        integer,
  eta_updated_at    timestamptz,
  cancel_reason     text,
  cancelled_by      uuid,
  created_at        timestamptz not null default now(),
  accepted_at       timestamptz,
  completed_at      timestamptz,
  updated_at        timestamptz not null default now()
);
create index if not exists service_requests_customer_status_idx on public.service_requests (customer_id, status);
create index if not exists service_requests_mechanic_status_idx on public.service_requests (mechanic_id, status);

create or replace function public.create_request(
  p_mechanic_id uuid, p_service_type text, p_description text,
  p_pickup_address text, p_pickup_lat double precision, p_pickup_lng double precision, p_budget_kobo bigint)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_timeout integer;
begin
  if v_uid is null then raise exception 'Not signed in'; end if;
  if (select role from public.profiles where id = v_uid) is distinct from 'driver' then
    raise exception 'Only drivers can request a mechanic';
  end if;
  if not exists (select 1 from public.mechanic_profiles where id = p_mechanic_id and is_online) then
    raise exception 'This mechanic is offline right now';
  end if;
  if exists (select 1 from public.service_requests
             where customer_id = v_uid
               and (status in ('accepted', 'en_route', 'arrived', 'in_progress')
                    or (status = 'requested' and respond_by > now()))) then
    raise exception 'You already have a request in progress';
  end if;
  select request_timeout_sec into v_timeout from public.app_config;
  insert into public.service_requests (customer_id, mechanic_id, service_type, description, pickup_address,
                                       pickup_lat, pickup_lng, budget_kobo, respond_by)
  values (v_uid, p_mechanic_id, coalesce(nullif(trim(p_service_type), ''), 'General repair'),
          nullif(trim(p_description), ''), p_pickup_address, p_pickup_lat, p_pickup_lng, p_budget_kobo,
          now() + make_interval(secs => coalesce(v_timeout, 180)))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.expire_stale_requests()
returns integer language sql security definer set search_path = public as $$
  with x as (
    update public.service_requests set status = 'expired', updated_at = now()
    where status = 'requested' and respond_by <= now() returning 1)
  select count(*)::integer from x;
$$;

-- Mechanic answers a request. Accepting needs a price; the ETA is their own guess
-- until they start the trip and live ETA takes over.
create or replace function public.respond_to_request(
  p_request_id uuid, p_accept boolean, p_quote_kobo bigint default null, p_eta_minutes integer default null)
returns void language plpgsql security definer set search_path = public as $$
declare r public.service_requests;
begin
  select * into r from public.service_requests where id = p_request_id for update;
  if r.id is null or r.mechanic_id <> auth.uid() then raise exception 'Request not found'; end if;
  if r.status <> 'requested' then raise exception 'This request is no longer waiting for you'; end if;
  if r.respond_by <= now() then
    update public.service_requests set status = 'expired', updated_at = now() where id = r.id;
    raise exception 'This request timed out';
  end if;
  if p_accept then
    if coalesce(p_quote_kobo, 0) <= 0 then raise exception 'Enter your price for this job'; end if;
    if p_quote_kobo > 500000000 then raise exception 'The most you can quote is ₦5,000,000'; end if;
    update public.service_requests set
      status = 'accepted', quoted_price_kobo = p_quote_kobo,
      eta_seconds = case when p_eta_minutes > 0 then p_eta_minutes * 60 end,
      accepted_at = now(), updated_at = now()
    where id = r.id;
  else
    update public.service_requests set status = 'rejected', updated_at = now() where id = r.id;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Phase 5 (tables first, functions use them): wallet ledger and escrow
-- ---------------------------------------------------------------------------
create table if not exists public.wallet_transactions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        text not null check (kind in ('topup', 'escrow_hold', 'escrow_release', 'escrow_refund',
                                            'escrow_incoming', 'withdrawal', 'withdrawal_reversal',
                                            'recycling_payout', 'test_topup')),
  amount_kobo bigint not null,            -- + credit, - debit from available balance
  request_id  uuid references public.service_requests (id) on delete set null,
  reference   text,
  description text,
  created_at  timestamptz not null default now()
);
create index if not exists wallet_transactions_user_idx on public.wallet_transactions (user_id, created_at desc);

create table if not exists public.escrow_holds (
  request_id  uuid primary key references public.service_requests (id) on delete cascade,
  payer_id    uuid not null references public.profiles (id),
  payee_id    uuid not null references public.profiles (id),
  amount_kobo bigint not null check (amount_kobo > 0),
  fee_kobo    bigint not null default 0,
  status      text not null default 'held' check (status in ('held', 'released', 'refunded', 'disputed')),
  dispute_reason text,
  created_at  timestamptz not null default now(),
  settled_at  timestamptz
);

create table if not exists public.payments (
  reference    text primary key,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  amount_kobo  bigint not null check (amount_kobo > 0),
  status       text not null default 'pending' check (status in ('pending', 'success', 'failed')),
  provider     text not null default 'paystack',
  raw          jsonb,
  created_at   timestamptz not null default now(),
  verified_at  timestamptz
);

create table if not exists public.payout_accounts (
  user_id        uuid primary key references public.profiles (id) on delete cascade,
  bank_name      text not null,
  bank_code      text not null,
  account_number text not null check (account_number ~ '^[0-9]{10}$'),
  account_name   text,
  recipient_code text,
  updated_at     timestamptz not null default now()
);

create table if not exists public.withdrawals (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  amount_kobo   bigint not null check (amount_kobo >= 10000),
  status        text not null default 'pending' check (status in ('pending', 'processing', 'paid', 'failed')),
  transfer_code text,
  failure_reason text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Internal: move money in/out of a wallet and write the ledger line.
create or replace function public._wallet_apply(p_user uuid, p_amount bigint, p_kind text,
                                                p_request uuid, p_reference text, p_description text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.wallets (user_id) values (p_user) on conflict do nothing;
  update public.wallets set available_kobo = available_kobo + p_amount, updated_at = now() where user_id = p_user;
  insert into public.wallet_transactions (user_id, kind, amount_kobo, request_id, reference, description)
  values (p_user, p_kind, p_amount, p_request, p_reference, p_description);
exception when check_violation then
  raise exception 'Not enough money in your wallet';
end $$;
revoke all on function public._wallet_apply(uuid, bigint, text, uuid, text, text) from public, anon, authenticated;

-- Internal: return held money to the driver.
create or replace function public._escrow_refund(p_request uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare h public.escrow_holds;
begin
  select * into h from public.escrow_holds where request_id = p_request and status in ('held', 'disputed') for update;
  if h.request_id is null then return; end if;
  perform public._wallet_apply(h.payer_id, h.amount_kobo, 'escrow_refund', p_request, null, p_reason);
  update public.escrow_holds set status = 'refunded', settled_at = now() where request_id = p_request;
  update public.service_requests set payment_status = 'refunded', updated_at = now() where id = p_request;
end $$;
revoke all on function public._escrow_refund(uuid, text) from public, anon, authenticated;

-- Internal: pay the mechanic.
create or replace function public._escrow_release(p_request uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare h public.escrow_holds; v_bps integer;
begin
  select * into h from public.escrow_holds where request_id = p_request and status in ('held', 'disputed') for update;
  if h.request_id is null then return; end if;
  select platform_fee_bps into v_bps from public.app_config;
  h.fee_kobo := (h.amount_kobo * coalesce(v_bps, 0)) / 10000;
  perform public._wallet_apply(h.payee_id, h.amount_kobo - h.fee_kobo, 'escrow_release', p_request, null, p_note);
  update public.escrow_holds set status = 'released', fee_kobo = h.fee_kobo, settled_at = now() where request_id = p_request;
  update public.service_requests set payment_status = 'released', updated_at = now() where id = p_request;
end $$;
revoke all on function public._escrow_release(uuid, text) from public, anon, authenticated;

-- Mechanic moves the job along: accepted -> en_route -> arrived -> in_progress -> completed.
-- Work can only start once the driver's payment is secured in escrow.
create or replace function public.update_job_status(p_request_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare r public.service_requests; ok boolean;
begin
  select * into r from public.service_requests where id = p_request_id for update;
  if r.id is null or r.mechanic_id <> auth.uid() then raise exception 'Job not found'; end if;
  ok := (r.status = 'accepted' and p_status = 'en_route')
     or (r.status = 'en_route' and p_status = 'arrived')
     or (r.status = 'accepted' and p_status = 'arrived')
     or (r.status = 'arrived' and p_status = 'in_progress')
     or (r.status = 'in_progress' and p_status = 'completed');
  if not ok then raise exception 'Can''t move this job from % to %', r.status, p_status; end if;
  if p_status = 'in_progress' and r.payment_status <> 'held' then
    raise exception 'Wait for the driver to pay into escrow before starting work';
  end if;
  update public.service_requests set
    status = p_status,
    completed_at = case when p_status = 'completed' then now() else completed_at end,
    eta_seconds = case when p_status in ('arrived', 'in_progress', 'completed') then null else eta_seconds end,
    updated_at = now()
  where id = r.id;
  if p_status = 'completed' then
    update public.mechanic_profiles set jobs_completed = jobs_completed + 1 where id = r.mechanic_id;
    -- Tell the mechanic the money is waiting for the driver's confirmation.
    insert into public.wallet_transactions (user_id, kind, amount_kobo, request_id, description)
    select r.mechanic_id, 'escrow_incoming', 0, r.id, 'Job complete. Payment releases when the driver confirms.'
    where r.payment_status = 'held';
  end if;
end $$;

-- Either side can cancel before work starts. Any held money goes back to the driver.
create or replace function public.cancel_request(p_request_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r public.service_requests; v_uid uuid := auth.uid();
begin
  select * into r from public.service_requests where id = p_request_id for update;
  if r.id is null or v_uid not in (r.customer_id, r.mechanic_id) then raise exception 'Request not found'; end if;
  if r.status not in ('requested', 'accepted', 'en_route', 'arrived') then
    raise exception 'This job can''t be cancelled now';
  end if;
  if v_uid = r.mechanic_id and r.status = 'requested' then
    raise exception 'Decline the request instead';
  end if;
  update public.service_requests set status = 'cancelled', cancel_reason = nullif(trim(p_reason), ''),
    cancelled_by = v_uid, eta_seconds = null, updated_at = now()
  where id = r.id;
  perform public._escrow_refund(r.id, 'Refund: job cancelled');
end $$;

-- Who is on the other side of a job. Phone numbers are shared only after acceptance.
create or replace function public.request_counterpart(p_request_id uuid)
returns table (display_name text, phone text)
language plpgsql stable security definer set search_path = public as $$
declare r public.service_requests; v_uid uuid := auth.uid();
begin
  select * into r from public.service_requests where id = p_request_id;
  if r.id is null or v_uid not in (r.customer_id, r.mechanic_id) then return; end if;
  if v_uid = r.customer_id then
    return query select m.business_name, case when r.status in ('accepted', 'en_route', 'arrived', 'in_progress', 'completed') then p.phone end
      from public.mechanic_profiles m join public.profiles p on p.id = m.id where m.id = r.mechanic_id;
  else
    return query select coalesce(p.full_name, 'Driver'), case when r.status in ('accepted', 'en_route', 'arrived', 'in_progress', 'completed') then p.phone end
      from public.profiles p where p.id = r.customer_id;
  end if;
end $$;

-- Driver pays the quoted price into escrow. The mechanic sees it as secured
-- but cannot spend it until the driver confirms the job is done.
create or replace function public.fund_escrow(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.service_requests; v_uid uuid := auth.uid();
begin
  select * into r from public.service_requests where id = p_request_id for update;
  if r.id is null or r.customer_id <> v_uid then raise exception 'Request not found'; end if;
  if r.status not in ('accepted', 'en_route', 'arrived') then raise exception 'This job isn''t waiting for payment'; end if;
  if r.payment_status <> 'unpaid' then raise exception 'You''ve already paid for this job'; end if;
  if r.quoted_price_kobo is null then raise exception 'The mechanic hasn''t set a price yet'; end if;
  perform public._wallet_apply(v_uid, -r.quoted_price_kobo, 'escrow_hold', r.id, null, 'Held in escrow: ' || r.service_type);
  insert into public.escrow_holds (request_id, payer_id, payee_id, amount_kobo)
  values (r.id, v_uid, r.mechanic_id, r.quoted_price_kobo);
  update public.service_requests set payment_status = 'held', updated_at = now() where id = r.id;
end $$;

create or replace function public.release_escrow(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.service_requests;
begin
  select * into r from public.service_requests where id = p_request_id for update;
  if r.id is null or r.customer_id <> auth.uid() then raise exception 'Request not found'; end if;
  if r.status <> 'completed' then raise exception 'You can release payment once the job is complete'; end if;
  if r.payment_status not in ('held', 'disputed') then raise exception 'There''s no payment waiting on this job'; end if;
  perform public._escrow_release(r.id, 'Payment for ' || r.service_type);
end $$;

create or replace function public.dispute_escrow(p_request_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare r public.service_requests;
begin
  select * into r from public.service_requests where id = p_request_id for update;
  if r.id is null or r.customer_id <> auth.uid() then raise exception 'Request not found'; end if;
  if r.payment_status <> 'held' then raise exception 'Only held payments can be disputed'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Tell us what went wrong'; end if;
  update public.escrow_holds set status = 'disputed', dispute_reason = trim(p_reason) where request_id = r.id;
  update public.service_requests set payment_status = 'disputed', updated_at = now() where id = r.id;
end $$;

-- Pays mechanics automatically if the driver neither confirms nor disputes in time.
-- Schedule with pg_cron:  select cron.schedule('autowave-auto-release', '*/30 * * * *', 'select public.auto_release_escrow()');
create or replace function public.auto_release_escrow()
returns integer language plpgsql security definer set search_path = public as $$
declare v_id uuid; n integer := 0; v_hours integer;
begin
  select auto_release_hours into v_hours from public.app_config;
  for v_id in select r.id from public.service_requests r
              where r.status = 'completed' and r.payment_status = 'held'
                and r.completed_at < now() - make_interval(hours => coalesce(v_hours, 48)) loop
    perform public._escrow_release(v_id, 'Auto-released after ' || v_hours || ' hours');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.auto_release_escrow() from public, anon, authenticated;

-- Called by the Paystack Edge Functions (service role) after a verified payment.
create or replace function public.credit_topup(p_reference text, p_amount_kobo bigint, p_raw jsonb)
returns boolean language plpgsql security definer set search_path = public as $$
declare p public.payments;
begin
  select * into p from public.payments where reference = p_reference for update;
  if p.reference is null then raise exception 'Unknown payment reference'; end if;
  if p.status = 'success' then return false; end if;                 -- already credited
  if p_amount_kobo <> p.amount_kobo then raise exception 'Amount mismatch'; end if;
  update public.payments set status = 'success', raw = p_raw, verified_at = now() where reference = p_reference;
  perform public._wallet_apply(p.user_id, p.amount_kobo, 'topup', null, p_reference, 'Wallet top-up (Paystack)');
  return true;
end $$;
revoke all on function public.credit_topup(text, bigint, jsonb) from public, anon, authenticated;

-- Test money while Paystack isn't connected. Disabled by app_config.allow_test_topups.
create or replace function public.test_topup(p_amount_kobo bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if not (select allow_test_topups from public.app_config) then raise exception 'Test top-ups are switched off'; end if;
  if p_amount_kobo <= 0 or p_amount_kobo > 50000000 then raise exception 'Choose an amount up to ₦500,000'; end if;
  perform public._wallet_apply(auth.uid(), p_amount_kobo, 'test_topup', null, null, 'Test money (not real)');
end $$;

create or replace function public.wallet_summary()
returns table (available_kobo bigint, in_escrow_kobo bigint, incoming_kobo bigint, allow_test_topups boolean)
language sql stable security definer set search_path = public as $$
  select
    coalesce((select w.available_kobo from public.wallets w where w.user_id = auth.uid()), 0),
    coalesce((select sum(h.amount_kobo) from public.escrow_holds h where h.payer_id = auth.uid() and h.status in ('held', 'disputed')), 0)::bigint,
    coalesce((select sum(h.amount_kobo) from public.escrow_holds h where h.payee_id = auth.uid() and h.status in ('held', 'disputed')), 0)::bigint,
    (select c.allow_test_topups from public.app_config c);
$$;

create or replace function public.save_payout_account(p_bank_name text, p_bank_code text,
                                                     p_account_number text, p_account_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  insert into public.payout_accounts (user_id, bank_name, bank_code, account_number, account_name)
  values (auth.uid(), trim(p_bank_name), trim(p_bank_code), trim(p_account_number), nullif(trim(p_account_name), ''))
  on conflict (user_id) do update set bank_name = excluded.bank_name, bank_code = excluded.bank_code,
    account_number = excluded.account_number, account_name = excluded.account_name,
    recipient_code = null, updated_at = now();
end $$;

create or replace function public.request_withdrawal(p_amount_kobo bigint)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if not exists (select 1 from public.payout_accounts where user_id = auth.uid()) then
    raise exception 'Add your bank account first';
  end if;
  if p_amount_kobo < 10000 then raise exception 'The minimum withdrawal is ₦100'; end if;
  insert into public.withdrawals (user_id, amount_kobo) values (auth.uid(), p_amount_kobo) returning id into v_id;
  perform public._wallet_apply(auth.uid(), -p_amount_kobo, 'withdrawal', null, v_id::text, 'Withdrawal to bank');
  return v_id;
end $$;

-- Used by the payout function if a Paystack transfer fails.
create or replace function public.fail_withdrawal(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare w public.withdrawals;
begin
  select * into w from public.withdrawals where id = p_id for update;
  if w.id is null or w.status in ('paid', 'failed') then return; end if;
  update public.withdrawals set status = 'failed', failure_reason = p_reason, updated_at = now() where id = p_id;
  perform public._wallet_apply(w.user_id, w.amount_kobo, 'withdrawal_reversal', null, p_id::text, 'Withdrawal returned: ' || coalesce(p_reason, 'failed'));
end $$;
revoke all on function public.fail_withdrawal(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reviews (phase 2 display, written after phase 4 completion)
-- ---------------------------------------------------------------------------
create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null unique references public.service_requests (id) on delete cascade,
  customer_id uuid not null references public.profiles (id) on delete cascade,
  mechanic_id uuid not null references public.mechanic_profiles (id) on delete cascade,
  rating      integer not null check (rating between 1 and 5),
  comment     text check (char_length(comment) <= 500),
  created_at  timestamptz not null default now()
);
create index if not exists reviews_mechanic_idx on public.reviews (mechanic_id, created_at desc);

create or replace function public.refresh_mechanic_rating()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_mech uuid := coalesce(new.mechanic_id, old.mechanic_id);
begin
  update public.mechanic_profiles m set
    rating_avg = coalesce((select round(avg(rating)::numeric, 2) from public.reviews where mechanic_id = v_mech), 0),
    rating_count = (select count(*) from public.reviews where mechanic_id = v_mech)
  where m.id = v_mech;
  return null;
end $$;
drop trigger if exists reviews_refresh_rating on public.reviews;
create trigger reviews_refresh_rating after insert or update or delete on public.reviews
  for each row execute function public.refresh_mechanic_rating();

create or replace function public.mechanic_reviews(p_mechanic_id uuid, p_limit integer default 20)
returns table (id uuid, rating integer, comment text, created_at timestamptz, reviewer text, service_type text)
language sql stable security definer set search_path = public as $$
  select v.id, v.rating, v.comment, v.created_at,
         coalesce(split_part(nullif(trim(p.full_name), ''), ' ', 1), 'Driver') as reviewer, r.service_type
  from public.reviews v
  join public.service_requests r on r.id = v.request_id
  left join public.profiles p on p.id = v.customer_id
  where v.mechanic_id = p_mechanic_id and auth.uid() is not null
  order by v.created_at desc
  limit least(coalesce(p_limit, 20), 100);
$$;

-- ---------------------------------------------------------------------------
-- Phase 4: live location
-- ---------------------------------------------------------------------------
create table if not exists public.mechanic_locations (
  mechanic_id uuid primary key references public.mechanic_profiles (id) on delete cascade,
  latitude    double precision not null,
  longitude   double precision not null,
  heading     double precision,
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Phase 6: recycling
-- ---------------------------------------------------------------------------
create table if not exists public.recycling_rates (
  item_type    text primary key,
  label        text not null,
  unit         text not null check (unit in ('kg', 'unit', 'litre')),
  rate_kobo    bigint not null check (rate_kobo >= 0),   -- indicative price per unit
  co2_kg       numeric not null default 0,               -- indicative CO2e avoided per unit
  description  text,
  sort_order   integer not null default 0
);

insert into public.recycling_rates (item_type, label, unit, rate_kobo, co2_kg, description, sort_order) values
  ('lead_acid_battery', 'Car battery',          'unit',  350000, 9,   'Lead-acid starter batteries. Lead and acid are recovered safely.', 1),
  ('lithium_battery',   'Hybrid / EV battery',  'kg',     90000, 4,   'Lithium-ion packs and modules. Collected by trained handlers only.', 2),
  ('tyres',             'Tyres',                'unit',   50000, 15,  'Worn tyres for crumb rubber and road surfacing.', 3),
  ('used_oil',          'Used engine oil',      'litre',  15000, 3,   'Drained engine or gear oil, sealed in a container.', 4),
  ('scrap_metal',       'Scrap metal & parts',  'kg',      25000, 1.5, 'Body panels, rims, exhausts, engine blocks.', 5),
  ('end_of_life_vehicle','Whole vehicle',       'unit', 15000000, 1500,'Cars that can no longer be repaired. We collect and dismantle.', 6)
on conflict (item_type) do update set label = excluded.label, unit = excluded.unit, rate_kobo = excluded.rate_kobo,
  co2_kg = excluded.co2_kg, description = excluded.description, sort_order = excluded.sort_order;

create table if not exists public.recycling_centres (
  id        uuid primary key default gen_random_uuid(),
  name      text not null unique,
  address   text not null,
  lat       double precision not null,
  lng       double precision not null,
  accepts   text[] not null default '{}',
  phone     text,
  hours     text
);
-- Sample centres for testing. Replace with your real partners.
insert into public.recycling_centres (name, address, lat, lng, accepts, hours) values
  ('AutoWave Hub Yaba',       'Herbert Macaulay Way, Yaba, Lagos',  6.5146, 3.3760, '{lead_acid_battery,tyres,used_oil,scrap_metal}', 'Mon–Sat, 8am–6pm'),
  ('AutoWave Hub Ikeja',      'Obafemi Awolowo Way, Ikeja, Lagos',  6.6018, 3.3515, '{lead_acid_battery,lithium_battery,scrap_metal,end_of_life_vehicle}', 'Mon–Fri, 9am–5pm'),
  ('AutoWave Hub Lekki',      'Admiralty Way, Lekki Phase 1, Lagos',6.4474, 3.4727, '{lead_acid_battery,tyres,used_oil}', 'Mon–Sat, 9am–5pm')
on conflict (name) do nothing;

create table if not exists public.recycling_requests (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references public.profiles (id) on delete cascade,
  item_type            text not null references public.recycling_rates (item_type),
  quantity             numeric not null check (quantity > 0 and quantity <= 10000),
  condition            text,
  notes                text,
  method               text not null default 'pickup' check (method in ('pickup', 'dropoff')),
  centre_id            uuid references public.recycling_centres (id),
  pickup_address       text,
  pickup_lat           double precision,
  pickup_lng           double precision,
  preferred_date       date,
  estimated_value_kobo bigint not null default 0,
  estimated_co2_kg     numeric not null default 0,
  status               text not null default 'submitted' check (status in
                         ('submitted', 'scheduled', 'collected', 'paid', 'cancelled')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index if not exists recycling_requests_user_idx on public.recycling_requests (user_id, created_at desc);

create or replace function public.submit_recycling(
  p_item_type text, p_quantity numeric, p_condition text, p_notes text, p_method text,
  p_centre_id uuid, p_pickup_address text, p_pickup_lat double precision, p_pickup_lng double precision,
  p_preferred_date date)
returns uuid language plpgsql security definer set search_path = public as $$
declare rate public.recycling_rates; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select * into rate from public.recycling_rates where item_type = p_item_type;
  if rate.item_type is null then raise exception 'Choose what you''re recycling'; end if;
  if coalesce(p_quantity, 0) <= 0 then raise exception 'Enter how much you have'; end if;
  if p_method = 'pickup' and coalesce(trim(p_pickup_address), '') = '' then raise exception 'Add a pickup address'; end if;
  if p_method = 'dropoff' and p_centre_id is null then raise exception 'Choose a drop-off centre'; end if;
  if p_preferred_date is not null and p_preferred_date < current_date then raise exception 'Pick a date from today on'; end if;
  insert into public.recycling_requests (user_id, item_type, quantity, condition, notes, method, centre_id,
    pickup_address, pickup_lat, pickup_lng, preferred_date, estimated_value_kobo, estimated_co2_kg)
  values (auth.uid(), p_item_type, p_quantity, nullif(trim(p_condition), ''), nullif(trim(p_notes), ''),
    coalesce(p_method, 'pickup'), case when p_method = 'dropoff' then p_centre_id end,
    case when p_method = 'pickup' then trim(p_pickup_address) end, p_pickup_lat, p_pickup_lng, p_preferred_date,
    round(rate.rate_kobo * p_quantity)::bigint, round(rate.co2_kg * p_quantity, 1))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.cancel_recycling(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.recycling_requests set status = 'cancelled', updated_at = now()
  where id = p_id and user_id = auth.uid() and status in ('submitted', 'scheduled');
  if not found then raise exception 'This request can''t be cancelled now'; end if;
end $$;

-- Staff/admin (service role, e.g. from the dashboard): mark collected items paid into the wallet.
create or replace function public.pay_recycling(p_id uuid, p_final_kobo bigint)
returns void language plpgsql security definer set search_path = public as $$
declare r public.recycling_requests;
begin
  select * into r from public.recycling_requests where id = p_id for update;
  if r.id is null or r.status = 'paid' then return; end if;
  update public.recycling_requests set status = 'paid', updated_at = now() where id = p_id;
  perform public._wallet_apply(r.user_id, p_final_kobo, 'recycling_payout', null, p_id::text, 'Recycling payment');
end $$;
revoke all on function public.pay_recycling(uuid, bigint) from public, anon, authenticated;

create or replace function public.my_recycling_impact()
returns table (total_co2_kg numeric, total_paid_kobo bigint, items integer)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(estimated_co2_kg) filter (where status in ('collected', 'paid')), 0),
         coalesce((select sum(amount_kobo) from public.wallet_transactions
                   where user_id = auth.uid() and kind = 'recycling_payout'), 0)::bigint,
         count(*) filter (where status <> 'cancelled')::integer
  from public.recycling_requests where user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Phase 7: AutoLearn conversation history (written by the autolearn function)
-- ---------------------------------------------------------------------------
create table if not exists public.learn_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       text not null check (role in ('user', 'assistant')),
  content    text not null check (char_length(content) <= 8000),
  topic      text,
  level      text,
  language   text,
  created_at timestamptz not null default now()
);
create index if not exists learn_messages_user_idx on public.learn_messages (user_id, created_at);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.app_config          enable row level security;
alter table public.profiles            enable row level security;
alter table public.wallets             enable row level security;
alter table public.mechanic_profiles   enable row level security;
alter table public.service_requests    enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.escrow_holds        enable row level security;
alter table public.payments            enable row level security;
alter table public.payout_accounts     enable row level security;
alter table public.withdrawals         enable row level security;
alter table public.reviews             enable row level security;
alter table public.mechanic_locations  enable row level security;
alter table public.recycling_rates     enable row level security;
alter table public.recycling_centres   enable row level security;
alter table public.recycling_requests  enable row level security;
alter table public.learn_messages      enable row level security;

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles for select to authenticated using (id = auth.uid());

drop policy if exists "own wallet" on public.wallets;
create policy "own wallet" on public.wallets for select to authenticated using (user_id = auth.uid());

drop policy if exists "mechanics are listed" on public.mechanic_profiles;
create policy "mechanics are listed" on public.mechanic_profiles for select to authenticated using (true);

drop policy if exists "parties see the request" on public.service_requests;
create policy "parties see the request" on public.service_requests for select to authenticated
  using (customer_id = auth.uid() or mechanic_id = auth.uid());

drop policy if exists "own ledger" on public.wallet_transactions;
create policy "own ledger" on public.wallet_transactions for select to authenticated using (user_id = auth.uid());

drop policy if exists "parties see escrow" on public.escrow_holds;
create policy "parties see escrow" on public.escrow_holds for select to authenticated
  using (payer_id = auth.uid() or payee_id = auth.uid());

drop policy if exists "own payments" on public.payments;
create policy "own payments" on public.payments for select to authenticated using (user_id = auth.uid());

drop policy if exists "own payout account" on public.payout_accounts;
create policy "own payout account" on public.payout_accounts for select to authenticated using (user_id = auth.uid());

drop policy if exists "own withdrawals" on public.withdrawals;
create policy "own withdrawals" on public.withdrawals for select to authenticated using (user_id = auth.uid());

drop policy if exists "reviews are public" on public.reviews;
create policy "reviews are public" on public.reviews for select to authenticated using (true);
drop policy if exists "driver reviews a completed job" on public.reviews;
create policy "driver reviews a completed job" on public.reviews for insert to authenticated
  with check (customer_id = auth.uid() and exists (
    select 1 from public.service_requests r
    where r.id = request_id and r.customer_id = auth.uid() and r.mechanic_id = reviews.mechanic_id and r.status = 'completed'));

drop policy if exists "mechanic shares own location" on public.mechanic_locations;
create policy "mechanic shares own location" on public.mechanic_locations for all to authenticated
  using (mechanic_id = auth.uid()) with check (mechanic_id = auth.uid());
drop policy if exists "driver sees mechanic on an active job" on public.mechanic_locations;
create policy "driver sees mechanic on an active job" on public.mechanic_locations for select to authenticated
  using (exists (select 1 from public.service_requests r
                 where r.mechanic_id = mechanic_locations.mechanic_id and r.customer_id = auth.uid()
                   and r.status in ('accepted', 'en_route', 'arrived')));

drop policy if exists "rates are public" on public.recycling_rates;
create policy "rates are public" on public.recycling_rates for select to authenticated using (true);
drop policy if exists "centres are public" on public.recycling_centres;
create policy "centres are public" on public.recycling_centres for select to authenticated using (true);
drop policy if exists "own recycling" on public.recycling_requests;
create policy "own recycling" on public.recycling_requests for select to authenticated using (user_id = auth.uid());

drop policy if exists "own lessons" on public.learn_messages;
create policy "own lessons" on public.learn_messages for select to authenticated using (user_id = auth.uid());
drop policy if exists "clear own lessons" on public.learn_messages;
create policy "clear own lessons" on public.learn_messages for delete to authenticated using (user_id = auth.uid());

-- Internal helpers are not callable from the apps.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.refresh_mechanic_rating() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Realtime: the apps stream these tables
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['service_requests', 'mechanic_locations', 'wallets', 'escrow_holds'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                   and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
exception when undefined_object then
  raise notice 'supabase_realtime publication not found; enable Realtime for these tables in the dashboard';
end $$;
