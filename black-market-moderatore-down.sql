-- =====================================================================
-- ANNULLAMENTO della migrazione 005 (black-market-moderatore.sql).
-- I moderatori tornano duellanti normali (con una riga di audit per ciascuno); funzioni e regole tornano a quelle di 001/003.
-- NON cancella nulla dello storico. Il valore 'moderator' resta nell'elenco dei ruoli (PostgreSQL non permette di rimuoverlo): è inerte.
-- Indipendente dall'annullamento della 004: l'ordine tra i due non conta.
-- =====================================================================
begin;
insert into public.audit_logs (actor_id, action, entity, entity_id, old_value, new_value, reason)
  select null, 'set_role', 'profile', id::text, jsonb_build_object('role', 'moderator'), jsonb_build_object('role', 'user'), 'annullamento migrazione 005' from public.profiles where role::text = 'moderator';
update public.profiles set role = 'user' where role::text = 'moderator';
drop policy if exists ladder_matches_read on public.ladder_matches;
create policy ladder_matches_read on public.ladder_matches for select to authenticated
  using (public.is_admin() or (public._module_on('ladder') and (status = 'closed' or challenger_id = auth.uid() or opponent_id = auth.uid())));
create or replace function public._need_role(p_roles public.app_role[]) returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid(); r public.app_role; s boolean;
begin
  if v is null then raise exception 'Accesso richiesto'; end if;
  select role, suspended into r, s from public.profiles where id = v;
  if not found then raise exception 'Profilo non registrato'; end if;
  if s then raise exception 'Account sospeso'; end if;
  if not (r = any (p_roles)) then raise exception 'Permessi insufficienti'; end if;
  return v;
end $$;

create or replace function public.admin_set_suspended(p_user uuid, p_on boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]);
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  if p_user = v then raise exception 'Non puoi sospendere te stesso'; end if;
  update public.profiles set suspended = p_on where id = p_user;
  if not found then raise exception 'Utente inesistente'; end if;
  perform public._audit(v, 'set_suspended', 'profile', p_user::text, null, jsonb_build_object('suspended', p_on), p_reason);
end $$;

create or replace function public.admin_ladder_resolve(p_id uuid, p_result text, p_score text, p_reason text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid; m public.ladder_matches%rowtype; r jsonb;
begin
  perform public._require_module('ladder');
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into m from public.ladder_matches where id = p_id for update;
  if not found then raise exception 'Match non trovato'; end if;
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
  v := public._need_role(array['admin']::public.app_role[]);
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into m from public.ladder_matches where id = p_id for update;
  if not found then raise exception 'Match non trovato'; end if;
  if m.status not in ('pending','accepted','reported','disputed') then raise exception 'Il match è già concluso'; end if;
  update public.ladder_matches set status = 'voided', resolved_by = v, resolution_reason = btrim(p_reason), closed_at = clock_timestamp() where id = p_id;
  perform public._audit(v, 'admin_ladder_void', 'ladder_match', p_id::text, jsonb_build_object('status', m.status), null, btrim(p_reason));
end $$;
drop function if exists public.mod_verify_match(uuid, uuid);
drop function if exists public.is_staff();
commit;
