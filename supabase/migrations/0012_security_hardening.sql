-- =====================================================================
-- 0012 - Sicurezza: blocco PIN dopo troppi errori, inviti ai colleghi,
--        creazione azienda riservata agli indirizzi autorizzati.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PIN: dopo 5 errori consecutivi blocco di 5 minuti, raddoppiato a ogni
--    ulteriore errore (max 80 minuti). Un PIN corretto azzera il contatore.
-- ---------------------------------------------------------------------
create table public.employee_pin_attempts (
  employee_id  uuid primary key references public.employees(id) on delete cascade,
  failed       int not null default 0,
  locked_until timestamptz
);
alter table public.employee_pin_attempts enable row level security;  -- nessuna policy: solo le funzioni

create or replace function public.verify_employee_pin(p_employee uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_company uuid; v_hash text; v_lock timestamptz; v_failed int;
begin
  select company_id into v_company from employees where id = p_employee;
  if v_company is null or not can_write(v_company) then return false; end if;

  select locked_until into v_lock from employee_pin_attempts where employee_id = p_employee;
  if v_lock is not null and v_lock > now() then
    raise exception 'PIN_LOCKED:%', greatest(1, ceil(extract(epoch from (v_lock - now())) / 60))::int;
  end if;

  select pin_hash into v_hash from employee_pins where employee_id = p_employee;
  if v_hash is not null and v_hash = crypt(p_pin, v_hash) then
    delete from employee_pin_attempts where employee_id = p_employee;
    return true;
  end if;

  insert into employee_pin_attempts as a (employee_id, failed) values (p_employee, 1)
  on conflict (employee_id) do update set failed = a.failed + 1
  returning a.failed into v_failed;
  if v_failed >= 5 then
    update employee_pin_attempts
       set locked_until = now() + (interval '5 minutes' * power(2, least(v_failed - 5, 4)))
     where employee_id = p_employee;
  end if;
  return false;
end $$;

-- Reimpostare il PIN (solo admin) sblocca anche l'operatore.
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
  delete from employee_pin_attempts where employee_id = p_employee;
end $$;

-- ---------------------------------------------------------------------
-- 2. INVITI: l'admin invita un collega o un consulente per email.
--    Chi si registra con quell'email (confermata) entra nell'azienda.
-- ---------------------------------------------------------------------
create table public.company_invites (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id),
  email       text not null check (email = lower(btrim(email)) and position('@' in email) > 1),
  role        app_role not null,
  created_by  uuid references auth.users(id) default auth.uid(),
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id)
);
create unique index company_invites_pending on public.company_invites (company_id, email)
  where accepted_at is null;

alter table public.company_invites enable row level security;
create policy company_invites_select on public.company_invites
  for select using (public.is_admin(company_id));
create policy company_invites_insert on public.company_invites
  for insert with check (public.is_admin(company_id));
create policy company_invites_delete on public.company_invites
  for delete using (public.is_admin(company_id) and accepted_at is null);

create or replace function public.accept_invites() returns int
language plpgsql security definer set search_path = public as $$
declare v_email text; v_n int := 0; r record;
begin
  if auth.uid() is null then return 0; end if;
  select lower(email) into v_email from auth.users
   where id = auth.uid() and email_confirmed_at is not null;
  if v_email is null then return 0; end if;
  for r in select * from company_invites where email = v_email and accepted_at is null for update loop
    insert into company_members (company_id, user_id, role) values (r.company_id, auth.uid(), r.role)
    on conflict (company_id, user_id) do update set active = true, role = excluded.role;
    update company_invites set accepted_at = now(), accepted_by = auth.uid() where id = r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------
-- 3. CREAZIONE AZIENDA: solo gli indirizzi presenti in company_creators
--    (li inserisce il gestore del servizio, da SQL).
-- ---------------------------------------------------------------------
create table public.company_creators (
  email text primary key check (email = lower(btrim(email)))
);
alter table public.company_creators enable row level security;  -- nessuna policy

create or replace function public.create_company(p_name text, p_vat text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_email text;
begin
  if auth.uid() is null then raise exception 'Non autenticato'; end if;
  select lower(email) into v_email from auth.users where id = auth.uid();
  if v_email is null or not exists (select 1 from company_creators where email = v_email) then
    raise exception 'NOT_ALLOWED';
  end if;
  if nullif(btrim(p_name), '') is null then raise exception 'Il nome dell''azienda e'' obbligatorio'; end if;
  insert into companies (name, vat_number) values (btrim(p_name), nullif(btrim(coalesce(p_vat, '')), ''))
    returning id into v_id;
  insert into company_members (company_id, user_id, role) values (v_id, auth.uid(), 'admin');
  insert into sites (company_id, name) values (v_id, 'Sede principale');
  return v_id;
end $$;
