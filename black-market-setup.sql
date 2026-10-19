-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET SPECIAL EDITION
-- Migrazione 001: schema, sicurezza (RLS), registro contabile, operazioni economiche.
-- Da eseguire UNA volta nel SQL Editor di Supabase.
-- Tutta la logica economica sta qui: il browser non può toccare saldi, match o riscossioni.
-- =====================================================================

create type public.app_role as enum ('user','organizer','admin');
create type public.bounty_status as enum ('active','under_review','settled','cancelled');
create type public.verification_status as enum ('pending','verified');

-- ---------- Tabelle ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  nickname text not null check (char_length(nickname) between 3 and 24),
  avatar text check (avatar is null or char_length(avatar) <= 8),
  role public.app_role not null default 'user',
  wanted_enabled boolean not null default false,   -- consenso a ricevere taglie (Most Wanted)
  suspended boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index profiles_nickname_lower on public.profiles (lower(nickname));

create table public.wallets (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  balance integer not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table public.system_settings (
  key text primary key,
  value_int integer not null,
  description text,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

create table public.ledger_entries (            -- registro contabile: SOLO inserimenti
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  amount integer not null check (amount <> 0),   -- positivo = accredito, negativo = addebito
  kind text not null check (kind in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment')),
  ref_type text,
  ref_id uuid,
  idempotency_key text not null unique,          -- impedisce movimenti duplicati
  balance_after integer not null check (balance_after >= 0),
  memo text,
  created_at timestamptz not null default clock_timestamp()
);
create index ledger_user_idx on public.ledger_entries (user_id, created_at desc);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 80),
  event_date date not null default current_date,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create table public.event_participants (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  rewarded boolean not null default false,
  primary key (event_id, user_id)
);
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  round integer not null default 1 check (round > 0),
  player_a uuid not null references public.profiles(id),
  player_b uuid not null references public.profiles(id),
  winner_id uuid references public.profiles(id),
  status public.verification_status not null default 'pending',
  verified_by uuid references public.profiles(id),
  verified_at timestamptz,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (player_a <> player_b),
  check (winner_id is null or winner_id in (player_a, player_b)),
  check ((status = 'verified') = (winner_id is not null and verified_by is not null and verified_at is not null)),
  unique (event_id, round, player_a, player_b)
);

create table public.bounty_settlements (        -- una sola liquidazione per match (vincolo anti doppia riscossione)
  id uuid primary key,
  match_id uuid not null unique references public.matches(id),
  target_id uuid not null references public.profiles(id),
  winner_id uuid not null references public.profiles(id),
  payout integer not null check (payout >= 0),   -- quote di ALTRI utenti incassate dal vincitore
  refunded integer not null check (refunded >= 0), -- quote proprie del vincitore, restituite
  quotas_count integer not null check (quotas_count >= 0),
  created_at timestamptz not null default clock_timestamp()
);

create table public.bounties (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id) on delete restrict,
  target_id uuid not null references public.profiles(id) on delete restrict,
  amount integer not null check (amount > 0),
  message text check (message is null or char_length(message) <= 140),
  status public.bounty_status not null default 'active',
  client_request_id text not null,
  settlement_id uuid references public.bounty_settlements(id) deferrable initially deferred,
  created_at timestamptz not null default clock_timestamp(),
  settled_at timestamptz,
  check (creator_id <> target_id),
  unique (creator_id, client_request_id)
);
create index bounties_target_idx on public.bounties (target_id, status);
create index bounties_creator_idx on public.bounties (creator_id, status);

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  opened_by uuid not null references public.profiles(id),
  match_id uuid references public.matches(id),
  bounty_id uuid references public.bounties(id),
  reason text not null check (char_length(reason) between 5 and 500),
  status text not null default 'open' check (status in ('open','resolved')),
  resolution text,
  resolved_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table public.audit_logs (                 -- registro di audit: SOLO inserimenti
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  entity text not null,
  entity_id text,
  old_value jsonb,
  new_value jsonb,
  reason text,
  created_at timestamptz not null default clock_timestamp()
);

