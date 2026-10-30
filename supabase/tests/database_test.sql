-- =====================================================================
-- Test del database (eseguito in CI su uno stack Supabase locale).
-- Tutto avviene in una transazione annullata alla fine (nessun residuo).
-- Un'asserzione fallita interrompe l'esecuzione (ON_ERROR_STOP).
-- =====================================================================
\set ON_ERROR_STOP on
begin;

-- Utility: simula un utente autenticato (come fa PostgREST con il JWT)
create function pg_temp.login(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', u::text, true);
  set local role authenticated;
end $$;

-- Controllo: le asserzioni devono essere attive, altrimenti i test non provano nulla
do $$ begin
  begin
    assert false, 'controllo';
    raise exception 'SETUP: le asserzioni plpgsql sono disattivate';
  exception when assert_failure then null;
  end;
end $$;

-- ---------------------------------------------------------------------
-- FIXTURE (come superuser, aggira la RLS)
-- ---------------------------------------------------------------------
do $$
declare
  ua uuid := gen_random_uuid();  -- admin azienda 1
  ub uuid := gen_random_uuid();  -- operatore azienda 1
  uc uuid := gen_random_uuid();  -- admin azienda 2
  ud uuid := gen_random_uuid();  -- consulente azienda 1
  co1 uuid; co2 uuid; site1 uuid; site2 uuid; cp1 uuid;
  emp_a uuid; emp_b uuid; emp_s uuid; plan1 uuid; plan2 uuid;
begin
  insert into auth.users (id, email) values
    (ua, 'a@test.local'), (ub, 'b@test.local'), (uc, 'c@test.local'), (ud, 'd@test.local');

  insert into companies (name) values ('Azienda 1') returning id into co1;
  insert into companies (name) values ('Azienda 2') returning id into co2;

  insert into company_members (company_id, user_id, role) values
    (co1, ua, 'admin'), (co1, ub, 'employee'), (co1, ud, 'consultant'), (co2, uc, 'admin');

  insert into sites (company_id, name) values (co1, 'Sede 1') returning id into site1;
  insert into sites (company_id, name) values (co2, 'Sede 2') returning id into site2;

  insert into temp_control_points (company_id, site_id, name, kind, min_temp_c, max_temp_c)
  values (co1, site1, 'Cella 1', 'fridge', 0, 4) returning id into cp1;

  insert into employees (company_id, site_id, user_id, first_name, last_name, is_supervisor)
  values (co1, site1, ua, 'Anna', 'Admin', true) returning id into emp_a;
  insert into employees (company_id, site_id, user_id, first_name, last_name, is_supervisor)
  values (co1, site1, ub, 'Bruno', 'Operatore', false) returning id into emp_b;
  insert into employees (company_id, site_id, first_name, last_name, is_supervisor)
  values (co1, site1, 'Sara', 'Responsabile', true) returning id into emp_s;

  insert into cleaning_plans (company_id, site_id, name, frequency, requires_approval)
  values (co1, site1, 'Piano 1', 'daily', true) returning id into plan1;
  insert into cleaning_plans (company_id, site_id, name, frequency)
  values (co2, site2, 'Piano 2', 'daily') returning id into plan2;

  perform set_config('t.ua', ua::text, true);  perform set_config('t.ub', ub::text, true);
  perform set_config('t.uc', uc::text, true);  perform set_config('t.ud', ud::text, true);
  perform set_config('t.co1', co1::text, true); perform set_config('t.co2', co2::text, true);
  perform set_config('t.site1', site1::text, true); perform set_config('t.site2', site2::text, true);
  perform set_config('t.cp1', cp1::text, true);
  perform set_config('t.emp_a', emp_a::text, true); perform set_config('t.emp_b', emp_b::text, true);
  perform set_config('t.emp_s', emp_s::text, true);
  perform set_config('t.plan1', plan1::text, true); perform set_config('t.plan2', plan2::text, true);
end $$;

-- ---------------------------------------------------------------------
-- T1-T2: isolamento tra aziende (utente C, admin dell'azienda 2)
-- ---------------------------------------------------------------------
reset role; select pg_temp.login(current_setting('t.uc')::uuid);
do $$ begin
  assert (select count(*) from companies) = 1, 'T1: C vede un numero di aziende diverso da 1';
  assert (select count(*) from sites) = 1, 'T1: C vede sedi di altre aziende';
  assert (select count(*) from temp_control_points) = 0, 'T1: C vede punti di controllo altrui';
  assert (select count(*) from cleaning_plans) = 1, 'T1: C vede piani di altre aziende';
end $$;

do $$ begin
  begin
    insert into sites (company_id, name) values (current_setting('t.co1')::uuid, 'intruso');
    raise exception 'T2: inserimento in un''altra azienda NON bloccato';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------------------------------------------------------------------
-- T3: registro temperature - calcolo fuori range e hash chain (operatore B)
-- ---------------------------------------------------------------------
reset role; select pg_temp.login(current_setting('t.ub')::uuid);
do $$
declare
  r1 uuid := gen_random_uuid(); r2 uuid := gen_random_uuid();
  o1 boolean; h1 text; o2 boolean; ph2 text; mn numeric; rcv timestamptz;
begin
  insert into temp_readings (id, company_id, site_id, control_point_id, value_c, measured_at)
  values (r1, current_setting('t.co1')::uuid, current_setting('t.site1')::uuid,
          current_setting('t.cp1')::uuid, 6.0, now() - interval '1 hour');
  insert into temp_readings (id, company_id, site_id, control_point_id, value_c, measured_at)
  values (r2, current_setting('t.co1')::uuid, current_setting('t.site1')::uuid,
          current_setting('t.cp1')::uuid, 3.0, now());

  select out_of_range, row_hash, min_c_snapshot, received_at into o1, h1, mn, rcv
  from temp_readings where id = r1;
  select out_of_range, prev_hash into o2, ph2 from temp_readings where id = r2;

  assert o1, 'T3: 6 °C con limite 4 °C non segnato fuori range';
  assert not o2, 'T3: 3 °C segnato fuori range';
  assert mn = 0, 'T3: limite minimo non salvato nella rilevazione';
  assert rcv is not null, 'T3: received_at mancante';
  assert h1 is not null and length(h1) = 64, 'T3: row_hash mancante';
  assert ph2 = h1, 'T3: la hash chain non collega le due rilevazioni';
  perform set_config('t.r1', r1::text, true);
end $$;

-- T4: i registri non si modificano (RLS: nessuna riga; superuser: trigger)
do $$ declare n int; begin
  update temp_readings set value_c = 1 where id = current_setting('t.r1')::uuid;
  get diagnostics n = row_count;
  assert n = 0, 'T4: un operatore ha modificato una rilevazione';
end $$;

reset role;
do $$ begin
  begin
    update temp_readings set value_c = 1 where id = current_setting('t.r1')::uuid;
    raise exception 'T4: update del registro NON bloccato dal trigger';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from temp_readings where id = current_setting('t.r1')::uuid;
    raise exception 'T4: delete del registro NON bloccato dal trigger';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------------------------------------------------------------------
-- T5: consulente (D) legge ma non scrive i registri
-- ---------------------------------------------------------------------
select pg_temp.login(current_setting('t.ud')::uuid);
do $$ begin
  assert (select count(*) from temp_readings) = 2, 'T5: il consulente non legge i registri';
  begin
    insert into temp_readings (id, company_id, site_id, control_point_id, value_c, measured_at)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, current_setting('t.site1')::uuid,
            current_setting('t.cp1')::uuid, 2.0, now());
    raise exception 'T5: il consulente ha potuto scrivere una rilevazione';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------------------------------------------------------------------
-- T6: scostamenti aperti e azione correttiva (operatore B)
-- ---------------------------------------------------------------------
reset role; select pg_temp.login(current_setting('t.ub')::uuid);
do $$ begin
  assert exists (select 1 from v_open_temp_deviations where id = current_setting('t.r1')::uuid),
    'T6: lo scostamento non risulta aperto';
  insert into temp_corrective_actions (id, company_id, reading_id, action_taken, product_fate)
  values (gen_random_uuid(), current_setting('t.co1')::uuid, current_setting('t.r1')::uuid,
          'Prodotto spostato in altra cella', 'kept');
  assert not exists (select 1 from v_open_temp_deviations where id = current_setting('t.r1')::uuid),
    'T6: lo scostamento resta aperto dopo l''azione correttiva';
end $$;

-- ---------------------------------------------------------------------
-- T7: PIN operatore
-- ---------------------------------------------------------------------
reset role; select pg_temp.login(current_setting('t.ua')::uuid);
select set_employee_pin(current_setting('t.emp_b')::uuid, '1234');

reset role; select pg_temp.login(current_setting('t.ub')::uuid);
do $$ begin
  assert verify_employee_pin(current_setting('t.emp_b')::uuid, '1234'), 'T7: PIN corretto rifiutato';
  assert not verify_employee_pin(current_setting('t.emp_b')::uuid, '0000'), 'T7: PIN errato accettato';
  begin
    perform set_employee_pin(current_setting('t.emp_b')::uuid, '9999');
    raise exception 'T7: un operatore ha cambiato un PIN';
  exception when raise_exception then
    if sqlerrm like 'T7:%' then raise; end if;
  end;
  assert (select count(*) from employee_pins) = 1, 'T7: i PIN non sono leggibili dall''operatore';
end $$;

reset role; select pg_temp.login(current_setting('t.ua')::uuid);
do $$ begin
  begin
    perform set_employee_pin(current_setting('t.emp_b')::uuid, '12');
    raise exception 'T7: PIN troppo corto accettato';
  exception when raise_exception then
    if sqlerrm like 'T7:%' then raise; end if;
  end;
end $$;

-- ---------------------------------------------------------------------
-- T8: pulizie - registrazione, coerenza azienda, controfirma
-- ---------------------------------------------------------------------
reset role; select pg_temp.login(current_setting('t.ub')::uuid);
do $$
declare l1 uuid := gen_random_uuid(); l2 uuid := gen_random_uuid(); h text; rcv timestamptz;
begin
  insert into cleaning_logs (id, company_id, site_id, plan_id, due_date, status, employee_id, performed_at)
  values (l1, current_setting('t.co1')::uuid, current_setting('t.site1')::uuid,
          current_setting('t.plan1')::uuid, current_date, 'done',
          current_setting('t.emp_b')::uuid, now());
  select row_hash, received_at into h, rcv from cleaning_logs where id = l1;
  assert h is not null and rcv is not null, 'T8: registrazione pulizia senza hash/ricezione';

  -- piano di un'altra azienda
  begin
    insert into cleaning_logs (id, company_id, site_id, plan_id, due_date, status, performed_at)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, current_setting('t.site1')::uuid,
            current_setting('t.plan2')::uuid, current_date, 'done', now());
    raise exception 'T8: piano di un''altra azienda accettato';
  exception when raise_exception then
    if sqlerrm like 'T8:%' then raise; end if;
  end;

  -- controfirma di chi non e' responsabile
  begin
    insert into cleaning_log_approvals (id, company_id, log_id, employee_id)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, l1, current_setting('t.emp_b')::uuid);
    raise exception 'T8: controfirma di un non responsabile accettata';
  exception when raise_exception then
    if sqlerrm like 'T8:%' then raise; end if;
  end;

  -- controfirma valida (responsabile diverso dall'esecutore)
  insert into cleaning_log_approvals (id, company_id, log_id, employee_id)
  values (gen_random_uuid(), current_setting('t.co1')::uuid, l1, current_setting('t.emp_a')::uuid);

  -- seconda controfirma sulla stessa registrazione
  begin
    insert into cleaning_log_approvals (id, company_id, log_id, employee_id)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, l1, current_setting('t.emp_s')::uuid);
    raise exception 'T8: doppia controfirma accettata';
  exception when unique_violation then null;
  end;

  -- esecutore responsabile che controfirma se stesso
  insert into cleaning_logs (id, company_id, site_id, plan_id, due_date, status, employee_id, performed_at)
  values (l2, current_setting('t.co1')::uuid, current_setting('t.site1')::uuid,
          current_setting('t.plan1')::uuid, current_date, 'done',
          current_setting('t.emp_s')::uuid, now());
  begin
    insert into cleaning_log_approvals (id, company_id, log_id, employee_id)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, l2, current_setting('t.emp_s')::uuid);
    raise exception 'T8: auto-controfirma accettata';
  exception when raise_exception then
    if sqlerrm like 'T8:%' then raise; end if;
  end;
