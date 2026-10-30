-- =====================================================================
-- 0008 - Persone, formazione e DPI (B3, B4) - coerenza, scadenzario, documenti
-- =====================================================================

-- Coerenza tra aziende (un dato non puo' riferirsi a record di un'altra azienda)
create or replace function public.employees_check() returns trigger
language plpgsql as $$
begin
  if NEW.job_role_id is not null and
     (select company_id from job_roles where id = NEW.job_role_id) is distinct from NEW.company_id then
    raise exception 'Mansione non valida per questa azienda';
  end if;
  if NEW.site_id is not null and
     (select company_id from sites where id = NEW.site_id) is distinct from NEW.company_id then
    raise exception 'Sede non valida per questa azienda';
  end if;
  if NEW.termination_date is not null and NEW.hire_date is not null and NEW.termination_date < NEW.hire_date then
    raise exception 'La cessazione precede l''assunzione';
  end if;
  return NEW;
end $$;

create or replace function public.training_records_check() returns trigger
language plpgsql as $$
declare v_type_company uuid;
begin
  if (select company_id from employees where id = NEW.employee_id) is distinct from NEW.company_id then
    raise exception 'Dipendente non valido per questa azienda';
  end if;
  select company_id into v_type_company from training_types where id = NEW.training_type_id;
  if not found or (v_type_company is not null and v_type_company <> NEW.company_id) then
    raise exception 'Tipo di formazione non valido per questa azienda';
  end if;
  if NEW.issued_on > current_date then
    raise exception 'La data dell''attestato e'' nel futuro';
  end if;
  if NEW.expires_on is not null and NEW.expires_on < NEW.issued_on then
    raise exception 'La scadenza precede la data dell''attestato';
  end if;
  return NEW;
end $$;

create or replace function public.ppe_assignments_check() returns trigger
language plpgsql as $$
begin
  if (select company_id from employees where id = NEW.employee_id) is distinct from NEW.company_id then
    raise exception 'Dipendente non valido per questa azienda';
  end if;
  if (select company_id from ppe_types where id = NEW.ppe_type_id) is distinct from NEW.company_id then
    raise exception 'Tipo di DPI non valido per questa azienda';
  end if;
  if NEW.delivered_by is not null and
     (select company_id from employees where id = NEW.delivered_by) is distinct from NEW.company_id then
    raise exception 'Consegnatario non valido per questa azienda';
  end if;
  if NEW.returned_on is not null and NEW.returned_on < NEW.delivered_on then
    raise exception 'La riconsegna precede la consegna';
  end if;
  -- La consegna deve essere firmata dal lavoratore (art. 18 c.1 lett. d, art. 77)
  if TG_OP = 'INSERT' and (NEW.signature_path is null or NEW.signature_hash is null) then
    raise exception 'La consegna del DPI richiede la firma del lavoratore';
  end if;
  if TG_OP = 'UPDATE' and (NEW.signature_path is distinct from OLD.signature_path
                           or NEW.signature_hash is distinct from OLD.signature_hash
                           or NEW.employee_id is distinct from OLD.employee_id
                           or NEW.ppe_type_id is distinct from OLD.ppe_type_id
                           or NEW.delivered_on is distinct from OLD.delivered_on) then
    raise exception 'Una consegna firmata non si altera: registra una nuova consegna'
      using errcode = '42501';
  end if;
  return NEW;
end $$;

create or replace function public.job_role_links_check() returns trigger
language plpgsql as $$
declare v_other uuid;
begin
  if (select company_id from job_roles where id = NEW.job_role_id) is distinct from NEW.company_id then
    raise exception 'Mansione non valida per questa azienda';
  end if;
  if TG_TABLE_NAME = 'job_role_ppe' then
    select company_id into v_other from ppe_types where id = NEW.ppe_type_id;
    if v_other is distinct from NEW.company_id then raise exception 'DPI non valido per questa azienda'; end if;
  else
    select company_id into v_other from training_types where id = NEW.training_type_id;
    if not found or (v_other is not null and v_other <> NEW.company_id) then
      raise exception 'Formazione non valida per questa azienda';
    end if;
  end if;
  return NEW;
end $$;

create trigger employees_check before insert or update on public.employees
  for each row execute function public.employees_check();
create trigger training_records_check before insert or update on public.training_records
  for each row execute function public.training_records_check();
create trigger ppe_assignments_check before insert or update on public.ppe_assignments
  for each row execute function public.ppe_assignments_check();
create trigger job_role_ppe_check before insert or update on public.job_role_ppe
  for each row execute function public.job_role_links_check();
create trigger job_role_training_check before insert or update on public.job_role_training_requirements
  for each row execute function public.job_role_links_check();

-- DPI previsti per la mansione ma non consegnati (o scaduti)
create or replace view public.v_ppe_missing with (security_invoker = true) as
select e.company_id, e.id as employee_id, r.ppe_type_id
from public.employees e
join public.job_role_ppe r on r.job_role_id = e.job_role_id
where e.active and e.deleted_at is null
  and not exists (
    select 1 from public.ppe_assignments a
    where a.employee_id = e.id and a.ppe_type_id = r.ppe_type_id
      and a.returned_on is null and (a.expires_on is null or a.expires_on >= current_date));

-- Scadenzario unico (aggiunge incarichi della sicurezza e azioni del DVR)
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
  union all
  select o.company_id, 'safety_officer'::text, o.employee_id, o.id,
         (o.role::text || coalesce(' - ' || o.external_name, ''))::text, o.ends_on
  from public.safety_officers o
  where o.ends_on is not null and o.deleted_at is null
  union all
  select a.company_id, 'dvr_action'::text, null::uuid, a.id, a.description, a.due_on
  from public.dvr_actions a
  where a.due_on is not null and a.status <> 'done' and a.deleted_at is null
) x;

-- Documenti del personale (attestati, libretti DPI)  <company_id>/<tipo>/<id>.jpg
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('hr-docs', 'hr-docs', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy hr_docs_select on storage.objects
  for select to authenticated
  using (bucket_id = 'hr-docs'
         and public.is_member(((storage.foldername(name))[1])::uuid));
create policy hr_docs_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'hr-docs'
              and public.can_write(((storage.foldername(name))[1])::uuid));
