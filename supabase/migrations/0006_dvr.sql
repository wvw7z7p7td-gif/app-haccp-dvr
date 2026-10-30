-- =====================================================================
-- 0006 - DVR digitale (B1) - D.Lgs. 81/08 artt. 17, 28, 29
-- Registro dei rischi (matrice P x D), programma di miglioramento,
-- figure della sicurezza e emissione di versioni immutabili del DVR.
-- Lo strumento supporta la valutazione: la responsabilita' resta del
-- Datore di Lavoro con RSPP / Medico Competente.
-- =====================================================================

create type action_status as enum ('open', 'in_progress', 'done');
create type safety_role   as enum ('employer', 'rspp', 'rls', 'company_doctor', 'fire_officer', 'first_aid_officer');

-- Catalogo globale dei pericoli tipici Ho.Re.Ca. (modificabile solo da migrazione)
create table public.hazard_catalog (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  category   text not null,
  name       text not null,
  example    text,
  sort_order smallint not null
);

insert into public.hazard_catalog (code, category, name, example, sort_order) values
  ('CUT',        'Meccanico',    'Tagli e abrasioni',               'Coltelli, affettatrici, mandolino', 1),
  ('BURN',       'Termico',      'Ustioni e scottature',            'Forni, friggitrici, piani cottura, liquidi caldi', 2),
  ('SLIP',       'Infortunistico','Scivolamento, inciampo, caduta',  'Pavimenti bagnati o unti, scale, passaggi ostruiti', 3),
  ('MANUAL',     'Ergonomico',   'Movimentazione manuale dei carichi','Casse, fusti, sacchi, merci in magazzino', 4),
  ('REPETITIVE', 'Ergonomico',   'Movimenti ripetitivi e postura',  'Servizio al banco, lavaggio stoviglie, lavoro in piedi', 5),
  ('ELECTRIC',   'Elettrico',    'Rischio elettrico',               'Apparecchiature in ambiente umido, prolunghe', 6),
  ('FIRE',       'Incendio',     'Incendio ed esplosione',          'Gas, oli di frittura, cappe non pulite', 7),
  ('CHEMICAL',   'Chimico',      'Agenti chimici',                  'Detergenti, sanificanti, soda caustica', 8),
  ('BIOLOGICAL', 'Biologico',    'Agenti biologici',                'Contatto con alimenti contaminati, rifiuti', 9),
  ('NOISE',      'Fisico',       'Rumore',                          'Cucina, lavastoviglie, musica nei locali', 10),
  ('MICROCLIMA', 'Fisico',       'Microclima e stress termico',     'Cucina calda, celle frigorifere', 11),
  ('LIGHTING',   'Fisico',       'Illuminazione',                   'Locali di servizio poco illuminati', 12),
  ('VDT',        'Ergonomico',   'Videoterminali',                  'Cassa, gestionale, ufficio', 13),
  ('MACHINES',   'Meccanico',    'Macchine e attrezzature',         'Impastatrici, tritacarne, robot da cucina', 14),
  ('PRESSURE',   'Meccanico',    'Attrezzature in pressione',       'Caffe'' espresso, pentole a pressione, bombole', 15),
  ('STRESS',     'Organizzativo','Stress lavoro-correlato',         'Picchi di servizio, turni, relazione con il pubblico', 16),
  ('AGGRESSION', 'Organizzativo','Aggressioni e rapine',            'Lavoro serale/notturno, gestione contanti', 17),
  ('NIGHT',      'Organizzativo','Lavoro notturno e turni',         'Locali serali, discoteche, pub', 18),
  ('PREGNANCY',  'Organizzativo','Lavoratrici gestanti',            'Mansioni vietate in gravidanza', 19),
  ('OTHER',      'Altro',        'Altro (specificare)',             null, 99);

-- Registro dei rischi (matrice 1-4 x 1-4)
create table public.dvr_risks (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id),
  site_id           uuid references public.sites(id),
  area_id           uuid references public.areas(id),
  job_role_id       uuid references public.job_roles(id),
  hazard_id         uuid not null references public.hazard_catalog(id),
  title             text not null check (btrim(title) <> ''),
  description       text,
  probability       smallint not null check (probability between 1 and 4),
  severity          smallint not null check (severity between 1 and 4),
  risk_score        smallint generated always as (probability * severity) stored,
  measures          text,                                       -- misure di prevenzione e protezione in atto
  residual_probability smallint check (residual_probability between 1 and 4),
  residual_severity    smallint check (residual_severity between 1 and 4),
  residual_score    smallint generated always as (residual_probability * residual_severity) stored,
  assessed_on       date not null default current_date,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  check ((residual_probability is null) = (residual_severity is null))
);
create index on public.dvr_risks (company_id);

