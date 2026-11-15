-- =====================================================================================
--  La guerra degli Eroi — Raid: rientro a pagamento (migrazione 048)
--  Chi va KO contro il boss del raid può rientrare subito pagando una quota in BC:
--  torna in battaglia con tutti i PV. La quota cresce a ogni rientro della stessa settimana
--  (100, 200, 400, 800… BC) e riparte da capo con il boss nuovo.
--  Resta tutto il resto: la cura di un alleato è sempre gratis, e il giorno dopo si torna in forze.
--  Impostazioni (Admin › Impostazioni):
--    game_raid_revive_bc      quota del primo rientro (0 = rientro a pagamento spento)
--    game_raid_revive_growth  aumento in % a ogni rientro (100 = raddoppia)
--    game_raid_revive_max     tetto della quota (0 = nessun tetto)
--  Si può rieseguire. Annulla con black-market-eroi-raid-rientro-down.sql
-- =====================================================================================
begin;

insert into public.system_settings (key, value_int, description) values
 ('game_raid_revive_bc', 100, 'Raid: BC per rientrare dopo un KO, la prima volta nella settimana (0 = spento)'),
 ('game_raid_revive_growth', 100, 'Raid: aumento in % della quota a ogni rientro della stessa settimana (100 = raddoppia)'),
 ('game_raid_revive_max', 0, 'Raid: tetto della quota di rientro in BC (0 = nessun tetto)')
on conflict (key) do nothing;

alter table public.game_raid_damage add column if not exists revives integer not null default 0;

-- nuovo tipo di movimento e nuova voce della cronaca
do $$
declare d text; kinds text[];
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.ledger_entries'::regclass and conname = 'ledger_entries_kind_check';
  if d is null then raise exception 'Vincolo ledger_entries_kind_check non trovato'; end if;
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  if not ('game_raid_revive' = any (kinds)) then
    kinds := kinds || 'game_raid_revive'::text;
    alter table public.ledger_entries drop constraint ledger_entries_kind_check;
    execute 'alter table public.ledger_entries add constraint ledger_entries_kind_check check (kind in (' || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
  end if;
  select conname into d from pg_constraint where conrelid = 'public.game_raid_log'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%attack%';
  if d is not null then execute format('alter table public.game_raid_log drop constraint %I', d); end if;
  alter table public.game_raid_log add constraint game_raid_log_action_check check (action in ('attack','guard','heal','study','revive'));
end $$;

-- quota del prossimo rientro: base × (1 + aumento)^rientri già fatti in questa settimana
create or replace function public._raid_revive_cost(p_raid bigint, p_user uuid) returns integer language sql stable security definer set search_path = public as $$
  select case when coalesce(public._setting('game_raid_revive_bc'), 0) <= 0 then 0 else
    least(1000000000, case when coalesce(public._setting('game_raid_revive_max'), 0) > 0 then public._setting('game_raid_revive_max') else 1000000000 end,
      round(public._setting('game_raid_revive_bc')::numeric
        * power(1 + greatest(0, coalesce(public._setting('game_raid_revive_growth'), 100)) / 100.0,
                least(60, coalesce((select revives from public.game_raid_damage where raid_id = p_raid and user_id = p_user), 0)))))::integer end $$;
revoke all on function public._raid_revive_cost(bigint, uuid) from public, anon, authenticated;

create or replace function public.game_raid_revive() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date := (now() at time zone 'Europe/Rome')::date; rid bigint; g public.game_raids%rowtype; me public.game_raid_days%rowtype; v_cost integer; v_bal integer; n integer;
begin
  perform public._require_module('heroes');
  if coalesce(public._setting('game_raid_enabled'), 0) <> 1 then raise exception 'Il raid non è attivo'; end if;
  rid := public._raid_ensure();
  select * into g from public.game_raids where id = rid for update;
  if g.status <> 'open' then raise exception 'Il boss di questa settimana è già caduto: il prossimo arriva lunedì'; end if;
  select * into me from public.game_raid_days where raid_id = rid and day = d and user_id = v for update;
  if not found or me.hp > 0 then raise exception 'Non sei KO: non serve rientrare'; end if;
  v_cost := public._raid_revive_cost(rid, v);
  if v_cost <= 0 then raise exception 'Il rientro a pagamento non è attivo'; end if;
  v_bal := public._ledger_move(v, -v_cost, 'game_raid_revive', 'game_raid', null, 'raidrev:' || rid || ':' || v::text || ':' || gen_random_uuid()::text, 'Raid: rientro in battaglia');
  update public.game_raid_days set hp = max_hp where raid_id = rid and day = d and user_id = v;
  insert into public.game_raid_damage (raid_id, user_id, revives) values (rid, v, 1)
    on conflict (raid_id, user_id) do update set revives = game_raid_damage.revives + 1 returning revives into n;
  insert into public.game_raid_log (raid_id, user_id, action, amount, note) values (rid, v, 'revive', v_cost, 'rientro');
  return jsonb_build_object('cost', v_cost, 'balance', v_bal, 'my_hp', me.max_hp, 'my_max_hp', me.max_hp, 'revives', n, 'next_cost', public._raid_revive_cost(rid, v));
end $$;
revoke all on function public.game_raid_revive() from public, anon;
grant execute on function public.game_raid_revive() to authenticated;

-- lo stato e le azioni del raid dicono anche quanto costa rientrare
do $do$
declare def text; pairs text[][] := array[
  ['public.game_raid_state()', $a$'ko', coalesce(me.hp, 1) <= 0,$a$, $b$'ko', coalesce(me.hp, 1) <= 0, 'revive_cost', public._raid_revive_cost(rid, v), 'revives', coalesce((select revives from public.game_raid_damage where raid_id = rid and user_id = v), 0),$b$],
  ['public.game_raid_act(text,uuid)', $a$'ko', me.hp <= 0,$a$, $b$'ko', me.hp <= 0, 'revive_cost', public._raid_revive_cost(rid, v),$b$],
  ['public.game_raid_act(text,uuid)', $a$'Sei KO: un alleato deve curarti, oppure torni in forze domani'$a$, $b$'Sei KO: rientra pagando la quota, fatti curare da un alleato oppure torna domani'$b$]];
  i integer;
begin
  for i in 1 .. array_length(pairs, 1) loop
    def := pg_get_functiondef(pairs[i][1]::regprocedure);
    if position(pairs[i][3] in def) = 0 then
      if position(pairs[i][2] in def) = 0 then raise exception 'Funzione % diversa dal previsto: mandami questo messaggio', pairs[i][1]; end if;
      execute replace(def, pairs[i][2], pairs[i][3]);
    end if;
  end loop;
end $do$;

commit;

select 'OK — rientro nel raid attivo: prima quota ' || (select value_int from public.system_settings where key = 'game_raid_revive_bc') || ' BC, +'
    || (select value_int from public.system_settings where key = 'game_raid_revive_growth') || '% a ogni rientro' as risultato;
