-- =====================================================================
-- 0007 - DUVRI e imprese appaltatrici (B2) - D.Lgs. 81/08 art. 26
-- Verifica dell'idoneita' tecnico-professionale, interferenze con misure
-- e costi della sicurezza, emissione congelata e firma di entrambe le parti.
-- =====================================================================

alter table public.contractors
  add column activity text;

alter table public.contractor_documents
  add column file_sha256 text,
  add column notes text;

alter table public.duvri_documents
  add column no_interference         boolean not null default false,
  add column snapshot                jsonb,
  add column snapshot_sha256         text,
  add column issued_at               timestamptz,
  add column issued_by               uuid references auth.users(id),
  add column compliance_override     text;           -- motivo se emesso con documenti mancanti

-- Interferenze: ogni riga = una situazione di interferenza con la sua misura e il costo
create table public.duvri_interferences (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id),
  duvri_id    uuid not null references public.duvri_documents(id),
  description text not null check (btrim(description) <> ''),
  area        text,
  measures    text not null check (btrim(measures) <> ''),
  responsible text,
  cost_eur    numeric(10,2) not null default 0 check (cost_eur >= 0),
  sort_order  smallint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index on public.duvri_interferences (duvri_id);

-- Firme delle parti (append-only)
create type duvri_party as enum ('employer', 'contractor');

create table public.duvri_signatures (
  id             uuid primary key,
  company_id     uuid not null references public.companies(id),
  duvri_id       uuid not null references public.duvri_documents(id),
  party          duvri_party not null,
  signer_name    text not null check (btrim(signer_name) <> ''),
  signature_path text not null,
  signature_sha256 text not null,
  signed_at      timestamptz not null default now(),
  recorded_by    uuid references auth.users(id),
  unique (duvri_id, party)
);

-- ---------------------------------------------------------------------
-- Idoneita' tecnico-professionale (art. 26 c.1 lett. a)
-- ---------------------------------------------------------------------
create or replace view public.v_contractor_compliance with (security_invoker = true) as
select c.id as contractor_id, c.company_id, c.name as contractor_name, req.doc_type,
       exists (
         select 1 from public.contractor_documents d
         where d.contractor_id = c.id and d.doc_type = req.doc_type
           and d.deleted_at is null and d.file_path is not null
           and (d.expires_on is null or d.expires_on >= current_date)
       ) as valid
from public.contractors c
cross join (values ('chamber_of_commerce'::contractor_doc_type), ('durc'::contractor_doc_type),
                   ('insurance'::contractor_doc_type), ('technical_fitness'::contractor_doc_type)) as req(doc_type)
where c.deleted_at is null and c.active;

create or replace function public.contractor_missing_docs(p_contractor uuid) returns text[]
language sql stable security invoker as $$
  select coalesce(array_agg(doc_type::text order by doc_type), '{}')
  from public.v_contractor_compliance
  where contractor_id = p_contractor and not valid
$$;

