-- =====================================================================
-- MIGRAZIONE 042 — LA GUERRA DEGLI EROI: I VILLAGGI (sindaci, risorse, soldati, invasioni)
-- Da eseguire in Supabase (SQL Editor) DOPO tutte le migrazioni precedenti (ultima: 041, Mappa dei terreni e Locanda).
--
-- VILLAGGI: OGNI terreno della Mappa può diventare un villaggio; chi possiede il terreno ne è il sindaco.
--   Il primo costa 10.000 BC (game_village_found_cost), ogni villaggio in più costa il 100% in più del base (game_village_found_step):
--   20.000 il secondo, 30.000 il terzo… Ogni villaggio è indipendente: edifici, risorse, cassa, esercito e guarnigione suoi.
--   Il villaggio compare sulla mappa con case, torre e nome al posto dell'edificio del terreno (la rendita del terreno continua).
--   Un villaggio appena fondato ha una tregua di 48 ore: nessuno può attaccarlo (game_village_shield_hours).
-- RISORSE: legno, pietra, cibo. Le producono Segheria, Cava e Fattoria (30 × livello × 1,2^(livello−1) all'ora).
--   Il Magazzino decide quanto se ne può tenere (1.000 × 1,5^livello per risorsa). Il 20% della capienza è nascosto: non si può saccheggiare.
--   Il cibo mantiene l'esercito: ogni fante e arciere mangia 1 cibo all'ora, ogni cavaliere 2 (anche quando sono in marcia).
--   Se il cibo finisce l'esercito è affamato e combatte a metà forza.
-- CASSA: il Municipio fa maturare BC nella cassa del villaggio (200 × livello × 1,25^(livello−1) al giorno, fino a 48 ore).
--   Il sindaco li versa nel portafoglio con «Riscuoti». I BC della cassa (non quelli del portafoglio) si possono saccheggiare.
-- EDIFICI (7, livello massimo 10; nessuno può superare il Municipio): Municipio, Segheria, Cava, Fattoria, Magazzino, Caserma, Mura.
--   Si costruiscono subito, pagando legno e pietra (Municipio, Caserma e Mura anche BC). Il costo cresce di ×1,65 a ogni livello.
-- SOLDATI (si pagano in BC più un po' di cibo, si addestrano subito):
--   🗡️ Fante 60 BC + 30 cibo — attacco 10, difesa 14, trasporta 25, 10 px/min — dalla Caserma 1
--   🏹 Arciere 90 BC + 40 cibo — attacco 14, difesa 10, trasporta 15, 10 px/min — dalla Caserma 3
--   🐎 Cavaliere 160 BC + 60 cibo — attacco 22, difesa 12, trasporta 50, 20 px/min — dalla Caserma 5
--   Sasso-carta-forbice: i fanti battono i cavalieri, i cavalieri battono gli arcieri, gli arcieri battono i fanti (×1,5 / ×0,75).
--   La Caserma limita l'esercito: 25 × L × (L+1) / 2 soldati in tutto (25 … 1.375).
-- DIFESA: il sindaco sceglie quanti soldati restano a difendere (la guarnigione); solo quelli che non difendono possono partire.
--   Oltre alla guarnigione difende sempre una milizia di 5 fanti per livello di Municipio, che non muore mai. Le Mura danno +10% per livello.
-- INVASIONI: l'esercito marcia verso il villaggio scelto (tempo in base alla distanza sulla mappa e al soldato più lento, minimo 5 minuti).
--   Il difensore riceve subito una notifica con l'ora d'arrivo (ma non sa quanti sono). All'arrivo la battaglia si decide da sola:
--   * vince chi ha più forza (con ±10% di fortuna); chi vince perde (forza nemica / forza propria)^1,5 dei soldati, chi perde il 70%.
--   * se vince l'attaccante, i sopravvissuti portano via risorse (oltre la parte nascosta) e fino al 25% della cassa, nei limiti di quanto possono
--     trasportare; il villaggio sconfitto ha 8 ore di tregua. Il bottino arriva quando l'esercito torna a casa (stesso tempo dell'andata).
--   * ogni villaggio parte da sé: massimo 5 attacchi al giorno PER VILLAGGIO; non si attaccano villaggi con il Municipio più basso
--     di 3 livelli di quello che attacca (protezione dei nuovi); non si attaccano i propri villaggi; attaccare toglie la tregua a chi parte.
-- Tutti i BC passano dal registro contabile (movimenti game_village_*), con chiave d'idempotenza.
-- Se avevi già eseguito una versione precedente di questa migrazione, rieseguila: i villaggi esistenti restano com'erano
-- (13 novembre 2026: lo stato include anche gli eserciti in marcia, per vederli muoversi sulla mappa).
-- Interruttore: game_village_enabled (Admin › Impostazioni). Si può rieseguire. Annullamento: black-market-eroi-villaggi-down.sql.
-- Test (solo su un progetto di prova vuoto): black-market-eroi-villaggi-test.sql.
-- =====================================================================
begin;

do $$ begin
  if to_regprocedure('public._map_check(uuid)') is null then
    raise exception 'Prima esegui la migrazione 041 (black-market-eroi-mappa.sql). Non è stato modificato nulla.';
  end if;
end $$;

-- ---------- tipi nuovi nel registro e nelle notifiche ----------
do $$
declare d text; kinds text[]; k text;
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.ledger_entries'::regclass and conname = 'ledger_entries_kind_check';
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  foreach k in array array['game_village_found','game_village_build','game_village_train','game_village_collect'] loop
    if not (k = any (kinds)) then kinds := kinds || k; end if;
  end loop;
  alter table public.ledger_entries drop constraint ledger_entries_kind_check;
  execute 'alter table public.ledger_entries add constraint ledger_entries_kind_check check (kind in (' || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.notifications'::regclass and conname = 'notifications_kind_check';
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  if not ('village' = any (kinds)) then
    kinds := kinds || 'village'::text;
    alter table public.notifications drop constraint notifications_kind_check;
    execute 'alter table public.notifications add constraint notifications_kind_check check (kind in (' || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
  end if;
end $$;

insert into public.system_settings (key, value_int, description) values
 ('game_village_enabled',         1,     'Eroi: 1 = Villaggi e invasioni attivi'),
 ('game_village_found_cost',      10000, 'Villaggi: BC per fondare il primo villaggio'),
 ('game_village_found_step',      100,   'Villaggi: % del costo base in più per ogni villaggio già posseduto'),
 ('game_village_shield_hours',    48,    'Villaggi: ore di tregua per un villaggio appena fondato'),
 ('game_village_defeat_shield',   8,     'Villaggi: ore di tregua dopo aver perso una difesa'),
 ('game_village_attacks_daily',   5,     'Villaggi: attacchi al giorno per villaggio'),
 ('game_village_loot_bc_pct',     25,    'Villaggi: % massima della cassa che si può saccheggiare'),
 ('game_village_hidden_pct',      20,    'Villaggi: % della capienza del magazzino nascosta ai saccheggi'),
 ('game_village_hall_gap',        3,     'Villaggi: non si attaccano Municipi più bassi di questi livelli rispetto al proprio')
on conflict (key) do nothing;

-- ---------- tabelle (un villaggio per terreno) ----------
-- toglie le funzioni della prima versione (un villaggio a testa), che avevano altri parametri
drop function if exists public.game_village_state();
drop function if exists public.game_village_rename(text);
drop function if exists public.game_village_build(text);
drop function if exists public.game_village_train(integer, integer, integer);
drop function if exists public.game_village_defense(integer, integer, integer);
drop function if exists public.game_village_attack(uuid, integer, integer, integer);
drop function if exists public.game_village_collect();
drop function if exists public._vil_sync(uuid);
drop function if exists public._vil_away(uuid);
drop function if exists public._vil_upkeep(uuid);

create table if not exists public.game_villages (
  plot_id smallint primary key references public.game_land(id),
  user_id uuid not null references public.profiles(id) on delete restrict,
  name text not null check (char_length(name) between 3 and 24),
  founded_at timestamptz not null default now(),
  hall smallint not null default 1, lumber smallint not null default 1, quarry smallint not null default 1, farm smallint not null default 1,
  warehouse smallint not null default 1, barracks smallint not null default 1, wall smallint not null default 0,
  wood numeric not null default 600, stone numeric not null default 600, food numeric not null default 600, vault numeric not null default 0,
  res_at timestamptz not null default now(),
  inf integer not null default 0 check (inf >= 0), arc integer not null default 0 check (arc >= 0), cav integer not null default 0 check (cav >= 0),
  def_inf integer not null default 0 check (def_inf >= 0), def_arc integer not null default 0 check (def_arc >= 0), def_cav integer not null default 0 check (def_cav >= 0),
  shield_until timestamptz,
  att_won integer not null default 0, att_lost integer not null default 0, def_won integer not null default 0, def_lost integer not null default 0,
  loot_bc bigint not null default 0, collected bigint not null default 0,
  check (def_inf <= inf and def_arc <= arc and def_cav <= cav)
);
-- prima versione: la chiave era il sindaco → ora è il terreno
do $$ begin
  if exists (select 1 from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
              where c.conrelid = 'public.game_villages'::regclass and c.contype = 'p' and a.attname = 'user_id') then
    alter table public.game_villages drop constraint game_villages_pkey;
    alter table public.game_villages add primary key (plot_id);
    alter table public.game_villages drop constraint if exists game_villages_plot_id_key;
  end if;
end $$;
create index if not exists game_villages_user on public.game_villages (user_id);
create unique index if not exists game_villages_name on public.game_villages (lower(name));

create table if not exists public.game_village_marches (
  id bigserial primary key,
  attacker_id uuid not null references public.profiles(id) on delete restrict,
  defender_id uuid not null references public.profiles(id) on delete restrict,
  inf integer not null default 0, arc integer not null default 0, cav integer not null default 0,
  status text not null default 'going' check (status in ('going', 'returning', 'done')),
  depart_at timestamptz not null default now(), arrive_at timestamptz not null, return_at timestamptz,
  won boolean, back_inf integer, back_arc integer, back_cav integer,
  loot_wood integer not null default 0, loot_stone integer not null default 0, loot_food integer not null default 0, loot_bc integer not null default 0,
  report jsonb
);
alter table public.game_village_marches add column if not exists attacker_plot smallint references public.game_land(id);
alter table public.game_village_marches add column if not exists defender_plot smallint references public.game_land(id);
update public.game_village_marches m set attacker_plot = v.plot_id from public.game_villages v where m.attacker_plot is null and v.user_id = m.attacker_id;
update public.game_village_marches m set defender_plot = v.plot_id from public.game_villages v where m.defender_plot is null and v.user_id = m.defender_id;
create index if not exists game_village_marches_due on public.game_village_marches (status, arrive_at);
create index if not exists game_village_marches_att on public.game_village_marches (attacker_plot, depart_at desc);
create index if not exists game_village_marches_def on public.game_village_marches (defender_plot, depart_at desc);
create index if not exists game_village_marches_attu on public.game_village_marches (attacker_id, depart_at desc);
create index if not exists game_village_marches_defu on public.game_village_marches (defender_id, depart_at desc);

do $$ declare t text; begin
  foreach t in array array['game_villages','game_village_marches'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- ---------- regole del gioco (in un posto solo) ----------
create or replace function public._vil_max_level() returns integer language sql immutable as $$ select 10 $$;
create or replace function public._vil_prod(p_level integer) returns numeric language sql immutable as $$            -- risorse all'ora
  select case when p_level <= 0 then 0 else round(30 * p_level * power(1.2, p_level - 1)) end $$;
create or replace function public._vil_cap(p_level integer) returns numeric language sql immutable as $$             -- capienza per risorsa
  select round(1000 * power(1.5, p_level)) $$;
create or replace function public._vil_bc_day(p_level integer) returns numeric language sql immutable as $$          -- BC al giorno nella cassa
  select round(200 * p_level * power(1.25, p_level - 1)) $$;
create or replace function public._vil_army_cap(p_level integer) returns integer language sql immutable as $$
  select 25 * p_level * (p_level + 1) / 2 $$;
-- costo per portare un edificio a p_level: {legno, pietra, bc}
create or replace function public._vil_cost(p_b text, p_level integer) returns integer[] language sql immutable as $$
  select array[ceil(b[1] * f), ceil(b[2] * f), ceil(b[3] * f)]::integer[]
    from (select power(1.65, p_level - 1) f,
                 case p_b when 'hall' then array[300, 300, 3000] when 'lumber' then array[100, 150, 0] when 'quarry' then array[150, 100, 0]
                          when 'farm' then array[120, 120, 0] when 'warehouse' then array[150, 150, 0] when 'barracks' then array[200, 250, 1000]
                          when 'wall' then array[150, 400, 1000] end b) x $$;
-- soldati: {bc, cibo, attacco, difesa, trasporto, velocità px/min, mantenimento/ora, caserma richiesta}
create or replace function public._vil_unit(p_t text) returns integer[] language sql immutable as $$
  select case p_t when 'inf' then array[60, 30, 10, 14, 25, 10, 1, 1] when 'arc' then array[90, 40, 14, 10, 15, 10, 1, 3]
                  when 'cav' then array[160, 60, 22, 12, 50, 20, 2, 5] end $$;
-- posizione sulla mappa illustrata (centro della regione + posto del terreno nella sua zona), per le distanze
create or replace function public._vil_pos(p_plot integer) returns numeric[] language sql stable security definer set search_path = public as $$
  select array[(case l.region_no when 1 then 450 when 2 then 215 when 3 then 190 when 4 then 255 when 5 then 480 when 6 then 715 when 7 then 715 else 665 end) + ((l.x % 5) - 2) * 30,
               (case l.region_no when 1 then 1000 when 2 then 900 when 3 then 590 when 4 then 300 when 5 then 215 when 6 then 380 when 7 then 730 else 1075 end) + ((l.y % 8) - 3.5) * 22]::numeric[]
    from public.game_land l where l.id = p_plot $$;
create or replace function public._vil_minutes(p_from integer, p_to integer, p_cav_only boolean) returns integer language sql stable security definer set search_path = public as $$
  select greatest(5, ceil(sqrt(power(a[1] - b[1], 2) + power(a[2] - b[2], 2)) / case when p_cav_only then 20 else 10 end))::integer
    from (select public._vil_pos(p_from) a, public._vil_pos(p_to) b) x $$;

-- soldati di un villaggio in marcia (mangiano anche loro)
create or replace function public._vil_away(p_plot integer) returns integer[] language sql stable security definer set search_path = public as $$
  select array[coalesce(sum(case when status = 'going' then inf else back_inf end), 0), coalesce(sum(case when status = 'going' then arc else back_arc end), 0),
               coalesce(sum(case when status = 'going' then cav else back_cav end), 0)]::integer[]
    from public.game_village_marches where attacker_plot = p_plot and status <> 'done' $$;
create or replace function public._vil_upkeep(p_plot integer) returns integer language sql stable security definer set search_path = public as $$
  select (v.inf + v.arc + 2 * v.cav + a[1] + a[2] + 2 * a[3])::integer from public.game_villages v, lateral (select public._vil_away(p_plot) a) x where v.plot_id = p_plot $$;

-- aggiorna risorse e cassa di un villaggio fino ad adesso (lo blocca)
create or replace function public._vil_sync(p_plot integer) returns public.game_villages language plpgsql security definer set search_path = public as $$
declare v public.game_villages%rowtype; hrs numeric; cap numeric; vcap numeric; up integer;
begin
  select * into v from public.game_villages where plot_id = p_plot for update;
  if not found then return v; end if;
  hrs := greatest(0, extract(epoch from now() - v.res_at) / 3600.0);
  if hrs > 0 then
    cap := public._vil_cap(v.warehouse); up := public._vil_upkeep(p_plot);
    vcap := public._vil_bc_day(v.hall) * 2;
    update public.game_villages set
      wood  = greatest(wood,  least(cap, wood  + public._vil_prod(lumber) * hrs)),
      stone = greatest(stone, least(cap, stone + public._vil_prod(quarry) * hrs)),
      food  = case when public._vil_prod(farm) >= up then greatest(food, least(cap, food + (public._vil_prod(farm) - up) * hrs))
                   else greatest(0, food + (public._vil_prod(farm) - up) * hrs) end,
      vault = case when vault >= vcap then vault else least(vcap, vault + public._vil_bc_day(hall) * hrs / 24.0) end,
      res_at = now()
     where plot_id = p_plot returning * into v;
  end if;
  return v;
end $$;

create or replace function public._vil_check(p_user uuid) returns public.game_heroes language plpgsql security definer set search_path = public as $$
declare h public.game_heroes%rowtype;
begin
  h := public._map_check(p_user);
  if coalesce(public._setting('game_village_enabled'), 0) <> 1 then raise exception 'I Villaggi sono chiusi in questo momento'; end if;
  return h;
end $$;
-- il villaggio del sindaco (aggiornato e bloccato), o errore
create or replace function public._vil_mine(p_user uuid, p_plot integer) returns public.game_villages language plpgsql security definer set search_path = public as $$
declare v public.game_villages%rowtype;
begin
  perform public._vil_tick();
  v := public._vil_sync(p_plot);
  if v.plot_id is null or v.user_id <> p_user then raise exception 'Questo non è un tuo villaggio'; end if;
  return v;
end $$;

-- forza di un esercito contro un altro (con i vantaggi sasso-carta-forbice)
create or replace function public._vil_power(a integer[], b integer[], p_attack boolean) returns numeric language plpgsql immutable as $$
declare t text[] := array['inf','arc','cav']; i integer; j integer; nb numeric := b[1] + b[2] + b[3]; s numeric := 0; f numeric; u integer[];
begin
  for i in 1..3 loop
    if a[i] <= 0 then continue; end if;
    u := public._vil_unit(t[i]);
    f := 0;
    if nb <= 0 then f := 1;
    else
      for j in 1..3 loop
        f := f + b[j] / nb * case when (i = 1 and j = 3) or (i = 3 and j = 2) or (i = 2 and j = 1) then 1.5
                                  when (j = 1 and i = 3) or (j = 3 and i = 2) or (j = 2 and i = 1) then 0.75 else 1 end;
      end loop;
    end if;
    s := s + a[i] * (case when p_attack then u[3] else u[4] end) * f;
  end loop;
  return s;
end $$;

-- risolve le battaglie arrivate e i ritorni a casa (chiamata da tutte le funzioni dei villaggi)
create or replace function public._vil_tick() returns void language plpgsql security definer set search_path = public as $$
declare m record; d public.game_villages%rowtype; a public.game_villages%rowtype; atk integer[]; def integer[]; mil integer;
  ap numeric; dp numeric; v_won boolean; la numeric; ld numeric; back integer[]; dlost integer[]; carry numeric; hidden numeric; avail numeric[]; tot numeric;
  take numeric; lw integer; ls integer; lf integer; lb integer; na text; nd text; mins integer; luck numeric; starvA boolean; starvD boolean;
begin
  for m in select * from public.game_village_marches where status = 'going' and arrive_at <= now() order by arrive_at for update skip locked loop
    a := public._vil_sync(m.attacker_plot); d := public._vil_sync(m.defender_plot);
    select nickname into na from public.profiles where id = m.attacker_id;
    select nickname into nd from public.profiles where id = m.defender_id;
    atk := array[m.inf, m.arc, m.cav];
    lw := 0; ls := 0; lf := 0; lb := 0; starvA := false; starvD := false;
    if d.plot_id is null or d.user_id <> m.defender_id then      -- il villaggio non c'è più: si torna a casa
      v_won := false; back := atk; dlost := array[0,0,0]; def := array[0,0,0]; ap := 0; dp := 0; mil := 0;
    else
      mil := 5 * d.hall;
      def := array[d.def_inf + mil, d.def_arc, d.def_cav];
      starvA := a.plot_id is not null and a.food <= 0 and public._vil_prod(a.farm) < public._vil_upkeep(m.attacker_plot);
      starvD := d.food <= 0 and public._vil_prod(d.farm) < public._vil_upkeep(m.defender_plot);
      luck := 0.9 + random() * 0.2;
      ap := public._vil_power(atk, def, true) * luck * case when starvA then 0.5 else 1 end;
      dp := public._vil_power(def, atk, false) * (1 + 0.1 * d.wall) * case when starvD then 0.5 else 1 end;
      v_won := ap > dp;
      if v_won then la := case when ap > 0 then power(dp / ap, 1.5) else 1 end; ld := 0.7;
      else la := 0.7; ld := case when dp > 0 then power(ap / dp, 1.5) else 0 end; end if;
      back := array[m.inf - ceil(m.inf * la), m.arc - ceil(m.arc * la), m.cav - ceil(m.cav * la)]::integer[];
      dlost := array[ceil(d.def_inf * ld), ceil(d.def_arc * ld), ceil(d.def_cav * ld)]::integer[];
      update public.game_villages set inf = inf - dlost[1], arc = arc - dlost[2], cav = cav - dlost[3],
             def_inf = def_inf - dlost[1], def_arc = def_arc - dlost[2], def_cav = def_cav - dlost[3],
             def_won = def_won + case when v_won then 0 else 1 end, def_lost = def_lost + case when v_won then 1 else 0 end,
             shield_until = case when v_won then greatest(coalesce(shield_until, now()), now() + make_interval(hours => coalesce(public._setting('game_village_defeat_shield'), 8))) else shield_until end
       where plot_id = d.plot_id returning * into d;
      if v_won then
        carry := back[1] * 25 + back[2] * 15 + back[3] * 50;
        hidden := public._vil_cap(d.warehouse) * coalesce(public._setting('game_village_hidden_pct'), 20) / 100.0;
        avail := array[greatest(0, d.wood - hidden), greatest(0, d.stone - hidden), greatest(0, d.food - hidden),
                       floor(d.vault * coalesce(public._setting('game_village_loot_bc_pct'), 25) / 100.0)];
        tot := avail[1] + avail[2] + avail[3] + avail[4];
        if tot > 0 and carry > 0 then
          take := least(1, carry / tot);
          lw := floor(avail[1] * take); ls := floor(avail[2] * take); lf := floor(avail[3] * take); lb := floor(avail[4] * take);
          update public.game_villages set wood = wood - lw, stone = stone - ls, food = food - lf, vault = vault - lb where plot_id = d.plot_id;
        end if;
      end if;
      update public.game_villages set att_won = att_won + case when v_won then 1 else 0 end, att_lost = att_lost + case when v_won then 0 else 1 end
       where plot_id = m.attacker_plot;
    end if;
    mins := greatest(1, ceil(extract(epoch from m.arrive_at - m.depart_at) / 60.0))::integer;
    update public.game_village_marches set status = 'returning', won = v_won, back_inf = back[1], back_arc = back[2], back_cav = back[3],
           return_at = m.arrive_at + make_interval(mins => mins), loot_wood = lw, loot_stone = ls, loot_food = lf, loot_bc = lb,
           report = jsonb_build_object('atk', atk, 'def', def, 'militia', mil, 'wall', coalesce(d.wall, 0), 'ap', round(ap), 'dp', round(dp),
                    'back', back, 'def_lost', dlost, 'att_lost', array[m.inf - back[1], m.arc - back[2], m.cav - back[3]],
                    'att_name', na, 'def_name', nd, 'att_village', a.name, 'def_village', d.name, 'starv_att', starvA, 'starv_def', starvD)
     where id = m.id;
    if d.plot_id is not null and d.user_id = m.defender_id then
      perform public._notify(m.attacker_id, 'village', case when v_won then '⚔️ Vittoria contro ' || d.name else '⚔️ Sconfitta contro ' || d.name end,
        case when v_won then 'L''esercito di ' || coalesce(a.name, 'tuo') || ' torna con ' || lw || ' legno, ' || ls || ' pietra, ' || lf || ' cibo e ' || lb || ' BC.'
             else 'L''esercito di ' || coalesce(a.name, 'tuo') || ' è stato respinto: tornano ' || (back[1] + back[2] + back[3]) || ' soldati.' end, 'eroi.html#map', 'game_village', null);
      perform public._notify(m.defender_id, 'village', case when v_won then '🔥 ' || na || ' ha saccheggiato ' || d.name else '🛡️ ' || d.name || ' ha respinto ' || na end,
        case when v_won then 'Hai perso ' || lw || ' legno, ' || ls || ' pietra, ' || lf || ' cibo e ' || lb || ' BC. Il villaggio ha 8 ore di tregua.'
             else 'La guarnigione ha tenuto: ' || (dlost[1] + dlost[2] + dlost[3]) || ' caduti fra i tuoi difensori.' end, 'eroi.html#map', 'game_village', null);
      perform public._tavern_log(case when v_won then m.attacker_id else m.defender_id end, 'village',
        case when v_won then 'ha saccheggiato il villaggio ' || d.name || ' di ' || nd else 'ha respinto l''attacco di ' || na || ' a ' || d.name end);
    end if;
  end loop;
  -- eserciti tornati a casa: soldati e bottino
  for m in select * from public.game_village_marches where status = 'returning' and return_at <= now() order by return_at for update skip locked loop
    a := public._vil_sync(m.attacker_plot);
    if a.plot_id is not null and a.user_id = m.attacker_id then
      update public.game_villages set inf = inf + m.back_inf, arc = arc + m.back_arc, cav = cav + m.back_cav,
             wood = least(greatest(wood, public._vil_cap(warehouse)), wood + m.loot_wood), stone = least(greatest(stone, public._vil_cap(warehouse)), stone + m.loot_stone),
             food = least(greatest(food, public._vil_cap(warehouse)), food + m.loot_food), vault = vault + m.loot_bc, loot_bc = loot_bc + m.loot_bc
       where plot_id = m.attacker_plot;
    end if;
    update public.game_village_marches set status = 'done' where id = m.id;
  end loop;
end $$;

create or replace function public._vil_found_cost(p_user uuid) returns integer language sql stable security definer set search_path = public as $$
  select ceil(coalesce(public._setting('game_village_found_cost'), 10000) * (1 + coalesce(public._setting('game_village_found_step'), 100) / 100.0
              * (select count(*) from public.game_villages where user_id = p_user)))::integer $$;

-- ---------- STATO (p_plot = il villaggio da mostrare; null = il primo) ----------
create or replace function public.game_village_state(p_plot integer default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); me public.game_villages%rowtype; h public.game_heroes%rowtype;
  d date := (now() at time zone 'Europe/Rome')::date; away integer[]; b text; blds jsonb := '[]'::jsonb; gap integer := coalesce(public._setting('game_village_hall_gap'), 3);
  cur integer;
begin
  perform public._require_module('heroes');
  if coalesce(public._setting('game_map_enabled'), 0) <> 1 or coalesce(public._setting('game_village_enabled'), 0) <> 1 then return jsonb_build_object('enabled', false); end if;
  perform public._vil_tick();
  -- aggiorna tutti i miei villaggi
  perform public._vil_sync(x.plot_id) from public.game_villages x where x.user_id = v;
  select plot_id into cur from public.game_villages where user_id = v and plot_id = p_plot;
  if cur is null then select plot_id into cur from public.game_villages where user_id = v order by founded_at, plot_id limit 1; end if;
  if cur is not null then select * into me from public.game_villages where plot_id = cur; end if;
  select * into h from public.game_heroes where user_id = v;
  if me.plot_id is not null then
    away := public._vil_away(me.plot_id);
    foreach b in array array['hall','lumber','quarry','farm','warehouse','barracks','wall'] loop
      blds := blds || jsonb_build_object('k', b, 'level', (to_jsonb(me)->>b)::int,
        'next', case when (to_jsonb(me)->>b)::int < public._vil_max_level() then to_jsonb(public._vil_cost(b, (to_jsonb(me)->>b)::int + 1)) else null end);
    end loop;
  end if;
  return jsonb_build_object('enabled', true, 'now', now(),
    'rules', jsonb_build_object('found_cost', public._vil_found_cost(v), 'max_level', public._vil_max_level(),
      'attacks_daily', public._setting('game_village_attacks_daily'), 'hall_gap', gap, 'hidden_pct', public._setting('game_village_hidden_pct'),
      'loot_bc_pct', public._setting('game_village_loot_bc_pct'),
      'units', jsonb_build_object('inf', to_jsonb(public._vil_unit('inf')), 'arc', to_jsonb(public._vil_unit('arc')), 'cav', to_jsonb(public._vil_unit('cav')))),
    -- i miei villaggi in breve (per passare dall'uno all'altro)
    'mine', coalesce((select jsonb_agg(jsonb_build_object('plot', x.plot_id, 'name', x.name, 'hall', x.hall, 'region', l.region_no, 'vault', floor(x.vault),
                  'army', x.inf + x.arc + x.cav, 'shield', x.shield_until > now(),
                  'incoming', (select count(*) from public.game_village_marches m where m.defender_plot = x.plot_id and m.status = 'going')) order by x.founded_at, x.plot_id)
                from public.game_villages x join public.game_land l on l.id = x.plot_id where x.user_id = v), '[]'::jsonb),
    'me', case when me.plot_id is null then null else jsonb_build_object(
      'name', me.name, 'plot', me.plot_id, 'founded_at', me.founded_at,
      'hall', me.hall, 'lumber', me.lumber, 'quarry', me.quarry, 'farm', me.farm, 'warehouse', me.warehouse, 'barracks', me.barracks, 'wall', me.wall,
      'wood', floor(me.wood), 'stone', floor(me.stone), 'food', floor(me.food), 'vault', floor(me.vault),
      'cap', public._vil_cap(me.warehouse), 'hidden', floor(public._vil_cap(me.warehouse) * coalesce(public._setting('game_village_hidden_pct'), 20) / 100.0),
      'prod', jsonb_build_array(public._vil_prod(me.lumber), public._vil_prod(me.quarry), public._vil_prod(me.farm)),
      'upkeep', public._vil_upkeep(me.plot_id), 'bc_day', public._vil_bc_day(me.hall), 'vault_cap', public._vil_bc_day(me.hall) * 2,
      'army', jsonb_build_array(me.inf, me.arc, me.cav), 'def', jsonb_build_array(me.def_inf, me.def_arc, me.def_cav), 'away', to_jsonb(away),
      'army_cap', public._vil_army_cap(me.barracks), 'militia', 5 * me.hall,
      'shield_until', case when me.shield_until > now() then me.shield_until end,
      'stats', jsonb_build_object('att_won', me.att_won, 'att_lost', me.att_lost, 'def_won', me.def_won, 'def_lost', me.def_lost, 'loot_bc', me.loot_bc, 'collected', me.collected),
      'attacks_today', (select count(*) from public.game_village_marches where attacker_plot = me.plot_id and (depart_at at time zone 'Europe/Rome')::date = d),
      'buildings', blds) end,
    'my_plots', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'region', l.region_no, 'level', l.level) order by l.region_no, l.id)
                  from public.game_land l where l.owner_id = v and not exists (select 1 from public.game_villages x where x.plot_id = l.id)), '[]'::jsonb),
    -- tutti i villaggi (per la mappa e per scegliere chi attaccare; tempi di marcia dal villaggio mostrato)
    'villages', coalesce((select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'nickname', p.nickname, 'name', x.name, 'plot', x.plot_id, 'hall', x.hall, 'wall', x.wall,
                  'shield_until', case when x.shield_until > now() then x.shield_until end, 'won', x.att_won + x.def_won,
                  'min', case when me.plot_id is not null and x.user_id <> v then public._vil_minutes(me.plot_id, x.plot_id, false) end,
                  'min_cav', case when me.plot_id is not null and x.user_id <> v then public._vil_minutes(me.plot_id, x.plot_id, true) end,
                  'too_small', me.plot_id is not null and x.hall < me.hall - gap)
                order by case when me.plot_id is not null and x.user_id <> v then public._vil_minutes(me.plot_id, x.plot_id, false) else 0 end, x.name)
                from public.game_villages x join public.profiles p on p.id = x.user_id), '[]'::jsonb),
    'marches', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'out', m.attacker_id = v, 'status', m.status,
                  'other', case when m.attacker_id = v then pd.nickname else pa.nickname end,
                  'from', va.name, 'from_plot', m.attacker_plot, 'to', vd.name, 'to_plot', m.defender_plot,
                  'army', case when m.attacker_id = v then jsonb_build_array(m.inf, m.arc, m.cav) end,
                  'back', case when m.attacker_id = v and m.status = 'returning' then jsonb_build_array(m.back_inf, m.back_arc, m.back_cav) end,
                  'won', m.won, 'arrive_at', m.arrive_at, 'return_at', m.return_at,
                  'loot', case when m.attacker_id = v and m.status = 'returning' then jsonb_build_array(m.loot_wood, m.loot_stone, m.loot_food, m.loot_bc) end)
                order by case when m.status = 'going' then m.arrive_at else m.return_at end)
                from public.game_village_marches m join public.profiles pa on pa.id = m.attacker_id join public.profiles pd on pd.id = m.defender_id
                left join public.game_villages va on va.plot_id = m.attacker_plot left join public.game_villages vd on vd.plot_id = m.defender_plot
               where (m.attacker_id = v and m.status <> 'done') or (m.defender_id = v and m.status = 'going')), '[]'::jsonb),
    -- tutti gli eserciti in marcia sull'isola (per vederli muoversi sulla mappa; senza dire quanti sono)
    'armies', coalesce((select jsonb_agg(jsonb_build_object('attacker_id', m.attacker_id, 'from_plot', m.attacker_plot, 'to_plot', m.defender_plot, 'status', m.status,
                  'depart_at', m.depart_at, 'arrive_at', m.arrive_at, 'return_at', m.return_at, 'inc', m.defender_id = v and m.status = 'going'))
                from (select * from public.game_village_marches where status <> 'done' order by depart_at desc limit 80) m), '[]'::jsonb),
    'reports', coalesce((select jsonb_agg(jsonb_build_object('id', y.id, 'out', y.attacker_id = v, 'won', y.won, 'at', y.arrive_at, 'report', y.report,
                  'loot', jsonb_build_array(y.loot_wood, y.loot_stone, y.loot_food, y.loot_bc)) order by y.arrive_at desc)
                from (select * from public.game_village_marches where (attacker_id = v or defender_id = v) and status <> 'going' order by arrive_at desc limit 20) y), '[]'::jsonb),
    'hero_level', coalesce(h.level, 1));
