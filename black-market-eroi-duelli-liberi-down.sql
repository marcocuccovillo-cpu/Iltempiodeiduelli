-- ANNULLAMENTO DELLA MIGRAZIONE 016 (duelli liberi): rimette «una sola sfida al giorno per avversario».
-- Prima riesegui black-market-eroi-v2.sql (015): rimette la funzione game_duel con la regola. Poi questo file, che rimette il vincolo
-- sul database solo se non ci sono già duelli ripetuti nello stesso giorno (quelli già fatti non si toccano e restano nella cronologia).
-- L'elenco dell'Arena può restare com'è (il campo in più non dà fastidio).
begin;
do $$
begin
  if exists (select 1 from public.game_duels group by day, attacker_id, defender_id having count(*) > 1) then
    raise notice 'Ci sono duelli ripetuti già registrati: il vincolo di unicità non viene rimesso (la regola resta comunque attiva nella funzione, dopo la 015).';
  elsif not exists (select 1 from pg_constraint where conrelid = 'public.game_duels'::regclass and contype = 'u') then
    alter table public.game_duels add constraint game_duels_day_attacker_id_defender_id_key unique (day, attacker_id, defender_id);
  end if;
end $$;
commit;
