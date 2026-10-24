-- =====================================================================
-- TEST DELLE SCOMMESSE (black-market-scommesse.sql)
-- Da eseguire su un database di PROVA vuoto, DOPO la Ladder e dopo black-market-scommesse.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Se un controllo fallisce compare un errore con il nome dello scenario.
-- Le sfide Ladder vengono create e chiuse con scritture dirette sulla tabella ladder_matches (è ciò che fanno le funzioni della Ladder,
-- e il trigger delle scommesse reagisce alla riga, non alla funzione). Se la tua tabella ha colonne obbligatorie in più, adatta pg_temp.mk().
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.events) or exists (select 1 from public.ladder_matches) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto (per esempio un secondo progetto Supabase gratuito), mai su quello reale. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);

create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-scommesse-' || n)::uuid $$;
create function pg_temp.act(u uuid) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true) $$;
create function pg_temp.as_(n text) returns text language sql as $$ select pg_temp.act(pg_temp.uid(n)) $$;
create function pg_temp.rows_as(n text, q text) returns bigint language plpgsql as $$
declare c bigint;
begin
  perform pg_temp.as_(n);
  begin
    execute 'set local role authenticated';
    execute 'select count(*) from (' || q || ') x' into c;
    raise exception 'RISULTATO:%', c;
  exception when others then
    if sqlerrm like 'RISULTATO:%' then return substr(sqlerrm, 11)::bigint; end if;
    raise;
  end;
end $$;
create function pg_temp.err(q text) returns text language plpgsql as $$
begin execute q; return null; exception when others then return sqlerrm; end $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n); return pg_temp.err(q); end $$;
create function pg_temp.err_auth(n text, q text) returns text language plpgsql as $$
begin
  perform pg_temp.as_(n);
  begin execute 'set local role authenticated'; execute q; raise exception 'RIUSCITA';
  exception when others then return case when sqlerrm = 'RIUSCITA' then null else sqlerrm end; end;
end $$;

-- Preparazione: Admin (il primo registrato), Ann/Bob/Fay/Gus giocano, Cy/Di/Eve/Povero scommettono
do $$
declare n text;
begin
  foreach n in array array['Admin','Ann','Bob','Fay','Gus','Cyr','Dia','Eve','Povero'] loop
    insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
    perform pg_temp.as_(n);
    perform public.register_profile(n);
    perform public.update_my_profile(null, true);
  end loop;
  insert into t_log (msg) values ('OK Preparazione: 9 utenti, Admin = primo registrato');
end $$;
create function pg_temp.set_(k text, v integer) returns void language plpgsql as $$
begin perform pg_temp.as_('Admin'); perform public.admin_set_setting(k, v, 'impostazione di prova'); end $$;
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.fund(n text, amt integer) returns void language plpgsql as $$
begin
  perform pg_temp.as_('Admin');
  perform public.admin_adjust_balance(pg_temp.uid(n), amt - pg_temp.bal(n), 'saldo di prova');
end $$;
-- una sfida Ladder (la tabella accetta stato e risultato direttamente)
create function pg_temp.mk(a text, b text, st text default 'pending', fmt text default 'Advanced', kind text default 'ladder') returns uuid language plpgsql as $$
declare i uuid := gen_random_uuid();
begin
  insert into public.ladder_matches (id, challenger_id, opponent_id, format, kind, status) values (i, pg_temp.uid(a), pg_temp.uid(b), fmt, kind, st);
  return i;
end $$;
create function pg_temp.mst(i uuid, st text, res text default null) returns void language plpgsql as $$
begin
  perform set_config('app.ladder_correct', 'on', true);       -- come fanno la correzione e l'annullamento dell'amministratore
  update public.ladder_matches set status = st, reported_result = res, closed_at = case when st = 'closed' then clock_timestamp() end where id = i;
  perform set_config('app.ladder_correct', 'off', true);
end $$;
create function pg_temp.bet(u text, m uuid, pick text, stake integer, minq integer default null) returns jsonb language plpgsql as $$
begin perform pg_temp.as_(u); return public.place_bet(m, pg_temp.uid(pick), stake, minq, gen_random_uuid()::text); end $$;
create function pg_temp.berr(u text, m uuid, pick text, stake integer, minq integer default null) returns text language plpgsql as $$
begin
  perform pg_temp.as_(u);
  begin perform public.place_bet(m, pg_temp.uid(pick), stake, minq, gen_random_uuid()::text); return null;
  exception when others then return sqlerrm; end;
end $$;
create function pg_temp.q(m uuid) returns jsonb language sql as $$ select public._bet_quote(l) from public.ladder_matches l where l.id = m $$;
create function pg_temp.bst(u text, m uuid) returns text language sql as $$ select status from public.bets where user_id = pg_temp.uid(u) and match_id = m $$;
create function pg_temp.bret(u text, m uuid) returns integer language sql as $$ select returned from public.bets where user_id = pg_temp.uid(u) and match_id = m $$;
create function pg_temp.inv() returns bigint language sql as $$
  select count(*) from public.wallets w where w.balance <> coalesce((select sum(amount) from public.ledger_entries l where l.user_id = w.user_id), 0) $$;
create function pg_temp.bounty_state() returns text language sql as $$
  select md5((select count(*)::text || coalesce(sum(amount), 0)::text from public.bounties) || (select count(*)::text from public.bounty_settlements)) $$;
create function pg_temp.addr(n text, w integer, d integer, l integer, fmt text default 'Advanced') returns void language sql as $$
  insert into public.ladder_ratings (user_id, format, wins, draws, losses) values (pg_temp.uid(n), fmt, w, d, l) on conflict (user_id, format) do update set wins = w, draws = d, losses = l $$;

do $$
declare n text;
begin
  foreach n in array array['Cyr','Dia','Eve'] loop perform pg_temp.fund(n, 1000); end loop;
  perform pg_temp.fund('Povero', 20);
  perform pg_temp.set_('bet_max_open', 50);
  insert into t_log (msg) values ('OK Saldi di prova: Cy/Di/Eve 1000, Povero 20');
end $$;

-- ---------------------------------------------------------------- S1 struttura, permessi, impostazioni
do $$
declare d text;
begin
  assert (select count(*) from public.system_settings where key like 'bet\_%') = 12, 'S1: dodici impostazioni';
  assert (select value_int from public.system_settings where key = 'bet_margin_pct') = 10 and (select value_int from public.system_settings where key = 'bet_close_minutes') = 10
     and (select value_int from public.system_settings where key = 'bet_w_winrate') = 100 and (select value_int from public.system_settings where key = 'bet_w_bounty') = 30
     and (select value_int from public.system_settings where key = 'bet_w_pool') = 40, 'S1: valori iniziali (anche i tre pesi 100/30/40)';
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.ledger_entries'::regclass and conname = 'ledger_entries_kind_check';
  assert d like '%initial_bonus%' and d like '%bounty_payout%' and d like '%admin_adjustment%' and d like '%bet_stake%' and d like '%bet_payout%' and d like '%bet_refund%' and d like '%bet_reversal%',
    'S1: i tipi di movimento vecchi restano e i nuovi si aggiungono';
  assert not has_function_privilege('anon', 'public.place_bet(uuid,uuid,integer,integer,text)', 'execute')
     and has_function_privilege('authenticated', 'public.place_bet(uuid,uuid,integer,integer,text)', 'execute'), 'S1: place_bet solo per utenti collegati';
  assert not has_function_privilege('authenticated', 'public._bet_reconcile(uuid)', 'execute')
     and not has_function_privilege('authenticated', 'public._bet_quote(public.ladder_matches)', 'execute')
     and not has_function_privilege('anon', 'public.bet_markets()', 'execute'), 'S1: le funzioni interne non sono chiamabili dal browser';
  assert pg_temp.err_auth('Cyr', 'insert into public.bets (user_id, match_id, pick, stake, quota, basis, prob_pct, client_request_id) select id, gen_random_uuid(), id, 10, 200, ''even'', 50, ''xxxxxxxxxx'' from public.profiles limit 1') is not null, 'S1: nessuna scrittura diretta sulle scommesse';
  assert pg_temp.err_auth('Cyr', 'update public.wallets set balance = balance + 1000') is not null or pg_temp.bal('Cyr') = 1000, 'S1: nessun accesso diretto ai saldi';
  assert pg_temp.err_auth('Cyr', 'select * from public.bet_windows') like '%permission denied%', 'S1: bet_windows chiusa al browser';
  assert pg_temp.err('select public.place_bet(gen_random_uuid(), gen_random_uuid(), 50, null, ''abcdefgh'')') is not null, 'S1: serve il login';
  insert into t_log (msg) values ('OK S1 — impostazioni, tipi di movimento, permessi');
