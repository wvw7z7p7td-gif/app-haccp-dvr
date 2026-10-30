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

-- ---------------------------------------------------------------------
-- T12: ricevimento merci
-- ---------------------------------------------------------------------
reset role;
do $$
declare s2 uuid;
begin
  insert into suppliers (company_id, name) values (current_setting('t.co2')::uuid, 'Fornitore Azienda 2')
  returning id into s2;
  perform set_config('t.sup2', s2::text, true);
end $$;

select pg_temp.login(current_setting('t.ub')::uuid);
do $$
declare
  s uuid := gen_random_uuid(); rc uuid := gen_random_uuid(); rc2 uuid := gen_random_uuid();
  l1 uuid := gen_random_uuid(); l2 uuid := gen_random_uuid();
  h1 text; ph2 text; tout boolean; ex boolean;
begin
  insert into suppliers (id, company_id, name) values (s, current_setting('t.co1')::uuid, 'Fornitore Test');

  -- fornitore di un'altra azienda
  begin
    insert into goods_receipts (id, company_id, site_id, supplier_id, doc_date, received_at)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, current_setting('t.site1')::uuid,
            current_setting('t.sup2')::uuid, current_date, now());
    raise exception 'T12: fornitore di un''altra azienda accettato';
  exception when raise_exception then
    if sqlerrm like 'T12:%' then raise; end if;
  end;

  insert into goods_receipts (id, company_id, site_id, supplier_id, doc_number, doc_date, received_at, employee_id)
  values (rc, current_setting('t.co1')::uuid, current_setting('t.site1')::uuid, s, 'DDT-1',
          current_date, now(), current_setting('t.emp_b')::uuid);

  -- fuori temperatura ma "accettato": bloccato
  begin
    insert into goods_receipt_lines (id, company_id, receipt_id, product_name, lot_code, temp_c, max_limit_c, outcome)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, rc, 'Latte', 'LT-1', 9.0, 4.0, 'accepted');
    raise exception 'T12: prodotto fuori temperatura accettato senza riserva';
  exception when raise_exception then
    if sqlerrm like 'T12:%' then raise; end if;
  end;

  -- scadenza superata ma solo "con riserva": bloccato
  begin
    insert into goods_receipt_lines (id, company_id, receipt_id, product_name, lot_code, expiry_date, expiry_kind, outcome, notes)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, rc, 'Yogurt', 'YG-1',
            current_date - 1, 'use_by', 'accepted_with_reservation', 'scaduto ieri');
    raise exception 'T12: scadenza superata accettata con riserva';
  exception when raise_exception then
    if sqlerrm like 'T12:%' then raise; end if;
  end;

  -- respinto senza motivo: vincolo di controllo
  begin
    insert into goods_receipt_lines (id, company_id, receipt_id, product_name, lot_code, outcome)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, rc, 'Burro', 'BR-1', 'rejected');
    raise exception 'T12: respinto senza motivo accettato';
  exception when check_violation then null;
  end;

  -- riga respinta con motivo: flag calcolati
  insert into goods_receipt_lines (id, company_id, receipt_id, product_name, lot_code, temp_c, max_limit_c, outcome, notes)
  values (l1, current_setting('t.co1')::uuid, rc, 'Latte fresco', 'LT-2', 9.0, 4.0, 'rejected', 'Temperatura oltre il limite');
  select temp_out_of_range, expired into tout, ex from goods_receipt_lines where id = l1;
  assert tout and not ex, 'T12: flag temperatura/scadenza non calcolati';

  -- riga accettata normale, con lotto ricercabile
  insert into goods_receipt_lines (id, company_id, receipt_id, product_name, lot_code, temp_c, max_limit_c, expiry_date)
  values (l2, current_setting('t.co1')::uuid, rc, 'Mozzarella', 'ABC-123', 3.0, 4.0, current_date + 5);
  assert (select count(*) from goods_receipt_lines where lower(lot_code) like '%abc-1%') = 1,
    'T12: ricerca per lotto non trova la riga';

  -- hash chain tra due ricevimenti
  insert into goods_receipts (id, company_id, site_id, supplier_id, doc_date, received_at)
  values (rc2, current_setting('t.co1')::uuid, current_setting('t.site1')::uuid, s, current_date, now());
  select row_hash into h1 from goods_receipts where id = rc;
  select prev_hash into ph2 from goods_receipts where id = rc2;
  assert h1 is not null and ph2 = h1, 'T12: hash chain dei ricevimenti non collegata';

  -- viste
  assert (select rejected_count from v_receipt_summary where receipt_id = rc) = 1, 'T12: v_receipt_summary errata';
  assert (select rejected_12m from v_supplier_stats where supplier_id = s) = 1, 'T12: v_supplier_stats errata';

  -- ritiro
  insert into product_recalls (id, company_id, line_id, lot_code, product_name, action, reason, performed_at)
  values (gen_random_uuid(), current_setting('t.co1')::uuid, l2, 'ABC-123', 'Mozzarella',
          'discarded', 'Richiamo del produttore', now());
