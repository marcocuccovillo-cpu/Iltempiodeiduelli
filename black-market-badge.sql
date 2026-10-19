-- =====================================================================
-- MIGRAZIONE 007 — BADGE E TRAGUARDI (Black Market + Ladder)
-- Da eseguire nel SQL Editor di Supabase DOPO 001…006. Si può rieseguire senza danni.
--
-- Cosa fa: aggiunge il catalogo dei traguardi (tabella badge_defs, solo lettura) e UNA funzione di
-- lettura, badge_progress(utente), che calcola ogni badge dai dati UFFICIALI già presenti:
--   match verificati, partecipazioni agli eventi, taglie, riscossioni, partite di Ladder concluse.
-- Cosa NON fa: nessun badge è memorizzato, nessun credito viene dato, nessuna funzione economica
-- (taglie, wallet, registro, Ladder, premi) viene toccata. I badge sono un valore SOLO cosmetico:
-- non si possono né comprare né assegnare a mano, e non spostano Black Credits.
-- Privacy: se l'amministrazione nasconde gli autori delle taglie (show_bounty_authors = 0) il badge
-- "taglie lanciate" resta visibile solo al diretto interessato e allo staff; i badge della Ladder
-- compaiono solo con il modulo Ladder acceso.
-- Annullamento: black-market-badge-down.sql (non perde dati: i badge sono derivati).
-- =====================================================================
begin;