end $$;

-- ---------------------------------------------------------------- S2 quote: win rate, bounty value e scommesse presenti insieme
-- (i valori attesi sono calcolati a parte, con una formula indipendente scritta in Python)
-- pq: null se probabilità e quote coincidono con quelle attese, altrimenti la quota trovata (per i messaggi di errore)
create function pg_temp.pq(m uuid, p numeric, qc integer, qo integer) returns text language sql as $$
  select case when (pg_temp.q(m)->>'p_challenger')::numeric = p and (pg_temp.q(m)->>'quota_challenger')::int = qc and (pg_temp.q(m)->>'quota_opponent')::int = qo
              then null else pg_temp.q(m)::text end $$;
do $$
declare m uuid; q jsonb; mf uuid; mp uuid;
begin
  -- nessun dato e nessuna taglia: 50/50, margine 10% → 1,80
  m := pg_temp.mk('Ann', 'Bob');
  q := pg_temp.q(m);
  assert q->>'basis' = 'even' and (q->>'p_challenger')::numeric = 50 and (q->>'quota_challenger')::int = 180 and (q->>'quota_opponent')::int = 180, 'S2: senza dati 50/50 e quota 1,80: ' || q::text;
  assert q->'p_winrate' = 'null'::jsonb and q->'p_bounty' = 'null'::jsonb and q->'p_bets' = 'null'::jsonb
     and (q->>'l_winrate')::numeric = 0 and (q->>'l_bounty')::numeric = 0 and (q->>'l_bets')::numeric = 0, 'S2: senza dati nessun segnale: ' || q::text;
  -- solo bounty value: 300 su Ann, 0 su Bob (nessuna partita): spinta 0,3·ln(400/100) = 0,42 → 60,25% (da sola: le taglie spostano poco)
  perform pg_temp.as_('Cyr'); perform public.create_bounty(pg_temp.uid('Ann'), 300, null, 'bounty-test-0001');
  q := pg_temp.q(m);
  assert q->>'basis' = 'mix' and (q->>'p_challenger')::numeric = 60.25 and (q->>'p_opponent')::numeric = 39.75, 'S2: solo bounty value → 60,25/39,75: ' || q::text;
  assert (q->>'quota_challenger')::int = 149 and (q->>'quota_opponent')::int = 226, 'S2: quote da bounty 1,49 e 2,26: ' || q::text;
  assert (q->>'bounty_challenger')::int = 300 and (q->>'bounty_opponent')::int = 0, 'S2: taglie mostrate';
  assert (q->>'p_bounty')::numeric = 80.00 and q->'p_winrate' = 'null'::jsonb and (q->>'l_bounty')::numeric = 0.42 and (q->>'l_winrate')::numeric = 0, 'S2: il segnale bounty dice 80% e sposta di 0,42: ' || q::text;
  -- una taglia annullata non conta (solo le attive)
  perform pg_temp.as_('Admin');
  perform public.admin_cancel_bounty((select id from public.bounties where target_id = pg_temp.uid('Ann')), 'prova di annullamento');
  assert pg_temp.q(m)->>'basis' = 'even', 'S2: una taglia annullata non conta';
  -- solo win rate: Ann 6V-0P-2S (70%), Bob 2V-2P-4S (40%): P(Ann) = .7·.6 / (.7·.6 + .4·.3) = 77,78%
  perform pg_temp.addr('Ann', 6, 0, 2); perform pg_temp.addr('Bob', 2, 2, 4);
  q := pg_temp.q(m);
  assert q->>'basis' = 'mix' and (q->>'p_challenger')::numeric = 77.78 and (q->>'p_opponent')::numeric = 22.22, 'S2: solo win rate → 77,78/22,22: ' || q::text;
  assert (q->>'quota_challenger')::int = 115 and (q->>'quota_opponent')::int = 405, 'S2: quote da win rate 1,15 e 4,05: ' || q::text;
  assert (q->>'games_challenger')::int = 8 and (q->>'games_opponent')::int = 8, 'S2: partite mostrate';
  assert (q->>'p_winrate')::numeric = 77.78 and (q->>'l_winrate')::numeric = 1.25 and (q->>'l_bounty')::numeric = 0, 'S2: spinta del win rate 1,25: ' || q::text;
  -- win rate E bounty insieme: la taglia da 300 su Ann si somma al win rate: 1,25 + 0,42 → 84,14%
  perform pg_temp.as_('Cyr'); perform public.create_bounty(pg_temp.uid('Ann'), 300, null, 'bounty-test-0002');
  assert pg_temp.pq(m, 84.14, 106, 567) is null, 'S2: win rate + bounty insieme: ' || coalesce(pg_temp.pq(m, 84.14, 106, 567), '');
  q := pg_temp.q(m);
  assert (q->>'p_winrate')::numeric = 77.78 and (q->>'p_bounty')::numeric = 80.00 and (q->>'l_winrate')::numeric = 1.25 and (q->>'l_bounty')::numeric = 0.42, 'S2: segnali mostrati separati: ' || q::text;
  -- un formato diverso ha statistiche proprie: Edison senza partite → conta solo il bounty value (le taglie non sono per formato)
  mf := pg_temp.mk('Ann', 'Bob', 'pending', 'Edison');
  assert pg_temp.pq(mf, 60.25, 149, 226) is null and pg_temp.q(mf)->'p_winrate' = 'null'::jsonb, 'S2: il win rate è per formato: ' || pg_temp.q(mf)::text;
  -- bet_bounty_smooth conta: con 10000 la stessa taglia da 300 sposta pochissimo (50,22%)
  perform pg_temp.set_('bet_bounty_smooth', 10000);
  assert pg_temp.pq(mf, 50.22, 179, 180) is null, 'S2: smussamento delle taglie alto: ' || pg_temp.q(mf)::text;
  perform pg_temp.set_('bet_bounty_smooth', 100);
  -- uno solo dei due con poche partite: il win rate conta in proporzione alle partite del meno esperto (2 su 3)
  perform pg_temp.addr('Bob', 1, 0, 1);
  assert pg_temp.pq(m, 72.73, 123, 329) is null, 'S2: pochi dati → win rate attenuato: ' || coalesce(pg_temp.pq(m, 72.73, 123, 329), '');
  perform pg_temp.addr('Bob', 0, 0, 0);
  assert pg_temp.pq(m, 60.25, 149, 226) is null and pg_temp.q(m)->'p_winrate' = 'null'::jsonb and (pg_temp.q(m)->>'l_winrate')::numeric = 0, 'S2: zero partite per uno dei due → win rate ignorato: ' || pg_temp.q(m)::text;
  perform pg_temp.addr('Ann', 0, 0, 0);
  assert pg_temp.q(m)->'p_winrate' = 'null'::jsonb, 'S2: zero partite per lo sfidante → win rate ignorato';
  perform pg_temp.addr('Ann', 6, 0, 2);
  perform pg_temp.addr('Bob', 2, 2, 4);
  -- soglia: con bet_min_games = 9 le 8 partite contano 8/9
  perform pg_temp.set_('bet_min_games', 9);
  assert pg_temp.pq(m, 82.19, 109, 505) is null, 'S2: soglia partite minime: ' || coalesce(pg_temp.pq(m, 82.19, 109, 505), '');
  perform pg_temp.set_('bet_min_games', 3);
  -- la probabilità non esce da 5%–95%, la quota non scende sotto 1,05
  perform pg_temp.addr('Fay', 30, 0, 0); perform pg_temp.addr('Gus', 0, 0, 30);
  q := pg_temp.q(pg_temp.mk('Fay', 'Gus'));
  assert (q->>'p_challenger')::numeric = 95.00 and (q->>'quota_challenger')::int = 105 and (q->>'quota_opponent')::int = 1800, 'S2: limiti 5–95% e quota minima 1,05: ' || q::text;
  -- speculare: l'avversario è il super favorito → limiti 5–95% anche per lo sfidante, e quota minima anche per l'avversario
  q := pg_temp.q(pg_temp.mk('Gus', 'Fay'));
  assert (q->>'p_challenger')::numeric = 5.00 and (q->>'quota_challenger')::int = 1800 and (q->>'quota_opponent')::int = 105, 'S2: limiti e quota minima anche per l''avversario: ' || q::text;
  -- le partite di un altro formato non entrano nel win rate
  perform pg_temp.addr('Ann', 20, 0, 0, 'Edison');
  perform pg_temp.addr('Bob', 0, 0, 20, 'Edison');
  assert pg_temp.pq(m, 84.14, 106, 567) is null and (pg_temp.q(m)->>'games_challenger')::int = 8, 'S2: il win rate Advanced non cambia con le partite Edison';
  assert pg_temp.pq(mf, 95.00, 105, 1800) is null and (pg_temp.q(mf)->>'games_challenger')::int = 20, 'S2: nel formato Edison contano le partite Edison: ' || pg_temp.q(mf)::text;
  perform pg_temp.addr('Ann', 0, 0, 0, 'Edison'); perform pg_temp.addr('Bob', 0, 0, 0, 'Edison');
  -- margine: 0 → quota 2,00; oltre 50 viene limitato a 50 (quota 1,05 al minimo)
  perform pg_temp.set_('bet_margin_pct', 0);
  assert (pg_temp.q(pg_temp.mk('Cyr', 'Dia'))->>'quota_challenger')::int = 200, 'S2: margine 0';
  perform pg_temp.set_('bet_margin_pct', 90);
  assert (pg_temp.q(pg_temp.mk('Cyr', 'Dia'))->>'quota_challenger')::int = 105, 'S2: margine limitato a 50%';
  assert (pg_temp.q(pg_temp.mk('Fay', 'Gus'))->>'quota_opponent')::int = 1000, 'S2: margine 50% su un 5%: quota 10,00';
  perform pg_temp.set_('bet_margin_pct', 10);
  -- i pareggi contano mezza vittoria, per entrambi: due record uguali con pareggi → 50/50 esatto
  perform pg_temp.addr('Cyr', 4, 2, 2); perform pg_temp.addr('Dia', 4, 2, 2);
  q := pg_temp.q(pg_temp.mk('Cyr', 'Dia'));
  assert q->>'basis' = 'mix' and (q->>'p_challenger')::numeric = 50.00 and (q->>'quota_challenger')::int = 180, 'S2: record uguali con pareggi → 50/50: ' || q::text;
  -- una taglia sull'avversario lo rende favorito: spinta 0,3·ln(100/200) = −0,21 → Povero 44,82%; annullata non conta
  perform pg_temp.as_('Cyr'); perform public.create_bounty(pg_temp.uid('Eve'), 100, null, 'bounty-test-0003');
  mp := pg_temp.mk('Povero', 'Eve');
  assert pg_temp.pq(mp, 44.82, 200, 163) is null, 'S2: taglia sull''avversario: ' || coalesce(pg_temp.pq(mp, 44.82, 200, 163), '');
  perform pg_temp.as_('Admin');
  perform public.admin_cancel_bounty((select id from public.bounties where target_id = pg_temp.uid('Eve') and status = 'active'), 'prova di annullamento');
  assert pg_temp.q(pg_temp.mk('Povero', 'Eve'))->>'basis' = 'even', 'S2: taglia annullata sull''avversario non conta';
  -- il margine rende ogni puntata «a valore atteso negativo»: P·quota < 1 per ogni sfida di prova
  assert not exists (select 1 from public.ladder_matches l, lateral (select public._bet_quote(l) q) z
    where (z.q->>'p_challenger')::numeric / 100 * (z.q->>'quota_challenger')::numeric / 100 >= 1
       or (z.q->>'p_opponent')::numeric / 100 * (z.q->>'quota_opponent')::numeric / 100 >= 1), 'S2: nessuna quota a valore atteso positivo';
  -- la taglia su Ann viene tolta: dalle prove che seguono Ann/Bob contano solo per win rate (77,78% → quota 1,15), come in origine
  perform public.admin_cancel_bounty((select id from public.bounties where target_id = pg_temp.uid('Ann') and status = 'active'), 'prova: si riparte dal solo win rate');
  assert pg_temp.pq(m, 77.78, 115, 405) is null, 'S2: base per le prove seguenti: ' || coalesce(pg_temp.pq(m, 77.78, 115, 405), '');
  insert into t_log (msg) values ('OK S2 — quote: win rate, bounty value e scommesse insieme, formati, soglie, limiti, margine');
