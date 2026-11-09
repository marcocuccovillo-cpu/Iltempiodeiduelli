-- =====================================================================
-- MIGRAZIONE 041 — LA GUERRA DEGLI EROI: LA MAPPA DEI TERRENI E LA LOCANDA
-- Da eseguire in Supabase (SQL Editor) DOPO tutte le migrazioni precedenti (ultima: 040, nuovi gradi di abilità).
--
-- MAPPA: una griglia 20 × 16 divisa in 8 regioni a tema (40 caselle ciascuna); al centro la Locanda (4 caselle, non si compra).
--   In tutto 316 terreni. Ogni regione si sblocca a un livello e ha un prezzo e una rendita base:
--     Prati del Tempio liv. 1 (2.000 BC, 100 BC/giorno) … Abisso Stellare liv. 400 (800.000 BC, 21.000 BC/giorno).
--   * Chi compra un terreno lo tiene PER SEMPRE (nessuno può portarglielo via).
--   * Il prezzo d'acquisto sale del 3% per ogni terreno che possiedi già (game_land_price_step): così nessuno compra tutta la mappa.
--   * 5 miglioramenti: Accampamento → Capanna → Casa → Villa → Castello. Costi: 60%, 100%, 160%, 250%, 400% del prezzo base della regione.
--     Rendita: ×1,6 ×2,4 ×3,4 ×4,6 ×6.
--   * La rendita matura ogni ora e si riscuote con un tocco; si accumula al massimo per 48 ore (game_land_cap_hours): bisogna tornare.
--     Comprando o migliorando, quella maturata viene riscossa da sola.
--   * Classifica: chi possiede più terreni (a parità: più miglioramenti, poi più rendita).
-- LOCANDA (non si compra):
--   * Chi c'è: gli eroi entrati negli ultimi 15 minuti.
--   * Offri un giro (1.000 BC, una volta all'ora): +10 energia a tutti gli eroi presenti, te compreso (ognuno ne riceve al massimo 3 al giorno).
--   * Riposo: una volta al giorno +25 energia (senza superare il massimo).
--   * Tavolo dei dadi: apri un tavolo con una posta (da 100 BC a 200 × il tuo livello, massimo 50.000); un altro eroe accetta con la stessa
--     posta; 2 dadi a testa, vince il più alto (pareggio: si rilancia). Il vincitore prende il piatto meno il 5% della casa (esce dal gioco).
--     Massimo 3 tavoli aperti e 20 partite al giorno a testa; un tavolo non accettato in 24 ore si chiude e la posta torna indietro.
-- Tutti i BC passano dal registro contabile (movimenti game_land_*, game_tavern_round, game_dice_*), con chiave d'idempotenza.
-- Interruttore: game_map_enabled (Admin › Impostazioni). Si può rieseguire. Annullamento: black-market-eroi-mappa-down.sql.
-- Test (solo su un progetto di prova vuoto): black-market-eroi-mappa-test.sql.
-- =====================================================================
begin;

do $$ begin
  if to_regprocedure('public._game_energy_checkpoint(uuid)') is null then
    raise exception 'Prima esegui le migrazioni della Guerra degli Eroi (energia). Non è stato modificato nulla.';
  end if;
end $$;

-- ---------- tipi nuovi nel registro e nelle notifiche ----------
do $$
declare d text; kinds text[]; k text;
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.ledger_entries'::regclass and conname = 'ledger_entries_kind_check';
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  foreach k in array array['game_land_buy','game_land_upgrade','game_land_income','game_tavern_round','game_dice_stake','game_dice_win','game_dice_refund'] loop
    if not (k = any (kinds)) then kinds := kinds || k; end if;
  end loop;
  alter table public.ledger_entries drop constraint ledger_entries_kind_check;
  execute 'alter table public.ledger_entries add constraint ledger_entries_kind_check check (kind in (' || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.notifications'::regclass and conname = 'notifications_kind_check';
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  if not ('tavern_dice' = any (kinds)) then
    kinds := kinds || 'tavern_dice'::text;
    alter table public.notifications drop constraint notifications_kind_check;
    execute 'alter table public.notifications add constraint notifications_kind_check check (kind in (' || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
  end if;
end $$;

insert into public.system_settings (key, value_int, description) values
 ('game_map_enabled',           1,     'Eroi: 1 = Mappa dei terreni e Locanda attive'),
 ('game_land_price_step',       3,     'Mappa: % in più sul prezzo d''acquisto per ogni terreno già posseduto'),
 ('game_land_cap_hours',        48,    'Mappa: ore massime di rendita accumulabile prima di riscuotere'),
 ('game_tavern_round_cost',     1000,  'Locanda: BC per offrire un giro'),
 ('game_tavern_round_energy',   10,    'Locanda: energia data a ogni presente da un giro'),
 ('game_tavern_rest_energy',    25,    'Locanda: energia del riposo (una volta al giorno)'),
 ('game_dice_max_stake',        50000, 'Locanda: posta massima ai dadi'),
 ('game_dice_daily',            20,    'Locanda: partite a dadi al giorno per eroe'),
 ('game_dice_cut',              5,     'Locanda: % del piatto dei dadi che va alla casa (esce dal gioco)')
on conflict (key) do nothing;

-- ---------- regioni e terreni ----------
create table if not exists public.game_map_regions (
  no smallint primary key, name text not null, emoji text not null, color text not null, sprite text not null, tint smallint not null default 0,
  min_level integer not null, price integer not null check (price > 0), income integer not null check (income > 0), lore text not null
);
insert into public.game_map_regions (no, name, emoji, color, sprite, tint, min_level, price, income, lore) values
 (1, 'Prati del Tempio',       '🌾', '#5f8f3a', 'goblin',     0,   1,   2000,   100, 'Erba alta e strade di campagna: qui ogni eroe muove i primi passi.'),
 (2, 'Foresta Sussurrante',    '🌲', '#2f6b45', 'lupo',       1,  25,   5000,   220, 'Gli alberi raccontano i duelli di chi è passato prima.'),
 (3, 'Paludi Nebbiose',        '🐸', '#4d6b5a', 'melma',      2,  50,  12000,   480, 'Nebbia fitta, rane enormi e terreni più fertili di quanto sembri.'),
 (4, 'Deserto delle Carte',    '🏜️', '#b8863b', 'scheletro',  3, 100,  30000,  1100, 'Sotto la sabbia giacciono mazzi dimenticati da secoli.'),
 (5, 'Montagne di Cristallo',  '🏔️', '#6f8fb5', 'golem',      1, 150,  70000,  2400, 'Picchi che brillano al tramonto: ci vivono solo i più tenaci.'),
 (6, 'Costa dei Naufragi',     '🌊', '#2f6f9a', 'kraken',     2, 200, 150000,  4800, 'Relitti, tesori e un mare che non dorme mai.'),
 (7, 'Vulcano Ardente',        '🌋', '#a8452c', 'drago',      3, 300, 350000, 10000, 'La terra trema, ma chi resiste qui diventa leggenda.'),
 (8, 'Abisso Stellare',        '🌌', '#5b3fa0', 'arconte',    4, 400, 800000, 21000, 'Il confine del mondo: oltre ci sono solo le stelle.')
on conflict (no) do update set name = excluded.name, emoji = excluded.emoji, color = excluded.color, sprite = excluded.sprite, tint = excluded.tint,
  min_level = excluded.min_level, price = excluded.price, income = excluded.income, lore = excluded.lore;

create table if not exists public.game_land (
  id smallint primary key,                                 -- y * 20 + x
  x smallint not null check (x between 0 and 19), y smallint not null check (y between 0 and 15),
  region_no smallint not null references public.game_map_regions(no),
  owner_id uuid references public.profiles(id) on delete restrict,
  level smallint not null default 0 check (level between 0 and 5),
  bought_at timestamptz, upgraded_at timestamptz,
  unique (x, y)
);
create index if not exists game_land_owner on public.game_land (owner_id);
insert into public.game_land (id, x, y, region_no)
select gy * 20 + gx, gx, gy, (gy / 8) * 4 + (gx / 5) + 1
  from generate_series(0, 19) gx cross join generate_series(0, 15) gy
 where not (gx between 9 and 10 and gy between 7 and 8)     -- la Locanda
on conflict (id) do nothing;

create table if not exists public.game_land_owners (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  last_claim_at timestamptz not null default now(),
  total_claimed bigint not null default 0
);

-- ---------- locanda ----------
create table if not exists public.game_tavern_presence (user_id uuid primary key references public.profiles(id) on delete restrict, seen_at timestamptz not null default now());
create table if not exists public.game_tavern_rest (user_id uuid not null references public.profiles(id) on delete restrict, day date not null, primary key (user_id, day));
create table if not exists public.game_tavern_rounds (
  id bigserial primary key, user_id uuid not null references public.profiles(id) on delete restrict, recipients integer not null default 0, created_at timestamptz not null default now());
create table if not exists public.game_tavern_round_got (user_id uuid not null references public.profiles(id) on delete restrict, day date not null, n smallint not null default 0, primary key (user_id, day));
create table if not exists public.game_dice (
  id bigserial primary key,
  creator_id uuid not null references public.profiles(id) on delete restrict,
  joiner_id uuid references public.profiles(id) on delete restrict,
  stake integer not null check (stake > 0),
  status text not null default 'open' check (status in ('open', 'done', 'cancelled', 'expired')),
  roll_a smallint[], roll_b smallint[], winner_id uuid references public.profiles(id), pot_paid integer,
  created_at timestamptz not null default now(), done_at timestamptz
);
create index if not exists game_dice_open on public.game_dice (status, created_at);
create table if not exists public.game_tavern_log (
  id bigserial primary key, user_id uuid references public.profiles(id) on delete restrict, kind text not null, text text not null, created_at timestamptz not null default clock_timestamp());

do $$ declare t text; begin
  foreach t in array array['game_map_regions','game_land','game_land_owners','game_tavern_presence','game_tavern_rest','game_tavern_rounds','game_tavern_round_got','game_dice','game_tavern_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
create policy game_map_regions_read on public.game_map_regions for select to authenticated using (true);
create policy game_land_read on public.game_land for select to authenticated using (public._module_on('heroes') or public.is_admin());
grant select on public.game_map_regions, public.game_land to authenticated;

-- ---------- funzioni interne ----------
create or replace function public._land_mult(p_level integer) returns numeric language sql immutable as $$
  select (array[1, 1.6, 2.4, 3.4, 4.6, 6])[p_level + 1] $$;
create or replace function public._land_upcost(p_level integer) returns numeric language sql immutable as $$   -- costo per passare a p_level
  select (array[0.6, 1, 1.6, 2.5, 4])[p_level] $$;
create or replace function public._land_daily(p_user uuid) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(round(r.income * public._land_mult(l.level))), 0)::bigint from public.game_land l join public.game_map_regions r on r.no = l.region_no where l.owner_id = p_user $$;
create or replace function public._land_pending(p_user uuid) returns bigint language sql stable security definer set search_path = public as $$
  select floor(public._land_daily(p_user) * least(greatest(0, extract(epoch from now() - o.last_claim_at)) / 3600.0, coalesce(public._setting('game_land_cap_hours'), 48)) / 24.0)::bigint
    from public.game_land_owners o where o.user_id = p_user $$;
-- riscuote la rendita maturata (0 se non c'è niente); restituisce i BC incassati
create or replace function public._land_collect(p_user uuid) returns integer language plpgsql security definer set search_path = public as $$
declare v_amt bigint;
begin
  insert into public.game_land_owners (user_id) values (p_user) on conflict do nothing;
  perform 1 from public.game_land_owners where user_id = p_user for update;
  v_amt := coalesce(public._land_pending(p_user), 0);
  if v_amt >= 1 then
    perform public._ledger_move(p_user, v_amt::integer, 'game_land_income', 'game_land', null, 'land:' || p_user || ':' || floor(extract(epoch from clock_timestamp()) * 1000), 'Rendita dei terreni');
    update public.game_land_owners set last_claim_at = now(), total_claimed = total_claimed + v_amt where user_id = p_user;
  else
    update public.game_land_owners set last_claim_at = now() where user_id = p_user and v_amt = 0 and public._land_daily(p_user) = 0;
  end if;
  return coalesce(v_amt, 0)::integer;
end $$;
create or replace function public._map_check(p_user uuid) returns public.game_heroes language plpgsql security definer set search_path = public as $$
declare h public.game_heroes%rowtype;
begin
  perform public._require_module('heroes');
  if coalesce(public._setting('game_map_enabled'), 0) <> 1 then raise exception 'La Mappa è chiusa in questo momento'; end if;
  perform public._game_ensure_hero(p_user);
  select * into h from public.game_heroes where user_id = p_user;
  if not h.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  return h;
end $$;
create or replace function public._tavern_energy(p_user uuid, p_amount integer) returns integer language plpgsql security definer set search_path = public as $$
declare v_before numeric; v_after numeric;
begin
  perform public._game_energy_checkpoint(p_user);
  select energy into v_before from public.game_heroes where user_id = p_user for update;
  update public.game_heroes set energy = least(public._game_energy_max(), energy + p_amount), energy_at = now() where user_id = p_user returning energy into v_after;
  return floor(v_after - v_before)::integer;
end $$;
create or replace function public._tavern_log(p_user uuid, p_kind text, p_text text) returns void language sql security definer set search_path = public as $$
  insert into public.game_tavern_log (user_id, kind, text) values (p_user, p_kind, p_text) $$;
-- chiude i tavoli dei dadi rimasti aperti più di 24 ore (posta restituita)
create or replace function public._dice_expire() returns void language plpgsql security definer set search_path = public as $$
declare d record;
begin
  for d in select * from public.game_dice where status = 'open' and created_at < now() - interval '24 hours' for update skip locked loop
    perform public._ledger_move(d.creator_id, d.stake, 'game_dice_refund', 'game_dice', null, 'dice:' || d.id || ':refund', 'Dadi: tavolo scaduto, posta restituita');
    update public.game_dice set status = 'expired', done_at = now() where id = d.id;
  end loop;
end $$;

-- ---------- MAPPA: stato, acquisto, miglioramento, riscossione ----------
create or replace function public.game_map_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); h public.game_heroes%rowtype; n integer;
begin
  perform public._require_module('heroes');
  if coalesce(public._setting('game_map_enabled'), 0) <> 1 then return jsonb_build_object('enabled', false); end if;
  select * into h from public.game_heroes where user_id = v;
  select count(*) into n from public.game_land where owner_id = v;
  return jsonb_build_object('enabled', true, 'w', 20, 'h', 16, 'tavern', jsonb_build_object('x', 9, 'y', 7, 'w', 2, 'h', 2),
    'regions', (select jsonb_agg(jsonb_build_object('no', r.no, 'name', r.name, 'emoji', r.emoji, 'color', r.color, 'sprite', r.sprite, 'tint', r.tint,
                  'min_level', r.min_level, 'price', r.price, 'income', r.income, 'lore', r.lore,
                  'owned', (select count(*) from public.game_land l where l.region_no = r.no and l.owner_id is not null),
                  'total', (select count(*) from public.game_land l where l.region_no = r.no)) order by r.no) from public.game_map_regions r),
    -- terreni in forma compatta: [id, regione, livello, indice del proprietario in "owners" o -1]
    'owners', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'n', p.nickname) order by p.id) from public.profiles p where p.id in (select distinct owner_id from public.game_land where owner_id is not null)), '[]'::jsonb),
    'plots', (select jsonb_agg(jsonb_build_array(l.id, l.region_no, l.level,
                coalesce((select o.i - 1 from (select p.id, row_number() over (order by p.id) as i from public.profiles p where p.id in (select distinct owner_id from public.game_land where owner_id is not null)) o where o.id = l.owner_id), -1)) order by l.id)
              from public.game_land l),
    'me', jsonb_build_object('level', coalesce(h.level, 1), 'plots', n, 'daily', public._land_daily(v), 'pending', coalesce(public._land_pending(v), 0),
            'cap_hours', public._setting('game_land_cap_hours'), 'price_mult', 1 + coalesce(public._setting('game_land_price_step'), 3) * n / 100.0,
            'total_claimed', coalesce((select total_claimed from public.game_land_owners where user_id = v), 0)),
    'mults', jsonb_build_array(1, 1.6, 2.4, 3.4, 4.6, 6), 'upcost', jsonb_build_array(0.6, 1, 1.6, 2.5, 4),
    'top', coalesce((select jsonb_agg(jsonb_build_object('user_id', x.owner_id, 'nickname', p.nickname, 'plots', x.n, 'levels', x.lv, 'daily', x.daily) order by x.n desc, x.lv desc, x.daily desc)
             from (select l.owner_id, count(*) n, sum(l.level) lv, sum(round(r.income * public._land_mult(l.level)))::bigint daily
                     from public.game_land l join public.game_map_regions r on r.no = l.region_no where l.owner_id is not null group by l.owner_id
                    order by count(*) desc, sum(l.level) desc limit 10) x join public.profiles p on p.id = x.owner_id), '[]'::jsonb),
    'my_rank', (select y.rk from (select owner_id, row_number() over (order by count(*) desc, sum(level) desc) rk from public.game_land where owner_id is not null group by owner_id) y where y.owner_id = v),
    'present', (select count(*) from public.game_tavern_presence where seen_at > now() - interval '15 minutes'));