-- Programma di miglioramento
create table public.dvr_actions (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies(id),
  risk_id         uuid not null references public.dvr_risks(id),
  description     text not null check (btrim(description) <> ''),
  responsible     text,
  due_on          date,
  status          action_status not null default 'open',
  done_on         date,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  check (status <> 'done' or done_on is not null)
);
create index on public.dvr_actions (company_id, status);
create index on public.dvr_actions (risk_id);

-- Figure della sicurezza (interne tramite employee_id, esterne tramite nome)
create table public.safety_officers (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.companies(id),
  role          safety_role not null,
  employee_id   uuid references public.employees(id),
  external_name text,
  appointed_on  date,
  ends_on       date,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  check (employee_id is not null or nullif(btrim(coalesce(external_name, '')), '') is not null)
);
create index on public.safety_officers (company_id);

-- Versioni emesse del DVR: contenuto congelato + impronta
alter table public.dvr_documents
  add column snapshot        jsonb,
  add column snapshot_sha256 text,
  add column issued_by       uuid references auth.users(id);

-- ---------------------------------------------------------------------
-- Funzioni e trigger
-- ---------------------------------------------------------------------
create or replace function public.risk_level(p_score int) returns text
language sql immutable as $$
  select case
    when p_score is null then null
    when p_score <= 2 then 'low'
    when p_score <= 4 then 'medium'
    when p_score <= 8 then 'high'
    else 'very_high' end
$$;

create or replace function public.dvr_risks_check() returns trigger
language plpgsql as $$
declare v_co uuid; v_site uuid;
begin
  if NEW.site_id is not null then
    select company_id into v_co from sites where id = NEW.site_id;
    if v_co is distinct from NEW.company_id then raise exception 'Sede non valida per questa azienda'; end if;
  end if;
  if NEW.area_id is not null then
    select company_id, site_id into v_co, v_site from areas where id = NEW.area_id;
    if v_co is distinct from NEW.company_id then raise exception 'Area non valida per questa azienda'; end if;
    if NEW.site_id is not null and v_site is distinct from NEW.site_id then
      raise exception 'L''area appartiene a un''altra sede';
    end if;
  end if;
  if NEW.job_role_id is not null then
    select company_id into v_co from job_roles where id = NEW.job_role_id;
    if v_co is distinct from NEW.company_id then raise exception 'Mansione non valida per questa azienda'; end if;
  end if;
  if NEW.residual_score is not null and NEW.residual_probability * NEW.residual_severity > NEW.probability * NEW.severity then
    raise exception 'Il rischio residuo non puo'' superare il rischio iniziale';
  end if;
  return NEW;
end $$;

create or replace function public.dvr_actions_check() returns trigger
language plpgsql as $$
declare v_co uuid;
begin
  select company_id into v_co from dvr_risks where id = NEW.risk_id;
  if v_co is distinct from NEW.company_id then raise exception 'Rischio non valido per questa azienda'; end if;
  return NEW;
end $$;

create or replace function public.safety_officers_check() returns trigger
language plpgsql as $$
declare v_co uuid;
begin
  if NEW.employee_id is not null then
    select company_id into v_co from employees where id = NEW.employee_id;
    if v_co is distinct from NEW.company_id then raise exception 'Dipendente non valido per questa azienda'; end if;
  end if;
  return NEW;
end $$;

-- Una versione emessa non si altera: restano modificabili solo stato e prossima revisione.
create or replace function public.dvr_documents_protect() returns trigger
language plpgsql as $$
begin
  if OLD.snapshot is not null then
    if NEW.snapshot is distinct from OLD.snapshot
       or NEW.snapshot_sha256 is distinct from OLD.snapshot_sha256
       or NEW.version is distinct from OLD.version
       or NEW.issued_on is distinct from OLD.issued_on
       or NEW.issued_by is distinct from OLD.issued_by
       or NEW.company_id is distinct from OLD.company_id then
      raise exception 'Una versione emessa del DVR e'' inalterabile: emetti una nuova versione.'
        using errcode = '42501';
    end if;
    if OLD.status in ('superseded', 'expired') and NEW.status = 'active' then
      raise exception 'Una versione sostituita non puo'' tornare attiva' using errcode = '42501';
    end if;
  elsif NEW.snapshot is not null and current_setting('app.issuing_dvr', true) is distinct from 'on' then
    raise exception 'Le versioni si emettono con issue_dvr()' using errcode = '42501';
  end if;
  return NEW;
end $$;

create trigger dvr_risks_check before insert or update on public.dvr_risks
  for each row execute function public.dvr_risks_check();
create trigger dvr_actions_check before insert or update on public.dvr_actions
  for each row execute function public.dvr_actions_check();
create trigger safety_officers_check before insert or update on public.safety_officers
  for each row execute function public.safety_officers_check();
create trigger dvr_documents_protect before update on public.dvr_documents
  for each row execute function public.dvr_documents_protect();

