-- Annulla la migrazione 051: rimette i valori della Torre difficile della 049.
begin;
update public.system_settings s set value_int = v.val from (values
  ('game_tower_ramp_floors', 150), ('game_tower_growth_bp', 10), ('game_tower_growth_from', 100), ('game_tower_boss_pct', 140), ('game_tower_miasma_max', 75)
) v(key, val) where s.key = v.key;
commit;
