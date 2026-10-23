-- =====================================================================
-- MIGRAZIONE 025 — DUEL SIMULATOR (tavolo digitale Yu-Gi-Oh! 1 contro 1, al meglio di 3)
--
-- Garanzie:
--  * usa lo stesso profilo del Black Market (profiles, ruoli, sospensioni) ma NON scrive mai in Ladder, Black Market,
--    wallet, registro contabile, taglie, XP, eroi o notifiche: crea solo tabelle sim_* e funzioni sim_*;
--  * nessuna tabella sim_* è leggibile dal browser: ogni lettura passa da sim_state()/sim_home(), che mostrano a ciascun
--    giocatore SOLO ciò che può vedere (mano, deck e carte coperte dell'avversario non escono mai dal database);
--  * ogni mossa è eseguita dal database (il browser chiama solo funzioni), con il duello bloccato in scrittura;
--  * tavolo digitale: il database NON applica le regole del gioco (chi gioca decide cosa è lecito), ma garantisce
--    le informazioni nascoste, il turno, i punti vita, le zone e il formato al meglio di 3 con side deck;
--  * modulo «duel» (Admin › Moduli aggiuntivi): con il modulo spento ogni funzione rifiuta l'operazione.
-- Annullamento: black-market-duel-simulator-down.sql (cancella SOLO ciò che crea questa migrazione).
-- =====================================================================
begin;

insert into public.system_settings (key, value_int, description) values
 ('module_duel',       1,  'Duel Simulator: 1 = attivo, 0 = spento'),
 ('sim_max_decks',    30,  'Duel Simulator: deck salvabili in libreria per ogni utente'),
 ('sim_lobby_minutes', 60, 'Duel Simulator: minuti dopo i quali una lobby non avviata si chiude da sola'),
 ('sim_idle_hours',    6,  'Duel Simulator: ore senza mosse dopo le quali un duello fermo si chiude da solo')
on conflict (key) do nothing;

-- l'interruttore del modulo accetta anche «duel»
create or replace function public.admin_set_module(p_module text, p_enabled boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o integer;
begin
  if p_module not in ('hall_of_fame','faction_wars','underground','ladder','heroes','duel') then raise exception 'Modulo sconosciuto'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select value_int into o from public.system_settings where key = 'module_' || p_module for update;
  if not found then raise exception 'Impostazione inesistente: esegui le migrazioni precedenti'; end if;
  update public.system_settings set value_int = case when p_enabled then 1 else 0 end, updated_at = now(), updated_by = v where key = 'module_' || p_module;
  perform public._audit(v, 'set_module', 'module', p_module, jsonb_build_object('enabled', o = 1), jsonb_build_object('enabled', p_enabled), p_reason);
end $$;

-- ---------- tabelle ----------
-- Libreria deck di ogni profilo (codici carta di YGOPRODeck, una voce per copia).
create table public.sim_decks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  name text not null check (char_length(btrim(name)) between 1 and 40),
  main integer[] not null default '{}',
  extra integer[] not null default '{}',
  side integer[] not null default '{}',
  temp boolean not null default false,            -- deck «usa solo per questa partita» (non compare in libreria)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(main) <= 60 and cardinality(extra) <= 15 and cardinality(side) <= 15)
);
create unique index sim_decks_name on public.sim_decks (owner_id, lower(btrim(name))) where not temp;
create index sim_decks_owner on public.sim_decks (owner_id, updated_at desc);

-- Lobby = un incontro al meglio di 3 tra due giocatori.
create table public.sim_lobbies (
  id bigserial primary key,
  host_id uuid not null references public.profiles(id) on delete restrict,
  title text check (title is null or char_length(title) between 1 and 30),
  status text not null default 'lobby' check (status in ('lobby','siding','playing','finished','cancelled')),
  game_no integer not null default 0 check (game_no between 0 and 3),
  wins_1 integer not null default 0,
  wins_2 integer not null default 0,
  chooser_seat smallint check (chooser_seat in (1,2)),   -- chi sceglie chi gioca per primo nel prossimo duello
  winner_seat smallint check (winner_seat in (1,2)),
  end_reason text,
  ver bigint not null default 1,                          -- cambia a ogni modifica: il browser scarica lo stato solo se è cambiato
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default now()
);
create index sim_lobbies_status on public.sim_lobbies (status, updated_at);

create table public.sim_players (
  lobby_id bigint not null references public.sim_lobbies(id) on delete cascade,
  seat smallint not null check (seat in (1,2)),
  user_id uuid not null references public.profiles(id) on delete restrict,
  deck_id uuid references public.sim_decks(id) on delete set null,
  ready boolean not null default false,
  cfg_main integer[], cfg_extra integer[], cfg_side integer[],   -- configurazione del deck in questo incontro (cambia col side)
  active boolean not null default true,
  joined_at timestamptz not null default now(),
  primary key (lobby_id, seat),
  unique (lobby_id, user_id)
);
create unique index sim_players_one_active on public.sim_players (user_id) where active;

create table public.sim_games (
  id bigserial primary key,
  lobby_id bigint not null references public.sim_lobbies(id) on delete cascade,
  no integer not null check (no between 1 and 3),
  status text not null default 'choosing' check (status in ('choosing','playing','finished')),
  chooser_seat smallint not null check (chooser_seat in (1,2)),
  first_seat smallint check (first_seat in (1,2)),
  turn_seat smallint check (turn_seat in (1,2)),
  turn_no integer not null default 0,
  phase text not null default 'draw' check (phase in ('draw','standby','main1','battle','main2','end')),
  lp_1 integer not null default 8000 check (lp_1 between 0 and 9999999),
  lp_2 integer not null default 8000 check (lp_2 between 0 and 9999999),
  proposal jsonb,
  pending_end jsonb,
  winner_seat smallint check (winner_seat in (1,2)),
  result text,
  started_at timestamptz,
  ended_at timestamptz,
  unique (lobby_id, no)
);

-- Una riga per carta fisica del duello. id = numero casuale (non rivela l'ordine del deck né l'identità).
create table public.sim_cards (
  game_id bigint not null references public.sim_games(id) on delete cascade,
  id integer not null,
  owner smallint not null check (owner in (1,2)),
  ctrl smallint not null check (ctrl in (1,2)),
  code integer not null check (code >= 0),                -- 0 = segnalino (token)
  zone text not null check (zone in ('deck','hand','extra','mz','emz','st','fz','gy','banish','ovl')),
  slot smallint,
  ord integer not null default 0,
  pos text check (pos in ('atk','def')),
  face_up boolean not null default false,
  host_id integer,                                        -- per i materiali Xyz (zone = 'ovl'): id del mostro
  counters integer not null default 0 check (counters between 0 and 99),
  revealed boolean not null default false,                -- carta in mano mostrata all'avversario
  primary key (game_id, id),
  check ((zone in ('mz','st') and slot between 1 and 5) or (zone = 'emz' and slot between 1 and 2) or (zone = 'fz' and slot = 1)
         or (zone not in ('mz','st','emz','fz') and slot is null))
);
create unique index sim_cards_slot on public.sim_cards (game_id, ctrl, zone, slot) where zone in ('mz','st','fz');
create unique index sim_cards_emz on public.sim_cards (game_id, slot) where zone = 'emz';
create index sim_cards_zone on public.sim_cards (game_id, owner, zone, ord);
create index sim_cards_host on public.sim_cards (game_id, host_id) where host_id is not null;

-- Registro pubblico del duello: contiene SOLO ciò che entrambi possono vedere.
create table public.sim_log (
  game_id bigint not null references public.sim_games(id) on delete cascade,
  n integer not null,
  seat smallint,
  kind text not null,
  data jsonb not null default '{}',
  at timestamptz not null default now(),
  primary key (game_id, n)
);

