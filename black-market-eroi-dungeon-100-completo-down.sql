-- =====================================================================
-- ANNULLA la migrazione unica (dungeon 56–100 + nuovo motore): prima toglie i dungeon, poi rimette le funzioni come dopo la 026.
-- Si ferma se c'è una lobby o un dungeon in corso tra il 56 e il 100. Non tocca saldi e registro.
-- =====================================================================
begin;
do $$
begin
  if exists (select 1 from public.game_runs where dungeon_no between 56 and 100 and status in ('lobby', 'active')) then
    raise exception 'Ci sono lobby o dungeon in corso tra il 56 e il 100: aspetta che finiscano (o falli scadere) e riprova';
  end if;
end $$;
delete from public.game_equipped where item_id in (select id from public.game_items where dungeon_no between 56 and 100);
delete from public.game_inventory where item_id in (select id from public.game_items where dungeon_no between 56 and 100);
delete from public.game_dungeon_endings where dungeon_no between 56 and 100;
delete from public.game_dungeon_progress where dungeon_no between 56 and 100;
delete from public.game_run_members where run_id in (select id from public.game_runs where dungeon_no between 56 and 100);
delete from public.game_runs where dungeon_no between 56 and 100;
delete from public.game_dungeon_graphs where dungeon_no between 56 and 100;
delete from public.game_items where dungeon_no between 56 and 100;
delete from public.game_dungeons where no between 56 and 100;
drop function if exists public.game_dungeon_choose(uuid, text, text);
drop function if exists public._game_dng_fx(jsonb, jsonb, text);
drop function if exists public._game_dng_odds(jsonb, text, numeric);

create or replace function public._game_dng_fx(p_state jsonb, p_fx jsonb) returns jsonb language plpgsql immutable set search_path = public as $$
declare st jsonb := p_state; mem jsonb := '[]'::jsonb; x jsonb; f text; pct numeric;
begin
  if p_fx is null or p_fx = 'null'::jsonb then return st; end if;
  if p_fx ? 'pow' then st := jsonb_set(st, '{pow}', to_jsonb(greatest(-50, least(100, (st->>'pow')::integer + (p_fx->>'pow')::integer)))); end if;
  if p_fx ? 'hp' then
    pct := (p_fx->>'hp')::numeric;
    for x in select * from jsonb_array_elements(st->'members') loop
      if (x->>'hp')::numeric > 0 or pct > 0 then
        x := jsonb_set(x, '{hp}', to_jsonb(round(greatest(1, least((x->>'mx')::numeric, (x->>'hp')::numeric + (x->>'mx')::numeric * pct / 100.0)), 2)));
      end if;
      mem := mem || jsonb_build_array(x);
    end loop;
    st := jsonb_set(st, '{members}', mem);
  end if;
  if p_fx ? 'flag' then
    f := p_fx->>'flag';
    if not (st->'flags') @> to_jsonb(f) then st := jsonb_set(st, '{flags}', (st->'flags') || to_jsonb(f)); end if;
  end if;
  return st;
end $$;

create or replace function public._game_dng_view(p_run uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r public.game_runs%rowtype; g jsonb; nd jsonb; st jsonb; fl text[]; opts jsonb := '[]'::jsonb; o jsonb; txt text; lock_ boolean; hint text; lbl jsonb;
begin
  select * into r from public.game_runs where id = p_run;
  if not found or r.state is null then return null; end if;
  st := r.state;
  select graph into g from public.game_dungeon_graphs where dungeon_no = r.dungeon_no;
  nd := g->(st->>'node');
  select coalesce(array_agg(f), '{}') into fl from jsonb_array_elements_text(st->'flags') f;
  lbl := coalesce(g->'_flags', '{}'::jsonb);
  if nd is not null and nd->>'t' = 'scene' then
    txt := nd->>'x';
    if nd ? 'h' and (nd->'h'->>'if') = any(fl) then txt := txt || E'\n\n' || (nd->'h'->>'t'); end if;
    for o in select * from jsonb_array_elements(nd->'o') loop
      continue when o ? 'only' and not coalesce((select bool_and(f = any(fl)) from jsonb_array_elements_text(o->'only') f), true);
      lock_ := o ? 'req' and not coalesce((select bool_and(f = any(fl)) from jsonb_array_elements_text(o->'req') f), true);
      hint := null;
      if lock_ then hint := 'Ti serve: ' || (select string_agg(coalesce(lbl->>f, f), ', ') from jsonb_array_elements_text(o->'req') f); end if;
      opts := opts || jsonb_build_array(jsonb_build_object('id', o->>'id', 'label', o->>'l', 'locked', lock_, 'hint', hint));
    end loop;
  end if;
  return jsonb_build_object('run_id', r.id, 'dungeon_no', r.dungeon_no, 'status', r.status, 'leader_id', r.leader_id, 'pow', (st->>'pow')::integer,
    'flags', coalesce((select jsonb_agg(jsonb_build_object('id', f, 'label', coalesce(lbl->>f, f))) from jsonb_array_elements_text(st->'flags') f), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', x->>'user_id', 'nickname', x->>'nickname', 'role', x->>'role', 'level', (x->>'level')::integer, 'hp', round((x->>'hp')::numeric), 'max_hp', round((x->>'mx')::numeric)))
                         from jsonb_array_elements(st->'members') x), '[]'::jsonb),
    'scene', case when txt is null then null else jsonb_build_object('id', st->>'node', 'title', nd->>'n', 'text', txt, 'options', opts) end,
    'step', jsonb_array_length(st->'log'), 'log', st->'log',
    'last_move_at', r.last_move_at, 'expires_at', r.last_move_at + make_interval(mins => greatest(1, public._setting('game_dng_path_minutes'))));
