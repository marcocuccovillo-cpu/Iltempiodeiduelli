-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 003: Ladder (classifica Elo con sfide) + immagine avatar del profilo.
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO black-market-setup.sql (001) e black-market-moduli.sql (002).
--
-- Cosa aggiunge (tutto nuovo, nulla di esistente viene modificato o cancellato):
--  * profiles.avatar_img + set_my_avatar_img(): immagine del profilo (foto ridotta, salvata nel profilo);
--  * Ladder: sfida a un duellante -> accettazione -> risultato inviato da uno e CONFERMATO DALL'ALTRO -> Elo aggiornato;
--    contestazione e risoluzione da parte dell'amministratore; scadenze; limite di match al giorno tra gli stessi due.
--  * La Ladder è separata dal Black Market: nessun BC, nessuna taglia e nessun match ufficiale WPA vengono toccati.
--  * Interruttore module_ladder (ATTIVO per impostazione iniziale; si spegne da Admin) controllato anche dal database.
--  * admin_set_module() viene riscritta per accettare anche 'ladder' (stessa logica e stesso audit della 002).
-- Annullamento: black-market-ladder-down.sql.
-- =====================================================================
begin;  -- tutto o niente

insert into public.system_settings (key, value_int, description) values
 ('module_ladder',          1,    'Ladder (classifica Elo): 1 = attiva, 0 = spenta'),
 ('ladder_start_elo',       1000, 'Ladder: Elo iniziale di un nuovo giocatore'),
 ('ladder_k',               32,   'Ladder: fattore K dell''Elo (quanto si muove la classifica a ogni match)'),
 ('ladder_expiry_days',     7,    'Ladder: giorni di validità di una sfida non accettata'),
 ('ladder_stale_days',      30,   'Ladder: giorni dopo i quali una sfida accettata ma senza risultato scade'),
 ('ladder_max_open',        5,    'Ladder: massimo di sfide aperte lanciate da un utente'),
 ('ladder_max_pair_per_day',3,    'Ladder: massimo di match conclusi nelle 24 ore tra gli stessi due duellanti')
on conflict (key) do nothing;