-- ---------- Registri immutabili ----------
create function public._immutable() returns trigger language plpgsql as $$
begin raise exception 'Registro immutabile: % non consentito su %', tg_op, tg_table_name; end $$;
create trigger ledger_immutable before update or delete on public.ledger_entries for each row execute function public._immutable();
create trigger ledger_no_truncate before truncate on public.ledger_entries for each statement execute function public._immutable();
create trigger audit_immutable before update or delete on public.audit_logs for each row execute function public._immutable();
create trigger audit_no_truncate before truncate on public.audit_logs for each statement execute function public._immutable();
create trigger settle_immutable before update or delete on public.bounty_settlements for each row execute function public._immutable();

-- ---------- Impostazioni iniziali (modificabili dall'admin) ----------
insert into public.system_settings (key, value_int, description) values
 ('initial_bonus',        300, 'Bonus iniziale in BC (una sola volta per utente)'),
 ('participation_reward',  30, 'BC per partecipazione verificata a un evento'),
 ('min_bounty',            50, 'Taglia minima in BC'),
 ('max_bounty',           500, 'Importo massimo per singola taglia in BC'),
 ('max_active_bounties',    5, 'Massimo di taglie attive create da ciascun utente'),
 ('show_bounty_authors',    1, '1 = gli autori delle taglie sono visibili, 0 = anonimi');

-- ---------- Funzioni di supporto (non esposte al client) ----------
create function public._setting(p_key text) returns integer language sql stable security definer set search_path = public as $$
  select value_int from public.system_settings where key = p_key $$;

create function public._audit(p_actor uuid, p_action text, p_entity text, p_entity_id text, p_old jsonb, p_new jsonb, p_reason text)
returns void language sql security definer set search_path = public as $$
  insert into public.audit_logs (actor_id, action, entity, entity_id, old_value, new_value, reason)
  values (p_actor, p_action, p_entity, p_entity_id, p_old, p_new, p_reason) $$;

create function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and not suspended) $$;

create function public._need_role(p_roles public.app_role[]) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid(); r public.app_role; s boolean;
begin
  if v is null then raise exception 'Accesso richiesto'; end if;
  select role, suspended into r, s from public.profiles where id = v;
  if not found then raise exception 'Profilo non registrato'; end if;
  if s then raise exception 'Account sospeso'; end if;
  if not (r = any (p_roles)) then raise exception 'Permessi insufficienti'; end if;
  return v;
end $$;

-- Unico punto in cui un saldo può cambiare. Blocca il wallet, controlla l'idempotenza, scrive il registro.
-- Ritorna il nuovo saldo, oppure -1 se la stessa operazione (idempotency_key) era già stata applicata.
create function public._ledger_move(p_user uuid, p_amount integer, p_kind text, p_ref_type text, p_ref uuid, p_key text, p_memo text)
returns integer language plpgsql security definer set search_path = public as $$
declare v_bal integer;
begin
  if p_amount = 0 then raise exception 'Importo nullo'; end if;
  select balance into v_bal from public.wallets where user_id = p_user for update;
  if not found then raise exception 'Wallet inesistente'; end if;
  if exists (select 1 from public.ledger_entries where idempotency_key = p_key) then return -1; end if;
  if v_bal + p_amount < 0 then raise exception 'Saldo insufficiente'; end if;
  v_bal := v_bal + p_amount;
  update public.wallets set balance = v_bal, updated_at = clock_timestamp() where user_id = p_user;
  insert into public.ledger_entries (user_id, amount, kind, ref_type, ref_id, idempotency_key, balance_after, memo)
  values (p_user, p_amount, p_kind, p_ref_type, p_ref, p_key, v_bal, p_memo);
  return v_bal;
end $$;