end $$;

-- consulente: legge ma non registra
select pg_temp.login(current_setting('t.ud')::uuid);
do $$ begin
  assert (select count(*) from goods_receipts) = 2, 'T12: il consulente non legge i ricevimenti';
  begin
    insert into suppliers (company_id, name) values (current_setting('t.co1')::uuid, 'Intruso');
    raise exception 'T12: il consulente ha creato un fornitore';
  exception when insufficient_privilege then null;
  end;
end $$;

-- isolamento: C non vede nulla dell'azienda 1
reset role; select pg_temp.login(current_setting('t.uc')::uuid);
do $$ begin
  assert (select count(*) from goods_receipts) = 0, 'T12: C vede i ricevimenti di un''altra azienda';
  assert (select count(*) from goods_receipt_lines) = 0, 'T12: C vede le righe di un''altra azienda';
  assert (select count(*) from suppliers) = 1, 'T12: C vede fornitori di altre aziende';
end $$;

-- immutabilita' dei registri
reset role;
do $$ begin
  begin
    update goods_receipt_lines set lot_code = 'MOD';
    raise exception 'T12: update delle righe NON bloccato';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from goods_receipts;
    raise exception 'T12: delete dei ricevimenti NON bloccato';
  exception when insufficient_privilege then null;
  end;
  begin
    update product_recalls set reason = 'x';
    raise exception 'T12: update dei ritiri NON bloccato';
  exception when insufficient_privilege then null;
  end;
  assert exists (select 1 from storage.buckets where id = 'receipts' and not public),
    'T12: bucket receipts mancante o pubblico';
end $$;

-- ---------------------------------------------------------------------
-- T13: allergeni e menu
-- ---------------------------------------------------------------------
reset role;
do $$ begin
  assert (select count(*) from allergens) = 14, 'T13: il catalogo deve avere 14 allergeni';
end $$;

select pg_temp.login(current_setting('t.ua')::uuid);
do $$
declare
  it uuid := gen_random_uuid();
  g uuid; m uuid; e uuid;
  rev timestamptz;
begin
  select id into g from allergens where code = 'GLUTEN';
  select id into m from allergens where code = 'MILK';
  select id into e from allergens where code = 'EGGS';

  insert into menu_items (id, company_id, name, category, ingredients)
  values (it, current_setting('t.co1')::uuid, 'Tagliatelle al ragu', 'Primi', 'farina, uova, carne');
  perform set_config('t.item', it::text, true);
  assert (select allergens_reviewed_at from menu_items where id = it) is null,
    'T13: un piatto nuovo deve risultare da verificare';

  -- scrittura diretta sulla matrice: vietata
  begin
    insert into menu_item_allergens (company_id, item_id, allergen_id, level)
    values (current_setting('t.co1')::uuid, it, g, 'contains');
    raise exception 'T13: scrittura diretta sulla matrice consentita';
  exception when insufficient_privilege then null;
  end;

  perform set_menu_item_allergens(it, array[g, e], array[m]);
  assert (select count(*) from menu_item_allergens where item_id = it and level = 'contains') = 2,
    'T13: allergeni "contiene" errati';
  assert (select count(*) from menu_item_allergens where item_id = it and level = 'traces') = 1,
    'T13: allergeni "tracce" errati';
  select allergens_reviewed_at into rev from menu_items where id = it;
  assert rev is not null, 'T13: verifica non registrata';

  -- stesso allergene in entrambi i livelli
  begin
    perform set_menu_item_allergens(it, array[g], array[g]);
    raise exception 'T13: allergene sia contiene sia tracce accettato';
  exception when raise_exception then
    if sqlerrm like 'T13:%' then raise; end if;
  end;

  -- allergene inesistente
  begin
    perform set_menu_item_allergens(it, array[gen_random_uuid()], '{}');
    raise exception 'T13: allergene inesistente accettato';
  exception when raise_exception then
    if sqlerrm like 'T13:%' then raise; end if;
  end;

  -- la matrice precedente e' rimasta intatta dopo i tentativi falliti
  assert (select count(*) from menu_item_allergens where item_id = it) = 3, 'T13: matrice alterata';

  -- cambiare gli ingredienti azzera la verifica; cambiare solo il nome no
  update menu_items set name = 'Tagliatelle al ragu'' bolognese' where id = it;
  assert (select allergens_reviewed_at from menu_items where id = it) is not null,
    'T13: il cambio nome non deve azzerare la verifica';
  update menu_items set ingredients = 'farina, uova, carne, burro' where id = it;
  assert (select allergens_reviewed_at from menu_items where id = it) is null,
    'T13: il cambio ingredienti deve azzerare la verifica';

  -- audit
  assert exists (select 1 from audit_log where table_name = 'menu_item_allergens'),
    'T13: audit della matrice mancante';
