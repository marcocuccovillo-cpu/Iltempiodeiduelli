-- ANNULLAMENTO DELLA MIGRAZIONE 044 (aspetto dell'eroe). Gli eroi tornano tutti con l'aspetto classico.
begin;
drop function if exists public.game_looks(uuid[]);
drop function if exists public.game_set_look(jsonb);
drop table if exists public.game_hero_looks;
commit;