end $$;

-- ---------- FONDARE e RINOMINARE ----------
create or replace function public.game_village_found(p_plot integer, p_name text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); l public.game_land%rowtype; n text := btrim(coalesce(p_name, ''));
  v_cost integer; v_bal integer;
begin
  perform public._vil_check(v);
  if char_length(n) < 3 or char_length(n) > 24 then raise exception 'Il nome del villaggio deve avere da 3 a 24 caratteri'; end if;
  select * into l from public.game_land where id = p_plot for update;
  if not found or l.owner_id is distinct from v then raise exception 'Puoi fondare un villaggio solo su un tuo terreno'; end if;
  if exists (select 1 from public.game_villages where plot_id = p_plot) then raise exception 'Su questo terreno c''è già un villaggio'; end if;
  if exists (select 1 from public.game_villages where lower(name) = lower(n)) then raise exception 'Esiste già un villaggio con questo nome'; end if;
  perform 1 from public.game_land_owners where user_id = v for update;
  v_cost := public._vil_found_cost(v);
  v_bal := public._ledger_move(v, -v_cost, 'game_village_found', 'game_village', null, 'vilfound:' || p_plot || ':' || v, 'Villaggi: fondazione di ' || n);
  insert into public.game_villages (plot_id, user_id, name, shield_until)
  values (l.id, v, n, now() + make_interval(hours => coalesce(public._setting('game_village_shield_hours'), 48)));
  perform public._tavern_log(v, 'village', 'ha fondato il villaggio ' || n);
  return jsonb_build_object('ok', true, 'plot', l.id, 'cost', v_cost, 'balance', v_bal, 'next_cost', public._vil_found_cost(v));