end $$;

-- operatore: legge ma non modifica
select pg_temp.login(current_setting('t.ub')::uuid);
do $$ begin
  assert (select count(*) from menu_items) = 1, 'T13: l''operatore non legge il menu';
  begin
    insert into menu_items (company_id, name) values (current_setting('t.co1')::uuid, 'Abusivo');
    raise exception 'T13: operatore ha creato un piatto';
  exception when insufficient_privilege then null;
  end;
  begin
    perform set_menu_item_allergens(current_setting('t.item')::uuid, '{}', '{}');
    raise exception 'T13: operatore ha modificato gli allergeni';
  exception when insufficient_privilege then null;
  end;
end $$;

-- consulente: lettura della matrice
select pg_temp.login(current_setting('t.ud')::uuid);
do $$ begin
  assert (select count(*) from menu_item_allergens) = 3, 'T13: il consulente non legge la matrice';
end $$;

-- altra azienda: isolamento
reset role; select pg_temp.login(current_setting('t.uc')::uuid);
do $$ begin
  assert (select count(*) from menu_items) = 0, 'T13: C vede il menu di un''altra azienda';
  assert (select count(*) from menu_item_allergens) = 0, 'T13: C vede la matrice di un''altra azienda';
  begin
    perform set_menu_item_allergens(current_setting('t.item')::uuid, '{}', '{}');
    raise exception 'T13: C ha modificato allergeni di un''altra azienda';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------------------------------------------------------------------
-- T14: controllo infestanti
-- ---------------------------------------------------------------------
reset role;
select pg_temp.login(current_setting('t.ub')::uuid);
do $$
declare
  co uuid := current_setting('t.co1')::uuid;
  site uuid := current_setting('t.site1')::uuid;
  st1 uuid := gen_random_uuid(); st2 uuid := gen_random_uuid();
  in1 uuid := gen_random_uuid(); in2 uuid := gen_random_uuid(); in3 uuid := gen_random_uuid();
  it1 uuid := gen_random_uuid(); it2 uuid := gen_random_uuid(); it_ok uuid := gen_random_uuid();
  h1 text; ph2 text;
