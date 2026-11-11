-- =====================================================================
-- ANNULLAMENTO DELLA MIGRAZIONE 043 (compagni dei gradi 10–14)
-- Chi aveva comprato uno dei 15 compagni nuovi riceve indietro i BC spesi (movimento nel registro). Chi lo aveva come compagno attivo
-- torna al suo compagno base. Poi i 15 compagni spariscono dal catalogo e i gradi tornano a fermarsi al 9.
-- =====================================================================
begin;
do $$
declare r record; n integer := 0;
begin
  for r in select hp.user_id, hp.pet_id, hp.active, g.price_bc, g.name from public.game_hero_pets hp join public.game_pets g on g.id = hp.pet_id where g.tier >= 10 order by hp.user_id, hp.pet_id loop
    perform public._ledger_move(r.user_id, r.price_bc, 'admin_adjustment', 'game_pet', null, 'gamepet043down:' || r.user_id::text || ':' || r.pet_id, 'Lo stagno: ' || r.name || ' rimborsato (annullamento della migrazione 043)');
    if r.active then
      update public.game_hero_pets set active = false where user_id = r.user_id and pet_id = r.pet_id;
      update public.game_hero_pets set active = true where user_id = r.user_id and pet_id = (select hp.pet_id from public.game_hero_pets hp join public.game_pets g on g.id = hp.pet_id where hp.user_id = r.user_id and g.starter limit 1);
    end if;
    n := n + 1;
  end loop;
  delete from public.game_hero_pets where pet_id in (select id from public.game_pets where tier >= 10);
  delete from public.game_pets where tier >= 10;               -- le righe dei bonus se ne vanno con loro (on delete cascade)
  if n > 0 then perform public._audit(null, 'pet043_down_refund', 'game_pet', null, null, jsonb_build_object('refunded', n), 'annullamento della migrazione 043'); end if;
  alter table public.game_pets drop constraint if exists game_pets_tier_check;
  alter table public.game_pets add constraint game_pets_tier_check check (tier between 0 and 9);
end $$;
commit;
