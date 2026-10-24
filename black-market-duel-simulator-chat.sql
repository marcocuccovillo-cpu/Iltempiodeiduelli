-- =====================================================================
-- DUEL SIMULATOR — CHAT, SEGNALI «PENSO» / «OK» E «MISCHIA MANO» (da eseguire DOPO black-market-duel-simulator.sql)
--
-- Aggiunge, SOLO dentro il Duel Simulator:
--  * una chat testuale tra i due giocatori della partita (tabella sim_chat, ultimi 200 messaggi per partita);
--  * il pulsante «Mischia mano» (sim_shuffle_hand: riordina a caso solo la tua mano, scrive «mescola la propria mano» nel registro);
--  * i segnali «Penso» (resta acceso finché chi lo ha premuto non lo spegne o dà l'OK, oppure per 5 minuti)
--    e «OK» (visibile per 12 secondi): l'avversario li riceve nello stato della partita e il browser lo avvisa.
-- Garanzie: la chat e i segnali sono visibili solo ai due partecipanti (nessun accesso diretto alle tabelle dal browser);
-- non toccano carte, registro del duello, Ladder, Black Market, BC, XP, taglie o notifiche; con il modulo «duel» spento
-- le due funzioni rifiutano l'operazione. Si può rieseguire.
-- Annullamento: black-market-duel-simulator-chat-down.sql
-- =====================================================================
begin;

create table if not exists public.sim_chat (
  lobby_id bigint not null references public.sim_lobbies(id) on delete cascade,
  n integer not null,
  seat smallint not null check (seat in (1,2)),
  body text not null check (char_length(body) between 1 and 200),
  at timestamptz not null default now(),
  primary key (lobby_id, n)
);
alter table public.sim_chat enable row level security;
revoke all on public.sim_chat from public, anon, authenticated;

alter table public.sim_players add column if not exists sig text;
alter table public.sim_players add column if not exists sig_at timestamptz;
alter table public.sim_players add column if not exists sig_n integer not null default 0;
alter table public.sim_players drop constraint if exists sim_players_sig_chk;
alter table public.sim_players add constraint sim_players_sig_chk check (sig is null or sig in ('think', 'ok'));

-- stato della partita: aggiunge i segnali dei giocatori e gli ultimi 80 messaggi di chat
create or replace function public._sim_state(p_lobby bigint, p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.sim_lobbies%rowtype; me smallint; g public.sim_games%rowtype; pl jsonb; cards jsonb := '[]'; cnt jsonb := '{}'; lg jsonb := '[]'; gm jsonb := null; hist jsonb; cfg jsonb := null; chat jsonb := '[]'; gst timestamptz;
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
    end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.n), '[]') into lg
      from (select n, seat, kind, data from public.sim_log where game_id = g.id order by n desc limit 100) x;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('n', x.n, 'seat', x.seat, 't', x.body, 'ts', extract(epoch from x.at)::bigint) order by x.n), '[]') into chat
    from (select n, seat, body, at from public.sim_chat where lobby_id = p_lobby order by n desc limit 80) x;
  return jsonb_build_object('v', l.ver, 'lobby', jsonb_build_object('id', l.id, 'title', l.title, 'status', l.status, 'game_no', l.game_no,
           'wins', jsonb_build_array(l.wins_1, l.wins_2), 'winner', l.winner_seat, 'end_reason', l.end_reason, 'chooser', l.chooser_seat, 'host_id', l.host_id),
         'me', jsonb_build_object('seat', me, 'user_id', p_user, 'cfg', cfg), 'players', pl, 'game', gm, 'games', hist,
         'cards', cards, 'counts', cnt, 'log', lg, 'chat', chat);
end $$;


create or replace function public.sim_chat_send(p_lobby bigint, p_text text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint; st text; t text := left(btrim(regexp_replace(coalesce(p_text, ''), '[[:cntrl:]]', ' ', 'g')), 200); nn integer;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'any');
  select status into st from public.sim_lobbies where id = p_lobby;
  if st not in ('lobby', 'siding', 'playing', 'finished') then raise exception 'La partita è chiusa'; end if;
  if char_length(t) < 1 then raise exception 'Scrivi qualcosa'; end if;
  if (select count(*) from public.sim_chat where lobby_id = p_lobby and seat = me and at > now() - interval '1 minute') >= 20 then
    raise exception 'Troppi messaggi: aspetta qualche secondo';
  end if;
  select coalesce(max(n), 0) + 1 into nn from public.sim_chat where lobby_id = p_lobby;
  insert into public.sim_chat (lobby_id, n, seat, body) values (p_lobby, nn, me, t);
  delete from public.sim_chat where lobby_id = p_lobby and n <= nn - 200;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

create or replace function public.sim_signal(p_lobby bigint, p_kind text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  if p_kind is null or p_kind not in ('think', 'ok', 'clear') then raise exception 'Segnale non valido'; end if;
  update public.sim_players set sig = case when p_kind = 'clear' then null else p_kind end,
         sig_at = case when p_kind = 'clear' then null else now() end, sig_n = sig_n + 1
   where lobby_id = p_lobby and seat = me;
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

-- mischia la PROPRIA mano: cambia solo l'ordine con cui tu la vedi (l'avversario vede soltanto quante carte hai)
create or replace function public.sim_shuffle_hand(p_lobby bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; me smallint; g bigint;
begin
  select * into v, me, g from public._sim_enter(p_lobby, 'playing');
  update public.sim_cards x set ord = r.rn
    from (select id, row_number() over (order by random())::integer as rn from public.sim_cards where game_id = g and owner = me and zone = 'hand') r
   where x.game_id = g and x.id = r.id;
  perform public._sim_log(g, me, 'shuffle_hand', '{}');
  perform public._sim_bump(p_lobby);
  return public._sim_state(p_lobby, v);
end $$;

revoke all on function public.sim_chat_send(bigint, text), public.sim_signal(bigint, text), public.sim_shuffle_hand(bigint) from public, anon, authenticated;
grant execute on function public.sim_chat_send(bigint, text), public.sim_signal(bigint, text), public.sim_shuffle_hand(bigint) to authenticated;
commit;
