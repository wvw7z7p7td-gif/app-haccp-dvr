-- =====================================================================
-- 0002 - Firme (storage privato), controfirma pulizie, controlli di coerenza
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. BUCKET FIRME (privato, solo PNG, max 512 KB)
--    Percorso oggetto: <company_id>/<tipo>/<id>.png
--    Nessuna policy di UPDATE/DELETE: le firme sono immutabili.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('signatures', 'signatures', false, 524288, array['image/png'])
on conflict (id) do nothing;

create policy signatures_select on storage.objects
  for select to authenticated
  using (bucket_id = 'signatures'
         and public.is_member(((storage.foldername(name))[1])::uuid));

create policy signatures_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'signatures'
              and public.can_write(((storage.foldername(name))[1])::uuid));

-- ---------------------------------------------------------------------
-- 2. REGISTRO PULIZIE: il piano deve appartenere alla stessa azienda
--    (sostituisce la funzione di 0001; il trigger resta lo stesso)
-- ---------------------------------------------------------------------
create or replace function public.cleaning_logs_prepare() returns trigger
language plpgsql as $$
declare v_company uuid;
begin
  select company_id into v_company from cleaning_plans where id = NEW.plan_id;
  if v_company is null or v_company <> NEW.company_id then
    raise exception 'Piano di pulizia non valido per questa azienda';
  end if;
  NEW.received_at := now();
  NEW.recorded_by := coalesce(NEW.recorded_by, auth.uid());
  return NEW;
end $$;

-- ---------------------------------------------------------------------
-- 3. CONTROFIRMA: solo un responsabile (is_supervisor) dell'azienda e
--    mai la stessa persona che ha eseguito la pulizia (doppio controllo).
-- ---------------------------------------------------------------------
create or replace function public.cleaning_approval_check() returns trigger
language plpgsql as $$
declare
  v_ok boolean;
  v_log_company uuid;
  v_log_employee uuid;
begin
  select (e.is_supervisor and e.active) and e.company_id = NEW.company_id
    into v_ok
  from employees e where e.id = NEW.employee_id;
  if coalesce(v_ok, false) = false then
    raise exception 'La controfirma richiede un responsabile dell''azienda';
  end if;

  select company_id, employee_id into v_log_company, v_log_employee
  from cleaning_logs where id = NEW.log_id;
  if v_log_company is distinct from NEW.company_id then
    raise exception 'Registrazione non valida per questa azienda';
  end if;
  if v_log_employee is not null and v_log_employee = NEW.employee_id then
    raise exception 'La controfirma non puo'' essere dello stesso operatore';
  end if;

  NEW.approved_at := now();
  return NEW;
end $$;

create trigger cleaning_log_approvals_check
  before insert on public.cleaning_log_approvals
  for each row execute function public.cleaning_approval_check();

-- Le voci di checklist devono appartenere a una registrazione della stessa azienda
create or replace function public.cleaning_log_items_check() returns trigger
language plpgsql as $$
declare v_company uuid;
begin
  select company_id into v_company from cleaning_logs where id = NEW.log_id;
  if v_company is distinct from NEW.company_id then
    raise exception 'Registrazione non valida per questa azienda';
  end if;
  return NEW;
end $$;

create trigger cleaning_log_items_check
  before insert on public.cleaning_log_items
  for each row execute function public.cleaning_log_items_check();
