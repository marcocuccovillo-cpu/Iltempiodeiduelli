-- =====================================================================
-- TEST DELLA MIGRAZIONE 040 (gradi 9–12, potenziamenti 3–8, scheda eroe)
-- Da eseguire SOLO su un progetto Supabase di PROVA ancora vuoto, con tutte le migrazioni applicate fino a black-market-eroi-progressi.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-prog-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n); execute q; return null; exception when others then return sqlerrm; end $$;

do $$
declare n text;
begin
  foreach n in array array['Ann','Bob'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n); perform public.game_state(); perform public.game_set_stats(4, 4, 4, 4, 4);
  end loop;
  -- Ann: livello 600, ricca, con gli 8 gradi di Forza già comprati
  update public.game_heroes set level = 600 where user_id = pg_temp.uid('Ann');
  perform public._ledger_move(pg_temp.uid('Ann'), 20000000, 'admin_adjustment', 'test', null, 'test:soldi-ann', 'soldi di prova');
  insert into public.game_hero_skills (user_id, skill_id) select pg_temp.uid('Ann'), id from public.game_skills where kind = 'perm' and stat = 'for' and tier <= 8;
  insert into t_log (msg) values ('OK Preparazione');
end $$;

-- P1 — Gradi permanenti 9–12: in ordine, livello richiesto, bonus applicato
do $$
declare b0 integer; b1 integer;
begin
  assert (select count(*) from public.game_skills where kind = 'perm') = 60, 'P1: 12 gradi × 5 statistiche';
  assert pg_temp.err_as('Ann', 'select public.game_buy_skill(''sk_for_10'')') like '%Prima ti serve%', 'P1: si comprano in ordine';
  assert pg_temp.err_as('Bob', 'select public.game_buy_skill(''sk_for_9'')') like '%livello 450%', 'P1: serve il livello';
  perform pg_temp.as_('Ann'); b0 := (select b_for from public._game_calc(pg_temp.uid('Ann')));
  perform public.game_buy_skill('sk_for_9'); perform public.game_buy_skill('sk_for_10'); perform public.game_buy_skill('sk_for_11'); perform public.game_buy_skill('sk_for_12');
  b1 := (select b_for from public._game_calc(pg_temp.uid('Ann')));
  assert b1 - b0 = 30 + 34 + 38 + 42, format('P1: +144%% di Forza (era %s, ora %s)', b0, b1);
  assert (select balance from public.wallets where user_id = pg_temp.uid('Ann')) = 1000 + 20000000 - 11250000, 'P1: prezzo pagato';
  insert into t_log (msg) values ('OK P1 — gradi 9–12 in ordine, dal livello 450 al 600, +144% e 11.250.000 BC');
end $$;

-- P2 — Potenziamenti temporanei 3–8: livello, uno per equipaggiamento, si sale di grado
do $$
begin
  assert (select count(*) from public.game_skills where kind = 'temp') = 40, 'P2: 8 gradi × 5 equipaggiamenti';
  assert pg_temp.err_as('Bob', 'select public.game_buy_skill(''tk_weapon_3'')') like '%livello 40%', 'P2: serve il livello';
  perform pg_temp.as_('Ann'); perform public.game_buy_skill('tk_weapon_7'); perform public.game_buy_skill('tk_weapon_8');
  assert pg_temp.err_as('Ann', 'select public.game_buy_skill(''tk_weapon_3'')') like '%potenziamento migliore%', 'P2: non si scende di grado';
  assert (select count(*) from public.game_temp_skills where user_id = pg_temp.uid('Ann') and expires_at > now()) = 1, 'P2: uno attivo per equipaggiamento';
  insert into t_log (msg) values ('OK P2 — potenziamenti 3–8 con livello richiesto, uno per equipaggiamento, solo verso l''alto');
end $$;

-- P3 — Scheda di un altro eroe
do $$
declare x jsonb;
begin
  perform pg_temp.as_('Bob'); x := public.game_hero_extra(pg_temp.uid('Ann'));
  assert (x->'grades'->>'for')::int = 12 and (x->>'grades_max')::int = 12, 'P3: gradi per statistica';
  assert (x->'dungeons'->>'total')::int = 100, 'P3: dungeon';
  assert x ? 'arena' and x ? 'tower' and x ? 'raid', 'P3: Arena, Torre, raid presenti (anche vuoti)';
  assert pg_temp.err_as('Bob', format('select public.game_hero_extra(%L)', gen_random_uuid())) like '%inesistente%', 'P3: eroe inesistente';
  insert into t_log (msg) values ('OK P3 — game_hero_extra');
end $$;

select msg as risultato from t_log order by n;
rollback;