alter table public.sim_decks enable row level security;
alter table public.sim_lobbies enable row level security;
alter table public.sim_players enable row level security;
alter table public.sim_games enable row level security;
alter table public.sim_cards enable row level security;
alter table public.sim_log enable row level security;
revoke all on public.sim_decks, public.sim_lobbies, public.sim_players, public.sim_games, public.sim_cards, public.sim_log from public, anon, authenticated;
revoke all on sequence public.sim_lobbies_id_seq, public.sim_games_id_seq from public, anon, authenticated;
-- nessuna policy: il browser non può leggere né scrivere queste tabelle direttamente, solo tramite le funzioni qui sotto.

-- ---------- funzioni di supporto (non esposte al browser) ----------
create function public._sim_user() returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
begin
  perform public._require_module('duel');
  return v;
end $$;

create function public._sim_bump(p_lobby bigint) returns void language sql security definer set search_path = public as $$
  update public.sim_lobbies set ver = ver + 1, updated_at = now() where id = p_lobby $$;

-- visibilità di una carta per chi guarda (viewer = 1 o 2)
create function public._sim_vis(p_zone text, p_face boolean, p_rev boolean, p_owner smallint, p_ctrl smallint, p_viewer smallint) returns boolean
language sql immutable as $$
  select case p_zone
    when 'deck' then false
    when 'hand' then p_owner = p_viewer or p_rev
    when 'extra' then p_owner = p_viewer or p_face
    when 'mz' then p_face or p_ctrl = p_viewer
    when 'emz' then p_face or p_ctrl = p_viewer
    when 'st' then p_face or p_ctrl = p_viewer
    when 'fz' then p_face or p_ctrl = p_viewer
    else p_face or p_owner = p_viewer      -- gy, banish, ovl
  end $$;

-- una carta è pubblica (la vedono entrambi)?
create function public._sim_pub(p_zone text, p_face boolean, p_rev boolean) returns boolean language sql immutable as $$
  select case p_zone when 'deck' then false when 'hand' then p_rev else p_face end $$;

create function public._sim_log(p_game bigint, p_seat smallint, p_kind text, p_data jsonb) returns void language sql security definer set search_path = public as $$
  insert into public.sim_log (game_id, n, seat, kind, data)
  values (p_game, coalesce((select max(n) from public.sim_log where game_id = p_game), 0) + 1, p_seat, p_kind, coalesce(p_data, '{}')) $$;

-- controlli sul deck: formato e copie (le dimensioni minime si verificano quando ci si dichiara PRONTO)
create function public._sim_deck_check(p_main integer[], p_extra integer[], p_side integer[]) returns void language plpgsql immutable as $$
declare x integer; bad integer;
begin
  if p_main is null or p_extra is null or p_side is null then raise exception 'Deck non valido'; end if;
  if cardinality(p_main) > 60 then raise exception 'Il Main Deck può avere al massimo 60 carte'; end if;
  if cardinality(p_extra) > 15 then raise exception 'L''Extra Deck può avere al massimo 15 carte'; end if;
  if cardinality(p_side) > 15 then raise exception 'Il Side Deck può avere al massimo 15 carte'; end if;
  select count(*) into bad from unnest(p_main || p_extra || p_side) c where c is null or c < 1 or c > 999999999;
  if bad > 0 then raise exception 'Codice carta non valido'; end if;
  select max(n) into x from (select count(*) n from unnest(p_main || p_extra || p_side) c group by c) q;
  if coalesce(x, 0) > 3 then raise exception 'Non puoi avere più di 3 copie della stessa carta (Main + Extra + Side)'; end if;
end $$;

create function public._sim_deck_playable(p_main integer[], p_extra integer[], p_side integer[]) returns void language plpgsql immutable as $$
begin
  perform public._sim_deck_check(p_main, p_extra, p_side);
  if cardinality(p_main) < 40 then raise exception 'Il Main Deck deve avere almeno 40 carte (ne ha %)', cardinality(p_main); end if;
end $$;

-- blocca la lobby e identifica chi chiama; p_need: lobby | siding | choosing | playing | any
create function public._sim_enter(p_lobby bigint, p_need text, out o_user uuid, out o_seat smallint, out o_game bigint)
language plpgsql security definer set search_path = public as $$
declare l public.sim_lobbies%rowtype; gs text;
begin
  o_user := public._sim_user();
  select * into l from public.sim_lobbies where id = p_lobby for update;
  if not found then raise exception 'Lobby inesistente'; end if;
  select seat into o_seat from public.sim_players where lobby_id = p_lobby and user_id = o_user;
  if not found then raise exception 'Non partecipi a questa partita'; end if;
  if p_need = 'lobby' and l.status <> 'lobby' then raise exception 'La partita è già iniziata'; end if;
  if p_need = 'siding' and l.status <> 'siding' then raise exception 'Non è il momento del side deck'; end if;
  if p_need in ('playing', 'choosing') then
    if l.status <> 'playing' then raise exception 'Il duello non è in corso'; end if;
    select id, status into o_game, gs from public.sim_games where lobby_id = p_lobby and no = l.game_no;
    if p_need = 'playing' and gs <> 'playing' then raise exception 'Il duello non è in corso'; end if;
    if p_need = 'choosing' and gs <> 'choosing' then raise exception 'Il duello è già iniziato'; end if;
  end if;
end $$;

create function public._sim_shuffle_deck(p_game bigint, p_owner smallint) returns void language sql security definer set search_path = public as $$
  update public.sim_cards x set ord = r.rn
  from (select id, row_number() over (order by random())::integer as rn from public.sim_cards where game_id = p_game and owner = p_owner and zone = 'deck') r
  where x.game_id = p_game and x.id = r.id $$;

-- punti vita a zero => fine del duello in attesa di conferma
create function public._sim_check_end(p_game bigint) returns void language plpgsql security definer set search_path = public as $$
declare g public.sim_games%rowtype; p jsonb;
begin
  select * into g from public.sim_games where id = p_game;
  p := g.pending_end;
  if g.lp_1 <= 0 and g.lp_2 <= 0 then p := jsonb_build_object('loser', 0, 'reason', 'lp');
  elsif g.lp_1 <= 0 then p := jsonb_build_object('loser', 1, 'reason', 'lp');
  elsif g.lp_2 <= 0 then p := jsonb_build_object('loser', 2, 'reason', 'lp');
  elsif p is not null and p->>'reason' = 'lp' then p := null;
  end if;
  update public.sim_games set pending_end = p where id = p_game;
end $$;

