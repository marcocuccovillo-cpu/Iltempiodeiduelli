-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 004: bonus iniziale 1000 BC + premi Ladder + vittorie Ladder come match WPA ufficiali.
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO 001, 002 e 003.
--
-- Cosa cambia (tutto additivo e reversibile con black-market-ladder-rewards-down.sql):
--  1. Bonus iniziale: l'impostazione initial_bonus passa da 300 a 1000 BC SOLO se è ancora al valore originale (300).
--     Vale per i NUOVI iscritti: chi è già iscritto non viene toccato (se vuoi dargli la differenza usa "Rettifica saldo" dal pannello Admin).
--  2. Premio Ladder: ogni VITTORIA confermata (non pareggio, non sconfitta) GENERA ladder_reward_bc Black Credits (20) per il vincitore.
--     I BC sono creati dal sistema, NON tolti allo sconfitto: nessun trasferimento tra utenti. Registro contabile, idempotenza e audit come per il resto.
--     Limiti anti-abuso (modificabili dall'Admin con admin_set_setting): max ladder_reward_max_day (3) vittorie premiate nelle 24 ore per giocatore,
--     max ladder_reward_pair_day (1) vittoria premiata nelle 24 ore contro lo stesso avversario.
--  3. Match WPA: una vittoria Ladder confermata dai due giocatori (o decisa dall'Admin) diventa anche un match UFFICIALE verificato,
--     inserito nell'evento automatico "Ladder WPA AAAA-MM-GG". Conta quindi per Hall of Fame, Faction Wars e per la riscossione delle taglie.
--     I pareggi restano solo Elo (un match ufficiale richiede un vincitore).
--     Limite: ladder_wpa_pair_day (1) match ufficiale nelle 24 ore per la stessa coppia (le altre partite contano per l'Elo ma non come match WPA).
--  4. Protezione anti-accordi sulle taglie: la riscossione di una taglia basata su un match Ladder si sblocca dopo ladder_claim_hold_hours (24) ore
--     dalla conferma. In questo intervallo l'Admin può mettere la taglia "in revisione" (funzione già esistente). Per i match degli organizzatori nulla cambia.
--     Per questo claim_bounty viene riscritta identica, con UN solo controllo in più (vale solo per i match con source = 'ladder').
--  5. Interruttori: ladder_reward_enabled (1) e ladder_wpa_matches (1) spengono premi e match ufficiali senza toccare la Ladder (Elo).
--  Le partite Ladder concluse PRIMA di questa migrazione non ricevono premi né diventano match ufficiali (nessun effetto retroattivo).
-- =====================================================================
begin;  -- tutto o niente

-- ---------- Impostazioni ----------
insert into public.system_settings (key, value_int, description) values
 ('ladder_reward_enabled',   1,  'Ladder: 1 = ogni vittoria confermata genera BC, 0 = nessun premio'),
 ('ladder_reward_bc',        20, 'Ladder: BC generati per ogni vittoria confermata'),
 ('ladder_reward_max_day',   3,  'Ladder: massimo di vittorie premiate nelle 24 ore per giocatore'),
 ('ladder_reward_pair_day',  1,  'Ladder: massimo di vittorie premiate nelle 24 ore contro lo stesso avversario'),
 ('ladder_wpa_matches',      1,  'Ladder: 1 = le vittorie confermate diventano match ufficiali WPA, 0 = solo Elo'),
 ('ladder_wpa_pair_day',     1,  'Ladder: massimo di match ufficiali WPA nelle 24 ore per la stessa coppia'),
 ('ladder_claim_hold_hours', 24, 'Ladder: ore di attesa prima di poter riscuotere una taglia con un match Ladder (0 = nessuna attesa)')
on conflict (key) do nothing;

do $$
declare o integer;
begin
  select value_int into o from public.system_settings where key = 'initial_bonus' for update;
  if o = 300 then
    update public.system_settings set value_int = 1000, updated_at = now() where key = 'initial_bonus';
    perform public._audit(null, 'set_setting', 'setting', 'initial_bonus', jsonb_build_object('value', 300), jsonb_build_object('value', 1000), 'migrazione 004: bonus iniziale a 1000 BC per i nuovi iscritti');
  end if;
end $$;

-- ---------- Nuovo tipo di movimento nel registro (additivo) ----------
alter table public.ledger_entries drop constraint ledger_entries_kind_check;
alter table public.ledger_entries add constraint ledger_entries_kind_check
  check (kind in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment','ladder_reward'));

-- ---------- Colonne nuove (nessun dato esistente cambia) ----------
alter table public.events  add column source text not null default 'organizer' check (source in ('organizer','ladder'));
alter table public.matches add column source text not null default 'organizer' check (source in ('organizer','ladder'));
alter table public.matches add column ladder_match_id uuid unique references public.ladder_matches(id) on delete restrict;
alter table public.ladder_matches
  add column reward_user uuid references public.profiles(id),
  add column reward_amount integer not null default 0 check (reward_amount >= 0),
  add column reward_note text,
  add column official_match_id uuid references public.matches(id) on delete restrict,
  add column official_note text;
create unique index events_ladder_day on public.events (event_date) where source = 'ladder';
create index ladder_matches_reward_idx on public.ladder_matches (reward_user, closed_at desc) where reward_amount > 0;

-- ---------- Evento automatico del giorno ----------
create function public._ladder_event(p_day date) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_admin uuid;
begin
  select id into v_id from public.events where source = 'ladder' and event_date = p_day;
  if found then return v_id; end if;
  select id into v_admin from public.profiles where role = 'admin' and not suspended order by created_at limit 1;
  if v_admin is null then return null; end if;                      -- nessun amministratore attivo: nessun match ufficiale
  insert into public.events (name, event_date, created_by, source) values ('Ladder WPA ' || to_char(p_day, 'YYYY-MM-DD'), p_day, v_admin, 'ladder')
    on conflict (event_date) where source = 'ladder' do nothing;
  select id into v_id from public.events where source = 'ladder' and event_date = p_day;
  return v_id;
end $$;

-- ---------- Chiusura di un match Ladder: Elo + premio + match ufficiale (un solo punto di calcolo) ----------
create or replace function public._ladder_close(p_id uuid, p_result text, p_score text, p_confirmer uuid, p_resolver uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.ladder_matches%rowtype; start_elo integer := coalesce(public._setting('ladder_start_elo'), 1000);
        k integer := coalesce(public._setting('ladder_k'), 32); ea integer; eo integer; s numeric; da integer;
        w uuid; l uuid; v_reward integer := 0; v_rnote text := null; v_off uuid := null; v_onote text := null;
        v_amt integer := coalesce(public._setting('ladder_reward_bc'), 0); n integer; v_event uuid; v_round integer; v_ver uuid;
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

  if p_result in ('challenger','opponent') then
    w := case p_result when 'challenger' then m.challenger_id else m.opponent_id end;
    l := case p_result when 'challenger' then m.opponent_id else m.challenger_id end;

    -- Premio in Black Credits (creati dal sistema, non tolti allo sconfitto)
    if coalesce(public._setting('ladder_reward_enabled'), 0) <> 1 or v_amt <= 0 then
      v_rnote := 'premi spenti';
    else
      perform 1 from public.wallets where user_id = w for update;                 -- serializza i premi dello stesso giocatore
      select count(*) into n from public.ladder_matches
        where reward_user = w and reward_amount > 0 and closed_at > clock_timestamp() - interval '24 hours';
      if n >= coalesce(public._setting('ladder_reward_max_day'), 3) then
        v_rnote := 'limite giornaliero di vittorie premiate raggiunto';
      else
        select count(*) into n from public.ladder_matches
          where reward_user = w and reward_amount > 0 and closed_at > clock_timestamp() - interval '24 hours'
            and (challenger_id = l or opponent_id = l);
        if n >= coalesce(public._setting('ladder_reward_pair_day'), 1) then
          v_rnote := 'già premiata una vittoria contro questo avversario nelle ultime 24 ore';
        else
          perform public._ledger_move(w, v_amt, 'ladder_reward', 'ladder_match', p_id, 'ladder:' || p_id, 'Vittoria in Ladder');
          v_reward := v_amt;
        end if;
      end if;
    end if;

    -- Match ufficiale WPA
    if coalesce(public._setting('ladder_wpa_matches'), 0) <> 1 then
      v_onote := 'match ufficiali Ladder spenti';
    elsif (select count(*) from public.matches mm where mm.source = 'ladder' and mm.verified_at > clock_timestamp() - interval '24 hours'
             and least(mm.player_a, mm.player_b) = least(m.challenger_id, m.opponent_id)
             and greatest(mm.player_a, mm.player_b) = greatest(m.challenger_id, m.opponent_id))
          >= coalesce(public._setting('ladder_wpa_pair_day'), 1) then
      v_onote := 'già registrato un match ufficiale tra questi duellanti nelle ultime 24 ore';
    else
      v_event := public._ladder_event((clock_timestamp() at time zone 'Europe/Rome')::date);
      if v_event is null then
        v_onote := 'nessun amministratore attivo';
      else
        v_ver := coalesce(p_confirmer, p_resolver);
        select count(*) + 1 into v_round from public.matches mm
          where mm.event_id = v_event and least(mm.player_a, mm.player_b) = least(m.challenger_id, m.opponent_id)
            and greatest(mm.player_a, mm.player_b) = greatest(m.challenger_id, m.opponent_id);
        v_off := gen_random_uuid();
        insert into public.matches (id, event_id, round, player_a, player_b, winner_id, status, verified_by, verified_at, created_by, source, ladder_match_id)
        values (v_off, v_event, v_round, m.challenger_id, m.opponent_id, w, 'verified', v_ver, clock_timestamp(), v_ver, 'ladder', p_id);
      end if;
    end if;
  end if;

  update public.ladder_matches set status = 'closed', reported_result = p_result, reported_score = p_score, closed_at = clock_timestamp(),
    confirmed_by = p_confirmer, resolved_by = p_resolver, resolution_reason = p_reason,
    elo_challenger_before = ea, elo_opponent_before = eo, elo_challenger_delta = da, elo_opponent_delta = -da,
    reward_user = case when v_reward > 0 then w end, reward_amount = v_reward, reward_note = v_rnote,
    official_match_id = v_off, official_note = v_onote
    where id = p_id;
  return jsonb_build_object('challenger_delta', da, 'opponent_delta', -da, 'challenger_elo', ea + da, 'opponent_elo', eo - da,
    'winner', w, 'reward', v_reward, 'reward_note', v_rnote, 'official_match', v_off, 'official_note', v_onote);
end $$;

-- ---------- claim_bounty: identica alla 001 + un solo controllo per i match Ladder ----------
create or replace function public.claim_bounty(p_match uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
        m public.matches%rowtype; s public.bounty_settlements%rowtype; v_target uuid; v_sid uuid := gen_random_uuid();
        v_pay integer; v_ref integer; v_n integer; v_frozen integer; v_hold integer;
begin
  select * into m from public.matches where id = p_match for update;           -- serializza le richieste sullo stesso match
  if not found then raise exception 'Match inesistente'; end if;
  if m.status <> 'verified' then raise exception 'Match non verificato: nessuna riscossione possibile'; end if;
  if m.winner_id is distinct from v_me then raise exception 'Solo il vincitore verificato può riscuotere'; end if;
  select * into s from public.bounty_settlements where match_id = p_match;
  if found then return jsonb_build_object('settlement_id', s.id, 'already', true, 'payout', s.payout, 'refunded', s.refunded); end if;
  if m.source = 'ladder' then                                                   -- NUOVO (004): attesa anti-accordi per i match Ladder
    v_hold := coalesce(public._setting('ladder_claim_hold_hours'), 24);
    if v_hold > 0 and m.verified_at > clock_timestamp() - make_interval(hours => v_hold) then
      raise exception 'Match Ladder: la taglia si potrà riscuotere dopo % ore dalla conferma (controllo anti-accordi)', v_hold;
    end if;
  end if;
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

-- ---------- Permessi ----------
revoke all on function public._ladder_event(date) from public, anon, authenticated;
commit;
