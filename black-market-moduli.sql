-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 002: Hall of Fame, Faction Wars, Underground Challenges.
-- Da eseguire DOPO black-market-setup.sql (migrazione 001), una sola volta.
--
-- Garanzie:
--  * nessuna tabella, funzione o dato della 001 viene modificato o cancellato;
--  * i tre moduli nascono SPENTI (impostazioni module_* = 0);
--  * lo stato dei moduli è controllato dal database: con il modulo spento le viste restano vuote,
--    le tabelle non sono leggibili (salvo agli admin) e ogni funzione di scrittura rifiuta l'operazione;
--  * nessuna funzione di questi moduli tocca wallet, registro contabile, taglie o match;
--  * punteggi e statistiche si calcolano sempre dalle fonti ufficiali (matches, event_participants,
--    bounty_settlements): niente copie che possano andare fuori sincrono.
-- Annullamento: black-market-moduli-down.sql (cancella SOLO ciò che crea questa migrazione).
-- =====================================================================

-- ---------- Impostazioni (riuso di system_settings; interruttori inizialmente a 0) ----------
begin;  -- tutto o niente: se qualcosa fallisce, non resta nulla a metà
insert into public.system_settings (key, value_int, description) values
 ('module_hall_of_fame',      0, 'Modulo Hall of Fame: 1 = attivo, 0 = spento'),
 ('module_faction_wars',      0, 'Modulo Faction Wars: 1 = attivo, 0 = spento'),
 ('module_underground',       0, 'Modulo Underground Challenges: 1 = attivo, 0 = spento'),
 ('hof_rivalry_min_matches',  3, 'Hall of Fame: match verificati minimi tra due duellanti per contare come rivalità'),
 ('faction_points_per_win',   3, 'Faction Wars: punti per ogni vittoria verificata (separati dai BC)'),
 ('faction_cooldown_days',    7, 'Faction Wars: giorni di attesa dopo aver lasciato una fazione'),
 ('faction_max_members',     20, 'Faction Wars: massimo di membri per fazione'),
 ('challenge_expiry_days',    7, 'Underground: giorni di validità di una sfida non accettata'),
 ('challenge_max_open',       5, 'Underground: massimo di sfide aperte create da un utente')
on conflict (key) do nothing;

-- ---------- Funzioni di supporto ----------
create function public._module_on(p_module text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select value_int = 1 from public.system_settings where key = 'module_' || p_module), false) $$;

create function public._require_module(p_module text) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public._module_on(p_module) then raise exception 'Modulo non attivo'; end if;
end $$;

create function public._no_delete() returns trigger language plpgsql as $$
begin raise exception 'Storico protetto: cancellazione non consentita su %', tg_table_name; end $$;

-- ---------- Stagioni (condivise da Hall of Fame e Faction Wars) ----------
create table public.seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 3 and 40),
  starts_on date not null,
  ends_on date not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on),
  exclude using gist (daterange(starts_on, ends_on, '[]') with &&)     -- le stagioni non si sovrappongono
);
create unique index seasons_name_lower on public.seasons (lower(btrim(name)));
create trigger seasons_no_delete before delete on public.seasons for each row execute function public._no_delete();

-- ---------- Faction Wars ----------
create table public.factions (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 3 and 30),
  description text check (description is null or char_length(description) <= 200),
  symbol text check (symbol is null or char_length(symbol) <= 8),
  founder_id uuid not null references public.profiles(id),
  status text not null default 'active' check (status in ('active','disbanded')),
  created_at timestamptz not null default clock_timestamp(),
  disbanded_at timestamptz,
  check ((status = 'disbanded') = (disbanded_at is not null))
);
create unique index factions_name_lower on public.factions (lower(btrim(name)));
create trigger factions_no_delete before delete on public.factions for each row execute function public._no_delete();

