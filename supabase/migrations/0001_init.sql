-- =====================================================================
-- HACCP & Sicurezza sul lavoro - Schema iniziale (Supabase / PostgreSQL 15+)
-- Multi-tenant (company_id su ogni tabella), RLS, registri append-only,
-- hash chain, audit log. PK uuid generate lato client (offline-first).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- ENUM
-- ---------------------------------------------------------------------
create type app_role            as enum ('admin', 'employee', 'consultant');
create type control_point_kind  as enum ('fridge', 'freezer', 'display', 'blast_chiller', 'hot_holding', 'other');
create type reading_source      as enum ('manual', 'sensor');
create type product_fate        as enum ('kept', 'discarded', 'reworked', 'quarantined', 'not_applicable');
create type cleaning_frequency  as enum ('daily', 'weekly', 'monthly', 'on_event');
create type cleaning_status     as enum ('done', 'skipped', 'not_applicable');
create type training_category   as enum ('haccp', 'fire', 'first_aid', 'general_safety', 'specific_safety',
                                         'rspp', 'rls', 'preposto', 'health_fitness', 'other');
create type document_status     as enum ('draft', 'active', 'superseded', 'expired');
create type contractor_doc_type as enum ('chamber_of_commerce', 'durc', 'insurance', 'technical_fitness', 'dvr', 'other');
create type duvri_status        as enum ('draft', 'signed', 'closed');

-- ---------------------------------------------------------------------
-- UTILITY: updated_at
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  NEW.updated_at := now();
  return NEW;
end $$;

-- ---------------------------------------------------------------------
-- 1. ANAGRAFICHE, UTENTI E RUOLI
-- ---------------------------------------------------------------------
create table public.companies (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  legal_name    text,
  vat_number    text,
  fiscal_code   text,
  activity_type text,                       -- bar, ristorante, pizzeria, retail...
  address       text,
  created_by    uuid default auth.uid() references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  phone      text,
  locale     text not null default 'it',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Appartenenza utente-azienda con ruolo. Un consulente puo' avere piu' aziende.
create table public.company_members (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       app_role not null,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, user_id)
);
create index on public.company_members (user_id) where active;

create table public.sites (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id),
  name        text not null,
  address     text,
  city        text,
  province    text,
  postal_code text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index on public.sites (company_id);

create table public.areas (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  site_id    uuid not null references public.sites(id),
  name       text not null,                 -- cucina, bar, magazzino, cella 1...
  kind       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index on public.areas (site_id);

create table public.job_roles (               -- mansioni
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id),
  name        text not null,
  description text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- Dipendenti: possono NON avere un login (es. tablet condiviso in cucina con PIN).
create table public.employees (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id),
  site_id          uuid references public.sites(id),
  user_id          uuid references auth.users(id),
  job_role_id      uuid references public.job_roles(id),
  first_name       text not null,
  last_name        text not null,
  tax_code         text,
  hire_date        date,
  termination_date date,
  is_supervisor    boolean not null default false,
  active           boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);
create index on public.employees (company_id);
create unique index on public.employees (company_id, user_id) where user_id is not null;

