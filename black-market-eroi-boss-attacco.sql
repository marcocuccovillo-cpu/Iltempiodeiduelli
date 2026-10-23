-- MIGRAZIONE 027 — Boss del giorno: l'attacco non conta come azione giornaliera, e il boss fa male davvero.
-- Prima: 3 azioni al giorno in tutto (attacca, difendi, cura, studia) e il boss moriva dopo ~3 attacchi a testa,
--        quindi nessuno perdeva mai PV (la rappresaglia è il 10% dei PV per attacco, e un solo scudo la assorbiva tutta).
-- Ora:   · ATTACCARE è illimitato e NON consuma azioni; le azioni giornaliere (3 + oggetti) valgono solo per Difendi, Cura e Studia;
--        · il limite agli attacchi è la salute: ogni attacco costa PV (rappresaglia del boss), a 0 PV sei KO finché un alleato non ti cura;
--        · i PV del boss si calcolano sugli eroi presenti in modo che, in media, ognuno perda una quota dei propri PV per batterlo:
--          25% con il primo boss, fino a 75% con il decimo (poi +25% per ogni giro, al massimo 100%). Scudo, cure e «Studia» abbassano il costo.
--        · la manopola «game_boss_difficulty» (admin) continua a valere. Le lobby già partite oggi tengono i PV già calcolati.
-- Nessun BC coinvolto. Annullamento: black-market-eroi-boss-attacco-down.sql (tornano le funzioni della 021).
-- Le funzioni sono le stesse di black-market-eroi-lobby.sql con due modifiche (azioni) e il nuovo calcolo dei PV del boss.

