-- =====================================================================
-- TEST DELLA MIGRAZIONE 048 (raid: rientro a pagamento). SOLO su un database di PROVA vuoto. Finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-rientro-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
do $$
declare s jsonb; r jsonb; n text; rid bigint; b0 integer; d date := (now() at time zone 'Europe/Rome')::date; e text;
begin
  foreach n in array array['Ann','Bob'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n); perform public.game_state(); perform public.game_set_stats(4, 4, 4, 4, 4);
  end loop;
  perform pg_temp.as_('Ann'); s := public.game_raid_state(); rid := (s->'raid'->>'id')::bigint;
  update public.game_raids set hp = max_hp * 1000, max_hp = max_hp * 1000 where id = rid;      -- un boss che non cade durante la prova
  assert (s->'me'->>'revive_cost')::int = 100 and (s->'me'->>'revives')::int = 0, format('T1: prima quota 100 (%s)', s->'me');

  -- T1: da vivi non si paga
  r := public.game_raid_act('attack', null);
  begin perform public.game_raid_revive(); raise exception 'PAGATO'; exception when others then assert sqlerrm = 'Non sei KO: non serve rientrare', 'T1: ' || sqlerrm; end;
  insert into t_log (msg) values ('OK T1 — chi è in piedi non può (e non deve) pagare');

  -- T2: KO → non si attacca; si rientra pagando 100, poi 200, poi 400; PV pieni; cronaca e registro
  update public.game_raid_days set hp = 0 where raid_id = rid and user_id = pg_temp.uid('Ann') and day = d;
  begin perform public.game_raid_act('attack', null); raise exception 'COLPITO'; exception when others then assert sqlerrm like 'Sei KO: rientra pagando%', 'T2: ' || sqlerrm; end;
  b0 := pg_temp.bal('Ann');
  r := public.game_raid_revive();
  assert (r->>'cost')::int = 100 and (r->>'next_cost')::int = 200 and (r->>'revives')::int = 1 and (r->>'my_hp')::bigint = (r->>'my_max_hp')::bigint, format('T2: primo rientro (%s)', r);
  assert pg_temp.bal('Ann') = b0 - 100, 'T2: saldo −100';
  r := public.game_raid_act('attack', null); assert (r->>'revive_cost')::int = 200, format('T2: l''azione riporta la quota (%s)', r->>'revive_cost');
  update public.game_raid_days set hp = 0 where raid_id = rid and user_id = pg_temp.uid('Ann') and day = d;
  r := public.game_raid_revive(); assert (r->>'cost')::int = 200, 'T2: secondo rientro 200';
  update public.game_raid_days set hp = 0 where raid_id = rid and user_id = pg_temp.uid('Ann') and day = d;
  r := public.game_raid_revive(); assert (r->>'cost')::int = 400 and (r->>'next_cost')::int = 800, 'T2: terzo rientro 400';
  assert pg_temp.bal('Ann') = b0 - 700, 'T2: saldo −700 in tutto';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Ann') and kind = 'game_raid_revive') = 3, 'T2: tre movimenti nel registro';
  assert (select count(*) from public.game_raid_log where raid_id = rid and action = 'revive') = 3, 'T2: tre voci in cronaca';
  s := public.game_raid_state(); assert (s->'me'->>'revives')::int = 3 and (s->'me'->>'revive_cost')::int = 800 and not (s->'me'->>'ko')::boolean, format('T2: stato (%s)', s->'me');
  insert into t_log (msg) values ('OK T2 — rientri a 100, 200, 400 BC con PV pieni; saldo, registro e cronaca coerenti');

  -- T3: la quota è personale; tetto, saldo insufficiente, spegnimento; la cura di un alleato resta gratis
  perform pg_temp.as_('Bob'); assert (public.game_raid_state()->'me'->>'revive_cost')::int = 100, 'T3: Bob parte da 100';
  update public.system_settings set value_int = 500 where key = 'game_raid_revive_max';
  assert public._raid_revive_cost(rid, pg_temp.uid('Ann')) = 500, 'T3: tetto 500';
  update public.system_settings set value_int = 0 where key = 'game_raid_revive_max';
  perform pg_temp.as_('Ann');
  update public.game_raid_days set hp = 0 where raid_id = rid and user_id = pg_temp.uid('Ann') and day = d;
  update public.wallets set balance = 10 where user_id = pg_temp.uid('Ann');
  begin perform public.game_raid_revive(); raise exception 'PAGATO'; exception when others then assert sqlerrm = 'Saldo insufficiente', 'T3: ' || sqlerrm; end;
  assert (select hp from public.game_raid_days where raid_id = rid and user_id = pg_temp.uid('Ann') and day = d) = 0, 'T3: senza BC si resta KO';
  perform pg_temp.as_('Bob'); perform public.game_raid_act('attack', null); r := public.game_raid_act('heal', pg_temp.uid('Ann'));
  assert (select hp from public.game_raid_days where raid_id = rid and user_id = pg_temp.uid('Ann') and day = d) > 0, 'T3: la cura di un alleato rianima gratis';
  update public.system_settings set value_int = 0 where key = 'game_raid_revive_bc';
  perform pg_temp.as_('Ann'); update public.game_raid_days set hp = 0 where raid_id = rid and user_id = pg_temp.uid('Ann') and day = d;
  begin perform public.game_raid_revive(); raise exception 'PAGATO'; exception when others then assert sqlerrm = 'Il rientro a pagamento non è attivo', 'T3: ' || sqlerrm; end;
  insert into t_log (msg) values ('OK T3 — quota personale, tetto rispettato, senza BC si resta KO, la cura dell''alleato resta gratis, funzione spegnibile');
end $$;
select msg as risultato from t_log order by n;
rollback;