end $$;

create or replace function public.game_land_buy(p_plot integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); h public.game_heroes%rowtype; l public.game_land%rowtype;
  r public.game_map_regions%rowtype; n integer; v_price integer; got integer; v_bal integer;
begin
  h := public._map_check(v);
  select * into l from public.game_land where id = p_plot for update;
  if not found then raise exception 'Terreno inesistente'; end if;
  if l.owner_id is not null then raise exception 'Questo terreno ha già un proprietario'; end if;
  select * into r from public.game_map_regions where no = l.region_no;
  if h.level < r.min_level then raise exception 'La regione % si sblocca al livello %', r.name, r.min_level; end if;
  perform 1 from public.game_land_owners where user_id = v for update;
  select count(*) into n from public.game_land where owner_id = v;
  v_price := ceil(r.price * (1 + coalesce(public._setting('game_land_price_step'), 3) * n / 100.0))::integer;
  got := public._land_collect(v);
  v_bal := public._ledger_move(v, -v_price, 'game_land_buy', 'game_land', null, 'landbuy:' || l.id || ':' || v, 'Mappa: terreno ' || r.name || ' (' || l.x + 1 || ',' || l.y + 1 || ')');
  update public.game_land set owner_id = v, level = 0, bought_at = now(), upgraded_at = null where id = l.id;
  perform public._tavern_log(v, 'land', 'ha comprato un terreno in ' || r.name);
  return jsonb_build_object('ok', true, 'price', v_price, 'collected', got, 'balance', v_bal, 'plots', n + 1);
