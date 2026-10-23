-- ANNULLAMENTO DELLA MIGRAZIONE 021 (premi a tutta la lobby e lobby multiple del boss).
-- Torna a un'unica lobby condivisa al giorno, con il minimo di azioni per ricevere il premio.
--   · il boss di ogni giorno riprende lo stato della lobby che l'ha sconfitto (se nessuna, della prima partita, altrimenti della prima);
--   · se oggi ci sono più lobby, tutti i loro giocatori finiscono nell'unica lobby del giorno (e restano quelli già premiati);
--   · BC, XP, oggetti e registro non si toccano: i premi già dati restano dati.
begin;

update public.game_days d set
  status = case when d.status in ('lobby','open') then s.status else d.status end,
  boss_level = s.boss_level, max_hp = s.max_hp, hp = s.hp, shield = s.shield, weak = s.weak,
  started_at = s.started_at, defeated_at = coalesce(s.defeated_at, d.defeated_at)
from (select distinct on (l.day) l.* from public.game_lobbies l
      order by l.day, (l.status = 'defeated') desc, (l.status = 'open') desc, l.id) s
where s.day = d.day;

drop function if exists public.game_boss_join(bigint);
drop function if exists public._game_finish_lobby(bigint);
alter table public.game_day_heroes drop column if exists lobby_id;
alter table public.game_day_log drop column if exists lobby_id;
drop table if exists public.game_lobbies;

insert into public.system_settings (key, value_int, description) values
 ('game_boss_min_actions', 2, 'Eroi: azioni minime per contare come partecipante al boss')
on conflict (key) do nothing;
update public.system_settings set value_int = 3 where key = 'game_boss_min_players' and value_int = 1;
update public.system_settings set description = 'Eroi: giocatori minimi nella lobby per far partire il boss' where key = 'game_boss_min_players';
update public.system_settings set description = 'Eroi: BC a ogni partecipante per boss sconfitto' where key = 'game_boss_bc';

-- funzioni come prima della 021
create or replace function public._game_finish_boss(p_day date) returns void language plpgsql security definer set search_path = public as $$
declare dy public.game_days%rowtype; r record; v_bc integer := public._setting('game_boss_bc'); v_min integer := greatest(1, public._setting('game_boss_min_actions'));
        v_item text; v_xp bigint; rw jsonb;
begin
  select * into dy from public.game_days where day = p_day for update;
  if dy.status = 'defeated' and exists (select 1 from public.game_rewards where day = p_day) then return; end if;
  update public.game_days set status = 'defeated', hp = 0, defeated_at = coalesce(defeated_at, now()) where day = p_day;
  for r in select dh.user_id, h.level from public.game_day_heroes dh
             join public.game_heroes h on h.user_id = dh.user_id join public.profiles p on p.id = dh.user_id
           where dh.day = p_day and dh.actions_used >= v_min and not p.suspended order by dh.user_id loop
    v_xp := 2 * (40 + 2 * r.level);                       -- XP doppia rispetto a battere un eroe del tuo livello
    v_item := public._game_draw_item(r.user_id, dy.boss_no::integer);
    if v_item is not null then insert into public.game_inventory (user_id, item_id, source) values (r.user_id, v_item, 'boss'); end if;
    if v_bc > 0 then
      perform public._ledger_move(r.user_id, v_bc, 'game_boss_reward', 'game_day', null, 'gameboss:' || p_day::text || ':' || r.user_id::text, 'La guerra degli Eroi: boss sconfitto');
    end if;
    rw := public._game_add_xp(r.user_id, v_xp);
    insert into public.game_rewards (day, user_id, boss_no, bc, xp, item_id, levels_gained)
      values (p_day, r.user_id, dy.boss_no, v_bc, (rw->>'xp')::bigint, v_item, (rw->>'levels')::integer);
    update public.game_heroes set bosses_beaten = bosses_beaten + 1 where user_id = r.user_id;
  end loop;
end $$;