begin
  insert into pest_stations (id, company_id, site_id, code, kind, location)
  values (st1, co, site, 'E1', 'rodent_bait', 'Retro cucina'),
         (st2, co, site, 'L1', 'insect_light', 'Ingresso');
  perform set_config('t.pst1', st1::text, true);

  -- codice duplicato nella stessa sede
  begin
    insert into pest_stations (company_id, site_id, code, kind) values (co, site, 'e1', 'other');
    raise exception 'T14: codice postazione duplicato accettato';
  exception when unique_violation then null;
  end;

  -- postazione prima di qualsiasi controllo: in ritardo
  assert (select overdue from v_pest_station_status where station_id = st1), 'T14: postazione mai controllata non in ritardo';

  -- servizio esterno senza fornitore
  begin
    insert into pest_inspections (id, company_id, site_id, kind, inspected_at)
    values (gen_random_uuid(), co, site, 'external_service', now());
    raise exception 'T14: servizio esterno senza fornitore accettato';
  exception when check_violation then null;
  end;

  insert into pest_inspections (id, company_id, site_id, inspected_at, employee_id)
  values (in1, co, site, now(), current_setting('t.emp_b')::uuid);

  -- rilievo non conforme senza note
  begin
    insert into pest_inspection_items (id, company_id, inspection_id, station_id, status)
    values (gen_random_uuid(), co, in1, st1, 'activity');
    raise exception 'T14: rilievo non conforme senza note accettato';
  exception when check_violation then null;
  end;

  insert into pest_inspection_items (id, company_id, inspection_id, station_id, status, catch_count, notes)
  values (it1, co, in1, st1, 'activity', 2, 'Esca consumata, 2 catture');
  insert into pest_inspection_items (id, company_id, inspection_id, station_id, status)
  values (it_ok, co, in1, st2, 'ok');

  -- stessa postazione due volte nella stessa ispezione
  begin
    insert into pest_inspection_items (id, company_id, inspection_id, station_id, status)
    values (gen_random_uuid(), co, in1, st2, 'ok');
    raise exception 'T14: postazione duplicata nell''ispezione accettata';
  exception when unique_violation then null;
  end;

  assert not (select overdue from v_pest_station_status where station_id = st1), 'T14: postazione appena controllata in ritardo';
  assert (select last_status from v_pest_station_status where station_id = st1) = 'activity', 'T14: ultimo esito errato';
  assert (select count(*) from v_open_pest_findings) = 1, 'T14: rilievo aperto non rilevato';

  -- azione correttiva su postazione conforme: vietata
  begin
    insert into pest_corrective_actions (id, company_id, item_id, action, performed_at)
    values (gen_random_uuid(), co, it_ok, 'Niente', now());
    raise exception 'T14: azione correttiva su rilievo conforme accettata';
  exception when raise_exception then
    if sqlerrm like 'T14:%' then raise; end if;
  end;

  insert into pest_corrective_actions (id, company_id, item_id, action, performed_at)
  values (gen_random_uuid(), co, it1, 'Sostituita esca, chiamato il disinfestatore', now());
  assert (select count(*) from v_open_pest_findings) = 0, 'T14: rilievo non chiuso dall''azione';

  -- hash chain
  insert into pest_inspections (id, company_id, site_id, inspected_at) values (in2, co, site, now());
  select row_hash into h1 from pest_inspections where id = in1;
  select prev_hash into ph2 from pest_inspections where id = in2;
  assert h1 is not null and ph2 = h1, 'T14: hash chain ispezioni non collegata';
end $$;

-- postazione di un'altra sede/azienda
reset role;
do $$
declare s2 uuid := gen_random_uuid(); st_other uuid := gen_random_uuid(); insp uuid := gen_random_uuid();
begin
  insert into sites (id, company_id, name) values (s2, current_setting('t.co1')::uuid, 'Seconda sede');
  insert into pest_stations (id, company_id, site_id, code, kind)
  values (st_other, current_setting('t.co1')::uuid, s2, 'X1', 'glue_trap');
  insert into pest_inspections (id, company_id, site_id, inspected_at)
  values (insp, current_setting('t.co1')::uuid, current_setting('t.site1')::uuid, now());
  begin
    insert into pest_inspection_items (id, company_id, inspection_id, station_id, status)
    values (gen_random_uuid(), current_setting('t.co1')::uuid, insp, st_other, 'ok');
    raise exception 'T14: postazione di un''altra sede accettata';
  exception when raise_exception then
    if sqlerrm like 'T14:%' then raise; end if;
  end;
end $$;

-- consulente: legge, non scrive
select pg_temp.login(current_setting('t.ud')::uuid);
do $$ begin
  assert (select count(*) from pest_inspections) >= 2, 'T14: il consulente non legge le ispezioni';
  begin
    insert into pest_stations (company_id, site_id, code, kind)
    values (current_setting('t.co1')::uuid, current_setting('t.site1')::uuid, 'Z9', 'other');
    raise exception 'T14: il consulente ha creato una postazione';
  exception when insufficient_privilege then null;
  end;
end $$;

-- operatore: non modifica le postazioni (solo admin)
select pg_temp.login(current_setting('t.ub')::uuid);
do $$ begin
  update pest_stations set location = 'Spostata' where id = current_setting('t.pst1')::uuid;
  assert (select location from pest_stations where id = current_setting('t.pst1')::uuid) = 'Retro cucina',
    'T14: l''operatore ha modificato una postazione';
end $$;

-- altra azienda: isolamento
reset role; select pg_temp.login(current_setting('t.uc')::uuid);
do $$ begin
  assert (select count(*) from pest_stations) = 0, 'T14: C vede postazioni altrui';
  assert (select count(*) from pest_inspections) = 0, 'T14: C vede ispezioni altrui';
  assert (select count(*) from v_pest_station_status) = 0, 'T14: C vede lo stato postazioni altrui';
end $$;