end $$;

create or replace function public.game_land_upgrade(p_plot integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); h public.game_heroes%rowtype; l public.game_land%rowtype;
  r public.game_map_regions%rowtype; v_cost integer; got integer; v_bal integer;
begin
  h := public._map_check(v);
  select * into l from public.game_land where id = p_plot for update;
  if not found or l.owner_id is distinct from v then raise exception 'Puoi migliorare solo i tuoi terreni'; end if;
  if l.level >= 5 then raise exception 'Questo terreno è già un Castello'; end if;
  select * into r from public.game_map_regions where no = l.region_no;
  v_cost := ceil(r.price * public._land_upcost(l.level + 1))::integer;
  got := public._land_collect(v);
  v_bal := public._ledger_move(v, -v_cost, 'game_land_upgrade', 'game_land', null, 'landup:' || l.id || ':' || (l.level + 1) || ':' || v, 'Mappa: miglioramento in ' || r.name);
  update public.game_land set level = level + 1, upgraded_at = now() where id = l.id;
  if l.level + 1 = 5 then perform public._tavern_log(v, 'land', 'ha costruito un Castello in ' || r.name); end if;
  return jsonb_build_object('ok', true, 'cost', v_cost, 'level', l.level + 1, 'collected', got, 'balance', v_bal);