-- ---------- Immagine avatar ----------
alter table public.profiles add column avatar_img text
  check (avatar_img is null or (char_length(avatar_img) <= 24000 and avatar_img ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$'));

create function public.set_my_avatar_img(p_img text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
begin
  if p_img is not null then
    if char_length(p_img) > 24000 then raise exception 'Immagine troppo grande: scegli una foto più piccola'; end if;
    if p_img !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' then raise exception 'Formato immagine non valido'; end if;
  end if;
  update public.profiles set avatar_img = p_img where id = v;
end $$;

-- ---------- Interruttori: ora anche 'ladder' ----------
create or replace function public.admin_set_module(p_module text, p_enabled boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o integer;
begin
  if p_module not in ('hall_of_fame','faction_wars','underground','ladder') then raise exception 'Modulo sconosciuto'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select value_int into o from public.system_settings where key = 'module_' || p_module for update;
  if not found then raise exception 'Impostazione inesistente: esegui le migrazioni 002 e 003'; end if;
  update public.system_settings set value_int = case when p_enabled then 1 else 0 end, updated_at = now(), updated_by = v where key = 'module_' || p_module;
  perform public._audit(v, 'set_module', 'module', p_module, jsonb_build_object('enabled', o = 1), jsonb_build_object('enabled', p_enabled), p_reason);
end $$;

-- ---------- Tabelle ----------
create table public.ladder_ratings (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  elo integer not null check (elo between 0 and 5000),
  wins integer not null default 0 check (wins >= 0),
  draws integer not null default 0 check (draws >= 0),
  losses integer not null default 0 check (losses >= 0),
  last_match_at timestamptz
);
create index ladder_ratings_elo_idx on public.ladder_ratings (elo desc);

create table public.ladder_matches (
  id uuid primary key default gen_random_uuid(),
  challenger_id uuid not null references public.profiles(id) on delete restrict,
  opponent_id uuid not null references public.profiles(id) on delete restrict,
  format text not null check (format in ('Advanced','Traditional','GOAT','Edison')),
  message text check (message is null or char_length(message) <= 140),
  client_request_id text not null check (char_length(client_request_id) >= 8),
  status text not null default 'pending' check (status in ('pending','accepted','reported','disputed','closed','declined','cancelled','expired','voided')),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  responded_at timestamptz,
  reported_by uuid references public.profiles(id),
  reported_result text check (reported_result in ('challenger','opponent','draw')),
  reported_score text,
  reported_at timestamptz,
  dispute_reason text,
  confirmed_by uuid references public.profiles(id),
  closed_at timestamptz,
  resolved_by uuid references public.profiles(id),
  resolution_reason text,
  elo_challenger_before integer,
  elo_opponent_before integer,
  elo_challenger_delta integer,
  elo_opponent_delta integer,
  check (challenger_id <> opponent_id),
  -- il punteggio (partite del lanciatore per prime) deve combaciare con l'esito
  check (reported_score is null or (reported_result = 'challenger' and reported_score in ('2-0','2-1'))
                                or (reported_result = 'opponent' and reported_score in ('0-2','1-2'))
                                or (reported_result = 'draw' and reported_score = '1-1')),
  check (status <> 'closed' or (reported_result is not null and elo_challenger_delta is not null and elo_opponent_delta is not null
                                and elo_challenger_delta + elo_opponent_delta = 0)),
  unique (challenger_id, client_request_id)
);
-- una sola sfida aperta per coppia (qualunque sia chi ha sfidato)
create unique index ladder_matches_open_pair on public.ladder_matches (least(challenger_id, opponent_id), greatest(challenger_id, opponent_id))
  where status in ('pending','accepted','reported','disputed');
create index ladder_matches_challenger_idx on public.ladder_matches (challenger_id, status);
create index ladder_matches_opponent_idx on public.ladder_matches (opponent_id, status);
create index ladder_matches_closed_idx on public.ladder_matches (closed_at desc) where status = 'closed';

create function public._ladder_guard() returns trigger language plpgsql as $$
begin
  if old.status in ('closed','declined','cancelled','expired','voided') then
    raise exception 'Match della Ladder già concluso: non è più modificabile'; end if;
  return new;
end $$;
create trigger ladder_matches_guard before update on public.ladder_matches for each row execute function public._ladder_guard();
create trigger ladder_matches_no_delete before delete on public.ladder_matches for each row execute function public._no_delete();
create trigger ladder_ratings_no_delete before delete on public.ladder_ratings for each row execute function public._no_delete();

-- ---------- Funzione interna: chiude un match e aggiorna l'Elo (un solo punto di calcolo) ----------
create function public._ladder_close(p_id uuid, p_result text, p_score text, p_confirmer uuid, p_resolver uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.ladder_matches%rowtype; start_elo integer := coalesce(public._setting('ladder_start_elo'), 1000);
        k integer := coalesce(public._setting('ladder_k'), 32); ea integer; eo integer; s numeric; da integer;
begin
  select * into m from public.ladder_matches where id = p_id for update;
  if m.status not in ('accepted','reported','disputed') then raise exception 'Il match non è chiudibile'; end if;
  insert into public.ladder_ratings (user_id, elo) values (m.challenger_id, start_elo), (m.opponent_id, start_elo) on conflict do nothing;
  perform 1 from public.ladder_ratings where user_id in (m.challenger_id, m.opponent_id) order by user_id for update;   -- ordine fisso: niente blocchi incrociati
  select elo into ea from public.ladder_ratings where user_id = m.challenger_id;
  select elo into eo from public.ladder_ratings where user_id = m.opponent_id;
  s := case p_result when 'challenger' then 1.0 when 'opponent' then 0.0 else 0.5 end;
  da := round(k * (s - 1.0 / (1.0 + power(10.0, (eo - ea) / 400.0))))::integer;
  update public.ladder_ratings set elo = greatest(0, elo + da), last_match_at = clock_timestamp(),
    wins = wins + (p_result = 'challenger')::integer, draws = draws + (p_result = 'draw')::integer, losses = losses + (p_result = 'opponent')::integer
    where user_id = m.challenger_id;
  update public.ladder_ratings set elo = greatest(0, elo - da), last_match_at = clock_timestamp(),
    wins = wins + (p_result = 'opponent')::integer, draws = draws + (p_result = 'draw')::integer, losses = losses + (p_result = 'challenger')::integer
    where user_id = m.opponent_id;
  update public.ladder_matches set status = 'closed', reported_result = p_result, reported_score = p_score, closed_at = clock_timestamp(),
    confirmed_by = p_confirmer, resolved_by = p_resolver, resolution_reason = p_reason,
    elo_challenger_before = ea, elo_opponent_before = eo, elo_challenger_delta = da, elo_opponent_delta = -da
    where id = p_id;
  return jsonb_build_object('challenger_delta', da, 'opponent_delta', -da, 'challenger_elo', ea + da, 'opponent_elo', eo - da);
end $$;

-- ---------- Funzioni dei giocatori ----------
create function public.ladder_expire() returns integer language plpgsql security definer set search_path = public as $$
declare n integer; n2 integer;
begin
  perform public._require_module('ladder');
  perform public._need_role(array['user','organizer','admin']::public.app_role[]);
  update public.ladder_matches set status = 'expired' where status = 'pending' and expires_at <= clock_timestamp();
  get diagnostics n = row_count;
  update public.ladder_matches set status = 'expired'
    where status = 'accepted' and responded_at <= clock_timestamp() - make_interval(days => coalesce(public._setting('ladder_stale_days'), 30));
  get diagnostics n2 = row_count;
  if n + n2 > 0 then perform public._audit(null, 'ladder_expire', 'ladder_match', null, null, jsonb_build_object('count', n + n2), 'scadenza automatica'); end if;
  return n + n2;
end $$;

create function public.ladder_challenge(p_opponent uuid, p_format text, p_message text, p_request_id text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid; v_id uuid := gen_random_uuid(); ex uuid;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  if p_request_id is null or char_length(p_request_id) < 8 then raise exception 'Richiesta non valida'; end if;
  select id into ex from public.ladder_matches where challenger_id = v and client_request_id = p_request_id;
  if found then return ex; end if;                                               -- richiesta ripetuta: nessuna doppia sfida
  if p_opponent is null or p_opponent = v then raise exception 'Scegli un altro duellante'; end if;
  if p_format is null or p_format not in ('Advanced','Traditional','GOAT','Edison') then raise exception 'Formato non valido'; end if;
  if not exists (select 1 from public.profiles where id = p_opponent and not suspended) then raise exception 'Duellante non disponibile'; end if;
  perform 1 from public.profiles where id = v for update;                        -- serializza le sfide dello stesso utente
  if (select count(*) from public.ladder_matches where challenger_id = v and status in ('pending','accepted','reported','disputed'))
       >= coalesce(public._setting('ladder_max_open'), 5) then raise exception 'Hai troppe sfide aperte'; end if;
  if (select count(*) from public.ladder_matches where status = 'closed' and closed_at > clock_timestamp() - interval '24 hours'
        and least(challenger_id, opponent_id) = least(v, p_opponent) and greatest(challenger_id, opponent_id) = greatest(v, p_opponent))
       >= coalesce(public._setting('ladder_max_pair_per_day'), 3) then raise exception 'Limite giornaliero di match con questo duellante raggiunto'; end if;
  begin
    insert into public.ladder_matches (id, challenger_id, opponent_id, format, message, client_request_id, expires_at)
    values (v_id, v, p_opponent, p_format, nullif(btrim(p_message), ''), p_request_id, clock_timestamp() + make_interval(days => coalesce(public._setting('ladder_expiry_days'), 7)));
  exception when unique_violation then raise exception 'Esiste già una sfida aperta con questo duellante';
            when check_violation then raise exception 'Dati della sfida non validi'; end;
  perform public._audit(v, 'ladder_challenge', 'ladder_match', v_id::text, null, jsonb_build_object('opponent', p_opponent, 'format', p_format), null);
  return v_id;
end $$;

create function public.ladder_respond(p_id uuid, p_accept boolean) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into m from public.ladder_matches where id = p_id for update;
  if not found or m.opponent_id <> v then raise exception 'Sfida non trovata'; end if;
  if m.status <> 'pending' then raise exception 'La sfida non è più in attesa'; end if;
  if m.expires_at <= clock_timestamp() then raise exception 'Sfida scaduta'; end if;
  update public.ladder_matches set status = case when p_accept then 'accepted' else 'declined' end, responded_at = clock_timestamp() where id = p_id;
  perform public._audit(v, case when p_accept then 'ladder_accept' else 'ladder_decline' end, 'ladder_match', p_id::text, null, null, null);
end $$;

create function public.ladder_cancel(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into m from public.ladder_matches where id = p_id for update;
  if not found or v not in (m.challenger_id, m.opponent_id) then raise exception 'Sfida non trovata'; end if;
  if m.status = 'pending' and v <> m.challenger_id then raise exception 'Solo chi ha lanciato la sfida può annullarla prima della risposta'; end if;
  if m.status not in ('pending','accepted') then raise exception 'La sfida non può più essere annullata'; end if;
  update public.ladder_matches set status = 'cancelled' where id = p_id;
  perform public._audit(v, 'ladder_cancel', 'ladder_match', p_id::text, null, null, null);
end $$;

-- p_result: 'challenger' | 'opponent' | 'draw'; p_score: partite del lanciatore per prime ('2-0','2-1','0-2','1-2','1-1')
create function public.ladder_report(p_id uuid, p_result text, p_score text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into m from public.ladder_matches where id = p_id for update;
  if not found or v not in (m.challenger_id, m.opponent_id) then raise exception 'Match non trovato'; end if;
  if m.status <> 'accepted' then raise exception 'Il risultato si può inviare solo per un match accettato e non ancora riportato'; end if;
  if p_result not in ('challenger','opponent','draw') then raise exception 'Esito non valido'; end if;
  if not ((p_result = 'challenger' and p_score in ('2-0','2-1')) or (p_result = 'opponent' and p_score in ('0-2','1-2')) or (p_result = 'draw' and p_score = '1-1'))
    then raise exception 'Il punteggio non corrisponde all''esito'; end if;
  update public.ladder_matches set status = 'reported', reported_by = v, reported_result = p_result, reported_score = p_score, reported_at = clock_timestamp() where id = p_id;
  perform public._audit(v, 'ladder_report', 'ladder_match', p_id::text, null, jsonb_build_object('result', p_result, 'score', p_score), null);
end $$;

-- Conferma: solo l'ALTRO giocatore (chi ha inviato il risultato non può confermarlo da solo)
create function public.ladder_confirm(p_id uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype; r jsonb;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into m from public.ladder_matches where id = p_id for update;
  if not found or v not in (m.challenger_id, m.opponent_id) then raise exception 'Match non trovato'; end if;
  if m.status <> 'reported' then raise exception 'Non c''è un risultato da confermare'; end if;
  if m.reported_by = v then raise exception 'Il risultato deve essere confermato dall''altro giocatore'; end if;
  if (select count(*) from public.ladder_matches where status = 'closed' and closed_at > clock_timestamp() - interval '24 hours'
        and least(challenger_id, opponent_id) = least(m.challenger_id, m.opponent_id) and greatest(challenger_id, opponent_id) = greatest(m.challenger_id, m.opponent_id))
       >= coalesce(public._setting('ladder_max_pair_per_day'), 3) then raise exception 'Limite giornaliero di match tra questi duellanti raggiunto: un amministratore può risolvere il caso'; end if;
  r := public._ladder_close(p_id, m.reported_result, m.reported_score, v, null, null);
  perform public._audit(v, 'ladder_confirm', 'ladder_match', p_id::text, null, r, null);
  return r;
end $$;

create function public.ladder_dispute(p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Spiega il motivo (almeno 5 caratteri)'; end if;
  select * into m from public.ladder_matches where id = p_id for update;
  if not found or v not in (m.challenger_id, m.opponent_id) then raise exception 'Match non trovato'; end if;
  if m.status <> 'reported' then raise exception 'Non c''è un risultato da contestare'; end if;
  if m.reported_by = v then raise exception 'Hai inviato tu il risultato: puoi solo annullare la sfida o attendere la conferma'; end if;
  update public.ladder_matches set status = 'disputed', dispute_reason = btrim(p_reason) where id = p_id;
  perform public._audit(v, 'ladder_dispute', 'ladder_match', p_id::text, null, null, btrim(p_reason));
end $$;

-- ---------- Funzioni amministrative ----------
create function public.admin_ladder_resolve(p_id uuid, p_result text, p_score text, p_reason text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype; r jsonb;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into m from public.ladder_matches where id = p_id for update;
  if not found then raise exception 'Match non trovato'; end if;
  if m.status not in ('accepted','reported','disputed') then raise exception 'Il match non è risolvibile in questo stato'; end if;
  if not ((p_result = 'challenger' and p_score in ('2-0','2-1')) or (p_result = 'opponent' and p_score in ('0-2','1-2')) or (p_result = 'draw' and p_score = '1-1'))
    then raise exception 'Esito o punteggio non validi'; end if;
  r := public._ladder_close(p_id, p_result, p_score, null, v, btrim(p_reason));
  perform public._audit(v, 'admin_ladder_resolve', 'ladder_match', p_id::text, jsonb_build_object('status', m.status), r || jsonb_build_object('result', p_result, 'score', p_score), btrim(p_reason));
  return r;
end $$;

create function public.admin_ladder_void(p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into m from public.ladder_matches where id = p_id for update;
  if not found then raise exception 'Match non trovato'; end if;
  if m.status not in ('pending','accepted','reported','disputed') then raise exception 'Il match è già concluso'; end if;
  update public.ladder_matches set status = 'voided', resolved_by = v, resolution_reason = btrim(p_reason), closed_at = clock_timestamp() where id = p_id;
  perform public._audit(v, 'admin_ladder_void', 'ladder_match', p_id::text, jsonb_build_object('status', m.status), null, btrim(p_reason));
end $$;

-- ---------- Viste ----------
create view public.ladder_standings_v as
  select r.user_id, p.nickname, p.avatar, r.elo, r.wins, r.draws, r.losses,
         (r.wins + r.draws + r.losses)::integer as matches, r.last_match_at,
         rank() over (order by r.elo desc, r.wins desc)::integer as rank
  from public.ladder_ratings r join public.profiles p on p.id = r.user_id
  where public._module_on('ladder');

-- ---------- Row Level Security ----------
alter table public.ladder_ratings enable row level security;
alter table public.ladder_matches enable row level security;
create policy ladder_ratings_read on public.ladder_ratings for select to authenticated
  using (public._module_on('ladder') or public.is_admin());
-- i match conclusi sono pubblici (storico); quelli in corso li vedono solo i due giocatori e l'amministratore
create policy ladder_matches_read on public.ladder_matches for select to authenticated
  using (public.is_admin() or (public._module_on('ladder') and (status = 'closed' or challenger_id = auth.uid() or opponent_id = auth.uid())));

-- ---------- Permessi: nessuna scrittura diretta ----------
revoke all on public.ladder_ratings, public.ladder_matches, public.ladder_standings_v from public, anon, authenticated;
grant select on public.ladder_ratings, public.ladder_matches, public.ladder_standings_v to authenticated;
revoke all on function public._ladder_guard(), public._ladder_close(uuid, text, text, uuid, uuid, text), public.set_my_avatar_img(text),
  public.ladder_expire(), public.ladder_challenge(uuid, text, text, text), public.ladder_respond(uuid, boolean), public.ladder_cancel(uuid),
  public.ladder_report(uuid, text, text), public.ladder_confirm(uuid), public.ladder_dispute(uuid, text),
  public.admin_ladder_resolve(uuid, text, text, text), public.admin_ladder_void(uuid, text), public.admin_set_module(text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.set_my_avatar_img(text),
  public.ladder_expire(), public.ladder_challenge(uuid, text, text, text), public.ladder_respond(uuid, boolean), public.ladder_cancel(uuid),
  public.ladder_report(uuid, text, text), public.ladder_confirm(uuid), public.ladder_dispute(uuid, text),
  public.admin_ladder_resolve(uuid, text, text, text), public.admin_ladder_void(uuid, text), public.admin_set_module(text, boolean, text)
  to authenticated;

commit;
