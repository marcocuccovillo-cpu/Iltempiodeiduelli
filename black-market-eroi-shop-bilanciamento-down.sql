-- =====================================================================
-- ANNULLAMENTO DELLA MIGRAZIONE 038 (bilanciamento equipaggiamento dello shop)
-- Rimette le statistiche originali salvate in game_items_bal_backup e toglie la tabella di backup.
-- =====================================================================
begin;
update public.game_items g set p_for = b.p_for, p_des = b.p_des, p_vig = b.p_vig, p_spi = b.p_spi, p_frt = b.p_frt
  from public.game_items_bal_backup b where b.id = g.id;
drop table if exists public.game_items_bal_backup;
commit;
