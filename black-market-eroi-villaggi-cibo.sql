-- =====================================================================================
--  La guerra degli Eroi — Villaggi: la Fattoria sfama la Caserma (migrazione 054)
--  Problema: Fattoria, Segheria e Cava producevano tutte 30 × L × 1,2^(L−1) all'ora, ma la Caserma ospita
--  25 × L × (L+1) / 2 soldati e ognuno mangia 1 cibo all'ora (il cavaliere 2): già dal livello 2 una Caserma piena
--  mangiava più di quanto la Fattoria dello stesso livello producesse (al livello 7: 627 cibo/ora per 700 posti).
--  Adesso la sola Fattoria produce il DOPPIO: 60 × L × 1,2^(L−1) cibo all'ora. Legno e pietra non cambiano.
--      livello Fattoria/Caserma     1     2     3     5      7      10
--      cibo all'ora (prima)        30    72   130   311    627   1.548
--      cibo all'ora (adesso)       60   144   259   622  1.254   3.096
--      posti in Caserma            25    75   150   375    700   1.375
--  Con Fattoria e Caserma allo stesso livello una Caserma piena di fanti e arcieri si mantiene sempre, con cibo
--  in avanzo per addestrare; i cavalieri mangiano il doppio, quindi un esercito di soli cavalieri resta più caro.
--  Vale dal prossimo aggiornamento del villaggio (il cibo già in magazzino resta). Si può rieseguire. Annulla con black-market-eroi-villaggi-cibo-down.sql
-- =====================================================================================
begin;

create or replace function public._vil_food_prod(p_level integer) returns numeric language sql immutable as $$     -- cibo all'ora della Fattoria
  select case when p_level <= 0 then 0 else round(60 * p_level * power(1.2, p_level - 1)) end $$;

create or replace function public._vil_sync(p_plot integer) returns public.game_villages language plpgsql security definer set search_path = public as $$
declare v public.game_villages%rowtype; hrs numeric; cap numeric; vcap numeric; up integer;
begin
  select * into v from public.game_villages where plot_id = p_plot for update;
  if not found then return v; end if;
  hrs := greatest(0, extract(epoch from now() - v.res_at) / 3600.0);
  if hrs > 0 then
    cap := public._vil_cap(v.warehouse); up := public._vil_upkeep(p_plot);
    vcap := public._vil_bc_day(v.hall) * 2;
    update public.game_villages set
      wood  = greatest(wood,  least(cap, wood  + public._vil_prod(lumber) * hrs)),
      stone = greatest(stone, least(cap, stone + public._vil_prod(quarry) * hrs)),
      food  = case when public._vil_food_prod(farm) >= up then greatest(food, least(cap, food + (public._vil_food_prod(farm) - up) * hrs))
                   else greatest(0, food + (public._vil_food_prod(farm) - up) * hrs) end,
      vault = case when vault >= vcap then vault else least(vcap, vault + public._vil_bc_day(hall) * hrs / 24.0) end,
      res_at = now()
     where plot_id = p_plot returning * into v;
  end if;
  return v;
end $$;

create or replace function public._vil_tick() returns void language plpgsql security definer set search_path = public as $$
declare m record; d public.game_villages%rowtype; a public.game_villages%rowtype; atk integer[]; def integer[]; mil integer;
  ap numeric; dp numeric; v_won boolean; la numeric; ld numeric; back integer[]; dlost integer[]; carry numeric; hidden numeric; avail numeric[]; tot numeric;
  take numeric; lw integer; ls integer; lf integer; lb integer; na text; nd text; mins integer; luck numeric; starvA boolean; starvD boolean;