end $$;

create temp table ctx (k text primary key, v uuid);
-- ---------------------------------------------------------------- S3 puntare: regole
do $$
declare m uuid; mm uuid; r jsonb; e text; b0 integer;
begin
  m := pg_temp.mk('Ann', 'Bob');                      -- ricordo: Ann ha 70%, Bob 40%, nessuna taglia: solo win rate
  insert into ctx values ('m1', m);
  b0 := pg_temp.bal('Cyr');
  perform pg_temp.as_('Cyr'); r := public.place_bet(m, pg_temp.uid('Ann'), 100, null, 'richiesta-fissa-1');
  assert (r->>'quota')::int = 115 and (r->>'payout_if_win')::int = 115 and (r->>'already')::boolean = false, 'S3: puntata riuscita: ' || r::text;
  assert pg_temp.bal('Cyr') = b0 - 100, 'S3: puntata addebitata';
  assert (select count(*) from public.ledger_entries where user_id = pg_temp.uid('Cyr') and kind = 'bet_stake' and amount = -100 and ref_type = 'bet') = 1, 'S3: riga nel registro';
  assert (select quota from public.bets where user_id = pg_temp.uid('Cyr') and match_id = m) = 115 and (select basis from public.bets where user_id = pg_temp.uid('Cyr') and match_id = m) = 'mix'
     and (select prob_pct from public.bets where user_id = pg_temp.uid('Cyr') and match_id = m) = 77.78, 'S3: quota e probabilità fissate sulla scommessa';
  -- la quota resta quella della puntata anche se poi i dati cambiano
  perform pg_temp.addr('Ann', 1, 0, 7);
  assert (select quota from public.bets where user_id = pg_temp.uid('Cyr') and match_id = m) = 115, 'S3: la quota non cambia dopo';
  perform pg_temp.addr('Ann', 6, 0, 2);
  -- stessa richiesta ripetuta: nessun secondo addebito
  e := pg_temp.err_as('Dia', format('select public.place_bet(%L, %L, 60, null, ''richiesta-fissa-1'')', m, pg_temp.uid('Bob')));
  assert e is null, 'S3: la stessa richiesta di un altro utente è una richiesta nuova: ' || coalesce(e, '');
  perform pg_temp.as_('Cyr');
  assert (public.place_bet(m, pg_temp.uid('Ann'), 100, null, 'richiesta-fissa-1')->>'already')::boolean = true, 'S3: richiesta ripetuta riconosciuta';
  assert (select count(*) from public.bets where user_id = pg_temp.uid('Cyr') and match_id = m) = 1 and pg_temp.bal('Cyr') = b0 - 100, 'S3: nessun doppio addebito';
  -- regole
  assert pg_temp.berr('Ann', m, 'Ann', 50) like '%che giochi tu%', 'S3: chi gioca non scommette (sfidante)';
  assert pg_temp.berr('Bob', m, 'Bob', 50) like '%che giochi tu%', 'S3: chi gioca non scommette (sfidato)';
  assert pg_temp.berr('Eve', m, 'Cyr', 50) like '%uno dei due sfidanti%', 'S3: si punta solo su uno dei due';
  assert pg_temp.berr('Eve', m, 'Bob', 9) like '%inferiore al minimo%', 'S3: puntata minima';
  assert pg_temp.berr('Eve', m, 'Bob', 201) like '%superiore al massimo%', 'S3: puntata massima';
  assert pg_temp.berr('Cyr', m, 'Bob', 50) like '%già scommesso%', 'S3: una sola scommessa per sfida (anche sull''altro)';
  assert pg_temp.berr('Povero', m, 'Bob', 50) like '%Saldo insufficiente%' and pg_temp.bal('Povero') = 20, 'S3: saldo insufficiente, niente cambia';
  assert pg_temp.berr('Eve', m, 'Bob', 50, 600) like '%quota è cambiata%', 'S3: la quota richiesta non c''è più';
  assert pg_temp.err_as('Eve', format('select public.place_bet(%L, %L, 50, null, ''corta'')', m, pg_temp.uid('Bob'))) like '%Richiesta non valida%', 'S3: richiesta senza identificativo valido';
  assert pg_temp.berr('Eve', gen_random_uuid(), 'Bob', 50) like '%Sfida non trovata%', 'S3: sfida inesistente';
  assert pg_temp.berr('Eve', m, null, 50) like '%uno dei due sfidanti%', 'S3: nessuna scelta';
  -- account sospeso
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Eve'), true, 'prova di sospensione');
  assert pg_temp.berr('Eve', m, 'Bob', 50) like '%sospeso%', 'S3: account sospeso';
  perform pg_temp.as_('Admin'); perform public.admin_set_suspended(pg_temp.uid('Eve'), false, 'fine prova');
  -- scommesse spente / modulo spento
  perform pg_temp.set_('bet_enabled', 0);
  assert pg_temp.berr('Eve', m, 'Bob', 50) like '%spente%', 'S3: scommesse spente';
  perform pg_temp.set_('bet_enabled', 1);
  perform pg_temp.set_('module_ladder', 0);
  assert pg_temp.berr('Eve', m, 'Bob', 50) = 'Modulo non attivo' and pg_temp.err_as('Eve', 'select public.bet_markets()') = 'Modulo non attivo', 'S3: Ladder spenta, niente scommesse';
  perform pg_temp.set_('module_ladder', 1);
  -- limite di scommesse aperte
  perform pg_temp.set_('bet_max_open', 1);
  mm := pg_temp.mk('Fay', 'Gus');
  assert pg_temp.berr('Cyr', mm, 'Fay', 50) like '%1 scommesse aperte%', 'S3: massimo di scommesse aperte';
  perform pg_temp.set_('bet_max_open', 50);
  assert pg_temp.berr('Cyr', mm, 'Fay', 50) is null, 'S3: sotto il limite si può';
  -- finestra di puntata
  assert pg_temp.berr('Eve', pg_temp.mk('Fay', 'Gus', 'reported'), 'Fay', 50) like '%chiuse%', 'S3: chiusa se il risultato è stato inviato';
  assert pg_temp.berr('Eve', pg_temp.mk('Fay', 'Gus', 'disputed'), 'Fay', 50) like '%chiuse%', 'S3: chiusa se contestata';
  assert pg_temp.berr('Eve', pg_temp.mk('Fay', 'Gus', 'closed'), 'Fay', 50) like '%chiuse%', 'S3: chiusa se conclusa';
  assert pg_temp.berr('Eve', pg_temp.mk('Fay', 'Gus', 'declined'), 'Fay', 50) like '%chiuse%', 'S3: chiusa se rifiutata';
  mm := pg_temp.mk('Fay', 'Gus', 'accepted');
  assert exists (select 1 from public.bet_windows where match_id = mm), 'S3: l''accettazione registra l''orario';
  assert pg_temp.berr('Eve', mm, 'Fay', 50) is null, 'S3: appena accettata si può ancora';
  mm := pg_temp.mk('Fay', 'Gus');
  perform pg_temp.mst(mm, 'accepted');
  assert exists (select 1 from public.bet_windows where match_id = mm), 'S3: accettare una sfida in attesa registra l''orario';
  update public.bet_windows set accepted_at = clock_timestamp() - interval '11 minutes' where match_id = mm;
  assert pg_temp.berr('Eve', mm, 'Fay', 50) like '%chiuse%', 'S3: chiusa dopo 10 minuti';
  update public.bet_windows set accepted_at = clock_timestamp() - interval '9 minutes' where match_id = mm;
  assert pg_temp.berr('Eve', mm, 'Fay', 50) is null, 'S3: aperta a 9 minuti';
  mm := pg_temp.mk('Fay', 'Gus', 'accepted'); delete from public.bet_windows where match_id = mm;
  assert pg_temp.berr('Eve', mm, 'Fay', 50) like '%chiuse%', 'S3: sfida accettata prima della migrazione: chiusa';
  perform pg_temp.set_('bet_close_minutes', 0);
  assert pg_temp.berr('Eve', mm, 'Fay', 50) is null, 'S3: con 0 minuti si punta fino al risultato';
  assert pg_temp.berr('Eve', pg_temp.mk('Fay', 'Gus', 'reported'), 'Fay', 50) like '%chiuse%', 'S3: con 0 minuti, chiusa se il risultato è stato inviato';
  assert pg_temp.berr('Eve', pg_temp.mk('Fay', 'Gus', 'disputed'), 'Fay', 50) like '%chiuse%', 'S3: con 0 minuti, chiusa se contestata';
  assert pg_temp.berr('Eve', pg_temp.mk('Fay', 'Gus', 'closed'), 'Fay', 50) like '%chiuse%', 'S3: con 0 minuti, chiusa se conclusa';
  perform pg_temp.set_('bet_close_minutes', 10);
  assert pg_temp.inv() = 0, 'S3: saldi = registro';
  insert into t_log (msg) values ('OK S3 — regole di puntata, ripetizioni, limiti, finestra di tempo');
