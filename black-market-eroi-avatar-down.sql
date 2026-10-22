-- ANNULLAMENTO DELLA MIGRAZIONE 014 (avatar degli eroi). Toglie la funzione e le due colonne: gli avatar scelti vanno persi,
-- tutto il resto del gioco (eroi, livelli, oggetti, BC) resta com'è.
begin;
drop function if exists public.game_set_avatar(integer, text);
alter table public.game_heroes drop constraint if exists game_heroes_avatar_chk;
alter table public.game_heroes drop column if exists avatar_card;
alter table public.game_heroes drop column if exists avatar_name;
commit;