end $$;

create or replace function public.game_land_collect() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); got integer;
begin
  perform public._map_check(v);
  got := public._land_collect(v);
  return jsonb_build_object('collected', got, 'daily', public._land_daily(v));
end $$;

-- ---------- LOCANDA ----------
create or replace function public.game_tavern_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := (now() at time zone 'Europe/Rome')::date; h public.game_heroes%rowtype;
begin
  h := public._map_check(v);
  insert into public.game_tavern_presence (user_id, seen_at) values (v, now()) on conflict (user_id) do update set seen_at = now();
  perform public._dice_expire();
  return jsonb_build_object(
    'present', coalesce((select jsonb_agg(jsonb_build_object('user_id', t.user_id, 'nickname', p.nickname, 'level', g.level, 'ago', floor(extract(epoch from now() - t.seen_at) / 60)) order by t.seen_at desc)
       from public.game_tavern_presence t join public.profiles p on p.id = t.user_id left join public.game_heroes g on g.user_id = t.user_id
      where t.seen_at > now() - interval '15 minutes'), '[]'::jsonb),
    'rested', exists (select 1 from public.game_tavern_rest where user_id = v and day = d),
    'rest_energy', public._setting('game_tavern_rest_energy'),
    'round_cost', public._setting('game_tavern_round_cost'), 'round_energy', public._setting('game_tavern_round_energy'),
    'round_next', (select max(created_at) + interval '1 hour' from public.game_tavern_rounds where user_id = v and created_at > now() - interval '1 hour'),
    'rounds_got', coalesce((select n from public.game_tavern_round_got where user_id = v and day = d), 0),
    'dice', jsonb_build_object('min', 100, 'max', least(coalesce(public._setting('game_dice_max_stake'), 50000), 200 * h.level), 'cut', public._setting('game_dice_cut'),
       'played_today', (select count(*) from public.game_dice where status = 'done' and (creator_id = v or joiner_id = v) and (done_at at time zone 'Europe/Rome')::date = d),
       'daily', public._setting('game_dice_daily'),
       'open', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'creator_id', g.creator_id, 'nickname', p.nickname, 'stake', g.stake, 'mine', g.creator_id = v, 'at', g.created_at) order by g.created_at desc)
          from public.game_dice g join public.profiles p on p.id = g.creator_id where g.status = 'open'), '[]'::jsonb),
       'recent', coalesce((select jsonb_agg(x order by x->>'at' desc) from (select jsonb_build_object('id', g.id, 'a', pa.nickname, 'b', pb.nickname, 'ra', g.roll_a, 'rb', g.roll_b,
            'winner', pw.nickname, 'stake', g.stake, 'at', g.done_at, 'mine', v in (g.creator_id, g.joiner_id)) as x
          from public.game_dice g join public.profiles pa on pa.id = g.creator_id join public.profiles pb on pb.id = g.joiner_id left join public.profiles pw on pw.id = g.winner_id
          where g.status = 'done' order by g.done_at desc limit 8) q), '[]'::jsonb)),
    'log', coalesce((select jsonb_agg(jsonb_build_object('nickname', p.nickname, 'kind', l.kind, 'text', l.text, 'at', l.created_at) order by l.id desc)
       from (select * from public.game_tavern_log order by id desc limit 8) l left join public.profiles p on p.id = l.user_id), '[]'::jsonb));
