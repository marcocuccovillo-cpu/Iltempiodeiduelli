-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 019: taglia riscossa subito, senza attesa di 24 ore e senza passaggi a mano.
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO le migrazioni 001…018.
--
-- Prima: dopo aver battuto in Ladder un duellante con una taglia, il vincitore doveva aspettare 24 ore (controllo anti-accordi) e poi premere
-- «Riscuoti» da un'altra pagina; molti pensavano di non aver ricevuto nulla.
-- Ora, nelle sfide «per la taglia» e «Ladder + taglia»: quando i due giocatori hanno confermato il risultato (o l'amministratore lo ha deciso)
-- e il vincitore è chi ha lanciato o ricevuto la sfida con la taglia sul perdente, la taglia viene RISCOSSA NELLO STESSO ISTANTE:
-- il vincitore riceve le quote messe dagli altri, gli torna la sua parte, le taglie diventano «riscosse». In «Ladder + taglia» cambiano anche
-- l'Elo e il premio Ladder come prima; in «solo per la taglia» l'Elo non cambia.
--  1. ladder_claim_hold_hours passa a 0 (nessuna attesa). L'amministratore può rimetterla da Admin → Impostazioni: con un valore maggiore di 0 la
--     riscossione automatica si ferma e la taglia si riscuote a mano dopo l'attesa, come prima.
--  2. La logica di riscossione passa in una funzione interna (_bounty_settle) usata sia da claim_bounty (invariata per chi la chiama) sia
--     dalla chiusura del match: stessi controlli di prima (vincitore verificato, match valido per la taglia, nessuna taglia in revisione).
--  3. Se qualcosa impedisce la riscossione automatica (per esempio una taglia in revisione) il match si chiude lo stesso e la taglia resta
--     da riscuotere a mano da «Caccia alle taglie», senza perdere nulla; il messaggio lo spiega.
--  Nessun dato esistente cambia. Reversibile con black-market-ladder-taglia-immediata-down.sql.
-- =====================================================================
begin;

do $$
declare o integer;
begin
  select value_int into o from public.system_settings where key = 'ladder_claim_hold_hours' for update;
  if found and o <> 0 then
    update public.system_settings set value_int = 0, updated_at = now() where key = 'ladder_claim_hold_hours';
    perform public._audit(null, 'set_setting', 'setting', 'ladder_claim_hold_hours', jsonb_build_object('value', o), jsonb_build_object('value', 0), 'migrazione 019: taglia riscossa subito, nessuna attesa');
  end if;
end $$;

-- ---------- Riscossione (stessa logica della 011, ora riusabile) ----------
create or replace function public._bounty_settle(p_match uuid, v_me uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare m public.matches%rowtype; s public.bounty_settlements%rowtype; v_target uuid; v_sid uuid := gen_random_uuid();
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

create or replace function public.claim_bounty(p_match uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
begin
  return public._bounty_settle(p_match, v_me);
end $$;

-- ---------- Chiusura di un match Ladder: come nella 011, più la riscossione immediata ----------
create or replace function public._ladder_close(p_id uuid, p_result text, p_score text, p_confirmer uuid, p_resolver uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.ladder_matches%rowtype; start_elo integer := coalesce(public._setting('ladder_start_elo'), 1000);
        k integer := coalesce(public._setting('ladder_k'), 32); ea integer; eo integer; s numeric; da integer := 0;
        w uuid; l uuid; v_reward integer := 0; v_rnote text := null; v_off uuid := null; v_onote text := null;
        v_amt integer := coalesce(public._setting('ladder_reward_bc'), 0); n integer; v_event uuid; v_round integer; v_ver uuid;
        v_elo boolean; v_bty boolean; v_claim jsonb := null; v_cnote text := null;
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
        -- NUOVO (019): sfida per la taglia vinta = la taglia si riscuote subito, senza passaggi né attese (se c'è una taglia incassabile sul perdente)
        if v_bty and exists (select 1 from public.bounties where target_id = l and status = 'active') then
          begin
            v_claim := public._bounty_settle(v_off, w);
          exception when others then
            v_claim := null; v_cnote := sqlerrm;          -- per esempio taglia in revisione: resta da riscuotere a mano
          end;
        end if;
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
    'winner', w, 'reward', v_reward, 'reward_note', v_rnote, 'official_match', v_off, 'official_note', v_onote, 'kind', m.kind, 'format', m.format,
    'bounty_claim', v_claim, 'bounty_note', v_cnote);
end $$;

revoke all on function public._bounty_settle(uuid, uuid) from public, anon, authenticated;

commit;