end $$;

create or replace function public._game_dng_advance(p_state jsonb, p_graph jsonb, p_no integer) returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.game_dungeons%rowtype; st jsonb := p_state; nd jsonb; t text; guard integer := 0; diff numeric; res jsonb; fl text[]; c jsonb; hit text; mem jsonb; x jsonb; y jsonb; j integer;
  w boolean; kind text; hits numeric; apct numeric; rm jsonb; mm jsonb;
begin
  select * into d from public.game_dungeons where no = p_no;
  diff := d.diff * (0.8 + 0.55 * (1 - exp(-(d.ref_level - 1) / 25.0))) * greatest(10, public._setting('game_dng_difficulty')) / 100.0;
  loop
    guard := guard + 1;
    if guard > 40 then raise exception 'Percorso del dungeon non valido'; end if;
    nd := p_graph->(st->>'node');
    if nd is null then raise exception 'Percorso del dungeon non valido'; end if;
    t := nd->>'t';
    if t = 'scene' then return jsonb_build_object('state', st, 'end', null); end if;
    if t = 'end' then return jsonb_build_object('state', st, 'end', nd || jsonb_build_object('id', st->>'node')); end if;
    select coalesce(array_agg(f), '{}') into fl from jsonb_array_elements_text(st->'flags') f;
    if t = 'route' then
      hit := nd->>'d';
      for c in select * from jsonb_array_elements(nd->'c') loop
        if coalesce((select bool_and(f = any(fl)) from jsonb_array_elements_text(c->'if') f), true) then hit := c->>'to'; exit; end if;
      end loop;
      st := jsonb_set(st, '{node}', to_jsonb(hit));
    elsif t = 'fight' then
      kind := coalesce(nd->>'k', 'n');
      hits := case kind when 'b' then 20 when 'e' then 16 else 12 end;
      apct := case kind when 'b' then 0.125 when 'e' then 0.11 else 0.09 end;
      res := public._game_dng_clash(st->'members', jsonb_build_object('m', coalesce((nd->>'m')::numeric, 1), 'hits', hits, 'apct', apct), (st->>'pow')::numeric, diff, d.ref_level);
      w := (res->>'win')::boolean;
      mem := '[]'::jsonb; mm := '[]'::jsonb;
      for j in 0..jsonb_array_length(st->'members') - 1 loop
        x := st->'members'->j; y := res->'members'->j;
        x := x || jsonb_build_object('dealt', (x->>'dealt')::numeric + (y->>'dealt')::numeric, 'taken', (x->>'taken')::numeric + (y->>'taken')::numeric, 'healed', (x->>'healed')::numeric + (y->>'healed')::numeric);
        mm := mm || jsonb_build_array(jsonb_build_object('user_id', x->>'user_id', 'nickname', x->>'nickname', 'role', x->>'role', 'dealt', (y->>'dealt')::numeric, 'taken', (y->>'taken')::numeric,
                                                          'healed', (y->>'healed')::numeric, 'hp', round((y->>'hp')::numeric), 'max_hp', round((x->>'mx')::numeric), 'ko', (y->>'ko')::boolean));
        if w then   -- dopo una vittoria il gruppo si riposa: +25% dei PV massimi (chi era KO torna con il 25%)
          x := jsonb_set(x, '{hp}', to_jsonb(round(case when (y->>'hp')::numeric <= 0 then 0.25 * (x->>'mx')::numeric else least((x->>'mx')::numeric, (y->>'hp')::numeric + 0.25 * (x->>'mx')::numeric) end, 2)));
        else
          x := jsonb_set(x, '{hp}', to_jsonb(round((y->>'hp')::numeric, 2)));
        end if;
        mem := mem || jsonb_build_array(x);
      end loop;
      st := jsonb_set(st, '{members}', mem);
      st := jsonb_set(st, '{rooms}', (st->'rooms') || jsonb_build_array(jsonb_build_object('no', jsonb_array_length(st->'rooms') + 1, 'name', nd->>'e', 'emoji', nd->>'em', 'boss', kind = 'b', 'cleared', w,
                                                                                         'rounds', (res->>'rounds')::integer, 'enemy_hp', (res->>'enemy_hp')::bigint, 'members', mm)));
      st := jsonb_set(st, '{log}', (st->'log') || jsonb_build_array(jsonb_build_object('k', 'f', 'e', nd->>'e', 'em', nd->>'em', 'boss', kind = 'b', 'win', w, 'rounds', (res->>'rounds')::integer)));
      if w then
        st := public._game_dng_fx(st, nd->'wfx');
        st := jsonb_set(st, '{node}', to_jsonb(nd->>'w'));
      else
        st := jsonb_set(st, '{node}', to_jsonb(nd->>'l'));
      end if;
    else
      raise exception 'Percorso del dungeon non valido';
    end if;
  end loop;