end $$;

create or replace function public.game_village_rename(p_plot integer, p_name text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); n text := btrim(coalesce(p_name, ''));
begin
  perform public._vil_check(v);
  if char_length(n) < 3 or char_length(n) > 24 then raise exception 'Il nome del villaggio deve avere da 3 a 24 caratteri'; end if;
  if exists (select 1 from public.game_villages where lower(name) = lower(n) and plot_id <> p_plot) then raise exception 'Esiste già un villaggio con questo nome'; end if;
  update public.game_villages set name = n where plot_id = p_plot and user_id = v;
  if not found then raise exception 'Questo non è un tuo villaggio'; end if;
  return jsonb_build_object('ok', true, 'name', n);
end $$;

-- ---------- COSTRUIRE ----------
create or replace function public.game_village_build(p_plot integer, p_building text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); me public.game_villages%rowtype; lv integer; c integer[]; v_bal integer;
  names jsonb := '{"hall":"Municipio","lumber":"Segheria","quarry":"Cava","farm":"Fattoria","warehouse":"Magazzino","barracks":"Caserma","wall":"Mura"}';
begin
  perform public._vil_check(uid);
  if not (names ? p_building) then raise exception 'Edificio sconosciuto'; end if;
  me := public._vil_mine(uid, p_plot);
  lv := (to_jsonb(me)->>p_building)::int;
  if lv >= public._vil_max_level() then raise exception '% è già al livello massimo', names->>p_building; end if;
  if p_building <> 'hall' and lv + 1 > me.hall then raise exception 'Prima porta il Municipio al livello %', lv + 1; end if;
  c := public._vil_cost(p_building, lv + 1);
  if me.wood < c[1] or me.stone < c[2] then raise exception 'Servono % legno e % pietra', c[1], c[2]; end if;
  if c[3] > 0 then
    v_bal := public._ledger_move(uid, -c[3], 'game_village_build', 'game_village', null, 'vilbuild:' || p_plot || ':' || p_building || ':' || (lv + 1) || ':' || floor(extract(epoch from me.founded_at)), 'Villaggi: ' || (names->>p_building) || ' livello ' || (lv + 1) || ' a ' || me.name);
  end if;
  execute format('update public.game_villages set %I = %I + 1, wood = wood - $1, stone = stone - $2 where plot_id = $3', p_building, p_building) using c[1], c[2], p_plot;
  return jsonb_build_object('ok', true, 'building', p_building, 'level', lv + 1, 'cost', to_jsonb(c), 'balance', v_bal);