-- immutabilita'
reset role;
do $$ begin
  begin
    update pest_inspection_items set status = 'ok';
    raise exception 'T14: update dei rilievi NON bloccato';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from pest_inspections;
    raise exception 'T14: delete delle ispezioni NON bloccato';
  exception when insufficient_privilege then null;
  end;
  assert exists (select 1 from storage.buckets where id = 'pest-reports' and not public),
    'T14: bucket pest-reports mancante o pubblico';
end $$;

-- ---------------------------------------------------------------------
-- T15: DVR digitale
-- ---------------------------------------------------------------------
reset role;
do $$ begin
  assert (select count(*) from hazard_catalog) >= 15, 'T15: catalogo pericoli incompleto';
  assert risk_level(1) = 'low' and risk_level(2) = 'low' and risk_level(3) = 'medium'
     and risk_level(4) = 'medium' and risk_level(6) = 'high' and risk_level(8) = 'high'
     and risk_level(9) = 'very_high' and risk_level(16) = 'very_high', 'T15: soglie risk_level errate';
end $$;

select pg_temp.login(current_setting('t.ua')::uuid);
do $$
declare
  co uuid := current_setting('t.co1')::uuid;
  site uuid := current_setting('t.site1')::uuid;
  haz uuid; r1 uuid := gen_random_uuid(); r2 uuid := gen_random_uuid();
  d1 uuid := gen_random_uuid(); d2 uuid := gen_random_uuid(); d3 uuid := gen_random_uuid();
  snap jsonb; sha text; act uuid := gen_random_uuid();
begin
  select id into haz from hazard_catalog where code = 'CUT';

  -- DVR vuoto: non emettibile
  insert into dvr_documents (id, company_id, site_id, version) values (d1, co, site, '1.0');
  begin
    perform issue_dvr(d1, current_date + 365);
    raise exception 'T15: DVR vuoto emesso';
  exception when raise_exception then
    if sqlerrm like 'T15:%' then raise; end if;
  end;

  insert into dvr_risks (id, company_id, site_id, hazard_id, title, probability, severity, measures,
                         residual_probability, residual_severity)
  values (r1, co, site, haz, 'Tagli con coltelli in cucina', 3, 3, 'Guanti antitaglio, formazione', 2, 2);
  assert (select risk_score from dvr_risks where id = r1) = 9, 'T15: punteggio rischio errato';
  assert (select residual_score from dvr_risks where id = r1) = 4, 'T15: punteggio residuo errato';
  assert (select level from v_dvr_risk_summary where id = r1) = 'very_high', 'T15: livello errato';

  -- residuo superiore all'iniziale
  begin
    insert into dvr_risks (company_id, site_id, hazard_id, title, probability, severity,
                           residual_probability, residual_severity)
    values (co, site, haz, 'Incoerente', 1, 2, 3, 3);
    raise exception 'T15: rischio residuo maggiore dell''iniziale accettato';
  exception when raise_exception then
    if sqlerrm like 'T15:%' then raise; end if;
  end;

  -- residuo solo a meta'
  begin
    insert into dvr_risks (company_id, site_id, hazard_id, title, probability, severity, residual_probability)
    values (co, site, haz, 'Mezzo residuo', 2, 2, 1);
    raise exception 'T15: residuo incompleto accettato';
  exception when check_violation then null;
  end;

  insert into dvr_risks (id, company_id, site_id, hazard_id, title, probability, severity)
  values (r2, co, site, haz, 'Scivolamento nel retro', 2, 2);

  insert into dvr_actions (id, company_id, risk_id, description, due_on)
  values (act, co, r1, 'Acquistare guanti antitaglio per tutti', current_date - 5);
  assert (select count(*) from v_dvr_actions_overdue) = 1, 'T15: azione scaduta non rilevata';
  begin
    update dvr_actions set status = 'done' where id = act;
    raise exception 'T15: azione completata senza data';
  exception when check_violation then null;
  end;
  update dvr_actions set status = 'done', done_on = current_date where id = act;
  assert (select count(*) from v_dvr_actions_overdue) = 0, 'T15: azione completata ancora scaduta';

  insert into safety_officers (company_id, role, external_name, appointed_on)
  values (co, 'rspp', 'Ing. Rossi', current_date - 100);
  begin
    insert into safety_officers (company_id, role) values (co, 'rls');
    raise exception 'T15: figura senza nome ne'' dipendente accettata';
  exception when check_violation then null;
  end;

  -- scrittura diretta dello snapshot: vietata
  begin
    update dvr_documents set snapshot = '{}'::jsonb where id = d1;
    raise exception 'T15: snapshot scritto fuori da issue_dvr';
  exception when insufficient_privilege then null;
  end;

  -- data di revisione nel passato
  begin
    perform issue_dvr(d1, current_date - 1);
    raise exception 'T15: revisione nel passato accettata';
  exception when raise_exception then
    if sqlerrm like 'T15:%' then raise; end if;
  end;

  perform issue_dvr(d1, current_date + 365, 'Prima emissione');
  select snapshot, snapshot_sha256 into snap, sha from dvr_documents where id = d1;
  assert (select status from dvr_documents where id = d1) = 'active', 'T15: DVR non attivo dopo emissione';
  assert jsonb_array_length(snap->'risks') = 2, 'T15: snapshot senza i rischi';
  assert (snap->'risks'->0->>'score')::int = 9, 'T15: rischi non ordinati per gravita''';
  assert jsonb_array_length(snap->'officers') = 1, 'T15: snapshot senza figure';
  assert sha = encode(extensions.digest(snap::text, 'sha256'), 'hex'), 'T15: impronta non coerente';
  perform set_config('t.dvr1', d1::text, true);

  -- la modifica successiva dei rischi non altera lo snapshot
  update dvr_risks set title = 'Titolo cambiato' where id = r1;
  assert (select snapshot from dvr_documents where id = d1) = snap, 'T15: snapshot alterato dai rischi';

  -- una versione emessa non si altera
  begin
    update dvr_documents set version = '9.9' where id = d1;
    raise exception 'T15: versione emessa modificata';
  exception when insufficient_privilege then null;
  end;

  -- nuova versione: la precedente diventa sostituita
  insert into dvr_documents (id, company_id, site_id, version) values (d2, co, site, '2.0');
  perform issue_dvr(d2, current_date + 365);
  assert (select status from dvr_documents where id = d1) = 'superseded', 'T15: versione precedente non sostituita';
  assert (select status from dvr_documents where id = d2) = 'active', 'T15: nuova versione non attiva';

  -- una versione sostituita non torna attiva
  begin
    update dvr_documents set status = 'active' where id = d1;
    raise exception 'T15: versione sostituita riattivata';
  exception when insufficient_privilege then null;
  end;

  -- una versione gia' emessa non si riemette
  begin
    perform issue_dvr(d2, current_date + 400);
    raise exception 'T15: versione gia'' emessa riemessa';
  exception when raise_exception then
    if sqlerrm like 'T15:%' then raise; end if;
  end;

  insert into dvr_documents (id, company_id, site_id, version) values (d3, co, site, '3.0');
  perform set_config('t.dvr3', d3::text, true);