create function public._can_manage_event(p_event uuid, p_user uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.events e join public.profiles p on p.id = p_user
                 where e.id = p_event and not p.suspended and (e.created_by = p_user or p.role = 'admin')) $$;

-- ---------- Profilo ----------
create function public.register_profile(p_nickname text) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid(); n text := btrim(p_nickname); v_first boolean; v_bonus integer;
begin
  if v is null then raise exception 'Accesso richiesto'; end if;
  if exists (select 1 from public.profiles where id = v) then return v; end if;
  if n is null or n !~ '^[A-Za-z0-9_ .-]{3,24}$' then
    raise exception 'Nickname non valido (3-24 caratteri: lettere, numeri, spazio, punto, trattino)'; end if;
  if exists (select 1 from public.profiles where lower(nickname) = lower(n)) then raise exception 'Nickname già in uso'; end if;
  v_first := not exists (select 1 from public.profiles);           -- il primo account diventa amministratore
  insert into public.profiles (id, nickname, role) values (v, n, case when v_first then 'admin'::public.app_role else 'user'::public.app_role end);
  insert into public.wallets (user_id, balance) values (v, 0);
  v_bonus := public._setting('initial_bonus');
  if v_bonus > 0 then perform public._ledger_move(v, v_bonus, 'initial_bonus', 'profile', v, 'bonus:' || v, 'Bonus iniziale'); end if;
  perform public._audit(v, 'register_profile', 'profile', v::text, null, jsonb_build_object('nickname', n, 'admin', v_first), null);
  return v;
end $$;

create function public.update_my_profile(p_avatar text, p_wanted boolean) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
begin
  if p_avatar is not null and char_length(p_avatar) > 8 then raise exception 'Avatar troppo lungo'; end if;
  update public.profiles set avatar = p_avatar, wanted_enabled = coalesce(p_wanted, wanted_enabled) where id = v;
end $$;

-- ---------- Taglie ----------
create function public.create_bounty(p_target uuid, p_amount integer, p_message text default null, p_request_id text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
        v_id uuid; v_existing uuid; v_active integer; v_msg text := nullif(btrim(p_message), '');
begin
  perform 1 from public.wallets where user_id = v_me for update;          -- serializza le richieste dello stesso utente
  if p_request_id is null or char_length(p_request_id) < 8 then raise exception 'Richiesta non valida'; end if;
  select id into v_existing from public.bounties where creator_id = v_me and client_request_id = p_request_id;
  if found then return v_existing; end if;                                  -- richiesta duplicata: nessun nuovo addebito
  if p_target = v_me then raise exception 'Non puoi mettere una taglia su te stesso'; end if;
  if p_amount is null or p_amount < public._setting('min_bounty') then raise exception 'Importo inferiore alla taglia minima (% BC)', public._setting('min_bounty'); end if;
  if p_amount > public._setting('max_bounty') then raise exception 'Importo superiore al massimo consentito (% BC)', public._setting('max_bounty'); end if;
  if v_msg is not null and char_length(v_msg) > 140 then raise exception 'Messaggio troppo lungo (max 140 caratteri)'; end if;
  perform 1 from public.profiles where id = p_target and wanted_enabled and not suspended;
  if not found then raise exception 'Questo duellante non accetta taglie'; end if;
  select count(*) into v_active from public.bounties where creator_id = v_me and status in ('active','under_review');
  if v_active >= public._setting('max_active_bounties') then raise exception 'Hai raggiunto il massimo di taglie attive (%)', public._setting('max_active_bounties'); end if;
  v_id := gen_random_uuid();
  insert into public.bounties (id, creator_id, target_id, amount, message, client_request_id) values (v_id, v_me, p_target, p_amount, v_msg, p_request_id);
  perform public._ledger_move(v_me, -p_amount, 'bounty_stake', 'bounty', v_id, 'stake:' || v_id, 'Taglia pubblicata');
  perform public._audit(v_me, 'create_bounty', 'bounty', v_id::text, null, jsonb_build_object('target', p_target, 'amount', p_amount), null);
  return v_id;
end $$;

-- ---------- Eventi e match ----------
create function public.create_event(p_name text, p_date date default current_date) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); v_id uuid := gen_random_uuid();
begin
  insert into public.events (id, name, event_date, created_by) values (v_id, btrim(p_name), coalesce(p_date, current_date), v);
  perform public._audit(v, 'create_event', 'event', v_id::text, null, jsonb_build_object('name', p_name), null);
  return v_id;
