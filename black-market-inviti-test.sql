-- =====================================================================
-- TEST DELLA MIGRAZIONE 037 (inviti e vetrina pubblica)
-- Da eseguire SOLO su un progetto Supabase di PROVA ancora vuoto, con tutte le migrazioni applicate fino a black-market-inviti.sql.
-- Gira in una transazione che finisce con ROLLBACK: non lascia dati. Alla fine mostra una riga "OK" per ogni scenario.
-- =====================================================================
begin;
do $$ begin
  if exists (select 1 from public.profiles) then
    raise exception 'TEST NON ESEGUITO: questo database contiene già dati. Eseguilo solo su un database di prova vuoto. Non è stato modificato nulla.';
  end if;
end $$;
create temp table t_log (n serial, msg text);

create function pg_temp.uid(n text) returns uuid language sql immutable as $$ select md5('tempio-inviti-' || n)::uuid $$;
create function pg_temp.as_(n text) returns text language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', pg_temp.uid(n), 'role', 'authenticated')::text, true) $$;
create function pg_temp.err_as(n text, q text) returns text language plpgsql as $$
begin perform pg_temp.as_(n); execute q; return null; exception when others then return sqlerrm; end $$;
create function pg_temp.rows_as(n text, q text) returns bigint language plpgsql as $$   -- come il browser: ruolo authenticated
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
create function pg_temp.bal(n text) returns integer language sql as $$ select balance from public.wallets where user_id = pg_temp.uid(n) $$;
create function pg_temp.play(a text, b text, result text) returns jsonb language plpgsql as $$
declare id uuid;
begin
  perform pg_temp.as_(a); id := public.ladder_challenge(pg_temp.uid(b), 'Advanced', null, gen_random_uuid()::text, 'ladder');
  perform pg_temp.as_(b); perform public.ladder_respond(id, true);
  perform pg_temp.as_(a); perform public.ladder_report(id, result, case result when 'challenger' then '2-0' when 'opponent' then '0-2' else '1-1' end);
  perform pg_temp.as_(b); return public.ladder_confirm(id);
end $$;
create function pg_temp.reg(n text) returns void language plpgsql as $$
begin
  insert into auth.users (id, email, aud, role) values (pg_temp.uid(n), lower(n) || '@test.local', 'authenticated', 'authenticated');
  perform pg_temp.as_(n); perform public.register_profile(n); perform public.update_my_profile(null, true);
end $$;

-- Preparazione
do $$
declare n text;
begin
  foreach n in array array['Admin','Org','Marco','Luca','Nuovo','Nuovo2','Vecchio','Furbo'] loop perform pg_temp.reg(n); end loop;
  perform pg_temp.as_('Admin'); perform public.admin_set_role(pg_temp.uid('Org'), 'organizer', 'organizzatore di test');
  insert into t_log (msg) values ('OK Preparazione: 8 utenti');
end $$;

-- I1 — Codice personale: uno solo, stabile, formato corretto; nessuno vede quello degli altri
do $$
declare c1 text; c2 text;
begin
  perform pg_temp.as_('Marco'); c1 := public.my_invite()->>'code'; c2 := public.my_invite()->>'code';
  assert c1 ~ '^[A-Z2-9]{6}$' and c1 = c2, 'I1: codice di 6 caratteri, sempre lo stesso';
  assert pg_temp.rows_as('Luca', 'select * from public.invite_codes') = 0, 'I1: Luca non vede il codice di Marco';
  assert pg_temp.rows_as('Marco', 'select * from public.invite_codes') = 1, 'I1: Marco vede il suo';
  assert (public.invite_info(lower(c1))->>'nickname') = 'Marco', 'I1: invite_info restituisce il nickname (maiuscole indifferenti)';
  assert public.invite_info('ZZZZZZ') is null, 'I1: codice inesistente = nessuna informazione';
  insert into t_log (msg) values ('OK I1 — codice personale stabile e privato, invite_info dice solo il nickname');
end $$;

