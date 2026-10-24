-- Annulla black-market-badge-extra.sql: toglie il catalogo e la funzione dei nuovi badge.
-- Non perde nulla (i badge sono derivati dai dati ufficiali, nessuno è memorizzato): il Sentiero e i profili tornano a mostrare solo i badge di prima.
begin;
drop function if exists public.badge_progress_extra(uuid);
drop table if exists public.badge_extra_defs;
commit;