end $$;

create or replace function public.game_tavern_rest() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := (now() at time zone 'Europe/Rome')::date; got integer;
begin
  perform public._map_check(v);
  begin
    insert into public.game_tavern_rest (user_id, day) values (v, d);
  exception when unique_violation then raise exception 'Hai già riposato oggi: torna domani';
  end;
  got := public._tavern_energy(v, coalesce(public._setting('game_tavern_rest_energy'), 25));
  return jsonb_build_object('energy', got);
end $$;

create or replace function public.game_tavern_round() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := (now() at time zone 'Europe/Rome')::date;
  v_cost integer := coalesce(public._setting('game_tavern_round_cost'), 1000); v_en integer := coalesce(public._setting('game_tavern_round_energy'), 10);
  r record; v_id bigint; v_n integer := 0; v_nick text;
begin
  perform public._map_check(v);
  perform pg_advisory_xact_lock(hashtext('tavern_round:' || v));
  if exists (select 1 from public.game_tavern_rounds where user_id = v and created_at > now() - interval '1 hour') then raise exception 'Puoi offrire un giro una volta all''ora'; end if;
  insert into public.game_tavern_presence (user_id, seen_at) values (v, now()) on conflict (user_id) do update set seen_at = now();
  insert into public.game_tavern_rounds (user_id) values (v) returning id into v_id;
  perform public._ledger_move(v, -v_cost, 'game_tavern_round', 'game_tavern', null, 'round:' || v_id, 'Locanda: un giro per tutti');
  select nickname into v_nick from public.profiles where id = v;
  for r in select t.user_id from public.game_tavern_presence t join public.profiles p on p.id = t.user_id
            where t.seen_at > now() - interval '15 minutes' and not p.suspended loop
    insert into public.game_tavern_round_got (user_id, day, n) values (r.user_id, d, 0) on conflict do nothing;
    update public.game_tavern_round_got g set n = g.n + 1 where g.user_id = r.user_id and g.day = d and g.n < 3;
    if found then perform public._tavern_energy(r.user_id, v_en); v_n := v_n + 1; end if;
  end loop;
  update public.game_tavern_rounds set recipients = v_n where id = v_id;
  perform public._tavern_log(v, 'round', 'offre un giro a tutta la locanda (+' || v_en || ' energia a ' || v_n || (case when v_n = 1 then ' eroe' else ' eroi' end) || ')');
  return jsonb_build_object('recipients', v_n, 'energy', v_en, 'cost', v_cost);
