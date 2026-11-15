-- Annulla la migrazione 048 (rientro a pagamento nel raid). Le quote già pagate restano nel registro.
begin;
do $do$
declare def text; pairs text[][] := array[
  ['public.game_raid_state()', $a$'ko', coalesce(me.hp, 1) <= 0,$a$, $b$'ko', coalesce(me.hp, 1) <= 0, 'revive_cost', public._raid_revive_cost(rid, v), 'revives', coalesce((select revives from public.game_raid_damage where raid_id = rid and user_id = v), 0),$b$],
  ['public.game_raid_act(text,uuid)', $a$'ko', me.hp <= 0,$a$, $b$'ko', me.hp <= 0, 'revive_cost', public._raid_revive_cost(rid, v),$b$],
  ['public.game_raid_act(text,uuid)', $a$'Sei KO: un alleato deve curarti, oppure torni in forze domani'$a$, $b$'Sei KO: rientra pagando la quota, fatti curare da un alleato oppure torna domani'$b$]];
  i integer;
begin
  for i in 1 .. array_length(pairs, 1) loop
    def := pg_get_functiondef(pairs[i][1]::regprocedure);
    if position(pairs[i][3] in def) > 0 then execute replace(def, pairs[i][3], pairs[i][2]); end if;
  end loop;
end $do$;
drop function if exists public.game_raid_revive();
drop function if exists public._raid_revive_cost(bigint, uuid);
delete from public.game_raid_log where action = 'revive';
alter table public.game_raid_log drop constraint if exists game_raid_log_action_check;
alter table public.game_raid_log add constraint game_raid_log_action_check check (action in ('attack','guard','heal','study'));
alter table public.game_raid_damage drop column if exists revives;
delete from public.system_settings where key in ('game_raid_revive_bc','game_raid_revive_growth','game_raid_revive_max');
commit;