-- ---------- stato visto da un giocatore ----------
create function public._sim_state(p_lobby bigint, p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.sim_lobbies%rowtype; me smallint; g public.sim_games%rowtype; pl jsonb; cards jsonb := '[]'; cnt jsonb := '{}'; lg jsonb := '[]'; gm jsonb := null; hist jsonb; cfg jsonb := null;
begin
  select * into l from public.sim_lobbies where id = p_lobby;
  select seat into me from public.sim_players where lobby_id = p_lobby and user_id = p_user;
  select coalesce(jsonb_agg(jsonb_build_object('seat', sp.seat, 'user_id', sp.user_id, 'nickname', pr.nickname, 'avatar', pr.avatar,
           'ready', sp.ready, 'deck_set', sp.deck_id is not null, 'active', sp.active,
           'deck_id', case when sp.seat = me then sp.deck_id end, 'deck_name', case when sp.seat = me then d.name end,
           'deck_main', case when sp.seat = me then cardinality(d.main) end) order by sp.seat), '[]')
    into pl
    from public.sim_players sp join public.profiles pr on pr.id = sp.user_id left join public.sim_decks d on d.id = sp.deck_id
    where sp.lobby_id = p_lobby;
  if l.status = 'siding' then
    select jsonb_build_object('main', cfg_main, 'extra', cfg_extra, 'side', cfg_side) into cfg from public.sim_players where lobby_id = p_lobby and seat = me;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('no', no, 'winner', winner_seat, 'result', result) order by no), '[]') into hist
    from public.sim_games where lobby_id = p_lobby and status = 'finished';
  if l.game_no > 0 then
    select * into g from public.sim_games where lobby_id = p_lobby and no = l.game_no;
    gm := jsonb_build_object('id', g.id, 'no', g.no, 'status', g.status, 'chooser', g.chooser_seat, 'first', g.first_seat, 'turn_seat', g.turn_seat,
            'turn_no', g.turn_no, 'phase', g.phase, 'lp', jsonb_build_array(g.lp_1, g.lp_2), 'proposal', g.proposal, 'pending_end', g.pending_end,
            'winner', g.winner_seat, 'result', g.result);
    if g.status <> 'finished' then
      select coalesce(jsonb_agg(jsonb_build_object('i', c.id, 'o', c.owner, 'c', c.ctrl, 'z', c.zone, 's', c.slot, 'k', c.ord, 'p', c.pos, 'f', c.face_up,
               'h', c.host_id, 'n', c.counters, 'r', c.revealed,
               'x', case when public._sim_vis(c.zone, c.face_up, c.revealed, c.owner, c.ctrl, me) then c.code end) order by c.zone, c.ord), '[]')
        into cards
        from public.sim_cards c
        where c.game_id = g.id and c.zone <> 'deck' and (c.zone <> 'hand' or c.owner = me or c.revealed) and (c.zone <> 'extra' or c.owner = me or c.face_up);
      select coalesce(jsonb_object_agg(q.owner::text, q.cnt), '{}') into cnt from (
        select owner, jsonb_build_object('deck', count(*) filter (where zone = 'deck'), 'hand', count(*) filter (where zone = 'hand'),
          'extra', count(*) filter (where zone = 'extra'), 'gy', count(*) filter (where zone = 'gy'), 'banish', count(*) filter (where zone = 'banish')) cnt
        from public.sim_cards where game_id = g.id group by owner) q;
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.n), '[]') into lg
      from (select n, seat, kind, data from public.sim_log where game_id = g.id order by n desc limit 100) x;
  end if;
  return jsonb_build_object('v', l.ver, 'lobby', jsonb_build_object('id', l.id, 'title', l.title, 'status', l.status, 'game_no', l.game_no,
           'wins', jsonb_build_array(l.wins_1, l.wins_2), 'winner', l.winner_seat, 'end_reason', l.end_reason, 'chooser', l.chooser_seat, 'host_id', l.host_id),
         'me', jsonb_build_object('seat', me, 'user_id', p_user, 'cfg', cfg), 'players', pl, 'game', gm, 'games', hist,
         'cards', cards, 'counts', cnt, 'log', lg);
end $$;

create function public.sim_state(p_lobby bigint, p_since bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user(); cur bigint;
begin
  if not exists (select 1 from public.sim_players where lobby_id = p_lobby and user_id = v) then raise exception 'Non partecipi a questa partita'; end if;
  select l.ver into cur from public.sim_lobbies l where l.id = p_lobby;
  if p_since is not null and p_since = cur then return jsonb_build_object('same', true, 'v', cur); end if;
  return public._sim_state(p_lobby, v);
end $$;

-- ---------- pulizia automatica ----------
create function public._sim_abandon(p_lobby bigint, p_reason text) returns void language plpgsql security definer set search_path = public as $$
begin
  update public.sim_games set status = 'finished', result = p_reason, ended_at = now(), proposal = null, pending_end = null
    where lobby_id = p_lobby and status in ('choosing', 'playing');
  delete from public.sim_cards where game_id in (select id from public.sim_games where lobby_id = p_lobby);
  update public.sim_lobbies set status = case when status = 'lobby' then 'cancelled' else 'finished' end, end_reason = p_reason, finished_at = now(), ver = ver + 1, updated_at = now()
    where id = p_lobby;
  update public.sim_players set active = false, ready = false where lobby_id = p_lobby;
end $$;

create function public._sim_sweep() returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select id from public.sim_lobbies where status = 'lobby'
           and updated_at < now() - make_interval(mins => coalesce(public._setting('sim_lobby_minutes'), 60)) loop
    perform public._sim_abandon(r.id, 'scaduta');
  end loop;
  for r in select id from public.sim_lobbies where status in ('siding', 'playing')
           and updated_at < now() - make_interval(hours => coalesce(public._setting('sim_idle_hours'), 6)) loop
    perform public._sim_abandon(r.id, 'abbandonata');
  end loop;
  delete from public.sim_lobbies where status in ('finished', 'cancelled') and coalesce(finished_at, updated_at) < now() - interval '30 days';
  delete from public.sim_decks where temp and created_at < now() - interval '2 days';
end $$;

-- ---------- libreria deck ----------
create function public.sim_deck_save(p_id uuid, p_name text, p_main integer[], p_extra integer[], p_side integer[], p_temp boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user(); n text := btrim(coalesce(p_name, '')); r uuid; mx integer := coalesce(public._setting('sim_max_decks'), 30);
begin
  if char_length(n) < 1 or char_length(n) > 40 then raise exception 'Il nome del deck deve avere da 1 a 40 caratteri'; end if;
  p_main := coalesce(p_main, '{}'); p_extra := coalesce(p_extra, '{}'); p_side := coalesce(p_side, '{}');
  perform public._sim_deck_check(p_main, p_extra, p_side);
  if p_id is not null then
    perform 1 from public.sim_decks where id = p_id and owner_id = v for update;
    if not found then raise exception 'Deck non trovato'; end if;
    begin
      update public.sim_decks set name = n, main = p_main, extra = p_extra, side = p_side, updated_at = now() where id = p_id;
    exception when unique_violation then raise exception 'Hai già un deck con questo nome';
    end;
    -- se il deck è scelto in una lobby non ancora avviata, il PRONTO va rimesso
    update public.sim_players sp set ready = false from public.sim_lobbies l
      where sp.deck_id = p_id and sp.lobby_id = l.id and l.status = 'lobby' and sp.ready;
    r := p_id;
  else
    if not p_temp and (select count(*) from public.sim_decks where owner_id = v and not temp) >= mx then
      raise exception 'Hai raggiunto il massimo di % deck in libreria: eliminane uno', mx;
    end if;
    if p_temp and (select count(*) from public.sim_decks where owner_id = v and temp) >= 10 then
      delete from public.sim_decks where id in (select id from public.sim_decks where owner_id = v and temp
        and id not in (select deck_id from public.sim_players where deck_id is not null and active) order by created_at limit 5);
    end if;
    begin
      insert into public.sim_decks (owner_id, name, main, extra, side, temp) values (v, n, p_main, p_extra, p_side, coalesce(p_temp, false)) returning id into r;
    exception when unique_violation then raise exception 'Hai già un deck con questo nome';
    end;
  end if;
  return r;
end $$;

create function public.sim_deck_delete(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user();
begin
  perform 1 from public.sim_decks where id = p_id and owner_id = v for update;
  if not found then raise exception 'Deck non trovato'; end if;
  update public.sim_players sp set deck_id = null, ready = false from public.sim_lobbies l
    where sp.deck_id = p_id and sp.lobby_id = l.id and l.status = 'lobby';
  delete from public.sim_decks where id = p_id;
end $$;

-- ---------- pagina iniziale: i miei deck, la mia lobby, le lobby aperte ----------
create function public.sim_home() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user(); mine bigint;
begin
  perform public._sim_sweep();
  select lobby_id into mine from public.sim_players where user_id = v and active;
  return jsonb_build_object(
    'mine', mine,
    'max_decks', coalesce(public._setting('sim_max_decks'), 30),
    'decks', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'main', d.main, 'extra', d.extra, 'side', d.side, 'updated_at', d.updated_at) order by d.updated_at desc), '[]')
              from public.sim_decks d where d.owner_id = v and not d.temp),
    'temp_decks', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'main', cardinality(d.main), 'extra', cardinality(d.extra), 'side', cardinality(d.side)) order by d.created_at desc), '[]')
              from (select * from public.sim_decks where owner_id = v and temp order by created_at desc limit 5) d),
    'lobbies', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'title', l.title, 'host_id', l.host_id, 'nickname', p.nickname, 'avatar', p.avatar, 'created_at', l.created_at) order by l.created_at desc), '[]')
                from public.sim_lobbies l join public.profiles p on p.id = l.host_id
                where l.status = 'lobby' and (select count(*) from public.sim_players sp where sp.lobby_id = l.id) = 1 and l.host_id <> v and not p.suspended),
    'recent', (select coalesce(jsonb_agg(x order by x.finished_at desc), '[]') from (
                select l.id, l.status, l.wins_1, l.wins_2, l.winner_seat, l.end_reason, l.finished_at, me.seat as my_seat, op.nickname as opponent
                from public.sim_players me join public.sim_lobbies l on l.id = me.lobby_id
                left join public.sim_players ops on ops.lobby_id = l.id and ops.seat <> me.seat
                left join public.profiles op on op.id = ops.user_id
                where me.user_id = v and l.status = 'finished' order by l.finished_at desc limit 5) x));