end $$;

create or replace function public.game_dungeon_choose(p_run uuid, p_option text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); r public.game_runs%rowtype; g jsonb; st jsonb; nd jsonb; o jsonb; fl text[]; adv jsonb; e jsonb; res jsonb;
begin
  perform public._require_module('heroes');
  select * into r from public.game_runs where id = p_run for update;
  if not found or r.status <> 'active' then raise exception 'Questo dungeon non è in corso'; end if;
  if r.last_move_at < now() - make_interval(mins => greatest(1, public._setting('game_dng_path_minutes'))) then
    perform public._game_dng_expire_active();
    return jsonb_build_object('run_id', p_run, 'dungeon_no', r.dungeon_no, 'status', 'failed', 'expired', true);
  end if;
  if r.leader_id <> v then raise exception 'Solo il capo gruppo può scegliere'; end if;
  select graph into g from public.game_dungeon_graphs where dungeon_no = r.dungeon_no;
  st := r.state; nd := g->(st->>'node');
  if nd is null or nd->>'t' <> 'scene' then raise exception 'Non c’è nessuna scelta da fare'; end if;
  select coalesce(array_agg(f), '{}') into fl from jsonb_array_elements_text(st->'flags') f;
  select x into o from jsonb_array_elements(nd->'o') x where x->>'id' = p_option;
  if o is null then raise exception 'Scelta non valida'; end if;
  if o ? 'only' and not coalesce((select bool_and(f = any(fl)) from jsonb_array_elements_text(o->'only') f), true) then raise exception 'Scelta non valida'; end if;
  if o ? 'req' and not coalesce((select bool_and(f = any(fl)) from jsonb_array_elements_text(o->'req') f), true) then raise exception 'Questa scelta non è ancora disponibile'; end if;
  st := public._game_dng_fx(st, o->'fx');
  st := jsonb_set(st, '{log}', (st->'log') || jsonb_build_array(jsonb_build_object('k', 'c', 'n', nd->>'n', 'l', o->>'l', 'r', coalesce(o->>'r', ''))));
  st := jsonb_set(st, '{node}', to_jsonb(o->>'to'));
  adv := public._game_dng_advance(st, g, r.dungeon_no::integer);
  st := adv->'state'; e := adv->'end';
  update public.game_runs set state = st, last_move_at = clock_timestamp() where id = p_run;
  if e is not null and e <> 'null'::jsonb then
    res := public._game_dng_settle(p_run, coalesce((e->>'win')::boolean, false), e);
    return jsonb_build_object('run_id', p_run, 'dungeon_no', r.dungeon_no, 'status', case when (res->>'win')::boolean then 'cleared' else 'failed' end, 'result', res);
  end if;
  return jsonb_build_object('run_id', p_run, 'dungeon_no', r.dungeon_no, 'status', 'active', 'view', public._game_dng_view(p_run));
end $$;
create or replace function public.game_dungeon_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); b jsonb; act uuid; cleared integer; total integer;
begin
  perform public._require_module('heroes');
  perform public._game_dng_expire_active();
  b := public._game_dng_state_base();
  select m.run_id into act from public.game_run_members m join public.game_runs r on r.id = m.run_id where m.user_id = v and r.status = 'active' order by r.started_at desc limit 1;
  cleared := (b->>'cleared')::integer; total := (b->>'total')::integer;
  b := jsonb_set(b, '{next_epic_in}', to_jsonb(case when cleared >= total then 0 else 5 - (cleared % 5) end));
  b := jsonb_set(b, '{dungeons}', coalesce((select jsonb_agg(e || jsonb_build_object('kind', d.kind,
          'endings_total', coalesce((select count(*) from jsonb_each(gg.graph) x where x.value->>'t' = 'end'), 0),
          'endings_found', (select count(*) from public.game_dungeon_endings en where en.user_id = v and en.dungeon_no = d.no),
          'forks', coalesce((select count(*) from jsonb_each(gg.graph) x where x.value->>'t' = 'scene'), 0)) order by d.no)
        from jsonb_array_elements(b->'dungeons') e join public.game_dungeons d on d.no = (e->>'no')::smallint left join public.game_dungeon_graphs gg on gg.dungeon_no = d.no), '[]'::jsonb));
  return b || jsonb_build_object('active', case when act is null then null else public._game_dng_view(act) end, 'path_minutes', public._setting('game_dng_path_minutes'));
end $$;

revoke all on function public._game_dng_fx(jsonb, jsonb), public._game_dng_view(uuid), public._game_dng_advance(jsonb, jsonb, integer) from public, anon, authenticated;
revoke all on function public.game_dungeon_choose(uuid, text), public.game_dungeon_state() from public, anon;
grant execute on function public.game_dungeon_choose(uuid, text), public.game_dungeon_state() to authenticated;
commit;
