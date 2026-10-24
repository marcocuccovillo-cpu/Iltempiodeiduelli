-- ANNULLAMENTO DI «CHAT E SEGNALI» del Duel Simulator: cancella SOLO la chat e i segnali Penso/OK
-- (i messaggi vanno persi) e rimette sim_state() com'era nella migrazione del Duel Simulator.
-- Non tocca carte, deck, lobby, Ladder, Black Market, BC, XP, taglie o notifiche.
begin;
drop function if exists public.sim_chat_send(bigint, text), public.sim_signal(bigint, text), public.sim_shuffle_hand(bigint);
create or replace function public._sim_state(p_lobby bigint, p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
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

drop table if exists public.sim_chat;
alter table public.sim_players drop constraint if exists sim_players_sig_chk;
alter table public.sim_players drop column if exists sig, drop column if exists sig_at, drop column if exists sig_n;
commit;