create table public.faction_members (          -- ogni riga è un periodo di appartenenza: lo storico non si cancella
  id uuid primary key default gen_random_uuid(),
  faction_id uuid not null references public.factions(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  role text not null default 'member' check (role in ('leader','member')),
  joined_at timestamptz not null default clock_timestamp(),
  left_at timestamptz,
  check (left_at is null or left_at >= joined_at)
);
create unique index faction_members_one_active on public.faction_members (user_id) where left_at is null;      -- una sola fazione alla volta
create unique index faction_members_one_leader on public.faction_members (faction_id) where left_at is null and role = 'leader';
create index faction_members_faction_idx on public.faction_members (faction_id, joined_at);
create index faction_members_user_idx on public.faction_members (user_id, joined_at);
create trigger faction_members_no_delete before delete on public.faction_members for each row execute function public._no_delete();

create table public.faction_match_exclusions ( -- caso eccezionale: un match escluso dal punteggio dall'admin (con motivazione)
  match_id uuid primary key references public.matches(id) on delete restrict,
  reason text not null check (char_length(btrim(reason)) >= 5),
  excluded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

-- ---------- Underground Challenges ----------
create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  challenger_id uuid not null references public.profiles(id) on delete restrict,
  opponent_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled','expired','in_progress','completed')),
  message text check (message is null or char_length(message) <= 140),
  client_request_id text not null,
  match_id uuid unique references public.matches(id) on delete restrict,   -- un match può servire una sola sfida
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  responded_at timestamptz,
  linked_at timestamptz,
  completed_at timestamptz,
  completed_by uuid references public.profiles(id),
  cancelled_by uuid references public.profiles(id),
  cancel_reason text,
  check (challenger_id <> opponent_id),
  check (match_id is not null or status not in ('in_progress','completed')),
  check ((status = 'completed') = (completed_at is not null)),
  unique (challenger_id, client_request_id)
);
create unique index challenges_open_pair on public.challenges
  (least(challenger_id, opponent_id), greatest(challenger_id, opponent_id)) where status in ('pending','accepted','in_progress');
create index challenges_challenger_idx on public.challenges (challenger_id, status);
create index challenges_opponent_idx on public.challenges (opponent_id, status);
create trigger challenges_no_delete before delete on public.challenges for each row execute function public._no_delete();

-- ---------- Interruttori ----------
create function public.admin_set_module(p_module text, p_enabled boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o integer;
begin
  if p_module not in ('hall_of_fame','faction_wars','underground') then raise exception 'Modulo sconosciuto'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select value_int into o from public.system_settings where key = 'module_' || p_module for update;
  if not found then raise exception 'Impostazione inesistente: esegui la migrazione 002'; end if;
  update public.system_settings set value_int = case when p_enabled then 1 else 0 end, updated_at = now(), updated_by = v where key = 'module_' || p_module;
  perform public._audit(v, 'set_module', 'module', p_module, jsonb_build_object('enabled', o = 1), jsonb_build_object('enabled', p_enabled), p_reason);
end $$;

create function public.admin_create_season(p_name text, p_start date, p_end date, p_reason text) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); v_id uuid := gen_random_uuid();
begin
  if not (public._module_on('hall_of_fame') or public._module_on('faction_wars')) then raise exception 'Modulo non attivo'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  begin
    insert into public.seasons (id, name, starts_on, ends_on, created_by) values (v_id, btrim(p_name), p_start, p_end, v);
  exception when exclusion_violation then raise exception 'La stagione si sovrappone a una già esistente';
            when unique_violation then raise exception 'Esiste già una stagione con questo nome';
            when check_violation then raise exception 'Dati della stagione non validi';
  end;
  perform public._audit(v, 'create_season', 'season', v_id::text, null, jsonb_build_object('name', btrim(p_name), 'starts_on', p_start, 'ends_on', p_end), p_reason);
  return v_id;
end $$;

-- =====================================================================
-- HALL OF FAME — solo viste di lettura sulle fonti ufficiali (match VERIFICATI, partecipazioni, riscossioni).
-- Con il modulo spento ogni vista è vuota.
-- =====================================================================
create view public.hof_matches_v as
  select m.id as match_id, m.event_id, e.name as event_name, e.event_date, m.round, m.player_a, m.player_b, m.winner_id,
         case when m.winner_id = m.player_a then m.player_b else m.player_a end as loser_id, m.verified_at
  from public.matches m join public.events e on e.id = m.event_id
  where m.status = 'verified' and public._module_on('hall_of_fame');

create view public.hof_player_stats_v as
  select p.id as player_id, p.nickname, p.avatar,
         (select count(*) from public.hof_matches_v h where h.winner_id = p.id)::integer as wins,
         (select count(*) from public.hof_matches_v h where h.loser_id = p.id)::integer as losses,
         (select count(*) from public.event_participants ep where ep.user_id = p.id)::integer as events_participated,
         (select count(*) from public.bounty_settlements s where s.winner_id = p.id and s.quotas_count > 0)::integer as bounty_claims,
         (select coalesce(sum(s.payout), 0) from public.bounty_settlements s where s.winner_id = p.id and s.quotas_count > 0)::integer as bounty_payout_total
  from public.profiles p where not p.suspended and public._module_on('hall_of_fame');

create view public.hof_season_stats_v as
  select s.id as season_id, p.id as player_id, p.nickname,
         (select count(*) from public.hof_matches_v h where h.winner_id = p.id and h.event_date between s.starts_on and s.ends_on)::integer as wins,
         (select count(*) from public.hof_matches_v h where h.loser_id = p.id and h.event_date between s.starts_on and s.ends_on)::integer as losses,
         (select count(*) from public.event_participants ep join public.events e on e.id = ep.event_id
            where ep.user_id = p.id and e.event_date between s.starts_on and s.ends_on)::integer as events_participated
  from public.seasons s cross join public.profiles p where not p.suspended and public._module_on('hall_of_fame');

create view public.hof_claims_v as
  select s.id as settlement_id, s.match_id, s.winner_id, s.target_id, s.payout, s.refunded, s.created_at
  from public.bounty_settlements s where s.quotas_count > 0 and public._module_on('hall_of_fame');

create view public.hof_rivalries_v as
  select least(h.player_a, h.player_b) as player_1, greatest(h.player_a, h.player_b) as player_2,
         count(*)::integer as matches,
         count(*) filter (where h.winner_id = least(h.player_a, h.player_b))::integer as player_1_wins,
         count(*) filter (where h.winner_id = greatest(h.player_a, h.player_b))::integer as player_2_wins,
         max(h.verified_at) as last_at
  from public.hof_matches_v h
  group by least(h.player_a, h.player_b), greatest(h.player_a, h.player_b)
  having count(*) >= greatest(coalesce(public._setting('hof_rivalry_min_matches'), 3), 2);

create view public.hof_events_v as
  select e.id as event_id, e.name, e.event_date,
         (select count(*) from public.matches m where m.event_id = e.id)::integer as matches_total,
         (select count(*) from public.matches m where m.event_id = e.id and m.status = 'verified')::integer as matches_verified,
         (select count(*) from public.event_participants ep where ep.event_id = e.id)::integer as participants
  from public.events e where public._module_on('hall_of_fame');

create view public.hof_milestones_v as
  with nw as (
    select winner_id as player_id, match_id, verified_at,
           row_number() over (partition by winner_id order by verified_at, match_id) as n
    from public.hof_matches_v)
  select player_id, 'wins_' || n as milestone, verified_at as achieved_at, match_id as ref_id from nw where n in (1, 10, 25, 50, 100)
  union all
  select s.winner_id, 'first_claim', min(s.created_at), null::uuid
  from public.bounty_settlements s where s.quotas_count > 0 and public._module_on('hall_of_fame') group by s.winner_id;

create view public.hof_records_v as
  with wins as (select winner_id as p, count(*) as n from public.hof_matches_v group by winner_id),
       evs as (select ep.user_id as p, count(*) as n from public.event_participants ep where public._module_on('hall_of_fame') group by ep.user_id),
       pm as (select player_a as p, match_id, verified_at, (winner_id = player_a) as won from public.hof_matches_v
              union all select player_b, match_id, verified_at, (winner_id = player_b) from public.hof_matches_v),
       g as (select p, won,
                    row_number() over (partition by p order by verified_at, match_id)
                  - row_number() over (partition by p, won order by verified_at, match_id) as grp from pm),
       streak as (select p, max(n) as n from (select p, count(*) as n from g where won group by p, grp) x group by p),
       big as (select winner_id as p, payout as n, match_id from public.hof_claims_v)
  select 'most_wins'::text as record_key, p as holder_id, n::integer as value, null::uuid as ref_id from (select p, n, rank() over (order by n desc) r from wins) x where r = 1 and n > 0
  union all
  select 'most_events', p, n::integer, null::uuid from (select p, n, rank() over (order by n desc) r from evs) x where r = 1 and n > 0
  union all
  select 'longest_win_streak', p, n::integer, null::uuid from (select p, n, rank() over (order by n desc) r from streak) x where r = 1 and n > 0
  union all
  select 'biggest_claim', p, n, match_id from (select p, n, match_id, rank() over (order by n desc) r from big) x where r = 1 and n > 0;

-- =====================================================================
-- FACTION WARS — il punteggio NON è memorizzato: si calcola dai match verificati (una sola fonte),
-- quindi un match non può essere contato due volte e nessuna modifica successiva crea incoerenze.
-- Regola: una vittoria verificata vale faction_points_per_win punti alla fazione del vincitore
-- (in quel momento), purché lo sconfitto non fosse della stessa fazione. I punti non sono BC.
-- =====================================================================
create view public.faction_scored_matches_v as
  select m.id as match_id, m.verified_at, e.event_date, m.winner_id, fw.faction_id,
         (select se.id from public.seasons se where e.event_date between se.starts_on and se.ends_on) as season_id,
         coalesce(public._setting('faction_points_per_win'), 0) as points
  from public.matches m
  join public.events e on e.id = m.event_id
  join public.faction_members fw on fw.user_id = m.winner_id and m.verified_at >= fw.joined_at and (fw.left_at is null or m.verified_at < fw.left_at)
  where m.status = 'verified' and public._module_on('faction_wars')
    and not exists (select 1 from public.faction_match_exclusions x where x.match_id = m.id)
    and not exists (select 1 from public.faction_members fl
                    where fl.user_id = case when m.winner_id = m.player_a then m.player_b else m.player_a end
                      and fl.faction_id = fw.faction_id
                      and m.verified_at >= fl.joined_at and (fl.left_at is null or m.verified_at < fl.left_at));

create view public.faction_standings_v as
  with base as (
    select s.id as season_id, f.id as faction_id from public.seasons s cross join public.factions f
    union all select null::uuid, f.id from public.factions f),
  agg as (
    select b.season_id, b.faction_id,
           coalesce(sum(sm.points), 0)::integer as points, count(sm.match_id)::integer as wins
    from base b left join public.faction_scored_matches_v sm
      on sm.faction_id = b.faction_id and (b.season_id is null or sm.season_id = b.season_id)
    group by b.season_id, b.faction_id)
  select a.season_id, a.faction_id, f.name, f.symbol, f.status, a.points, a.wins,
         (select count(*) from public.faction_members fm where fm.faction_id = f.id and fm.left_at is null)::integer as members,
         rank() over (partition by a.season_id order by a.points desc)::integer as rank
  from agg a join public.factions f on f.id = a.faction_id
  where public._module_on('faction_wars') and (f.status = 'active' or a.points > 0);

create view public.faction_members_v as
  select fm.faction_id, fm.user_id, p.nickname, p.avatar, fm.role, fm.joined_at,
         (select count(*) from public.faction_scored_matches_v sm where sm.winner_id = fm.user_id and sm.faction_id = fm.faction_id)::integer as wins_for_faction
  from public.faction_members fm join public.profiles p on p.id = fm.user_id
  where fm.left_at is null and public._module_on('faction_wars');

-- Funzioni dei giocatori
create function public.create_faction(p_name text, p_description text default null, p_symbol text default null) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid; v_id uuid := gen_random_uuid(); n text := btrim(p_name);
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  if n is null or char_length(n) not between 3 and 30 then raise exception 'Il nome deve avere da 3 a 30 caratteri'; end if;
  if exists (select 1 from public.faction_members where user_id = v and left_at is null) then raise exception 'Fai già parte di una fazione'; end if;
  if exists (select 1 from public.faction_members where user_id = v and left_at > clock_timestamp() - make_interval(days => coalesce(public._setting('faction_cooldown_days'), 0)))
    then raise exception 'Hai lasciato una fazione da poco: attendi la fine del periodo di attesa'; end if;
  begin
    insert into public.factions (id, name, description, symbol, founder_id) values (v_id, n, nullif(btrim(p_description), ''), nullif(btrim(p_symbol), ''), v);
    insert into public.faction_members (faction_id, user_id, role) values (v_id, v, 'leader');
  exception when unique_violation then raise exception 'Esiste già una fazione con questo nome, oppure fai già parte di una fazione';
            when check_violation then raise exception 'Dati della fazione non validi';
  end;
  perform public._audit(v, 'create_faction', 'faction', v_id::text, null, jsonb_build_object('name', n), null);
  return v_id;
end $$;

create function public.join_faction(p_faction uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; f public.factions%rowtype;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into f from public.factions where id = p_faction for update;
  if not found or f.status <> 'active' then raise exception 'Fazione non disponibile'; end if;
  if exists (select 1 from public.faction_members where user_id = v and left_at is null) then raise exception 'Fai già parte di una fazione'; end if;
  if exists (select 1 from public.faction_members where user_id = v and left_at > clock_timestamp() - make_interval(days => coalesce(public._setting('faction_cooldown_days'), 0)))
    then raise exception 'Hai lasciato una fazione da poco: attendi la fine del periodo di attesa'; end if;
  if (select count(*) from public.faction_members where faction_id = p_faction and left_at is null) >= coalesce(public._setting('faction_max_members'), 20)
    then raise exception 'La fazione è al completo'; end if;
  begin
    insert into public.faction_members (faction_id, user_id, role) values (p_faction, v, 'member');
  exception when unique_violation then raise exception 'Fai già parte di una fazione'; end;
  perform public._audit(v, 'join_faction', 'faction', p_faction::text, null, null, null);
end $$;

create function public.leave_faction() returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.faction_members%rowtype; n integer;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into m from public.faction_members where user_id = v and left_at is null for update;
  if not found then raise exception 'Non fai parte di alcuna fazione'; end if;
  select count(*) into n from public.faction_members where faction_id = m.faction_id and left_at is null and user_id <> v;
  if m.role = 'leader' and n > 0 then raise exception 'Il capo deve prima cedere la guida a un altro membro'; end if;
  update public.faction_members set left_at = clock_timestamp() where id = m.id;
  if m.role = 'leader' then update public.factions set status = 'disbanded', disbanded_at = clock_timestamp() where id = m.faction_id; end if;
  perform public._audit(v, 'leave_faction', 'faction', m.faction_id::text, null, jsonb_build_object('disbanded', m.role = 'leader'), null);
end $$;

create function public.transfer_faction_leadership(p_user uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.faction_members%rowtype;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into m from public.faction_members where user_id = v and left_at is null and role = 'leader' for update;
  if not found then raise exception 'Solo il capo può cedere la guida'; end if;
  if not exists (select 1 from public.faction_members where faction_id = m.faction_id and user_id = p_user and left_at is null and user_id <> v) then raise exception 'Il nuovo capo deve essere un membro della fazione'; end if;
  update public.faction_members set role = 'member' where id = m.id;
  update public.faction_members set role = 'leader' where faction_id = m.faction_id and user_id = p_user and left_at is null;
  perform public._audit(v, 'transfer_leadership', 'faction', m.faction_id::text, jsonb_build_object('leader', v), jsonb_build_object('leader', p_user), null);
end $$;

create function public.kick_faction_member(p_user uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.faction_members%rowtype;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into m from public.faction_members where user_id = v and left_at is null and role = 'leader' for update;
  if not found then raise exception 'Solo il capo può rimuovere un membro'; end if;
  if p_user = v then raise exception 'Per uscire usa "Lascia la fazione"'; end if;
  update public.faction_members set left_at = clock_timestamp() where faction_id = m.faction_id and user_id = p_user and left_at is null;
  if not found then raise exception 'Il giocatore non è membro della tua fazione'; end if;
  perform public._audit(v, 'kick_member', 'faction', m.faction_id::text, null, jsonb_build_object('user', p_user), null);
end $$;

create function public.update_faction(p_description text, p_symbol text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.faction_members%rowtype;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into m from public.faction_members where user_id = v and left_at is null and role = 'leader';
  if not found then raise exception 'Solo il capo può modificare la fazione'; end if;
  begin
    update public.factions set description = nullif(btrim(p_description), ''), symbol = nullif(btrim(p_symbol), '') where id = m.faction_id;
  exception when check_violation then raise exception 'Dati della fazione non validi'; end;
  perform public._audit(v, 'update_faction', 'faction', m.faction_id::text, null, jsonb_build_object('symbol', p_symbol), null);
end $$;

-- Funzioni amministrative
create function public.admin_faction_disband(p_faction uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; f public.factions%rowtype;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into f from public.factions where id = p_faction for update;
  if not found or f.status <> 'active' then raise exception 'Fazione non attiva'; end if;
  update public.faction_members set left_at = clock_timestamp() where faction_id = p_faction and left_at is null;
  update public.factions set status = 'disbanded', disbanded_at = clock_timestamp() where id = p_faction;
  perform public._audit(v, 'disband_faction', 'faction', p_faction::text, to_jsonb(f), null, p_reason);
end $$;

create function public.admin_faction_rename(p_faction uuid, p_name text, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; o text;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select name into o from public.factions where id = p_faction for update;
  if not found then raise exception 'Fazione inesistente'; end if;
  begin
    update public.factions set name = btrim(p_name) where id = p_faction;
  exception when unique_violation then raise exception 'Esiste già una fazione con questo nome';
            when check_violation then raise exception 'Il nome deve avere da 3 a 30 caratteri'; end;
  perform public._audit(v, 'rename_faction', 'faction', p_faction::text, jsonb_build_object('name', o), jsonb_build_object('name', btrim(p_name)), p_reason);
end $$;

create function public.admin_faction_move_member(p_user uuid, p_faction uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.faction_members%rowtype; n integer;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into m from public.faction_members where user_id = p_user and left_at is null for update;
  if found then
    select count(*) into n from public.faction_members where faction_id = m.faction_id and left_at is null and user_id <> p_user;
    if m.role = 'leader' and n > 0 then raise exception 'Cedi prima la guida della fazione di origine'; end if;
    update public.faction_members set left_at = clock_timestamp() where id = m.id;
    if m.role = 'leader' then update public.factions set status = 'disbanded', disbanded_at = clock_timestamp() where id = m.faction_id; end if;
  end if;
  if p_faction is not null then
    perform 1 from public.factions where id = p_faction and status = 'active' for update;
    if not found then raise exception 'Fazione non disponibile'; end if;
    if (select count(*) from public.faction_members where faction_id = p_faction and left_at is null) >= coalesce(public._setting('faction_max_members'), 20) then raise exception 'La fazione è al completo'; end if;
    insert into public.faction_members (faction_id, user_id, role) values (p_faction, p_user, 'member');
  end if;
  perform public._audit(v, 'move_faction_member', 'profile', p_user::text, jsonb_build_object('faction', m.faction_id), jsonb_build_object('faction', p_faction), p_reason);
end $$;

create function public.admin_faction_exclude_match(p_match uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  if not exists (select 1 from public.matches where id = p_match and status = 'verified') then raise exception 'Match inesistente o non verificato'; end if;
  insert into public.faction_match_exclusions (match_id, reason, excluded_by) values (p_match, btrim(p_reason), v) on conflict do nothing;
  perform public._audit(v, 'exclude_match_from_factions', 'match', p_match::text, null, null, p_reason);
end $$;

create function public.admin_faction_include_match(p_match uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  perform public._require_module('faction_wars');
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  delete from public.faction_match_exclusions where match_id = p_match;
  perform public._audit(v, 'include_match_in_factions', 'match', p_match::text, null, null, p_reason);
end $$;

-- =====================================================================
-- UNDERGROUND CHALLENGES — una sfida NON è un match ufficiale: queste funzioni non scrivono mai su
-- matches, wallets, ledger_entries, bounties o punteggi. Il risultato diventa ufficiale solo con verify_match (001).
-- =====================================================================
create view public.challenges_v as
  select c.id, c.challenger_id, c.opponent_id, c.status, c.message, c.created_at, c.expires_at, c.responded_at, c.match_id,
         c.linked_at, c.completed_at, c.cancel_reason,
         m.status as match_status, m.winner_id as match_winner_id          -- letti dal match ufficiale, mai copiati
  from public.challenges c left join public.matches m on m.id = c.match_id
  where public._module_on('underground') or public.is_admin();

create function public.expire_challenges() returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  perform public._require_module('underground');
  perform public._need_role(array['user','organizer','admin']::public.app_role[]);
  update public.challenges set status = 'expired' where status = 'pending' and expires_at <= clock_timestamp();
  get diagnostics n = row_count;
  if n > 0 then perform public._audit(null, 'expire_challenges', 'challenge', null, null, jsonb_build_object('count', n), 'scadenza automatica'); end if;
  return n;
end $$;

create function public.create_challenge(p_opponent uuid, p_message text, p_request_id text) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid; v_id uuid := gen_random_uuid(); ex uuid;
begin
  perform public._require_module('underground');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  if p_request_id is null or char_length(p_request_id) < 8 then raise exception 'Richiesta non valida'; end if;
  select id into ex from public.challenges where challenger_id = v and client_request_id = p_request_id;
  if found then return ex; end if;                                               -- richiesta ripetuta: nessuna doppia sfida
  if p_opponent is null or p_opponent = v then raise exception 'Scegli un altro duellante'; end if;
  if not exists (select 1 from public.profiles where id = p_opponent and not suspended) then raise exception 'Duellante non disponibile'; end if;
  perform 1 from public.profiles where id = v for update;                        -- serializza le sfide dello stesso utente
  if (select count(*) from public.challenges where challenger_id = v and status in ('pending','accepted','in_progress')) >= coalesce(public._setting('challenge_max_open'), 5)
    then raise exception 'Hai troppe sfide aperte'; end if;
  begin
    insert into public.challenges (id, challenger_id, opponent_id, message, client_request_id, expires_at)
    values (v_id, v, p_opponent, nullif(btrim(p_message), ''), p_request_id, clock_timestamp() + make_interval(days => coalesce(public._setting('challenge_expiry_days'), 7)));
  exception when unique_violation then raise exception 'Esiste già una sfida aperta con questo duellante';
            when check_violation then raise exception 'Dati della sfida non validi'; end;
  perform public._audit(v, 'create_challenge', 'challenge', v_id::text, null, jsonb_build_object('opponent', p_opponent), null);
  return v_id;
end $$;

create function public.respond_challenge(p_id uuid, p_accept boolean) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; c public.challenges%rowtype;
begin
  perform public._require_module('underground');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into c from public.challenges where id = p_id for update;
  if not found or c.opponent_id <> v then raise exception 'Sfida non trovata'; end if;
  if c.status <> 'pending' then raise exception 'La sfida non è più in attesa'; end if;
  if c.expires_at <= clock_timestamp() then raise exception 'Sfida scaduta'; end if;
  update public.challenges set status = case when p_accept then 'accepted' else 'declined' end, responded_at = clock_timestamp() where id = p_id;
  perform public._audit(v, case when p_accept then 'accept_challenge' else 'decline_challenge' end, 'challenge', p_id::text, null, null, null);
end $$;

create function public.cancel_challenge(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; c public.challenges%rowtype;
begin
  perform public._require_module('underground');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  select * into c from public.challenges where id = p_id for update;
  if not found or v not in (c.challenger_id, c.opponent_id) then raise exception 'Sfida non trovata'; end if;
  if c.status = 'pending' and v <> c.challenger_id then raise exception 'Solo chi ha lanciato la sfida può annullarla prima della risposta'; end if;
  if c.status not in ('pending','accepted') then raise exception 'La sfida non può più essere annullata'; end if;
  update public.challenges set status = 'cancelled', cancelled_by = v where id = p_id;
  perform public._audit(v, 'cancel_challenge', 'challenge', p_id::text, null, null, null);
end $$;

create function public.link_challenge_match(p_id uuid, p_match uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; c public.challenges%rowtype; m public.matches%rowtype;
begin
  perform public._require_module('underground');
  v := public._need_role(array['organizer','admin']::public.app_role[]);
  select * into c from public.challenges where id = p_id for update;
  if not found then raise exception 'Sfida non trovata'; end if;
  if c.status <> 'accepted' then raise exception 'La sfida deve essere accettata'; end if;
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'Match inesistente'; end if;
  if not public._can_manage_event(m.event_id, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  if not (m.player_a in (c.challenger_id, c.opponent_id) and m.player_b in (c.challenger_id, c.opponent_id)) then raise exception 'Il match deve essere tra i due sfidanti'; end if;
  if m.created_at < c.responded_at then raise exception 'Il match deve essere registrato dopo l''accettazione della sfida'; end if;
  begin
    update public.challenges set status = 'in_progress', match_id = p_match, linked_at = clock_timestamp() where id = p_id;
  exception when unique_violation then raise exception 'Questo match è già collegato a un''altra sfida'; end;
  perform public._audit(v, 'link_challenge_match', 'challenge', p_id::text, null, jsonb_build_object('match', p_match), null);
end $$;

create function public.complete_challenge(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; c public.challenges%rowtype; m public.matches%rowtype;
begin
  perform public._require_module('underground');
  v := public._need_role(array['organizer','admin']::public.app_role[]);
  select * into c from public.challenges where id = p_id for update;
  if not found then raise exception 'Sfida non trovata'; end if;
  if c.status <> 'in_progress' then raise exception 'La sfida non è in corso'; end if;
  select * into m from public.matches where id = c.match_id;
  if not public._can_manage_event(m.event_id, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  if m.status <> 'verified' then raise exception 'Il match deve essere prima verificato'; end if;
  update public.challenges set status = 'completed', completed_at = clock_timestamp(), completed_by = v where id = p_id;
  perform public._audit(v, 'complete_challenge', 'challenge', p_id::text, null, jsonb_build_object('match', c.match_id), null);
end $$;

create function public.admin_cancel_challenge(p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; c public.challenges%rowtype;
begin
  perform public._require_module('underground');
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into c from public.challenges where id = p_id for update;
  if not found then raise exception 'Sfida non trovata'; end if;
  if c.status in ('completed','cancelled','declined','expired') then raise exception 'La sfida è già chiusa'; end if;
  update public.challenges set status = 'cancelled', cancelled_by = v, cancel_reason = btrim(p_reason) where id = p_id;
  perform public._audit(v, 'admin_cancel_challenge', 'challenge', p_id::text, to_jsonb(c), null, p_reason);
end $$;

-- ---------- Row Level Security ----------
alter table public.seasons enable row level security;
alter table public.factions enable row level security;
alter table public.faction_members enable row level security;
alter table public.faction_match_exclusions enable row level security;
alter table public.challenges enable row level security;

create policy seasons_read on public.seasons for select to authenticated
  using (public._module_on('hall_of_fame') or public._module_on('faction_wars') or public.is_admin());
create policy factions_read on public.factions for select to authenticated
  using (public._module_on('faction_wars') or public.is_admin());
create policy faction_members_read on public.faction_members for select to authenticated
  using (public._module_on('faction_wars') or public.is_admin());
create policy faction_exclusions_read on public.faction_match_exclusions for select to authenticated using (public.is_admin());
create policy challenges_read on public.challenges for select to authenticated
  using (public._module_on('underground') or public.is_admin());

-- ---------- Permessi: nessuna scrittura diretta, solo le funzioni ----------
-- (Supabase concede di default privilegi sulle nuove tabelle e funzioni: li togliamo esplicitamente.)
revoke all on public.seasons, public.factions, public.faction_members, public.faction_match_exclusions, public.challenges,
  public.hof_matches_v, public.hof_player_stats_v, public.hof_season_stats_v, public.hof_claims_v, public.hof_rivalries_v,
  public.hof_events_v, public.hof_milestones_v, public.hof_records_v,
  public.faction_scored_matches_v, public.faction_standings_v, public.faction_members_v, public.challenges_v
  from public, anon, authenticated;
grant select on public.seasons, public.factions, public.faction_members, public.faction_match_exclusions, public.challenges,
  public.hof_matches_v, public.hof_player_stats_v, public.hof_season_stats_v, public.hof_claims_v, public.hof_rivalries_v,
  public.hof_events_v, public.hof_milestones_v, public.hof_records_v,
  public.faction_scored_matches_v, public.faction_standings_v, public.faction_members_v, public.challenges_v to authenticated;

revoke all on function public._module_on(text), public._require_module(text), public._no_delete(),
  public.admin_set_module(text, boolean, text), public.admin_create_season(text, date, date, text),
  public.create_faction(text, text, text), public.join_faction(uuid), public.leave_faction(), public.transfer_faction_leadership(uuid),
  public.kick_faction_member(uuid), public.update_faction(text, text),
  public.admin_faction_disband(uuid, text), public.admin_faction_rename(uuid, text, text), public.admin_faction_move_member(uuid, uuid, text),
  public.admin_faction_exclude_match(uuid, text), public.admin_faction_include_match(uuid, text),
  public.expire_challenges(), public.create_challenge(uuid, text, text), public.respond_challenge(uuid, boolean), public.cancel_challenge(uuid),
  public.link_challenge_match(uuid, uuid), public.complete_challenge(uuid), public.admin_cancel_challenge(uuid, text)
  from public, anon, authenticated;
grant execute on function public._module_on(text) to authenticated;          -- servono alle policy RLS e alle viste
grant execute on function
  public.admin_set_module(text, boolean, text), public.admin_create_season(text, date, date, text),
  public.create_faction(text, text, text), public.join_faction(uuid), public.leave_faction(), public.transfer_faction_leadership(uuid),
  public.kick_faction_member(uuid), public.update_faction(text, text),
  public.admin_faction_disband(uuid, text), public.admin_faction_rename(uuid, text, text), public.admin_faction_move_member(uuid, uuid, text),
  public.admin_faction_exclude_match(uuid, text), public.admin_faction_include_match(uuid, text),
  public.expire_challenges(), public.create_challenge(uuid, text, text), public.respond_challenge(uuid, boolean), public.cancel_challenge(uuid),
  public.link_challenge_match(uuid, uuid), public.complete_challenge(uuid), public.admin_cancel_challenge(uuid, text)
  to authenticated;

commit;