-- I2 — Inserimento del codice: regole
do $$
declare c text; r jsonb;
begin
  perform pg_temp.as_('Marco'); c := public.my_invite()->>'code';
  assert pg_temp.err_as('Marco', format('select public.redeem_invite(%L)', c)) like '%tuo stesso codice%', 'I2: niente auto-invito';
  assert pg_temp.err_as('Nuovo', 'select public.redeem_invite(''ABCDEF'')') like '%non valido%', 'I2: codice sbagliato rifiutato';
  perform pg_temp.as_('Nuovo'); r := public.redeem_invite(c);
  assert (r->>'ok')::boolean and r->>'inviter' = 'Marco', 'I2: Nuovo collegato a Marco';
  perform pg_temp.as_('Nuovo'); r := public.redeem_invite(c);
  assert (r->>'already')::boolean, 'I2: un solo padrino per duellante';
  assert pg_temp.bal('Nuovo') = 1000 and pg_temp.bal('Marco') = 1000, 'I2: nessun BC prima di giocare';
  -- iscritto da troppo tempo
  update public.profiles set created_at = now() - interval '30 days' where id = pg_temp.uid('Vecchio');
  assert pg_temp.err_as('Vecchio', format('select public.redeem_invite(%L)', c)) like '%primi 7 giorni%', 'I2: oltre 7 giorni dall''iscrizione non vale';
  -- chi ha già giocato non può più inserire un codice
  perform pg_temp.play('Furbo', 'Luca', 'challenger');
  assert pg_temp.err_as('Furbo', format('select public.redeem_invite(%L)', c)) like '%prima del primo match%', 'I2: dopo il primo match non vale';
  -- inviti incrociati
  perform pg_temp.as_('Nuovo'); c := public.my_invite()->>'code';
  assert pg_temp.err_as('Marco', format('select public.redeem_invite(%L)', c)) like '%a vicenda%', 'I2: niente inviti incrociati';
  insert into t_log (msg) values ('OK I2 — niente auto-invito, codici falsi, doppio padrino, iscritti da oltre 7 giorni, chi ha già giocato, inviti incrociati');
end $$;

-- I3 — Il match contro chi ti ha invitato NON fa scattare il premio; il primo match contro un altro sì
do $$
declare t0 bigint;
begin
  perform pg_temp.play('Nuovo', 'Marco', 'challenger');
  assert pg_temp.bal('Marco') = 1000, 'I3: nessun premio invito se l''avversario è il padrino';
  assert (select rewarded_at from public.invites where invitee_id = pg_temp.uid('Nuovo')) is null, 'I3: invito ancora in attesa';
  perform pg_temp.play('Luca', 'Nuovo', 'challenger');   -- Nuovo perde: conta lo stesso (ha giocato)
  assert pg_temp.bal('Marco') = 1200, 'I3: +200 BC a chi invita';
  assert pg_temp.bal('Nuovo') = 1000 + 20 + 100, 'I3: +100 BC all''invitato (più i 20 della vittoria di prima)';
  assert (select count(*) from public.ledger_entries where kind = 'invite_reward' and user_id = pg_temp.uid('Marco') and amount = 200) = 1, 'I3: registro: invite_reward';
  assert (select count(*) from public.ledger_entries where kind = 'invite_bonus' and user_id = pg_temp.uid('Nuovo') and amount = 100) = 1, 'I3: registro: invite_bonus';
  assert (select count(*) from public.notifications where user_id = pg_temp.uid('Marco') and kind = 'invite_reward') = 1, 'I3: notifica a chi invita';
  perform pg_temp.play('Luca', 'Nuovo', 'opponent');
  assert pg_temp.bal('Marco') = 1200, 'I3: premio una volta sola';
  perform pg_temp.as_('Admin');
  assert (select bool_and(ok) from public.wallet_reconciliation_v), 'I3: ogni saldo coincide con il registro';
  insert into t_log (msg) values ('OK I3 — match col padrino non conta; primo match con un altro: +200 a chi invita, +100 all''invitato, una sola volta, registro e notifica');
end $$;