-- ---------------------------------------------------------------------
-- Trigger
-- ---------------------------------------------------------------------
create or replace function public.duvri_documents_guard() returns trigger
language plpgsql as $$
declare v_co uuid; v_internal boolean := coalesce(current_setting('app.duvri_internal', true), '') = 'on';
begin
  select company_id into v_co from contractors where id = NEW.contractor_id;
  if v_co is distinct from NEW.company_id then
    raise exception 'Appaltatore non valido per questa azienda';
  end if;
  if NEW.site_id is not null and
     (select company_id from sites where id = NEW.site_id) is distinct from NEW.company_id then
    raise exception 'Sede non valida per questa azienda';
  end if;
  if NEW.ends_on is not null and NEW.starts_on is not null and NEW.ends_on < NEW.starts_on then
    raise exception 'La data di fine precede quella di inizio';
  end if;

  if TG_OP = 'INSERT' then
    if NEW.snapshot is not null or NEW.status <> 'draft' then
      raise exception 'Un DUVRI nasce come bozza' using errcode = '42501';
    end if;
    return NEW;
  end if;

  if OLD.snapshot is null then
    if (NEW.snapshot is not null or NEW.status <> 'draft') and not v_internal then
      raise exception 'Il DUVRI si emette con issue_duvri()' using errcode = '42501';
    end if;
  else
    if NEW.snapshot is distinct from OLD.snapshot or NEW.snapshot_sha256 is distinct from OLD.snapshot_sha256
       or NEW.company_id is distinct from OLD.company_id or NEW.contractor_id is distinct from OLD.contractor_id
       or NEW.activity_description is distinct from OLD.activity_description
       or NEW.areas_involved is distinct from OLD.areas_involved
       or NEW.starts_on is distinct from OLD.starts_on or NEW.ends_on is distinct from OLD.ends_on
       or NEW.safety_costs_eur is distinct from OLD.safety_costs_eur
       or NEW.no_interference is distinct from OLD.no_interference
       or NEW.issued_at is distinct from OLD.issued_at or NEW.issued_by is distinct from OLD.issued_by then
      raise exception 'Un DUVRI emesso e'' inalterabile' using errcode = '42501';
    end if;
    if NEW.status = 'signed' and OLD.status = 'draft' and not v_internal then
      raise exception 'Il DUVRI risulta firmato solo con la firma di entrambe le parti' using errcode = '42501';
    end if;
    if OLD.status = 'closed' and NEW.status <> 'closed' then
      raise exception 'Un DUVRI chiuso non si riapre' using errcode = '42501';
    end if;
  end if;
  return NEW;
end $$;

create or replace function public.duvri_interferences_guard() returns trigger
language plpgsql as $$
declare v_row public.duvri_documents%rowtype; v_id uuid;
begin
  v_id := case when TG_OP = 'DELETE' then OLD.duvri_id else NEW.duvri_id end;
  select * into v_row from duvri_documents where id = v_id;
  if v_row.snapshot is not null then
    raise exception 'Il DUVRI e'' gia'' emesso: le interferenze non si modificano' using errcode = '42501';
  end if;
  if TG_OP <> 'DELETE' and v_row.company_id is distinct from NEW.company_id then
    raise exception 'DUVRI non valido per questa azienda';
  end if;
  return case when TG_OP = 'DELETE' then OLD else NEW end;
end $$;

create or replace function public.duvri_signatures_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare d public.duvri_documents%rowtype; v_parties int;
begin
  select * into d from duvri_documents where id = NEW.duvri_id;
  if d.id is null or d.company_id is distinct from NEW.company_id then
    raise exception 'DUVRI non valido per questa azienda';
  end if;
  if d.snapshot is null then
    raise exception 'Il DUVRI va emesso prima di essere firmato';
  end if;
  if d.status = 'closed' then
    raise exception 'DUVRI chiuso';
  end if;
  NEW.signed_at := now();
  NEW.recorded_by := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

create or replace function public.duvri_signatures_after() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_parties int;
begin
  select count(distinct party) into v_parties from duvri_signatures where duvri_id = NEW.duvri_id;
  if v_parties = 2 then
    perform set_config('app.duvri_internal', 'on', true);
    update duvri_documents set status = 'signed', signed_at = now()
     where id = NEW.duvri_id and status = 'draft';
    perform set_config('app.duvri_internal', 'off', true);
  end if;
  return NEW;
end $$;

create trigger duvri_documents_guard before insert or update on public.duvri_documents
  for each row execute function public.duvri_documents_guard();
create trigger duvri_interferences_guard before insert or update or delete on public.duvri_interferences
  for each row execute function public.duvri_interferences_guard();
create trigger duvri_signatures_1_guard before insert on public.duvri_signatures
  for each row execute function public.duvri_signatures_guard();
create trigger duvri_signatures_2_after after insert on public.duvri_signatures
  for each row execute function public.duvri_signatures_after();
create trigger duvri_signatures_immutable before update or delete on public.duvri_signatures
  for each row execute function public.forbid_mutation();
create trigger duvri_interferences_updated_at before update on public.duvri_interferences
  for each row execute function public.set_updated_at();
create trigger duvri_interferences_audit after insert or update or delete on public.duvri_interferences
  for each row execute function public.audit_row();

alter table public.duvri_interferences enable row level security;
create policy duvri_interferences_select on public.duvri_interferences
  for select using (public.is_member(company_id));