end $$;

-- ---------------------------------------------------------------- S4 liquidazione alla chiusura
do $$
declare m uuid := (select v from ctx where k = 'm1'); cy integer := pg_temp.bal('Cyr'); di integer; ev integer; r jsonb; lg integer;
begin
  -- Dia ha già puntato 60 su Bob nello scenario S3, DOPO i 100 di Cyr su Ann: la quota di Bob è salita da 4,05 a 5,05 (82,20% Ann)
  assert (select quota from public.bets where user_id = pg_temp.uid('Dia') and match_id = m) = 505 and (select stake from public.bets where user_id = pg_temp.uid('Dia') and match_id = m) = 60, 'S4: scommessa di Dia';
  perform pg_temp.bet('Eve', m, 'Ann', 30);                      -- con 100 su Ann e 60 su Bob la quota di Ann è 1,13 → 33
  di := pg_temp.bal('Dia'); ev := pg_temp.bal('Eve');
  -- finché la sfida non si chiude, nulla si muove; anche il risultato inviato non liquida
  perform pg_temp.mst(m, 'accepted'); perform pg_temp.mst(m, 'reported', 'challenger');
  assert pg_temp.bst('Cyr', m) = 'open' and pg_temp.bal('Cyr') = cy, 'S4: con il risultato solo inviato resta aperta';
  lg := (select count(*) from public.ledger_entries);
  -- chiusura: vince Ann
  perform pg_temp.mst(m, 'closed', 'challenger');
  assert pg_temp.bst('Cyr', m) = 'won' and pg_temp.bst('Eve', m) = 'won' and pg_temp.bst('Dia', m) = 'lost', 'S4: stati dopo la chiusura';
  assert pg_temp.bal('Cyr') = cy + 115 and pg_temp.bal('Eve') = ev + 33 and pg_temp.bal('Dia') = di, 'S4: vincite accreditate, perdita non restituita (Cy +115, Eve +33, Di +0)';
  assert (select count(*) from public.ledger_entries where kind = 'bet_payout') = 2 and (select count(*) from public.ledger_entries) = lg + 2, 'S4: due sole righe di vincita';
  assert (select amount from public.ledger_entries where user_id = pg_temp.uid('Cyr') and kind = 'bet_payout') = 115
     and (select balance_after from public.ledger_entries where user_id = pg_temp.uid('Cyr') and kind = 'bet_payout') = cy + 115, 'S4: riga di registro con saldo dopo';
  assert pg_temp.bret('Cyr', m) = 115 and pg_temp.bret('Dia', m) = 0, 'S4: restituito';
  assert (select count(*) from public.audit_logs where action = 'bet_settle' and entity_id in (select id::text from public.bets where match_id = m)) = 3, 'S4: audit di ogni liquidazione';
  -- ripetere non cambia nulla
  assert public._bet_reconcile(m) = 0, 'S4: seconda liquidazione = nessuna modifica';
  perform pg_temp.as_('Cyr'); assert public.bet_sync() = 0, 'S4: bet_sync non trova niente';
  assert pg_temp.inv() = 0, 'S4: saldi = registro';
  insert into t_log (msg) values ('OK S4 — vittoria e sconfitta liquidate alla chiusura, una volta sola');
end $$;

