-- =====================================================================
-- 0009 - Infortuni e near-miss (B5) - D.Lgs. 81/08 art. 18, 53, 25
-- Registro append-only con hash chain, indagine, azioni correttive,
-- denuncia INAIL e chiusura controllata.
-- =====================================================================

create type incident_kind     as enum ('injury', 'near_miss');
create type injury_severity   as enum ('none', 'first_aid', 'medical', 'lost_time', 'serious');
create type incident_step     as enum ('investigation', 'corrective', 'inail_report', 'closure');

create table public.incidents (
  id                 uuid primary key,
  seq                bigint generated always as identity,
  company_id         uuid not null references public.companies(id),
  site_id            uuid references public.sites(id),
  kind               incident_kind not null,
  occurred_at        timestamptz not null,
  received_server_at timestamptz not null default now(),
  employee_id        uuid references public.employees(id),        -- infortunato
  reported_by        uuid references public.employees(id),        -- chi segnala
  recorded_by        uuid references auth.users(id),
  area               text,
  description        text not null check (btrim(description) <> ''),
  body_part          text,
  severity           injury_severity not null default 'none',
  days_lost          smallint not null default 0 check (days_lost >= 0),
  dvr_risk_id        uuid references public.dvr_risks(id),
  inail_report_required boolean not null default false,            -- calcolato dal trigger
  prev_hash          text,
  row_hash           text,
  check (kind <> 'injury' or employee_id is not null),
  check (kind <> 'near_miss' or (severity = 'none' and days_lost = 0))
);
create index on public.incidents (company_id, occurred_at desc);

create table public.incident_actions (
  id                 uuid primary key,
  company_id         uuid not null references public.companies(id),
  incident_id        uuid not null references public.incidents(id),
  step               incident_step not null,
  description        text not null check (btrim(description) <> ''),
  reference          text,                                          -- es. protocollo INAIL
  performed_at       timestamptz not null,
  received_server_at timestamptz not null default now(),
  employee_id        uuid references public.employees(id),
  recorded_by        uuid references auth.users(id)
);
create index on public.incident_actions (incident_id);

create or replace function public.incidents_prepare() returns trigger
language plpgsql as $$
begin
  if NEW.site_id is not null and
     (select company_id from sites where id = NEW.site_id) is distinct from NEW.company_id then
    raise exception 'Sede non valida per questa azienda';
  end if;
  if NEW.employee_id is not null and
     (select company_id from employees where id = NEW.employee_id) is distinct from NEW.company_id then
    raise exception 'Persona non valida per questa azienda';
  end if;
  if NEW.reported_by is not null and
     (select company_id from employees where id = NEW.reported_by) is distinct from NEW.company_id then
    raise exception 'Segnalante non valido per questa azienda';
  end if;
  if NEW.dvr_risk_id is not null and
     (select company_id from dvr_risks where id = NEW.dvr_risk_id) is distinct from NEW.company_id then
    raise exception 'Rischio non valido per questa azienda';
  end if;
  if NEW.occurred_at > now() + interval '10 minutes' then
    raise exception 'La data dell''evento e'' nel futuro';
  end if;
  -- Denuncia all'INAIL: inabilita' oltre i 3 giorni oppure infortunio grave
  NEW.inail_report_required := NEW.kind = 'injury' and (NEW.days_lost > 3 or NEW.severity = 'serious');
  NEW.received_server_at := now();
  NEW.recorded_by := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

create or replace function public.incident_actions_prepare() returns trigger
language plpgsql as $$
declare i incidents%rowtype;
begin
  select * into i from incidents where id = NEW.incident_id;
  if i.id is null or i.company_id is distinct from NEW.company_id then
    raise exception 'Evento non valido per questa azienda';
  end if;
  if NEW.employee_id is not null and
     (select company_id from employees where id = NEW.employee_id) is distinct from NEW.company_id then
    raise exception 'Persona non valida per questa azienda';
  end if;
  if exists (select 1 from incident_actions where incident_id = NEW.incident_id and step = 'closure') then
    raise exception 'Evento gia'' chiuso';
  end if;
  if NEW.step = 'inail_report' and not i.inail_report_required then
    raise exception 'Per questo evento non e'' prevista la denuncia INAIL';
  end if;
  if NEW.step = 'closure' then
    if not exists (select 1 from incident_actions
                    where incident_id = NEW.incident_id and step in ('investigation', 'corrective')) then
      raise exception 'Prima di chiudere registra un''indagine o un''azione correttiva';
    end if;
    if i.inail_report_required and not exists (
         select 1 from incident_actions where incident_id = NEW.incident_id and step = 'inail_report') then
      raise exception 'Prima di chiudere registra la denuncia INAIL';
    end if;
  end if;
  NEW.received_server_at := now();
  NEW.recorded_by := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

create trigger incidents_1_prepare before insert on public.incidents
  for each row execute function public.incidents_prepare();
create trigger incidents_2_chain before insert on public.incidents
  for each row execute function public.chain_hash();
create trigger incident_actions_prepare before insert on public.incident_actions
  for each row execute function public.incident_actions_prepare();
create trigger incidents_immutable before update or delete on public.incidents
  for each row execute function public.forbid_mutation();
create trigger incident_actions_immutable before update or delete on public.incident_actions
  for each row execute function public.forbid_mutation();

alter table public.incidents enable row level security;
alter table public.incident_actions enable row level security;
create policy incidents_select on public.incidents for select using (public.is_member(company_id));
create policy incidents_insert on public.incidents for insert with check (public.can_write(company_id));
create policy incident_actions_select on public.incident_actions for select using (public.is_member(company_id));
create policy incident_actions_insert on public.incident_actions for insert with check (public.can_write(company_id));

-- Stato di ogni evento
create or replace view public.v_incident_status with (security_invoker = true) as
select i.id as incident_id, i.company_id, i.kind, i.occurred_at, i.severity, i.days_lost,
       i.inail_report_required,
       exists (select 1 from public.incident_actions a where a.incident_id = i.id and a.step = 'investigation') as investigated,
       exists (select 1 from public.incident_actions a where a.incident_id = i.id and a.step = 'corrective') as has_corrective,
       exists (select 1 from public.incident_actions a where a.incident_id = i.id and a.step = 'inail_report') as inail_reported,
       exists (select 1 from public.incident_actions a where a.incident_id = i.id and a.step = 'closure') as closed
from public.incidents i;
