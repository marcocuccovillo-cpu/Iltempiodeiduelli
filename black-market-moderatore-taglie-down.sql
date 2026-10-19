-- =====================================================================
-- ANNULLAMENTO della migrazione 006 (black-market-moderatore-taglie.sql): le taglie tornano di sola competenza dell'amministratore.
-- Non cancella nulla: revisioni e annullamenti già fatti dai moderatori restano nello storico e nell'audit.
-- =====================================================================
begin;
create or replace function public.admin_set_bounty_review(p_bounty uuid, p_on boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); b public.bounties%rowtype;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into b from public.bounties where id = p_bounty for update;
  if not found then raise exception 'Taglia inesistente'; end if;
  if b.status not in ('active','under_review') then raise exception 'La taglia è già chiusa'; end if;
  update public.bounties set status = case when p_on then 'under_review'::public.bounty_status else 'active'::public.bounty_status end where id = p_bounty;
  perform public._audit(v, 'bounty_review', 'bounty', p_bounty::text, jsonb_build_object('status', b.status), jsonb_build_object('under_review', p_on), p_reason);
end $$;

create or replace function public.admin_cancel_bounty(p_bounty uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); b public.bounties%rowtype;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into b from public.bounties where id = p_bounty for update;
  if not found then raise exception 'Taglia inesistente'; end if;
  if b.status not in ('active','under_review') then raise exception 'La taglia è già chiusa'; end if;
  update public.bounties set status = 'cancelled', settled_at = clock_timestamp() where id = p_bounty;
  perform public._ledger_move(b.creator_id, b.amount, 'bounty_refund', 'bounty', p_bounty, 'cancel:' || p_bounty, 'Taglia annullata dall''amministrazione');
  perform public._audit(v, 'cancel_bounty', 'bounty', p_bounty::text, to_jsonb(b), jsonb_build_object('status', 'cancelled'), p_reason);
end $$;

drop policy if exists bounties_read on public.bounties;
create policy bounties_read on public.bounties for select to authenticated using (creator_id = auth.uid() or public.is_admin());
commit;