end $$;

create function public.add_participant(p_event uuid, p_user uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]);
begin
  if not public._can_manage_event(p_event, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  insert into public.event_participants (event_id, user_id) values (p_event, p_user) on conflict do nothing;
end $$;

create function public.create_match(p_event uuid, p_round integer, p_a uuid, p_b uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); v_id uuid := gen_random_uuid();
begin
  if not public._can_manage_event(p_event, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  insert into public.event_participants (event_id, user_id) values (p_event, p_a), (p_event, p_b) on conflict do nothing;
  insert into public.matches (id, event_id, round, player_a, player_b, created_by) values (v_id, p_event, coalesce(p_round, 1), p_a, p_b, v);
  return v_id;
end $$;

create function public.verify_match(p_match uuid, p_winner uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); m public.matches%rowtype;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'Match inesistente'; end if;
  if not public._can_manage_event(m.event_id, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  if m.status = 'verified' then raise exception 'Match già verificato'; end if;
  if p_winner is null or p_winner not in (m.player_a, m.player_b) then raise exception 'Il vincitore deve essere uno dei due giocatori'; end if;
  update public.matches set winner_id = p_winner, status = 'verified', verified_by = v, verified_at = clock_timestamp() where id = p_match;
  perform public._audit(v, 'verify_match', 'match', p_match::text, to_jsonb(m), jsonb_build_object('winner', p_winner), null);
end $$;

create function public.award_participation(p_event uuid) returns integer language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['organizer','admin']::public.app_role[]); r record; v_n integer := 0; v_rew integer := public._setting('participation_reward');
begin
  if not public._can_manage_event(p_event, v) then raise exception 'Non sei l''organizzatore di questo evento'; end if;
  for r in select user_id from public.event_participants where event_id = p_event and not rewarded order by user_id for update loop
    if v_rew > 0 and public._ledger_move(r.user_id, v_rew, 'participation_reward', 'event', p_event, 'part:' || p_event || ':' || r.user_id, 'Partecipazione a evento') <> -1 then v_n := v_n + 1; end if;
    update public.event_participants set rewarded = true where event_id = p_event and user_id = r.user_id;
  end loop;
  perform public._audit(v, 'award_participation', 'event', p_event::text, null, jsonb_build_object('rewarded', v_n), null);
  return v_n;
end $$;

-- ---------- Riscossione ----------
-- Formula: sulle quote ATTIVE del bersaglio, create prima della verifica del match:
--   premio    = somma delle quote finanziate da ALTRI utenti
--   rimborso  = somma delle quote finanziate dal vincitore stesso (restituite, nessun guadagno)
--   il vincitore riceve premio + rimborso; tutte le quote coinvolte passano a 'settled'.
-- Esempio: Marco 200 + Andrea 300 su Luca; vince Marco -> premio 300, rimborso 200, totale +500.
create function public.claim_bounty(p_match uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
        m public.matches%rowtype; s public.bounty_settlements%rowtype; v_target uuid; v_sid uuid := gen_random_uuid();
        v_pay integer; v_ref integer; v_n integer; v_frozen integer;
begin
  select * into m from public.matches where id = p_match for update;           -- serializza le richieste sullo stesso match
  if not found then raise exception 'Match inesistente'; end if;
  if m.status <> 'verified' then raise exception 'Match non verificato: nessuna riscossione possibile'; end if;
  if m.winner_id is distinct from v_me then raise exception 'Solo il vincitore verificato può riscuotere'; end if;
  select * into s from public.bounty_settlements where match_id = p_match;
  if found then return jsonb_build_object('settlement_id', s.id, 'already', true, 'payout', s.payout, 'refunded', s.refunded); end if;
  v_target := case when m.player_a = v_me then m.player_b else m.player_a end;
  select count(*) into v_frozen from public.bounties where target_id = v_target and status = 'under_review' and created_at <= m.verified_at;
  if v_frozen > 0 then raise exception 'Una taglia sul bersaglio è in revisione: riscossione sospesa'; end if;
  with closed as (
    update public.bounties set status = 'settled', settled_at = clock_timestamp(), settlement_id = v_sid
    where target_id = v_target and status = 'active' and created_at <= m.verified_at
    returning creator_id, amount)
  select coalesce(sum(amount) filter (where creator_id <> v_me), 0)::integer,
         coalesce(sum(amount) filter (where creator_id = v_me), 0)::integer, count(*)::integer
    into v_pay, v_ref, v_n from closed;
  insert into public.bounty_settlements (id, match_id, target_id, winner_id, payout, refunded, quotas_count) values (v_sid, p_match, v_target, v_me, v_pay, v_ref, v_n);
  if v_pay > 0 then perform public._ledger_move(v_me, v_pay, 'bounty_payout', 'settlement', v_sid, 'payout:' || v_sid, 'Ricompensa riscossa'); end if;
  if v_ref > 0 then perform public._ledger_move(v_me, v_ref, 'bounty_refund', 'settlement', v_sid, 'refund:' || v_sid, 'Quota propria restituita'); end if;
  perform public._audit(v_me, 'claim_bounty', 'settlement', v_sid::text, null, jsonb_build_object('match', p_match, 'target', v_target, 'payout', v_pay, 'refunded', v_ref, 'quotas', v_n), null);
  return jsonb_build_object('settlement_id', v_sid, 'already', false, 'payout', v_pay, 'refunded', v_ref, 'quotas', v_n);
end $$;

-- ---------- Contestazioni e amministrazione ----------
create function public.open_dispute(p_match uuid, p_bounty uuid, p_reason text) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]); v_id uuid := gen_random_uuid();
begin
  if p_match is null and p_bounty is null then raise exception 'Indica un match o una taglia'; end if;
  insert into public.disputes (id, opened_by, match_id, bounty_id, reason) values (v_id, v, p_match, p_bounty, btrim(p_reason));
  perform public._audit(v, 'open_dispute', 'dispute', v_id::text, null, jsonb_build_object('match', p_match, 'bounty', p_bounty), p_reason);
  return v_id;
end $$;

create function public.resolve_dispute(p_id uuid, p_resolution text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]);
begin
  if p_resolution is null or char_length(btrim(p_resolution)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  update public.disputes set status = 'resolved', resolution = btrim(p_resolution), resolved_by = v, resolved_at = now() where id = p_id and status = 'open';
  if not found then raise exception 'Contestazione inesistente o già chiusa'; end if;
  perform public._audit(v, 'resolve_dispute', 'dispute', p_id::text, null, jsonb_build_object('resolution', p_resolution), p_resolution);
end $$;

create function public.admin_set_bounty_review(p_bounty uuid, p_on boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); b public.bounties%rowtype;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into b from public.bounties where id = p_bounty for update;
  if not found then raise exception 'Taglia inesistente'; end if;
  if b.status not in ('active','under_review') then raise exception 'La taglia è già chiusa'; end if;
  update public.bounties set status = case when p_on then 'under_review'::public.bounty_status else 'active'::public.bounty_status end where id = p_bounty;
  perform public._audit(v, 'bounty_review', 'bounty', p_bounty::text, jsonb_build_object('status', b.status), jsonb_build_object('under_review', p_on), p_reason);
end $$;

create function public.admin_cancel_bounty(p_bounty uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); b public.bounties%rowtype;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into b from public.bounties where id = p_bounty for update;
  if not found then raise exception 'Taglia inesistente'; end if;
  if b.status not in ('active','under_review') then raise exception 'La taglia è già chiusa'; end if;
  update public.bounties set status = 'cancelled', settled_at = clock_timestamp() where id = p_bounty;
  perform public._ledger_move(b.creator_id, b.amount, 'bounty_refund', 'bounty', p_bounty, 'cancel:' || p_bounty, 'Taglia annullata dall''amministrazione');
  perform public._audit(v, 'cancel_bounty', 'bounty', p_bounty::text, to_jsonb(b), jsonb_build_object('status', 'cancelled'), p_reason);
end $$;

create function public.admin_set_role(p_user uuid, p_role public.app_role, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o public.app_role;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select role into o from public.profiles where id = p_user for update;
  if not found then raise exception 'Utente inesistente'; end if;
  if p_user = v and p_role <> 'admin' then raise exception 'Non puoi togliere a te stesso il ruolo di amministratore'; end if;
  update public.profiles set role = p_role where id = p_user;
  perform public._audit(v, 'set_role', 'profile', p_user::text, jsonb_build_object('role', o), jsonb_build_object('role', p_role), p_reason);
end $$;

create function public.admin_set_suspended(p_user uuid, p_on boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]);
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  if p_user = v then raise exception 'Non puoi sospendere te stesso'; end if;
  update public.profiles set suspended = p_on where id = p_user;
  if not found then raise exception 'Utente inesistente'; end if;
  perform public._audit(v, 'set_suspended', 'profile', p_user::text, null, jsonb_build_object('suspended', p_on), p_reason);
end $$;

create function public.admin_set_setting(p_key text, p_value integer, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o integer;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  if p_value is null or p_value < 0 then raise exception 'Valore non valido'; end if;
  select value_int into o from public.system_settings where key = p_key for update;
  if not found then raise exception 'Impostazione inesistente'; end if;
  update public.system_settings set value_int = p_value, updated_at = now(), updated_by = v where key = p_key;
  perform public._audit(v, 'set_setting', 'setting', p_key, jsonb_build_object('value', o), jsonb_build_object('value', p_value), p_reason);
end $$;

-- Rettifica di saldo: non è mai silenziosa, scrive una riga di registro e una di audit con motivazione.
create function public.admin_adjust_balance(p_user uuid, p_amount integer, p_reason text) returns integer language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); v_id uuid := gen_random_uuid(); v_bal integer;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  v_bal := public._ledger_move(p_user, p_amount, 'admin_adjustment', 'admin', v_id, 'adj:' || v_id, btrim(p_reason));
  perform public._audit(v, 'adjust_balance', 'wallet', p_user::text, null, jsonb_build_object('amount', p_amount, 'balance_after', v_bal), p_reason);
  return v_bal;
end $$;

create function public.admin_export() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]);
begin
  return jsonb_build_object('exported_at', now(),
    'profiles', (select coalesce(jsonb_agg(to_jsonb(p)), '[]') from public.profiles p),
    'wallets', (select coalesce(jsonb_agg(to_jsonb(w)), '[]') from public.wallets w),
    'ledger_entries', (select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at), '[]') from public.ledger_entries l),
    'bounties', (select coalesce(jsonb_agg(to_jsonb(b) order by b.created_at), '[]') from public.bounties b),
    'bounty_settlements', (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from public.bounty_settlements s),
    'events', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from public.events e),
    'matches', (select coalesce(jsonb_agg(to_jsonb(m)), '[]') from public.matches m),
    'audit_logs', (select coalesce(jsonb_agg(to_jsonb(a) order by a.id), '[]') from public.audit_logs a));
