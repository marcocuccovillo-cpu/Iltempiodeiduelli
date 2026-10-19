-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 005: ruolo MODERATORE (lo assegna solo l'amministratore) e sezione "Funzioni Mod".
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO 001, 002, 003 e 004.
--
-- Il moderatore è un duellante a tutti gli effetti (profilo, wallet, taglie, Ladder) e in più può, SOLO con motivazione e con audit:
--  1. verificare i match ufficiali in attesa (qualsiasi evento): mod_verify_match;
--  2. decidere o annullare i match della Ladder contestati o fermi: admin_ladder_resolve / admin_ladder_void;
--  3. rimuovere un duellante sospendendone l'account (e riattivarlo): admin_set_suspended. Non può sospendere admin o altri moderatori.
--  Non può: assegnare il ruolo (nemmeno a sé), gestire i moduli, cambiare impostazioni, assegnare o rettificare crediti, premi di partecipazione,
--  creare eventi o match, annullare taglie, chiudere contestazioni generiche, esportare i dati, leggere l'audit e i saldi altrui.
--  Un moderatore non può decidere né verificare un match in cui gioca lui. L'amministratore conserva tutti i poteri.
--  "Rimuovere" = sospendere: lo storico (match, saldi, registro) non si cancella mai.
-- Cambiano: _need_role (il moderatore passa i controlli che ammettono 'user'), admin_set_suspended, admin_ladder_resolve, admin_ladder_void,
--  la regola di lettura dei match Ladder (ora anche per i moderatori). Nuove: is_staff, mod_verify_match.
-- Annullamento: black-market-moderatore-down.sql (la voce 'moderator' resta nell'elenco dei ruoli: PostgreSQL non permette di toglierla).
-- =====================================================================
-- Nuovo valore del ruolo: fuori dalla transazione e senza usarlo qui sotto in modo immediato (tutte le funzioni sono plpgsql: lo leggono solo quando girano).
alter type public.app_role add value if not exists 'moderator';

begin;  -- tutto o niente

create or replace function public.is_staff() returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  return exists (select 1 from public.profiles where id = auth.uid() and role::text in ('admin','moderator') and not suspended);
end $$;

create or replace function public._need_role(p_roles public.app_role[]) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid(); r public.app_role; s boolean;
begin
  if v is null then raise exception 'Accesso richiesto'; end if;
  select role, suspended into r, s from public.profiles where id = v;
  if not found then raise exception 'Profilo non registrato'; end if;
  if s then raise exception 'Account sospeso'; end if;
  -- il moderatore è anche un normale giocatore: passa ogni controllo che ammette il ruolo 'user' (mai quelli solo per organizzatori o admin)
  if not (r = any (p_roles) or (r::text = 'moderator' and 'user'::public.app_role = any (p_roles))) then raise exception 'Permessi insufficienti'; end if;
  return v;
end $$;

create or replace function public.admin_set_suspended(p_user uuid, p_on boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin','moderator']::public.app_role[]); t public.app_role;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  if p_user = v then raise exception 'Non puoi sospendere te stesso'; end if;
  select role into t from public.profiles where id = p_user;
  if found and t::text in ('admin','moderator') and (select role::text from public.profiles where id = v) = 'moderator' then
    raise exception 'Un moderatore non può sospendere amministratori o altri moderatori'; end if;
  update public.profiles set suspended = p_on where id = p_user;
  if not found then raise exception 'Utente inesistente'; end if;
  perform public._audit(v, 'set_suspended', 'profile', p_user::text, null, jsonb_build_object('suspended', p_on), p_reason);
end $$;

create or replace function public.admin_ladder_resolve(p_id uuid, p_result text, p_score text, p_reason text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype; r jsonb;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['admin','moderator']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into m from public.ladder_matches where id = p_id for update;
  if not found then raise exception 'Match non trovato'; end if;
  if v in (m.challenger_id, m.opponent_id) and (select role::text from public.profiles where id = v) = 'moderator' then raise exception 'Non puoi decidere un match in cui giochi tu'; end if;
  if m.status not in ('accepted','reported','disputed') then raise exception 'Il match non è risolvibile in questo stato'; end if;
  if not ((p_result = 'challenger' and p_score in ('2-0','2-1')) or (p_result = 'opponent' and p_score in ('0-2','1-2')) or (p_result = 'draw' and p_score = '1-1'))
    then raise exception 'Esito o punteggio non validi'; end if;
  r := public._ladder_close(p_id, p_result, p_score, null, v, btrim(p_reason));
  perform public._audit(v, 'admin_ladder_resolve', 'ladder_match', p_id::text, jsonb_build_object('status', m.status), r || jsonb_build_object('result', p_result, 'score', p_score), btrim(p_reason));
  return r;
end $$;

create or replace function public.admin_ladder_void(p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['admin','moderator']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into m from public.ladder_matches where id = p_id for update;
  if not found then raise exception 'Match non trovato'; end if;
  if v in (m.challenger_id, m.opponent_id) and (select role::text from public.profiles where id = v) = 'moderator' then raise exception 'Non puoi decidere un match in cui giochi tu'; end if;
  if m.status not in ('pending','accepted','reported','disputed') then raise exception 'Il match è già concluso'; end if;
  update public.ladder_matches set status = 'voided', resolved_by = v, resolution_reason = btrim(p_reason), closed_at = clock_timestamp() where id = p_id;
  perform public._audit(v, 'admin_ladder_void', 'ladder_match', p_id::text, jsonb_build_object('status', m.status), null, btrim(p_reason));
end $$;

-- Verifica di un match ufficiale in attesa (stessa regola di verify_match della 001, ma valida per qualsiasi evento)
create or replace function public.mod_verify_match(p_match uuid, p_winner uuid) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin','moderator']::public.app_role[]); m public.matches%rowtype;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'Match inesistente'; end if;
  if m.status = 'verified' then raise exception 'Match già verificato'; end if;
  if v in (m.player_a, m.player_b) and (select role::text from public.profiles where id = v) = 'moderator' then raise exception 'Non puoi verificare un match in cui giochi tu'; end if;
  if p_winner is null or p_winner not in (m.player_a, m.player_b) then raise exception 'Il vincitore deve essere uno dei due giocatori'; end if;
  update public.matches set winner_id = p_winner, status = 'verified', verified_by = v, verified_at = clock_timestamp() where id = p_match;
  perform public._audit(v, 'mod_verify_match', 'match', p_match::text, to_jsonb(m), jsonb_build_object('winner', p_winner), null);
end $$;

-- I moderatori vedono tutti i match Ladder (anche quelli in corso e contestati), come l'amministratore
drop policy if exists ladder_matches_read on public.ladder_matches;
create policy ladder_matches_read on public.ladder_matches for select to authenticated
  using (public.is_staff() or (public._module_on('ladder') and (status = 'closed' or challenger_id = auth.uid() or opponent_id = auth.uid())));

-- Permessi
revoke all on function public.is_staff(), public.mod_verify_match(uuid, uuid) from public, anon, authenticated;
grant execute on function public.is_staff(), public.mod_verify_match(uuid, uuid) to authenticated;
commit;
