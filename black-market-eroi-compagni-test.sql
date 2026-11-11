-- =====================================================================
-- TEST DELLA MIGRAZIONE 043 (nuovi compagni dei gradi 10–14)
-- Da eseguire SOLO su un progetto Supabase di PROVA ancora vuoto, con le migrazioni applicate fino a black-market-eroi-compagni.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-compagni-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n); execute q; return null; exception when others then return sqlerrm; end $$;

do $$
declare s jsonb; b0 integer; r jsonb; c record;
begin
  -- catalogo
  assert (select count(*) from public.game_pets) = 45 and (select count(*) from public.game_pets where tier between 10 and 14) = 15, 'C1: 15 compagni nuovi, 45 in tutto';
  assert (select array_agg(distinct min_level order by min_level) from public.game_pets where tier >= 10) = array[420, 460, 500, 550, 600], 'C1: livelli 420…600';
  assert (select count(*) from public.game_pets where tier >= 10 group by tier having count(distinct variant) = 3 limit 1) = 3, 'C1: tre stili per grado';
  assert (select max(l.max_value) from public.game_pet_lines l join public.game_pets g on g.id = l.pet_id where g.tier = 14 and l.pos = 1) = 64, 'C1: bonus principale 64% al grado 14';
  assert (select count(*) from public.game_pet_lines l join public.game_pets g on g.id = l.pet_id where g.tier >= 12 and l.pos = 6 and l.unlock_level = 90) = 9, 'C1: 6° bonus al livello 90 dai gradi 12';
  insert into t_log (msg) values ('OK C1 — catalogo: 15 compagni nei gradi 10–14 (livelli 420–600), tre stili per grado, bonus in scala');

  insert into auth.users (id, email, aud, role) values (pg_temp.uid('Ann'), 'ann@test.local', 'authenticated', 'authenticated');
  perform pg_temp.as_('Ann'); perform public.register_profile('Ann'); perform public.game_state(); perform public.game_set_stats(4, 4, 4, 4, 4);
  perform public._ledger_move(pg_temp.uid('Ann'), 20000000, 'admin_adjustment', 'test', null, 'test:soldi:ann', 'soldi di prova');
  perform public.game_pet_choose('pet_ranocchio');
  update public.game_heroes set level = 599 where user_id = pg_temp.uid('Ann');
  assert pg_temp.err_as('Ann', 'select public.game_pet_buy(''pet_drago_primordiale'')') like '%livello 600%', 'C2: al livello 599 il grado 14 è chiuso';
  b0 := (select balance from public.wallets where user_id = pg_temp.uid('Ann'));
  r := public.game_pet_buy('pet_kirin');
  assert (r->>'price')::int = 1600000 and (select balance from public.wallets where user_id = pg_temp.uid('Ann')) = b0 - 1600000, 'C2: Kirin del Lampo costa 1.600.000 BC';
  update public.game_heroes set level = 600 where user_id = pg_temp.uid('Ann');
  perform public.game_pet_buy('pet_drago_primordiale'); perform public.game_pet_activate('pet_drago_primordiale');
  update public.game_hero_pets set level = 100 where user_id = pg_temp.uid('Ann') and pet_id = 'pet_drago_primordiale';
  select * into c from public._game_pet_bonus(pg_temp.uid('Ann'));
  assert c.pf = 64 and c.pd = 48 and c.pv = 32 and c.px = 16 and c.pa = 1 and c.pr = 20, format('C2: bonus pieni del Drago Primordiale (%s)', row_to_json(c));
  s := public.game_pet_state();
  assert (select count(*) from jsonb_array_elements(s->'pets') e where (e->>'tier')::int >= 10) = 15, 'C2: lo Stagno mostra i 15 nuovi';
  perform pg_temp.as_('Ann');
  insert into t_log (msg) values ('OK C2 — acquisto con il livello giusto, prezzo nel registro, bonus pieni al livello 100 del compagno, Stagno aggiornato');
end $$;

select msg as risultato from t_log order by n;
rollback;
