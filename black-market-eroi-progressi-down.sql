-- =====================================================================
-- ANNULLAMENTO DELLA MIGRAZIONE 040 (nuovi gradi di abilità e scheda eroe)
-- Toglie la funzione game_hero_extra. I gradi nuovi già COMPRATI non si possono togliere dal catalogo (restano legati agli acquisti
-- nel registro): questo file li rende soltanto non più acquistabili alzando il livello richiesto oltre il massimo.
-- I potenziamenti temporanei nuovi non ancora comprati da nessuno vengono cancellati.
-- =====================================================================
begin;
drop function if exists public.game_hero_extra(uuid);
update public.game_skills set min_level = 99999
 where (kind = 'perm' and tier between 9 and 12) or (kind = 'temp' and tier between 3 and 8);
delete from public.game_skills k
 where k.kind = 'temp' and k.tier between 3 and 8
   and not exists (select 1 from public.game_temp_skills t where t.skill_id = k.id);
delete from public.game_skills k
 where k.kind = 'perm' and k.tier between 9 and 12
   and not exists (select 1 from public.game_hero_skills h where h.skill_id = k.id);
commit;
