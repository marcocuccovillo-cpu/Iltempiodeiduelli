-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 032: eventi «Torneo svizzero» (lobby, turni, risultati dei giocatori), durata e annullamento degli eventi.
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO le migrazioni precedenti. Si può rieseguire senza danni.
--
-- COSA CAMBIA PER GLI ORGANIZZATORI
--  * Alla creazione di un evento l'organizzatore sceglie se è un «Torneo svizzero con lobby» e quanto dura (in giorni, da 1 a 90).
--    Gli eventi già esistenti e quelli creati senza la spunta restano IDENTICI (l'organizzatore aggiunge i match a mano).
--  * LOBBY: finché il torneo non è partito, ogni giocatore si iscrive (e si disiscrive) da solo dalla pagina dell'evento (massimo 64 iscritti).
--  * SOLO l'organizzatore (o un amministratore) fa partire il torneo: il sistema genera il primo turno. Il numero di turni è deciso dal sistema
--    in base agli iscritti (il minimo che basta per avere un solo vincitore: 2 iscritti = 1 turno, 3–4 = 2, 5–8 = 3, 9–16 = 4 …)
--    oppure lo sceglie l'organizzatore (alla partenza o dopo; si può cambiare finché il torneo non è concluso).
--  * ACCOPPIAMENTI SVIZZERI: turno 1 a caso; dal 2° in poi si affrontano giocatori con lo stesso punteggio (3 punti a vittoria, 0 a sconfitta;
--    a parità vale la somma dei punti degli avversari affrontati). Nessuno incontra due volte lo stesso avversario, se è possibile evitarlo;
--    con un numero dispari di giocatori uno riposa (BYE = 3 punti), a rotazione: chi ha già riposato viene scelto per ultimo.
--  * RISULTATI: li registrano i giocatori in autonomia, come in Ladder: uno dei due indica chi ha vinto, l'altro conferma (il match diventa
--    ufficiale e verificato) oppure contesta (allora decide l'organizzatore). L'organizzatore può sempre decidere un match fermo.
--  * TURNO SUCCESSIVO: l'organizzatore può generarlo SOLO quando tutti i risultati del turno sono registrati (e finché c'è ancora un turno previsto
--    e la durata dell'evento non è scaduta). Alla fine l'organizzatore conclude il torneo.
--  * RITIRO: un giocatore può ritirarsi durante il torneo (o l'organizzatore lo toglie): non sarà più accoppiato e l'avversario del suo match
--    in corso vince a tavolino (3 punti, senza match ufficiale: così non si possono regalare vittorie per riscuotere taglie).
--  * DURATA: giorni scelti alla creazione, contando il giorno dell'evento (evento del 1° novembre di 14 giorni = fino al 14 novembre incluso).
--    Dopo l'ultimo giorno non si possono più creare turni nuovi; i risultati già in corso si possono ancora registrare e l'evento si conclude.
--  * ANNULLAMENTO: l'organizzatore (o un amministratore) può annullare QUALSIASI evento (anche vecchio o a mano), con un motivo facoltativo.
--    L'evento resta in elenco, segnato «Annullato». I match ancora da verificare vengono tolti; quelli già verificati restano (hanno già
--    prodotto i loro effetti, per esempio le taglie riscosse). Se l'evento non ha nessun match verificato, vengono tolte anche le iscrizioni
--    (così non conta come «evento disputato»). L'evento automatico della Ladder non si può annullare.
--  * Nei tornei svizzeri gli accoppiamenti li genera solo il sistema (non si possono più aggiungere match a mano); in un evento annullato
--    nessun match si può più aggiungere.
--  Soldi e taglie: i match svizzeri verificati sono match normali dell'evento, quindi valgono come quelli verificati dall'organizzatore
--  (taglie riscosse al momento della verifica, statistiche, ecc.). Le ricompense di partecipazione si danno con il pulsante già esistente.
--  Reversibile con black-market-eventi-svizzera-down.sql.
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.events') is null or to_regclass('public.matches') is null or to_regclass('public.event_participants') is null
     or to_regprocedure('public._can_manage_event(uuid,uuid)') is null or to_regprocedure('public._audit(uuid,text,text,text,jsonb,jsonb,text)') is null then
    raise exception 'Prima esegui le migrazioni del Black Market (serve la 001 con eventi e match). Non è stato modificato nulla.';
  end if;
end $$;

-- ---------- colonne nuove (nomi con prefisso, per non scontrarsi con altre migrazioni) ----------
alter table public.events
  add column if not exists event_format text not null default 'manual' check (event_format in ('manual','swiss')),
  add column if not exists event_status text not null default 'open' check (event_status in ('open','running','finished','cancelled')),
  add column if not exists duration_days integer check (duration_days is null or duration_days between 1 and 90),
  add column if not exists rounds_planned integer check (rounds_planned is null or rounds_planned between 1 and 20),
  add column if not exists current_round integer not null default 0 check (current_round >= 0),
  add column if not exists started_at timestamptz,
  add column if not exists finished_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references public.profiles(id),
  add column if not exists cancel_reason text check (cancel_reason is null or char_length(cancel_reason) <= 200);
alter table public.event_participants
  add column if not exists dropped boolean not null default false,
  add column if not exists dropped_at timestamptz;

-- riposi e vittorie a tavolino (nessun match ufficiale); i risultati contestati o in attesa stanno qui, chiusi al browser
create table if not exists public.event_byes (
  event_id uuid not null references public.events(id) on delete cascade,
  round integer not null check (round > 0),
  user_id uuid not null references public.profiles(id),
  kind text not null default 'bye' check (kind in ('bye','forfeit')),
  created_at timestamptz not null default clock_timestamp(),
  primary key (event_id, round, user_id)
);
create table if not exists public.event_match_reports (
  match_id uuid primary key references public.matches(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id),
  winner_id uuid not null references public.profiles(id),
  disputed boolean not null default false,
  disputed_by uuid references public.profiles(id),
  reported_at timestamptz not null default clock_timestamp()
);
alter table public.event_byes enable row level security;
alter table public.event_match_reports enable row level security;
revoke all on public.event_byes, public.event_match_reports from public, anon, authenticated;

-- ---------- guardia sugli inserimenti di match ----------
create or replace function public._trg_matches_event_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare e public.events%rowtype;
begin
  select * into e from public.events where id = new.event_id;
  if found then
    if e.event_status = 'cancelled' then raise exception 'Evento annullato: non si possono aggiungere match'; end if;
    if e.event_format = 'swiss' and coalesce(current_setting('tempio.swiss_internal', true), '') <> '1' then
      raise exception 'Nei tornei svizzeri gli accoppiamenti li genera il sistema'; end if;
  end if;
  return new;
end $$;
drop trigger if exists matches_event_guard on public.matches;
create trigger matches_event_guard before insert on public.matches for each row execute function public._trg_matches_event_guard();

-- ---------- funzioni interne ----------
create or replace function public._swiss_today() returns date language sql stable as $$ select (clock_timestamp() at time zone 'Europe/Rome')::date $$;

-- turni minimi per avere un solo vincitore: la più piccola potenza di 2 che copre i giocatori
create or replace function public._swiss_auto_rounds(p_n integer) returns integer language plpgsql immutable as $$
declare r integer := 1;
begin
  while (2 ^ r) < greatest(p_n, 2) loop r := r + 1; end loop;
  return least(r, 20);
end $$;

-- classifica: 3 punti a vittoria (anche a tavolino o per riposo), somma dei punti degli avversari come spareggio
create or replace function public._swiss_table(p_event uuid)
returns table (user_id uuid, dropped boolean, wins integer, losses integer, byes integer, points integer, omw integer, rank integer)
language sql stable security definer set search_path = public as $$
  with p as (select ep.user_id as uid, ep.dropped as dr from public.event_participants ep where ep.event_id = p_event),
  vm as (select m.player_a as a, m.player_b as b, m.winner_id as wn from public.matches m where m.event_id = p_event and m.status = 'verified'),
  wi as (select wn as uid, count(*)::integer as c from vm group by wn),
  lo as (select case when wn = a then b else a end as uid, count(*)::integer as c from vm group by 1),
  bye as (select eb.user_id as uid, count(*)::integer as c from public.event_byes eb where eb.event_id = p_event group by eb.user_id),
  base as (select p.uid, p.dr, coalesce(wi.c, 0) as w, coalesce(lo.c, 0) as l, coalesce(bye.c, 0) as b,
                  3 * (coalesce(wi.c, 0) + coalesce(bye.c, 0)) as pts
           from p left join wi on wi.uid = p.uid left join lo on lo.uid = p.uid left join bye on bye.uid = p.uid),
  opp as (select a as uid, b as o from vm union all select b, a from vm),
  om as (select opp.uid, sum(base.pts)::integer as s from opp join base on base.uid = opp.o group by opp.uid)
  select base.uid, base.dr, base.w, base.l, base.b, base.pts, coalesce(om.s, 0),
         (row_number() over (order by base.pts desc, coalesce(om.s, 0) desc, base.w desc, pr.nickname, base.uid))::integer
  from base left join om on om.uid = base.uid join public.profiles pr on pr.id = base.uid $$;

-- ricerca degli accoppiamenti: il primo giocatore con il più vicino in classifica che non ha già affrontato, con ritorno indietro se serve.
-- Con p_strict = false i rematch sono permessi (ultima spiaggia: restituisce sempre una soluzione).
create or replace function public._swiss_try(p_event uuid, p_rem uuid[], p_strict boolean) returns uuid[]
language plpgsql security definer set search_path = public as $$
declare a uuid; b uuid; i integer; n integer := coalesce(array_length(p_rem, 1), 0); sub uuid[]; c integer;
begin
  if n = 0 then return '{}'::uuid[]; end if;
  c := coalesce(nullif(current_setting('tempio.swiss_nodes', true), '')::integer, 0) + 1;
  perform set_config('tempio.swiss_nodes', c::text, true);
  if p_strict and c > 20000 then return null; end if;      -- troppo difficile da incastrare senza rematch: si passa alla modalità libera
  a := p_rem[1];
  for i in 2..n loop
    b := p_rem[i];
    if p_strict and exists (select 1 from public.matches m where m.event_id = p_event and ((m.player_a = a and m.player_b = b) or (m.player_a = b and m.player_b = a))) then
      continue;
    end if;
    sub := public._swiss_try(p_event, p_rem[2:i - 1] || p_rem[i + 1:n], p_strict);
    if sub is not null then return array[a, b] || sub; end if;
  end loop;
  return null;
end $$;

-- genera i match di un turno (e l'eventuale riposo)
create or replace function public._swiss_make_round(p_event uuid, p_round integer, p_by uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ord uuid[]; n integer; bye uuid; pairs uuid[]; i integer; a uuid; b uuid; rematches integer := 0;
begin
  if p_round = 1 then
    select array_agg(ep.user_id order by random()) into ord from public.event_participants ep where ep.event_id = p_event and not ep.dropped;
  else
    select array_agg(t.user_id order by t.points desc, t.omw desc, random()) into ord from public._swiss_table(p_event) t where not t.dropped;
  end if;
  n := coalesce(array_length(ord, 1), 0);
  if n < 2 then raise exception 'Servono almeno 2 giocatori per creare un turno'; end if;
  if n % 2 = 1 then       -- riposa il giocatore più in basso in classifica che non ha ancora riposato (o vinto a tavolino)
    select t.u into bye from unnest(ord) with ordinality as t(u, ix)
      where not exists (select 1 from public.event_byes eb where eb.event_id = p_event and eb.user_id = t.u) order by t.ix desc limit 1;
    if bye is null then bye := ord[n]; end if;
    ord := array_remove(ord, bye);
  end if;
  perform set_config('tempio.swiss_nodes', '0', true);
  pairs := public._swiss_try(p_event, ord, true);
  if pairs is null then pairs := public._swiss_try(p_event, ord, false); end if;
  perform set_config('tempio.swiss_internal', '1', true);
  for i in 1..(array_length(pairs, 1) / 2) loop
    a := pairs[2 * i - 1]; b := pairs[2 * i];
    if exists (select 1 from public.matches m where m.event_id = p_event and ((m.player_a = a and m.player_b = b) or (m.player_a = b and m.player_b = a))) then
      rematches := rematches + 1;
    end if;
    insert into public.matches (id, event_id, round, player_a, player_b, created_by) values (gen_random_uuid(), p_event, p_round, a, b, p_by);
  end loop;
  perform set_config('tempio.swiss_internal', '', true);
  if bye is not null then insert into public.event_byes (event_id, round, user_id, kind) values (p_event, p_round, bye, 'bye'); end if;
  return jsonb_build_object('pairs', array_length(pairs, 1) / 2, 'bye', bye, 'rematches', rematches);
end $$;

-- chiude un match con il vincitore (stesso effetto di una verifica dell'organizzatore: stato «verificato»)
create or replace function public._swiss_close(p_match uuid, p_winner uuid, p_verifier uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.matches set winner_id = p_winner, status = 'verified', verified_by = p_verifier, verified_at = clock_timestamp()
    where id = p_match and status = 'pending';
  if not found then raise exception 'Match già concluso'; end if;
  perform public._audit(p_verifier, 'swiss_result', 'match', p_match::text, null, jsonb_build_object('winner', p_winner), null);
end $$;

-- ritiro: dall'iscrizione (lobby) si esce e basta; a torneo in corso si resta in classifica ma non si viene più accoppiati
create or replace function public._swiss_drop(p_event uuid, p_user uuid, p_by uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.events%rowtype; m public.matches%rowtype; opp uuid;
begin
  select * into e from public.events where id = p_event for update;
  if e.event_status = 'open' then
    delete from public.event_participants where event_id = p_event and user_id = p_user;
  elsif e.event_status = 'running' then
    update public.event_participants set dropped = true, dropped_at = clock_timestamp() where event_id = p_event and user_id = p_user and not dropped;
    for m in select * from public.matches where event_id = p_event and status = 'pending' and p_user in (player_a, player_b) for update loop
      opp := case when m.player_a = p_user then m.player_b else m.player_a end;
      delete from public.matches where id = m.id;
      insert into public.event_byes (event_id, round, user_id, kind) values (p_event, m.round, opp, 'forfeit') on conflict do nothing;
    end loop;
  else
    raise exception 'L''evento non è in corso';
  end if;
  perform public._audit(p_by, 'swiss_drop', 'event', p_event::text, null, jsonb_build_object('user', p_user), null);
end $$;

-- ---------- creazione (nuova funzione: create_event resta com'è) ----------
create or replace function public.create_event_ex(p_name text, p_date date default current_date, p_days integer default null, p_swiss boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); v_id uuid := gen_random_uuid();
begin
  if p_days is not null and (p_days < 1 or p_days > 90) then raise exception 'La durata va da 1 a 90 giorni'; end if;
  if coalesce(p_swiss, false) and p_days is null then raise exception 'Indica la durata del torneo in giorni'; end if;
  insert into public.events (id, name, event_date, created_by, event_format, duration_days)
    values (v_id, btrim(p_name), coalesce(p_date, current_date), v, case when coalesce(p_swiss, false) then 'swiss' else 'manual' end, p_days);
  perform public._audit(v, 'create_event', 'event', v_id::text, null, jsonb_build_object('name', p_name, 'swiss', coalesce(p_swiss, false), 'days', p_days), null);
  return v_id;
end $$;

-- ---------- iscrizione ----------
create or replace function public.swiss_join(p_event uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); e public.events%rowtype; n integer;
begin
  select * into e from public.events where id = p_event for update;
  if not found or e.event_format <> 'swiss' then raise exception 'Questo evento non ha una lobby'; end if;
  if e.event_status <> 'open' then raise exception 'Le iscrizioni sono chiuse'; end if;
  select count(*) into n from public.event_participants where event_id = p_event;
  if n >= 64 and not exists (select 1 from public.event_participants where event_id = p_event and user_id = v) then raise exception 'Il torneo è al completo (64 giocatori)'; end if;
  insert into public.event_participants (event_id, user_id) values (p_event, v) on conflict do nothing;
  return jsonb_build_object('joined', true, 'players', (select count(*) from public.event_participants where event_id = p_event));
end $$;

create or replace function public.swiss_leave(p_event uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); e public.events%rowtype;
begin
  select * into e from public.events where id = p_event;
  if not found or e.event_format <> 'swiss' then raise exception 'Questo evento non ha una lobby'; end if;
  if not exists (select 1 from public.event_participants where event_id = p_event and user_id = v and not dropped) then raise exception 'Non sei iscritto a questo torneo'; end if;
  perform public._swiss_drop(p_event, v, v);
  return jsonb_build_object('left', true);
end $$;

create or replace function public.swiss_kick(p_event uuid, p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]);
begin
  if not public._can_manage_event(p_event, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  if not exists (select 1 from public.events where id = p_event and event_format = 'swiss') then raise exception 'Questo evento non ha una lobby'; end if;
  if not exists (select 1 from public.event_participants where event_id = p_event and user_id = p_user and not dropped) then raise exception 'Il giocatore non è iscritto'; end if;
  perform public._swiss_drop(p_event, p_user, v);
  return jsonb_build_object('removed', true);
end $$;

-- ---------- organizzatore: partenza, turni, conclusione ----------
create or replace function public.swiss_set_rounds(p_event uuid, p_rounds integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); e public.events%rowtype; n integer; mx integer;
begin
  if not public._can_manage_event(p_event, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  select * into e from public.events where id = p_event for update;
  if not found or e.event_format <> 'swiss' then raise exception 'Questo evento non è un torneo svizzero'; end if;
  if e.event_status not in ('open','running') then raise exception 'Il torneo è già concluso o annullato'; end if;
  select count(*) into n from public.event_participants where event_id = p_event and not dropped;
  mx := least(20, greatest(1, n - 1));
  if p_rounds is null or p_rounds < greatest(1, e.current_round) or p_rounds > mx then
    raise exception 'Numero di turni non valido: da % a % (con % giocatori)', greatest(1, e.current_round), mx, n; end if;
  update public.events set rounds_planned = p_rounds where id = p_event;
  return jsonb_build_object('rounds', p_rounds);
end $$;

create or replace function public.swiss_start(p_event uuid, p_rounds integer default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); e public.events%rowtype; n integer; r integer; mx integer; res jsonb;
begin
  if not public._can_manage_event(p_event, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  select * into e from public.events where id = p_event for update;
  if not found or e.event_format <> 'swiss' then raise exception 'Questo evento non è un torneo svizzero'; end if;
  if e.event_status = 'cancelled' then raise exception 'Evento annullato'; end if;
  if e.event_status <> 'open' then raise exception 'Il torneo è già partito'; end if;
  if e.duration_days is not null and public._swiss_today() > e.event_date + e.duration_days - 1 then raise exception 'La durata dell''evento è terminata'; end if;
  select count(*) into n from public.event_participants where event_id = p_event and not dropped;
  if n < 2 then raise exception 'Servono almeno 2 giocatori iscritti (ora %)', n; end if;
  mx := least(20, greatest(1, n - 1));
  r := coalesce(p_rounds, e.rounds_planned, public._swiss_auto_rounds(n));
  if r < 1 or r > mx then raise exception 'Numero di turni non valido: da 1 a % (con % giocatori)', mx, n; end if;
  update public.events set event_status = 'running', rounds_planned = r, current_round = 1, started_at = clock_timestamp() where id = p_event;
  res := public._swiss_make_round(p_event, 1, v);
  perform public._audit(v, 'swiss_start', 'event', p_event::text, null, jsonb_build_object('players', n, 'rounds', r), null);
  return jsonb_build_object('rounds', r, 'round', 1) || res;
end $$;

create or replace function public.swiss_next_round(p_event uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); e public.events%rowtype; pend integer; n integer; res jsonb;
begin
  if not public._can_manage_event(p_event, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  select * into e from public.events where id = p_event for update;
  if not found or e.event_format <> 'swiss' then raise exception 'Questo evento non è un torneo svizzero'; end if;
  if e.event_status <> 'running' then raise exception 'Il torneo non è in corso'; end if;
  select count(*) into pend from public.matches where event_id = p_event and status = 'pending';
  if pend > 0 then raise exception 'Mancano ancora % risultati nel turno %', pend, e.current_round; end if;
  if e.current_round >= e.rounds_planned then raise exception 'Tutti i % turni previsti sono stati giocati: concludi il torneo o aumenta i turni', e.rounds_planned; end if;
  if e.duration_days is not null and public._swiss_today() > e.event_date + e.duration_days - 1 then
    raise exception 'La durata dell''evento è terminata: non si possono creare altri turni, puoi solo concluderlo'; end if;
  select count(*) into n from public.event_participants where event_id = p_event and not dropped;
  if n < 2 then raise exception 'Sono rimasti meno di 2 giocatori: concludi il torneo'; end if;
  update public.events set current_round = current_round + 1 where id = p_event;
  res := public._swiss_make_round(p_event, e.current_round + 1, v);
  perform public._audit(v, 'swiss_next_round', 'event', p_event::text, null, jsonb_build_object('round', e.current_round + 1), null);
  return jsonb_build_object('round', e.current_round + 1) || res;
end $$;

create or replace function public.swiss_finish(p_event uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); e public.events%rowtype; pend integer;
begin
  if not public._can_manage_event(p_event, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  select * into e from public.events where id = p_event for update;
  if not found or e.event_format <> 'swiss' then raise exception 'Questo evento non è un torneo svizzero'; end if;
  if e.event_status <> 'running' then raise exception 'Il torneo non è in corso'; end if;
  select count(*) into pend from public.matches where event_id = p_event and status = 'pending';
  if pend > 0 then raise exception 'Mancano ancora % risultati: registrali o decidili prima di concludere', pend; end if;
  update public.events set event_status = 'finished', finished_at = clock_timestamp() where id = p_event;
  perform public._audit(v, 'swiss_finish', 'event', p_event::text, null, jsonb_build_object('rounds', e.current_round), null);
  return jsonb_build_object('finished', true, 'winner', (select t.user_id from public._swiss_table(p_event) t order by t.rank limit 1));
end $$;

-- ---------- risultati ----------
create or replace function public.swiss_report(p_match uuid, p_winner uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); m public.matches%rowtype; e public.events%rowtype; r public.event_match_reports%rowtype;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'Match inesistente'; end if;
  select * into e from public.events where id = m.event_id;
  if e.event_format <> 'swiss' or e.event_status <> 'running' then raise exception 'Questo match non è in un torneo svizzero in corso'; end if;
  if v not in (m.player_a, m.player_b) then raise exception 'Non giochi questo match'; end if;
  if m.status <> 'pending' then raise exception 'Il risultato è già registrato'; end if;
  if p_winner is null or p_winner not in (m.player_a, m.player_b) then raise exception 'Il vincitore deve essere uno dei due giocatori'; end if;
  select * into r from public.event_match_reports where match_id = p_match for update;
  if not found then
    insert into public.event_match_reports (match_id, reporter_id, winner_id) values (p_match, v, p_winner);
    return jsonb_build_object('state', 'reported');
  end if;
  if r.disputed then raise exception 'Il risultato è contestato: lo decide l''organizzatore'; end if;
  if r.reporter_id = v then
    update public.event_match_reports set winner_id = p_winner, reported_at = clock_timestamp() where match_id = p_match;
    return jsonb_build_object('state', 'reported');
  end if;
  if r.winner_id = p_winner then                      -- l'altro giocatore conferma: il match è ufficiale
    perform public._swiss_close(p_match, p_winner, v);
    return jsonb_build_object('state', 'closed', 'winner', p_winner);
  end if;
  update public.event_match_reports set disputed = true, disputed_by = v where match_id = p_match;     -- indica un altro vincitore: contestazione
  return jsonb_build_object('state', 'disputed');
end $$;

create or replace function public.swiss_dispute(p_match uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); m public.matches%rowtype; r public.event_match_reports%rowtype;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'Match inesistente'; end if;
  if v not in (m.player_a, m.player_b) then raise exception 'Non giochi questo match'; end if;
  if m.status <> 'pending' then raise exception 'Il risultato è già registrato'; end if;
  select * into r from public.event_match_reports where match_id = p_match for update;
  if not found then raise exception 'Nessun risultato da contestare'; end if;
  if r.reporter_id = v then raise exception 'Hai indicato tu questo risultato: puoi correggerlo indicando un altro vincitore'; end if;
  update public.event_match_reports set disputed = true, disputed_by = v where match_id = p_match;
  return jsonb_build_object('state', 'disputed');
end $$;

create or replace function public.swiss_decide(p_match uuid, p_winner uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); m public.matches%rowtype; e public.events%rowtype;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'Match inesistente'; end if;
  if not public._can_manage_event(m.event_id, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  select * into e from public.events where id = m.event_id;
  if e.event_format <> 'swiss' or e.event_status <> 'running' then raise exception 'Questo match non è in un torneo svizzero in corso'; end if;
  if m.status <> 'pending' then raise exception 'Il risultato è già registrato'; end if;
  if p_winner is null or p_winner not in (m.player_a, m.player_b) then raise exception 'Il vincitore deve essere uno dei due giocatori'; end if;
  perform public._swiss_close(p_match, p_winner, v);
  return jsonb_build_object('state', 'closed', 'winner', p_winner);
end $$;

-- ---------- annullamento di qualunque evento ----------
create or replace function public.cancel_event(p_event uuid, p_reason text default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); e public.events%rowtype; r text := nullif(btrim(coalesce(p_reason, '')), '');
        nm integer; verified integer; nd integer := 0;
begin
  if not public._can_manage_event(p_event, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  select * into e from public.events where id = p_event for update;
  if not found then raise exception 'Evento inesistente'; end if;
  if e.event_status = 'cancelled' then raise exception 'Evento già annullato'; end if;
  if coalesce(to_jsonb(e)->>'source', '') = 'ladder' then raise exception 'L''evento automatico della Ladder non si può annullare'; end if;
  if r is not null and char_length(r) > 200 then raise exception 'Motivo troppo lungo (max 200 caratteri)'; end if;
  with d as (delete from public.matches where event_id = p_event and status = 'pending' returning 1) select count(*) into nm from d;
  select count(*) into verified from public.matches where event_id = p_event and status = 'verified';
  if verified = 0 then
    with d as (delete from public.event_participants where event_id = p_event and not rewarded returning 1) select count(*) into nd from d;
  end if;
  update public.events set event_status = 'cancelled', cancelled_at = clock_timestamp(), cancelled_by = v, cancel_reason = r where id = p_event;
  perform public._audit(v, 'cancel_event', 'event', p_event::text, to_jsonb(e), jsonb_build_object('pending_removed', nm, 'verified_kept', verified), r);
  return jsonb_build_object('cancelled', true, 'pending_removed', nm, 'verified_kept', verified, 'registrations_removed', nd);
end $$;

-- ---------- stato per la pagina ----------
create or replace function public.swiss_state(p_event uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); e public.events%rowtype;
        n integer; pend integer; mng boolean; ends date; expired boolean; mx integer; jn boolean; dr boolean; running boolean;
begin
  select * into e from public.events where id = p_event;
  if not found then raise exception 'Evento inesistente'; end if;
  mng := public._can_manage_event(p_event, v);
  select count(*) into n from public.event_participants where event_id = p_event and not dropped;
  select count(*) into pend from public.matches where event_id = p_event and status = 'pending';
  select true, ep.dropped into jn, dr from public.event_participants ep where ep.event_id = p_event and ep.user_id = v;
  jn := coalesce(jn, false); dr := coalesce(dr, false);
  ends := case when e.duration_days is null then null else e.event_date + e.duration_days - 1 end;
  expired := ends is not null and public._swiss_today() > ends;
  mx := least(20, greatest(1, n - 1));
  running := e.event_status = 'running';
  return jsonb_build_object(
    'event', jsonb_build_object('id', e.id, 'name', e.name, 'date', e.event_date, 'format', e.event_format, 'status', e.event_status, 'duration_days', e.duration_days, 'ends_on', ends,
              'expired', expired, 'rounds_planned', e.rounds_planned, 'current_round', e.current_round, 'organizer_id', e.created_by, 'organizer', (select nickname from public.profiles where id = e.created_by),
              'cancel_reason', e.cancel_reason, 'cancelled_at', e.cancelled_at, 'finished_at', e.finished_at),
    'is_organizer', mng, 'me', jsonb_build_object('id', v, 'joined', jn, 'dropped', dr),
    'n_active', n, 'n_total', (select count(*) from public.event_participants where event_id = p_event), 'auto_rounds', public._swiss_auto_rounds(n), 'max_rounds', mx, 'pending', pend,
    'can', jsonb_build_object(
      'join', e.event_format = 'swiss' and e.event_status = 'open' and not jn,
      'leave', e.event_format = 'swiss' and jn and not dr and e.event_status in ('open','running'),
      'start', mng and e.event_format = 'swiss' and e.event_status = 'open' and n >= 2 and not expired,
      'next', mng and e.event_format = 'swiss' and running and pend = 0 and e.current_round < e.rounds_planned and not expired and n >= 2,
      'finish', mng and e.event_format = 'swiss' and running and pend = 0,
      'set_rounds', mng and e.event_format = 'swiss' and e.event_status in ('open','running'),
      'cancel', mng and e.event_status <> 'cancelled' and coalesce(to_jsonb(e)->>'source', '') <> 'ladder'),
    'players', coalesce((select jsonb_agg(jsonb_build_object('user_id', t.user_id, 'nickname', pr.nickname, 'dropped', t.dropped, 'rank', t.rank, 'points', t.points, 'wins', t.wins,
                          'losses', t.losses, 'byes', t.byes, 'omw', t.omw) order by t.rank) from public._swiss_table(p_event) t join public.profiles pr on pr.id = t.user_id), '[]'::jsonb),
    'rounds', coalesce((select jsonb_agg(jsonb_build_object('round', x.round,
        'matches', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'a', m.player_a, 'b', m.player_b, 'a_nick', pa.nickname, 'b_nick', pb.nickname, 'status', m.status, 'winner', m.winner_id,
                      'reported_by', rp.reporter_id, 'reported_winner', rp.winner_id, 'disputed', coalesce(rp.disputed, false)) order by m.created_at, m.id), '[]'::jsonb)
                    from public.matches m join public.profiles pa on pa.id = m.player_a join public.profiles pb on pb.id = m.player_b
                    left join public.event_match_reports rp on rp.match_id = m.id where m.event_id = p_event and m.round = x.round),
        'byes', (select coalesce(jsonb_agg(jsonb_build_object('user_id', b.user_id, 'nickname', pr.nickname, 'kind', b.kind) order by pr.nickname), '[]'::jsonb)
                 from public.event_byes b join public.profiles pr on pr.id = b.user_id where b.event_id = p_event and b.round = x.round)) order by x.round desc)
      from (select round from public.matches where event_id = p_event union select round from public.event_byes where event_id = p_event) x), '[]'::jsonb));
end $$;

-- ---------- permessi ----------
revoke all on function public._swiss_today(), public._swiss_auto_rounds(integer), public._swiss_table(uuid), public._swiss_try(uuid, uuid[], boolean),
  public._swiss_make_round(uuid, integer, uuid), public._swiss_close(uuid, uuid, uuid), public._swiss_drop(uuid, uuid, uuid), public._trg_matches_event_guard() from public, anon, authenticated;
revoke all on function public.create_event_ex(text, date, integer, boolean), public.swiss_join(uuid), public.swiss_leave(uuid), public.swiss_kick(uuid, uuid), public.swiss_set_rounds(uuid, integer),
  public.swiss_start(uuid, integer), public.swiss_next_round(uuid), public.swiss_finish(uuid), public.swiss_report(uuid, uuid), public.swiss_dispute(uuid), public.swiss_decide(uuid, uuid),
  public.cancel_event(uuid, text), public.swiss_state(uuid) from public, anon;
grant execute on function public.create_event_ex(text, date, integer, boolean), public.swiss_join(uuid), public.swiss_leave(uuid), public.swiss_kick(uuid, uuid), public.swiss_set_rounds(uuid, integer),
  public.swiss_start(uuid, integer), public.swiss_next_round(uuid), public.swiss_finish(uuid), public.swiss_report(uuid, uuid), public.swiss_dispute(uuid), public.swiss_decide(uuid, uuid),
  public.cancel_event(uuid, text), public.swiss_state(uuid) to authenticated;
commit;