-- ---------------------------------------------------------------- S5 pareggio e sfide che non si giocano
do $$
declare m uuid; st text; cy integer; b0 integer;
begin
  -- pareggio: la puntata torna intera
  m := pg_temp.mk('Fay', 'Gus', 'accepted');
  b0 := pg_temp.bal('Cyr'); perform pg_temp.bet('Cyr', m, 'Fay', 80); perform pg_temp.bet('Dia', m, 'Gus', 40);
  perform pg_temp.mst(m, 'closed', 'draw');
  assert pg_temp.bst('Cyr', m) = 'refunded' and pg_temp.bst('Dia', m) = 'refunded' and pg_temp.bal('Cyr') = b0, 'S5: pareggio = rimborso';
  assert (select count(*) from public.ledger_entries where kind = 'bet_refund' and ref_id in (select id from public.bets where match_id = m)) = 2, 'S5: righe di rimborso';
  -- rifiutata, annullata, scaduta
  foreach st in array array['declined','cancelled','expired'] loop
    m := pg_temp.mk('Fay', 'Gus');
    b0 := pg_temp.bal('Cyr'); perform pg_temp.bet('Cyr', m, 'Fay', 60);
    assert pg_temp.bal('Cyr') = b0 - 60, 'S5: ' || st || ': puntata addebitata';
    perform pg_temp.mst(m, st);
    assert pg_temp.bst('Cyr', m) = 'refunded' and pg_temp.bal('Cyr') = b0, 'S5: ' || st || ': puntata restituita';
    assert public._bet_reconcile(m) = 0, 'S5: ' || st || ': una volta sola';
  end loop;
  -- annullata dall'amministratore prima di giocare (da accettata)
  m := pg_temp.mk('Fay', 'Gus', 'accepted'); b0 := pg_temp.bal('Dia'); perform pg_temp.bet('Dia', m, 'Gus', 70);
  perform pg_temp.mst(m, 'voided');
  assert pg_temp.bst('Dia', m) = 'refunded' and pg_temp.bal('Dia') = b0, 'S5: sfida annullata = rimborso';
  -- le sfide ancora aperte non liquidano
  m := pg_temp.mk('Fay', 'Gus', 'accepted'); perform pg_temp.bet('Cyr', m, 'Gus', 20);
  perform pg_temp.mst(m, 'disputed', 'challenger');
  assert pg_temp.bst('Cyr', m) = 'open', 'S5: contestata = ancora aperta';
  perform pg_temp.mst(m, 'closed', 'opponent');
  assert pg_temp.bst('Cyr', m) = 'won', 'S5: la contestazione si chiude e la scommessa viene liquidata';
  assert pg_temp.inv() = 0, 'S5: saldi = registro';
  insert into t_log (msg) values ('OK S5 — pareggio, rifiutata, annullata, scaduta, contestata');
end $$;

-- ---------------------------------------------------------------- S6 correzione del risultato dopo la chiusura
do $$
declare m uuid; cy integer; di integer; ev integer; b0cy integer; b0di integer; b0ev integer;
begin
  perform pg_temp.addr('Fay', 0, 0, 0); perform pg_temp.addr('Gus', 0, 0, 0);
  m := pg_temp.mk('Fay', 'Gus', 'accepted', 'Edison');            -- Edison senza dati e senza taglie: le quote seguono le puntate già presenti (Cy 1,80, Di 2,08 con 100 su Fay, Eve 1,80 a 100 pari)
  b0cy := pg_temp.bal('Cyr'); b0di := pg_temp.bal('Dia'); b0ev := pg_temp.bal('Eve');
  perform pg_temp.bet('Cyr', m, 'Fay', 100); perform pg_temp.bet('Dia', m, 'Gus', 100); perform pg_temp.bet('Eve', m, 'Fay', 50);
  perform pg_temp.mst(m, 'closed', 'challenger');                  -- Cy +180, Eve +90, Di perde
  assert pg_temp.bal('Cyr') = b0cy + 80 and pg_temp.bal('Dia') = b0di - 100 and pg_temp.bal('Eve') = b0ev + 40, 'S6: prima della correzione';
  -- l'admin corregge: vince Gus (Di incassa 100 × 2,08)
  perform pg_temp.mst(m, 'closed', 'opponent');
  assert pg_temp.bst('Cyr', m) = 'lost' and pg_temp.bst('Dia', m) = 'won' and pg_temp.bst('Eve', m) = 'lost', 'S6: stati dopo la correzione';
  assert pg_temp.bal('Cyr') = b0cy - 100 and pg_temp.bal('Dia') = b0di + 108 and pg_temp.bal('Eve') = b0ev - 50, 'S6: ricalcolo: tolto il pagato in più, pagato il mancante';
  assert (select count(*) from public.ledger_entries where kind = 'bet_reversal' and ref_id in (select id from public.bets where match_id = m)) = 2, 'S6: due righe di correzione';
  assert public._bet_reconcile(m) = 0, 'S6: correzione applicata una volta sola';
  -- stessa correzione ripetuta (risultato invariato): niente
  perform pg_temp.mst(m, 'closed', 'opponent');
  assert pg_temp.bal('Cyr') = b0cy - 100 and pg_temp.bal('Dia') = b0di + 108, 'S6: riscrivere lo stesso risultato non cambia i saldi';
  -- ... e diventa pareggio: tutte restituite
  perform pg_temp.mst(m, 'closed', 'draw');
  assert pg_temp.bst('Cyr', m) = 'refunded' and pg_temp.bst('Dia', m) = 'refunded' and pg_temp.bst('Eve', m) = 'refunded', 'S6: pareggio dopo la correzione';
  assert pg_temp.bal('Cyr') = b0cy and pg_temp.bal('Dia') = b0di and pg_temp.bal('Eve') = b0ev, 'S6: ognuno ha di nuovo il suo saldo di partenza';
  -- ... e poi la sfida viene annullata dall'admin: rimborso (nessun doppio rimborso)
  perform pg_temp.mst(m, 'voided');
  assert pg_temp.bst('Cyr', m) = 'refunded' and pg_temp.bal('Cyr') = b0cy and pg_temp.bal('Dia') = b0di, 'S6: annullamento dopo il pareggio: invariato';
  assert pg_temp.inv() = 0, 'S6: saldi = registro';
  -- annullamento di una sfida vinta: si toglie la vincita e si restituisce la puntata
  m := pg_temp.mk('Fay', 'Gus', 'accepted', 'Edison'); b0cy := pg_temp.bal('Cyr');
  perform pg_temp.bet('Cyr', m, 'Fay', 100); perform pg_temp.mst(m, 'closed', 'challenger');
  assert pg_temp.bal('Cyr') = b0cy + 80, 'S6: vinta';
  perform pg_temp.mst(m, 'voided');
  assert pg_temp.bal('Cyr') = b0cy and pg_temp.bst('Cyr', m) = 'refunded', 'S6: sfida annullata dopo la vittoria: si torna al punto di partenza';
  -- la correzione può toccare soltanto il risultato, senza riscrivere lo stato
  m := pg_temp.mk('Fay', 'Gus', 'accepted', 'Edison'); b0cy := pg_temp.bal('Cyr');
  perform pg_temp.bet('Cyr', m, 'Fay', 100); perform pg_temp.mst(m, 'closed', 'challenger');
  assert pg_temp.bal('Cyr') = b0cy + 80, 'S6: vinta';
  perform set_config('app.ladder_correct', 'on', true);
  update public.ladder_matches set reported_result = 'opponent' where id = m;
  perform set_config('app.ladder_correct', 'off', true);
  assert pg_temp.bst('Cyr', m) = 'lost' and pg_temp.bal('Cyr') = b0cy - 100, 'S6: ricalcolo anche se cambia solo il risultato';
  insert into t_log (msg) values ('OK S6 — correzione del risultato, pareggio, annullamento dopo la chiusura');
end $$;

-- ---------------------------------------------------------------- S7 vincita già spesa: saldo mai negativo
do $$
declare m uuid; b0 integer; wo integer;
begin
  m := pg_temp.mk('Fay', 'Gus', 'accepted', 'Edison'); b0 := pg_temp.bal('Cyr');
  perform pg_temp.bet('Cyr', m, 'Fay', 100); perform pg_temp.mst(m, 'closed', 'challenger');       -- Cy: +180 → b0 + 80
  perform pg_temp.fund('Cyr', 30);                                                                  -- spende quasi tutto: restano 30 BC
  perform pg_temp.mst(m, 'closed', 'opponent');                                                    -- avrebbe dovuto restituire 180, ne ha 30
  assert pg_temp.bal('Cyr') = 0, 'S7: si recupera solo fino al saldo disponibile';
  assert (select written_off from public.bets where user_id = pg_temp.uid('Cyr') and match_id = m) = 150 and pg_temp.bst('Cyr', m) = 'lost', 'S7: il non recuperato è registrato (150)';
  assert (select amount from public.ledger_entries where user_id = pg_temp.uid('Cyr') and kind = 'bet_reversal' order by created_at desc limit 1) = -30, 'S7: riga di correzione di 30';
  assert public._bet_reconcile(m) = 0 and pg_temp.bal('Cyr') = 0, 'S7: non si riprende altro dopo';
  assert pg_temp.inv() = 0 and (select min(balance) from public.wallets) >= 0, 'S7: nessun saldo negativo';
  -- saldo a zero: nessuna riga di correzione
  m := pg_temp.mk('Fay', 'Gus', 'accepted', 'Edison'); perform pg_temp.fund('Cyr', 500);
  perform pg_temp.bet('Cyr', m, 'Fay', 100); perform pg_temp.mst(m, 'closed', 'challenger'); perform pg_temp.fund('Cyr', 0);
  b0 := (select count(*) from public.ledger_entries where kind = 'bet_reversal');
  perform pg_temp.mst(m, 'closed', 'opponent');
  assert (select count(*) from public.ledger_entries where kind = 'bet_reversal') = b0 and pg_temp.bal('Cyr') = 0
     and (select written_off from public.bets where user_id = pg_temp.uid('Cyr') and match_id = m) = 180, 'S7: saldo a zero: nessuna riga e 180 non recuperati';
  perform pg_temp.fund('Cyr', 1000);
  insert into t_log (msg) values ('OK S7 — vincita già spesa: saldo mai negativo, il non recuperato resta scritto');
