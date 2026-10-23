-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 018: correzione dei risultati Ladder già conclusi (solo amministratori).
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO le migrazioni 001…017.
--
-- Prima di questa migrazione un match chiuso non si poteva più toccare: l'amministratore poteva solo decidere i match contestati o fermi.
-- Ora l'amministratore può correggere esito e punteggio di un match già concluso con admin_ladder_correct(match, esito, punteggio, motivazione).
-- Cosa succede, tutto in un'unica operazione (o tutto o niente):
--  1. ELO: la classifica del formato viene ricalcolata rigiocando in ordine tutti i match chiusi con l'esito aggiornato
--     (una correzione vecchia cambia anche le variazioni dei match successivi dei due giocatori, perché l'Elo dipende dall'ordine).
--     Le variazioni mostrate in ogni match vengono aggiornate di conseguenza.
--  2. PREMIO IN BC: se il vincitore cambia e il premio era stato dato, viene tolto al vecchio vincitore (si recupera al massimo quanto ha
--     ancora nel wallet) e dato al nuovo; se il match diventa un pareggio il premio viene solo tolto; se un pareggio diventa una vittoria
--     il premio viene dato (senza applicare i limiti giornalieri). Ogni movimento è nel registro, di tipo «admin_adjustment». Se cambia solo il
--     punteggio (stesso vincitore) i BC non si toccano.
--  3. MATCH WPA UFFICIALE: se il vincitore cambia, il match ufficiale passa al nuovo vincitore; se diventa un pareggio viene rimosso;
--     se un pareggio diventa una vittoria ne viene creato uno nuovo. Se sul match era GIÀ stata riscossa una taglia (o il match è collegato a
--     una sfida, a una contestazione o a un'esclusione dalle fazioni) il vincitore non si può cambiare: la correzione viene rifiutata.
--  4. I due giocatori ricevono una notifica; il match mostra «corretto dall'amministratore»; tutto finisce nell'audit con prima e dopo.
--  Solo gli amministratori (non i moderatori). Motivazione obbligatoria. Non si cambia il tipo di sfida né i giocatori.
--  Le funzioni di sempre (conferma, contestazione, risoluzione, annullamento) non cambiano. Il guardiano dei match chiusi resta, con una
--  sola eccezione: la funzione di correzione.
-- Reversibile con black-market-ladder-correzioni-down.sql.
-- =====================================================================
begin;

alter table public.ladder_matches
  add column corrected_at timestamptz,
  add column corrected_by uuid references public.profiles(id),
  add column correction_count integer not null default 0 check (correction_count >= 0);

-- nuovo tipo di notifica
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('bounty_received','ladder_challenge','bounty_challenge','test','ladder_accepted','ladder_declined','ladder_correction'));

