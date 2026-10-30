-- =====================================================================
-- 0003 - Tracciabilita' e ricevimento merci (A3)
-- Fornitori, prodotti, ricevimenti con righe/lotti, ritiri, foto bolle.
-- Ricevimenti, righe e ritiri sono registri APPEND-ONLY.
-- =====================================================================

create type receipt_outcome as enum ('accepted', 'accepted_with_reservation', 'rejected');
create type expiry_kind     as enum ('use_by', 'best_before');   -- scadenza / TMC
create type recall_action   as enum ('withdrawn', 'discarded', 'returned_to_supplier', 'authority_notified');

-- ---------------------------------------------------------------------
-- 1. ANAGRAFICHE (l'operatore puo' aggiungere al volo, solo l'admin modifica)
-- ---------------------------------------------------------------------
create table public.suppliers (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references public.companies(id),
  name         text not null,
  vat_number   text,
  contact_name text,
  phone        text,
  email        text,
  notes        text,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index on public.suppliers (company_id);

create table public.products (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references public.companies(id),
  supplier_id    uuid references public.suppliers(id),
  name           text not null,
  category       text,
  delivery_min_c numeric(5,2),               -- limiti di temperatura alla consegna
  delivery_max_c numeric(5,2),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  check (delivery_min_c is null or delivery_max_c is null or delivery_min_c <= delivery_max_c)
);
create index on public.products (company_id);

-- ---------------------------------------------------------------------
-- 2. RICEVIMENTI (APPEND-ONLY)
-- ---------------------------------------------------------------------
create table public.goods_receipts (
  id                 uuid primary key,          -- generato dal client
  seq                bigint generated always as identity,
  company_id         uuid not null references public.companies(id),
  site_id            uuid not null references public.sites(id),
  supplier_id        uuid not null references public.suppliers(id),
  doc_number         text,
  doc_date           date not null,
  received_at        timestamptz not null,       -- ora del dispositivo
  received_server_at timestamptz not null default now(),
  employee_id        uuid references public.employees(id),
  recorded_by        uuid references auth.users(id),
  vehicle_ok         boolean not null default true,
  doc_photo_path     text,
  doc_photo_hash     text,
  notes              text,
  prev_hash          text,
  row_hash           text
);
create index on public.goods_receipts (company_id, received_at desc);
create index on public.goods_receipts (supplier_id);

create table public.goods_receipt_lines (
  id                uuid primary key,
  company_id        uuid not null references public.companies(id),
  receipt_id        uuid not null references public.goods_receipts(id),
  sort_order        smallint not null default 0,
  product_id        uuid references public.products(id),
  product_name      text not null,
  lot_code          text,
  expiry_date       date,
  expiry_kind       expiry_kind not null default 'use_by',
  quantity          numeric(10,3),
  unit              text,
  temp_c            numeric(5,2),
  min_limit_c       numeric(5,2),
  max_limit_c       numeric(5,2),
  temp_out_of_range boolean not null default false,   -- calcolato dal trigger
  expired           boolean not null default false,   -- calcolato dal trigger
  packaging_ok      boolean not null default true,
  label_ok          boolean not null default true,
  outcome           receipt_outcome not null default 'accepted',
  notes             text,
  -- respinto o accettato con riserva: il motivo e' obbligatorio
  check (outcome = 'accepted' or nullif(btrim(coalesce(notes, '')), '') is not null)
);
create index on public.goods_receipt_lines (receipt_id);
create index on public.goods_receipt_lines (company_id, lower(lot_code));
create index on public.goods_receipt_lines (company_id, expiry_date);

-- ---------------------------------------------------------------------
-- 3. RITIRI / RICHIAMI (APPEND-ONLY)
-- ---------------------------------------------------------------------
create table public.product_recalls (
  id                 uuid primary key,
  company_id         uuid not null references public.companies(id),
  line_id            uuid references public.goods_receipt_lines(id),
  lot_code           text not null,
  product_name       text not null,
  action             recall_action not null,
  quantity           numeric(10,3),
  unit               text,
  reason             text not null check (btrim(reason) <> ''),
  performed_at       timestamptz not null,
  received_server_at timestamptz not null default now(),
  employee_id        uuid references public.employees(id),
  recorded_by        uuid references auth.users(id),
  notes              text
);
create index on public.product_recalls (company_id, lower(lot_code));

-- ---------------------------------------------------------------------
-- 4. TRIGGER
-- ---------------------------------------------------------------------
create or replace function public.goods_receipts_prepare() returns trigger
language plpgsql as $$
declare v_supplier_company uuid; v_site_company uuid;
begin
  select company_id into v_supplier_company from suppliers where id = NEW.supplier_id;
  if v_supplier_company is distinct from NEW.company_id then
    raise exception 'Fornitore non valido per questa azienda';
  end if;
  select company_id into v_site_company from sites where id = NEW.site_id;
  if v_site_company is distinct from NEW.company_id then
    raise exception 'Sede non valida per questa azienda';
  end if;
  NEW.received_server_at := now();
  NEW.recorded_by := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

-- Calcola i flag e impedisce di accettare cio' che non si puo' accettare:
--  - scadenza (use_by) superata  -> solo "respinto"
--  - TMC superato / temperatura fuori limite -> mai "accettato" senza riserva
create or replace function public.goods_receipt_lines_prepare() returns trigger
language plpgsql as $$
declare v_company uuid; v_received timestamptz; v_day date;
begin
  select company_id, received_at into v_company, v_received
  from goods_receipts where id = NEW.receipt_id;
  if v_company is distinct from NEW.company_id then
    raise exception 'Ricevimento non valido per questa azienda';
  end if;

  v_day := (v_received at time zone 'Europe/Rome')::date;

  NEW.temp_out_of_range := NEW.temp_c is not null and (
       (NEW.min_limit_c is not null and NEW.temp_c < NEW.min_limit_c)
    or (NEW.max_limit_c is not null and NEW.temp_c > NEW.max_limit_c));
  NEW.expired := NEW.expiry_date is not null and NEW.expiry_date < v_day;

  if NEW.expired and NEW.expiry_kind = 'use_by' and NEW.outcome <> 'rejected' then
    raise exception 'Prodotto con scadenza superata: deve essere respinto';
  end if;
  if (NEW.expired or NEW.temp_out_of_range) and NEW.outcome = 'accepted' then
    raise exception 'Prodotto scaduto o fuori temperatura: non puo'' essere accettato senza riserva';
  end if;
  return NEW;
end $$;

create or replace function public.product_recalls_prepare() returns trigger
language plpgsql as $$
begin
  NEW.received_server_at := now();
  NEW.recorded_by := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

create trigger goods_receipts_1_prepare before insert on public.goods_receipts
  for each row execute function public.goods_receipts_prepare();
create trigger goods_receipts_2_chain before insert on public.goods_receipts
  for each row execute function public.chain_hash();
create trigger goods_receipt_lines_prepare before insert on public.goods_receipt_lines
  for each row execute function public.goods_receipt_lines_prepare();
create trigger product_recalls_prepare before insert on public.product_recalls
  for each row execute function public.product_recalls_prepare();

create trigger goods_receipts_immutable before update or delete on public.goods_receipts
  for each row execute function public.forbid_mutation();
create trigger goods_receipt_lines_immutable before update or delete on public.goods_receipt_lines
  for each row execute function public.forbid_mutation();
create trigger product_recalls_immutable before update or delete on public.product_recalls
  for each row execute function public.forbid_mutation();

create trigger suppliers_updated_at before update on public.suppliers
  for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();
create trigger suppliers_audit after insert or update or delete on public.suppliers
  for each row execute function public.audit_row();
create trigger products_audit after insert or update or delete on public.products
  for each row execute function public.audit_row();

-- ---------------------------------------------------------------------
-- 5. RLS
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  -- Anagrafiche: lettura ai membri, inserimento admin/operatore, modifica solo admin
  foreach t in array array['suppliers', 'products'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (public.is_member(company_id))',
                   t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (public.can_write(company_id))',
                   t || '_insert', t);
    execute format('create policy %I on public.%I for update using (public.is_admin(company_id))
                    with check (public.is_admin(company_id))', t || '_admin_update', t);
  end loop;

  -- Registri append-only: lettura ai membri, inserimento admin/operatore (mai il consulente)
  foreach t in array array['goods_receipts', 'goods_receipt_lines', 'product_recalls'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (public.is_member(company_id))',
                   t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (public.can_write(company_id))',
                   t || '_insert', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 6. VISTE (security_invoker: rispettano la RLS dell'utente)
-- ---------------------------------------------------------------------
create or replace view public.v_receipt_summary with (security_invoker = true) as
select r.id as receipt_id, r.company_id,
       count(l.id)                                                   as line_count,
       count(*) filter (where l.outcome = 'rejected')                as rejected_count,
       count(*) filter (where l.outcome = 'accepted_with_reservation') as reservation_count
from public.goods_receipts r
left join public.goods_receipt_lines l on l.receipt_id = r.id
group by r.id, r.company_id;

-- Valutazione fornitori sugli ultimi 12 mesi
create or replace view public.v_supplier_stats with (security_invoker = true) as
select s.id as supplier_id, s.company_id,
       count(distinct r.id) filter (where r.received_at > now() - interval '12 months') as receipts_12m,
       count(l.id) filter (where r.received_at > now() - interval '12 months')         as lines_12m,
       count(l.id) filter (where r.received_at > now() - interval '12 months'
                             and l.outcome = 'rejected')                               as rejected_12m,
       count(l.id) filter (where r.received_at > now() - interval '12 months'
                             and l.outcome = 'accepted_with_reservation')              as reservation_12m
from public.suppliers s
left join public.goods_receipts r on r.supplier_id = s.id
left join public.goods_receipt_lines l on l.receipt_id = r.id
group by s.id, s.company_id;

-- ---------------------------------------------------------------------
-- 7. FOTO DEI DOCUMENTI (bucket privato, JPEG/PNG, max 5 MB, immutabili)
--    Percorso: <company_id>/receipts/<id>.jpg
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy receipts_select on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts'
         and public.is_member(((storage.foldername(name))[1])::uuid));

create policy receipts_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts'
              and public.can_write(((storage.foldername(name))[1])::uuid));
