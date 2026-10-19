-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 006: i moderatori gestiscono anche le taglie.
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO 001–005.
--
-- Il moderatore può, con motivazione e audit:
--  * mettere una taglia IN REVISIONE e toglierla dalla revisione (admin_set_bounty_review): la riscossione sul bersaglio resta sospesa;
--  * ANNULLARE una taglia (admin_cancel_bounty): la quota torna al creatore, che riceve indietro soltanto i BC che aveva versato (nessun credito nuovo).
--  * vedere tutte le taglie (prima solo il creatore e l'admin le leggevano).
--  Non può gestire una taglia in cui è lui il creatore o il bersaglio. Per tutto il resto valgono i limiti della 005.
-- Cambiano: admin_set_bounty_review, admin_cancel_bounty (stessa logica della 001, più ruolo e un controllo), regola di lettura delle taglie.
-- Annullamento: black-market-moderatore-taglie-down.sql.
-- =====================================================================
begin;
create or replace function public.admin_set_bounty_review(p_bounty uuid, p_on boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin','moderator']::public.app_role[]); b public.bounties%rowtype;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into b from public.bounties where id = p_bounty for update;
  if not found then raise exception 'Taglia inesistente'; end if;
  if (select role::text from public.profiles where id = v) = 'moderator' and v in (b.creator_id, b.target_id) then raise exception 'Non puoi gestire una taglia che ti riguarda'; end if;
  if b.status not in ('active','under_review') then raise exception 'La taglia è già chiusa'; end if;
  update public.bounties set status = case when p_on then 'under_review'::public.bounty_status else 'active'::public.bounty_status end where id = p_bounty;
  perform public._audit(v, 'bounty_review', 'bounty', p_bounty::text, jsonb_build_object('status', b.status), jsonb_build_object('under_review', p_on), p_reason);
end $$;

create or replace function public.admin_cancel_bounty(p_bounty uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin','moderator']::public.app_role[]); b public.bounties%rowtype;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into b from public.bounties where id = p_bounty for update;
  if not found then raise exception 'Taglia inesistente'; end if;
  if (select role::text from public.profiles where id = v) = 'moderator' and v in (b.creator_id, b.target_id) then raise exception 'Non puoi gestire una taglia che ti riguarda'; end if;
  if b.status not in ('active','under_review') then raise exception 'La taglia è già chiusa'; end if;
  update public.bounties set status = 'cancelled', settled_at = clock_timestamp() where id = p_bounty;
  perform public._ledger_move(b.creator_id, b.amount, 'bounty_refund', 'bounty', p_bounty, 'cancel:' || p_bounty, 'Taglia annullata dall''amministrazione');
  perform public._audit(v, 'cancel_bounty', 'bounty', p_bounty::text, to_jsonb(b), jsonb_build_object('status', 'cancelled'), p_reason);
end $$;

drop policy if exists bounties_read on public.bounties;
create policy bounties_read on public.bounties for select to authenticated using (creator_id = auth.uid() or public.is_staff());
commit;
