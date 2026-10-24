-- =====================================================================
-- DUEL SIMULATOR — DICHIARARE GLI ATTACCHI E SEGNARE I «BERSAGLI»
-- (da eseguire DOPO black-market-duel-simulator.sql, ...-chat.sql e ...-catene.sql)
--
-- Aggiunge, SOLO dentro il Duel Simulator:
--  * sim_attack: dichiara un attacco con un TUO mostro scoperto sul campo, contro un mostro dell'avversario oppure diretto
--    (p_target nullo). Scrive solo nel registro pubblico: i punti vita e le carte restano a carico dei giocatori. Se il mostro
--    attaccato è coperto, il suo nome NON compare nel registro.
--  * sim_target: segna (o toglie, toccando di nuovo) una carta come «bersaglio»: carte sul campo (anche coperte), nel Cimitero o tra
--    le carte rimosse che chi guarda può vedere. Al massimo 5 bersagli insieme; scadono a fine turno e quando la carta cambia zona.
--  * sim_target_clear: toglie tutti i bersagli.
--  * lo stato della partita porta i bersagli in corso.
-- Le carte rimosse SCOPERTE le vedono entrambi i giocatori, quelle COPERTE solo il proprietario (regola già in vigore: qui è solo
-- coperta dai test).
-- Nessuna regola automatica. Non tocca Ladder, Black Market, BC, XP, taglie o notifiche.
-- Con il modulo «duel» spento le funzioni rifiutano l'operazione. Si può rieseguire.
-- Annullamento: black-market-duel-simulator-attacchi-down.sql
-- =====================================================================
begin;

create table if not exists public.sim_target (
  game_id bigint not null references public.sim_games(id) on delete cascade,
  card_id integer not null,
  seat smallint not null check (seat in (1,2)),
  zone text not null,
  turn integer not null,
  at timestamptz not null default now(),
  primary key (game_id, card_id)
);
alter table public.sim_target enable row level security;
revoke all on public.sim_target from public, anon, authenticated;

-- stato della partita: aggiunge i bersagli in corso (mantiene chat, segnali e catena)
create or replace function public._sim_state(p_lobby bigint, p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;


create or replace function public.sim_attack(p_lobby bigint, p_card integer, p_target integer default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; c public.sim_cards%rowtype; t public.sim_cards%rowtype; tx integer := null;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select * into c from public.sim_cards where game_id = g and id = p_card for update;
  if not found then raise exception 'Carta inesistente'; end if;
  if c.zone not in ('mz', 'emz') or c.ctrl <> me then raise exception 'Puoi attaccare solo con i tuoi mostri sul campo'; end if;
  if not c.face_up then raise exception 'Solo un mostro scoperto può attaccare'; end if;
  if p_target is not null then
    select * into t from public.sim_cards where game_id = g and id = p_target;
    if not found then raise exception 'Bersaglio inesistente'; end if;
    if t.zone not in ('mz', 'emz') or t.ctrl = me then raise exception 'Puoi attaccare solo un mostro dell''avversario'; end if;
    if public._sim_pub(t.zone, t.face_up, t.revealed) then tx := t.code; end if;
  end if;
  perform public._sim_log(g, me, 'attack', jsonb_build_object('x', c.code, 'a', c.id, 'd', p_target is null, 'tx', tx, 't', p_target));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create or replace function public.sim_target(p_lobby bigint, p_card integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; c public.sim_cards%rowtype; tn integer; had boolean; n integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select turn_no into tn from public.sim_games where id = g;
  select * into c from public.sim_cards where game_id = g and id = p_card for update;
  if not found then raise exception 'Carta inesistente'; end if;
  if c.zone not in ('mz', 'emz', 'st', 'fz', 'gy', 'banish') then
    raise exception 'Puoi scegliere come bersaglio solo carte sul campo, nel Cimitero o tra le rimosse';
  end if;
  if c.zone in ('gy', 'banish') and not public._sim_vis(c.zone, c.face_up, c.revealed, c.owner, c.ctrl, me) then
    raise exception 'Non puoi vedere quella carta';
  end if;
  delete from public.sim_target t where t.game_id = g and (t.turn <> tn or not exists (
    select 1 from public.sim_cards x where x.game_id = t.game_id and x.id = t.card_id and x.zone = t.zone));
  select exists (select 1 from public.sim_target where game_id = g and card_id = p_card) into had;
  if had then
    delete from public.sim_target where game_id = g and card_id = p_card;
  else
    select count(*) into n from public.sim_target where game_id = g;
    if n >= 5 then raise exception 'Puoi avere al massimo 5 bersagli: togline uno'; end if;
    insert into public.sim_target (game_id, card_id, seat, zone, turn) values (g, c.id, me, c.zone, tn);
  end if;
  perform public._sim_log(g, me, 'target', jsonb_build_object('x', case when public._sim_pub(c.zone, c.face_up, c.revealed) then c.code end,
           'i', c.id, 'on', not had, 'z', c.zone, 'o', c.owner));
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create or replace function public.sim_target_clear(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; tn integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  select turn_no into tn from public.sim_games where id = g;
  delete from public.sim_target t where t.game_id = g and (t.turn <> tn or not exists (
    select 1 from public.sim_cards x where x.game_id = t.game_id and x.id = t.card_id and x.zone = t.zone));
  if not exists (select 1 from public.sim_target where game_id = g) then raise exception 'Non ci sono bersagli'; end if;
  delete from public.sim_target where game_id = g;
  perform public._sim_log(g, me, 'target_clear', '{}');
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

revoke all on function public.sim_attack(bigint, integer, integer), public.sim_target(bigint, integer), public.sim_target_clear(bigint) from public, anon, authenticated;
grant execute on function public.sim_attack(bigint, integer, integer), public.sim_target(bigint, integer), public.sim_target_clear(bigint) to authenticated;
commit;