end $$;

-- operatore: legge, non scrive, non emette
select pg_temp.login(current_setting('t.ub')::uuid);
do $$ begin
  assert (select count(*) from dvr_risks) = 2, 'T15: l''operatore non legge i rischi';
  begin
    insert into dvr_risks (company_id, site_id, hazard_id, title, probability, severity)
    values (current_setting('t.co1')::uuid, current_setting('t.site1')::uuid,
            (select id from hazard_catalog limit 1), 'Abusivo', 1, 1);
    raise exception 'T15: l''operatore ha creato un rischio';
  exception when insufficient_privilege then null;
  end;
  begin
    perform issue_dvr(current_setting('t.dvr3')::uuid, current_date + 100);
    raise exception 'T15: l''operatore ha emesso il DVR';
  exception when insufficient_privilege then null;
  end;
end $$;

-- consulente: lettura
select pg_temp.login(current_setting('t.ud')::uuid);
do $$ begin
  assert (select count(*) from dvr_documents where snapshot is not null) = 2, 'T15: il consulente non legge i DVR';
end $$;

-- altra azienda
reset role; select pg_temp.login(current_setting('t.uc')::uuid);
do $$ begin
  assert (select count(*) from dvr_risks) = 0, 'T15: C vede rischi altrui';
  assert (select count(*) from dvr_documents) = 0, 'T15: C vede DVR altrui';
  begin
    perform issue_dvr(current_setting('t.dvr3')::uuid, current_date + 100);
    raise exception 'T15: C ha emesso il DVR di un''altra azienda';
  exception when insufficient_privilege or raise_exception then
    if sqlerrm like 'T15:%' then raise; end if;
  end;
end $$;

reset role;
rollback;
\echo 'TUTTI I TEST DATABASE SUPERATI'