end $$;

-- ---------------------------------------------------------------------
-- T9: formazione e DPI - scadenze calcolate, viste
-- ---------------------------------------------------------------------
reset role; select pg_temp.login(current_setting('t.ua')::uuid);
do $$
declare tt uuid; exp date; ppe uuid := gen_random_uuid(); exp2 date;
begin
  select id into tt from training_types where code = 'HACCP' and company_id is null;
  assert tt is not null, 'T9: catalogo formazione globale non visibile';

  insert into training_records (company_id, employee_id, training_type_id, issued_on)
  values (current_setting('t.co1')::uuid, current_setting('t.emp_b')::uuid, tt, date '2026-01-15');
  select expires_on into exp from training_records
  where employee_id = current_setting('t.emp_b')::uuid and training_type_id = tt;
  assert exp = date '2029-01-15', 'T9: scadenza HACCP (36 mesi) non calcolata: ' || coalesce(exp::text, 'null');

  insert into ppe_types (id, company_id, name, replace_after_months)
  values (ppe, current_setting('t.co1')::uuid, 'Scarpe antinfortunistiche', 12);
  insert into ppe_assignments (id, company_id, employee_id, ppe_type_id, delivered_on)
  values (gen_random_uuid(), current_setting('t.co1')::uuid, current_setting('t.emp_b')::uuid, ppe, date '2026-02-01');
  select expires_on into exp2 from ppe_assignments where ppe_type_id = ppe;
  assert exp2 = date '2027-02-01', 'T9: scadenza DPI non calcolata';

  assert (select count(*) from v_deadlines where kind = 'training') = 1, 'T9: v_deadlines senza la formazione';
  assert (select count(*) from v_deadlines where kind = 'ppe') = 1, 'T9: v_deadlines senza i DPI';