end $$;

-- ---------------------------------------------------------------- S8 la chiusura non fallisce mai per colpa delle scommesse
do $$
declare m uuid; b0 integer; n integer;
begin
  m := pg_temp.mk('Fay', 'Gus', 'accepted', 'Edison'); b0 := pg_temp.bal('Dia');
  perform pg_temp.bet('Dia', m, 'Gus', 50);
  create function pg_temp.boom() returns trigger language plpgsql as $f$ begin raise exception 'guasto simulato'; end $f$;
  create trigger boom before update on public.bets for each row execute function pg_temp.boom();
  perform pg_temp.mst(m, 'closed', 'opponent');                  -- non deve fallire
  assert (select status from public.ladder_matches where id = m) = 'closed', 'S8: la sfida si chiude lo stesso';
  assert pg_temp.bst('Dia', m) = 'open' and pg_temp.bal('Dia') = b0 - 50, 'S8: scommessa ancora aperta, nessun movimento a metà';
  drop trigger boom on public.bets;
  perform pg_temp.as_('Eve'); n := public.bet_sync();
  assert n = 1 and pg_temp.bst('Dia', m) = 'won' and pg_temp.bal('Dia') = b0 - 50 + 90, 'S8: bet_sync liquida dopo: ' || n;
  assert pg_temp.inv() = 0, 'S8: saldi = registro';
  insert into t_log (msg) values ('OK S8 — guasto nella liquidazione: la sfida si chiude, bet_sync recupera');
end $$;

-- ---------------------------------------------------------------- S9 visibilità, elenco sfide, le mie scommesse
do $$
declare m uuid; mk jsonb; r jsonb; x jsonb;
begin
  m := pg_temp.mk('Ann', 'Gus', 'accepted');
  perform pg_temp.bet('Cyr', m, 'Ann', 60);
  assert pg_temp.rows_as('Cyr', 'select * from public.bets') = (select count(*) from public.bets where user_id = pg_temp.uid('Cyr')), 'S9: si vedono solo le proprie scommesse';
  assert pg_temp.rows_as('Dia', format('select * from public.bets where match_id = %L', m)) = 0, 'S9: gli altri non vedono la mia scommessa';
  assert pg_temp.rows_as('Ann', format('select * from public.bets where match_id = %L', m)) = 0, 'S9: nemmeno i giocatori della sfida';
  assert pg_temp.rows_as('Admin', 'select * from public.bets') = (select count(*) from public.bets), 'S9: l''amministratore vede tutto';
  perform pg_temp.as_('Dia');
  r := public.bet_markets();
  x := (select e from jsonb_array_elements(r) e where e->>'id' = m::text);
  assert x is not null and (x->>'open')::boolean and (x->>'can_bet')::boolean and x->'mine' = 'null'::jsonb, 'S9: elenco: sfida aperta, Di può puntare, nessuna sua scommessa: ' || coalesce(x::text, 'assente');
  assert x->>'challenger_name' = 'Ann' and x->>'opponent_name' = 'Gus' and x->'quote'->>'basis' is not null and x->>'closes_at' is not null, 'S9: nomi, quote e orario di chiusura';
  perform pg_temp.as_('Cyr'); r := public.bet_markets();
  x := (select e from jsonb_array_elements(r) e where e->>'id' = m::text);
  assert (x->'mine'->>'stake')::int = 60, 'S9: la mia scommessa compare sulla sfida';
  perform pg_temp.as_('Ann'); r := public.bet_markets();
  x := (select e from jsonb_array_elements(r) e where e->>'id' = m::text);
  assert not (x->>'can_bet')::boolean, 'S9: chi gioca vede che non può puntare';
  assert not exists (select 1 from jsonb_array_elements(r) e where e->>'status' not in ('pending','accepted')), 'S9: solo sfide aperte';
  -- le sfide con la finestra chiusa compaiono ma non sono puntabili
  update public.bet_windows set accepted_at = clock_timestamp() - interval '30 minutes' where match_id = m;
  perform pg_temp.as_('Dia'); r := public.bet_markets();
  x := (select e from jsonb_array_elements(r) e where e->>'id' = m::text);
  assert not (x->>'open')::boolean, 'S9: finestra chiusa → open = false';
  -- le mie scommesse
  perform pg_temp.as_('Cyr'); r := public.bet_mine();
  assert jsonb_array_length(r) = (select count(*) from public.bets where user_id = pg_temp.uid('Cyr')), 'S9: bet_mine = le mie';
  assert not exists (select 1 from jsonb_array_elements(r) e where e->>'id' not in (select id::text from public.bets where user_id = pg_temp.uid('Cyr'))), 'S9: solo mie';
  x := (select e from jsonb_array_elements(r) e where e->>'match' = m::text);
  assert x->>'pick_name' = 'Ann' and x->>'status' = 'open' and x->>'challenger_name' = 'Ann' and x->>'opponent_name' = 'Gus', 'S9: dettagli della scommessa';
  assert pg_temp.err_as('Cyr', 'select public.bet_admin_stats()') like '%Permessi insufficienti%', 'S9: statistiche solo admin';
  perform pg_temp.mst(m, 'cancelled');
  insert into t_log (msg) values ('OK S9 — visibilità, elenco delle sfide, le mie scommesse');
end $$;

