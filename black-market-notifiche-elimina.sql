-- =====================================================================
-- MIGRAZIONE 010 — CANCELLARE LE NOTIFICHE GIÀ LETTE
-- Da eseguire in Supabase (SQL Editor) DOPO la 009 (black-market-notifiche.sql). Si può rieseguire senza danni.
--
-- Aggiunge una sola funzione, notif_delete(p_id):
--   * cancella SOLO notifiche del chiamante e SOLO se già lette (le non lette non si possono cancellare: non si perde
--     un avviso mai visto);
--   * con un id cancella quella notifica, senza id cancella tutte le sue notifiche lette;
--   * il browser continua a non poter scrivere né cancellare direttamente nella tabella: passa solo da questa funzione.
-- Non tocca BC, wallet, registro, taglie, sfide, Shop. Le notifiche sono avvisi di servizio, non storico contabile:
-- le righe di economia (taglie, riscossioni, movimenti) non vengono mai toccate.
-- Una notifica cancellata non si ricrea da sola: ogni evento ne genera una una volta sola.
-- =====================================================================
begin;
create or replace function public.notif_delete(p_id uuid default null) returns integer language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]); n integer;
begin
  if p_id is not null and exists (select 1 from public.notifications where id = p_id and user_id = v and read_at is null) then
    raise exception 'Puoi cancellare solo le notifiche già lette';
  end if;
  delete from public.notifications where user_id = v and read_at is not null and (p_id is null or id = p_id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.notif_delete(uuid) from public, anon, authenticated;
grant execute on function public.notif_delete(uuid) to authenticated;
commit;