end $$;

-- ---------------------------------------------------------------------
-- T10: audit log
-- ---------------------------------------------------------------------
do $$ begin
  assert (select count(*) from audit_log) > 0, 'T10: l''admin non vede l''audit log';
end $$;

reset role; select pg_temp.login(current_setting('t.ub')::uuid);
do $$ begin
  assert (select count(*) from audit_log) = 0, 'T10: l''operatore vede l''audit log';
end $$;

reset role;
do $$ begin
  begin
    delete from audit_log;
    raise exception 'T10: delete dell''audit log NON bloccato';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------------------------------------------------------------------
-- T11: bucket firme e policy storage
-- ---------------------------------------------------------------------
do $$ begin
  assert exists (select 1 from storage.buckets where id = 'signatures' and not public),
    'T11: bucket signatures mancante o pubblico';
end $$;

select pg_temp.login(current_setting('t.ub')::uuid);
do $$ begin
  insert into storage.objects (bucket_id, name)
  values ('signatures', current_setting('t.co1') || '/cleaning/test.png');
  begin
    insert into storage.objects (bucket_id, name)
    values ('signatures', current_setting('t.co2') || '/cleaning/test.png');
    raise exception 'T11: scrittura nella cartella di un''altra azienda accettata';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;
\echo 'TUTTI I TEST DATABASE SUPERATI'
