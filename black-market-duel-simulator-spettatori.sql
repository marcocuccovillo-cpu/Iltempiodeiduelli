-- =====================================================================
-- DUEL SIMULATOR — SPETTATORI
-- (da eseguire DOPO black-market-duel-simulator.sql, ...-chat.sql, ...-catene.sql e ...-attacchi.sql)
--
-- Aggiunge, SOLO dentro il Duel Simulator:
--  * un utente può entrare come SPETTATORE in una partita già avviata (lobby in side deck o in gioco), se i giocatori non
--    l'hanno chiusa agli spettatori. Max 8 spettatori per partita (impostazione sim_max_spectators). Non si può guardare
--    una partita mentre si gioca in un'altra: entrando come giocatore da qualche parte si esce dalle partite guardate.
--  * DI DEFAULT lo spettatore vede solo il tavolo come lo vedrebbe un osservatore neutro: carte scoperte, cimiteri, carte
--    rimosse scoperte, punti vita, registro, catena e bersagli. NON vede mano, deck, extra deck coperto né carte coperte
--    sul campo: questi dati non gli arrivano nemmeno dal database (filtro lato server, non solo grafico).
--  * può scrivere nella chat della partita (messaggi con il suo nome, fino a 12 al minuto).
--  * ogni GIOCATORE può dare il permesso (solo sulle PROPRIE carte) a un singolo spettatore o a tutti gli spettatori:
--    «mano» (1), «carte coperte sul campo e nei cimiteri» (2), «deck ed extra deck» (4), in qualunque combinazione.
--    Il permesso si toglie in qualsiasi momento; uscendo, lo spettatore perde i permessi. Ogni concessione compare nel registro
--    pubblico, e chi gioca vede sempre chi ha il permesso (trasparenza: nessuno guarda di nascosto).
--  * ogni giocatore può cacciare uno spettatore (non può più rientrare in quella partita) o chiudere la partita agli spettatori.
--  * gli spettatori NON possono compiere nessuna azione di gioco: tutte le funzioni di gioco restano riservate ai due giocatori.
--
-- Limite noto (da conoscere): uno spettatore a cui sia stata mostrata la mano può riferirla nella chat, che è condivisa. È la
-- stessa fiducia che c'è a un tavolo vero: per questo il permesso lo concede il giocatore, a chi vuole, ed è visibile a tutti.
--
-- Non tocca Ladder, Black Market, BC, XP, taglie o notifiche. Con il modulo «duel» spento le funzioni rifiutano l'operazione.
-- Si può rieseguire. Annullamento: black-market-duel-simulator-spettatori-down.sql
-- =====================================================================
begin;

insert into public.system_settings (key, value_int, description) values
 ('sim_max_spectators', 8, 'Duel Simulator: spettatori massimi per ogni partita')
on conflict (key) do nothing;

-- ---------- tabelle ----------
alter table public.sim_lobbies add column if not exists allow_spec boolean not null default true;
alter table public.sim_players add column if not exists spec_all smallint not null default 0;
alter table public.sim_players drop constraint if exists sim_players_spec_all_chk;
alter table public.sim_players add constraint sim_players_spec_all_chk check (spec_all between 0 and 7);

