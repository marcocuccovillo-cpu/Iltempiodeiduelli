-- =====================================================================
-- DUEL SIMULATOR — DICHIARARE GLI EFFETTI E CONCATENARLI IN «CATENE»
-- (da eseguire DOPO black-market-duel-simulator.sql e black-market-duel-simulator-chat.sql)
--
-- Aggiunge, SOLO dentro il Duel Simulator:
--  * sim_activate: dichiara l'effetto di una TUA carta (mano, campo, Cimitero, carte rimosse). Diventa un «anello» della catena
--    (Catena 1, Catena 2, …, al massimo 12). Il nome della carta diventa pubblico per entrambi (è lo scopo della dichiarazione);
--    una carta coperta sul campo si scopre. Nessuna carta cambia zona: spostarle resta compito dei giocatori.
--  * sim_chain_resolve: risolve l'ultimo anello non ancora risolto (si risolve al contrario: l'ultimo dichiarato per primo);
--    risolti tutti gli anelli la catena si chiude da sola. Può farlo uno qualunque dei due giocatori.
--  * sim_chain_clear: annulla l'intera catena (errore di dichiarazione).
--  * lo stato della partita porta la catena aperta; il codice della carta dichiarata è pubblico, l'identificativo della carta solo se è
--    visibile a entrambi (una carta dichiarata dalla mano non può essere ricollegata a quando verrà giocata coperta).
-- Nessuna regola automatica: il simulatore non controlla se la catena è legale. Non tocca Ladder, Black Market, BC, XP, taglie o notifiche.
-- Con il modulo «duel» spento le funzioni rifiutano l'operazione. Si può rieseguire.
-- Annullamento: black-market-duel-simulator-catene-down.sql
-- =====================================================================
begin;

create table if not exists public.sim_chain (
  game_id bigint not null references public.sim_games(id) on delete cascade,
  n smallint not null check (n between 1 and 12),
  seat smallint not null check (seat in (1,2)),
  card_id integer,
  code integer not null check (code > 0),
  resolved boolean not null default false,
  at timestamptz not null default now(),
  primary key (game_id, n)
);
alter table public.sim_chain enable row level security;
revoke all on public.sim_chain from public, anon, authenticated;

-- stato della partita: aggiunge la catena aperta (mantiene chat e segnali)
create or replace function public._sim_state(p_lobby bigint, p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.sim_lobbies%rowtype; me smallint; g public.sim_games%rowtype; pl jsonb; cards jsonb := '[]'; cnt jsonb := '{}'; lg jsonb := '[]'; gm jsonb := null; hist jsonb; cfg jsonb := null; chat jsonb := '[]'; gst timestamptz; chn jsonb := '[]';
begin
  select * into l from public.sim_lobbies where id = p_lobby;
  select seat into me from public.sim_players where lobby_id = p_lobby and user_id = p_user;
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
      select coalesce(jsonb_agg(jsonb_build_object('n', k.n, 'seat', k.seat, 'x', k.code, 'res', k.resolved,
               'i', (select c.id from public.sim_cards c where c.game_id = k.game_id and c.id = k.card_id and public._sim_pub(c.zone, c.face_up, c.revealed))) order by k.n), '[]')
        into chn from public.sim_chain k where k.game_id = g.id;
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.n), '[]') into lg
      from (select n, seat, kind, data from public.sim_log where game_id = g.id order by n desc limit 100) x;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('n', x.n, 'seat', x.seat, 't', x.body, 'ts', extract(epoch from x.at)::bigint) order by x.n), '[]') into chat
    from (select n, seat, body, at from public.sim_chat where lobby_id = p_lobby order by n desc limit 80) x;
  return jsonb_build_object('v', l.ver, 'lobby', jsonb_build_object('id', l.id, 'title', l.title, 'status', l.status, 'game_no', l.game_no,
           'wins', jsonb_build_array(l.wins_1, l.wins_2), 'winner', l.winner_seat, 'end_reason', l.end_reason, 'chooser', l.chooser_seat, 'host_id', l.host_id),
         'me', jsonb_build_object('seat', me, 'user_id', p_user, 'cfg', cfg), 'players', pl, 'game', gm, 'games', hist,
         'cards', cards, 'counts', cnt, 'log', lg, 'chat', chat, 'chain', chn);
end $$;


create or replace function public.sim_activate(p_lobby bigint, p_card integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; c public.sim_cards%rowtype; nn integer; flip boolean := false;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into c from public.sim_cards where game_id = g and id = p_card for update;
  if not found then raise exception 'Carta inesistente'; end if;
  if c.code = 0 then raise exception 'I segnalini non hanno effetti da dichiarare'; end if;
  if c.zone in ('mz', 'emz', 'st', 'fz') then
    if c.ctrl <> me then raise exception 'Puoi dichiarare solo effetti delle tue carte'; end if;
  elsif c.zone in ('hand', 'gy', 'banish') then
    if c.owner <> me then raise exception 'Puoi dichiarare solo effetti delle tue carte'; end if;
  else
    raise exception 'Da qui non puoi dichiarare un effetto';
  end if;
  select coalesce(max(n), 0) + 1 into nn from public.sim_chain where game_id = g;
  if nn > 12 then raise exception 'La catena ha già 12 anelli: risolvila o annullala'; end if;
  if c.zone in ('mz', 'emz', 'st', 'fz') and not c.face_up then
    update public.sim_cards set face_up = true where game_id = g and id = c.id;
    flip := true;
  end if;
  insert into public.sim_chain (game_id, n, seat, card_id, code) values (g, nn, me, c.id, c.code);
  perform public._sim_log(g, me, 'activate', jsonb_build_object('x', c.code, 'n', nn, 'z', c.zone, 'fl', flip));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create or replace function public.sim_chain_resolve(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; k public.sim_chain%rowtype;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into k from public.sim_chain where game_id = g and not resolved order by n desc limit 1;
  if not found then raise exception 'Non c''è nessuna catena da risolvere'; end if;
  update public.sim_chain set resolved = true where game_id = g and n = k.n;
  perform public._sim_log(g, me, 'chain_res', jsonb_build_object('n', k.n, 'x', k.code));
  if not exists (select 1 from public.sim_chain where game_id = g and not resolved) then
    delete from public.sim_chain where game_id = g;
    perform public._sim_log(g, me, 'chain_end', '{}');
  end if;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create or replace function public.sim_chain_clear(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if not exists (select 1 from public.sim_chain where game_id = g) then raise exception 'Non c''è nessuna catena'; end if;
  delete from public.sim_chain where game_id = g;
  perform public._sim_log(g, me, 'chain_clear', '{}');
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

revoke all on function public.sim_activate(bigint, integer), public.sim_chain_resolve(bigint), public.sim_chain_clear(bigint) from public, anon, authenticated;
grant execute on function public.sim_activate(bigint, integer), public.sim_chain_resolve(bigint), public.sim_chain_clear(bigint) to authenticated;
commit;