create or replace function public.game_boss_act(p_action text, p_target uuid default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date; dy public.game_days%rowtype; l public.game_lobbies%rowtype; bo public.game_bosses%rowtype; h public.game_heroes%rowtype; c record; dh public.game_day_heroes%rowtype; th public.game_day_heroes%rowtype;
  v_lim integer; ref numeric; amt bigint := 0; crit boolean := false; dodge boolean := false; raw numeric := 0; took bigint := 0; absorbed bigint := 0; v_hp bigint; v_new bigint;
  v_note text := null; v_target uuid := null; v_dead boolean := false; v_weak integer; res jsonb; rw jsonb;
begin
  perform public._require_module('heroes');
  if p_action is null or p_action not in ('attack','guard','heal','study') then raise exception 'Azione non valida'; end if;
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v;
  if not h.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  d := public._game_ensure_day();
  select * into dh from public.game_day_heroes where day = d and user_id = v;
  if not found then raise exception 'Non sei in nessuna lobby di oggi: creane una o entra in quella di un amico'; end if;
  select * into l from public.game_lobbies where id = dh.lobby_id for update;
  if l.status = 'lobby' then raise exception 'Il boss non è ancora partito: avvialo dalla lobby'; end if;
  if l.status <> 'open' then raise exception 'Hai già sconfitto il boss di oggi con la tua lobby: torna domani'; end if;
  select * into dy from public.game_days where day = d;
  select * into bo from public.game_bosses where no = dy.boss_no;
  select * into c from public._game_calc(v);
  select * into dh from public.game_day_heroes where day = d and user_id = v for update;
  v_lim := greatest(1, public._setting('game_daily_actions')) + c.extra_actions;
  if p_action <> 'attack' and dh.actions_used >= v_lim then raise exception 'Hai usato tutte le azioni di oggi (difendi, cura, studia): l’attacco resta sempre libero'; end if;   -- attaccare non conta come azione giornaliera
  if dh.hp <= 0 then raise exception 'Sei esausto: un alleato deve curarti per tornare in battaglia'; end if;
  ref := 5 + 10 * c.level;

  if p_action = 'attack' then
    crit := random() < least(0.6, 0.05 + 0.4 * c.s_des / ref);
    amt := greatest(1, round(c.s_for * 3 * (0.85 + 0.3 * random()) * (case when crit then 1.6 else 1 end) * (1 + l.weak / 100.0) * bo.dmg_taken)::bigint);
    v_hp := greatest(0, l.hp - amt);
    update public.game_lobbies set hp = v_hp where id = l.id;
    v_dead := v_hp = 0;
    if not v_dead then      -- il boss reagisce: una frazione dei PV dell'eroe, assorbita prima dallo scudo comune
      dodge := random() < least(0.5, 0.03 + 0.35 * c.s_frt / ref);
      if not dodge then
        raw := dh.max_hp * bo.retal * (1 + 0.1 * dy.cycle) * (0.9 + 0.2 * random());
        absorbed := least(l.shield, round(raw)::bigint);
        took := greatest(0, round(raw)::bigint - absorbed);
        update public.game_lobbies set shield = shield - absorbed where id = l.id;
        update public.game_day_heroes set hp = greatest(0, hp - took) where day = d and user_id = v;
      end if;
    end if;
    v_note := case when v_dead then 'colpo finale' when dodge then 'schivata' when crit then 'critico' else null end;
    update public.game_day_heroes set dmg = dmg + amt where day = d and user_id = v;
  elsif p_action = 'guard' then
    amt := greatest(1, round(c.s_vig * 4 * bo.shield_eff * (0.9 + 0.2 * random()))::bigint);
    update public.game_lobbies set shield = shield + amt where id = l.id;
    update public.game_day_heroes set shielded = shielded + amt where day = d and user_id = v;
  elsif p_action = 'heal' then
    v_target := coalesce(p_target, v);
    select * into th from public.game_day_heroes where lobby_id = l.id and user_id = v_target for update;
    if not found then raise exception 'Questo eroe non è nella tua lobby'; end if;
    if th.hp >= th.max_hp then raise exception 'Non ha bisogno di cure'; end if;
    amt := greatest(1, round(c.s_spi * 6 * bo.heal_eff * (0.9 + 0.2 * random()))::bigint);
    v_new := least(th.max_hp, th.hp + amt);
    v_note := case when th.hp <= 0 then 'rianimato' else null end;
    amt := v_new - th.hp;
    update public.game_day_heroes set hp = v_new where day = d and user_id = v_target;
    update public.game_day_heroes set healed = healed + amt where day = d and user_id = v;
  else  -- study: svela una debolezza (percentuale, non dipende dal livello), al massimo +40% in totale
    if l.weak >= 40 then raise exception 'Hai già scoperto tutte le debolezze del boss di oggi'; end if;
    v_weak := 2 + round(6 * least(1, c.s_des / ref))::integer;
    v_weak := least(v_weak, 40 - l.weak);
    amt := v_weak;
    update public.game_lobbies set weak = weak + v_weak where id = l.id;
    update public.game_day_heroes set studied = studied + v_weak where day = d and user_id = v;
  end if;

  if p_action <> 'attack' then update public.game_day_heroes set actions_used = actions_used + 1 where day = d and user_id = v; end if;
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1 where user_id = v;
  insert into public.game_day_log (day, lobby_id, user_id, action, amount, target_id, note) values (d, l.id, v, p_action, amt, v_target, v_note);
  if v_dead then perform public._game_finish_lobby(l.id); end if;

  select * into l from public.game_lobbies where id = l.id;
  select * into dh from public.game_day_heroes where day = d and user_id = v;
  res := jsonb_build_object('action', p_action, 'amount', amt, 'crit', crit, 'dodge', dodge, 'taken', took, 'absorbed', absorbed, 'note', v_note,
           'my_hp', dh.hp, 'my_max_hp', dh.max_hp, 'ko', dh.hp <= 0, 'boss_hp', l.hp, 'boss_max_hp', l.max_hp, 'shield', l.shield, 'weak', l.weak,
           'defeated', l.status = 'defeated', 'actions_left', greatest(0, v_lim - dh.actions_used));
  if v_dead then
    select jsonb_build_object('bc', r.bc, 'xp', r.xp, 'levels', r.levels_gained, 'item', (select name from public.game_items where id = r.item_id))
      into rw from public.game_rewards r where r.day = d and r.user_id = v;
    res := res || jsonb_build_object('reward', rw);
  end if;
  return res;
end $$;

create or replace function public.game_boss_start() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date; dy public.game_days%rowtype; l public.game_lobbies%rowtype; mine public.game_day_heroes%rowtype; bo public.game_bosses%rowtype; r record; c record; n integer := 0;
  v_min integer := greatest(1, public._setting('game_boss_min_players')); sum_need numeric := 0; sum_lvl numeric := 0; v_hp bigint;
begin
  perform public._require_module('heroes');
  d := public._game_ensure_day();
  select * into mine from public.game_day_heroes where day = d and user_id = v;
  if not found then raise exception 'Entra prima in una lobby'; end if;
  select * into l from public.game_lobbies where id = mine.lobby_id for update;
  if l.status = 'open' then raise exception 'Il boss è già partito'; end if;
  if l.status <> 'lobby' then raise exception 'Hai già sconfitto il boss di oggi con la tua lobby: torna domani'; end if;
  select * into dy from public.game_days where day = d;
  select * into bo from public.game_bosses where no = dy.boss_no;
  for r in select x.user_id from public.game_day_heroes x join public.profiles p on p.id = x.user_id where x.lobby_id = l.id and not p.suspended order by x.user_id loop
    select * into c from public._game_calc(r.user_id);
    update public.game_day_heroes set max_hp = c.max_hp, hp = c.max_hp where day = d and user_id = r.user_id;      -- l'equipaggiamento può essere cambiato dopo l'ingresso
    -- ogni eroe «vale» tanti attacchi quanti ne regge prima di cadere (1 / rappresaglia), per la quota di PV che il boss di oggi deve togliergli
    sum_need := sum_need + c.s_for * 3 * least(1.0, (0.25 + 0.5 * (bo.coverage - 0.3) / 0.95) * (1 + 0.25 * dy.cycle)) / (bo.retal * (1 + 0.1 * dy.cycle)); sum_lvl := sum_lvl + c.level; n := n + 1;
  end loop;
  delete from public.game_day_heroes x using public.profiles p where x.lobby_id = l.id and p.id = x.user_id and p.suspended;
  if n < v_min then raise exception 'Servono almeno % giocatori nella lobby (ora %)', v_min, n; end if;
  v_hp := greatest(50, ceil(sum_need * greatest(10, public._setting('game_boss_difficulty')) / 100.0))::bigint;
  update public.game_lobbies set status = 'open', max_hp = v_hp, hp = v_hp, boss_level = greatest(1, round(sum_lvl / n)::integer), started_at = now() where id = l.id;
  return jsonb_build_object('players', n, 'boss_hp', v_hp, 'lobby', l.id);
end $$;

revoke all on function public.game_boss_act(text, uuid), public.game_boss_start() from public, anon;
grant execute on function public.game_boss_act(text, uuid), public.game_boss_start() to authenticated;