end $$;

-- ---------- ADDESTRARE ----------
create or replace function public.game_village_train(p_plot integer, p_inf integer, p_arc integer, p_cav integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); me public.game_villages%rowtype; away integer[];
  n integer[] := array[greatest(0, coalesce(p_inf, 0)), greatest(0, coalesce(p_arc, 0)), greatest(0, coalesce(p_cav, 0))]; u integer[];
  v_bc integer := 0; v_food integer := 0; t text[] := array['inf','arc','cav']; nm text[] := array['fanti','arcieri','cavalieri']; i integer; v_bal integer; cap integer;
begin
  perform public._vil_check(uid);
  if n[1] + n[2] + n[3] <= 0 then raise exception 'Scegli quanti soldati addestrare'; end if;
  me := public._vil_mine(uid, p_plot);
  for i in 1..3 loop
    u := public._vil_unit(t[i]);
    if n[i] > 0 and me.barracks < u[8] then raise exception 'Per i % serve la Caserma al livello %', nm[i], u[8]; end if;
    v_bc := v_bc + n[i] * u[1]; v_food := v_food + n[i] * u[2];
  end loop;
  away := public._vil_away(p_plot); cap := public._vil_army_cap(me.barracks);
  if me.inf + me.arc + me.cav + away[1] + away[2] + away[3] + n[1] + n[2] + n[3] > cap then
    raise exception 'La Caserma ospita al massimo % soldati (compresi quelli in marcia): migliorala', cap; end if;
  if me.food < v_food then raise exception 'Servono % cibo per addestrarli', v_food; end if;
  v_bal := public._ledger_move(uid, -v_bc, 'game_village_train', 'game_village', null, 'viltrain:' || p_plot || ':' || floor(extract(epoch from clock_timestamp()) * 1000), 'Villaggi: ' || (n[1] + n[2] + n[3]) || ' soldati a ' || me.name);
  update public.game_villages set inf = inf + n[1], arc = arc + n[2], cav = cav + n[3], food = food - v_food where plot_id = p_plot;
  return jsonb_build_object('ok', true, 'bc', v_bc, 'food', v_food, 'balance', v_bal);