-- _notify identica a quella della 011, con un tipo in più: la correzione segue la preferenza «sfide in Ladder»
create or replace function public._notify(p_user uuid, p_kind text, p_title text, p_body text, p_url text, p_ref_type text, p_ref uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
begin
  if coalesce(public._setting('notifications_enabled'), 1) <> 1 then return; end if;
  select case when p_kind = 'bounty_received' then coalesce(bounty, true)
              when p_kind in ('ladder_challenge','ladder_accepted','ladder_declined','ladder_correction') then coalesce(ladder, true)
              else coalesce(hunt, true) end
    into v_ok from public.notification_prefs where user_id = p_user;
  if not found then v_ok := true; end if;                                              -- nessuna preferenza salvata = tutto acceso
  if not v_ok then return; end if;
  insert into public.notifications (user_id, kind, title, body, url, ref_type, ref_id) values (p_user, p_kind, p_title, p_body, p_url, p_ref_type, p_ref)
    on conflict (user_id, kind, ref_id) do nothing;
end $$;

-- guardiano: un match concluso non si modifica, salvo la correzione (che resta 'closed' e lo dichiara con un'impostazione di sessione)
create or replace function public._ladder_guard() returns trigger language plpgsql as $$
begin
  if old.status in ('closed','declined','cancelled','expired','voided') then
    if old.status = 'closed' and new.status = 'closed' and coalesce(current_setting('app.ladder_correct', true), '') = 'on' then return new; end if;
    raise exception 'Match della Ladder già concluso: non è più modificabile';
  end if;
  return new;
end $$;

-- ---------- Ricalcolo dell'Elo di un formato: si rigiocano in ordine tutti i match chiusi che contano per l'Elo ----------
create function public._ladder_rebuild(p_format text) returns void language plpgsql security definer set search_path = public as $$
declare m record; ea integer; eo integer; da integer; s numeric;
        st integer := coalesce(public._setting('ladder_start_elo'), 1000); k integer := coalesce(public._setting('ladder_k'), 32);
        prev text := coalesce(current_setting('app.ladder_correct', true), '');
begin
  if p_format not in ('Advanced','Edison') then return; end if;
  perform set_config('app.ladder_correct', 'on', true);          -- aggiorna le variazioni mostrate nei match chiusi (il guardiano lo consente solo qui)
  perform 1 from public.ladder_ratings where format = p_format order by user_id for update;
  update public.ladder_ratings set elo = st, wins = 0, draws = 0, losses = 0, last_match_at = null where format = p_format;
  for m in select * from public.ladder_matches where status = 'closed' and format = p_format and kind in ('ladder','both') order by closed_at, id loop
    insert into public.ladder_ratings (user_id, format, elo) values (m.challenger_id, p_format, st), (m.opponent_id, p_format, st) on conflict do nothing;
    select elo into ea from public.ladder_ratings where user_id = m.challenger_id and format = p_format;
    select elo into eo from public.ladder_ratings where user_id = m.opponent_id and format = p_format;
    s := case m.reported_result when 'challenger' then 1.0 when 'opponent' then 0.0 else 0.5 end;
    da := round(k * (s - 1.0 / (1.0 + power(10.0, (eo - ea) / 400.0))))::integer;
    update public.ladder_ratings set elo = greatest(0, elo + da), last_match_at = m.closed_at,
      wins = wins + (m.reported_result = 'challenger')::integer, draws = draws + (m.reported_result = 'draw')::integer, losses = losses + (m.reported_result = 'opponent')::integer
      where user_id = m.challenger_id and format = p_format;
    update public.ladder_ratings set elo = greatest(0, elo - da), last_match_at = m.closed_at,
      wins = wins + (m.reported_result = 'opponent')::integer, draws = draws + (m.reported_result = 'draw')::integer, losses = losses + (m.reported_result = 'challenger')::integer
      where user_id = m.opponent_id and format = p_format;
    update public.ladder_matches set elo_challenger_before = ea, elo_opponent_before = eo, elo_challenger_delta = da, elo_opponent_delta = -da where id = m.id;
  end loop;
  perform set_config('app.ladder_correct', prev, true);
end $$;

-- ---------- La correzione ----------
create function public.admin_ladder_correct(p_id uuid, p_result text, p_score text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v uuid; r text := btrim(coalesce(p_reason, '')); m public.ladder_matches%rowtype; om public.matches%rowtype;
        old_w uuid; new_w uuid; v_amt integer := coalesce(public._setting('ladder_reward_bc'), 0);
        v_bal integer; v_rev integer := 0; v_given integer := 0; v_ruser uuid; v_ramt integer; v_rnote text;
        v_off uuid; v_onote text; v_event uuid; v_round integer; v_nth integer; v_bty boolean; v_elo boolean;
        rr record; v_old jsonb; v_new jsonb; n1 text; n2 text; txt text; fin public.ladder_matches%rowtype;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['admin']::public.app_role[]);
  if char_length(r) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into m from public.ladder_matches where id = p_id for update;
  if not found then raise exception 'Match non trovato'; end if;
  if m.status <> 'closed' then raise exception 'Si correggono solo i match già conclusi (gli altri si risolvono o si annullano)'; end if;
  if not ((p_result = 'challenger' and p_score in ('2-0','2-1')) or (p_result = 'opponent' and p_score in ('0-2','1-2')) or (p_result = 'draw' and p_score = '1-1'))
    then raise exception 'Esito o punteggio non validi'; end if;
  if p_result = m.reported_result and p_score = m.reported_score then raise exception 'Nessuna modifica: il risultato è già questo'; end if;
  old_w := case m.reported_result when 'challenger' then m.challenger_id when 'opponent' then m.opponent_id end;
  new_w := case p_result when 'challenger' then m.challenger_id when 'opponent' then m.opponent_id end;
  v_elo := m.kind in ('ladder','both'); v_bty := m.kind in ('bounty','both');
  v_ruser := m.reward_user; v_ramt := m.reward_amount; v_rnote := m.reward_note; v_off := m.official_match_id; v_onote := m.official_note;
  v_nth := m.correction_count + 1;
  v_old := jsonb_build_object('result', m.reported_result, 'score', m.reported_score, 'challenger_delta', m.elo_challenger_delta, 'opponent_delta', m.elo_opponent_delta,
                              'reward_user', m.reward_user, 'reward_amount', m.reward_amount, 'official_match', m.official_match_id);

  perform set_config('app.ladder_correct', 'on', true);          -- vale solo dentro questa transazione, per il guardiano dei match chiusi

  if new_w is distinct from old_w then
    -- ---- match ufficiale WPA ----
    if v_off is not null then
      select * into om from public.matches where id = v_off for update;
      if exists (select 1 from public.bounty_settlements where match_id = v_off) then
        raise exception 'Su questo match è già stata riscossa una taglia: il vincitore non si può cambiare'; end if;
      if new_w is null then
        if exists (select 1 from public.faction_match_exclusions where match_id = v_off) or exists (select 1 from public.challenges where match_id = v_off)
           or exists (select 1 from public.disputes where match_id = v_off) then
          raise exception 'Il match ufficiale collegato è usato altrove (sfida, contestazione o esclusione): il match non può diventare un pareggio'; end if;
        update public.ladder_matches set official_match_id = null where id = p_id;
        delete from public.matches where id = v_off;
        for rr in select id from public.matches where event_id = om.event_id and round > om.round                       -- i turni restano 1,2,3… senza buchi (la chiusura dei match li numera contando)
                     and least(player_a, player_b) = least(om.player_a, om.player_b) and greatest(player_a, player_b) = greatest(om.player_a, om.player_b) order by round loop
          update public.matches set round = round - 1 where id = rr.id;
        end loop;
        v_off := null; v_onote := 'corretto in pareggio: match ufficiale rimosso';
      else
        update public.matches set winner_id = new_w where id = v_off;
      end if;
    elsif old_w is null and new_w is not null then                 -- da pareggio a vittoria: nasce il match ufficiale
      if coalesce(public._setting('ladder_wpa_matches'), 0) <> 1 then
        v_onote := 'match ufficiali Ladder spenti';
      else
        v_event := public._ladder_event((m.closed_at at time zone 'Europe/Rome')::date);
        if v_event is null then
          v_onote := 'nessun amministratore attivo';
        else
          select count(*) + 1 into v_round from public.matches mm
            where mm.event_id = v_event and least(mm.player_a, mm.player_b) = least(m.challenger_id, m.opponent_id)
              and greatest(mm.player_a, mm.player_b) = greatest(m.challenger_id, m.opponent_id);
          v_off := gen_random_uuid();
          insert into public.matches (id, event_id, round, player_a, player_b, winner_id, status, verified_by, verified_at, created_by, source, ladder_match_id, bounty_eligible)
          values (v_off, v_event, v_round, m.challenger_id, m.opponent_id, new_w, 'verified', v, clock_timestamp(), v, 'ladder', p_id, v_bty);
          v_onote := null;
        end if;
      end if;
    end if;

    -- ---- premio in BC ----
    if v_elo then
      if m.reward_amount > 0 then                                    -- il premio c'era: segue il vincitore
        select balance into v_bal from public.wallets where user_id = m.reward_user for update;
        v_rev := least(m.reward_amount, coalesce(v_bal, 0));
        if v_rev > 0 then
          perform public._ledger_move(m.reward_user, -v_rev, 'admin_adjustment', 'ladder_match', p_id, 'ladder_corr_rev:' || p_id || ':' || v_nth,
            'Correzione risultato Ladder: premio annullato');
        end if;
        if new_w is null then
          v_ruser := null; v_ramt := 0; v_rnote := 'risultato corretto in pareggio: premio annullato';
        else
          perform public._ledger_move(new_w, m.reward_amount, 'admin_adjustment', 'ladder_match', p_id, 'ladder_corr_add:' || p_id || ':' || v_nth,
            'Correzione risultato Ladder: premio al vincitore corretto');
          v_ruser := new_w; v_given := m.reward_amount; v_rnote := null;
        end if;
      elsif old_w is null and new_w is not null and v_amt > 0 and coalesce(public._setting('ladder_reward_enabled'), 0) = 1 then   -- da pareggio a vittoria
        perform public._ledger_move(new_w, v_amt, 'admin_adjustment', 'ladder_match', p_id, 'ladder_corr_add:' || p_id || ':' || v_nth,
          'Correzione risultato Ladder: premio per la vittoria');
        v_ruser := new_w; v_ramt := v_amt; v_given := v_amt; v_rnote := null;
      end if;
    end if;
  end if;

  update public.ladder_matches set reported_result = p_result, reported_score = p_score,
    corrected_at = clock_timestamp(), corrected_by = v, correction_count = v_nth,
    reward_user = v_ruser, reward_amount = v_ramt, reward_note = v_rnote, official_match_id = v_off, official_note = v_onote
    where id = p_id;
  if v_elo then perform public._ladder_rebuild(m.format); end if;
  perform set_config('app.ladder_correct', 'off', true);

  select * into fin from public.ladder_matches where id = p_id;
  v_new := jsonb_build_object('result', p_result, 'score', p_score, 'challenger_delta', fin.elo_challenger_delta, 'opponent_delta', fin.elo_opponent_delta,
                              'reward_user', fin.reward_user, 'reward_amount', fin.reward_amount, 'official_match', fin.official_match_id,
                              'reward_taken_back', v_rev, 'reward_given', v_given);
  perform public._audit(v, 'admin_ladder_correct', 'ladder_match', p_id::text, v_old, v_new, r);

  select nickname into n1 from public.profiles where id = m.challenger_id;
  select nickname into n2 from public.profiles where id = m.opponent_id;
  txt := format('L''amministratore ha corretto il risultato di %s contro %s (%s): ora risulta %s.%s', n1, n2, m.format,
    case p_result when 'draw' then 'un pareggio' else 'la vittoria di ' || case p_result when 'challenger' then n1 else n2 end || ' ' ||
      case when p_result = 'challenger' then p_score else reverse(p_score) end end,
    case when v_elo then ' Elo e classifica sono stati ricalcolati.' else '' end);
  perform public._notify(m.challenger_id, 'ladder_correction', 'Risultato Ladder corretto', left(txt, 400), 'black-market.html#/ladder', 'ladder_match', gen_random_uuid());
  perform public._notify(m.opponent_id,   'ladder_correction', 'Risultato Ladder corretto', left(txt, 400), 'black-market.html#/ladder', 'ladder_match', gen_random_uuid());

  return v_new || jsonb_build_object('old_result', m.reported_result, 'old_score', m.reported_score, 'official_note', fin.official_note, 'reward_note', fin.reward_note,
                                      'elo_recalculated', v_elo);
end $$;

revoke all on function public._ladder_rebuild(text), public.admin_ladder_correct(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.admin_ladder_correct(uuid, text, text, text) to authenticated;

commit;
