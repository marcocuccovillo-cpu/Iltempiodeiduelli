-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 020: la riscossione delle taglie è SEMPRE automatica.
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO le migrazioni 001…019.
--
-- La 019 rendeva immediata la riscossione alla conferma di una sfida Ladder. Restavano a mano: i match verificati da un organizzatore o da un
-- moderatore, le taglie rimaste ferme perché «in revisione», i match corretti dall'amministratore e le vittorie già registrate prima della 019.
-- Ora vale una regola sola, nel database: appena un match valido per la taglia diventa «verificato» con un vincitore (qualunque ne sia la via:
-- conferma Ladder, decisione dell'amministratore, verifica dell'organizzatore o del moderatore, correzione), il vincitore incassa le taglie
-- che il perdente aveva addosso in quel momento e gli torna la sua quota. Senza pulsanti e senza attese.
--  1. Un trigger sui match fa la riscossione al momento della verifica (stessi controlli di prima: vincitore verificato, match valido per la taglia).
--  2. Se una taglia sul perdente è IN REVISIONE la riscossione resta sospesa; appena l'amministratore o il moderatore toglie la revisione
--     (o la taglia viene chiusa) la riscossione parte da sola.
--  3. Una sola volta, in questa migrazione: le vittorie già verificate e mai riscosse vengono riscosse adesso (solo le taglie esistenti al
--     momento di quella vittoria, come sarebbe successo con la riscossione a mano).
--  4. Le funzioni a mano (claim_bounty, pulsante «Riscuoti») restano come rete di sicurezza e non pagano mai due volte.
--  Se rimetti un'attesa maggiore di 0 in «ladder_claim_hold_hours», per i match Ladder la riscossione automatica non parte e vale l'attesa.
-- Nessun BC viene creato: si pagano le quote che i creatori delle taglie avevano già versato. Reversibile con black-market-taglie-automatiche-down.sql.
-- =====================================================================
begin;

-- ---------- Riscossione automatica di un match (mai bloccante: se non si può, resta da fare più tardi) ----------
create function public._bounty_autoclaim(p_match uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare m public.matches%rowtype; v_loser uuid;
begin
  select * into m from public.matches where id = p_match;
  if not found or m.status <> 'verified' or m.winner_id is null or not m.bounty_eligible then return null; end if;
  if exists (select 1 from public.bounty_settlements where match_id = p_match) then return null; end if;
  v_loser := case when m.player_a = m.winner_id then m.player_b else m.player_a end;
  if not exists (select 1 from public.bounties where target_id = v_loser and status in ('active','under_review') and created_at <= m.verified_at) then return null; end if;
  begin
    return public._bounty_settle(p_match, m.winner_id);
  exception when others then
    return jsonb_build_object('pending', true, 'note', sqlerrm);          -- per esempio taglia in revisione: riparte da sola
  end;
end $$;

-- ---------- Trigger: un match che diventa verificato (o cambia vincitore) riscuote da solo ----------
create function public._trg_bounty_autoclaim() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'verified' and new.winner_id is not null and new.bounty_eligible then
    perform public._bounty_autoclaim(new.id);
  end if;
  return null;
end $$;
create trigger matches_bounty_autoclaim after insert or update of status, winner_id on public.matches
  for each row execute function public._trg_bounty_autoclaim();

-- ---------- Revisione tolta (o taglia chiusa): le riscossioni rimaste sospese ripartono ----------
create function public._bounty_sweep_target(p_target uuid) returns integer language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0; res jsonb;
begin
  for r in select m.id from public.matches m
           where m.status = 'verified' and m.winner_id is not null and m.bounty_eligible and (m.player_a = p_target or m.player_b = p_target) and m.winner_id <> p_target
             and not exists (select 1 from public.bounty_settlements s where s.match_id = m.id)
           order by m.verified_at, m.id loop
    res := public._bounty_autoclaim(r.id);
    if res is not null and coalesce((res->>'pending')::boolean, false) = false then n := n + 1; end if;
  end loop;
  return n;
end $$;
create function public._trg_bounty_review_end() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'under_review' and new.status <> 'under_review' then perform public._bounty_sweep_target(new.target_id); end if;
  return null;
end $$;
create trigger bounties_review_end after update of status on public.bounties
  for each row execute function public._trg_bounty_review_end();

-- ---------- Una tantum: vittorie già verificate e mai riscosse ----------
do $$
declare r record; n integer := 0; res jsonb;
begin
  for r in select m.id from public.matches m
           where m.status = 'verified' and m.winner_id is not null and m.bounty_eligible
             and not exists (select 1 from public.bounty_settlements s where s.match_id = m.id)
           order by m.verified_at, m.id loop
    res := public._bounty_autoclaim(r.id);
    if res is not null and coalesce((res->>'pending')::boolean, false) = false then n := n + 1; end if;
  end loop;
  raise notice 'Migrazione 020: % riscossioni in sospeso completate', n;
end $$;

-- ---------- Chiusura di un match Ladder: come nella 019, ma l'esito della riscossione si legge dopo il trigger ----------
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
        -- 019/020: sfida per la taglia vinta = la taglia si riscuote subito (la fa il trigger dei match; qui si legge l'esito per la risposta)
        if v_bty then
          v_claim := public._bounty_autoclaim(v_off);                  -- null se non c'era nulla da fare o l'ha già fatto il trigger
          if v_claim is not null and coalesce((v_claim->>'pending')::boolean, false) then v_cnote := v_claim->>'note'; v_claim := null; end if;   -- per esempio taglia in revisione
          if v_claim is null then
            select jsonb_build_object('settlement_id', s.id, 'already', true, 'payout', s.payout, 'refunded', s.refunded, 'quotas', s.quotas_count)
              into v_claim from public.bounty_settlements s where s.match_id = v_off;
          end if;
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

revoke all on function public._bounty_autoclaim(uuid), public._trg_bounty_autoclaim(), public._bounty_sweep_target(uuid), public._trg_bounty_review_end() from public, anon, authenticated;

commit;