-- ---------------------------------------------------------------- S10 isolamento e contabilità
do $$
declare s jsonb; st text; m uuid; before_b text; lm_before text; lm_after text;
begin
  before_b := pg_temp.bounty_state();
  m := pg_temp.mk('Ann', 'Gus', 'accepted'); perform pg_temp.bet('Eve', m, 'Gus', 100);
  select md5(string_agg(t::text, ',' order by id)) into lm_before from (select id, challenger_id, opponent_id, format, kind, status, reported_result from public.ladder_matches where id <> m) t;
  perform pg_temp.mst(m, 'closed', 'opponent');
  select md5(string_agg(t::text, ',' order by id)) into lm_after from (select id, challenger_id, opponent_id, format, kind, status, reported_result from public.ladder_matches where id <> m) t;
  assert lm_before = lm_after, 'S10: le altre sfide non cambiano';
  assert (select status from public.ladder_matches where id = m) = 'closed' and (select reported_result from public.ladder_matches where id = m) = 'opponent', 'S10: la sfida chiusa è quella della Ladder, intatta';
  assert pg_temp.bounty_state() = before_b, 'S10: taglie e riscossioni non toccate dalle scommesse';
  assert pg_temp.inv() = 0, 'S10: ogni saldo coincide con il registro';
  -- contabilità: stake − restituito = incasso della casa sulle liquidate; le aperte tengono la puntata bloccata
  perform pg_temp.as_('Admin'); s := public.bet_admin_stats();
  assert (s->>'bets_total')::int = (select count(*) from public.bets) and (s->>'staked_total')::int = (select sum(stake) from public.bets)
     and (s->>'returned_total')::int = (select sum(returned) from public.bets)
     and (s->>'open_count')::int = (select count(*) from public.bets where status = 'open')
     and (s->>'open_stake')::int = (select coalesce(sum(stake), 0) from public.bets where status = 'open'), 'S10: statistiche admin = somme della tabella: ' || s::text;
  assert (s->>'house_net')::int = (select sum(stake) - sum(returned) from public.bets where status <> 'open'), 'S10: incasso della casa';
  -- il registro: tutto ciò che le scommesse hanno mosso = restituito + non recuperato (rimasto all'utente) − puntato
  assert (select coalesce(sum(amount), 0) from public.ledger_entries where kind in ('bet_stake','bet_payout','bet_refund','bet_reversal'))
       = (select sum(returned) + sum(written_off) - sum(stake) from public.bets), 'S10: registro = restituito + non recuperato − puntato';
  insert into t_log (msg) values ('OK S10 — isolamento da Ladder e taglie, saldi = registro, statistiche');
end $$;

-- ---------------------------------------------------------------- S11 le scommesse già presenti entrano nella quota (da sole, con le taglie, con il win rate)
do $$
declare m uuid; m2 uuid; m3 uuid; m4 uuid; q jsonb; r jsonb; x jsonb; bc0 integer; bd0 integer; pb0 numeric;
begin
  perform pg_temp.set_('bet_pool_smooth', 100);
  assert (select value_int from public.system_settings where key = 'bet_pool_smooth') = 100, 'S11: impostazione bet_pool_smooth';
  bc0 := pg_temp.bal('Cyr'); bd0 := pg_temp.bal('Dia');
  -- 1) nessuna scommessa, nessuna taglia, nessun win rate: alla pari
  m := pg_temp.mk('Povero', 'Eve');
  q := pg_temp.q(m);
  assert q->>'basis' = 'even' and (q->>'quota_challenger')::int = 180 and (q->>'pool_challenger')::int = 0 and (q->>'pool_opponent')::int = 0, 'S11: all''inizio alla pari: ' || q::text;
  -- 2) il primo scommettitore trova 50/50 e puntando sposta la quota: spinta 0,4·ln(300/100) = 0,44 → Povero 60,81%
  r := pg_temp.bet('Cyr', m, 'Povero', 200);
  assert (r->>'quota')::int = 180 and r->>'basis' = 'even', 'S11: il primo trova 1,80: ' || r::text;
  q := pg_temp.q(m);
  assert q->>'basis' = 'mix' and (q->>'p_bets')::numeric = 75.00 and (q->>'l_bets')::numeric = 0.44 and (q->>'p_challenger')::numeric = 60.81 and (q->>'p_opponent')::numeric = 39.19
     and (q->>'quota_challenger')::int = 147 and (q->>'quota_opponent')::int = 229 and (q->>'pool_challenger')::int = 200 and (q->>'pool_opponent')::int = 0,
     'S11: con 200 su Povero: 60,81/39,19, quote 1,47 e 2,29: ' || q::text;
  -- 3) chi punta sull'altro trova la quota alta; poi la quota si riequilibra: 200 contro 100 → Povero 54,05%
  r := pg_temp.bet('Dia', m, 'Eve', 100);
  assert (r->>'quota')::int = 229 and r->>'basis' = 'mix', 'S11: Dia trova 2,29: ' || r::text;
  assert (select quota from public.bets where user_id = pg_temp.uid('Dia') and match_id = m) = 229
     and (select basis from public.bets where user_id = pg_temp.uid('Dia') and match_id = m) = 'mix'
     and (select prob_pct from public.bets where user_id = pg_temp.uid('Dia') and match_id = m) = 39.19, 'S11: quota, criterio e probabilità fissati sulla scommessa';
  q := pg_temp.q(m);
  assert (q->>'p_challenger')::numeric = 54.05 and (q->>'quota_challenger')::int = 166 and (q->>'quota_opponent')::int = 195, 'S11: riequilibrio 54,05/45,95: ' || q::text;
  -- più soldi su un duellante non fanno mai salire la sua quota: 200 su Povero hanno portato la sua quota da 1,80 a 1,47; i 100 su Eve la riportano a 1,66
  assert (select quota from public.bets where user_id = pg_temp.uid('Cyr') and match_id = m) = 180, 'S11: la quota del primo non cambia';
  -- 4) l'impostazione conta: con un valore enorme le puntate spostano pochissimo
  perform pg_temp.set_('bet_pool_smooth', 10000);
  q := pg_temp.q(m);
  assert (q->>'p_challenger')::numeric = 50.10, 'S11: smussamento alto → quasi 50/50: ' || q::text;
  perform pg_temp.set_('bet_pool_smooth', 100);
  -- 5) la vincita usa la quota fissata alla puntata: Eve vince → Dia incassa 100 × 2,29 = 229, Cyr perde
  perform pg_temp.mst(m, 'closed', 'opponent');
  assert pg_temp.bst('Dia', m) = 'won' and pg_temp.bret('Dia', m) = 229 and pg_temp.bal('Dia') = bd0 + 129, 'S11: vincita a quota 2,29';
  assert pg_temp.bst('Cyr', m) = 'lost' and pg_temp.bal('Cyr') = bc0 - 200, 'S11: sconfitta';
  -- 6) con una taglia presente contano insieme la taglia e le scommesse; tolta la taglia resta solo il segnale delle scommesse
  m2 := pg_temp.mk('Povero', 'Eve');
  perform pg_temp.bet('Cyr', m2, 'Povero', 100);
  assert pg_temp.pq(m2, 56.89, 158, 208) is null, 'S11: con 100 su Povero e senza taglie: 56,89%: ' || pg_temp.q(m2)::text;
  perform pg_temp.as_('Dia'); perform public.create_bounty(pg_temp.uid('Eve'), 300, null, 'bounty-test-s11-01');
  q := pg_temp.q(m2);
  assert pg_temp.pq(m2, 46.54, 193, 168) is null and (q->>'pool_challenger')::int = 100, 'S11: 300 di taglia su Eve + 100 su Povero insieme: 46,54% a Povero: ' || q::text;
  assert (q->>'p_bounty')::numeric = 20.00 and (q->>'p_bets')::numeric = 66.67 and (q->>'l_bounty')::numeric = -0.42 and (q->>'l_bets')::numeric = 0.28, 'S11: i due segnali separati: ' || q::text;
  perform pg_temp.as_('Admin');
  perform public.admin_cancel_bounty((select id from public.bounties where target_id = pg_temp.uid('Eve') and status = 'active'), 'prova S11');
  assert pg_temp.pq(m2, 56.89, 158, 208) is null, 'S11: taglia annullata → di nuovo solo le scommesse';
  -- 7) con il win rate le scommesse contano comunque: 200 su Ann e 20 su Bob spingono Ann da 77,78% a 83,47%
  m3 := pg_temp.mk('Ann', 'Bob');
  pb0 := (pg_temp.q(m3)->>'p_challenger')::numeric;
  assert pb0 = 77.78 and pg_temp.q(m3)->>'basis' = 'mix', 'S11: Ann e Bob hanno dati';
  perform pg_temp.bet('Cyr', m3, 'Ann', 200); perform pg_temp.bet('Dia', m3, 'Bob', 20);
  assert pg_temp.pq(m3, 83.47, 107, 544) is null and (pg_temp.q(m3)->>'pool_challenger')::int = 200, 'S11: win rate e scommesse insieme: ' || pg_temp.q(m3)::text;
  assert (pg_temp.q(m3)->>'p_winrate')::numeric = 77.78 and (pg_temp.q(m3)->>'p_bets')::numeric = 71.43, 'S11: segnali separati: ' || pg_temp.q(m3)::text;
  -- 8) quota che si muove: chi aveva visto 1,80 non puntando a quota inferiore a quella vista
  m4 := pg_temp.mk('Povero', 'Eve');
  perform pg_temp.bet('Cyr', m4, 'Povero', 200);
  assert pg_temp.berr('Dia', m4, 'Povero', 50, 180) like '%La quota è cambiata%', 'S11: la quota è scesa sotto quella vista';
  assert (pg_temp.bet('Dia', m4, 'Eve', 50, 229)->>'quota')::int = 229, 'S11: la quota alta sull''altro lato regge';
  -- 9) l'elenco delle sfide porta le quote e i BC puntati su ciascuno
  perform pg_temp.as_('Cyr');
  x := (select e from jsonb_array_elements(public.bet_markets()) e where e->>'id' = m4::text);
  assert (x->'quote'->>'pool_challenger')::int = 200 and (x->'quote'->>'pool_opponent')::int = 50 and x->'quote'->>'basis' = 'mix' and (x->'quote'->>'p_bets')::numeric = 66.67, 'S11: bet_markets mostra i BC puntati e il segnale: ' || x::text;
  -- 10) i rimborsi e i saldi restano coerenti
  perform pg_temp.mst(m2, 'cancelled'); perform pg_temp.mst(m3, 'cancelled'); perform pg_temp.mst(m4, 'cancelled');
  assert pg_temp.bst('Cyr', m4) = 'refunded' and pg_temp.bst('Dia', m4) = 'refunded' and pg_temp.bst('Cyr', m2) = 'refunded', 'S11: sfide annullate → puntate restituite';
  assert pg_temp.inv() = 0, 'S11: ogni saldo coincide con il registro';
  insert into t_log (msg) values ('OK S11 — le scommesse già presenti nella quota: da sole, con taglie, con win rate, riequilibrio, quota fissa, impostazione');
end $$;