-- ---------- Catalogo dei traguardi (regole; nomi e grafica stanno nell'app) ----------
create table if not exists public.badge_defs (
  code text primary key check (code ~ '^[a-z0-9_]+$'),
  family text not null,                                   -- gruppo di badge che salgono di livello
  area text not null check (area in ('market','duel','ladder','special')),
  tier integer not null check (tier between 1 and 5),     -- 1 bronzo, 2 argento, 3 oro, 4 leggenda, 5 unico
  metric text not null,                                   -- cosa si misura (vedi badge_progress)
  kind text not null check (kind in ('count','max')),     -- count = quante volte; max = valore più alto raggiunto
  threshold integer not null check (threshold > 0),
  sort integer not null,
  unique (family, tier)
);

alter table public.badge_defs enable row level security;
drop policy if exists badge_defs_read on public.badge_defs;
create policy badge_defs_read on public.badge_defs for select to authenticated using (true);

-- Catalogo: una riga per traguardo. (Le regole si cambiano con una nuova migrazione, mai a mano.)
insert into public.badge_defs (code, family, area, tier, metric, kind, threshold, sort) values
 -- Black Market: taglie lanciate
 ('taglie_1',  'taglie',   'market', 1, 'bounty_placed', 'count',  1, 110), ('taglie_2',  'taglie',   'market', 2, 'bounty_placed', 'count',  5, 111),
 ('taglie_3',  'taglie',   'market', 3, 'bounty_placed', 'count', 15, 112), ('taglie_4',  'taglie',   'market', 4, 'bounty_placed', 'count', 40, 113),
 -- Black Market: taglie riscosse
 ('riscosse_1','riscosse', 'market', 1, 'bounty_claim',  'count',  1, 120), ('riscosse_2','riscosse', 'market', 2, 'bounty_claim',  'count',  5, 121),
 ('riscosse_3','riscosse', 'market', 3, 'bounty_claim',  'count', 15, 122), ('riscosse_4','riscosse', 'market', 4, 'bounty_claim',  'count', 30, 123),
 -- Black Market: taglie ricevute (Most Wanted)
 ('ricercato_1','ricercato','market',1, 'bounty_on_me',  'count',  1, 130), ('ricercato_2','ricercato','market',2, 'bounty_on_me',  'count',  5, 131),
 ('ricercato_3','ricercato','market',3, 'bounty_on_me',  'count', 15, 132), ('ricercato_4','ricercato','market',4, 'bounty_on_me',  'count', 30, 133),
 -- Black Market: riscossione più alta
 ('bottino_1', 'bottino',  'market', 1, 'claim_best',    'max',  100, 140), ('bottino_2', 'bottino',  'market', 2, 'claim_best',    'max',  300, 141),
 ('bottino_3', 'bottino',  'market', 3, 'claim_best',    'max',  600, 142),
 -- Match ufficiali (eventi): vittorie
 ('ufficiali_1','ufficiali','duel',  1, 'duel_win',      'count',  1, 210), ('ufficiali_2','ufficiali','duel',  2, 'duel_win',      'count',  5, 211),
 ('ufficiali_3','ufficiali','duel',  3, 'duel_win',      'count', 15, 212), ('ufficiali_4','ufficiali','duel',  4, 'duel_win',      'count', 40, 213),
 -- Match ufficiali: vittorie di fila
 ('serie_1',   'serie',    'duel',   1, 'duel_streak',   'max',    3, 220), ('serie_2',   'serie',    'duel',   2, 'duel_streak',   'max',    5, 221),
 ('serie_3',   'serie',    'duel',   3, 'duel_streak',   'max',    8, 222),
 -- Eventi giocati
 ('presenza_1','presenza', 'duel',   1, 'event',         'count',  1, 230), ('presenza_2','presenza', 'duel',   2, 'event',         'count',  5, 231),
 ('presenza_3','presenza', 'duel',   3, 'event',         'count', 15, 232), ('presenza_4','presenza', 'duel',   4, 'event',         'count', 30, 233),
 -- Ladder: vittorie
 ('arena_1',   'arena',    'ladder', 1, 'ladder_win',    'count',  1, 310), ('arena_2',   'arena',    'ladder', 2, 'ladder_win',    'count', 10, 311),
 ('arena_3',   'arena',    'ladder', 3, 'ladder_win',    'count', 30, 312), ('arena_4',   'arena',    'ladder', 4, 'ladder_win',    'count', 75, 313),
 -- Ladder: Elo massimo raggiunto
 ('elo_1',     'elo',      'ladder', 1, 'elo_peak',      'max', 1100, 320), ('elo_2',     'elo',      'ladder', 2, 'elo_peak',      'max', 1200, 321),
 ('elo_3',     'elo',      'ladder', 3, 'elo_peak',      'max', 1350, 322), ('elo_4',     'elo',      'ladder', 4, 'elo_peak',      'max', 1500, 323),
 -- Ladder: vittorie di fila
 ('furia_1',   'furia',    'ladder', 1, 'ladder_streak', 'max',    3, 330), ('furia_2',   'furia',    'ladder', 2, 'ladder_streak', 'max',    5, 331),
 ('furia_3',   'furia',    'ladder', 3, 'ladder_streak', 'max',    8, 332),
 -- Ladder: avversari diversi battuti
 ('caccia_1',  'caccia',   'ladder', 1, 'ladder_rival',  'count',  3, 340), ('caccia_2',  'caccia',   'ladder', 2, 'ladder_rival',  'count',  8, 341),
 ('caccia_3',  'caccia',   'ladder', 3, 'ladder_rival',  'count', 15, 342),
 -- Ladder: battere chi ha almeno 100 punti Elo più di te
 ('giganti_1', 'giganti',  'ladder', 1, 'ladder_upset',  'count',  1, 350), ('giganti_2', 'giganti',  'ladder', 2, 'ladder_upset',  'count',  3, 351),
 ('giganti_3', 'giganti',  'ladder', 3, 'ladder_upset',  'count', 10, 352),
 -- Ladder: rivincite (battere chi ti aveva battuto)
 ('rivincita_1','rivincita','ladder',1, 'ladder_revenge','count',  1, 360), ('rivincita_2','rivincita','ladder',2, 'ladder_revenge','count',  5, 361),
 -- Speciali (livello unico)
 ('iniziato',  'iniziato', 'special',5, 'joined',        'count',  1, 910),
 ('doppia',    'doppia',   'special',5, 'double',        'count',  1, 920),
 ('custode',   'custode',  'special',5, 'staff',         'count',  1, 930)
on conflict (code) do nothing;

-- ---------- Calcolo dei progressi (sola lettura) ----------
-- Un solo punto di calcolo per tutti i badge. Ogni "occorrenza" nasce da un dato ufficiale:
--   duel_win / duel_streak / event       -> match VERIFICATI ed eventi (tabelle matches, event_participants)
--   bounty_placed / bounty_on_me / bounty_claim / claim_best -> taglie e riscossioni (bounties, bounty_settlements)
--   ladder_*  / elo_peak                 -> partite di Ladder CONCLUSE e confermate (ladder_matches, status 'closed')
--   joined / staff / double              -> profilo, ruolo, e l'aver vinto sia in Ladder sia riscosso una taglia
create or replace function public.badge_progress(p_user uuid default null)
returns table (code text, family text, area text, tier integer, metric text, kind text, threshold integer,
               value integer, earned boolean, earned_at timestamptz, hidden boolean, sort integer)
language plpgsql stable security definer set search_path = public as $$
declare u uuid := coalesce(p_user, auth.uid());
        ladder_on boolean := public._module_on('ladder');
        authors_ok boolean;
begin
  if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
  if u is null or not exists (select 1 from public.profiles where id = u) then raise exception 'Duellante non trovato'; end if;
  -- chi ha lanciato una taglia è un dato pubblico solo se l'amministrazione non lo nasconde
  authors_ok := coalesce(public._setting('show_bounty_authors'), 1) = 1 or u = auth.uid() or public.is_staff();

  return query
  with
  -- partite ufficiali verificate del giocatore, dal punto di vista di u
  w as (
    select m.id, m.verified_at as at, (m.winner_id = u) as won
    from public.matches m
    where m.status = 'verified' and (m.player_a = u or m.player_b = u)),
  wg as (
    select id, at, won, row_number() over (order by at, id) - row_number() over (partition by won order by at, id) as grp from w),
  wstreak as (
    select at, row_number() over (partition by grp order by at, id)::integer as v from wg where won),
  -- partite di Ladder concluse, dal punto di vista di u
  lm as (
    select l.id, l.closed_at as at,
           case when l.challenger_id = u then l.opponent_id else l.challenger_id end as opp,
           case l.reported_result when 'draw' then 'D'
                when 'challenger' then case when l.challenger_id = u then 'W' else 'L' end
                else case when l.opponent_id = u then 'W' else 'L' end end as res,
           case when l.challenger_id = u then l.elo_challenger_before else l.elo_opponent_before end as elo_me,
           case when l.challenger_id = u then l.elo_opponent_before else l.elo_challenger_before end as elo_opp,
           case when l.challenger_id = u then l.elo_challenger_delta else l.elo_opponent_delta end as delta
    from public.ladder_matches l
    where ladder_on and l.status = 'closed' and (l.challenger_id = u or l.opponent_id = u)),
  lg as (
    select id, at, res, row_number() over (order by at, id) - row_number() over (partition by (res = 'W') order by at, id) as grp from lm),
  lstreak as (
    select at, row_number() over (partition by grp order by at, id)::integer as v from lg where res = 'W'),
  lrev as (   -- vittoria contro chi, prima di allora, ti aveva battuto
    select at, res, bool_or(res = 'L') over (partition by opp order by at, id rows between unbounded preceding and 1 preceding) as had_lost
    from lm),
  lrival as (select opp, min(at) as at from lm where res = 'W' group by opp),
  cl as (select s.created_at as at, s.payout from public.bounty_settlements s where s.winner_id = u and s.quotas_count > 0),
  occ as (
    select 'duel_win'::text as metric, at, 1 as v from w where won
    union all select 'duel_streak', at, v from wstreak
    union all select 'event', e.event_date::timestamptz, 1 from public.event_participants ep join public.events e on e.id = ep.event_id where ep.user_id = u
    union all select 'bounty_placed', b.created_at, 1 from public.bounties b where authors_ok and b.creator_id = u and b.status <> 'cancelled'
    union all select 'bounty_on_me', b.created_at, 1 from public.bounties b where b.target_id = u and b.status <> 'cancelled'
    union all select 'bounty_claim', at, 1 from cl
    union all select 'claim_best', at, payout from cl
    union all select 'ladder_win', at, 1 from lm where res = 'W'
    union all select 'ladder_streak', at, v from lstreak
    union all select 'elo_peak', at, greatest(elo_me, elo_me + delta) from lm
    union all select 'ladder_rival', at, 1 from lrival
    union all select 'ladder_upset', at, 1 from lm where res = 'W' and elo_opp >= elo_me + 100
    union all select 'ladder_revenge', at, 1 from lrev where res = 'W' and coalesce(had_lost, false)
    union all select 'joined', p.created_at, 1 from public.profiles p where p.id = u
    union all select 'staff', p.created_at, 1 from public.profiles p where p.id = u and p.role::text in ('admin', 'moderator', 'organizer')
    union all select 'double', greatest((select min(at) from lm where res = 'W'), (select min(at) from cl)), 1
      where exists (select 1 from lm where res = 'W') and exists (select 1 from cl)),
  occn as (select o.*, row_number() over (partition by o.metric order by o.at) as rn from occ o),
  st as (select o.metric, count(*)::integer as cnt, max(o.v)::integer as mx from occ o group by o.metric)
  select d.code, d.family, d.area, d.tier, d.metric, d.kind, d.threshold,
         case when h.hid then 0 else coalesce(case d.kind when 'count' then st.cnt else st.mx end, 0) end as value,
         (not h.hid) and coalesce(case d.kind when 'count' then st.cnt else st.mx end, 0) >= d.threshold as earned,
         case when h.hid then null
              when d.kind = 'count' then (select o.at from occn o where o.metric = d.metric and o.rn = d.threshold)
              else (select min(o.at) from occ o where o.metric = d.metric and o.v >= d.threshold) end as earned_at,
         h.hid as hidden, d.sort
  from public.badge_defs d
  left join st on st.metric = d.metric
  cross join lateral (select (d.area = 'ladder' and not ladder_on) or (d.metric = 'bounty_placed' and not authors_ok) as hid) h
  order by d.sort;
end $$;

-- ---------- Permessi: sola lettura per gli iscritti, nessuna scrittura ----------
revoke all on public.badge_defs from public, anon, authenticated;
grant select on public.badge_defs to authenticated;
revoke all on function public.badge_progress(uuid) from public, anon, authenticated;
grant execute on function public.badge_progress(uuid) to authenticated;

commit;