end $$;

-- ---------- GUARNIGIONE ----------
create or replace function public.game_village_defense(p_plot integer, p_inf integer, p_arc integer, p_cav integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); me public.game_villages%rowtype;
begin
  perform public._vil_check(uid);
  me := public._vil_mine(uid, p_plot);
  if least(coalesce(p_inf, 0), coalesce(p_arc, 0), coalesce(p_cav, 0)) < 0 then raise exception 'Numeri non validi'; end if;
  if p_inf > me.inf or p_arc > me.arc or p_cav > me.cav then raise exception 'Non hai abbastanza soldati in questo villaggio'; end if;
  update public.game_villages set def_inf = coalesce(p_inf, 0), def_arc = coalesce(p_arc, 0), def_cav = coalesce(p_cav, 0) where plot_id = p_plot;
  return jsonb_build_object('ok', true, 'def', jsonb_build_array(coalesce(p_inf, 0), coalesce(p_arc, 0), coalesce(p_cav, 0)));
end $$;

-- ---------- ATTACCARE (da un mio villaggio a un villaggio altrui) ----------
create or replace function public.game_village_attack(p_from integer, p_target integer, p_inf integer, p_arc integer, p_cav integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); me public.game_villages%rowtype; t public.game_villages%rowtype;
  n integer[] := array[greatest(0, coalesce(p_inf, 0)), greatest(0, coalesce(p_arc, 0)), greatest(0, coalesce(p_cav, 0))];
  d date := (now() at time zone 'Europe/Rome')::date; lim integer := coalesce(public._setting('game_village_attacks_daily'), 5); mins integer; v_id bigint; na text;
  gap integer := coalesce(public._setting('game_village_hall_gap'), 3);