-- PIN operatore: serve ad ATTRIBUIRE la registrazione a una persona sul tablet
-- condiviso (non e' autenticazione forte). Hash bcrypt.
create table public.employee_pins (
  employee_id uuid primary key references public.employees(id) on delete cascade,
  company_id  uuid not null references public.companies(id),
  pin_hash    text not null,
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. FUNZIONI DI SUPPORTO RLS
-- ---------------------------------------------------------------------
create or replace function public.is_member(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from company_members
                 where company_id = p_company and user_id = auth.uid() and active)
$$;

create or replace function public.is_admin(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from company_members
                 where company_id = p_company and user_id = auth.uid() and active and role = 'admin')
$$;

create or replace function public.can_write(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from company_members
                 where company_id = p_company and user_id = auth.uid() and active
                   and role in ('admin', 'employee'))
$$;

-- Creazione azienda + membership admin (bootstrap del primo utente)
create or replace function public.create_company(p_name text, p_vat text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Non autenticato'; end if;
  insert into companies (name, vat_number) values (p_name, p_vat) returning id into v_id;
  insert into company_members (company_id, user_id, role) values (v_id, auth.uid(), 'admin');
  return v_id;
end $$;

create or replace function public.set_employee_pin(p_employee uuid, p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_company uuid;
begin
  select company_id into v_company from employees where id = p_employee;
  if v_company is null or not is_admin(v_company) then raise exception 'Operazione non consentita'; end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'Il PIN deve essere di 4-8 cifre'; end if;
  insert into employee_pins (employee_id, company_id, pin_hash)
  values (p_employee, v_company, crypt(p_pin, gen_salt('bf', 8)))
  on conflict (employee_id) do update set pin_hash = excluded.pin_hash, updated_at = now();
end $$;

create or replace function public.verify_employee_pin(p_employee uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_company uuid; v_hash text;
begin
  select company_id into v_company from employees where id = p_employee;
  if v_company is null or not can_write(v_company) then return false; end if;
  select pin_hash into v_hash from employee_pins where employee_id = p_employee;
  return v_hash is not null and v_hash = crypt(p_pin, v_hash);
end $$;

-- Profilo automatico alla registrazione
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, full_name) values (NEW.id, NEW.raw_user_meta_data->>'full_name')
  on conflict do nothing;
  return NEW;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 3. HACCP - REGISTRO TEMPERATURE
-- ---------------------------------------------------------------------
create table public.temp_control_points (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id),
  site_id          uuid not null references public.sites(id),
  area_id          uuid references public.areas(id),
  name             text not null,
  kind             control_point_kind not null default 'fridge',
  min_temp_c       numeric(5,2),
  max_temp_c       numeric(5,2),
  readings_per_day smallint not null default 1 check (readings_per_day between 0 and 24),
  sensor_id        text,                       -- predisposizione IoT
  qr_code          text,
  active           boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  check (min_temp_c is null or max_temp_c is null or min_temp_c <= max_temp_c)
);
create index on public.temp_control_points (company_id, site_id);

-- REGISTRO APPEND-ONLY: nessun update/delete. Le correzioni sono nuovi record.
create table public.temp_readings (
  id               uuid primary key,            -- generato dal client (offline)
  seq              bigint generated always as identity,
  company_id       uuid not null references public.companies(id),
  site_id          uuid not null references public.sites(id),
  control_point_id uuid not null references public.temp_control_points(id),
  value_c          numeric(5,2) not null check (value_c between -100 and 300),
  measured_at      timestamptz not null,        -- ora del dispositivo
  received_at      timestamptz not null default now(), -- ora server (forzata da trigger)
  employee_id      uuid references public.employees(id),
  recorded_by      uuid references auth.users(id),
  source           reading_source not null default 'manual',
  device_id        text,
  min_c_snapshot   numeric(5,2),                -- limiti validi al momento della registrazione
  max_c_snapshot   numeric(5,2),
  out_of_range     boolean not null default false,
  notes            text,
  prev_hash        text,
  row_hash         text
);
create index on public.temp_readings (control_point_id, measured_at desc);
create index on public.temp_readings (company_id, measured_at desc);
create index on public.temp_readings (company_id) where out_of_range;

create table public.temp_corrective_actions (
  id                uuid primary key,
  company_id        uuid not null references public.companies(id),
  reading_id        uuid not null references public.temp_readings(id),
  cause             text,
  action_taken      text not null,
  product_fate      product_fate not null default 'not_applicable',
  retest_reading_id uuid references public.temp_readings(id),
  employee_id       uuid references public.employees(id),
  performed_at      timestamptz not null default now(),
  signature_path    text,
  signature_hash    text,
  notes             text,
  received_at       timestamptz not null default now()
);
create index on public.temp_corrective_actions (reading_id);

-- ---------------------------------------------------------------------
-- 4. HACCP - PULIZIE E SANIFICAZIONE
-- ---------------------------------------------------------------------
create table public.cleaning_products (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id),
  name              text not null,
  active_ingredient text,
  sds_path          text,                       -- scheda di sicurezza
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create table public.cleaning_plans (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id),
  site_id           uuid not null references public.sites(id),
  area_id           uuid references public.areas(id),
  name              text not null,
  description       text,
  frequency         cleaning_frequency not null default 'daily',
  weekdays          smallint[],                  -- ISO 1=lun .. 7=dom (weekly)
  day_of_month      smallint check (day_of_month between 1 and 31),
  shift             text,                        -- apertura / chiusura / ...
  product_id        uuid references public.cleaning_products(id),
  method            text,
  dilution          text,
  contact_time_min  smallint,
  requires_approval boolean not null default false,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index on public.cleaning_plans (company_id, site_id);

create table public.cleaning_plan_items (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id),
  plan_id     uuid not null references public.cleaning_plans(id),
  description text not null,
  sort_order  smallint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table public.cleaning_logs (            -- APPEND-ONLY
  id             uuid primary key,
  seq            bigint generated always as identity,
  company_id     uuid not null references public.companies(id),
  site_id        uuid not null references public.sites(id),
  plan_id        uuid not null references public.cleaning_plans(id),
  due_date       date not null,
  status         cleaning_status not null default 'done',
  employee_id    uuid references public.employees(id),
  recorded_by    uuid references auth.users(id),
  performed_at   timestamptz not null,
  received_at    timestamptz not null default now(),
  device_id      text,
  notes          text,
  signature_path text,
  signature_hash text,
  prev_hash      text,
  row_hash       text
);
create index on public.cleaning_logs (plan_id, due_date desc);
create index on public.cleaning_logs (company_id, due_date desc);

create table public.cleaning_log_items (       -- APPEND-ONLY
  id           uuid primary key,
  company_id   uuid not null references public.companies(id),
  log_id       uuid not null references public.cleaning_logs(id),
  plan_item_id uuid references public.cleaning_plan_items(id),
  done         boolean not null default true
);
create index on public.cleaning_log_items (log_id);

create table public.cleaning_log_approvals (   -- controfirma del responsabile, APPEND-ONLY
  id             uuid primary key,
  company_id     uuid not null references public.companies(id),
  log_id         uuid not null unique references public.cleaning_logs(id),
  employee_id    uuid not null references public.employees(id),
  approved_at    timestamptz not null default now(),
  signature_path text,
  signature_hash text
);

-- ---------------------------------------------------------------------
-- 5. FORMAZIONE E SCADENZARIO
-- ---------------------------------------------------------------------
-- company_id NULL = catalogo globale. Durate indicative: da verificare con
-- RSPP / normativa regionale (es. HACCP varia per Regione) e modificabili.
create table public.training_types (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid references public.companies(id),
  code            text not null,
  name            text not null,
  category        training_category not null default 'other',
  validity_months smallint,                     -- NULL = senza scadenza
  default_hours   numeric(4,1),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create unique index on public.training_types
  ((coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid)), code);

create table public.job_role_training_requirements (
  job_role_id      uuid not null references public.job_roles(id),
  training_type_id uuid not null references public.training_types(id),
  company_id       uuid not null references public.companies(id),
  primary key (job_role_id, training_type_id)
);

create table public.training_records (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id),
  employee_id      uuid not null references public.employees(id),
  training_type_id uuid not null references public.training_types(id),
  issued_on        date not null,
  expires_on       date,                        -- calcolata da validity_months se NULL
  provider         text,
  hours            numeric(4,1),
  certificate_path text,
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);
create index on public.training_records (employee_id, training_type_id, issued_on desc);
create index on public.training_records (company_id, expires_on);

-- ---------------------------------------------------------------------
-- 6. DPI
-- ---------------------------------------------------------------------
create table public.ppe_types (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references public.companies(id),
  name                 text not null,
  category             smallint check (category between 1 and 3),  -- I, II, III
  standard_en          text,                    -- es. EN ISO 20345
  description          text,
  replace_after_months smallint,
  manual_path          text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);

create table public.job_role_ppe (
  job_role_id uuid not null references public.job_roles(id),
  ppe_type_id uuid not null references public.ppe_types(id),
  company_id  uuid not null references public.companies(id),
  primary key (job_role_id, ppe_type_id)
);

create table public.ppe_assignments (
  id             uuid primary key,
  company_id     uuid not null references public.companies(id),
  employee_id    uuid not null references public.employees(id),
  ppe_type_id    uuid not null references public.ppe_types(id),
  size           text,
  serial_number  text,
  quantity       smallint not null default 1 check (quantity > 0),
  delivered_on   date not null,
  expires_on     date,                          -- calcolata da replace_after_months se NULL
  delivered_by   uuid references public.employees(id),
  signature_path text,                          -- firma del lavoratore alla consegna
  signature_hash text,
  returned_on    date,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on public.ppe_assignments (employee_id);
create index on public.ppe_assignments (company_id, expires_on) where returned_on is null;

-- ---------------------------------------------------------------------
-- 7. DVR / DUVRI
-- ---------------------------------------------------------------------
create table public.dvr_documents (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references public.companies(id),
  site_id              uuid references public.sites(id),
  version              text not null,
  status               document_status not null default 'draft',
  issued_on            date,
  next_review_on       date,
  review_reason        text,
  file_path            text,
  file_sha256          text,
  signed_at            timestamptz,
  timestamp_proof_path text,                    -- marca temporale / PEC (data certa art. 28)
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);
create index on public.dvr_documents (company_id, status);

create table public.contractors (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references public.companies(id),
  name         text not null,
  vat_number   text,
  contact_name text,
  email        text,
  phone        text,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create table public.contractor_documents (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.companies(id),
  contractor_id uuid not null references public.contractors(id),
  doc_type      contractor_doc_type not null,
  issued_on     date,
  expires_on    date,
  file_path     text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index on public.contractor_documents (company_id, expires_on);

create table public.duvri_documents (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references public.companies(id),
  site_id              uuid references public.sites(id),
  contractor_id        uuid not null references public.contractors(id),
  activity_description text not null,
  areas_involved       text,
  interference_risks   jsonb not null default '[]'::jsonb,
  safety_measures      jsonb not null default '[]'::jsonb,
  safety_costs_eur     numeric(10,2),
  starts_on            date,
  ends_on              date,
  status               duvri_status not null default 'draft',
  file_path            text,
  signed_at            timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);

-- ---------------------------------------------------------------------
-- 8. AUDIT LOG
-- ---------------------------------------------------------------------
create table public.audit_log (
  id         bigint generated always as identity primary key,
  company_id uuid,
  table_name text not null,
  record_id  text,
  action     text not null,
  actor      uuid default auth.uid(),
  changed_at timestamptz not null default now(),
  old_data   jsonb,
  new_data   jsonb
);
create index on public.audit_log (company_id, changed_at desc);

create or replace function public.audit_row() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_row jsonb := to_jsonb(coalesce(NEW, OLD));
begin
  insert into audit_log (company_id, table_name, record_id, action, old_data, new_data)
  values ((v_row->>'company_id')::uuid, TG_TABLE_NAME, v_row->>'id', TG_OP,
          case when TG_OP in ('UPDATE','DELETE') then to_jsonb(OLD) end,
          case when TG_OP in ('INSERT','UPDATE') then to_jsonb(NEW) end);
  return coalesce(NEW, OLD);
end $$;

-- ---------------------------------------------------------------------
-- 9. TRIGGER: INALTERABILITA', HASH CHAIN, CALCOLI AUTOMATICI
-- ---------------------------------------------------------------------
create or replace function public.forbid_mutation() returns trigger
language plpgsql as $$
begin
  raise exception 'Il registro % e'' inalterabile: inserire una registrazione correttiva.', TG_TABLE_NAME
    using errcode = '42501';
end $$;

-- Hash chain per azienda e per registro: ogni riga include l'hash della precedente.
create or replace function public.chain_hash() returns trigger
language plpgsql set search_path = public, extensions as $$
declare v_prev text;
begin
  perform pg_advisory_xact_lock(hashtext(TG_TABLE_NAME || NEW.company_id::text));
  execute format('select row_hash from %I.%I where company_id = $1 order by seq desc limit 1',
                 TG_TABLE_SCHEMA, TG_TABLE_NAME)
    into v_prev using NEW.company_id;
  NEW.prev_hash := v_prev;
  NEW.row_hash  := encode(digest(coalesce(v_prev, '') ||
                     (to_jsonb(NEW) - 'row_hash' - 'prev_hash')::text, 'sha256'), 'hex');
  return NEW;
end $$;

create or replace function public.temp_readings_prepare() returns trigger
language plpgsql as $$
declare v_min numeric; v_max numeric; v_company uuid;
begin
  select company_id, min_temp_c, max_temp_c into v_company, v_min, v_max
  from temp_control_points where id = NEW.control_point_id;
  if not found or v_company <> NEW.company_id then
    raise exception 'Punto di controllo non valido per questa azienda';
  end if;
  NEW.min_c_snapshot := v_min;
  NEW.max_c_snapshot := v_max;
  NEW.out_of_range   := (v_min is not null and NEW.value_c < v_min)
                     or (v_max is not null and NEW.value_c > v_max);
  NEW.received_at    := now();
  NEW.recorded_by    := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

create or replace function public.cleaning_logs_prepare() returns trigger
language plpgsql as $$
begin
  NEW.received_at := now();
  NEW.recorded_by := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

create or replace function public.training_records_defaults() returns trigger
language plpgsql as $$
declare v_months smallint;
begin
  if NEW.expires_on is null then
    select validity_months into v_months from training_types where id = NEW.training_type_id;
    if v_months is not null then
      NEW.expires_on := (NEW.issued_on + make_interval(months => v_months))::date;
    end if;
  end if;
  return NEW;
end $$;

create or replace function public.ppe_assignments_defaults() returns trigger
language plpgsql as $$
declare v_months smallint;
begin
  if NEW.expires_on is null then
    select replace_after_months into v_months from ppe_types where id = NEW.ppe_type_id;
    if v_months is not null then
      NEW.expires_on := (NEW.delivered_on + make_interval(months => v_months))::date;
    end if;
  end if;
  return NEW;
end $$;

create trigger temp_readings_1_prepare before insert on public.temp_readings
  for each row execute function public.temp_readings_prepare();
create trigger temp_readings_2_chain before insert on public.temp_readings
  for each row execute function public.chain_hash();
create trigger cleaning_logs_1_prepare before insert on public.cleaning_logs
  for each row execute function public.cleaning_logs_prepare();
create trigger cleaning_logs_2_chain before insert on public.cleaning_logs
  for each row execute function public.chain_hash();
create trigger training_records_defaults before insert or update on public.training_records
  for each row execute function public.training_records_defaults();
create trigger ppe_assignments_defaults before insert or update on public.ppe_assignments
  for each row execute function public.ppe_assignments_defaults();

do $$
declare t text;
begin
  -- registri inalterabili
  foreach t in array array['temp_readings','temp_corrective_actions','cleaning_logs',
                           'cleaning_log_items','cleaning_log_approvals','audit_log'] loop
    execute format('create trigger %I before update or delete on public.%I
                    for each row execute function public.forbid_mutation()', t || '_immutable', t);
  end loop;

  -- updated_at
  foreach t in array array['companies','profiles','company_members','sites','areas','job_roles','employees',
                           'temp_control_points','cleaning_products','cleaning_plans','cleaning_plan_items',
                           'training_types','training_records','ppe_types','ppe_assignments',
                           'dvr_documents','contractors','contractor_documents','duvri_documents'] loop
    execute format('create trigger %I before update on public.%I
                    for each row execute function public.set_updated_at()', t || '_updated_at', t);
  end loop;

  -- audit sulle tabelle modificabili sensibili
  foreach t in array array['company_members','employees','temp_control_points','cleaning_plans',
                           'training_records','ppe_assignments','dvr_documents','contractor_documents',
                           'duvri_documents'] loop
    execute format('create trigger %I after insert or update or delete on public.%I
                    for each row execute function public.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 10. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  -- Configurazione: lettura ai membri, scrittura solo admin
  foreach t in array array['sites','areas','job_roles','employees','temp_control_points','cleaning_products',
                           'cleaning_plans','cleaning_plan_items','job_role_training_requirements',
                           'ppe_types','job_role_ppe','contractors','training_records',
                           'dvr_documents','duvri_documents','contractor_documents'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (public.is_member(company_id))',
                   t || '_select', t);
    execute format('create policy %I on public.%I for all using (public.is_admin(company_id))
                    with check (public.is_admin(company_id))', t || '_admin_write', t);
  end loop;

  -- Registri append-only: lettura ai membri, inserimento admin/operatore (mai il consulente)
  foreach t in array array['temp_readings','temp_corrective_actions','cleaning_logs',
                           'cleaning_log_items','cleaning_log_approvals'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (public.is_member(company_id))',
                   t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (public.can_write(company_id))',
                   t || '_insert', t);
  end loop;
end $$;

-- companies: nessun insert diretto (usare create_company())
alter table public.companies enable row level security;
create policy companies_select on public.companies for select using (public.is_member(id));
create policy companies_update on public.companies for update
  using (public.is_admin(id)) with check (public.is_admin(id));

alter table public.profiles enable row level security;
create policy profiles_select on public.profiles for select using (
  id = auth.uid() or exists (select 1 from public.company_members m
                             where m.user_id = profiles.id and public.is_member(m.company_id)));
create policy profiles_update_own on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

alter table public.company_members enable row level security;
create policy company_members_select on public.company_members for select
  using (user_id = auth.uid() or public.is_member(company_id));
create policy company_members_admin_write on public.company_members for all
  using (public.is_admin(company_id)) with check (public.is_admin(company_id));

alter table public.employee_pins enable row level security;
create policy employee_pins_select on public.employee_pins for select using (public.can_write(company_id));

alter table public.training_types enable row level security;
create policy training_types_select on public.training_types for select
  using (company_id is null or public.is_member(company_id));
create policy training_types_admin_write on public.training_types for all
  using (company_id is not null and public.is_admin(company_id))
  with check (company_id is not null and public.is_admin(company_id));

-- DPI: l'operatore puo' registrare una consegna firmata; modifiche/resi solo admin
alter table public.ppe_assignments enable row level security;
create policy ppe_assignments_select on public.ppe_assignments for select using (public.is_member(company_id));
create policy ppe_assignments_insert on public.ppe_assignments for insert with check (public.can_write(company_id));
create policy ppe_assignments_admin_update on public.ppe_assignments for update
  using (public.is_admin(company_id)) with check (public.is_admin(company_id));

alter table public.audit_log enable row level security;
create policy audit_log_select on public.audit_log for select
  using (company_id is not null and (public.is_admin(company_id) or exists (
    select 1 from public.company_members m
    where m.company_id = audit_log.company_id and m.user_id = auth.uid() and m.active and m.role = 'consultant')));

-- ---------------------------------------------------------------------
-- 11. VISTE (security_invoker: rispettano la RLS dell'utente)
-- ---------------------------------------------------------------------
create or replace view public.v_open_temp_deviations with (security_invoker = true) as
select r.*
from public.temp_readings r
where r.out_of_range
  and not exists (select 1 from public.temp_corrective_actions a where a.reading_id = r.id);

create or replace view public.v_deadlines with (security_invoker = true) as
select x.*, (x.due_on - current_date) as days_left
from (
  with last_training as (
    select distinct on (employee_id, training_type_id) *
    from public.training_records
    where expires_on is not null and deleted_at is null
    order by employee_id, training_type_id, issued_on desc
  )
  select lt.company_id, 'training'::text as kind, lt.employee_id, lt.id as record_id,
         tt.name as label, lt.expires_on as due_on
  from last_training lt join public.training_types tt on tt.id = lt.training_type_id
  union all
  select a.company_id, 'ppe'::text, a.employee_id, a.id, p.name, a.expires_on
  from public.ppe_assignments a join public.ppe_types p on p.id = a.ppe_type_id
  where a.expires_on is not null and a.returned_on is null
  union all
  select d.company_id, 'dvr_review'::text, null::uuid, d.id, ('Revisione DVR ' || d.version)::text, d.next_review_on
  from public.dvr_documents d
  where d.status = 'active' and d.next_review_on is not null and d.deleted_at is null
  union all
  select c.company_id, 'contractor_doc'::text, null::uuid, c.id, (k.name || ' - ' || c.doc_type::text)::text, c.expires_on
  from public.contractor_documents c join public.contractors k on k.id = c.contractor_id
  where c.expires_on is not null and c.deleted_at is null
) x;

create or replace view public.v_missing_training with (security_invoker = true) as
select e.company_id, e.id as employee_id, r.training_type_id
from public.employees e
join public.job_role_training_requirements r on r.job_role_id = e.job_role_id
where e.active and e.deleted_at is null
  and not exists (
    select 1 from public.training_records tr
    where tr.employee_id = e.id and tr.training_type_id = r.training_type_id
      and tr.deleted_at is null and (tr.expires_on is null or tr.expires_on >= current_date));

-- ---------------------------------------------------------------------
-- 12. CATALOGO GLOBALE FORMAZIONE (durate indicative, modificabili)
-- ---------------------------------------------------------------------
insert into public.training_types (company_id, code, name, category, validity_months, default_hours) values
  (null, 'HACCP',       'Formazione HACCP / Alimentarista',               'haccp',           36,   null),
  (null, 'FIRE_LOW',    'Addetto antincendio (rischio basso)',            'fire',            60,   4),
  (null, 'FIRST_AID',   'Addetto primo soccorso',                         'first_aid',       36,   12),
  (null, 'SAFETY_GEN',  'Formazione generale lavoratori',                 'general_safety',  null, 4),
  (null, 'SAFETY_SPEC', 'Formazione specifica lavoratori',                'specific_safety', 60,   4),
  (null, 'PREPOSTO',    'Formazione preposto',                            'preposto',        24,   8),
  (null, 'RLS',         'Rappresentante dei lavoratori (RLS)',            'rls',             12,   4),
  (null, 'RSPP',        'RSPP / ASPP (aggiornamento)',                    'rspp',            60,   null),
  (null, 'HEALTH_FIT',  'Idoneita'' sanitaria (sorveglianza sanitaria)',  'health_fitness',  12,   null);
