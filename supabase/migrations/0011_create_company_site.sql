-- La creazione dell'azienda crea anche la sede principale: i punti di controllo ne hanno bisogno.
create or replace function public.create_company(p_name text, p_vat text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Non autenticato'; end if;
  if nullif(btrim(p_name), '') is null then raise exception 'Il nome dell''azienda e'' obbligatorio'; end if;
  insert into companies (name, vat_number) values (btrim(p_name), nullif(btrim(coalesce(p_vat, '')), ''))
    returning id into v_id;
  insert into company_members (company_id, user_id, role) values (v_id, auth.uid(), 'admin');
  insert into sites (company_id, name) values (v_id, 'Sede principale');
  return v_id;
end $$;
