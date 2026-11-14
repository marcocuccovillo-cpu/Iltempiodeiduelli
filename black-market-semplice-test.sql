-- =====================================================================
-- TEST DELLA MIGRAZIONE 045 (vetrina pubblica e primi passi). SOLO su un progetto di PROVA vuoto. Finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-semplice-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
do $$
declare r jsonb; n text; m uuid; b0 integer; b1 integer;
begin
  foreach n in array array['Ann','Bob','Cal'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n);
  end loop;
  update public.profiles set suspended = true where id = pg_temp.uid('Cal');
  update public.profiles set wanted_enabled = true;

  -- S1: all'inizio nessun obiettivo è completato e non si può riscuotere
  perform pg_temp.as_('Ann');
  r := public.onboarding_state();
  assert (select bool_and(not (x->>'done')::boolean) from jsonb_array_elements(r->'steps') x), format('S1: nessun obiettivo fatto (%s)', r);
  begin perform public.onboarding_claim('photo'); raise exception 'PAGATO'; exception when others then assert sqlerrm = 'Obiettivo non ancora completato', 'S1: ' || sqlerrm; end;
  begin perform public.onboarding_claim('boh'); raise exception 'PAGATO'; exception when others then assert sqlerrm = 'Obiettivo sconosciuto', 'S1b: ' || sqlerrm; end;
  insert into t_log (msg) values ('OK S1 — obiettivi non completati non si riscuotono');

  -- S2: foto, sfida, taglia, match: ogni bonus si paga una volta sola
  update public.profiles set avatar_img = 'data:image/jpeg;base64,AAAA' where id = pg_temp.uid('Ann');
  select balance into b0 from public.wallets where user_id = pg_temp.uid('Ann');
  r := public.onboarding_claim('photo');
  assert (r->>'bc')::int = 100 and not (r->>'already')::boolean, format('S2: bonus foto (%s)', r);
  r := public.onboarding_claim('photo');
  assert (r->>'bc')::int = 0 and (r->>'already')::boolean, format('S2: secondo tentativo non paga (%s)', r);
  select balance into b1 from public.wallets where user_id = pg_temp.uid('Ann');
  assert b1 = b0 + 100, format('S2: saldo +100 (%s → %s)', b0, b1);
  perform public.ladder_challenge(pg_temp.uid('Bob'), 'Advanced', null, gen_random_uuid()::text, 'ladder');
  select id into m from public.ladder_matches where challenger_id = pg_temp.uid('Ann');
  perform public.create_bounty(pg_temp.uid('Bob'), 50, null, gen_random_uuid()::text);
  assert (public.onboarding_claim('challenge')->>'bc')::int = 100, 'S2: bonus prima sfida';
  assert (public.onboarding_claim('bounty')->>'bc')::int = 100, 'S2: bonus prima taglia';
  perform pg_temp.as_('Bob'); perform public.ladder_respond(m, true);
  perform pg_temp.as_('Ann'); perform public.ladder_report(m, 'challenger', '2-0');
  perform pg_temp.as_('Bob'); perform public.ladder_confirm(m);
  perform pg_temp.as_('Ann');
  r := public.onboarding_state();
  assert (select bool_and((x->>'done')::boolean) from jsonb_array_elements(r->'steps') x) and (r->>'played')::int = 1, format('S2: tutti fatti, 1 match (%s)', r);
  assert (public.onboarding_claim('match')->>'bc')::int = 100, 'S2: bonus primo match';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Ann') and kind = 'onboarding_bonus') = 4, 'S2: 4 movimenti';
  assert (select bool_and((x->>'claimed')::boolean) from jsonb_array_elements(public.onboarding_state()->'steps') x), 'S2: tutti riscossi';
  insert into t_log (msg) values ('OK S2 — 4 obiettivi pagati una volta sola, saldo e registro coerenti');

  -- S3: vetrina pubblica, anche senza account; niente sospesi, niente email
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  execute 'set local role anon';
  r := public.public_showcase();
  execute 'reset role';
  assert (r->>'on')::boolean, 'S3: vetrina attiva';
  assert jsonb_array_length(r->'ladder'->'Advanced') >= 2, format('S3: classifica Advanced (%s)', r->'ladder');
  assert jsonb_typeof(r->'wanted') = 'array', format('S3: Most Wanted (%s)', r->'wanted');
  assert jsonb_array_length(r->'recent') = 1 and r->'recent'->0->>'a' = 'Ann', format('S3: ultimo risultato (%s)', r->'recent');
  assert position('Cal' in r::text) = 0 and position('@test.local' in r::text) = 0, 'S3: niente sospesi né email';
  assert (r->'counts'->>'players')::int = 2, format('S3: conteggio duellanti (%s)', r->'counts');
  update public.system_settings set value_int = 0 where key = 'showcase_public';
  assert not (public.public_showcase()->>'on')::boolean, 'S3: vetrina spegnibile';
  perform pg_temp.as_('Ann');
  update public.system_settings set value_int = 0 where key = 'onboarding_enabled';
  begin perform public.onboarding_claim('photo'); raise exception 'PAGATO'; exception when others then assert sqlerrm = 'I primi passi non sono attivi', 'S3: ' || sqlerrm; end;
  insert into t_log (msg) values ('OK S3 — vetrina leggibile senza account (senza sospesi né email), spegnibile; primi passi spegnibili');
end $$;
select msg as risultato from t_log order by n;
rollback;