create policy duvri_interferences_admin_write on public.duvri_interferences
  for all using (public.is_admin(company_id)) with check (public.is_admin(company_id));

alter table public.duvri_signatures enable row level security;
create policy duvri_signatures_select on public.duvri_signatures
  for select using (public.is_member(company_id));
create policy duvri_signatures_admin_insert on public.duvri_signatures
  for insert with check (public.is_admin(company_id));

-- ---------------------------------------------------------------------
-- Emissione: congela contenuto, interferenze, costi e stato documentale
-- ---------------------------------------------------------------------
create or replace function public.issue_duvri(p_duvri uuid, p_override_reason text default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  d duvri_documents%rowtype;
  v_missing text[];
  v_n int; v_total numeric(10,2); v_snap jsonb;
begin
  select * into d from duvri_documents where id = p_duvri and deleted_at is null;
  if not found then raise exception 'DUVRI non trovato'; end if;
  if not public.is_admin(d.company_id) then
    raise exception 'Solo il titolare puo'' emettere il DUVRI' using errcode = '42501';
  end if;
  if d.snapshot is not null then raise exception 'DUVRI gia'' emesso'; end if;

  select count(*), coalesce(sum(cost_eur), 0) into v_n, v_total from duvri_interferences where duvri_id = d.id;
  if v_n = 0 and not d.no_interference then
    raise exception 'Indica le interferenze oppure dichiara che non ce ne sono';
  end if;
  if v_n > 0 and d.no_interference then
    raise exception 'Hai dichiarato assenza di interferenze ma ne hai elencate';
  end if;

  select coalesce(array_agg(doc_type::text order by doc_type), '{}') into v_missing
    from v_contractor_compliance where contractor_id = d.contractor_id and not valid;
  if cardinality(v_missing) > 0 and nullif(btrim(coalesce(p_override_reason, '')), '') is null then
    raise exception 'Documenti dell''appaltatore mancanti o scaduti: %', array_to_string(v_missing, ', ');
  end if;

  v_snap := jsonb_build_object(
    'issued_at', now(),
    'company', (select name from companies where id = d.company_id),
    'contractor', (select jsonb_build_object('name', name, 'vat', vat_number, 'contact', contact_name, 'activity', activity)
                     from contractors where id = d.contractor_id),
    'activity', d.activity_description,
    'areas', d.areas_involved,
    'starts_on', d.starts_on, 'ends_on', d.ends_on,
    'no_interference', d.no_interference,
    'interferences', coalesce((
      select jsonb_agg(jsonb_build_object('description', i.description, 'area', i.area,
        'measures', i.measures, 'responsible', i.responsible, 'cost_eur', i.cost_eur)
        order by i.sort_order, i.created_at)
      from duvri_interferences i where i.duvri_id = d.id), '[]'::jsonb),
    'safety_costs_eur', v_total,
    'missing_documents', to_jsonb(v_missing),
    'override_reason', nullif(btrim(coalesce(p_override_reason, '')), ''),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object('type', x.doc_type, 'issued_on', x.issued_on, 'expires_on', x.expires_on))
      from contractor_documents x
      where x.contractor_id = d.contractor_id and x.deleted_at is null and x.file_path is not null), '[]'::jsonb)
  );

  perform set_config('app.duvri_internal', 'on', true);
  update duvri_documents
     set snapshot = v_snap,
         snapshot_sha256 = encode(digest(v_snap::text, 'sha256'), 'hex'),
         issued_at = now(), issued_by = auth.uid(),
         safety_costs_eur = v_total,
         compliance_override = nullif(btrim(coalesce(p_override_reason, '')), '')
   where id = d.id;
  perform set_config('app.duvri_internal', 'off', true);
  return d.id;
end $$;

grant execute on function public.issue_duvri(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- Storage: documenti degli appaltatori  <company_id>/contractors/<id>.<ext>
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contractor-docs', 'contractor-docs', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy contractor_docs_select on storage.objects
  for select to authenticated
  using (bucket_id = 'contractor-docs'
         and public.is_member(((storage.foldername(name))[1])::uuid));
create policy contractor_docs_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'contractor-docs'
              and public.is_admin(((storage.foldername(name))[1])::uuid));