create table if not exists public.sim_spectators (
  lobby_id bigint not null references public.sim_lobbies(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (lobby_id, user_id),
  unique (user_id)
);
create table if not exists public.sim_spec_grants (
  lobby_id bigint not null,
  seat smallint not null check (seat in (1, 2)),
  user_id uuid not null,
  mask smallint not null check (mask between 1 and 7),
  primary key (lobby_id, seat, user_id),
  foreign key (lobby_id, user_id) references public.sim_spectators(lobby_id, user_id) on delete cascade
);
create table if not exists public.sim_spec_bans (
  lobby_id bigint not null references public.sim_lobbies(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (lobby_id, user_id)
);
alter table public.sim_spectators enable row level security;
alter table public.sim_spec_grants enable row level security;
alter table public.sim_spec_bans enable row level security;
revoke all on public.sim_spectators, public.sim_spec_grants, public.sim_spec_bans from public, anon, authenticated;

-- la chat accetta anche i messaggi degli spettatori (seat 0 + autore)
alter table public.sim_chat add column if not exists user_id uuid references public.profiles(id) on delete cascade;
alter table public.sim_chat drop constraint if exists sim_chat_seat_check;
alter table public.sim_chat add constraint sim_chat_seat_check check (seat in (0, 1, 2));
alter table public.sim_chat drop constraint if exists sim_chat_spec_chk;
alter table public.sim_chat add constraint sim_chat_spec_chk check ((seat = 0) = (user_id is not null));

-- chi diventa giocatore smette di essere spettatore
create or replace function public._sim_spec_clear() returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.sim_spectators where user_id = new.user_id;
  return new;
end $$;
drop trigger if exists sim_players_clear_spec on public.sim_players;
create trigger sim_players_clear_spec after insert on public.sim_players for each row execute function public._sim_spec_clear();

-- ---------- funzioni interne ----------
-- permessi effettivi di uno spettatore sul giocatore di quel posto: bit 1 mano, 2 campo coperto, 4 deck
create or replace function public._sim_mask(p_lobby bigint, p_user uuid, p_seat smallint) returns smallint language sql stable security definer set search_path = public as $$
  select (coalesce((select g.mask from public.sim_spec_grants g where g.lobby_id = p_lobby and g.seat = p_seat and g.user_id = p_user), 0)
          | coalesce((select sp.spec_all from public.sim_players sp where sp.lobby_id = p_lobby and sp.seat = p_seat), 0))::smallint $$;

-- visibilità di una carta data la maschera di permessi sui due posti (il giocatore vede tutto il PROPRIO = 7)
create or replace function public._sim_vis_m(p_zone text, p_face boolean, p_rev boolean, p_owner smallint, p_ctrl smallint, p_mk1 smallint, p_mk2 smallint)
returns boolean language sql immutable as $$
  select case p_zone
    when 'deck'  then ((case p_owner when 1 then p_mk1 else p_mk2 end) & 4) <> 0
    when 'hand'  then p_rev or ((case p_owner when 1 then p_mk1 else p_mk2 end) & 1) <> 0
    when 'extra' then p_face or ((case p_owner when 1 then p_mk1 else p_mk2 end) & 4) <> 0
    when 'mz'    then p_face or ((case p_ctrl when 1 then p_mk1 else p_mk2 end) & 2) <> 0
    when 'emz'   then p_face or ((case p_ctrl when 1 then p_mk1 else p_mk2 end) & 2) <> 0
    when 'st'    then p_face or ((case p_ctrl when 1 then p_mk1 else p_mk2 end) & 2) <> 0
    when 'fz'    then p_face or ((case p_ctrl when 1 then p_mk1 else p_mk2 end) & 2) <> 0
    else p_face or ((case p_owner when 1 then p_mk1 else p_mk2 end) & 2) <> 0   -- gy, banish, ovl
  end $$;

-- come _sim_bump ma senza «tenere sveglia» la partita: le azioni degli spettatori non devono rimandare l'abbandono
create or replace function public._sim_bump_ver(p_lobby bigint) returns void language sql security definer set search_path = public as $$
  update public.sim_lobbies set ver = ver + 1 where id = p_lobby $$;

-- ---------- stato del tavolo (giocatori e spettatori) ----------
create or replace function public._sim_state(p_lobby bigint, p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.sim_lobbies%rowtype; me smallint; g public.sim_games%rowtype; pl jsonb; cards jsonb := '[]'; cnt jsonb := '{}'; lg jsonb := '[]'; gm jsonb := null; hist jsonb; cfg jsonb := null; chat jsonb := '[]'; gst timestamptz; chn jsonb := '[]'; tgt jsonb := '[]';
  mk1 smallint; mk2 smallint; deckv jsonb := '{}'; spc jsonb;
begin
  select * into l from public.sim_lobbies where id = p_lobby;
  select seat into me from public.sim_players where lobby_id = p_lobby and user_id = p_user;
  if me is not null then
    mk1 := case when me = 1 then 7 else 0 end; mk2 := case when me = 2 then 7 else 0 end;
  else
    mk1 := public._sim_mask(p_lobby, p_user, 1::smallint); mk2 := public._sim_mask(p_lobby, p_user, 2::smallint);
  end if;
  select started_at into gst from public.sim_games where lobby_id = p_lobby and no = l.game_no;
  select coalesce(jsonb_agg(jsonb_build_object('seat', sp.seat, 'user_id', sp.user_id, 'nickname', pr.nickname, 'avatar', pr.avatar,
           'ready', sp.ready, 'deck_set', sp.deck_id is not null, 'active', sp.active,
           'sig', case when sp.sig_at is null or (gst is not null and sp.sig_at < gst) then null
                       when sp.sig = 'think' and now() - sp.sig_at < interval '5 minutes' then 'think'
                       when sp.sig = 'ok' and now() - sp.sig_at < interval '12 seconds' then 'ok' end,
           'sig_age', case when sp.sig_at is not null then floor(extract(epoch from now() - sp.sig_at))::integer end, 'sig_n', sp.sig_n,
           'deck_id', case when sp.seat = me then sp.deck_id end, 'deck_name', case when sp.seat = me then d.name end,
           'deck_main', case when sp.seat = me then cardinality(d.main) end) order by sp.seat), '[]')
    into pl
    from public.sim_players sp join public.profiles pr on pr.id = sp.user_id left join public.sim_decks d on d.id = sp.deck_id
    where sp.lobby_id = p_lobby;
  if l.status = 'siding' and me is not null then
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
               'x', case when public._sim_vis_m(c.zone, c.face_up, c.revealed, c.owner, c.ctrl, mk1, mk2) then c.code end) order by c.zone, c.ord), '[]')
        into cards
        from public.sim_cards c
        where c.game_id = g.id and c.zone <> 'deck'
          and (c.zone <> 'hand' or c.revealed or ((case c.owner when 1 then mk1 else mk2 end) & 1) <> 0)
          and (c.zone <> 'extra' or c.face_up or ((case c.owner when 1 then mk1 else mk2 end) & 4) <> 0);
      select coalesce(jsonb_object_agg(q.owner::text, q.cnt), '{}') into cnt from (
        select owner, jsonb_build_object('deck', count(*) filter (where zone = 'deck'), 'hand', count(*) filter (where zone = 'hand'),
          'extra', count(*) filter (where zone = 'extra'), 'gy', count(*) filter (where zone = 'gy'), 'banish', count(*) filter (where zone = 'banish')) cnt
        from public.sim_cards where game_id = g.id group by owner) q;
      select coalesce(jsonb_agg(jsonb_build_object('n', k.n, 'seat', k.seat, 'x', k.code, 'res', k.resolved,
               'i', (select c.id from public.sim_cards c where c.game_id = k.game_id and c.id = k.card_id and public._sim_pub(c.zone, c.face_up, c.revealed))) order by k.n), '[]')
        into chn from public.sim_chain k where k.game_id = g.id;
      select coalesce(jsonb_agg(jsonb_build_object('i', t.card_id, 'seat', t.seat, 'z', t.zone) order by t.at, t.card_id), '[]')
        into tgt from public.sim_target t join public.sim_cards c on c.game_id = t.game_id and c.id = t.card_id
        where t.game_id = g.id and t.turn = g.turn_no and c.zone = t.zone;
      -- l'ordine del deck lo riceve SOLO uno spettatore col permesso «deck» su quel giocatore (cima per prima)
      if me is null then
        select coalesce(jsonb_object_agg(q.owner::text, q.codes), '{}') into deckv from (
          select c.owner, jsonb_agg(c.code order by c.ord desc, c.id) codes from public.sim_cards c
          where c.game_id = g.id and c.zone = 'deck' and ((case c.owner when 1 then mk1 else mk2 end) & 4) <> 0 group by c.owner) q;
      end if;
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.n), '[]') into lg
      from (select n, seat, kind, data from public.sim_log where game_id = g.id order by n desc limit 100) x;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('n', x.n, 'seat', x.seat, 't', x.body, 'ts', extract(epoch from x.at)::bigint, 'u', x.nick, 'uid', x.uid) order by x.n), '[]') into chat
    from (select c.n, c.seat, c.body, c.at, case when c.seat = 0 then pr.nickname end as nick, c.user_id as uid
          from public.sim_chat c left join public.profiles pr on pr.id = c.user_id where c.lobby_id = p_lobby order by c.n desc limit 80) x;
  select jsonb_build_object('open', l.allow_spec, 'max', coalesce(public._setting('sim_max_spectators'), 8),
           'all', jsonb_build_array(coalesce((select spec_all from public.sim_players where lobby_id = p_lobby and seat = 1), 0),
                                    coalesce((select spec_all from public.sim_players where lobby_id = p_lobby and seat = 2), 0)),
           'list', coalesce((select jsonb_agg(jsonb_build_object('u', s.user_id, 'nickname', pr.nickname, 'avatar', pr.avatar,
                      'g', jsonb_build_array(coalesce((select mask from public.sim_spec_grants x where x.lobby_id = s.lobby_id and x.seat = 1 and x.user_id = s.user_id), 0),
                                             coalesce((select mask from public.sim_spec_grants x where x.lobby_id = s.lobby_id and x.seat = 2 and x.user_id = s.user_id), 0)))
                      order by s.joined_at, s.user_id)
                    from public.sim_spectators s join public.profiles pr on pr.id = s.user_id where s.lobby_id = p_lobby), '[]'))
    into spc;
  return jsonb_build_object('v', l.ver, 'lobby', jsonb_build_object('id', l.id, 'title', l.title, 'status', l.status, 'game_no', l.game_no,
           'wins', jsonb_build_array(l.wins_1, l.wins_2), 'winner', l.winner_seat, 'end_reason', l.end_reason, 'chooser', l.chooser_seat, 'host_id', l.host_id),
         'me', jsonb_build_object('seat', me, 'user_id', p_user, 'cfg', cfg, 'spec', me is null, 'mk', case when me is null then jsonb_build_array(mk1, mk2) end),
         'players', pl, 'game', gm, 'games', hist,
         'cards', cards, 'counts', cnt, 'log', lg, 'chat', chat, 'chain', chn, 'targets', tgt, 'deckv', deckv, 'spec', spc);
