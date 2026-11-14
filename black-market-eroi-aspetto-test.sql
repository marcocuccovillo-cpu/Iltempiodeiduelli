-- =====================================================================
-- TEST DELLA MIGRAZIONE 044 (aspetto dell'eroe). SOLO su un progetto di PROVA vuoto. Finisce con ROLLBACK: non lascia dati.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-aspetto-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
do $$
declare r jsonb; n text;
begin
  foreach n in array array['Ann','Bob'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n);
  end loop;
  perform pg_temp.as_('Ann');
  r := public.game_set_look('{"skin":2,"hair":7,"hs":3,"armor":1,"cape":8,"weapon":2}');
  assert r->'look' = '{"skin":2,"hair":7,"hs":3,"armor":1,"cape":8,"weapon":2}'::jsonb, 'A1: aspetto salvato';
  r := public.game_set_look('{"skin":9,"hair":-1,"hs":1,"armor":"x","nuovo":3}');
  assert r->'look' = '{"hs":1}'::jsonb, format('A1: valori fuori dai limiti scartati (%s)', r);
  perform pg_temp.as_('Bob');
  r := public.game_looks(array[pg_temp.uid('Ann'), pg_temp.uid('Bob')]);
  assert r = jsonb_build_object(pg_temp.uid('Ann')::text, '{"hs":1}'::jsonb), format('A2: si leggono gli aspetti degli altri (%s)', r);
  begin execute 'set local role authenticated'; perform pg_temp.as_('Bob'); update public.game_hero_looks set look = '{}'; raise exception 'SCRITTO';
  exception when others then assert sqlerrm <> 'SCRITTO', 'A3: il browser non scrive direttamente'; end;
  execute 'reset role';
  insert into t_log (msg) values ('OK A1–A3 — aspetto salvato e validato, letto dagli altri, tabella protetta');
end $$;
select msg as risultato from t_log order by n;
rollback;
