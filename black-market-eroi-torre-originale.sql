-- =====================================================================================
--  La guerra degli Eroi — Torre Infinita: difficoltà ORIGINALE + 10% (migrazione 053)
--  Toglie i rinforzi della Torre difficile (049/051/052) e rimette i nemici come nella Torre originale (029),
--  con tutte le statistiche dei nemici +10%. Cambia solo impostazioni (nessuna funzione, nessun dato):
--    game_tower_ramp_floors   0     crescita lineare in più spenta
--    game_tower_growth_bp     0     crescita composta spenta
--    game_tower_boss_pct      115   boss ×1,15 come all'origine
--    game_tower_miasma_max    0     Miasma spento: le cure tornano piene
--    game_tower_difficulty    110   nemici +10% rispetto all'originale
--  Restano come sono: la caduta di un piano a ogni sconfitta (050), il premio ridotto alla riconquista (052, 25%)
--  e l'XP dei piani al 75% (052). Si ritocca tutto da Admin › Impostazioni.
--  Da eseguire DOPO la 052. Si può rieseguire. Annulla con black-market-eroi-torre-originale-down.sql (rimette i valori della 052).
-- =====================================================================================
begin;
do $$ begin
  if (select count(*) from public.system_settings where key in ('game_tower_ramp_floors','game_tower_growth_bp','game_tower_boss_pct','game_tower_miasma_max','game_tower_difficulty')) <> 5 then
    raise exception 'Prima esegui le migrazioni 049–052 della Torre: le impostazioni non ci sono.';
  end if;
end $$;
update public.system_settings s set value_int = v.val from (values
  ('game_tower_ramp_floors', 0), ('game_tower_growth_bp', 0), ('game_tower_boss_pct', 115), ('game_tower_miasma_max', 0), ('game_tower_difficulty', 110)
) v(key, val) where s.key = v.key;
commit;