end $$;

-- lo stato lo può chiedere chi gioca e chi guarda
create or replace function public.sim_state(p_lobby bigint, p_since bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user(); cur bigint;
begin
  if not exists (select 1 from public.sim_players where lobby_id = p_lobby and user_id = v)
     and not exists (select 1 from public.sim_spectators where lobby_id = p_lobby and user_id = v) then
    raise exception 'Non partecipi a questa partita';
  end if;
  select l.ver into cur from public.sim_lobbies l where l.id = p_lobby;
  if p_since is not null and p_since = cur then return jsonb_build_object('same', true, 'v', cur); end if;
  return public._sim_state(p_lobby, v);
end $$;

-- ---------- spettatore: entra, esce, scrive ----------
create or replace function public.sim_watch_join(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user(); l public.sim_lobbies%rowtype;
begin
  select * into l from public.sim_lobbies where id = p_lobby for update;
  if not found then raise exception 'Lobby inesistente'; end if;
  if exists (select 1 from public.sim_players where user_id = v and active) then raise exception 'Stai giocando una partita: non puoi guardarne un’altra'; end if;
  if exists (select 1 from public.sim_players where lobby_id = p_lobby and user_id = v) then raise exception 'Sei uno dei giocatori di questa partita'; end if;
  if exists (select 1 from public.sim_spectators where lobby_id = p_lobby and user_id = v) then return public._sim_state(p_lobby, v); end if;
  if l.status not in ('siding', 'playing') then raise exception 'Si può guardare solo una partita in corso'; end if;
  if not l.allow_spec then raise exception 'I giocatori hanno chiuso la partita agli spettatori'; end if;
  if exists (select 1 from public.sim_spec_bans where lobby_id = p_lobby and user_id = v) then raise exception 'Sei stato allontanato da questa partita'; end if;
  if (select count(*) from public.sim_spectators where lobby_id = p_lobby) >= coalesce(public._setting('sim_max_spectators'), 8) then raise exception 'Ci sono già troppi spettatori'; end if;
  delete from public.sim_spectators where user_id = v;            -- una sola partita guardata alla volta
  insert into public.sim_spectators (lobby_id, user_id) values (p_lobby, v);
  perform public._sim_bump_ver(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create or replace function public.sim_watch_leave(p_lobby bigint) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user();
begin
  if exists (select 1 from public.sim_spectators where lobby_id = p_lobby and user_id = v) then
    delete from public.sim_spectators where lobby_id = p_lobby and user_id = v;
    perform public._sim_bump_ver(p_lobby);
  end if;
end $$;

create or replace function public.sim_watch_say(p_lobby bigint, p_text text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user(); l public.sim_lobbies%rowtype; nn integer; t text := left(btrim(regexp_replace(coalesce(p_text, ''), '[[:cntrl:]]', ' ', 'g')), 200);
begin
  select * into l from public.sim_lobbies where id = p_lobby for update;
  if not found then raise exception 'Lobby inesistente'; end if;
  if not exists (select 1 from public.sim_spectators where lobby_id = p_lobby and user_id = v) then raise exception 'Non sei tra gli spettatori'; end if;
  if l.status not in ('siding', 'playing', 'finished') then raise exception 'La partita è chiusa'; end if;
  if char_length(t) < 1 then raise exception 'Scrivi qualcosa'; end if;
  if (select count(*) from public.sim_chat where lobby_id = p_lobby and user_id = v and at > now() - interval '1 minute') >= 12 then
    raise exception 'Troppi messaggi: aspetta qualche secondo';
  end if;
  select coalesce(max(n), 0) + 1 into nn from public.sim_chat where lobby_id = p_lobby;
  insert into public.sim_chat (lobby_id, n, seat, user_id, body) values (p_lobby, nn, 0, v, t);
  delete from public.sim_chat where lobby_id = p_lobby and n <= nn - 200;
  perform public._sim_bump_ver(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- ---------- giocatore: permessi, espulsione, chiusura ----------
-- p_spectator nullo = tutti gli spettatori (anche quelli che entreranno); p_mask 0 = toglie il permesso. Vale per il TUO posto.
create or replace function public.sim_spec_grant(p_lobby bigint, p_spectator uuid, p_mask integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; l public.sim_lobbies%rowtype; nm text; gid bigint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'any');
  if p_mask is null or p_mask < 0 or p_mask > 7 then raise exception 'Permesso non valido'; end if;
  select * into l from public.sim_lobbies where id = p_lobby;
  if l.status not in ('siding', 'playing') then raise exception 'La partita non è in corso'; end if;
  if p_spectator is null then
    update public.sim_players set spec_all = p_mask where lobby_id = p_lobby and seat = me;
  else
    select pr.nickname into nm from public.sim_spectators s join public.profiles pr on pr.id = s.user_id where s.lobby_id = p_lobby and s.user_id = p_spectator;
    if not found then raise exception 'Quello spettatore non c’è più'; end if;
    if p_mask = 0 then
      delete from public.sim_spec_grants where lobby_id = p_lobby and seat = me and user_id = p_spectator;
    else
      insert into public.sim_spec_grants (lobby_id, seat, user_id, mask) values (p_lobby, me, p_spectator, p_mask)
        on conflict (lobby_id, seat, user_id) do update set mask = excluded.mask;
    end if;
  end if;
  select id into gid from public.sim_games where lobby_id = p_lobby and no = l.game_no;
  if gid is not null then
    perform public._sim_log(gid, me, 'spec', jsonb_build_object('n', nm, 'm', p_mask, 'all', p_spectator is null));
  end if;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create or replace function public.sim_spec_kick(p_lobby bigint, p_spectator uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'any');
  if not exists (select 1 from public.sim_spectators where lobby_id = p_lobby and user_id = p_spectator) then raise exception 'Quello spettatore non c’è più'; end if;
  delete from public.sim_spectators where lobby_id = p_lobby and user_id = p_spectator;
  insert into public.sim_spec_bans (lobby_id, user_id) values (p_lobby, p_spectator) on conflict do nothing;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- chiude (o riapre) la partita agli spettatori; chiudendo, chi sta guardando viene fatto uscire
create or replace function public.sim_spec_open(p_lobby bigint, p_open boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'any');
  if p_open is null then raise exception 'Scelta non valida'; end if;
  update public.sim_lobbies set allow_spec = p_open where id = p_lobby;
  if not p_open then
    delete from public.sim_spectators where lobby_id = p_lobby;
    update public.sim_players set spec_all = 0 where lobby_id = p_lobby;
  end if;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- ---------- elenco della home: partite da guardare e partita che sto guardando ----------
create or replace function public.sim_home() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._sim_user(); mine bigint; watching bigint;
begin
  perform public._sim_sweep();
  delete from public.sim_spectators s using public.sim_lobbies l where s.user_id = v and l.id = s.lobby_id and l.status in ('finished', 'cancelled');
  select lobby_id into mine from public.sim_players where user_id = v and active;
  select lobby_id into watching from public.sim_spectators where user_id = v;
  return jsonb_build_object(
    'mine', mine,
    'watching', watching,
    'max_decks', coalesce(public._setting('sim_max_decks'), 30),
    'decks', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'main', d.main, 'extra', d.extra, 'side', d.side, 'updated_at', d.updated_at) order by d.updated_at desc), '[]')
              from public.sim_decks d where d.owner_id = v and not d.temp),
    'temp_decks', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'main', cardinality(d.main), 'extra', cardinality(d.extra), 'side', cardinality(d.side)) order by d.created_at desc), '[]')
              from (select * from public.sim_decks where owner_id = v and temp order by created_at desc limit 5) d),
    'lobbies', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'title', l.title, 'host_id', l.host_id, 'nickname', p.nickname, 'avatar', p.avatar, 'created_at', l.created_at) order by l.created_at desc), '[]')
                from public.sim_lobbies l join public.profiles p on p.id = l.host_id
                where l.status = 'lobby' and (select count(*) from public.sim_players sp where sp.lobby_id = l.id) = 1 and l.host_id <> v and not p.suspended),
    'live', (select coalesce(jsonb_agg(x order by x.updated_at desc), '[]') from (
                select l.id, l.title, l.status, l.game_no, l.wins_1, l.wins_2, l.updated_at,
                  (select count(*) from public.sim_spectators s where s.lobby_id = l.id) as watchers,
                  (select jsonb_agg(jsonb_build_object('seat', sp.seat, 'nickname', pr.nickname, 'avatar', pr.avatar) order by sp.seat)
                     from public.sim_players sp join public.profiles pr on pr.id = sp.user_id where sp.lobby_id = l.id) as players
                from public.sim_lobbies l
                where l.status in ('siding', 'playing') and l.allow_spec
                  and not exists (select 1 from public.sim_players me where me.lobby_id = l.id and me.user_id = v)
                  and not exists (select 1 from public.sim_spec_bans b where b.lobby_id = l.id and b.user_id = v)
                order by l.updated_at desc limit 20) x),
    'recent', (select coalesce(jsonb_agg(x order by x.finished_at desc), '[]') from (
                select l.id, l.status, l.wins_1, l.wins_2, l.winner_seat, l.end_reason, l.finished_at, me.seat as my_seat, op.nickname as opponent
                from public.sim_players me join public.sim_lobbies l on l.id = me.lobby_id
                left join public.sim_players ops on ops.lobby_id = l.id and ops.seat <> me.seat
                left join public.profiles op on op.id = ops.user_id
                where me.user_id = v and l.status = 'finished' order by l.finished_at desc limit 5) x));
end $$;

-- ---------- permessi ----------
revoke all on function public._sim_spec_clear(), public._sim_mask(bigint, uuid, smallint),
  public._sim_vis_m(text, boolean, boolean, smallint, smallint, smallint, smallint), public._sim_bump_ver(bigint) from public, anon, authenticated;
revoke all on function public.sim_watch_join(bigint), public.sim_watch_leave(bigint), public.sim_watch_say(bigint, text),
  public.sim_spec_grant(bigint, uuid, integer), public.sim_spec_kick(bigint, uuid), public.sim_spec_open(bigint, boolean) from public, anon, authenticated;
grant execute on function public.sim_watch_join(bigint), public.sim_watch_leave(bigint), public.sim_watch_say(bigint, text),
  public.sim_spec_grant(bigint, uuid, integer), public.sim_spec_kick(bigint, uuid), public.sim_spec_open(bigint, boolean) to authenticated;
commit;
