-- =====================================================================
-- 0005 - Controllo infestanti / pest control (A5)
-- Postazioni di monitoraggio, ispezioni (interne o del servizio esterno),
-- esiti per postazione e azioni correttive. Registri append-only.
-- =====================================================================

create type pest_station_kind as enum
  ('rodent_bait', 'rodent_trap', 'insect_light', 'glue_trap', 'pheromone', 'other');
create type pest_inspection_kind as enum ('internal_check', 'external_service');
create type pest_finding_status as enum ('ok', 'activity', 'damaged', 'missing');

create table public.pest_stations (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies(id),
  site_id         uuid not null references public.sites(id),
  code            text not null check (btrim(code) <> ''),   -- es. "E1", "T3"
  kind            pest_station_kind not null,
  location        text,                                       -- dove si trova
  check_every_days smallint not null default 7 check (check_every_days between 1 and 365),
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create unique index on public.pest_stations (site_id, lower(code)) where deleted_at is null;
create index on public.pest_stations (company_id);

create table public.pest_inspections (
  id                 uuid primary key,
  seq                bigint generated always as identity,
  company_id         uuid not null references public.companies(id),
  site_id            uuid not null references public.sites(id),
  kind               pest_inspection_kind not null default 'internal_check',
  inspected_at       timestamptz not null,
  received_server_at timestamptz not null default now(),
  employee_id        uuid references public.employees(id),
  recorded_by        uuid references auth.users(id),
  provider_name      text,
  report_photo_path  text,
  report_photo_hash  text,
  notes              text,
  prev_hash          text,
  row_hash           text,
  check (kind <> 'external_service' or nullif(btrim(coalesce(provider_name, '')), '') is not null)
);
create index on public.pest_inspections (company_id, inspected_at desc);

create table public.pest_inspection_items (
  id            uuid primary key,
  company_id    uuid not null references public.companies(id),
  inspection_id uuid not null references public.pest_inspections(id),
  station_id    uuid not null references public.pest_stations(id),
  status        pest_finding_status not null default 'ok',
  catch_count   smallint check (catch_count is null or catch_count >= 0),
  notes         text,
  unique (inspection_id, station_id),
  check (status = 'ok' or nullif(btrim(coalesce(notes, '')), '') is not null)
);
create index on public.pest_inspection_items (station_id);
create index on public.pest_inspection_items (company_id);

create table public.pest_corrective_actions (
  id                 uuid primary key,
  company_id         uuid not null references public.companies(id),
  item_id            uuid not null references public.pest_inspection_items(id),
  action             text not null check (btrim(action) <> ''),
  performed_at       timestamptz not null,
  received_server_at timestamptz not null default now(),
  employee_id        uuid references public.employees(id),
  recorded_by        uuid references auth.users(id)
);
create index on public.pest_corrective_actions (item_id);

-- ---------------------------------------------------------------------
-- Trigger
-- ---------------------------------------------------------------------
create or replace function public.pest_stations_check() returns trigger
language plpgsql as $$
declare v_company uuid;
begin
  select company_id into v_company from sites where id = NEW.site_id;
  if v_company is distinct from NEW.company_id then
    raise exception 'Sede non valida per questa azienda';
  end if;
  return NEW;
end $$;

create or replace function public.pest_inspections_prepare() returns trigger
language plpgsql as $$
declare v_company uuid;
begin
  select company_id into v_company from sites where id = NEW.site_id;
  if v_company is distinct from NEW.company_id then
    raise exception 'Sede non valida per questa azienda';
  end if;
  NEW.received_server_at := now();
  NEW.recorded_by := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

create or replace function public.pest_items_check() returns trigger
language plpgsql as $$
declare v_insp_company uuid; v_insp_site uuid; v_st_company uuid; v_st_site uuid;
begin
  select company_id, site_id into v_insp_company, v_insp_site
    from pest_inspections where id = NEW.inspection_id;
  select company_id, site_id into v_st_company, v_st_site
    from pest_stations where id = NEW.station_id;
  if v_insp_company is distinct from NEW.company_id or v_st_company is distinct from NEW.company_id then
    raise exception 'Ispezione o postazione non valida per questa azienda';
  end if;
  if v_insp_site is distinct from v_st_site then
    raise exception 'La postazione appartiene a un''altra sede';
  end if;
  return NEW;
end $$;

create or replace function public.pest_actions_check() returns trigger
language plpgsql as $$
declare v_company uuid; v_status pest_finding_status;
begin
  select company_id, status into v_company, v_status from pest_inspection_items where id = NEW.item_id;
  if v_company is distinct from NEW.company_id then
    raise exception 'Rilievo non valido per questa azienda';
  end if;
  if v_status = 'ok' then
    raise exception 'Nessuna azione correttiva per una postazione conforme';
  end if;
  NEW.received_server_at := now();
  NEW.recorded_by := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

create trigger pest_stations_check before insert or update on public.pest_stations
  for each row execute function public.pest_stations_check();
create trigger pest_inspections_1_prepare before insert on public.pest_inspections
  for each row execute function public.pest_inspections_prepare();
create trigger pest_inspections_2_chain before insert on public.pest_inspections
  for each row execute function public.chain_hash();
create trigger pest_items_check before insert on public.pest_inspection_items
  for each row execute function public.pest_items_check();
create trigger pest_actions_check before insert on public.pest_corrective_actions
  for each row execute function public.pest_actions_check();

create trigger pest_inspections_immutable before update or delete on public.pest_inspections
  for each row execute function public.forbid_mutation();
create trigger pest_items_immutable before update or delete on public.pest_inspection_items
  for each row execute function public.forbid_mutation();
create trigger pest_actions_immutable before update or delete on public.pest_corrective_actions
  for each row execute function public.forbid_mutation();

create trigger pest_stations_updated_at before update on public.pest_stations
  for each row execute function public.set_updated_at();
create trigger pest_stations_audit after insert or update or delete on public.pest_stations
  for each row execute function public.audit_row();

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.pest_stations enable row level security;
create policy pest_stations_select on public.pest_stations for select using (public.is_member(company_id));
create policy pest_stations_insert on public.pest_stations for insert with check (public.can_write(company_id));
create policy pest_stations_update on public.pest_stations for update
  using (public.is_admin(company_id)) with check (public.is_admin(company_id));

do $$
declare t text;
begin
  foreach t in array array['pest_inspections', 'pest_inspection_items', 'pest_corrective_actions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (public.is_member(company_id))',
                   t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (public.can_write(company_id))',
                   t || '_insert', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Viste
-- ---------------------------------------------------------------------
-- Rilievi non conformi senza azione correttiva
create or replace view public.v_open_pest_findings with (security_invoker = true) as
select i.id as item_id, i.company_id, i.station_id, i.inspection_id, i.status, i.catch_count, i.notes,
       n.inspected_at
from public.pest_inspection_items i
join public.pest_inspections n on n.id = i.inspection_id
where i.status <> 'ok'
  and not exists (select 1 from public.pest_corrective_actions a where a.item_id = i.id);

-- Ultimo controllo di ogni postazione e se e' in ritardo
create or replace view public.v_pest_station_status with (security_invoker = true) as
select s.id as station_id, s.company_id, s.site_id, s.code, s.kind, s.location,
       s.check_every_days, s.active,
       l.inspected_at as last_inspected_at,
       l.status       as last_status,
       (s.active and (l.inspected_at is null
          or l.inspected_at < now() - make_interval(days => s.check_every_days))) as overdue
from public.pest_stations s
left join lateral (
  select n.inspected_at, i.status
  from public.pest_inspection_items i
  join public.pest_inspections n on n.id = i.inspection_id
  where i.station_id = s.id
  order by n.inspected_at desc
  limit 1
) l on true
where s.deleted_at is null;

-- ---------------------------------------------------------------------
-- Rapporti del servizio esterno (bucket privato)  <company_id>/pest/<id>.jpg
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pest-reports', 'pest-reports', false, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy pest_reports_select on storage.objects
  for select to authenticated
  using (bucket_id = 'pest-reports'
         and public.is_member(((storage.foldername(name))[1])::uuid));
create policy pest_reports_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'pest-reports'
              and public.can_write(((storage.foldername(name))[1])::uuid));