end $$;

-- ---------- lobby ----------
create function public.sim_lobby_create(p_title text default null) returns bigint language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user(); lid bigint; t text := nullif(btrim(coalesce(p_title, '')), '');
begin
  perform public._sim_sweep();
  if t is not null and char_length(t) > 30 then raise exception 'Il titolo può avere al massimo 30 caratteri'; end if;
  if exists (select 1 from public.sim_players where user_id = v and active) then raise exception 'Sei già in una lobby: esci prima di crearne un’altra'; end if;
  insert into public.sim_lobbies (host_id, title) values (v, t) returning sim_lobbies.id into lid;
  insert into public.sim_players (lobby_id, seat, user_id) values (lid, 1, v);
  return lid;
end $$;

create function public.sim_lobby_join(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user(); l public.sim_lobbies%rowtype;
begin
  select * into l from public.sim_lobbies where id = p_lobby for update;
  if not found then raise exception 'Lobby inesistente'; end if;
  if l.status <> 'lobby' then raise exception 'Questa lobby non è più disponibile'; end if;
  if exists (select 1 from public.sim_players where user_id = v and active) then raise exception 'Sei già in una lobby: esci prima'; end if;
  if (select count(*) from public.sim_players where lobby_id = p_lobby) >= 2 then raise exception 'La lobby è piena'; end if;
  if exists (select 1 from public.profiles where id = l.host_id and suspended) then raise exception 'La lobby non è disponibile'; end if;
  insert into public.sim_players (lobby_id, seat, user_id) values (p_lobby, 2, v);
  update public.sim_players set ready = false where lobby_id = p_lobby;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- esce dalla lobby; a partita iniziata equivale ad arrendersi all'incontro
create function public.sim_lobby_leave(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; l public.sim_lobbies%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'any');
  select * into l from public.sim_lobbies where id = p_lobby;
  if l.status = 'lobby' then
    if l.host_id = v then
      perform public._sim_abandon(p_lobby, 'annullata');
    else
      delete from public.sim_players where lobby_id = p_lobby and user_id = v;
      update public.sim_players set ready = false where lobby_id = p_lobby;
      perform public._sim_bump(p_lobby);
    end if;
    return jsonb_build_object('left', true);
  elsif l.status in ('siding', 'playing') then
    perform public._sim_forfeit(p_lobby, me, 'forfeit');
  else
    update public.sim_players set active = false where lobby_id = p_lobby and user_id = v;
  end if;
  return jsonb_build_object('left', true);
end $$;

create function public.sim_lobby_kick(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; l public.sim_lobbies%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'lobby');
  select * into l from public.sim_lobbies where id = p_lobby;
  if l.host_id <> v then raise exception 'Solo chi ha creato la lobby può farlo'; end if;
  delete from public.sim_players where lobby_id = p_lobby and user_id <> v;
  update public.sim_players set ready = false where lobby_id = p_lobby;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_set_deck(p_lobby bigint, p_deck uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'lobby');
  if p_deck is not null and not exists (select 1 from public.sim_decks where id = p_deck and owner_id = v) then raise exception 'Deck non trovato'; end if;
  update public.sim_players set deck_id = p_deck, ready = false where lobby_id = p_lobby and user_id = v;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- PRONTO: in lobby richiede un deck valido; tra un duello e l'altro (side) basta esserci
create function public.sim_set_ready(p_lobby bigint, p_ready boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; l public.sim_lobbies%rowtype; d public.sim_decks%rowtype; p public.sim_players%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'any');
  select * into l from public.sim_lobbies where id = p_lobby;
  select * into p from public.sim_players where lobby_id = p_lobby and user_id = v;
  if l.status = 'lobby' then
    if p_ready then
      if p.deck_id is null then raise exception 'Scegli prima un deck'; end if;
      select * into d from public.sim_decks where id = p.deck_id;
      perform public._sim_deck_playable(d.main, d.extra, d.side);
      if (select count(*) from public.sim_players where lobby_id = p_lobby) < 2 then raise exception 'Aspetta che entri l''avversario'; end if;
    end if;
    update public.sim_players set ready = coalesce(p_ready, false) where lobby_id = p_lobby and user_id = v;
  elsif l.status = 'siding' then
    update public.sim_players set ready = coalesce(p_ready, false) where lobby_id = p_lobby and user_id = v;
    if (select count(*) from public.sim_players where lobby_id = p_lobby and ready) = 2 then
      perform public._sim_new_game(p_lobby);
    end if;
  else
    raise exception 'Non è il momento di dichiararsi pronti';
  end if;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- crea il prossimo duello dell'incontro: resta da scegliere chi gioca per primo
create function public._sim_new_game(p_lobby bigint) returns void language plpgsql security definer set search_path = public as $$
declare l public.sim_lobbies%rowtype; ch smallint; gid bigint;
begin
  select * into l from public.sim_lobbies where id = p_lobby;
  ch := coalesce(l.chooser_seat, (1 + floor(random() * 2))::smallint);
  insert into public.sim_games (lobby_id, no, chooser_seat) values (p_lobby, l.game_no + 1, ch) returning id into gid;
  update public.sim_lobbies set game_no = l.game_no + 1, status = 'playing', chooser_seat = ch where id = p_lobby;
  update public.sim_players set ready = false where lobby_id = p_lobby;
  perform public._sim_log(gid, ch, 'choose', jsonb_build_object('no', l.game_no + 1));
end $$;

-- l'host avvia l'incontro: servono due giocatori PRONTI con un deck valido
create function public.sim_start(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; l public.sim_lobbies%rowtype; r record; d public.sim_decks%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'lobby');
  select * into l from public.sim_lobbies where id = p_lobby;
  if l.host_id <> v then raise exception 'Solo chi ha creato la lobby può avviare la partita'; end if;
  if (select count(*) from public.sim_players where lobby_id = p_lobby) <> 2 then raise exception 'Serve un avversario'; end if;
  if exists (select 1 from public.sim_players where lobby_id = p_lobby and not ready) then raise exception 'Entrambi i giocatori devono essere PRONTI'; end if;
  for r in select * from public.sim_players where lobby_id = p_lobby loop
    select * into d from public.sim_decks where id = r.deck_id;
    if not found then raise exception 'Un giocatore non ha un deck'; end if;
    perform public._sim_deck_playable(d.main, d.extra, d.side);
    update public.sim_players set cfg_main = d.main, cfg_extra = d.extra, cfg_side = d.side where lobby_id = p_lobby and seat = r.seat;
  end loop;
  update public.sim_lobbies set started_at = now(), chooser_seat = null where id = p_lobby;
  perform public._sim_new_game(p_lobby);
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- ---------- inizio del duello ----------
create function public.sim_choose_first(p_lobby bigint, p_first smallint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; gm public.sim_games%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'choosing');
  select * into gm from public.sim_games where id = g;
  if gm.chooser_seat <> me then raise exception 'Non tocca a te scegliere'; end if;
  if p_first not in (1, 2) then raise exception 'Scelta non valida'; end if;
  -- crea le carte con numeri casuali (l'id non rivela né l'ordine né l'identità), poi mescola e pesca 5 carte a testa
  insert into public.sim_cards (game_id, id, owner, ctrl, code, zone, ord, face_up)
  select g, n.id, n.seat, n.seat, n.code, n.zone, (row_number() over (partition by n.seat, n.zone order by random()))::integer, false
  from (select s.seat, s.zone, s.code, (row_number() over (order by random()))::integer as id from (
          select sp.seat, 'deck' as zone, c as code from public.sim_players sp, unnest(sp.cfg_main) c where sp.lobby_id = p_lobby
          union all
          select sp.seat, 'extra', c from public.sim_players sp, unnest(sp.cfg_extra) c where sp.lobby_id = p_lobby) s) n;
  with top as (select id, (row_number() over (partition by owner order by ord desc))::integer rn from public.sim_cards where game_id = g and zone = 'deck')
  update public.sim_cards c set zone = 'hand', ord = top.rn from top where c.game_id = g and c.id = top.id and top.rn <= 5;
  update public.sim_games set status = 'playing', first_seat = p_first, turn_seat = p_first, turn_no = 1, phase = 'draw', started_at = now() where id = g;
  perform public._sim_log(g, me, 'start', jsonb_build_object('first', p_first, 'no', gm.no));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- ---------- fine del duello e dell'incontro ----------
create function public._sim_finish_game(p_lobby bigint, p_winner integer, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare l public.sim_lobbies%rowtype; g public.sim_games%rowtype; w smallint := nullif(p_winner, 0); w1 integer; w2 integer; loser smallint;
begin
  select * into l from public.sim_lobbies where id = p_lobby;
  select * into g from public.sim_games where lobby_id = p_lobby and no = l.game_no;
  update public.sim_games set status = 'finished', winner_seat = w, result = p_reason, ended_at = now(), proposal = null, pending_end = null where id = g.id;
  perform public._sim_log(g.id, w, 'end', jsonb_build_object('winner', w, 'reason', p_reason));
  delete from public.sim_cards where game_id = g.id;          -- a duello finito non serve più conservare il tavolo
  w1 := l.wins_1 + case when w = 1 then 1 else 0 end;
  w2 := l.wins_2 + case when w = 2 then 1 else 0 end;
  if w1 >= 2 or w2 >= 2 or l.game_no >= 3 then
    update public.sim_lobbies set status = 'finished', wins_1 = w1, wins_2 = w2, winner_seat = case when w1 >= 2 then 1 when w2 >= 2 then 2 end,
           end_reason = 'normale', finished_at = now() where id = p_lobby;
    update public.sim_players set active = false, ready = false where lobby_id = p_lobby;
  else
    -- sceglie chi ha perso; dopo un pareggio si tira la moneta
    loser := case when w is null then (1 + floor(random() * 2))::smallint else (3 - w)::smallint end;
    update public.sim_lobbies set status = 'siding', wins_1 = w1, wins_2 = w2, chooser_seat = loser where id = p_lobby;
    update public.sim_players set ready = false where lobby_id = p_lobby;
  end if;
end $$;

-- chi se ne va (o abbandona) perde l'incontro
create function public._sim_forfeit(p_lobby bigint, p_loser smallint, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare l public.sim_lobbies%rowtype;
begin
  select * into l from public.sim_lobbies where id = p_lobby;
  if exists (select 1 from public.sim_games where lobby_id = p_lobby and no = l.game_no and status in ('choosing', 'playing')) then
    perform public._sim_finish_game(p_lobby, 3 - p_loser, p_reason);
  end if;
  update public.sim_lobbies set status = 'finished', winner_seat = (3 - p_loser)::smallint, end_reason = p_reason, finished_at = now(), ver = ver + 1, updated_at = now() where id = p_lobby;
  update public.sim_players set active = false, ready = false where lobby_id = p_lobby;
end $$;

create function public.sim_concede(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  perform public._sim_log(g, me, 'concede', '{}');
  perform public._sim_finish_game(p_lobby, 3 - me, 'concede');
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- punti vita a zero o mazzo vuoto: uno dei due conferma la fine
create function public.sim_confirm_end(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; gm public.sim_games%rowtype; lo integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into gm from public.sim_games where id = g;
  if gm.pending_end is null then raise exception 'Nessuna fine da confermare'; end if;
  lo := (gm.pending_end->>'loser')::integer;
  perform public._sim_finish_game(p_lobby, case when lo = 0 then 0 else 3 - lo end, gm.pending_end->>'reason');
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- mazzo vuoto segnalato per errore: lo annulla l'avversario di chi dovrebbe perdere
create function public.sim_dismiss_end(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; gm public.sim_games%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into gm from public.sim_games where id = g;
  if gm.pending_end is null or gm.pending_end->>'reason' <> 'deckout' then raise exception 'Niente da annullare'; end if;
  if (gm.pending_end->>'loser')::integer = me then raise exception 'Può annullarlo solo l''avversario'; end if;
  update public.sim_games set pending_end = null where id = g;
  perform public._sim_log(g, me, 'dismiss', '{}');
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- proposte che richiedono il consenso dell'avversario: pareggio, vittoria per effetto di una carta
create function public.sim_propose(p_lobby bigint, p_kind text, p_reason text default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; gm public.sim_games%rowtype; rs text := nullif(left(btrim(coalesce(p_reason, '')), 80), '');
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into gm from public.sim_games where id = g;
  if p_kind not in ('draw', 'win') then raise exception 'Proposta non valida'; end if;
  if gm.proposal is not null then raise exception 'C''è già una proposta in sospeso'; end if;
  update public.sim_games set proposal = jsonb_build_object('kind', p_kind, 'by', me, 'reason', rs) where id = g;
  perform public._sim_log(g, me, 'propose', jsonb_build_object('kind', p_kind, 'reason', rs));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_respond(p_lobby bigint, p_accept boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; gm public.sim_games%rowtype; by_ smallint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into gm from public.sim_games where id = g;
  if gm.proposal is null then raise exception 'Nessuna proposta in sospeso'; end if;
  by_ := (gm.proposal->>'by')::smallint;
  if by_ = me then
    if p_accept then raise exception 'Non puoi accettare la tua proposta'; end if;
    update public.sim_games set proposal = null where id = g;
    perform public._sim_log(g, me, 'withdraw', jsonb_build_object('kind', gm.proposal->>'kind'));
  elsif p_accept then
    perform public._sim_log(g, me, 'accept', jsonb_build_object('kind', gm.proposal->>'kind'));
    perform public._sim_finish_game(p_lobby, case when gm.proposal->>'kind' = 'draw' then 0 else by_ end, case when gm.proposal->>'kind' = 'draw' then 'draw' else 'claim' end);
  else
    update public.sim_games set proposal = null where id = g;
    perform public._sim_log(g, me, 'decline', jsonb_build_object('kind', gm.proposal->>'kind'));
  end if;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- ---------- side deck tra un duello e l'altro ----------
create function public.sim_side(p_lobby bigint, p_main integer[], p_extra integer[], p_side integer[]) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; p public.sim_players%rowtype; a integer[]; b integer[];
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'siding');
  select * into p from public.sim_players where lobby_id = p_lobby and user_id = v;
  if p.ready then raise exception 'Togli il PRONTO per modificare il deck'; end if;
  p_main := coalesce(p_main, '{}'); p_extra := coalesce(p_extra, '{}'); p_side := coalesce(p_side, '{}');
  perform public._sim_deck_playable(p_main, p_extra, p_side);
  select array_agg(x order by x) into a from unnest(p.cfg_main || p.cfg_extra || p.cfg_side) x;
  select array_agg(x order by x) into b from unnest(p_main || p_extra || p_side) x;
  if a is distinct from b then raise exception 'Con il side puoi solo scambiare carte tra Main, Extra e Side: non aggiungerne né toglierne'; end if;
  if cardinality(p_side) <> cardinality(p.cfg_side) then raise exception 'Il Side Deck deve restare di % carte', cardinality(p.cfg_side); end if;
  update public.sim_players set cfg_main = p_main, cfg_extra = p_extra, cfg_side = p_side where lobby_id = p_lobby and user_id = v;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- ---------- il tavolo ----------
create function public.sim_draw(p_lobby bigint, p_n integer default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; have integer; base integer; got integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if p_n is null or p_n < 1 or p_n > 10 then raise exception 'Puoi pescare da 1 a 10 carte'; end if;
  select count(*) into have from public.sim_cards where game_id = g and owner = me and zone = 'deck';
  got := least(have, p_n);
  select coalesce(max(ord), 0) into base from public.sim_cards where game_id = g and owner = me and zone = 'hand';
  with top as (select id, (row_number() over (order by ord desc))::integer rn from public.sim_cards where game_id = g and owner = me and zone = 'deck' order by ord desc limit got)
  update public.sim_cards c set zone = 'hand', ord = base + top.rn, revealed = false from top where c.game_id = g and c.id = top.id;
  perform public._sim_log(g, me, 'draw', jsonb_build_object('n', got));
  if have < p_n then
    update public.sim_games set pending_end = jsonb_build_object('loser', me, 'reason', 'deckout') where id = g;
    perform public._sim_log(g, me, 'deckout', '{}');
  end if;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_move(p_lobby bigint, p_card integer, p_zone text, p_slot integer default null, p_pos text default null,
  p_face boolean default null, p_top boolean default true, p_host integer default null, p_shuffle boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; c public.sim_cards%rowtype; h public.sim_cards%rowtype; to_side smallint; s integer; f boolean; ps text; o integer;
  fld boolean; src_fld boolean; shuf boolean; pb boolean; pa boolean; ov record; gb integer; n integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if p_zone not in ('hand', 'deck', 'extra', 'gy', 'banish', 'mz', 'emz', 'st', 'fz', 'ovl') then raise exception 'Zona non valida'; end if;
  select * into c from public.sim_cards where game_id = g and id = p_card for update;
  if not found then raise exception 'Carta inesistente'; end if;
  if c.ctrl <> me and c.zone not in ('mz', 'emz', 'st', 'fz', 'gy', 'banish') then raise exception 'Non puoi muovere quella carta'; end if;
  fld := p_zone in ('mz', 'emz', 'st', 'fz');
  src_fld := c.zone in ('mz', 'emz', 'st', 'fz');
  to_side := case when fld then me else c.owner end;
  pb := public._sim_pub(c.zone, c.face_up, c.revealed);

  -- destinazione: zona libera sul campo
  s := null;
  if p_zone = 'ovl' then
    select * into h from public.sim_cards where game_id = g and id = p_host and zone in ('mz', 'emz');
    if not found or h.id = c.id then raise exception 'Scegli il mostro a cui allegare il materiale'; end if;
    to_side := h.ctrl;
  elsif p_zone in ('mz', 'st') then
    s := coalesce(p_slot, (select min(k) from generate_series(1, 5) k where not exists (
           select 1 from public.sim_cards x where x.game_id = g and x.ctrl = me and x.zone = p_zone and x.slot = k and x.id <> c.id)));
    if s is null then raise exception 'Nessuna zona libera'; end if;
    if s not between 1 and 5 then raise exception 'Zona non valida'; end if;
    if exists (select 1 from public.sim_cards x where x.game_id = g and x.ctrl = me and x.zone = p_zone and x.slot = s and x.id <> c.id) then raise exception 'Zona occupata'; end if;
  elsif p_zone = 'emz' then
    s := coalesce(p_slot, (select min(k) from generate_series(1, 2) k where not exists (
           select 1 from public.sim_cards x where x.game_id = g and x.zone = 'emz' and x.slot = k and x.id <> c.id)));
    if s is null then raise exception 'Nessuna zona libera'; end if;
    if s not between 1 and 2 then raise exception 'Zona non valida'; end if;
    if exists (select 1 from public.sim_cards x where x.game_id = g and x.zone = 'emz' and x.slot = s and x.id <> c.id) then raise exception 'Zona occupata'; end if;
  elsif p_zone = 'fz' then
    s := 1;
    if exists (select 1 from public.sim_cards x where x.game_id = g and x.ctrl = me and x.zone = 'fz' and x.id <> c.id) then raise exception 'Zona occupata'; end if;
  end if;

  -- posizione e faccia
  ps := null;
  if p_zone in ('mz', 'emz') then
    if c.zone in ('mz', 'emz') then ps := coalesce(p_pos, c.pos, 'atk'); f := coalesce(p_face, c.face_up);
    else ps := coalesce(p_pos, 'atk'); f := coalesce(p_face, true); end if;
    if ps not in ('atk', 'def') then raise exception 'Posizione non valida'; end if;
  elsif p_zone in ('st', 'fz') then
    f := coalesce(p_face, case when src_fld then c.face_up else true end);
  elsif p_zone = 'extra' then f := coalesce(p_face, false);
  elsif p_zone = 'banish' then f := coalesce(p_face, true);
  elsif p_zone in ('gy', 'ovl') then f := true;
  else f := false;
  end if;
  pa := public._sim_pub(p_zone, f, false);

  -- ordine nella zona di arrivo
  if p_zone = 'deck' then
    if coalesce(p_top, true) then select coalesce(max(ord), 0) + 1 into o from public.sim_cards where game_id = g and owner = c.owner and zone = 'deck' and id <> c.id;
    else select coalesce(min(ord), 1) - 1 into o from public.sim_cards where game_id = g and owner = c.owner and zone = 'deck' and id <> c.id; end if;
  else
    select coalesce(max(ord), 0) + 1 into o from public.sim_cards where game_id = g and zone = p_zone and (owner = to_side or ctrl = to_side) and id <> c.id;
  end if;

  -- mescola il deck se la carta non era in cima (ricerca) o se richiesto
  shuf := case when p_shuffle is not null then p_shuffle
               when c.zone = 'deck' and p_zone <> 'deck' then c.ord < (select max(ord) from public.sim_cards where game_id = g and owner = c.owner and zone = 'deck')
               else false end;

  -- i materiali di un mostro che lascia il campo (o diventa materiale) vanno nel Cimitero; se resta in campo lo seguono
  if c.zone in ('mz', 'emz') and exists (select 1 from public.sim_cards where game_id = g and host_id = c.id and zone = 'ovl') then
    if p_zone in ('mz', 'emz') then
      update public.sim_cards set ctrl = me where game_id = g and host_id = c.id and zone = 'ovl';
    else
      for ov in select * from public.sim_cards where game_id = g and host_id = c.id and zone = 'ovl' order by ord loop
        select coalesce(max(x.ord), 0) + 1 into gb from public.sim_cards x where x.game_id = g and x.zone = 'gy' and x.owner = ov.owner;
        update public.sim_cards set zone = 'gy', ord = gb, ctrl = ov.owner, host_id = null, face_up = true where game_id = g and id = ov.id;
      end loop;
    end if;
  end if;

  if c.code = 0 and not fld then      -- i segnalini che lasciano il campo scompaiono
    delete from public.sim_cards where game_id = g and id = c.id;
  else
    update public.sim_cards set zone = p_zone, slot = s, ord = o, pos = ps, face_up = f,
           ctrl = case when p_zone = 'ovl' then h.ctrl when fld then me else c.owner end,
           host_id = case when p_zone = 'ovl' then p_host end,
           counters = case when fld then counters else 0 end, revealed = false
     where game_id = g and id = c.id;
  end if;
  if shuf then perform public._sim_shuffle_deck(g, c.owner); end if;
  perform public._sim_log(g, me, 'move', jsonb_build_object('from', c.zone, 'fs', c.ctrl, 'to', p_zone, 'ts', to_side, 'x', case when pb or pa then c.code end,
            'f', f, 'p', ps, 'sh', shuf, 'o', c.owner));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- cambia posizione / gira una carta sul campo (solo chi la controlla)
create function public.sim_set(p_lobby bigint, p_card integer, p_pos text default null, p_face boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; c public.sim_cards%rowtype; np text; nf boolean;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into c from public.sim_cards where game_id = g and id = p_card for update;
  if not found then raise exception 'Carta inesistente'; end if;
  if c.ctrl <> me or c.zone not in ('mz', 'emz', 'st', 'fz', 'banish', 'extra') then raise exception 'Non puoi cambiare quella carta'; end if;
  np := c.pos; nf := c.face_up;
  if p_pos is not null then
    if c.zone not in ('mz', 'emz') then raise exception 'Solo i mostri hanno una posizione'; end if;
    if p_pos not in ('atk', 'def') then raise exception 'Posizione non valida'; end if;
    np := p_pos;
  end if;
  if p_face is not null then nf := p_face; end if;
  update public.sim_cards set pos = np, face_up = nf where game_id = g and id = c.id;
  perform public._sim_log(g, me, 'set', jsonb_build_object('z', c.zone, 's', c.slot, 'x', case when c.face_up or nf then c.code end, 'p', np, 'f', nf, 'wasf', c.face_up));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_counter(p_lobby bigint, p_card integer, p_delta integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; c public.sim_cards%rowtype; nn integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into c from public.sim_cards where game_id = g and id = p_card for update;
  if not found or c.ctrl <> me or c.zone not in ('mz', 'emz', 'st', 'fz') then raise exception 'Puoi mettere segnalini solo su carte che controlli sul campo'; end if;
  nn := greatest(0, least(99, c.counters + coalesce(p_delta, 0)));
  update public.sim_cards set counters = nn where game_id = g and id = c.id;
  perform public._sim_log(g, me, 'counter', jsonb_build_object('x', case when public._sim_pub(c.zone, c.face_up, false) then c.code end, 'n', nn, 'd', nn - c.counters));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_token(p_lobby bigint, p_zone text default 'mz', p_slot integer default null, p_pos text default 'atk') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; s integer; nid integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if p_zone not in ('mz', 'emz') then raise exception 'I segnalini si evocano nelle zone mostri'; end if;
  if p_pos not in ('atk', 'def') then raise exception 'Posizione non valida'; end if;
  if (select count(*) from public.sim_cards where game_id = g and owner = me and code = 0) >= 10 then raise exception 'Massimo 10 segnalini'; end if;
  if p_zone = 'mz' then
    s := coalesce(p_slot, (select min(k) from generate_series(1, 5) k where not exists (select 1 from public.sim_cards x where x.game_id = g and x.ctrl = me and x.zone = 'mz' and x.slot = k)));
    if s is null or s not between 1 and 5 then raise exception 'Nessuna zona libera'; end if;
    if exists (select 1 from public.sim_cards x where x.game_id = g and x.ctrl = me and x.zone = 'mz' and x.slot = s) then raise exception 'Zona occupata'; end if;
  else
    s := coalesce(p_slot, (select min(k) from generate_series(1, 2) k where not exists (select 1 from public.sim_cards x where x.game_id = g and x.zone = 'emz' and x.slot = k)));
    if s is null or s not between 1 and 2 then raise exception 'Nessuna zona libera'; end if;
    if exists (select 1 from public.sim_cards x where x.game_id = g and x.zone = 'emz' and x.slot = s) then raise exception 'Zona occupata'; end if;
  end if;
  select coalesce(max(id), 0) + 1 into nid from public.sim_cards where game_id = g;
  insert into public.sim_cards (game_id, id, owner, ctrl, code, zone, slot, ord, pos, face_up) values (g, nid, me, me, 0, p_zone, s, 0, p_pos, true);
  perform public._sim_log(g, me, 'token', jsonb_build_object('z', p_zone, 's', s));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_reveal(p_lobby bigint, p_card integer, p_show boolean default true) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; c public.sim_cards%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into c from public.sim_cards where game_id = g and id = p_card for update;
  if not found or c.owner <> me or c.zone <> 'hand' then raise exception 'Puoi mostrare solo carte della tua mano'; end if;
  update public.sim_cards set revealed = coalesce(p_show, true) where game_id = g and id = c.id;
  perform public._sim_log(g, me, case when coalesce(p_show, true) then 'reveal' else 'hide' end, jsonb_build_object('x', case when coalesce(p_show, true) then c.code end));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_shuffle(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  perform public._sim_shuffle_deck(g, me);
  perform public._sim_log(g, me, 'shuffle', '{}');
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- elenco del PROPRIO deck in ordine di codice (mai nell'ordine reale) per cercare una carta
create function public.sim_search(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; r jsonb;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select coalesce(jsonb_agg(jsonb_build_object('i', id, 'x', code) order by code, id), '[]') into r from public.sim_cards where game_id = g and owner = me and zone = 'deck';
  perform public._sim_log(g, me, 'search', '{}');
  perform public._sim_bump(p_lobby);
  return r;
end $$;

-- guarda le prime n carte del proprio deck (solo chi chiama le vede)
create function public.sim_peek(p_lobby bigint, p_n integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; r jsonb;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if p_n is null or p_n < 1 or p_n > 15 then raise exception 'Puoi guardare da 1 a 15 carte'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('i', id, 'x', code) order by ord desc), '[]') into r
    from (select id, code, ord from public.sim_cards where game_id = g and owner = me and zone = 'deck' order by ord desc limit p_n) t;
  perform public._sim_log(g, me, 'peek', jsonb_build_object('n', p_n));
  perform public._sim_bump(p_lobby);
  return r;
end $$;

-- rimette in cima (o in fondo) al proprio deck le carte indicate, nell'ordine dato (la prima è la più vicina alla cima)
create function public.sim_reorder(p_lobby bigint, p_ids integer[], p_bottom boolean default false) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; n integer; base integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  n := coalesce(cardinality(p_ids), 0);
  if n < 1 or n > 60 then raise exception 'Nessuna carta indicata'; end if;
  if (select count(distinct x) from unnest(p_ids) x) <> n
     or (select count(*) from public.sim_cards where game_id = g and owner = me and zone = 'deck' and id = any (p_ids)) <> n then
    raise exception 'Le carte devono essere nel tuo deck';
  end if;
  if coalesce(p_bottom, false) then
    select coalesce(min(ord), 1) into base from public.sim_cards where game_id = g and owner = me and zone = 'deck' and id <> all (p_ids);
    update public.sim_cards c set ord = base - t.k from unnest(p_ids) with ordinality as t(id, k) where c.game_id = g and c.id = t.id;
  else
    select coalesce(max(ord), 0) into base from public.sim_cards where game_id = g and owner = me and zone = 'deck' and id <> all (p_ids);
    update public.sim_cards c set ord = base + n - t.k + 1 from unnest(p_ids) with ordinality as t(id, k) where c.game_id = g and c.id = t.id;
  end if;
  perform public._sim_log(g, me, 'reorder', jsonb_build_object('n', n, 'bottom', coalesce(p_bottom, false)));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- manda le prime n carte del proprio deck nel Cimitero o tra le carte rimosse
create function public.sim_top(p_lobby bigint, p_n integer, p_zone text, p_face boolean default true) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; ids integer[]; codes jsonb; base integer; f boolean;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if p_zone not in ('gy', 'banish') then raise exception 'Destinazione non valida'; end if;
  if p_n is null or p_n < 1 or p_n > 60 then raise exception 'Quantità non valida'; end if;
  f := p_zone = 'gy' or coalesce(p_face, true);
  select array_agg(id order by ord desc) into ids from (select id, ord from public.sim_cards where game_id = g and owner = me and zone = 'deck' order by ord desc limit p_n) t;
  if ids is null then raise exception 'Il deck è vuoto'; end if;
  select coalesce(max(ord), 0) into base from public.sim_cards where game_id = g and owner = me and zone = p_zone;
  select jsonb_agg(c.code order by t.k) into codes from public.sim_cards c join unnest(ids) with ordinality t(id, k) on t.id = c.id where c.game_id = g;
  update public.sim_cards c set zone = p_zone, ord = base + t.k, face_up = f, revealed = false from unnest(ids) with ordinality t(id, k) where c.game_id = g and c.id = t.id;
  perform public._sim_log(g, me, 'top', jsonb_build_object('n', cardinality(ids), 'to', p_zone, 'f', f, 'codes', case when f then codes end));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_lp(p_lobby bigint, p_seat smallint, p_delta integer default null, p_set integer default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; gm public.sim_games%rowtype; old integer; nw integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if p_seat not in (1, 2) then raise exception 'Giocatore non valido'; end if;
  if (p_delta is null) = (p_set is null) then raise exception 'Indica una variazione oppure un valore'; end if;
  select * into gm from public.sim_games where id = g for update;
  old := case when p_seat = 1 then gm.lp_1 else gm.lp_2 end;
  nw := greatest(0, least(9999999, coalesce(p_set, old + p_delta)));
  if p_seat = 1 then update public.sim_games set lp_1 = nw where id = g; else update public.sim_games set lp_2 = nw where id = g; end if;
  perform public._sim_log(g, me, 'lp', jsonb_build_object('t', p_seat, 'from', old, 'to', nw));
  perform public._sim_check_end(g);
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_phase(p_lobby bigint, p_phase text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; gm public.sim_games%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into gm from public.sim_games where id = g;
  if gm.turn_seat <> me then raise exception 'Non è il tuo turno'; end if;
  if p_phase not in ('draw', 'standby', 'main1', 'battle', 'main2', 'end') then raise exception 'Fase non valida'; end if;
  update public.sim_games set phase = p_phase where id = g;
  perform public._sim_log(g, me, 'phase', jsonb_build_object('phase', p_phase));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_end_turn(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; gm public.sim_games%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into gm from public.sim_games where id = g;
  if gm.turn_seat <> me then raise exception 'Non è il tuo turno'; end if;
  update public.sim_games set turn_seat = 3 - me, turn_no = turn_no + 1, phase = 'draw' where id = g;
  perform public._sim_log(g, me, 'turn', jsonb_build_object('turn', gm.turn_no + 1, 'seat', 3 - me));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_coin(p_lobby bigint, p_n integer default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; r jsonb;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if p_n is null or p_n < 1 or p_n > 5 then raise exception 'Da 1 a 5 monete'; end if;
  select jsonb_agg(random() < 0.5) into r from generate_series(1, p_n);
  perform public._sim_log(g, me, 'coin', jsonb_build_object('r', r));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create function public.sim_dice(p_lobby bigint, p_n integer default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; r jsonb;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if p_n is null or p_n < 1 or p_n > 5 then raise exception 'Da 1 a 5 dadi'; end if;
  select jsonb_agg(1 + floor(random() * 6)::integer) into r from generate_series(1, p_n);
  perform public._sim_log(g, me, 'dice', jsonb_build_object('r', r));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- annuncio testuale (attivazioni, catene, messaggi)
create function public.sim_say(p_lobby bigint, p_text text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; t text := left(btrim(regexp_replace(coalesce(p_text, ''), '[[:cntrl:]]', ' ', 'g')), 140);
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if char_length(t) < 1 then raise exception 'Scrivi qualcosa'; end if;
  perform public._sim_log(g, me, 'say', jsonb_build_object('t', t));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- ---------- permessi ----------
revoke all on function public._sim_user(), public._sim_bump(bigint), public._sim_vis(text, boolean, boolean, smallint, smallint, smallint),
  public._sim_pub(text, boolean, boolean), public._sim_log(bigint, smallint, text, jsonb), public._sim_deck_check(integer[], integer[], integer[]),
  public._sim_deck_playable(integer[], integer[], integer[]), public._sim_enter(bigint, text), public._sim_shuffle_deck(bigint, smallint),
  public._sim_check_end(bigint), public._sim_state(bigint, uuid), public._sim_abandon(bigint, text), public._sim_sweep(),
  public._sim_new_game(bigint), public._sim_finish_game(bigint, integer, text), public._sim_forfeit(bigint, smallint, text)
  from public, anon, authenticated;
revoke all on function public.sim_state(bigint, bigint), public.sim_deck_save(uuid, text, integer[], integer[], integer[], boolean), public.sim_deck_delete(uuid),
  public.sim_home(), public.sim_lobby_create(text), public.sim_lobby_join(bigint), public.sim_lobby_leave(bigint), public.sim_lobby_kick(bigint),
  public.sim_set_deck(bigint, uuid), public.sim_set_ready(bigint, boolean), public.sim_start(bigint), public.sim_choose_first(bigint, smallint),
  public.sim_concede(bigint), public.sim_confirm_end(bigint), public.sim_dismiss_end(bigint), public.sim_propose(bigint, text, text), public.sim_respond(bigint, boolean),
  public.sim_side(bigint, integer[], integer[], integer[]), public.sim_draw(bigint, integer),
  public.sim_move(bigint, integer, text, integer, text, boolean, boolean, integer, boolean), public.sim_set(bigint, integer, text, boolean),
  public.sim_counter(bigint, integer, integer), public.sim_token(bigint, text, integer, text), public.sim_reveal(bigint, integer, boolean),
  public.sim_shuffle(bigint), public.sim_search(bigint), public.sim_peek(bigint, integer), public.sim_reorder(bigint, integer[], boolean),
  public.sim_top(bigint, integer, text, boolean), public.sim_lp(bigint, smallint, integer, integer), public.sim_phase(bigint, text), public.sim_end_turn(bigint),
  public.sim_coin(bigint, integer), public.sim_dice(bigint, integer), public.sim_say(bigint, text), public.admin_set_module(text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.sim_state(bigint, bigint), public.sim_deck_save(uuid, text, integer[], integer[], integer[], boolean), public.sim_deck_delete(uuid),
  public.sim_home(), public.sim_lobby_create(text), public.sim_lobby_join(bigint), public.sim_lobby_leave(bigint), public.sim_lobby_kick(bigint),
  public.sim_set_deck(bigint, uuid), public.sim_set_ready(bigint, boolean), public.sim_start(bigint), public.sim_choose_first(bigint, smallint),
  public.sim_concede(bigint), public.sim_confirm_end(bigint), public.sim_dismiss_end(bigint), public.sim_propose(bigint, text, text), public.sim_respond(bigint, boolean),
  public.sim_side(bigint, integer[], integer[], integer[]), public.sim_draw(bigint, integer),
  public.sim_move(bigint, integer, text, integer, text, boolean, boolean, integer, boolean), public.sim_set(bigint, integer, text, boolean),
  public.sim_counter(bigint, integer, integer), public.sim_token(bigint, text, integer, text), public.sim_reveal(bigint, integer, boolean),
  public.sim_shuffle(bigint), public.sim_search(bigint), public.sim_peek(bigint, integer), public.sim_reorder(bigint, integer[], boolean),
  public.sim_top(bigint, integer, text, boolean), public.sim_lp(bigint, smallint, integer, integer), public.sim_phase(bigint, text), public.sim_end_turn(bigint),
  public.sim_coin(bigint, integer), public.sim_dice(bigint, integer), public.sim_say(bigint, text), public.admin_set_module(text, boolean, text)
  to authenticated;
commit;
