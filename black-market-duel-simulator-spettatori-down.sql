-- ANNULLAMENTO DI «SPETTATORI» del Duel Simulator: cancella SOLO spettatori, permessi, divieti e i loro messaggi in chat,
-- e rimette _sim_state(), sim_state() e sim_home() com'erano dopo gli attacchi.
-- Non tocca carte, deck, lobby, chat dei giocatori, catene, bersagli, Ladder, Black Market, BC, XP, taglie o notifiche.
begin;
drop trigger if exists sim_players_clear_spec on public.sim_players;
drop function if exists public.sim_watch_join(bigint), public.sim_watch_leave(bigint), public.sim_watch_say(bigint, text),
  public.sim_spec_grant(bigint, uuid, integer), public.sim_spec_kick(bigint, uuid), public.sim_spec_open(bigint, boolean);

create or replace function public._sim_state(p_lobby bigint, p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l public.sim_lobbies%rowtype; me smallint; g public.sim_games%rowtype; pl jsonb; cards jsonb := '[]'; cnt jsonb := '{}'; lg jsonb := '[]'; gm jsonb := null; hist jsonb; cfg jsonb := null; chat jsonb := '[]'; gst timestamptz; chn jsonb := '[]'; tgt jsonb := '[]';
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
      select coalesce(jsonb_agg(jsonb_build_object('i', t.card_id, 'seat', t.seat, 'z', t.zone) order by t.at, t.card_id), '[]')
        into tgt from public.sim_target t join public.sim_cards c on c.game_id = t.game_id and c.id = t.card_id
        where t.game_id = g.id and t.turn = g.turn_no and c.zone = t.zone;
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.n), '[]') into lg
      from (select n, seat, kind, data from public.sim_log where game_id = g.id order by n desc limit 100) x;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('n', x.n, 'seat', x.seat, 't', x.body, 'ts', extract(epoch from x.at)::bigint) order by x.n), '[]') into chat
    from (select n, seat, body, at from public.sim_chat where lobby_id = p_lobby order by n desc limit 80) x;
  return jsonb_build_object('v', l.ver, 'lobby', jsonb_build_object('id', l.id, 'title', l.title, 'status', l.status, 'game_no', l.game_no,
           'wins', jsonb_build_array(l.wins_1, l.wins_2), 'winner', l.winner_seat, 'end_reason', l.end_reason, 'chooser', l.chooser_seat, 'host_id', l.host_id),
         'me', jsonb_build_object('seat', me, 'user_id', p_user, 'cfg', cfg), 'players', pl, 'game', gm, 'games', hist,
         'cards', cards, 'counts', cnt, 'log', lg, 'chat', chat, 'chain', chn, 'targets', tgt);
end $function$;

create or replace function public.sim_state(p_lobby bigint, p_since bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v uuid := public._sim_user(); cur bigint;
begin
  if not exists (select 1 from public.sim_players where lobby_id = p_lobby and user_id = v) then raise exception 'Non partecipi a questa partita'; end if;
  select l.ver into cur from public.sim_lobbies l where l.id = p_lobby;
  if p_since is not null and p_since = cur then return jsonb_build_object('same', true, 'v', cur); end if;
  return public._sim_state(p_lobby, v);
end $function$;

create or replace function public.sim_home() returns jsonb language plpgsql security definer set search_path = public as $$
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

drop function if exists public._sim_spec_clear(), public._sim_mask(bigint, uuid, smallint),
  public._sim_vis_m(text, boolean, boolean, smallint, smallint, smallint, smallint), public._sim_bump_ver(bigint);
drop table if exists public.sim_spec_grants, public.sim_spec_bans, public.sim_spectators;
delete from public.sim_chat where seat = 0;
alter table public.sim_chat drop constraint if exists sim_chat_spec_chk;
alter table public.sim_chat drop constraint if exists sim_chat_seat_check;
alter table public.sim_chat add constraint sim_chat_seat_check check (seat in (1, 2));
alter table public.sim_chat drop column if exists user_id;
alter table public.sim_players drop constraint if exists sim_players_spec_all_chk;
alter table public.sim_players drop column if exists spec_all;
alter table public.sim_lobbies drop column if exists allow_spec;
delete from public.system_settings where key = 'sim_max_spectators';
commit;