begin
  perform public._vil_check(uid);
  if n[1] + n[2] + n[3] <= 0 then raise exception 'Scegli quali soldati mandare'; end if;
  me := public._vil_mine(uid, p_from);
  select * into t from public.game_villages where plot_id = p_target;
  if not found then raise exception 'Questo villaggio non esiste'; end if;
  if t.user_id = uid then raise exception 'Non puoi attaccare un tuo villaggio'; end if;
  if t.shield_until > now() then raise exception '% è in tregua fino alle %', t.name, to_char(t.shield_until at time zone 'Europe/Rome', 'HH24:MI'); end if;
  if t.hall < me.hall - gap then raise exception '% è troppo piccolo per %: puoi attaccare solo Municipi dal livello %', t.name, me.name, me.hall - gap; end if;
  if (select count(*) from public.game_village_marches where attacker_plot = p_from and (depart_at at time zone 'Europe/Rome')::date = d) >= lim then
    raise exception '% ha già attaccato % volte oggi: torna domani o parti da un altro villaggio', me.name, lim; end if;
  if n[1] > me.inf - me.def_inf or n[2] > me.arc - me.def_arc or n[3] > me.cav - me.def_cav then
    raise exception 'Puoi mandare solo i soldati che non sono di guardia al villaggio'; end if;
  mins := public._vil_minutes(p_from, p_target, n[1] + n[2] = 0);
  update public.game_villages set inf = inf - n[1], arc = arc - n[2], cav = cav - n[3], shield_until = null where plot_id = p_from;
  insert into public.game_village_marches (attacker_id, defender_id, attacker_plot, defender_plot, inf, arc, cav, arrive_at)
  values (uid, t.user_id, p_from, p_target, n[1], n[2], n[3], now() + make_interval(mins => mins)) returning game_village_marches.id into v_id;
  select nickname into na from public.profiles where id = uid;
  perform public._notify(t.user_id, 'village', '🚨 ' || na || ' sta attaccando ' || t.name,
    'Un esercito da ' || me.name || ' arriva alle ' || to_char((now() + make_interval(mins => mins)) at time zone 'Europe/Rome', 'HH24:MI') || '. Controlla la guarnigione!', 'eroi.html#map', 'game_village', null);
  return jsonb_build_object('ok', true, 'id', v_id, 'minutes', mins, 'arrive_at', now() + make_interval(mins => mins));
