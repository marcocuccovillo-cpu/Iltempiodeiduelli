-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 033: i match dei tornei svizzeri contano per l'Elo Advanced della Ladder.
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO la 032 (black-market-eventi-svizzera.sql) e dopo le migrazioni della Ladder
-- (in particolare black-market-ladder-correzioni.sql, che ha creato il ricalcolo dell'Elo). Si può rieseguire senza danni.
--
-- COSA CAMBIA
--  * Ogni match di un TORNEO SVIZZERO verificato (risultato confermato dai due giocatori, o deciso dall'organizzatore) modifica l'Elo
--    Advanced dei due giocatori, con la stessa formula e gli stessi parametri della Ladder (impostazioni ladder_start_elo e ladder_k).
--    Vincite e sconfitte entrano anche nel loro conteggio V/S della Ladder. Non esistono pareggi nei tornei.
--  * Non contano: gli eventi a match manuali, i match in attesa o contestati, i riposi (BYE) e le vittorie a tavolino per ritiro
--    (non sono partite giocate), gli eventi annullati.
--  * ANNULLARE un torneo toglie il suo effetto dall'Elo (come annullare un match della Ladder): l'Elo viene ricalcolato senza di lui.
--  * Le partite si rigiocano in ordine di tempo insieme a quelle della Ladder: il ricalcolo (_ladder_rebuild, già usato per correggere
--    o annullare un match della Ladder) ora comprende anche i match dei tornei. Per questo una correzione o un annullamento in Ladder
--    non cancella mai l'Elo guadagnato nei tornei.
--  * PASSATO: alla prima esecuzione i match svizzeri già verificati vengono inclusi (se ce ne sono, l'Elo Advanced viene ricalcolato
--    una volta). Se non c'è nessun match svizzero, non cambia nulla per nessuno.
--  * Nuova funzione swiss_elo(evento): variazione di Elo di ogni match dell'evento e Elo attuale dei giocatori (per la pagina dell'evento).
--  * Formato fisso: Advanced (funzione _swiss_elo_format(); per cambiarlo basta riscriverla con 'Edison').
--  Nessun movimento di BC. La tabella nuova è chiusa al browser. Non tocca i dati della Ladder, a parte il ricalcolo descritto sopra.
--  ANNULLAMENTO: black-market-eventi-elo-down.sql (rimette il ricalcolo com'era e toglie l'effetto dei tornei dall'Elo).
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.ladder_matches') is null or to_regclass('public.ladder_ratings') is null
     or to_regprocedure('public._ladder_rebuild(text)') is null or to_regprocedure('public._setting(text)') is null then
    raise exception 'Prima esegui le migrazioni della Ladder (in particolare black-market-ladder-correzioni.sql): manca la Ladder o il suo ricalcolo dell''Elo. Non è stato modificato nulla.';
  end if;
  if to_regclass('public.events') is null or to_regclass('public.matches') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'events' and column_name = 'event_format') then
    raise exception 'Prima esegui la migrazione 032 (black-market-eventi-svizzera.sql). Non è stato modificato nulla.';
  end if;
end $$;

-- ---------- variazioni di Elo dei match dei tornei (riscritta a ogni ricalcolo) ----------
create table if not exists public.event_match_elo (
  match_id uuid primary key references public.matches(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  format   text not null,
  a_before integer not null, b_before integer not null,
  a_delta  integer not null, b_delta  integer not null,
  at       timestamptz
);
create index if not exists event_match_elo_event_idx on public.event_match_elo (event_id);
alter table public.event_match_elo enable row level security;
revoke all on public.event_match_elo from public, anon, authenticated;

-- formato di Ladder a cui contribuiscono i tornei
create or replace function public._swiss_elo_format() returns text language sql immutable as $$ select 'Advanced'::text $$;

-- ---------- ricalcolo dell'Elo di un formato: rigioca in ordine di tempo i match chiusi della Ladder e i match dei tornei svizzeri ----------
create or replace function public._ladder_rebuild(p_format text) returns void language plpgsql security definer set search_path = public as $$
declare m record; ea integer; eo integer; da integer; s numeric;
        st integer := coalesce(public._setting('ladder_start_elo'), 1000); k integer := coalesce(public._setting('ladder_k'), 32);
        prev text := coalesce(current_setting('app.ladder_correct', true), '');
        sw boolean := (p_format = public._swiss_elo_format());
begin
  if p_format not in ('Advanced','Edison') then return; end if;
  perform set_config('app.ladder_correct', 'on', true);          -- aggiorna le variazioni mostrate nei match chiusi (il guardiano lo consente solo qui)
  perform 1 from public.ladder_ratings where format = p_format order by user_id for update;
  update public.ladder_ratings set elo = st, wins = 0, draws = 0, losses = 0, last_match_at = null where format = p_format;
  delete from public.event_match_elo where format = p_format;
  for m in
    select 'ladder'::text as src, lm.id, null::uuid as ev, lm.challenger_id as pa, lm.opponent_id as pb, lm.reported_result as res, lm.closed_at as t
      from public.ladder_matches lm
     where lm.status = 'closed' and lm.format = p_format and lm.kind in ('ladder','both')
    union all
    select 'event'::text, mt.id, mt.event_id, mt.player_a, mt.player_b, case when mt.winner_id = mt.player_a then 'challenger' else 'opponent' end, mt.verified_at
      from public.matches mt join public.events ev on ev.id = mt.event_id
     where sw and ev.event_format = 'swiss' and ev.event_status <> 'cancelled' and mt.status = 'verified' and mt.winner_id is not null
    order by t, id
  loop
    insert into public.ladder_ratings (user_id, format, elo) values (m.pa, p_format, st), (m.pb, p_format, st) on conflict do nothing;
    select elo into ea from public.ladder_ratings where user_id = m.pa and format = p_format;
    select elo into eo from public.ladder_ratings where user_id = m.pb and format = p_format;
    s := case m.res when 'challenger' then 1.0 when 'opponent' then 0.0 else 0.5 end;
    da := round(k * (s - 1.0 / (1.0 + power(10.0, (eo - ea) / 400.0))))::integer;
    update public.ladder_ratings set elo = greatest(0, elo + da), last_match_at = m.t,
      wins = wins + (m.res = 'challenger')::integer, draws = draws + (m.res = 'draw')::integer, losses = losses + (m.res = 'opponent')::integer
      where user_id = m.pa and format = p_format;
    update public.ladder_ratings set elo = greatest(0, elo - da), last_match_at = m.t,
      wins = wins + (m.res = 'opponent')::integer, draws = draws + (m.res = 'draw')::integer, losses = losses + (m.res = 'challenger')::integer
      where user_id = m.pb and format = p_format;
    if m.src = 'ladder' then
      update public.ladder_matches set elo_challenger_before = ea, elo_opponent_before = eo, elo_challenger_delta = da, elo_opponent_delta = -da where id = m.id;
    else
      insert into public.event_match_elo (match_id, event_id, format, a_before, b_before, a_delta, b_delta, at) values (m.id, m.ev, p_format, ea, eo, da, -da, m.t);
    end if;
  end loop;
  perform set_config('app.ladder_correct', prev, true);
end $$;

-- ---------- quando cambia qualcosa che conta per l'Elo, si ricalcola ----------
-- un match svizzero diventa verificato (o una verifica sparisce)
create or replace function public._trg_matches_elo() returns trigger language plpgsql security definer set search_path = public as $$
declare fmt text := public._swiss_elo_format(); eid uuid := case when tg_op = 'DELETE' then old.event_id else new.event_id end;
begin
  if not exists (select 1 from public.events where id = eid and event_format = 'swiss') then return null; end if;
  if tg_op = 'UPDATE' and not (new.status = 'verified' or old.status = 'verified') then return null; end if;
  if tg_op = 'DELETE' and old.status <> 'verified' then return null; end if;
  if tg_op = 'INSERT' and new.status <> 'verified' then return null; end if;
  perform public._ladder_rebuild(fmt);
  return null;
end $$;
drop trigger if exists matches_elo on public.matches;
create trigger matches_elo after insert or update or delete on public.matches for each row execute function public._trg_matches_elo();

-- un torneo viene annullato (o ripristinato)
create or replace function public._trg_events_elo() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.event_format = 'swiss' and old.event_status is distinct from new.event_status and (new.event_status = 'cancelled' or old.event_status = 'cancelled')
     and exists (select 1 from public.matches where event_id = new.id and status = 'verified') then
    perform public._ladder_rebuild(public._swiss_elo_format());
  end if;
  return null;
end $$;
drop trigger if exists events_elo on public.events;
create trigger events_elo after update on public.events for each row execute function public._trg_events_elo();

-- ---------- per la pagina dell'evento ----------
create or replace function public.swiss_elo(p_event uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); fmt text := public._swiss_elo_format();
begin
  if not exists (select 1 from public.events where id = p_event) then raise exception 'Evento inesistente'; end if;
  return jsonb_build_object(
    'format', fmt,
    'counts', (select e.event_format = 'swiss' and e.event_status <> 'cancelled' from public.events e where e.id = p_event),
    'matches', (select coalesce(jsonb_agg(jsonb_build_object('match_id', x.match_id, 'a_before', x.a_before, 'b_before', x.b_before, 'a_delta', x.a_delta, 'b_delta', x.b_delta) order by x.at), '[]'::jsonb)
                  from public.event_match_elo x where x.event_id = p_event),
    'players', (select coalesce(jsonb_agg(jsonb_build_object('user_id', r.user_id, 'elo', r.elo) order by r.user_id), '[]'::jsonb)
                  from public.ladder_ratings r where r.format = fmt
                   and r.user_id in (select user_id from public.event_participants where event_id = p_event)));
end $$;

-- ---------- passato: i match svizzeri già verificati entrano nell'Elo (solo se ce ne sono di non ancora contati) ----------
do $$ begin
  if exists (select 1 from public.matches mt join public.events ev on ev.id = mt.event_id
              where ev.event_format = 'swiss' and ev.event_status <> 'cancelled' and mt.status = 'verified' and mt.winner_id is not null
                and not exists (select 1 from public.event_match_elo x where x.match_id = mt.id)) then
    perform public._ladder_rebuild(public._swiss_elo_format());
  end if;
end $$;

-- ---------- permessi ----------
revoke all on function public._swiss_elo_format(), public._trg_matches_elo(), public._trg_events_elo() from public, anon, authenticated;
revoke all on function public.swiss_elo(uuid) from public, anon;
grant execute on function public.swiss_elo(uuid) to authenticated;
commit;
