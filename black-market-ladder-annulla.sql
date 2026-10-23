-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 022: annullamento di un risultato Ladder già concluso (solo amministratori).
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO le migrazioni 001…021. Si può rieseguire.
--
-- Con admin_ladder_cancel_closed(match, motivazione) l'amministratore cancella una sfida Ladder già conclusa come se non fosse mai stata
-- giocata (il match passa a «Annullato» e resta nello storico). Tutto in un'unica operazione (o tutto o niente):
--  1. ELO: la classifica del formato viene ricalcolata senza quel match (e le variazioni degli altri match dei due giocatori si aggiornano,
--     perché l'Elo dipende dall'ordine). Vittorie, pareggi e sconfitte tornano quelli di prima.
--  2. PREMIO IN BC: se il vincitore aveva ricevuto il premio Ladder, gli viene tolto (al massimo quanto ha ancora nel wallet). Il movimento è
--     nel registro, di tipo «admin_adjustment». Il premio annullato non conta più nei limiti giornalieri.
--  3. MATCH WPA UFFICIALE: viene rimosso dall'evento «Ladder WPA» del giorno e i turni degli altri match della stessa coppia si riallineano.
--  4. LIMITI GIORNALIERI: il match annullato non conta più nel limite di match al giorno con lo stesso avversario: possono rigiocarlo.
--  5. I due giocatori ricevono una notifica; tutto finisce nell'audit con prima e dopo.
--  Si rifiuta (e non cambia nulla) se sul match è già stata riscossa una taglia, o se il match ufficiale è usato altrove
--  (sfida, contestazione, esclusione dalle fazioni). Solo amministratori (non moderatori). Motivazione obbligatoria.
--  I match NON conclusi si annullano come prima (admin_ladder_void / ladder_cancel). Il guardiano dei match chiusi resta, con una sola
--  eccezione in più: questa funzione.
-- Reversibile con black-market-ladder-annulla-down.sql (ferma le nuove funzioni; i match già annullati restano annullati).
-- =====================================================================
begin;

-- guardiano: un match concluso non si modifica, salvo la correzione (resta 'closed') e l'annullamento (diventa 'voided'): lo dichiarano con
-- un'impostazione di sessione che vale solo dentro la transazione
create or replace function public._ladder_guard() returns trigger language plpgsql as $$
begin
  if old.status in ('closed','declined','cancelled','expired','voided') then
    if old.status = 'closed' and new.status in ('closed', 'voided') and coalesce(current_setting('app.ladder_correct', true), '') = 'on' then return new; end if;
    raise exception 'Match della Ladder già concluso: non è più modificabile';
  end if;
  return new;
end $$;

create or replace function public.admin_ladder_cancel_closed(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v uuid; r text := btrim(coalesce(p_reason, '')); m public.ladder_matches%rowtype; om public.matches%rowtype;
        v_bal integer; v_rev integer := 0; v_off uuid; v_elo boolean; rr record; v_old jsonb; v_new jsonb; n1 text; n2 text; txt text;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['admin']::public.app_role[]);
  if char_length(r) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into m from public.ladder_matches where id = p_id for update;
  if not found then raise exception 'Match non trovato'; end if;
  if m.status <> 'closed' then raise exception 'Qui si annullano solo i match già conclusi (gli altri si annullano dalla lista delle sfide)'; end if;
  v_elo := m.kind in ('ladder','both');
  v_off := m.official_match_id;
  if v_off is not null then
    select * into om from public.matches where id = v_off for update;
    if exists (select 1 from public.bounty_settlements where match_id = v_off) then
      raise exception 'Su questo match è già stata riscossa una taglia: non si può annullare'; end if;
    if exists (select 1 from public.faction_match_exclusions where match_id = v_off) or exists (select 1 from public.challenges where match_id = v_off)
       or exists (select 1 from public.disputes where match_id = v_off) then
      raise exception 'Il match ufficiale collegato è usato altrove (sfida, contestazione o esclusione): non si può annullare'; end if;
  end if;
  v_old := jsonb_build_object('result', m.reported_result, 'score', m.reported_score, 'challenger_delta', m.elo_challenger_delta, 'opponent_delta', m.elo_opponent_delta,
                              'reward_user', m.reward_user, 'reward_amount', m.reward_amount, 'official_match', m.official_match_id, 'format', m.format, 'kind', m.kind);

  perform set_config('app.ladder_correct', 'on', true);          -- vale solo dentro questa transazione, per il guardiano dei match chiusi

  -- ---- match ufficiale WPA: via, e i turni successivi della coppia scalano di uno ----
  if v_off is not null then
    update public.ladder_matches set official_match_id = null where id = p_id;
    delete from public.matches where id = v_off;
    for rr in select id from public.matches where event_id = om.event_id and round > om.round
                 and least(player_a, player_b) = least(om.player_a, om.player_b) and greatest(player_a, player_b) = greatest(om.player_a, om.player_b) order by round loop
      update public.matches set round = round - 1 where id = rr.id;
    end loop;
  end if;

  -- ---- premio in BC: si toglie a chi l'ha ricevuto (al massimo quanto ha ancora) ----
  if m.reward_amount > 0 and m.reward_user is not null then
    select balance into v_bal from public.wallets where user_id = m.reward_user for update;
    v_rev := least(m.reward_amount, coalesce(v_bal, 0));
    if v_rev > 0 then
      perform public._ledger_move(m.reward_user, -v_rev, 'admin_adjustment', 'ladder_match', p_id, 'ladder_cancel_rev:' || p_id, 'Annullamento risultato Ladder: premio annullato');
    end if;
  end if;

  -- ---- il match diventa «annullato» (resta nello storico, ma non conta più per nulla) ----
  update public.ladder_matches set status = 'voided', resolved_by = v, resolution_reason = r, corrected_at = clock_timestamp(), corrected_by = v,
    correction_count = correction_count + 1,
    reward_user = null, reward_amount = 0, reward_note = case when m.reward_amount > 0 then 'risultato annullato dall''amministratore: premio tolto' else m.reward_note end,
    official_match_id = null, official_note = case when v_off is not null then 'risultato annullato: match ufficiale rimosso' else m.official_note end,
    elo_challenger_before = null, elo_opponent_before = null, elo_challenger_delta = null, elo_opponent_delta = null
    where id = p_id;
  if v_elo then perform public._ladder_rebuild(m.format); end if;
  perform set_config('app.ladder_correct', 'off', true);

  v_new := jsonb_build_object('status', 'voided', 'reward_taken_back', v_rev, 'official_removed', v_off is not null, 'elo_recalculated', v_elo);
  perform public._audit(v, 'admin_ladder_cancel_closed', 'ladder_match', p_id::text, v_old, v_new, r);

  select nickname into n1 from public.profiles where id = m.challenger_id;
  select nickname into n2 from public.profiles where id = m.opponent_id;
  txt := format('L''amministratore ha annullato il risultato di %s contro %s (%s): è come se non fosse mai stato giocato.%s', n1, n2, m.format,
    case when v_elo then ' Elo e classifica sono stati ricalcolati.' else '' end);
  perform public._notify(m.challenger_id, 'ladder_correction', 'Risultato Ladder annullato', left(txt, 400), 'black-market.html#/ladder', 'ladder_match', gen_random_uuid());
  perform public._notify(m.opponent_id,   'ladder_correction', 'Risultato Ladder annullato', left(txt, 400), 'black-market.html#/ladder', 'ladder_match', gen_random_uuid());

  return v_new;
end $$;

revoke all on function public.admin_ladder_cancel_closed(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_ladder_cancel_closed(uuid, text) to authenticated;

commit;