do $$
declare t text;
begin
  foreach t in array array['dvr_risks', 'dvr_actions', 'safety_officers'] loop
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
                   t || '_updated_at', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_row()',
                   t || '_audit', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (public.is_member(company_id))',
                   t || '_select', t);
    execute format('create policy %I on public.%I for all using (public.is_admin(company_id))
                    with check (public.is_admin(company_id))', t || '_admin_write', t);
  end loop;
end $$;

alter table public.hazard_catalog enable row level security;
create policy hazard_catalog_select on public.hazard_catalog for select to authenticated using (true);

-- Emissione di una nuova versione del DVR: congela rischi, azioni e figure.
create or replace function public.issue_dvr(p_dvr uuid, p_next_review date, p_reason text default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  d dvr_documents%rowtype;
  v_snap jsonb;
  v_risks int;
begin
  select * into d from dvr_documents where id = p_dvr and deleted_at is null;
  if not found then raise exception 'DVR non trovato'; end if;
  if not public.is_admin(d.company_id) then
    raise exception 'Solo il titolare puo'' emettere il DVR' using errcode = '42501';
  end if;
  if d.status <> 'draft' then raise exception 'Solo una bozza puo'' essere emessa'; end if;
  if p_next_review is null or p_next_review <= current_date then
    raise exception 'Indica una data di prossima revisione futura';
  end if;

  select count(*) into v_risks from dvr_risks r
   where r.company_id = d.company_id and r.active and r.deleted_at is null
     and (d.site_id is null or r.site_id is null or r.site_id = d.site_id);
  if v_risks = 0 then raise exception 'Nessun rischio valutato: il DVR non puo'' essere emesso vuoto'; end if;

  v_snap := jsonb_build_object(
    'issued_at', now(),
    'company', (select name from companies where id = d.company_id),
    'version', d.version,
    'risks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'title', r.title, 'description', r.description,
        'hazard', h.name, 'category', h.category,
        'area', a.name, 'job_role', jr.name,
        'probability', r.probability, 'severity', r.severity,
        'score', r.risk_score, 'level', public.risk_level(r.risk_score),
        'measures', r.measures,
        'residual_probability', r.residual_probability, 'residual_severity', r.residual_severity,
        'residual_score', r.residual_score, 'residual_level', public.risk_level(r.residual_score),
        'assessed_on', r.assessed_on) order by r.risk_score desc, r.title)
      from dvr_risks r
      join hazard_catalog h on h.id = r.hazard_id
      left join areas a on a.id = r.area_id
      left join job_roles jr on jr.id = r.job_role_id
      where r.company_id = d.company_id and r.active and r.deleted_at is null
        and (d.site_id is null or r.site_id is null or r.site_id = d.site_id)), '[]'::jsonb),
    'actions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'risk_id', x.risk_id, 'description', x.description, 'responsible', x.responsible,
        'due_on', x.due_on, 'status', x.status) order by x.due_on nulls last)
      from dvr_actions x join dvr_risks r on r.id = x.risk_id
      where x.company_id = d.company_id and x.deleted_at is null and x.status <> 'done'
        and r.active and r.deleted_at is null
        and (d.site_id is null or r.site_id is null or r.site_id = d.site_id)), '[]'::jsonb),
    'officers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'role', o.role, 'name', coalesce(o.external_name, e.first_name || ' ' || e.last_name),
        'appointed_on', o.appointed_on, 'ends_on', o.ends_on))
      from safety_officers o left join employees e on e.id = o.employee_id
      where o.company_id = d.company_id and o.deleted_at is null
        and (o.ends_on is null or o.ends_on >= current_date)), '[]'::jsonb)
  );

  -- le versioni precedenti, della stessa sede, diventano "sostituite"
  update dvr_documents set status = 'superseded'
   where company_id = d.company_id and site_id is not distinct from d.site_id
     and status = 'active' and id <> d.id;

  perform set_config('app.issuing_dvr', 'on', true);
  update dvr_documents
     set status = 'active', issued_on = current_date, next_review_on = p_next_review,
         review_reason = coalesce(p_reason, review_reason),
         snapshot = v_snap,
         snapshot_sha256 = encode(digest(v_snap::text, 'sha256'), 'hex'),
         issued_by = auth.uid()
   where id = d.id;
  perform set_config('app.issuing_dvr', 'off', true);
  return d.id;
end $$;

grant execute on function public.issue_dvr(uuid, date, text) to authenticated;

-- ---------------------------------------------------------------------
-- Viste
-- ---------------------------------------------------------------------
create or replace view public.v_dvr_risk_summary with (security_invoker = true) as
select r.*, public.risk_level(r.risk_score) as level,
       public.risk_level(r.residual_score) as residual_level,
       (select count(*) from public.dvr_actions a
         where a.risk_id = r.id and a.deleted_at is null and a.status <> 'done') as open_actions
from public.dvr_risks r
where r.deleted_at is null;

create or replace view public.v_dvr_actions_overdue with (security_invoker = true) as
select a.* from public.dvr_actions a
where a.deleted_at is null and a.status <> 'done' and a.due_on is not null and a.due_on < current_date;
