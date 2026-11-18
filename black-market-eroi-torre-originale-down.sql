-- Annulla la migrazione 053: rimette i valori della Torre dopo la 052.
begin;
update public.system_settings s set value_int = v.val from (values
  ('game_tower_ramp_floors', 250), ('game_tower_growth_bp', 6), ('game_tower_boss_pct', 125), ('game_tower_miasma_max', 50), ('game_tower_difficulty', 85)
) v(key, val) where s.key = v.key;
commit;
