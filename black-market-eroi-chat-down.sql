-- =====================================================================
-- ANNULLA «LA GUERRA DEGLI EROI — CHAT PUBBLICA E CHI È ONLINE»
-- Toglie funzioni e tabelle della chat e della presenza (i messaggi vanno persi). Il resto del gioco non viene toccato:
-- eroi, BC, oggetti, boss, dungeon e classifica restano come sono. Le voci dell'audit «game_chat_hide» restano nel registro.
-- =====================================================================
begin;
drop function if exists public.game_chat_hide(bigint, text);
drop function if exists public.game_online();
drop function if exists public.game_presence_ping();
drop function if exists public.game_chat_list(bigint);
drop function if exists public.game_chat_send(text);
drop table if exists public.game_presence;
drop table if exists public.game_chat;
commit;
