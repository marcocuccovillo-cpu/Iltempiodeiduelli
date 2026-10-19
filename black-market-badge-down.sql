-- =====================================================================
-- ANNULLAMENTO della migrazione 007 (black-market-badge.sql).
-- Cosa fa: toglie la funzione badge_progress e il catalogo badge_defs.
-- Cosa NON perde: nulla. I badge non sono memorizzati (si calcolano dai match, dalle taglie e dalla Ladder),
-- quindi tutti i dati ufficiali, i saldi e il registro restano esattamente come sono.
-- Dopo l'annullamento l'app mostra il Sentiero e i profili senza la sezione badge.
-- Ordine inverso delle migrazioni: puoi eseguirlo senza toccare le 001…006.
-- =====================================================================
begin;
drop function if exists public.badge_progress(uuid);
drop table if exists public.badge_defs;
commit;
