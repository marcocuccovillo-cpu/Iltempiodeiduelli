-- =====================================================================
-- MIGRAZIONE 040 — LA GUERRA DEGLI EROI: NUOVI GRADI DI ABILITÀ E SCHEDA EROE COMPLETA
-- Da eseguire in Supabase (SQL Editor) DOPO tutte le migrazioni precedenti (ultima: 039, raid settimanale).
--
-- 1. ABILITÀ PERMANENTI dal 9° al 12° grado (20 nuove, 4 per statistica), fino al livello 600. Si comprano in ordine dopo l'8° grado,
--    una volta sola, per sempre, solo con BC (che escono dal gioco):
--      grado  9: +30%   750.000 BC   livello 450
--      grado 10: +34% 1.500.000 BC   livello 500
--      grado 11: +38% 3.000.000 BC   livello 550
--      grado 12: +42% 6.000.000 BC   livello 600
--    Con tutti i 12 gradi una statistica ha +253% (fino all'8° grado: +109%).
-- 2. POTENZIAMENTI TEMPORANEI dal 3° all'8° grado (30 nuovi, 6 per equipaggiamento). Durano game_temp_hours (24 ore), uno attivo
--    per equipaggiamento come oggi (si rinnova o si passa a un grado più alto). Statistica principale / secondaria:
--      grado 3: +18% / +9%     1.200 BC   livello  40
--      grado 4: +25% / +12%    4.000 BC   livello 100
--      grado 5: +35% / +17%   10.000 BC   livello 200
--      grado 6: +45% / +22%   20.000 BC   livello 300
--      grado 7: +60% / +30%   35.000 BC   livello 400
--      grado 8: +75% / +37%   60.000 BC   livello 500
-- 3. game_hero_extra(utente): i dati in più per la scheda di un eroe (Arena del mese, Torre, dungeon, raid della settimana,
--    gradi di abilità per statistica). Solo lettura, per chi gioca.
-- Prezzi e livelli si cambiano dal database come per gli altri gradi (update public.game_skills set price_bc = … where id = …).
-- Si può rieseguire (aggiorna nomi, bonus, prezzi e livelli dei gradi nuovi). Annullamento: black-market-eroi-progressi-down.sql.
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.game_skills') is null then raise exception 'Prima esegui le migrazioni della Guerra degli Eroi. Non è stato modificato nulla.'; end if;
end $$;

-- ---------- abilità permanenti 9–12 ----------
insert into public.game_skills (id, name, kind, stat, slot, tier, price_bc, min_level, p_for, p_des, p_vig, p_spi, p_frt, descr)
select 'sk_' || s.stat || '_' || g.tier, s.names[g.tier - 8], 'perm', s.stat, null, g.tier, g.price, g.lvl,
       case when s.stat = 'for' then g.pct else 0 end, case when s.stat = 'des' then g.pct else 0 end, case when s.stat = 'vig' then g.pct else 0 end,
       case when s.stat = 'spi' then g.pct else 0 end, case when s.stat = 'frt' then g.pct else 0 end,
       'Allenamento permanente: +' || g.pct || '% ' || s.label || ', per sempre.'
  from (values
    ('for', 'Forza',     array['Pugno della Montagna', 'Furia degli Dei', 'Colpo dell''Apocalisse', 'Forza Assoluta']),
    ('des', 'Destrezza', array['Occhio dell''Aquila', 'Danza delle Lame', 'Istinto Infallibile', 'Destino Scritto']),
    ('vig', 'Vigore',    array['Sangue di Drago', 'Carne di Titano', 'Cuore Eterno', 'Immortalità']),
    ('spi', 'Spirito',   array['Luce dell''Alba', 'Anima Ancestrale', 'Spirito Celeste', 'Illuminazione Totale']),
    ('frt', 'Fortezza',  array['Scudo del Mondo', 'Bastione Eterno', 'Roccaforte Divina', 'Inamovibile'])
  ) as s(stat, label, names)
  cross join (values (9, 30, 750000, 450), (10, 34, 1500000, 500), (11, 38, 3000000, 550), (12, 42, 6000000, 600)) as g(tier, pct, price, lvl)
on conflict (id) do update set name = excluded.name, tier = excluded.tier, price_bc = excluded.price_bc, min_level = excluded.min_level,
  p_for = excluded.p_for, p_des = excluded.p_des, p_vig = excluded.p_vig, p_spi = excluded.p_spi, p_frt = excluded.p_frt, descr = excluded.descr;

-- ---------- potenziamenti temporanei 3–8 ----------
insert into public.game_skills (id, name, kind, stat, slot, tier, price_bc, min_level, p_for, p_des, p_vig, p_spi, p_frt, descr)
select 'tk_' || s.slot || '_' || g.tier, s.names[g.tier - 2], 'temp', null, s.slot, g.tier, g.price, g.lvl,
       case when s.a = 'for' then g.hi when s.b = 'for' then g.lo else 0 end,
       case when s.a = 'des' then g.hi when s.b = 'des' then g.lo else 0 end,
       case when s.a = 'vig' then g.hi when s.b = 'vig' then g.lo else 0 end,
       case when s.a = 'spi' then g.hi when s.b = 'spi' then g.lo else 0 end,
       case when s.a = 'frt' then g.hi when s.b = 'frt' then g.lo else 0 end,
       'Potenzia ' || s.label || ': ' || s.la || ' +' || g.hi || '%, ' || s.lb || ' +' || g.lo || '% per un periodo limitato.'
  from (values
    ('weapon', 'arma',        'for', 'Forza',     'des', 'Destrezza', array['Lama Runica', 'Filo del Drago', 'Acciaio Stellare', 'Taglio del Vuoto', 'Furia Primordiale', 'Lama dell''Eternità']),
    ('armor',  'armatura',    'vig', 'Vigore',    'frt', 'Fortezza',  array['Piastre Benedette', 'Guscio di Drago', 'Corazza Stellare', 'Pelle del Titano', 'Bastione Primordiale', 'Armatura dell''Eternità']),
    ('helm',   'elmo',        'spi', 'Spirito',   'vig', 'Vigore',    array['Diadema Arcano', 'Corona di Fiamme', 'Occhio Stellare', 'Visione del Vuoto', 'Mente Primordiale', 'Corona dell''Eternità']),
    ('amulet', 'amuleto',     'frt', 'Fortezza',  'des', 'Destrezza', array['Sigillo Antico', 'Talismano del Drago', 'Stella Polare', 'Amuleto del Vuoto', 'Cuore Primordiale', 'Sigillo dell''Eternità']),
    ('tool',   'strumento',   'des', 'Destrezza', 'spi', 'Spirito',   array['Tonico Runico', 'Elisir del Drago', 'Essenza Stellare', 'Pozione del Vuoto', 'Distillato Primordiale', 'Nettare dell''Eternità'])
  ) as s(slot, label, a, la, b, lb, names)
  cross join (values (3, 18, 9, 1200, 40), (4, 25, 12, 4000, 100), (5, 35, 17, 10000, 200), (6, 45, 22, 20000, 300), (7, 60, 30, 35000, 400), (8, 75, 37, 60000, 500)) as g(tier, hi, lo, price, lvl)
on conflict (id) do update set name = excluded.name, tier = excluded.tier, price_bc = excluded.price_bc, min_level = excluded.min_level,
  p_for = excluded.p_for, p_des = excluded.p_des, p_vig = excluded.p_vig, p_spi = excluded.p_spi, p_frt = excluded.p_frt, descr = excluded.descr;

-- ---------- dati extra per la scheda di un eroe ----------
create or replace function public.game_hero_extra(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); s text; ar jsonb; out jsonb;
begin
  perform public._require_module('heroes');
  if not exists (select 1 from public.game_heroes where user_id = p_user) then raise exception 'Eroe inesistente'; end if;
  -- gradi di abilità permanenti raggiunti per statistica
  out := jsonb_build_object(
    'grades', coalesce((select jsonb_object_agg(x.stat, x.top) from (
        select k.stat, max(k.tier) as top from public.game_hero_skills hs join public.game_skills k on k.id = hs.skill_id
         where hs.user_id = p_user and k.kind = 'perm' group by k.stat) x), '{}'::jsonb),
    'grades_max', (select max(tier) from public.game_skills where kind = 'perm'),
    'dungeons', jsonb_build_object(
      'cleared', (select count(*) from public.game_dungeon_progress where user_id = p_user and clears > 0),
      'top', (select max(dungeon_no) from public.game_dungeon_progress where user_id = p_user and clears > 0),
      'total', (select count(*) from public.game_dungeons)));
  -- Arena del mese
  if to_regprocedure('public._game_arena_season(date)') is not null then
    s := public._game_arena_season(null);
    select jsonb_build_object('points', r.points, 'wins', r.wins, 'losses', r.losses, 'best', r.best,
             'league', (select l.name from public.game_arena_leagues l where l.min_points <= r.points order by l.min_points desc limit 1),
             'rank', (select count(*) + 1 from public.game_arena_rating o where o.season = s and o.points > r.points))
      into ar from public.game_arena_rating r where r.user_id = p_user and r.season = s;
    out := out || jsonb_build_object('arena', ar);
  end if;
  -- Torre
  if to_regclass('public.game_tower') is not null then
    out := out || jsonb_build_object('tower', (select jsonb_build_object('best', t.best_floor, 'wins', t.wins) from public.game_tower t where t.user_id = p_user));
  end if;
  -- raid della settimana
  if to_regclass('public.game_raids') is not null then
    out := out || jsonb_build_object(
      'raid', (select jsonb_build_object('dmg', d.dmg, 'hits', d.hits, 'rank', (select count(*) + 1 from public.game_raid_damage o where o.raid_id = d.raid_id and o.dmg > d.dmg))
                 from public.game_raid_damage d join public.game_raids g on g.id = d.raid_id
                where d.user_id = p_user and g.week_start = date_trunc('week', (now() at time zone 'Europe/Rome')::date)::date),
      'raids_won', (select count(*) from public.game_raid_rewards where user_id = p_user and won));
  end if;
  return out;
end $$;
revoke all on function public.game_hero_extra(uuid) from public, anon;
grant execute on function public.game_hero_extra(uuid) to authenticated;

commit;
