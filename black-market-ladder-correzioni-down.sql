-- ANNULLAMENTO DELLA MIGRAZIONE 018 (correzione dei risultati Ladder).
-- Toglie le funzioni di correzione e rimette il guardiano dei match chiusi com'era (nessuna eccezione).
-- Non cancella nulla: i match già corretti restano come sono (con il risultato corretto, Elo e premi già ricalcolati),
-- le colonne corrected_at / corrected_by / correction_count e le notifiche restano come storico, e il tipo di notifica
-- «ladder_correction» resta ammesso (nessuno ne creerà più); la funzione di notifica resta quella con il tipo in più (non cambia nulla per gli altri tipi).
-- Per rimettere la correzione basta rieseguire black-market-ladder-correzioni.sql.
begin;

drop function if exists public.admin_ladder_correct(uuid, text, text, text);
drop function if exists public._ladder_rebuild(text);

create or replace function public._ladder_guard() returns trigger language plpgsql as $$
begin
  if old.status in ('closed','declined','cancelled','expired','voided') then
    raise exception 'Match della Ladder già concluso: non è più modificabile'; end if;
  return new;
end $$;

commit;