end $$;

create function public.ping() returns text language sql stable as $$ select 'ok'::text $$;   -- usata dal promemoria anti-pausa

-- ---------- Viste pubbliche (colonne sicure) ----------
create view public.bounty_value_v as
  select target_id, sum(amount)::integer as bounty_value, count(*)::integer as active_count, max(created_at) as last_at
  from public.bounties where status = 'active' group by target_id;

create view public.most_wanted_v as
  select p.id, p.nickname, p.avatar, v.bounty_value, v.active_count, v.last_at
  from public.profiles p join public.bounty_value_v v on v.target_id = p.id where not p.suspended;

create view public.bounties_public_v as
  select b.id, b.target_id,
         case when coalesce(public._setting('show_bounty_authors'), 1) = 1 then b.creator_id end as creator_id,
         b.amount, b.message, b.status, b.created_at, b.settled_at, b.settlement_id
  from public.bounties b;

create view public.market_feed_v as
  select 'bounty'::text as kind, created_at as at, creator_id as actor_id, target_id, amount, id as ref_id from public.bounties_public_v
  union all
  select 'claim'::text, s.created_at, s.winner_id, s.target_id, s.payout + s.refunded, s.id from public.bounty_settlements s where s.quotas_count > 0;

create view public.wallet_reconciliation_v as   -- visibile solo agli amministratori
  select w.user_id, w.balance, coalesce(sum(l.amount), 0)::integer as ledger_sum, (w.balance = coalesce(sum(l.amount), 0)) as ok
  from public.wallets w left join public.ledger_entries l on l.user_id = w.user_id
  where public.is_admin() group by w.user_id, w.balance;

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.system_settings enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.events enable row level security;
alter table public.event_participants enable row level security;
alter table public.matches enable row level security;
alter table public.bounty_settlements enable row level security;
alter table public.bounties enable row level security;
alter table public.disputes enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_read on public.profiles for select to authenticated using (true);
create policy settings_read on public.system_settings for select to authenticated using (true);
create policy wallets_read on public.wallets for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy ledger_read on public.ledger_entries for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy events_read on public.events for select to authenticated using (true);
create policy participants_read on public.event_participants for select to authenticated using (true);
create policy matches_read on public.matches for select to authenticated using (true);
create policy settlements_read on public.bounty_settlements for select to authenticated using (true);
create policy bounties_read on public.bounties for select to authenticated using (creator_id = auth.uid() or public.is_admin());
create policy disputes_read on public.disputes for select to authenticated using (opened_by = auth.uid() or public.is_admin());
create policy audit_read on public.audit_logs for select to authenticated using (public.is_admin());

