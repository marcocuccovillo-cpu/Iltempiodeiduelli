-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 011: Ladder con formati Advanced ed Edison, classifiche Elo separate e tipo di sfida.
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO le migrazioni 001…010. Annullamento: black-market-ladder-formati-down.sql.
--
-- 1. FORMATI. Le nuove sfide possono essere solo Advanced oppure Edison (controllo nel database, non solo nell'interfaccia).
--    Le partite già giocate negli altri formati restano nello storico, mai cancellate.
-- 2. CLASSIFICHE SEPARATE. L'Elo è ora uno per formato: ogni giocatore ha un Elo Advanced e un Elo Edison, partendo da 1000.
--    La tabella ladder_ratings passa a una riga per (giocatore, formato). La vecchia tabella, con l'Elo unico, NON viene
--    cancellata: si chiama ladder_ratings_legacy. Le nuove classifiche si ricostruiscono rigiocando in ordine tutte le partite
--    concluse in Advanced ed Edison (stessa formula, stesso K): le partite negli altri formati restano consultabili ma non contano.
-- 3. TIPO DI SFIDA. Chi sfida sceglie:
--      'ladder' = Ladder normale : Elo + premio Ladder (BC) + match WPA ufficiale, ma la vittoria NON dà diritto alla taglia;
--      'bounty' = per la taglia  : solo match WPA ufficiale valido per riscuotere la taglia; nessun Elo e nessun premio Ladder;
--      'both'   = entrambe       : Elo + premio Ladder + match WPA ufficiale valido anche per la taglia.
--    'bounty' e 'both' sono possibili solo se l'avversario ha taglie che lo sfidante può davvero incassare (non le proprie).
--    Il tipo lo vede lo sfidato PRIMA di accettare. La scelta è registrata e non si può cambiare dopo.
--    ladder_challenge ha un nuovo parametro facoltativo p_kind: se manca, vale il comportamento di prima
--    (taglie incassabili = 'both', altrimenti 'ladder').
-- 4. RISCOSSIONE. claim_bounty è identica alla 004 più un controllo: un match nato come Ladder normale non fa riscuotere nulla.
--    Tutti gli altri match (eventi degli organizzatori, sfide 'bounty' e 'both', partite precedenti a questa migrazione) restano riscuotibili.
-- 5. NOTIFICHE. Lo sfidato riceve il tipo di sfida nel testo; lo sfidante riceve un avviso quando la sfida viene accettata o rifiutata
--    (nuovi tipi ladder_accepted / ladder_declined, governati dalla preferenza «sfida in Ladder»).
-- 6. BADGE. Le sfide 'bounty' (senza Elo) non contano come partite di Ladder nei badge; contano come match ufficiali.
-- Nessun saldo, taglia, riscossione o notifica già esistente viene modificato o cancellato.
-- =====================================================================
begin;  -- tutto o niente

-- ---------- 1. Formati ----------
create function public._ladder_format_guard() returns trigger language plpgsql as $$
begin
  if new.format not in ('Advanced','Edison') then raise exception 'Formato non valido: in Ladder si gioca solo Advanced o Edison'; end if;
  return new;
end $$;
create trigger ladder_matches_format_guard before insert on public.ladder_matches for each row execute function public._ladder_format_guard();

-- ---------- 3. Tipo di sfida e idoneità del match alla riscossione ----------
alter table public.ladder_matches add column kind text not null default 'both' check (kind in ('ladder','bounty','both'));
alter table public.matches add column bounty_eligible boolean not null default true;

-- ---------- 2. Elo per formato ----------
alter table public.ladder_ratings rename to ladder_ratings_legacy;
alter index public.ladder_ratings_pkey rename to ladder_ratings_legacy_pkey;
alter index public.ladder_ratings_elo_idx rename to ladder_ratings_legacy_elo_idx;
drop view public.ladder_standings_v;

create table public.ladder_ratings (
  user_id uuid not null references public.profiles(id) on delete restrict,
  format text not null check (format in ('Advanced','Edison')),
  elo integer not null check (elo between 0 and 5000),
  wins integer not null default 0 check (wins >= 0),
  draws integer not null default 0 check (draws >= 0),
  losses integer not null default 0 check (losses >= 0),
  last_match_at timestamptz,
  primary key (user_id, format)
);
create index ladder_ratings_elo_idx on public.ladder_ratings (format, elo desc);
create trigger ladder_ratings_no_delete before delete on public.ladder_ratings for each row execute function public._no_delete();

-- Ricostruzione: si rigiocano in ordine le partite concluse in Advanced ed Edison (le altre restano solo nello storico)
do $$
declare m record; ea integer; eo integer; da integer; s numeric;
        st integer := coalesce(public._setting('ladder_start_elo'), 1000); k integer := coalesce(public._setting('ladder_k'), 32);
begin
  for m in select * from public.ladder_matches where status = 'closed' and format in ('Advanced','Edison') order by closed_at, id loop
    insert into public.ladder_ratings (user_id, format, elo) values (m.challenger_id, m.format, st), (m.opponent_id, m.format, st) on conflict do nothing;
    select elo into ea from public.ladder_ratings where user_id = m.challenger_id and format = m.format;
    select elo into eo from public.ladder_ratings where user_id = m.opponent_id and format = m.format;
    s := case m.reported_result when 'challenger' then 1.0 when 'opponent' then 0.0 else 0.5 end;
    da := round(k * (s - 1.0 / (1.0 + power(10.0, (eo - ea) / 400.0))))::integer;
    update public.ladder_ratings set elo = greatest(0, elo + da), last_match_at = m.closed_at,
      wins = wins + (m.reported_result = 'challenger')::integer, draws = draws + (m.reported_result = 'draw')::integer, losses = losses + (m.reported_result = 'opponent')::integer
      where user_id = m.challenger_id and format = m.format;
    update public.ladder_ratings set elo = greatest(0, elo - da), last_match_at = m.closed_at,
      wins = wins + (m.reported_result = 'opponent')::integer, draws = draws + (m.reported_result = 'draw')::integer, losses = losses + (m.reported_result = 'challenger')::integer
      where user_id = m.opponent_id and format = m.format;
  end loop;
end $$;

create view public.ladder_standings_v as
  select r.user_id, p.nickname, p.avatar, r.format, r.elo, r.wins, r.draws, r.losses,
         (r.wins + r.draws + r.losses)::integer as matches, r.last_match_at,
         rank() over (partition by r.format order by r.elo desc, r.wins desc)::integer as rank
  from public.ladder_ratings r join public.profiles p on p.id = r.user_id
  where public._module_on('ladder');

alter table public.ladder_ratings enable row level security;
create policy ladder_ratings_read on public.ladder_ratings for select to authenticated
  using (public._module_on('ladder') or public.is_admin());
revoke all on public.ladder_ratings, public.ladder_ratings_legacy, public.ladder_standings_v from public, anon, authenticated;
grant select on public.ladder_ratings, public.ladder_standings_v to authenticated;

-- ---------- Chiusura di un match Ladder: Elo del formato + premio + match ufficiale (un solo punto di calcolo) ----------
create or replace function public._ladder_close(p_id uuid, p_result text, p_score text, p_confirmer uuid, p_resolver uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.ladder_matches%rowtype; start_elo integer := coalesce(public._setting('ladder_start_elo'), 1000);
        k integer := coalesce(public._setting('ladder_k'), 32); ea integer; eo integer; s numeric; da integer := 0;
        w uuid; l uuid; v_reward integer := 0; v_rnote text := null; v_off uuid := null; v_onote text := null;
        v_amt integer := coalesce(public._setting('ladder_reward_bc'), 0); n integer; v_event uuid; v_round integer; v_ver uuid;
        v_elo boolean; v_bty boolean;
begin
  select * into m from public.ladder_matches where id = p_id for update;
  if m.status not in ('accepted','reported','disputed') then raise exception 'Il match non è chiudibile'; end if;
  v_elo := m.kind in ('ladder','both');          -- conta per Elo e premio Ladder
  v_bty := m.kind in ('bounty','both');          -- il match ufficiale vale per riscuotere la taglia
  if v_elo then
    insert into public.ladder_ratings (user_id, format, elo) values (m.challenger_id, m.format, start_elo), (m.opponent_id, m.format, start_elo) on conflict do nothing;
    perform 1 from public.ladder_ratings where user_id in (m.challenger_id, m.opponent_id) and format = m.format order by user_id for update;   -- ordine fisso: niente blocchi incrociati
    select elo into ea from public.ladder_ratings where user_id = m.challenger_id and format = m.format;
    select elo into eo from public.ladder_ratings where user_id = m.opponent_id and format = m.format;
    s := case p_result when 'challenger' then 1.0 when 'opponent' then 0.0 else 0.5 end;
    da := round(k * (s - 1.0 / (1.0 + power(10.0, (eo - ea) / 400.0))))::integer;
    update public.ladder_ratings set elo = greatest(0, elo + da), last_match_at = clock_timestamp(),
      wins = wins + (p_result = 'challenger')::integer, draws = draws + (p_result = 'draw')::integer, losses = losses + (p_result = 'opponent')::integer
      where user_id = m.challenger_id and format = m.format;
    update public.ladder_ratings set elo = greatest(0, elo - da), last_match_at = clock_timestamp(),
      wins = wins + (p_result = 'opponent')::integer, draws = draws + (p_result = 'draw')::integer, losses = losses + (p_result = 'challenger')::integer
      where user_id = m.opponent_id and format = m.format;
  end if;

  if p_result in ('challenger','opponent') then
    w := case p_result when 'challenger' then m.challenger_id else m.opponent_id end;
    l := case p_result when 'challenger' then m.opponent_id else m.challenger_id end;

    -- Premio in Black Credits (creati dal sistema, non tolti allo sconfitto): solo se la sfida conta per la Ladder
    if not v_elo then
      v_rnote := 'sfida solo per la taglia: nessun premio Ladder';
    elsif coalesce(public._setting('ladder_reward_enabled'), 0) <> 1 or v_amt <= 0 then
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

    -- Match ufficiale WPA (il limite giornaliero per coppia vale separatamente per i match "per la taglia" e per quelli normali)
    if coalesce(public._setting('ladder_wpa_matches'), 0) <> 1 then
      v_onote := 'match ufficiali Ladder spenti';
    elsif (select count(*) from public.matches mm where mm.source = 'ladder' and mm.bounty_eligible = v_bty and mm.verified_at > clock_timestamp() - interval '24 hours'
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
        insert into public.matches (id, event_id, round, player_a, player_b, winner_id, status, verified_by, verified_at, created_by, source, ladder_match_id, bounty_eligible)
        values (v_off, v_event, v_round, m.challenger_id, m.opponent_id, w, 'verified', v_ver, clock_timestamp(), v_ver, 'ladder', p_id, v_bty);
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
    'winner', w, 'reward', v_reward, 'reward_note', v_rnote, 'official_match', v_off, 'official_note', v_onote, 'kind', m.kind, 'format', m.format);
end $$;

-- ---------- Riscossione: identica alla 004 + un controllo (il match deve valere per la taglia) ----------
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
  if not m.bounty_eligible then raise exception 'Questo match era una sfida Ladder normale, non una sfida per la taglia: non dà diritto a riscuotere'; end if;   -- NUOVO (011)
  if m.source = 'ladder' then                                                   -- attesa anti-accordi per i match Ladder (004)
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

-- ---------- Lancio di una sfida: nuovo parametro p_kind ----------
drop function public.ladder_challenge(uuid, text, text, text);
create function public.ladder_challenge(p_opponent uuid, p_format text, p_message text, p_request_id text, p_kind text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid; v_id uuid := gen_random_uuid(); ex uuid; v_claim integer; v_kind text;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['user','organizer','admin']::public.app_role[]);
  if p_request_id is null or char_length(p_request_id) < 8 then raise exception 'Richiesta non valida'; end if;
  select id into ex from public.ladder_matches where challenger_id = v and client_request_id = p_request_id;
  if found then return ex; end if;                                               -- richiesta ripetuta: nessuna doppia sfida
  if p_opponent is null or p_opponent = v then raise exception 'Scegli un altro duellante'; end if;
  if p_format is null or p_format not in ('Advanced','Edison') then raise exception 'Formato non valido: in Ladder si gioca solo Advanced o Edison'; end if;
  if p_kind is not null and p_kind not in ('ladder','bounty','both') then raise exception 'Tipo di sfida non valido'; end if;
  if not exists (select 1 from public.profiles where id = p_opponent and not suspended) then raise exception 'Duellante non disponibile'; end if;
  perform 1 from public.profiles where id = v for update;                        -- serializza le sfide dello stesso utente
  if (select count(*) from public.ladder_matches where challenger_id = v and status in ('pending','accepted','reported','disputed'))
       >= coalesce(public._setting('ladder_max_open'), 5) then raise exception 'Hai troppe sfide aperte'; end if;
  if (select count(*) from public.ladder_matches where status = 'closed' and closed_at > clock_timestamp() - interval '24 hours'
        and least(challenger_id, opponent_id) = least(v, p_opponent) and greatest(challenger_id, opponent_id) = greatest(v, p_opponent))
       >= coalesce(public._setting('ladder_max_pair_per_day'), 3) then raise exception 'Limite giornaliero di match con questo duellante raggiunto'; end if;
  -- taglie che lo sfidante può davvero incassare: le quote attive degli altri (le proprie gli tornano indietro, non sono un guadagno)
  select coalesce(sum(amount), 0)::integer into v_claim from public.bounties where target_id = p_opponent and status = 'active' and creator_id <> v;
  v_kind := coalesce(p_kind, case when v_claim > 0 then 'both' else 'ladder' end);
  if v_kind in ('bounty','both') and v_claim <= 0 then
    raise exception 'Questo duellante non ha taglie che tu possa riscuotere: scegli «Ladder normale»'; end if;
  begin
    insert into public.ladder_matches (id, challenger_id, opponent_id, format, kind, message, client_request_id, expires_at)
    values (v_id, v, p_opponent, p_format, v_kind, nullif(btrim(p_message), ''), p_request_id, clock_timestamp() + make_interval(days => coalesce(public._setting('ladder_expiry_days'), 7)));
  exception when unique_violation then raise exception 'Esiste già una sfida aperta con questo duellante';
            when check_violation then raise exception 'Dati della sfida non validi'; end;
  perform public._audit(v, 'ladder_challenge', 'ladder_match', v_id::text, null, jsonb_build_object('opponent', p_opponent, 'format', p_format, 'kind', v_kind), null);
  return v_id;
end $$;

-- ---------- Notifiche: tipo di sfida nel testo + risposta allo sfidante ----------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('bounty_received','ladder_challenge','bounty_challenge','test','ladder_accepted','ladder_declined'));

create or replace function public._notify(p_user uuid, p_kind text, p_title text, p_body text, p_url text, p_ref_type text, p_ref uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
begin
  if coalesce(public._setting('notifications_enabled'), 1) <> 1 then return; end if;
  select case when p_kind = 'bounty_received' then coalesce(bounty, true)
              when p_kind in ('ladder_challenge','ladder_accepted','ladder_declined') then coalesce(ladder, true)
              else coalesce(hunt, true) end
    into v_ok from public.notification_prefs where user_id = p_user;
  if not found then v_ok := true; end if;                                              -- nessuna preferenza salvata = tutto acceso
  if not v_ok then return; end if;
  insert into public.notifications (user_id, kind, title, body, url, ref_type, ref_id) values (p_user, p_kind, p_title, p_body, p_url, p_ref_type, p_ref)
    on conflict (user_id, kind, ref_id) do nothing;
end $$;

create or replace function public._trg_notify_ladder() returns trigger language plpgsql security definer set search_path = public as $$
declare v_nick text; v_hunt integer; v_pref boolean;
begin
  begin
    if tg_op = 'INSERT' and new.status = 'pending' then
      select nickname into v_nick from public.profiles where id = new.challenger_id;
      select coalesce(sum(amount), 0)::integer into v_hunt from public.bounties          -- la parte che il cacciatore potrebbe davvero incassare
        where target_id = new.opponent_id and status = 'active' and creator_id <> new.challenger_id;
      select coalesce(hunt, true) into v_pref from public.notification_prefs where user_id = new.opponent_id;
      if not found then v_pref := true; end if;
      if new.kind in ('bounty','both') and v_hunt > 0 and v_pref then
        perform public._notify(new.opponent_id, 'bounty_challenge', 'Sfida per la tua taglia!',
          case when new.kind = 'bounty'
            then format('%s ti ha sfidato (%s) per riscuotere la taglia da %s BC che hai addosso. Nessun Elo in gioco: conta solo per la taglia.', coalesce(v_nick, 'Un duellante'), new.format, v_hunt)
            else format('%s ti ha sfidato in Ladder (%s) per riscuotere la taglia da %s BC che hai addosso. In gioco anche l''Elo.', coalesce(v_nick, 'Un duellante'), new.format, v_hunt) end,
          'black-market.html#/ladder', 'ladder_match', new.id);
      else                                                                              -- Ladder normale (o "sfida per la taglia" spento): sfida Ladder
        perform public._notify(new.opponent_id, 'ladder_challenge', 'Nuova sfida in Ladder',
          format('%s ti ha sfidato in Ladder (%s).', coalesce(v_nick, 'Un duellante'), new.format),
          'black-market.html#/ladder', 'ladder_match', new.id);
      end if;
    elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('accepted','declined') then
      select nickname into v_nick from public.profiles where id = new.opponent_id;
      if new.status = 'accepted' then
        perform public._notify(new.challenger_id, 'ladder_accepted', 'Sfida accettata',
          format('%s ha accettato la tua sfida (%s). Giocate e inviate il risultato dalla Ladder.', coalesce(v_nick, 'Il duellante'), new.format),
          'black-market.html#/ladder', 'ladder_match', new.id);
      else
        perform public._notify(new.challenger_id, 'ladder_declined', 'Sfida rifiutata',
          format('%s ha rifiutato la tua sfida (%s).', coalesce(v_nick, 'Il duellante'), new.format),
          'black-market.html#/ladder', 'ladder_match', new.id);
      end if;
    end if;
  exception when others then null;
  end;
  return null;
end $$;
drop trigger if exists notify_ladder on public.ladder_matches;
create trigger notify_ladder after insert or update of status on public.ladder_matches for each row execute function public._trg_notify_ladder();

-- ---------- Permessi ----------
revoke all on function public._ladder_format_guard(), public._ladder_close(uuid, text, text, uuid, uuid, text), public.claim_bounty(uuid),
  public.ladder_challenge(uuid, text, text, text, text), public._notify(uuid, text, text, text, text, text, uuid), public._trg_notify_ladder() from public, anon, authenticated;
grant execute on function public.claim_bounty(uuid), public.ladder_challenge(uuid, text, text, text, text) to authenticated;

-- ---------- 6. Badge: le sfide solo per la taglia (senza Elo) non sono partite di Ladder ----------
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
    where ladder_on and l.status = 'closed' and l.kind <> 'bounty' and (l.challenger_id = u or l.opponent_id = u)),   -- 011: le sfide solo per la taglia non contano come Ladder
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

commit;
