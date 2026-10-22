-- TEST DELLA MIGRAZIONE 014 (avatar degli eroi). Da eseguire su un database di PROVA vuoto, DOPO le migrazioni 001…014. Finisce con ROLLBACK.
begin;
do $$ begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.events) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto, mai su quello reale. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);
create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-avatar-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$ begin perform pg_temp.as_(n); return pg_temp.err(q); end $$;
create function pg_temp.err_auth(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n);
  begin execute 'set local role authenticated'; execute q; raise exception 'RIUSCITA';
  exception when others then return case when sqlerrm = 'RIUSCITA' then null else sqlerrm end; end; end $$;
create function pg_temp.rows_as(n text, q text) returns bigint language plpgsql as $$
declare c bigint;
begin perform pg_temp.as_(n);
  begin execute 'set local role authenticated'; execute 'select count(*) from (' || q || ') x' into c; raise exception 'RISULTATO:%', c;
  exception when others then if sqlerrm like 'RISULTATO:%' then return substr(sqlerrm, 11)::bigint; end if; raise; end; end $$;

do $$
declare n text; r jsonb; m numeric;
begin
  foreach n in array array['Admin','Ann','Bob'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n); perform public.register_profile(n);
  end loop;
  -- V1: impostare, cambiare, togliere
  perform pg_temp.as_('Ann'); r := public.game_set_avatar(46986414, '  Dark Magician  ');
  assert r->>'avatar_card' = '46986414' and r->>'avatar_name' = 'Dark Magician', 'V1: avatar impostato, nome ripulito';
  assert (select avatar_card from public.game_heroes where user_id = pg_temp.uid('Ann')) = 46986414, 'V1: salvato';
  perform public.game_set_avatar(89631139, 'Blue-Eyes White Dragon');
  assert (select avatar_card from public.game_heroes where user_id = pg_temp.uid('Ann')) = 89631139, 'V1: cambiato';
  assert pg_temp.rows_as('Bob', 'select avatar_card from public.game_heroes where user_id = ''' || pg_temp.uid('Ann') || ''' and avatar_card = 89631139') = 1, 'V1: gli altri eroi lo vedono';
  perform pg_temp.as_('Ann'); r := public.game_set_avatar(null, null);
  assert (select avatar_card is null and avatar_name is null from public.game_heroes where user_id = pg_temp.uid('Ann')), 'V1: avatar tolto';
  -- V2: valori non validi
  assert pg_temp.err_as('Ann', 'select public.game_set_avatar(0, ''x'')') = 'Carta non valida', 'V2: 0 rifiutato';
  assert pg_temp.err_as('Ann', 'select public.game_set_avatar(-5, ''x'')') = 'Carta non valida', 'V2: negativo rifiutato';
  assert pg_temp.err_as('Ann', 'select public.game_set_avatar(1000000000, ''x'')') = 'Carta non valida', 'V2: troppo grande rifiutato';
  assert pg_temp.err_as('Ann', 'select public.game_set_avatar(123, null)') = 'Nome della carta mancante', 'V2: nome obbligatorio';
  assert pg_temp.err_as('Ann', 'select public.game_set_avatar(123, ''   '')') = 'Nome della carta mancante', 'V2: nome vuoto';
  perform pg_temp.as_('Ann'); perform public.game_set_avatar(123, repeat('a', 300));
  assert (select char_length(avatar_name) from public.game_heroes where user_id = pg_temp.uid('Ann')) = 80, 'V2: nome tagliato a 80';
  perform public.game_set_avatar(124, E'Nome\twith\ncontrol');
  assert (select avatar_name from public.game_heroes where user_id = pg_temp.uid('Ann')) = 'Namewithcontrol' or (select avatar_name !~ '[[:cntrl:]]' from public.game_heroes where user_id = pg_temp.uid('Ann')), 'V2: niente caratteri di controllo';
  -- V3: solo il proprio eroe, niente scritture dirette, modulo spento
  assert pg_temp.err_auth('Ann', 'update public.game_heroes set avatar_card = 5, avatar_name = ''x'' where user_id = ''' || pg_temp.uid('Bob') || '''') is not null, 'V3: nessuna scrittura diretta';
  assert not has_function_privilege('anon', 'public.game_set_avatar(integer,text)', 'execute'), 'V3: anon non può';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('heroes', false, 'prova del modulo');
  assert pg_temp.err_as('Ann', 'select public.game_set_avatar(5, ''x'')') = 'Modulo non attivo', 'V3: a modulo spento rifiutato';
  perform pg_temp.as_('Admin'); perform public.admin_set_module('heroes', true, 'riaccendo');
  insert into t_log (msg) values ('OK V1–V3 — avatar: imposta/cambia/toglie, valori non validi rifiutati, nessuna scrittura diretta, modulo spento blocca');
end $$;
-- V4: l'avatar di un altro eroe non cambia, i BC non si muovono
do $$
declare t0 bigint := (select coalesce(sum(balance),0) from public.wallets);
begin
  perform pg_temp.as_('Bob'); perform public.game_set_avatar(777, 'Exodia');
  assert (select avatar_card from public.game_heroes where user_id = pg_temp.uid('Ann')) = 124, 'V4: l''avatar di Ann è rimasto suo';
  assert (select coalesce(sum(balance),0) from public.wallets) = t0, 'V4: nessun BC mosso';
  insert into t_log (msg) values ('OK V4 — ognuno cambia solo il suo avatar, nessun BC mosso');
end $$;
select n, msg from t_log order by n;
rollback;