end $$;

-- ---------- RISCUOTERE LA CASSA (p_plot null = di tutti i miei villaggi) ----------
create or replace function public.game_village_collect(p_plot integer default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); x record; amt integer := 0; k integer := 0; v_bal integer;
begin
  perform public._vil_check(uid);
  perform public._vil_tick();
  for x in select plot_id from public.game_villages where user_id = uid and (p_plot is null or plot_id = p_plot) order by plot_id loop
    perform public._vil_sync(x.plot_id);
  end loop;
  for x in select plot_id, floor(vault)::integer a from public.game_villages where user_id = uid and (p_plot is null or plot_id = p_plot) and vault >= 1 order by plot_id for update loop
    update public.game_villages set vault = vault - x.a, collected = collected + x.a where plot_id = x.plot_id;
    amt := amt + x.a; k := k + 1;
  end loop;
  if amt < 1 then raise exception 'La cassa è vuota'; end if;
  v_bal := public._ledger_move(uid, amt, 'game_village_collect', 'game_village', null, 'vilcol:' || uid || ':' || floor(extract(epoch from clock_timestamp()) * 1000),
    'Villaggi: cassa di ' || k || case when k = 1 then ' villaggio' else ' villaggi' end);
  return jsonb_build_object('ok', true, 'collected', amt, 'villages', k, 'balance', v_bal);