begin
  for m in select * from public.game_village_marches where status = 'going' and arrive_at <= now() order by arrive_at for update skip locked loop
    a := public._vil_sync(m.attacker_plot); d := public._vil_sync(m.defender_plot);
    select nickname into na from public.profiles where id = m.attacker_id;
    select nickname into nd from public.profiles where id = m.defender_id;
    atk := array[m.inf, m.arc, m.cav];
    lw := 0; ls := 0; lf := 0; lb := 0; starvA := false; starvD := false;
    if d.plot_id is null or d.user_id <> m.defender_id then      -- il villaggio non c'è più: si torna a casa
      v_won := false; back := atk; dlost := array[0,0,0]; def := array[0,0,0]; ap := 0; dp := 0; mil := 0;
    else
      mil := 5 * d.hall;
      def := array[d.def_inf + mil, d.def_arc, d.def_cav];
      starvA := a.plot_id is not null and a.food <= 0 and public._vil_food_prod(a.farm) < public._vil_upkeep(m.attacker_plot);
      starvD := d.food <= 0 and public._vil_food_prod(d.farm) < public._vil_upkeep(m.defender_plot);
      luck := 0.9 + random() * 0.2;
      ap := public._vil_power(atk, def, true) * luck * case when starvA then 0.5 else 1 end;
      dp := public._vil_power(def, atk, false) * (1 + 0.1 * d.wall) * case when starvD then 0.5 else 1 end;
      v_won := ap > dp;
      if v_won then la := case when ap > 0 then power(dp / ap, 1.5) else 1 end; ld := 0.7;
      else la := 0.7; ld := case when dp > 0 then power(ap / dp, 1.5) else 0 end; end if;
      back := array[m.inf - ceil(m.inf * la), m.arc - ceil(m.arc * la), m.cav - ceil(m.cav * la)]::integer[];
      dlost := array[ceil(d.def_inf * ld), ceil(d.def_arc * ld), ceil(d.def_cav * ld)]::integer[];
      update public.game_villages set inf = inf - dlost[1], arc = arc - dlost[2], cav = cav - dlost[3],
             def_inf = def_inf - dlost[1], def_arc = def_arc - dlost[2], def_cav = def_cav - dlost[3],
             def_won = def_won + case when v_won then 0 else 1 end, def_lost = def_lost + case when v_won then 1 else 0 end,
             shield_until = case when v_won then greatest(coalesce(shield_until, now()), now() + make_interval(hours => coalesce(public._setting('game_village_defeat_shield'), 8))) else shield_until end
       where plot_id = d.plot_id returning * into d;
      if v_won then
        carry := back[1] * 25 + back[2] * 15 + back[3] * 50;
        hidden := public._vil_cap(d.warehouse) * coalesce(public._setting('game_village_hidden_pct'), 20) / 100.0;
        avail := array[greatest(0, d.wood - hidden), greatest(0, d.stone - hidden), greatest(0, d.food - hidden),
                       floor(d.vault * coalesce(public._setting('game_village_loot_bc_pct'), 25) / 100.0)];
        tot := avail[1] + avail[2] + avail[3] + avail[4];
        if tot > 0 and carry > 0 then
          take := least(1, carry / tot);
          lw := floor(avail[1] * take); ls := floor(avail[2] * take); lf := floor(avail[3] * take); lb := floor(avail[4] * take);
          update public.game_villages set wood = wood - lw, stone = stone - ls, food = food - lf, vault = vault - lb where plot_id = d.plot_id;
        end if;
      end if;
      update public.game_villages set att_won = att_won + case when v_won then 1 else 0 end, att_lost = att_lost + case when v_won then 0 else 1 end
       where plot_id = m.attacker_plot;
    end if;
    mins := greatest(1, ceil(extract(epoch from m.arrive_at - m.depart_at) / 60.0))::integer;
    update public.game_village_marches set status = 'returning', won = v_won, back_inf = back[1], back_arc = back[2], back_cav = back[3],
           return_at = m.arrive_at + make_interval(mins => mins), loot_wood = lw, loot_stone = ls, loot_food = lf, loot_bc = lb,
           report = jsonb_build_object('atk', atk, 'def', def, 'militia', mil, 'wall', coalesce(d.wall, 0), 'ap', round(ap), 'dp', round(dp),
                    'back', back, 'def_lost', dlost, 'att_lost', array[m.inf - back[1], m.arc - back[2], m.cav - back[3]],
                    'att_name', na, 'def_name', nd, 'att_village', a.name, 'def_village', d.name, 'starv_att', starvA, 'starv_def', starvD)
     where id = m.id;
    if d.plot_id is not null and d.user_id = m.defender_id then
      perform public._notify(m.attacker_id, 'village', case when v_won then '⚔️ Vittoria contro ' || d.name else '⚔️ Sconfitta contro ' || d.name end,
        case when v_won then 'L''esercito di ' || coalesce(a.name, 'tuo') || ' torna con ' || lw || ' legno, ' || ls || ' pietra, ' || lf || ' cibo e ' || lb || ' BC.'
             else 'L''esercito di ' || coalesce(a.name, 'tuo') || ' è stato respinto: tornano ' || (back[1] + back[2] + back[3]) || ' soldati.' end, 'eroi.html#map', 'game_village', null);
      perform public._notify(m.defender_id, 'village', case when v_won then '🔥 ' || na || ' ha saccheggiato ' || d.name else '🛡️ ' || d.name || ' ha respinto ' || na end,
        case when v_won then 'Hai perso ' || lw || ' legno, ' || ls || ' pietra, ' || lf || ' cibo e ' || lb || ' BC. Il villaggio ha 8 ore di tregua.'
             else 'La guarnigione ha tenuto: ' || (dlost[1] + dlost[2] + dlost[3]) || ' caduti fra i tuoi difensori.' end, 'eroi.html#map', 'game_village', null);
      perform public._tavern_log(case when v_won then m.attacker_id else m.defender_id end, 'village',
        case when v_won then 'ha saccheggiato il villaggio ' || d.name || ' di ' || nd else 'ha respinto l''attacco di ' || na || ' a ' || d.name end);
    end if;
  end loop;
  -- eserciti tornati a casa: soldati e bottino
  for m in select * from public.game_village_marches where status = 'returning' and return_at <= now() order by return_at for update skip locked loop
    a := public._vil_sync(m.attacker_plot);
    if a.plot_id is not null and a.user_id = m.attacker_id then
      update public.game_villages set inf = inf + m.back_inf, arc = arc + m.back_arc, cav = cav + m.back_cav,
             wood = least(greatest(wood, public._vil_cap(warehouse)), wood + m.loot_wood), stone = least(greatest(stone, public._vil_cap(warehouse)), stone + m.loot_stone),
             food = least(greatest(food, public._vil_cap(warehouse)), food + m.loot_food), vault = vault + m.loot_bc, loot_bc = loot_bc + m.loot_bc
       where plot_id = m.attacker_plot;
    end if;
    update public.game_village_marches set status = 'done' where id = m.id;
  end loop;
