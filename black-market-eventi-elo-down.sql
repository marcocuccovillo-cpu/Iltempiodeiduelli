-- =====================================================================
-- ANNULLA la migrazione 033: i match dei tornei svizzeri non contano più per l'Elo.
-- Rimette il ricalcolo dell'Elo della Ladder com'era (copia di black-market-ladder-correzioni.sql), toglie i due controlli automatici,
-- la funzione swiss_elo e la tabella delle variazioni; se almeno un match di torneo era stato contato, l'Elo Advanced viene ricalcolato
-- UNA volta con le sole partite della Ladder (l'Elo guadagnato nei tornei sparisce). I tornei, i match e le iscrizioni restano.
-- Se in passato hai modificato a mano _ladder_rebuild nel database, questa copia lo sostituisce con la versione della migrazione.
-- Si può rieseguire senza danni.
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.ladder_matches') is null or to_regclass('public.ladder_ratings') is null then
    raise exception 'La Ladder non c''è: niente da annullare. Non è stato modificato nulla.';
  end if;
end $$;

drop trigger if exists matches_elo on public.matches;
drop trigger if exists events_elo on public.events;
drop function if exists public._trg_matches_elo();
drop function if exists public._trg_events_elo();
drop function if exists public.swiss_elo(uuid);

-- ricalcolo com'era prima (solo partite della Ladder)
create or replace function public._ladder_rebuild(p_format text) returns void language plpgsql security definer set search_path = public as $$
declare m record; ea integer; eo integer; da integer; s numeric;
        st integer := coalesce(public._setting('ladder_start_elo'), 1000); k integer := coalesce(public._setting('ladder_k'), 32);
        prev text := coalesce(current_setting('app.ladder_correct', true), '');
begin
  if p_format not in ('Advanced','Edison') then return; end if;
  perform set_config('app.ladder_correct', 'on', true);          -- aggiorna le variazioni mostrate nei match chiusi (il guardiano lo consente solo qui)
  perform 1 from public.ladder_ratings where format = p_format order by user_id for update;
  update public.ladder_ratings set elo = st, wins = 0, draws = 0, losses = 0, last_match_at = null where format = p_format;
  for m in select * from public.ladder_matches where status = 'closed' and format = p_format and kind in ('ladder','both') order by closed_at, id loop
    insert into public.ladder_ratings (user_id, format, elo) values (m.challenger_id, p_format, st), (m.opponent_id, p_format, st) on conflict do nothing;
    select elo into ea from public.ladder_ratings where user_id = m.challenger_id and format = p_format;
    select elo into eo from public.ladder_ratings where user_id = m.opponent_id and format = p_format;
    s := case m.reported_result when 'challenger' then 1.0 when 'opponent' then 0.0 else 0.5 end;
    da := round(k * (s - 1.0 / (1.0 + power(10.0, (eo - ea) / 400.0))))::integer;
    update public.ladder_ratings set elo = greatest(0, elo + da), last_match_at = m.closed_at,
      wins = wins + (m.reported_result = 'challenger')::integer, draws = draws + (m.reported_result = 'draw')::integer, losses = losses + (m.reported_result = 'opponent')::integer
      where user_id = m.challenger_id and format = p_format;
    update public.ladder_ratings set elo = greatest(0, elo - da), last_match_at = m.closed_at,
      wins = wins + (m.reported_result = 'opponent')::integer, draws = draws + (m.reported_result = 'draw')::integer, losses = losses + (m.reported_result = 'challenger')::integer
      where user_id = m.opponent_id and format = p_format;
    update public.ladder_matches set elo_challenger_before = ea, elo_opponent_before = eo, elo_challenger_delta = da, elo_opponent_delta = -da where id = m.id;
  end loop;
  perform set_config('app.ladder_correct', prev, true);
end $$;

do $$ declare had boolean := false; begin
  if to_regclass('public.event_match_elo') is not null then
    execute 'select exists (select 1 from public.event_match_elo)' into had;
  end if;
  drop table if exists public.event_match_elo;
  drop function if exists public._swiss_elo_format();
  if had then perform public._ladder_rebuild('Advanced'); end if;
end $$;

revoke all on function public._ladder_rebuild(text) from public, anon, authenticated;
commit;
