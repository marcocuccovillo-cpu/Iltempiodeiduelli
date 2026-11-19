-- =====================================================================================
--  La guerra degli Eroi — Torre Infinita: difficoltà un po' più bassa (migrazione 051)
--  La 049 era troppo dura. Cambia solo i valori delle impostazioni della Torre (nessuna funzione, nessun dato):
--                               prima (049)   adesso
--    game_tower_ramp_floors         150         250    la forza dei nemici raddoppia ogni 250 piani invece di 150
--    game_tower_growth_bp            10           6    crescita composta +0,06% a piano invece di +0,10%
--    game_tower_growth_from         100         200    e parte dal piano 200 invece del 100
--    game_tower_boss_pct            140         125    boss ×1,25 invece di ×1,40
--    game_tower_miasma_max           75          50    il Miasma toglie al massimo il 50% delle cure (dal piano 500)
--  Pressione dei nemici: ×1,4 al piano 100 (era 1,6), ×3,5 al 500 (era 6,4), ×8,6 al 1050 (era 20,5), ×15 al 1500 (era 44).
--  La caduta di un piano a ogni sconfitta (050) resta com'è. Tutto si può ritoccare da Admin › Impostazioni.
--  Da eseguire DOPO la 049 e la 050. Si può rieseguire. Annulla con black-market-eroi-torre-facile-down.sql
-- =====================================================================================
begin;
update public.system_settings s set value_int = v.val from (values
  ('game_tower_ramp_floors', 250), ('game_tower_growth_bp', 6), ('game_tower_growth_from', 200), ('game_tower_boss_pct', 125), ('game_tower_miasma_max', 50)
) v(key, val) where s.key = v.key;
do $$ begin
  if (select count(*) from public.system_settings where key in ('game_tower_ramp_floors','game_tower_growth_bp','game_tower_growth_from','game_tower_boss_pct','game_tower_miasma_max')) <> 5 then
    raise exception 'Prima esegui la migrazione 049 (black-market-eroi-torre-hard.sql): le impostazioni della Torre difficile non ci sono.';
  end if;
end $$;
commit;