-- I4 — Anche un match ufficiale verificato (torneo dell'organizzatore) fa scattare il premio
do $$
declare c text; ev uuid; m uuid;
begin
  perform pg_temp.as_('Luca'); c := public.my_invite()->>'code';
  perform pg_temp.as_('Nuovo2'); perform public.redeem_invite(c);
  perform pg_temp.as_('Org'); ev := public.create_event('Torneo di prova ' || gen_random_uuid(), current_date);
  m := public.create_match(ev, 1, pg_temp.uid('Nuovo2'), pg_temp.uid('Org'));
  perform public.verify_match(m, pg_temp.uid('Org'));
  assert pg_temp.bal('Luca') = (select 1000 + sum(amount) from public.ledger_entries where user_id = pg_temp.uid('Luca') and kind <> 'initial_bonus'), 'I4: saldo coerente';
  assert (select inviter_paid from public.invites where invitee_id = pg_temp.uid('Nuovo2')) = 200, 'I4: premio da match ufficiale';
  insert into t_log (msg) values ('OK I4 — premio anche dal match ufficiale verificato di un torneo');
end $$;

-- I5 — Tetto ai premi e interruttore
do $$
declare c text;
begin
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('invite_max_rewards', 1, 'tetto di prova');
  perform pg_temp.reg('Terzo');
  perform pg_temp.as_('Marco'); c := public.my_invite()->>'code';
  perform pg_temp.as_('Terzo'); perform public.redeem_invite(c);
  perform pg_temp.play('Terzo', 'Luca', 'challenger');
  assert pg_temp.bal('Marco') = 1200, 'I5: oltre il tetto chi invita non prende altro';
  assert pg_temp.bal('Terzo') = 1000 + 20 + 100, 'I5: l''invitato riceve comunque il bonus';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('invite_enabled', 0, 'spento per prova');
  perform pg_temp.reg('Quarto');
  assert pg_temp.err_as('Quarto', format('select public.redeem_invite(%L)', c)) like '%non sono attivi%', 'I5: inviti spenti';
  assert public.invite_info(c) is null, 'I5: inviti spenti = nessun banner';
  perform pg_temp.as_('Admin'); perform public.admin_set_setting('invite_enabled', 1, 'riacceso');
  insert into t_log (msg) values ('OK I5 — tetto ai premi (l''invitato riceve comunque il bonus) e interruttore invite_enabled');
end $$;

-- I6 — Badge Reclutatore
do $$
begin
  perform pg_temp.as_('Marco');
  assert (select value from public.badge_progress_invite() where code = 'c_recluta_1') = 2, 'I6: 2 amici che hanno giocato';
  assert (select earned from public.badge_progress_invite() where code = 'c_recluta_1') and not (select earned from public.badge_progress_invite() where code = 'c_recluta_2'), 'I6: bronzo sì, argento no';
  perform pg_temp.as_('Luca');
  assert (select count(*) from public.badge_progress_invite(pg_temp.uid('Marco'))) = 4, 'I6: i badge degli altri si vedono';
  insert into t_log (msg) values ('OK I6 — badge Reclutatore calcolati dagli inviti premiati');
end $$;

-- I7 — Privacy e vetrina pubblica
do $$
declare s jsonb; t text;
begin
  assert pg_temp.rows_as('Luca', 'select * from public.invites') = 1, 'I7: Luca vede solo gli inviti che lo riguardano';
  perform pg_temp.as_('Marco'); perform public.create_bounty(pg_temp.uid('Luca'), 300, 'prova', 'req-vetrina-1');
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  s := public.public_showcase();
  execute 'reset role';
  assert jsonb_array_length(s->'ladder'->'Advanced') between 1 and 5, 'I7: classifica Ladder presente';
  assert (s->'wanted'->0->>'value')::int = 300, 'I7: Most Wanted con la taglia';
  assert jsonb_array_length(s->'results') >= 1, 'I7: ultimi risultati';
  assert (s->'stats'->>'players')::int >= 8, 'I7: numero duellanti';
  t := s::text;
  assert t not like '%@test.local%' and t not like '%balance%' and t not like '%ledger%', 'I7: nessuna email, saldo o registro nella vetrina';
  assert s->'people'->(pg_temp.uid('Luca')::text)->>'n' = 'Luca', 'I7: nickname nella vetrina';
  -- l'anonimo non legge tabelle né usa le funzioni riservate
  begin execute 'set local role anon'; perform count(*) from public.invites; raise exception 'LETTO'; exception when others then
    assert sqlerrm <> 'LETTO', 'I7: anon non legge la tabella inviti'; end;
  execute 'reset role';
  begin execute 'set local role anon'; perform public.my_invite(); raise exception 'ESEGUITO'; exception when others then
    assert sqlerrm <> 'ESEGUITO', 'I7: anon non usa my_invite'; end;
  execute 'reset role';
  insert into t_log (msg) values ('OK I7 — vetrina leggibile senza account, solo nickname e numeri pubblici; tabelle inviti protette');
end $$;

select msg as risultato from t_log order by n;
rollback;