create or replace function public._game_ensure_day() returns date language plpgsql security definer set search_path = public as $$
declare d date := public._game_today(); last_ public.game_days%rowtype; v_idx integer; v_cycle integer; v_nb integer;
begin
  if exists (select 1 from public.game_days where day = d) then return d; end if;
  perform pg_advisory_xact_lock(hashtext('game_day'));
  if exists (select 1 from public.game_days where day = d) then return d; end if;
  select count(*) into v_nb from public.game_bosses;
  select * into last_ from public.game_days where day < d order by day desc limit 1;
  if not found then v_idx := 1; v_cycle := 0;
  elsif last_.status = 'defeated' then
    v_idx := last_.boss_no + 1; v_cycle := last_.cycle;
    if v_idx > v_nb then v_idx := 1; v_cycle := v_cycle + 1; end if;
  else v_idx := last_.boss_no; v_cycle := last_.cycle; end if;
  update public.game_days set status = 'escaped' where status in ('open', 'lobby') and day < d;
  insert into public.game_days (day, boss_no, cycle, boss_level, max_hp, hp, status) values (d, v_idx, v_cycle, 1, 0, 0, 'lobby');
  return d;
end $$;

create or replace function public.game_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date; dy public.game_days%rowtype; bo public.game_bosses%rowtype; prev public.game_days%rowtype; c record; dh public.game_day_heroes%rowtype;
  v_acts integer; v_fights integer; v_found boolean; en numeric; reg numeric; emax integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  update public.game_heroes set last_active_at = now() where user_id = v;
  d := public._game_ensure_day();
  perform public._game_ensure_merchant(d);
  select * into dy from public.game_days where day = d;
  select * into bo from public.game_bosses where no = dy.boss_no;
  select * into c from public._game_calc(v);
  select * into dh from public.game_day_heroes where day = d and user_id = v;
  v_found := found;
  v_acts := greatest(1, public._setting('game_daily_actions')) + c.extra_actions;
  select count(*) into v_fights from public.game_duels where day = d and attacker_id = v;
  select * into prev from public.game_days where day < d order by day desc limit 1;
  en := public._game_energy_of(v); reg := public._game_energy_rate(v); emax := public._game_energy_max();
  return jsonb_build_object(
    'me', public._game_hero_json(v),
    'today', d, 'next_reset', public._game_next_reset(),
    'settings', jsonb_build_object('points', public._setting('game_stat_points'), 'cap', public._setting('game_stat_cap'), 'actions', public._setting('game_daily_actions'),
        'points_per_level', public._setting('game_points_per_level'), 'min_players', public._setting('game_boss_min_players'), 'temp_hours', public._setting('game_temp_hours'), 'boss_bc', public._setting('game_boss_bc'), 'min_actions', public._setting('game_boss_min_actions'),
        'respec_cost', public._setting('game_respec_cost')),
    'boss', jsonb_build_object(
        'no', bo.no, 'name', bo.name, 'emoji', bo.emoji, 'lore', bo.lore, 'trait', bo.trait, 'total', (select count(*) from public.game_bosses),
        'cycle', dy.cycle, 'level', dy.boss_level, 'hp', dy.hp, 'max_hp', dy.max_hp, 'shield', dy.shield, 'weak', dy.weak, 'status', dy.status,
        'retal', bo.retal, 'defeated_at', dy.defeated_at, 'joined', v_found, 'min_players', public._setting('game_boss_min_players'), 'started_at', dy.started_at,
        'actions_left', case when v_found then greatest(0, v_acts - dh.actions_used) else v_acts end, 'actions_max', v_acts,
        'my', case when v_found then jsonb_build_object('hp', dh.hp, 'max_hp', dh.max_hp, 'actions_used', dh.actions_used, 'dmg', dh.dmg, 'healed', dh.healed, 'shielded', dh.shielded, 'studied', dh.studied)
               else jsonb_build_object('hp', c.max_hp, 'max_hp', c.max_hp, 'actions_used', 0, 'dmg', 0, 'healed', 0, 'shielded', 0, 'studied', 0) end,
        'party', coalesce((select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'nickname', p.nickname, 'avatar', p.avatar, 'hp', x.hp, 'max_hp', x.max_hp, 'actions_used', x.actions_used,
                    'dmg', x.dmg, 'healed', x.healed, 'shielded', x.shielded, 'studied', x.studied) order by x.dmg desc, p.nickname)
                  from public.game_day_heroes x join public.profiles p on p.id = x.user_id where x.day = d), '[]'::jsonb),
        'log', coalesce((select jsonb_agg(jsonb_build_object('nickname', p.nickname, 'action', l.action, 'amount', l.amount, 'target', t.nickname, 'note', l.note, 'at', l.created_at) order by l.id desc)
                  from (select * from public.game_day_log where day = d order by id desc limit 20) l join public.profiles p on p.id = l.user_id left join public.profiles t on t.id = l.target_id), '[]'::jsonb),
        'previous', case when prev.day is null then null else jsonb_build_object('day', prev.day, 'status', prev.status, 'boss', (select name from public.game_bosses where no = prev.boss_no), 'emoji', (select emoji from public.game_bosses where no = prev.boss_no)) end),
    'merchant', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'slot', i.slot, 'rarity', i.rarity, 'tier', i.tier, 'min_level', i.min_level, 'price', o.price, 'list_price', i.price_bc,
                    'discounted', o.discounted, 'p_for', i.p_for, 'p_des', i.p_des, 'p_vig', i.p_vig, 'p_spi', i.p_spi, 'p_frt', i.p_frt, 'xp_pct', i.xp_pct, 'extra_actions', i.extra_actions, 'extra_fights', i.extra_fights,
                    'owned', exists (select 1 from public.game_inventory g where g.user_id = v and g.item_id = i.id)) order by i.slot, i.tier)
                  from public.game_merchant_offers o join public.game_items i on i.id = o.item_id where o.day = d), '[]'::jsonb),
    'inventory', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'slot', i.slot, 'rarity', i.rarity, 'tier', i.tier, 'min_level', i.min_level, 'source', g.source,
                    'p_for', i.p_for, 'p_des', i.p_des, 'p_vig', i.p_vig, 'p_spi', i.p_spi, 'p_frt', i.p_frt, 'xp_pct', i.xp_pct, 'extra_actions', i.extra_actions, 'extra_fights', i.extra_fights, 'descr', i.descr,
                    'equipped', exists (select 1 from public.game_equipped e where e.user_id = v and e.item_id = i.id)) order by i.slot, i.tier, i.id)
                  from public.game_inventory g join public.game_items i on i.id = g.item_id where g.user_id = v), '[]'::jsonb),
    'duels', jsonb_build_object('used', v_fights,         'recent', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'attacker', pa.nickname, 'defender', pd.nickname, 'winner', pw.nickname, 'attacker_id', q.attacker_id, 'defender_id', q.defender_id,
                    'xp', q.xp_awarded, 'rounds', q.rounds, 'atk_level', q.atk_level, 'def_level', q.def_level, 'at', q.created_at) order by q.created_at desc)
                  from (select * from public.game_duels where attacker_id = v or defender_id = v order by created_at desc limit 10) q
                  join public.profiles pa on pa.id = q.attacker_id join public.profiles pd on pd.id = q.defender_id join public.profiles pw on pw.id = q.winner_id), '[]'::jsonb)),
    'rewards', coalesce((select jsonb_agg(jsonb_build_object('day', r.day, 'boss', b.name, 'emoji', b.emoji, 'bc', r.bc, 'xp', r.xp, 'item', it.name, 'item_rarity', it.rarity, 'levels', r.levels_gained) order by r.created_at desc)
                  from (select * from public.game_rewards where user_id = v order by created_at desc limit 5) r join public.game_bosses b on b.no = r.boss_no left join public.game_items it on it.id = r.item_id), '[]'::jsonb),
    'energy', jsonb_build_object('value', round(en, 2), 'max', emax, 'per_hour', round(reg, 3),
        'full_in_s', case when en >= emax then 0 else ceil((emax - en) / reg * 3600)::bigint end,
        'win', public._setting('game_energy_win'), 'loss', public._setting('game_energy_loss'),
        'min', greatest(public._setting('game_energy_win'), public._setting('game_energy_loss'))),
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'kind', k.kind, 'stat', k.stat, 'slot', k.slot, 'tier', k.tier, 'min_level', k.min_level, 'price', k.price_bc,
            'p_for', k.p_for, 'p_des', k.p_des, 'p_vig', k.p_vig, 'p_spi', k.p_spi, 'p_frt', k.p_frt, 'descr', k.descr,
            'owned', exists (select 1 from public.game_hero_skills s where s.user_id = v and s.skill_id = k.id),
            'prev', (select p.name from public.game_skills p where p.kind = 'perm' and p.stat = k.stat and p.tier = k.tier - 1),
            'prev_owned', k.kind = 'temp' or k.tier = 1 or exists (select 1 from public.game_skills p join public.game_hero_skills s on s.skill_id = p.id and s.user_id = v where p.kind = 'perm' and p.stat = k.stat and p.tier = k.tier - 1),
            'active_until', (select max(t.expires_at) from public.game_temp_skills t where t.user_id = v and t.skill_id = k.id and t.expires_at > now()))
          order by k.kind desc, coalesce(k.stat, k.slot), k.tier) from public.game_skills k), '[]'::jsonb)
  );
