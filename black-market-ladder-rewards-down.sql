-- =====================================================================
-- ANNULLAMENTO della migrazione 004 (black-market-ladder-rewards.sql).
-- Cosa fa: riporta claim_bounty (001) e _ladder_close (003) al comportamento precedente, toglie le impostazioni e le colonne aggiunte.
-- Cosa NON fa (lo storico non si cancella mai):
--   * le righe 'ladder_reward' già scritte nel registro contabile restano e i saldi restano come sono;
--     la regola sui tipi di movimento torna quella originale ma vale solo per i NUOVI movimenti (constraint NOT VALID);
--   * i match ufficiali nati dalla Ladder e gli eventi "Ladder WPA ..." restano nella tabella dei match/eventi come match normali già verificati;
--   * il bonus iniziale torna a 300 solo se è ancora esattamente 1000 (con voce di audit); gli iscritti già entrati con 1000 BC li tengono.
-- Eseguilo prima dell'annullamento della 003 (stesso ordine inverso delle migrazioni).
-- =====================================================================
begin;
create or replace function public.claim_bounty(p_match uuid) returns jsonb language plpgsql security definer set search_path = public as $$
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

create or replace function public._ladder_close(p_id uuid, p_result text, p_score text, p_confirmer uuid, p_resolver uuid, p_reason text) returns jsonb
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

drop function if exists public._ladder_event(date);
drop index if exists public.events_ladder_day;
drop index if exists public.ladder_matches_reward_idx;
alter table public.ladder_matches drop column if exists official_match_id, drop column if exists official_note,
  drop column if exists reward_user, drop column if exists reward_amount, drop column if exists reward_note;
alter table public.matches drop column if exists ladder_match_id, drop column if exists source;
alter table public.events drop column if exists source;
alter table public.ledger_entries drop constraint if exists ledger_entries_kind_check;
alter table public.ledger_entries add constraint ledger_entries_kind_check
  check (kind in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment')) not valid;
delete from public.system_settings where key in ('ladder_reward_enabled','ladder_reward_bc','ladder_reward_max_day','ladder_reward_pair_day','ladder_wpa_matches','ladder_wpa_pair_day','ladder_claim_hold_hours');
do $$ begin
  if (select value_int from public.system_settings where key = 'initial_bonus') = 1000 then
    update public.system_settings set value_int = 300, updated_at = now() where key = 'initial_bonus';
    perform public._audit(null, 'set_setting', 'setting', 'initial_bonus', jsonb_build_object('value', 1000), jsonb_build_object('value', 300), 'annullamento migrazione 004');
  end if;
end $$;
commit;
