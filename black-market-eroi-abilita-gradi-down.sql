-- =====================================================================
-- ANNULLAMENTO della MIGRAZIONE 030 (abilità permanenti, gradi dal 5° all'8°)
-- Toglie i 20 gradi nuovi dal catalogo del Mercante. Si ferma, senza toccare nulla, se qualcuno ne ha già comprato uno
-- (i BC spesi non si restituiscono da soli e gli acquisti non si cancellano): in quel caso decidi tu a mano.
-- =====================================================================
begin;
do $$
declare n integer;
begin
  select count(*) into n from public.game_hero_skills s join public.game_skills k on k.id = s.skill_id where k.kind = 'perm' and k.tier >= 5;
  if n > 0 then raise exception 'ANNULLAMENTO FERMATO: % acquisti dei gradi 5–8 già fatti dagli eroi. Non è stato modificato nulla.', n; end if;
end $$;
delete from public.game_skills where kind = 'perm' and tier >= 5;
commit;