end $$;

create or replace function public.game_boss_act(p_action text, p_target uuid default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date; dy public.game_days%rowtype; bo public.game_bosses%rowtype; h public.game_heroes%rowtype; c record; dh public.game_day_heroes%rowtype; th public.game_day_heroes%rowtype;
  v_lim integer; ref numeric; amt bigint := 0; crit boolean := false; dodge boolean := false; raw numeric := 0; took bigint := 0; absorbed bigint := 0; v_hp bigint; v_new bigint;
  v_note text := null; v_target uuid := null; v_dead boolean := false; v_weak integer; res jsonb; rw jsonb;
begin
  perform public._require_module('heroes');
  if p_action is null or p_action not in ('attack','guard','heal','study') then raise exception 'Azione non valida'; end if;
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v;
  if not h.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  d := public._game_ensure_day();
  select * into dy from public.game_days where day = d for update;
  if dy.status = 'lobby' then raise exception 'Il boss non è ancora partito: serve la lobby con almeno % giocatori', public._setting('game_boss_min_players'); end if;
  if dy.status <> 'open' then raise exception 'Il boss di oggi è già stato sconfitto: torna domani'; end if;
  select * into bo from public.game_bosses where no = dy.boss_no;
  select * into c from public._game_calc(v);
  select * into dh from public.game_day_heroes where day = d and user_id = v for update;
  if not found then raise exception 'Non sei nella lobby di oggi: il boss è partito senza di te'; end if;
  v_lim := greatest(1, public._setting('game_daily_actions')) + c.extra_actions;
  if dh.actions_used >= v_lim then raise exception 'Hai usato tutte le azioni di oggi: torna domani'; end if;
  if dh.hp <= 0 then raise exception 'Sei esausto: un alleato deve curarti per tornare in battaglia'; end if;
  ref := 5 + 10 * c.level;

  if p_action = 'attack' then
    crit := random() < least(0.6, 0.05 + 0.4 * c.s_des / ref);
    amt := greatest(1, round(c.s_for * 3 * (0.85 + 0.3 * random()) * (case when crit then 1.6 else 1 end) * (1 + dy.weak / 100.0) * bo.dmg_taken)::bigint);
    v_hp := greatest(0, dy.hp - amt);
    update public.game_days set hp = v_hp where day = d;
    v_dead := v_hp = 0;
    if not v_dead then      -- il boss reagisce: una frazione dei PV dell'eroe, assorbita prima dallo scudo comune
      dodge := random() < least(0.5, 0.03 + 0.35 * c.s_frt / ref);
      if not dodge then
        raw := dh.max_hp * bo.retal * (1 + 0.1 * dy.cycle) * (0.9 + 0.2 * random());
        absorbed := least(dy.shield, round(raw)::bigint);
        took := greatest(0, round(raw)::bigint - absorbed);
        update public.game_days set shield = shield - absorbed where day = d;
        update public.game_day_heroes set hp = greatest(0, hp - took) where day = d and user_id = v;
      end if;
    end if;
    v_note := case when v_dead then 'colpo finale' when dodge then 'schivata' when crit then 'critico' else null end;
    update public.game_day_heroes set dmg = dmg + amt where day = d and user_id = v;
  elsif p_action = 'guard' then
    amt := greatest(1, round(c.s_vig * 4 * bo.shield_eff * (0.9 + 0.2 * random()))::bigint);
    update public.game_days set shield = shield + amt where day = d;
    update public.game_day_heroes set shielded = shielded + amt where day = d and user_id = v;
  elsif p_action = 'heal' then
    v_target := coalesce(p_target, v);
    select * into th from public.game_day_heroes where day = d and user_id = v_target for update;
    if not found then raise exception 'Questo eroe non è ancora sceso in campo oggi'; end if;
    if th.hp >= th.max_hp then raise exception 'Non ha bisogno di cure'; end if;
    amt := greatest(1, round(c.s_spi * 6 * bo.heal_eff * (0.9 + 0.2 * random()))::bigint);
    v_new := least(th.max_hp, th.hp + amt);
    v_note := case when th.hp <= 0 then 'rianimato' else null end;
    amt := v_new - th.hp;
    update public.game_day_heroes set hp = v_new where day = d and user_id = v_target;
    update public.game_day_heroes set healed = healed + amt where day = d and user_id = v;
  else  -- study: svela una debolezza (percentuale, non dipende dal livello), al massimo +40% in totale
    if dy.weak >= 40 then raise exception 'Hai già scoperto tutte le debolezze del boss di oggi'; end if;
    v_weak := 2 + round(6 * least(1, c.s_des / ref))::integer;
    v_weak := least(v_weak, 40 - dy.weak);
    amt := v_weak;
    update public.game_days set weak = weak + v_weak where day = d;
    update public.game_day_heroes set studied = studied + v_weak where day = d and user_id = v;
  end if;

  update public.game_day_heroes set actions_used = actions_used + 1 where day = d and user_id = v;
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1 where user_id = v;
  insert into public.game_day_log (day, user_id, action, amount, target_id, note) values (d, v, p_action, amt, v_target, v_note);
  if v_dead then perform public._game_finish_boss(d); end if;

  select * into dy from public.game_days where day = d;
  select * into dh from public.game_day_heroes where day = d and user_id = v;
  res := jsonb_build_object('action', p_action, 'amount', amt, 'crit', crit, 'dodge', dodge, 'taken', took, 'absorbed', absorbed, 'note', v_note,
           'my_hp', dh.hp, 'my_max_hp', dh.max_hp, 'ko', dh.hp <= 0, 'boss_hp', dy.hp, 'boss_max_hp', dy.max_hp, 'shield', dy.shield, 'weak', dy.weak,
           'defeated', dy.status = 'defeated', 'actions_left', greatest(0, v_lim - dh.actions_used));
  if v_dead then
    select jsonb_build_object('bc', r.bc, 'xp', r.xp, 'levels', r.levels_gained, 'item', (select name from public.game_items where id = r.item_id))
      into rw from public.game_rewards r where r.day = d and r.user_id = v;
    res := res || jsonb_build_object('reward', rw);
  end if;
  return res;
end $$;

create or replace function public.game_boss_join() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date; dy public.game_days%rowtype; h public.game_heroes%rowtype; c record; n integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v;
  if not h.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  d := public._game_ensure_day();
  select * into dy from public.game_days where day = d for update;
  if dy.status = 'open' then raise exception 'Il boss è già partito: si entra solo prima dell''inizio'; end if;
  if dy.status <> 'lobby' then raise exception 'Il boss di oggi è già stato sconfitto: torna domani'; end if;
  select * into c from public._game_calc(v);
  insert into public.game_day_heroes (day, user_id, hp, max_hp) values (d, v, c.max_hp, c.max_hp) on conflict do nothing;
  select count(*) into n from public.game_day_heroes where day = d;
  return jsonb_build_object('players', n, 'needed', public._setting('game_boss_min_players'));
end $$;

create or replace function public.game_boss_leave() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date; dy public.game_days%rowtype; n integer;
begin
  perform public._require_module('heroes');
  d := public._game_ensure_day();
  select * into dy from public.game_days where day = d for update;
  if dy.status <> 'lobby' then raise exception 'Il boss è già partito: non si può più uscire'; end if;
  delete from public.game_day_heroes where day = d and user_id = v;
  select count(*) into n from public.game_day_heroes where day = d;
  return jsonb_build_object('players', n, 'needed', public._setting('game_boss_min_players'));
end $$;

create or replace function public.game_boss_start() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date; dy public.game_days%rowtype; bo public.game_bosses%rowtype; r record; c record; n integer := 0; v_min integer := greatest(1, public._setting('game_boss_min_players'));
  sum_hit numeric := 0; sum_lvl numeric := 0; v_hp bigint;
begin
  perform public._require_module('heroes');
  d := public._game_ensure_day();
  select * into dy from public.game_days where day = d for update;
  if dy.status = 'open' then raise exception 'Il boss è già partito'; end if;
  if dy.status <> 'lobby' then raise exception 'Il boss di oggi è già stato sconfitto: torna domani'; end if;
  if not exists (select 1 from public.game_day_heroes where day = d and user_id = v) then raise exception 'Entra prima nella lobby'; end if;
  select * into bo from public.game_bosses where no = dy.boss_no;
  for r in select x.user_id from public.game_day_heroes x join public.profiles p on p.id = x.user_id where x.day = d and not p.suspended order by x.user_id loop
    select * into c from public._game_calc(r.user_id);
    update public.game_day_heroes set max_hp = c.max_hp, hp = c.max_hp where day = d and user_id = r.user_id;      -- l'equipaggiamento può essere cambiato dopo l'ingresso
    sum_hit := sum_hit + c.s_for * 3; sum_lvl := sum_lvl + c.level; n := n + 1;
  end loop;
  delete from public.game_day_heroes x using public.profiles p where x.day = d and p.id = x.user_id and p.suspended;
  if n < v_min then raise exception 'Servono almeno % giocatori nella lobby (ora %)', v_min, n; end if;
  v_hp := greatest(50, ceil(sum_hit * greatest(1, public._setting('game_daily_actions')) * bo.coverage * (1 + 0.25 * dy.cycle) * greatest(10, public._setting('game_boss_difficulty')) / 100.0))::bigint;
  update public.game_days set status = 'open', max_hp = v_hp, hp = v_hp, boss_level = greatest(1, round(sum_lvl / n)::integer), started_at = now() where day = d;
  return jsonb_build_object('players', n, 'boss_hp', v_hp);
end $$;

revoke all on function public._game_ensure_day(), public._game_finish_boss(date) from public, anon, authenticated;
revoke all on function public.game_state(), public.game_boss_act(text, uuid), public.game_boss_join(), public.game_boss_leave(), public.game_boss_start() from public, anon, authenticated;
grant execute on function public.game_state(), public.game_boss_act(text, uuid), public.game_boss_join(), public.game_boss_leave(), public.game_boss_start() to authenticated;
commit;