end $$;

create or replace function public.game_village_state(p_plot integer default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); me public.game_villages%rowtype; h public.game_heroes%rowtype;
  d date := (now() at time zone 'Europe/Rome')::date; away integer[]; b text; blds jsonb := '[]'::jsonb; gap integer := coalesce(public._setting('game_village_hall_gap'), 3);
  cur integer;
begin
  perform public._require_module('heroes');
  if coalesce(public._setting('game_map_enabled'), 0) <> 1 or coalesce(public._setting('game_village_enabled'), 0) <> 1 then return jsonb_build_object('enabled', false); end if;
  perform public._vil_tick();
  -- aggiorna tutti i miei villaggi
  perform public._vil_sync(x.plot_id) from public.game_villages x where x.user_id = v;
  select plot_id into cur from public.game_villages where user_id = v and plot_id = p_plot;
  if cur is null then select plot_id into cur from public.game_villages where user_id = v order by founded_at, plot_id limit 1; end if;
  if cur is not null then select * into me from public.game_villages where plot_id = cur; end if;
  select * into h from public.game_heroes where user_id = v;
  if me.plot_id is not null then
    away := public._vil_away(me.plot_id);
    foreach b in array array['hall','lumber','quarry','farm','warehouse','barracks','wall'] loop
      blds := blds || jsonb_build_object('k', b, 'level', (to_jsonb(me)->>b)::int,
        'next', case when (to_jsonb(me)->>b)::int < public._vil_max_level() then to_jsonb(public._vil_cost(b, (to_jsonb(me)->>b)::int + 1)) else null end);
    end loop;
  end if;
  return jsonb_build_object('enabled', true, 'now', now(),
    'rules', jsonb_build_object('found_cost', public._vil_found_cost(v), 'max_level', public._vil_max_level(),
      'attacks_daily', public._setting('game_village_attacks_daily'), 'hall_gap', gap, 'hidden_pct', public._setting('game_village_hidden_pct'),
      'loot_bc_pct', public._setting('game_village_loot_bc_pct'),
      'units', jsonb_build_object('inf', to_jsonb(public._vil_unit('inf')), 'arc', to_jsonb(public._vil_unit('arc')), 'cav', to_jsonb(public._vil_unit('cav')))),
    -- i miei villaggi in breve (per passare dall'uno all'altro)
    'mine', coalesce((select jsonb_agg(jsonb_build_object('plot', x.plot_id, 'name', x.name, 'hall', x.hall, 'region', l.region_no, 'vault', floor(x.vault),
                  'army', x.inf + x.arc + x.cav, 'shield', x.shield_until > now(),
                  'incoming', (select count(*) from public.game_village_marches m where m.defender_plot = x.plot_id and m.status = 'going')) order by x.founded_at, x.plot_id)
                from public.game_villages x join public.game_land l on l.id = x.plot_id where x.user_id = v), '[]'::jsonb),
    'me', case when me.plot_id is null then null else jsonb_build_object(
      'name', me.name, 'plot', me.plot_id, 'founded_at', me.founded_at,
      'hall', me.hall, 'lumber', me.lumber, 'quarry', me.quarry, 'farm', me.farm, 'warehouse', me.warehouse, 'barracks', me.barracks, 'wall', me.wall,
      'wood', floor(me.wood), 'stone', floor(me.stone), 'food', floor(me.food), 'vault', floor(me.vault),
      'cap', public._vil_cap(me.warehouse), 'hidden', floor(public._vil_cap(me.warehouse) * coalesce(public._setting('game_village_hidden_pct'), 20) / 100.0),
      'prod', jsonb_build_array(public._vil_prod(me.lumber), public._vil_prod(me.quarry), public._vil_food_prod(me.farm)),
      'upkeep', public._vil_upkeep(me.plot_id), 'bc_day', public._vil_bc_day(me.hall), 'vault_cap', public._vil_bc_day(me.hall) * 2,
      'army', jsonb_build_array(me.inf, me.arc, me.cav), 'def', jsonb_build_array(me.def_inf, me.def_arc, me.def_cav), 'away', to_jsonb(away),
      'army_cap', public._vil_army_cap(me.barracks), 'militia', 5 * me.hall,
      'shield_until', case when me.shield_until > now() then me.shield_until end,
      'stats', jsonb_build_object('att_won', me.att_won, 'att_lost', me.att_lost, 'def_won', me.def_won, 'def_lost', me.def_lost, 'loot_bc', me.loot_bc, 'collected', me.collected),
      'attacks_today', (select count(*) from public.game_village_marches where attacker_plot = me.plot_id and (depart_at at time zone 'Europe/Rome')::date = d),
      'buildings', blds) end,
    'my_plots', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'region', l.region_no, 'level', l.level) order by l.region_no, l.id)
                  from public.game_land l where l.owner_id = v and not exists (select 1 from public.game_villages x where x.plot_id = l.id)), '[]'::jsonb),
    -- tutti i villaggi (per la mappa e per scegliere chi attaccare; tempi di marcia dal villaggio mostrato)
    'villages', coalesce((select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'nickname', p.nickname, 'name', x.name, 'plot', x.plot_id, 'hall', x.hall, 'wall', x.wall,
                  'shield_until', case when x.shield_until > now() then x.shield_until end, 'won', x.att_won + x.def_won,
                  'min', case when me.plot_id is not null and x.user_id <> v then public._vil_minutes(me.plot_id, x.plot_id, false) end,
                  'min_cav', case when me.plot_id is not null and x.user_id <> v then public._vil_minutes(me.plot_id, x.plot_id, true) end,
                  'too_small', me.plot_id is not null and x.hall < me.hall - gap)
                order by case when me.plot_id is not null and x.user_id <> v then public._vil_minutes(me.plot_id, x.plot_id, false) else 0 end, x.name)
                from public.game_villages x join public.profiles p on p.id = x.user_id), '[]'::jsonb),
    'marches', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'out', m.attacker_id = v, 'status', m.status,
                  'other', case when m.attacker_id = v then pd.nickname else pa.nickname end,
                  'from', va.name, 'from_plot', m.attacker_plot, 'to', vd.name, 'to_plot', m.defender_plot,
                  'army', case when m.attacker_id = v then jsonb_build_array(m.inf, m.arc, m.cav) end,
                  'back', case when m.attacker_id = v and m.status = 'returning' then jsonb_build_array(m.back_inf, m.back_arc, m.back_cav) end,
                  'won', m.won, 'arrive_at', m.arrive_at, 'return_at', m.return_at,
                  'loot', case when m.attacker_id = v and m.status = 'returning' then jsonb_build_array(m.loot_wood, m.loot_stone, m.loot_food, m.loot_bc) end)
                order by case when m.status = 'going' then m.arrive_at else m.return_at end)
                from public.game_village_marches m join public.profiles pa on pa.id = m.attacker_id join public.profiles pd on pd.id = m.defender_id
                left join public.game_villages va on va.plot_id = m.attacker_plot left join public.game_villages vd on vd.plot_id = m.defender_plot
               where (m.attacker_id = v and m.status <> 'done') or (m.defender_id = v and m.status = 'going')), '[]'::jsonb),
    -- tutti gli eserciti in marcia sull'isola (per vederli muoversi sulla mappa; senza dire quanti sono)
    'armies', coalesce((select jsonb_agg(jsonb_build_object('attacker_id', m.attacker_id, 'from_plot', m.attacker_plot, 'to_plot', m.defender_plot, 'status', m.status,
                  'depart_at', m.depart_at, 'arrive_at', m.arrive_at, 'return_at', m.return_at, 'inc', m.defender_id = v and m.status = 'going'))
                from (select * from public.game_village_marches where status <> 'done' order by depart_at desc limit 80) m), '[]'::jsonb),
    'reports', coalesce((select jsonb_agg(jsonb_build_object('id', y.id, 'out', y.attacker_id = v, 'won', y.won, 'at', y.arrive_at, 'report', y.report,
                  'loot', jsonb_build_array(y.loot_wood, y.loot_stone, y.loot_food, y.loot_bc)) order by y.arrive_at desc)
                from (select * from public.game_village_marches where (attacker_id = v or defender_id = v) and status <> 'going' order by arrive_at desc limit 20) y), '[]'::jsonb),
    'hero_level', coalesce(h.level, 1));
end $$;

revoke all on function public._vil_food_prod(integer), public._vil_sync(integer), public._vil_tick() from public, anon, authenticated;
revoke all on function public.game_village_state(integer) from public, anon, authenticated;
grant execute on function public.game_village_state(integer) to authenticated;

commit;