end $$;

-- ---------- permessi ----------
do $$ declare f text; begin
  foreach f in array array['_vil_max_level()','_vil_prod(integer)','_vil_cap(integer)','_vil_bc_day(integer)','_vil_army_cap(integer)','_vil_cost(text,integer)',
    '_vil_unit(text)','_vil_pos(integer)','_vil_minutes(integer,integer,boolean)','_vil_away(integer)','_vil_upkeep(integer)','_vil_sync(integer)','_vil_check(uuid)',
    '_vil_mine(uuid,integer)','_vil_power(integer[],integer[],boolean)','_vil_tick()','_vil_found_cost(uuid)','game_village_state(integer)','game_village_found(integer,text)',
    'game_village_rename(integer,text)','game_village_build(integer,text)','game_village_train(integer,integer,integer,integer)',
    'game_village_defense(integer,integer,integer,integer)','game_village_attack(integer,integer,integer,integer,integer)','game_village_collect(integer)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon, authenticated';
  end loop;
  foreach f in array array['game_village_state(integer)','game_village_found(integer,text)','game_village_rename(integer,text)','game_village_build(integer,text)',
    'game_village_train(integer,integer,integer,integer)','game_village_defense(integer,integer,integer,integer)',
    'game_village_attack(integer,integer,integer,integer,integer)','game_village_collect(integer)'] loop
    execute 'grant execute on function public.' || f || ' to authenticated';
  end loop;
end $$;

commit;