-- ---------------------------------------------------------------- S12 i tre segnali insieme e i loro pesi
do $$
declare m uuid; m0 uuid; r jsonb; d jsonb; x jsonb; bd integer; qa integer; qb integer; pa0 numeric;
begin
  -- Ann (win rate 70%) con 300 di taglia, contro Bob (40%): 84,14%; poi 200 BC puntati su Ann
  perform pg_temp.as_('Dia'); perform public.create_bounty(pg_temp.uid('Ann'), 300, null, 'bounty-test-s12-01');
  m := pg_temp.mk('Ann', 'Bob');
  assert pg_temp.pq(m, 84.14, 106, 567) is null, 'S12: win rate + taglia: ' || pg_temp.q(m)::text;
  r := pg_temp.bet('Cyr', m, 'Ann', 200);
  assert (r->>'quota')::int = 106 and (r->>'payout_if_win')::int = 212, 'S12: Cyr punta 200 a quota 1,06: ' || r::text;
  assert pg_temp.pq(m, 89.17, 105, 830) is null, 'S12: tutti e tre insieme (pesi 100/30/40): ' || pg_temp.q(m)::text;
  assert (pg_temp.q(m)->>'p_winrate')::numeric = 77.78 and (pg_temp.q(m)->>'p_bounty')::numeric = 80.00 and (pg_temp.q(m)->>'p_bets')::numeric = 75.00
     and (pg_temp.q(m)->>'l_winrate')::numeric = 1.25 and (pg_temp.q(m)->>'l_bounty')::numeric = 0.42 and (pg_temp.q(m)->>'l_bets')::numeric = 0.44, 'S12: i tre segnali e le tre spinte: ' || pg_temp.q(m)::text;
  -- ogni peso a zero spegne il suo segnale
  perform pg_temp.set_('bet_w_winrate', 0);
  assert pg_temp.pq(m, 70.17, 128, 301) is null, 'S12: win rate spento: ' || pg_temp.q(m)::text;
  perform pg_temp.set_('bet_w_winrate', 100); perform pg_temp.set_('bet_w_bounty', 0);
  assert pg_temp.pq(m, 84.45, 106, 578) is null, 'S12: taglie spente: ' || pg_temp.q(m)::text;
  perform pg_temp.set_('bet_w_bounty', 30); perform pg_temp.set_('bet_w_pool', 0);
  assert pg_temp.pq(m, 84.14, 106, 567) is null, 'S12: scommesse spente: ' || pg_temp.q(m)::text;
  perform pg_temp.set_('bet_w_winrate', 0); perform pg_temp.set_('bet_w_bounty', 0); perform pg_temp.set_('bet_w_pool', 40);
  assert pg_temp.pq(m, 60.81, 147, 229) is null, 'S12: solo scommesse: ' || pg_temp.q(m)::text;
  perform pg_temp.set_('bet_w_pool', 0);
  assert pg_temp.pq(m, 50.00, 180, 180) is null, 'S12: tutti i pesi a zero → alla pari: ' || pg_temp.q(m)::text;
  perform pg_temp.set_('bet_w_winrate', 100); perform pg_temp.set_('bet_w_bounty', 30); perform pg_temp.set_('bet_w_pool', 40);
  -- un peso negativo non esiste: viene trattato come zero
  assert pg_temp.err_as('Admin', 'select public.admin_set_setting(''bet_w_bounty'', -5, ''impostazione di prova'')') like '%Valore non valido%', 'S12: l''admin non può impostare un peso negativo: ' || coalesce(pg_temp.err_as('Admin', 'select public.admin_set_setting(''bet_w_bounty'', -5, ''impostazione di prova'')'), 'null');
  execute 'reset role'; update public.system_settings set value_int = -5 where key = 'bet_w_bounty';        -- anche a forza (scrittura diretta) la funzione lo tratta come 0
  assert pg_temp.pq(m, 84.45, 106, 578) is null, 'S12: peso negativo = 0';
  update public.system_settings set value_int = 30 where key = 'bet_w_bounty';
  update public.system_settings set value_int = -5 where key = 'bet_w_winrate';
  assert pg_temp.pq(m, 70.17, 128, 301) is null, 'S12: peso del win rate negativo = 0: ' || pg_temp.q(m)::text;
  update public.system_settings set value_int = 100 where key = 'bet_w_winrate';
  update public.system_settings set value_int = -5 where key = 'bet_w_pool';
  assert pg_temp.pq(m, 84.14, 106, 567) is null, 'S12: peso delle scommesse negativo = 0: ' || pg_temp.q(m)::text;
  update public.system_settings set value_int = 40 where key = 'bet_w_pool';
  -- pesi doppi = spinte doppie (non sono relativi): si arriva al limite del 95%
  perform pg_temp.set_('bet_w_winrate', 200); perform pg_temp.set_('bet_w_bounty', 60); perform pg_temp.set_('bet_w_pool', 80);
  assert pg_temp.pq(m, 95.00, 105, 1800) is null, 'S12: pesi doppi: ' || pg_temp.q(m)::text;
  perform pg_temp.set_('bet_w_winrate', 100); perform pg_temp.set_('bet_w_bounty', 30); perform pg_temp.set_('bet_w_pool', 40);
  -- monotonia: ogni nuova puntata su un duellante non fa mai salire la sua quota (e non fa scendere quella dell'altro)
  m0 := pg_temp.mk('Ann', 'Bob');
  qa := (pg_temp.q(m0)->>'quota_challenger')::int; qb := (pg_temp.q(m0)->>'quota_opponent')::int;
  perform pg_temp.bet('Eve', m0, 'Ann', 100);
  assert (pg_temp.q(m0)->>'quota_challenger')::int <= qa and (pg_temp.q(m0)->>'quota_opponent')::int >= qb, 'S12: dopo una puntata su Ann la sua quota non sale e quella di Bob non scende';
  assert (pg_temp.q(m0)->>'quota_challenger')::int < qa, 'S12: …e infatti scende davvero (' || qa || ' → ' || (pg_temp.q(m0)->>'quota_challenger') || ')';
  pa0 := (pg_temp.q(m0)->>'p_challenger')::numeric;
  perform pg_temp.bet('Cyr', m0, 'Bob', 200);
  assert (pg_temp.q(m0)->>'p_challenger')::numeric < pa0, 'S12: dopo 200 su Bob la stima di Ann scende';
  -- soldi soltanto sul secondo duellante: 100 su Eve (avversario) → Povero scende a 43,11% e la sua quota sale
  m0 := pg_temp.mk('Povero', 'Eve');
  perform pg_temp.bet('Cyr', m0, 'Eve', 100);
  assert pg_temp.pq(m0, 43.11, 208, 158) is null and (pg_temp.q(m0)->>'l_bets')::numeric = -0.28, 'S12: 100 solo sul secondo duellante: ' || pg_temp.q(m0)::text;
  -- la puntata salva i segnali usati e il criterio; la quota resta quella vista
  r := pg_temp.bet('Dia', m, 'Bob', 50, 830);
  assert (r->>'quota')::int = 830 and r->>'basis' = 'mix', 'S12: Dia trova 8,30 su Bob: ' || r::text;
  d := (select detail from public.bets where user_id = pg_temp.uid('Dia') and match_id = m);
  assert (d->>'l_winrate')::numeric = 1.25 and (d->>'l_bounty')::numeric = 0.42 and (d->>'l_bets')::numeric = 0.44 and (d->>'p_bounty')::numeric = 80.00, 'S12: dettaglio salvato con la scommessa: ' || coalesce(d::text, 'null');
  assert (select prob_pct from public.bets where user_id = pg_temp.uid('Dia') and match_id = m) = 10.83, 'S12: probabilità salvata (10,83% Bob)';
  perform pg_temp.as_('Dia');
  x := (select e from jsonb_array_elements(public.bet_mine()) e where e->>'match' = m::text);
  assert (x->'detail'->>'l_winrate')::numeric = 1.25 and x->>'basis' = 'mix', 'S12: bet_mine porta il dettaglio';
  -- vince Ann: Cyr (puntato a quota 1,06) incassa 200 × 1,06 = 212; Dia perde
  bd := pg_temp.bal('Dia');
  perform pg_temp.mst(m, 'closed', 'challenger');
  assert pg_temp.bst('Cyr', m) = 'won' and pg_temp.bret('Cyr', m) = 212 and pg_temp.bst('Dia', m) = 'lost' and pg_temp.bal('Dia') = bd, 'S12: liquidazione con la quota fissata';
  assert pg_temp.inv() = 0, 'S12: ogni saldo coincide con il registro';
  insert into t_log (msg) values ('OK S12 — i tre segnali insieme: spinte che si sommano, pesi, ognuno spegnibile, tutto a zero = alla pari, monotonia, dettaglio salvato');
end $$;

select n, msg from t_log order by n;
rollback;
