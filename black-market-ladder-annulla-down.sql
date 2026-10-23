-- ANNULLAMENTO DELLA MIGRAZIONE 022 (annullamento dei risultati Ladder già conclusi).
-- Toglie la funzione e rimette il guardiano della 018 (solo correzioni closed → closed). I match già annullati restano annullati
-- (Elo, premi e match ufficiali non si ripristinano: sono già stati ricalcolati e registrati nell'audit).
begin;
drop function if exists public.admin_ladder_cancel_closed(uuid, text);
create or replace function public._ladder_guard() returns trigger language plpgsql as $$
begin
  if old.status in ('closed','declined','cancelled','expired','voided') then
    if old.status = 'closed' and new.status = 'closed' and coalesce(current_setting('app.ladder_correct', true), '') = 'on' then return new; end if;
    raise exception 'Match della Ladder già concluso: non è più modificabile';
  end if;
  return new;
end $$;
commit;