end $$;

create or replace function public.game_dice_open(p_stake integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); h public.game_heroes%rowtype; v_max integer; v_id bigint;
begin
  h := public._map_check(v);
  v_max := least(coalesce(public._setting('game_dice_max_stake'), 50000), 200 * h.level);
  if p_stake is null or p_stake < 100 or p_stake > v_max then raise exception 'La posta va da 100 a % BC', v_max; end if;
  perform pg_advisory_xact_lock(hashtext('dice:' || v));
  if (select count(*) from public.game_dice where creator_id = v and status = 'open') >= 3 then raise exception 'Hai già 3 tavoli aperti'; end if;
  insert into public.game_dice (creator_id, stake) values (v, p_stake) returning id into v_id;
  perform public._ledger_move(v, -p_stake, 'game_dice_stake', 'game_dice', null, 'dice:' || v_id || ':a', 'Dadi: posta del tavolo');
  return jsonb_build_object('id', v_id, 'stake', p_stake);
end $$;

create or replace function public.game_dice_cancel(p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); g public.game_dice%rowtype;
begin
  perform public._map_check(v);
  select * into g from public.game_dice where id = p_id for update;
  if not found or g.creator_id <> v then raise exception 'Puoi chiudere solo i tuoi tavoli'; end if;
  if g.status <> 'open' then raise exception 'Il tavolo non è più aperto'; end if;
  perform public._ledger_move(v, g.stake, 'game_dice_refund', 'game_dice', null, 'dice:' || g.id || ':refund', 'Dadi: tavolo chiuso, posta restituita');
  update public.game_dice set status = 'cancelled', done_at = now() where id = g.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.game_dice_join(p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := (now() at time zone 'Europe/Rome')::date;
  g public.game_dice%rowtype; a smallint[]; b smallint[]; sa integer; sb integer; tries integer := 0; v_win uuid; v_pot integer; v_cut integer; na text; nb text; lim integer;
begin
  perform public._map_check(v);
  select * into g from public.game_dice where id = p_id for update;
  if not found or g.status <> 'open' then raise exception 'Questo tavolo non è più disponibile'; end if;
  if g.created_at < now() - interval '24 hours' then raise exception 'Questo tavolo è scaduto'; end if;
  if g.creator_id = v then raise exception 'Non puoi giocare contro te stesso'; end if;
  lim := coalesce(public._setting('game_dice_daily'), 20);
  if (select count(*) from public.game_dice where status = 'done' and (creator_id = v or joiner_id = v) and (done_at at time zone 'Europe/Rome')::date = d) >= lim then
    raise exception 'Hai giocato % partite a dadi oggi: torna domani', lim; end if;
  perform public._ledger_move(v, -g.stake, 'game_dice_stake', 'game_dice', null, 'dice:' || g.id || ':b', 'Dadi: posta accettata');
  loop
    tries := tries + 1;
    a := array[1 + floor(random() * 6), 1 + floor(random() * 6)]::smallint[];
    b := array[1 + floor(random() * 6), 1 + floor(random() * 6)]::smallint[];
    sa := a[1] + a[2]; sb := b[1] + b[2];
    exit when sa <> sb or tries >= 10;
  end loop;
  select nickname into na from public.profiles where id = g.creator_id;
  select nickname into nb from public.profiles where id = v;
  if sa = sb then
    perform public._ledger_move(g.creator_id, g.stake, 'game_dice_refund', 'game_dice', null, 'dice:' || g.id || ':refund', 'Dadi: pareggio, posta restituita');
    perform public._ledger_move(v, g.stake, 'game_dice_refund', 'game_dice', null, 'dice:' || g.id || ':refundb', 'Dadi: pareggio, posta restituita');
    v_win := null; v_pot := 0;
  else
    v_win := case when sa > sb then g.creator_id else v end;
    v_cut := floor(2 * g.stake * coalesce(public._setting('game_dice_cut'), 5) / 100.0)::integer;
    v_pot := 2 * g.stake - v_cut;
    perform public._ledger_move(v_win, v_pot, 'game_dice_win', 'game_dice', null, 'dice:' || g.id || ':win', 'Dadi: vinto il piatto');
  end if;
  update public.game_dice set joiner_id = v, roll_a = a, roll_b = b, winner_id = v_win, pot_paid = v_pot, status = 'done', done_at = now() where id = g.id;
  perform public._tavern_log(v_win, 'dice', case when v_win is null then na || ' e ' || nb || ' pareggiano ai dadi' else 'vince ' || v_pot || ' BC ai dadi contro ' || case when v_win = v then na else nb end end);
  perform public._notify(g.creator_id, 'tavern_dice', case when v_win = g.creator_id then 'Hai vinto ai dadi!' when v_win is null then 'Pareggio ai dadi' else 'Hai perso ai dadi' end,
    nb || ' ha accettato il tuo tavolo da ' || g.stake || ' BC: ' || sa || ' contro ' || sb || case when v_win = g.creator_id then '. Vinci ' || v_pot || ' BC.' else '.' end,
    'eroi.html#map', 'game_dice', null);
  return jsonb_build_object('a', a, 'b', b, 'sum_a', sa, 'sum_b', sb, 'won', v_win = v, 'draw', v_win is null, 'pot', v_pot, 'stake', g.stake, 'opponent', na);
end $$;

-- ---------- permessi ----------
do $$ declare f text; begin
  foreach f in array array['_land_mult(integer)','_land_upcost(integer)','_land_daily(uuid)','_land_pending(uuid)','_land_collect(uuid)','_map_check(uuid)',
    '_tavern_energy(uuid,integer)','_tavern_log(uuid,text,text)','_dice_expire()','game_map_state()','game_land_buy(integer)','game_land_upgrade(integer)',
    'game_land_collect()','game_tavern_state()','game_tavern_rest()','game_tavern_round()','game_dice_open(integer)','game_dice_cancel(bigint)','game_dice_join(bigint)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon, authenticated';
  end loop;
  foreach f in array array['game_map_state()','game_land_buy(integer)','game_land_upgrade(integer)','game_land_collect()','game_tavern_state()','game_tavern_rest()',
    'game_tavern_round()','game_dice_open(integer)','game_dice_cancel(bigint)','game_dice_join(bigint)'] loop
    execute 'grant execute on function public.' || f || ' to authenticated';
  end loop;
end $$;

commit;