-- ---------- Permessi: nessuna scrittura diretta, solo le funzioni ----------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.system_settings, public.wallets, public.ledger_entries, public.events, public.event_participants,
  public.matches, public.bounty_settlements, public.bounties, public.disputes, public.audit_logs to authenticated;
grant select on public.bounty_value_v, public.most_wanted_v, public.bounties_public_v, public.market_feed_v, public.wallet_reconciliation_v to authenticated;
grant execute on function public.is_admin(), public._setting(text) to authenticated;   -- servono alle policy RLS e alle viste
grant execute on function public.register_profile(text), public.update_my_profile(text, boolean),
  public.create_bounty(uuid, integer, text, text), public.create_event(text, date), public.add_participant(uuid, uuid),
  public.create_match(uuid, integer, uuid, uuid), public.verify_match(uuid, uuid), public.award_participation(uuid),
  public.claim_bounty(uuid), public.open_dispute(uuid, uuid, text), public.resolve_dispute(uuid, text),
  public.admin_set_bounty_review(uuid, boolean, text), public.admin_cancel_bounty(uuid, text),
  public.admin_set_role(uuid, public.app_role, text), public.admin_set_suspended(uuid, boolean, text),
  public.admin_set_setting(text, integer, text), public.admin_adjust_balance(uuid, integer, text), public.admin_export() to authenticated;
grant execute on function public.ping() to anon, authenticated;
