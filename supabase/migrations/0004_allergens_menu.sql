-- =====================================================================
-- 0004 - Allergeni e menu (A4) - Reg. UE 1169/2011, Allegato II
-- Catalogo dei 14 allergeni, piatti con ingredienti e matrice allergeni.
-- La matrice si modifica SOLO tramite la funzione set_menu_item_allergens
-- (atomica, solo admin); cambiare gli ingredienti azzera la verifica.
-- =====================================================================

create type allergen_level as enum ('contains', 'traces');   -- contiene / puo' contenere tracce

create table public.allergens (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  name       text not null,
  sort_order smallint not null
);

insert into public.allergens (code, name, sort_order) values
  ('GLUTEN',    'Cereali contenenti glutine', 1),
  ('CRUSTACEA', 'Crostacei', 2),
  ('EGGS',      'Uova', 3),
  ('FISH',      'Pesce', 4),
  ('PEANUTS',   'Arachidi', 5),
  ('SOYBEANS',  'Soia', 6),
  ('MILK',      'Latte (incluso lattosio)', 7),
  ('NUTS',      'Frutta a guscio', 8),
  ('CELERY',    'Sedano', 9),
  ('MUSTARD',   'Senape', 10),
  ('SESAME',    'Semi di sesamo', 11),
  ('SULPHITES', 'Anidride solforosa e solfiti', 12),
  ('LUPIN',     'Lupini', 13),
  ('MOLLUSCS',  'Molluschi', 14);

create table public.menu_items (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references public.companies(id),
  name                  text not null check (btrim(name) <> ''),
  category              text,
  ingredients           text,
  notes                 text,
  active                boolean not null default true,
  allergens_reviewed_at timestamptz,          -- NULL = allergeni da verificare
  allergens_reviewed_by uuid references auth.users(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz
);
create index on public.menu_items (company_id);

create table public.menu_item_allergens (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id),
  item_id     uuid not null references public.menu_items(id) on delete cascade,
  allergen_id uuid not null references public.allergens(id),
  level       allergen_level not null,
  unique (item_id, allergen_id)
);
create index on public.menu_item_allergens (company_id);

-- Se cambiano gli ingredienti la verifica non e' piu' valida.
create or replace function public.menu_items_ingredients_changed() returns trigger
language plpgsql as $$
begin
  if NEW.ingredients is distinct from OLD.ingredients
     and NEW.allergens_reviewed_at is not distinct from OLD.allergens_reviewed_at then
    NEW.allergens_reviewed_at := null;
    NEW.allergens_reviewed_by := null;
  end if;
  return NEW;
end $$;

create trigger menu_items_1_ingredients before update on public.menu_items
  for each row execute function public.menu_items_ingredients_changed();
create trigger menu_items_updated_at before update on public.menu_items
  for each row execute function public.set_updated_at();
create trigger menu_items_audit after insert or update or delete on public.menu_items
  for each row execute function public.audit_row();
create trigger menu_item_allergens_audit after insert or update or delete on public.menu_item_allergens
  for each row execute function public.audit_row();

-- Sostituisce in blocco la matrice di un piatto e ne registra la verifica.
create or replace function public.set_menu_item_allergens(
  p_item uuid, p_contains uuid[], p_traces uuid[]
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_company uuid;
  v_contains uuid[] := coalesce(p_contains, '{}');
  v_traces   uuid[] := coalesce(p_traces, '{}');
begin
  select company_id into v_company from menu_items where id = p_item and deleted_at is null;
  if v_company is null then
    raise exception 'Piatto non trovato';
  end if;
  if not public.is_admin(v_company) then
    raise exception 'Solo il titolare puo'' modificare gli allergeni' using errcode = '42501';
  end if;
  if exists (select 1 from unnest(v_contains) a where a = any (v_traces)) then
    raise exception 'Un allergene non puo'' essere sia "contiene" sia "tracce"';
  end if;
  if (select count(*) from allergens where id = any (v_contains || v_traces))
       <> cardinality(array(select distinct x from unnest(v_contains || v_traces) x)) then
    raise exception 'Allergene non valido';
  end if;

  delete from menu_item_allergens where item_id = p_item;
  insert into menu_item_allergens (company_id, item_id, allergen_id, level)
    select v_company, p_item, a, 'contains' from (select distinct unnest(v_contains) a) s;
  insert into menu_item_allergens (company_id, item_id, allergen_id, level)
    select v_company, p_item, a, 'traces' from (select distinct unnest(v_traces) a) s;

  update menu_items
     set allergens_reviewed_at = now(), allergens_reviewed_by = auth.uid()
   where id = p_item;
end $$;

grant execute on function public.set_menu_item_allergens(uuid, uuid[], uuid[]) to authenticated;

-- RLS
alter table public.allergens enable row level security;
create policy allergens_select on public.allergens for select to authenticated using (true);

alter table public.menu_items enable row level security;
create policy menu_items_select on public.menu_items for select using (public.is_member(company_id));
create policy menu_items_admin_insert on public.menu_items for insert with check (public.is_admin(company_id));
create policy menu_items_admin_update on public.menu_items for update
  using (public.is_admin(company_id)) with check (public.is_admin(company_id));

alter table public.menu_item_allergens enable row level security;
create policy menu_item_allergens_select on public.menu_item_allergens
  for select using (public.is_member(company_id));
-- nessuna policy di scrittura: solo set_menu_item_allergens
