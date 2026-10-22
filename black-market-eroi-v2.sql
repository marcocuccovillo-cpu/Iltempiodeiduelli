-- =====================================================================
-- MIGRAZIONE 015 — La guerra degli Eroi, versione 2
--   1. Energia a batteria (max 100, si ricarica da sola in 8 ore): ogni duello in Arena costa 5 (vinto) o 8 (perso). Sostituisce il limite
--      di 5 duelli al giorno. Resta «una sfida al giorno per avversario».
--   2. Skill permanenti (20, quattro gradi per statistica) e skill temporanee (10, due gradi per slot, durano 24 ore), tutte acquistabili
--      in BC dal Mercante e sempre disponibili.
--   3. 3 punti abilità in più a ogni livello, da mettere nelle statistiche (si aggiungono ai 20 iniziali; gli eroi già salgiti li ricevono per i livelli passati).
--   4. Lobby del boss: servono almeno 3 giocatori. Chi vuole sfidare il boss entra nella lobby di oggi; con 3 o più, uno qualunque dei presenti lo fa partire.
--      I PV del boss si calcolano al via, sui giocatori della lobby.
-- Da eseguire in Supabase (SQL Editor) DOPO la 013 (e la 014 se l'hai fatta). Si può rieseguire.
-- Non tocca saldi o registro già scritti. Nuovi tipi di movimento BC: game_skill (acquisti di skill, solo uscite).
-- =====================================================================
begin;

insert into public.system_settings (key, value_int, description) values
 ('game_points_per_level',  3,   'Eroi: punti abilità guadagnati a ogni livello'),
 ('game_boss_min_players',  3,   'Eroi: giocatori minimi nella lobby per far partire il boss'),
 ('game_energy_max',        100, 'Eroi: energia massima (batteria)'),
 ('game_energy_regen_hours',8,   'Eroi: ore per ricaricare la batteria da 0 al massimo'),
 ('game_energy_win',        5,   'Eroi: energia spesa per un duello vinto'),
 ('game_energy_loss',       8,   'Eroi: energia spesa per un duello perso'),
 ('game_temp_hours',        24,  'Eroi: durata in ore delle skill temporanee')
on conflict (key) do nothing;
update public.system_settings set description = 'Eroi: (non più usato dalla 015: i duelli costano energia)' where key = 'game_daily_fights';

alter table public.ledger_entries drop constraint if exists ledger_entries_kind_check;
alter table public.ledger_entries add constraint ledger_entries_kind_check
  check (kind in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment','ladder_reward','shop_purchase','game_boss_reward','game_purchase','game_respec','game_skill'));

-- punti abilità: crescono con i livelli, quindi servono interi grandi
alter table public.game_heroes alter column a_for type integer, alter column a_des type integer, alter column a_vig type integer, alter column a_spi type integer, alter column a_frt type integer;
alter table public.game_heroes add column if not exists energy numeric not null default 100 check (energy >= 0);
alter table public.game_heroes add column if not exists energy_at timestamptz not null default now();

-- lobby: il giorno nasce «in lobby», poi diventa «aperto» quando parte
alter table public.game_days drop constraint if exists game_days_max_hp_check;
alter table public.game_days add constraint game_days_max_hp_check check (max_hp >= 0);
alter table public.game_days drop constraint if exists game_days_status_check;
alter table public.game_days add constraint game_days_status_check check (status in ('lobby','open','defeated','escaped'));
alter table public.game_days add column if not exists started_at timestamptz;
alter table public.game_day_heroes add column if not exists joined_at timestamptz not null default now();

-- skill
create table if not exists public.game_skills (
  id text primary key,
  name text not null,
  kind text not null check (kind in ('perm','temp')),
  stat text check (stat in ('for','des','vig','spi','frt')),                    -- skill permanenti: statistica potenziata
  slot text check (slot in ('weapon','armor','helm','amulet','tool')),          -- skill temporanee: equipaggiamento potenziato
  tier smallint not null check (tier >= 1),
  price_bc integer not null check (price_bc > 0),
  min_level integer not null check (min_level >= 1),
  p_for smallint not null default 0, p_des smallint not null default 0, p_vig smallint not null default 0, p_spi smallint not null default 0, p_frt smallint not null default 0,
  descr text,
  check ((kind = 'perm' and stat is not null and slot is null) or (kind = 'temp' and slot is not null and stat is null))
);
create table if not exists public.game_hero_skills (
  user_id uuid not null references public.profiles(id) on delete restrict,
  skill_id text not null references public.game_skills(id),
  acquired_at timestamptz not null default now(),
  primary key (user_id, skill_id)
);
create table if not exists public.game_temp_skills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  skill_id text not null references public.game_skills(id),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists game_temp_skills_idx on public.game_temp_skills (user_id, expires_at);
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'game_hero_skills_nodel') then
    create trigger game_hero_skills_nodel before delete on public.game_hero_skills for each row execute function public._no_delete();
    create trigger game_temp_skills_nodel before delete on public.game_temp_skills for each row execute function public._no_delete();
  end if;
end $$;

insert into public.game_skills (id, name, kind, stat, slot, tier, price_bc, min_level, p_for, p_des, p_vig, p_spi, p_frt, descr) values
  ('sk_for_1','Pugno Temprato','perm','for',null,1,250,3,3,0,0,0,0,'Allenamento permanente: +3% Forza, per sempre.'),
  ('sk_for_2','Colpo Possente','perm','for',null,2,900,12,5,0,0,0,0,'Allenamento permanente: +5% Forza, per sempre.'),
  ('sk_for_3','Furia del Titano','perm','for',null,3,3000,30,8,0,0,0,0,'Allenamento permanente: +8% Forza, per sempre.'),
  ('sk_for_4','Forza Primordiale','perm','for',null,4,10000,70,12,0,0,0,0,'Allenamento permanente: +12% Forza, per sempre.'),
  ('sk_des_1','Occhio Attento','perm','des',null,1,250,3,0,3,0,0,0,'Allenamento permanente: +3% Destrezza, per sempre.'),
  ('sk_des_2','Riflessi Felini','perm','des',null,2,900,12,0,5,0,0,0,'Allenamento permanente: +5% Destrezza, per sempre.'),
  ('sk_des_3','Mano di Vento','perm','des',null,3,3000,30,0,8,0,0,0,'Allenamento permanente: +8% Destrezza, per sempre.'),
  ('sk_des_4','Precisione Assoluta','perm','des',null,4,10000,70,0,12,0,0,0,'Allenamento permanente: +12% Destrezza, per sempre.'),
  ('sk_vig_1','Pelle Dura','perm','vig',null,1,250,3,0,0,3,0,0,'Allenamento permanente: +3% Vigore, per sempre.'),
  ('sk_vig_2','Cuore Saldo','perm','vig',null,2,900,12,0,0,5,0,0,'Allenamento permanente: +5% Vigore, per sempre.'),
  ('sk_vig_3','Corpo d''Acciaio','perm','vig',null,3,3000,30,0,0,8,0,0,'Allenamento permanente: +8% Vigore, per sempre.'),
  ('sk_vig_4','Vitalità Eterna','perm','vig',null,4,10000,70,0,0,12,0,0,'Allenamento permanente: +12% Vigore, per sempre.'),
  ('sk_spi_1','Mente Serena','perm','spi',null,1,250,3,0,0,0,3,0,'Allenamento permanente: +3% Spirito, per sempre.'),
  ('sk_spi_2','Soffio Guaritore','perm','spi',null,2,900,12,0,0,0,5,0,'Allenamento permanente: +5% Spirito, per sempre.'),
  ('sk_spi_3','Aura Radiosa','perm','spi',null,3,3000,30,0,0,0,8,0,'Allenamento permanente: +8% Spirito, per sempre.'),
  ('sk_spi_4','Anima Luminosa','perm','spi',null,4,10000,70,0,0,0,12,0,'Allenamento permanente: +12% Spirito, per sempre.'),
  ('sk_frt_1','Passo Leggero','perm','frt',null,1,250,3,0,0,0,0,3,'Allenamento permanente: +3% Fortezza, per sempre.'),
  ('sk_frt_2','Scudo Interiore','perm','frt',null,2,900,12,0,0,0,0,5,'Allenamento permanente: +5% Fortezza, per sempre.'),
  ('sk_frt_3','Volontà di Ferro','perm','frt',null,3,3000,30,0,0,0,0,8,'Allenamento permanente: +8% Fortezza, per sempre.'),
  ('sk_frt_4','Bastione dell''Anima','perm','frt',null,4,10000,70,0,0,0,0,12,'Allenamento permanente: +12% Fortezza, per sempre.'),
  ('tk_weapon_1','Affilatura','temp',null,'weapon',1,80,1,6,3,0,0,0,'Potenzia arma: Forza +6%, Destrezza +3% per un periodo limitato.'),
  ('tk_weapon_2','Lama Infuocata','temp',null,'weapon',2,300,15,12,6,0,0,0,'Potenzia arma: Forza +12%, Destrezza +6% per un periodo limitato.'),
  ('tk_armor_1','Rinforzo','temp',null,'armor',1,80,1,0,0,6,0,3,'Potenzia armatura: Vigore +6%, Fortezza +3% per un periodo limitato.'),
  ('tk_armor_2','Corazza Runica','temp',null,'armor',2,300,15,0,0,12,0,6,'Potenzia armatura: Vigore +12%, Fortezza +6% per un periodo limitato.'),
  ('tk_helm_1','Visione Chiara','temp',null,'helm',1,80,1,0,0,3,6,0,'Potenzia elmo: Spirito +6%, Vigore +3% per un periodo limitato.'),
  ('tk_helm_2','Corona di Luce','temp',null,'helm',2,300,15,0,0,6,12,0,'Potenzia elmo: Spirito +12%, Vigore +6% per un periodo limitato.'),
  ('tk_amulet_1','Benedizione','temp',null,'amulet',1,80,1,0,3,0,0,6,'Potenzia amuleto: Fortezza +6%, Destrezza +3% per un periodo limitato.'),
  ('tk_amulet_2','Talismano Lunare','temp',null,'amulet',2,300,15,0,6,0,0,12,'Potenzia amuleto: Fortezza +12%, Destrezza +6% per un periodo limitato.'),
  ('tk_tool_1','Unguento Vivace','temp',null,'tool',1,80,1,0,6,0,3,0,'Potenzia strumento: Destrezza +6%, Spirito +3% per un periodo limitato.'),
  ('tk_tool_2','Elisir del Maestro','temp',null,'tool',2,300,15,0,12,0,6,0,'Potenzia strumento: Destrezza +12%, Spirito +6% per un periodo limitato.')
on conflict (id) do update set name = excluded.name, price_bc = excluded.price_bc, min_level = excluded.min_level,
  p_for = excluded.p_for, p_des = excluded.p_des, p_vig = excluded.p_vig, p_spi = excluded.p_spi, p_frt = excluded.p_frt, descr = excluded.descr;

-- ---------- energia ----------
create or replace function public._game_energy_max() returns integer language sql stable as $$ select greatest(1, public._setting('game_energy_max')) $$;
-- energia che si recupera ogni ora (gli oggetti con «+duelli» la rendono più veloce: +25% a punto)
create or replace function public._game_energy_rate(p_user uuid) returns numeric language sql stable security definer set search_path = public as $$
  select public._game_energy_max()::numeric / greatest(1, public._setting('game_energy_regen_hours'))
         * (1 + 0.25 * coalesce((select c.extra_fights from public._game_calc(p_user) c), 0)) $$;
-- energia di adesso: quella salvata più quanto recuperato nel frattempo (mai oltre il massimo)
create or replace function public._game_energy_of(p_user uuid) returns numeric language sql stable security definer set search_path = public as $$
  select least(public._game_energy_max()::numeric, h.energy + greatest(0, extract(epoch from (now() - h.energy_at))) / 3600.0 * public._game_energy_rate(p_user))
  from public.game_heroes h where h.user_id = p_user $$;

-- ---------- punti abilità: 20 + 3 per ogni livello dopo il primo ----------
create or replace function public._game_points(p_level integer) returns integer language sql stable as $$
  select public._setting('game_stat_points') + public._setting('game_points_per_level') * (greatest(1, p_level) - 1) $$;

-- statistiche reali: base 5 + punti × livello, poi i bonus % di equipaggiamento + skill permanenti + skill temporanee attive
drop function if exists public._game_calc(uuid);
create function public._game_calc(p_user uuid)
returns table (level integer, s_for bigint, s_des bigint, s_vig bigint, s_spi bigint, s_frt bigint, max_hp bigint, xp_pct integer, extra_actions integer, extra_fights integer,
               b_for integer, b_des integer, b_vig integer, b_spi integer, b_frt integer)
language sql stable security definer set search_path = public as $$
  with h as (select * from public.game_heroes where user_id = p_user),
  b as (select coalesce(sum(i.p_for),0) pf, coalesce(sum(i.p_des),0) pd, coalesce(sum(i.p_vig),0) pv, coalesce(sum(i.p_spi),0) ps, coalesce(sum(i.p_frt),0) pr,
               coalesce(sum(i.xp_pct),0) px, coalesce(sum(i.extra_actions),0) pa, coalesce(sum(i.extra_fights),0) pq
        from public.game_equipped e join public.game_items i on i.id = e.item_id where e.user_id = p_user),
  k as (select coalesce(sum(s.p_for),0) kf, coalesce(sum(s.p_des),0) kd, coalesce(sum(s.p_vig),0) kv, coalesce(sum(s.p_spi),0) ks, coalesce(sum(s.p_frt),0) kr
        from (select skill_id from public.game_hero_skills where user_id = p_user
              union all select skill_id from public.game_temp_skills where user_id = p_user and expires_at > now()) x
        join public.game_skills s on s.id = x.skill_id),
  t as (select b.pf + k.kf as tf, b.pd + k.kd as td, b.pv + k.kv as tv, b.ps + k.ks as ts, b.pr + k.kr as tr, b.px, b.pa, b.pq from b, k),
  s as (select h.level,
          round((5 + h.a_for::numeric * h.level) * (100 + t.tf) / 100)::bigint as sf,
          round((5 + h.a_des::numeric * h.level) * (100 + t.td) / 100)::bigint as sd,
          round((5 + h.a_vig::numeric * h.level) * (100 + t.tv) / 100)::bigint as sv,
          round((5 + h.a_spi::numeric * h.level) * (100 + t.ts) / 100)::bigint as ss,
          round((5 + h.a_frt::numeric * h.level) * (100 + t.tr) / 100)::bigint as sr,
          t.tf, t.td, t.tv, t.ts, t.tr, t.px, t.pa, t.pq from h, t)
  select s.level, s.sf, s.sd, s.sv, s.ss, s.sr, 50 + 12 * s.sv, s.px::integer, s.pa::integer, s.pq::integer, s.tf::integer, s.td::integer, s.tv::integer, s.ts::integer, s.tr::integer from s $$;

-- scheda di un eroe
create or replace function public._game_hero_json(p_user uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'user_id', h.user_id, 'nickname', p.nickname, 'avatar', p.avatar,
    'level', h.level, 'xp', h.xp, 'xp_need', public._game_xp_need(h.level),
    'alloc', jsonb_build_object('for', h.a_for, 'des', h.a_des, 'vig', h.a_vig, 'spi', h.a_spi, 'frt', h.a_frt),
    'points', public._game_points(h.level), 'points_free', public._game_points(h.level) - (h.a_for + h.a_des + h.a_vig + h.a_spi + h.a_frt),
    'stats', jsonb_build_object('for', c.s_for, 'des', c.s_des, 'vig', c.s_vig, 'spi', c.s_spi, 'frt', c.s_frt),
    'bonus', jsonb_build_object('for', c.b_for, 'des', c.b_des, 'vig', c.b_vig, 'spi', c.b_spi, 'frt', c.b_frt),
    'max_hp', c.max_hp, 'xp_pct', c.xp_pct, 'extra_actions', c.extra_actions, 'extra_fights', c.extra_fights,
    'stats_set', h.stats_set, 'arena_open', h.arena_open, 'duels_won', h.duels_won, 'duels_lost', h.duels_lost, 'bosses_beaten', h.bosses_beaten,
    'respec_count', h.respec_count, 'fights_total', h.fights_total,
    'equipped', coalesce((select jsonb_object_agg(e.slot, jsonb_build_object('id', i.id, 'name', i.name, 'rarity', i.rarity, 'tier', i.tier, 'min_level', i.min_level,
        'p_for', i.p_for, 'p_des', i.p_des, 'p_vig', i.p_vig, 'p_spi', i.p_spi, 'p_frt', i.p_frt, 'xp_pct', i.xp_pct, 'extra_actions', i.extra_actions, 'extra_fights', i.extra_fights, 'descr', i.descr))
      from public.game_equipped e join public.game_items i on i.id = e.item_id where e.user_id = h.user_id), '{}'::jsonb),
    'perm_skills', coalesce((select jsonb_agg(k.name order by k.stat, k.tier) from public.game_hero_skills s join public.game_skills k on k.id = s.skill_id where s.user_id = h.user_id), '[]'::jsonb),
    'temp_skills', coalesce((select jsonb_agg(jsonb_build_object('name', k.name, 'slot', k.slot, 'until', t.expires_at) order by t.expires_at)
                             from public.game_temp_skills t join public.game_skills k on k.id = t.skill_id where t.user_id = h.user_id and t.expires_at > now()), '[]'::jsonb))
  from public.game_heroes h join public.profiles p on p.id = h.user_id
  cross join lateral public._game_calc(h.user_id) c
  where h.user_id = p_user $$;

-- ---------- il giorno nasce «in lobby»: i PV si calcolano quando il boss parte ----------
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

create or replace function public.game_duel(p_target uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date := public._game_today(); a public.game_heroes%rowtype; b public.game_heroes%rowtype; ca jsonb; cb jsonb; sim jsonb; v_en numeric; v_need integer; v_cost integer;
  v_win uuid; v_xp bigint := 0; v_id uuid := gen_random_uuid(); rw jsonb; v_first uuid; v_second uuid; pn text;
begin
  perform public._require_module('heroes');
  if p_target is null or p_target = v then raise exception 'Scegli un altro eroe da sfidare'; end if;
  perform public._game_ensure_hero(v);
  if not exists (select 1 from public.profiles where id = p_target and not suspended) then raise exception 'Eroe non disponibile'; end if;
  if not exists (select 1 from public.game_heroes where user_id = p_target) then raise exception 'Questo duellante non è ancora un eroe'; end if;
  v_first := least(v, p_target); v_second := greatest(v, p_target);                  -- blocco in ordine fisso
  perform 1 from public.game_heroes where user_id = v_first for update;
  perform 1 from public.game_heroes where user_id = v_second for update;
  select * into a from public.game_heroes where user_id = v;
  select * into b from public.game_heroes where user_id = p_target;
  if not a.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  if not b.stats_set then raise exception 'Questo eroe non ha ancora assegnato i suoi punti abilità'; end if;
  if not b.arena_open then raise exception 'Questo eroe non accetta sfide in Arena'; end if;
  select to_jsonb(x) into ca from public._game_calc(v) x;
  select to_jsonb(x) into cb from public._game_calc(p_target) x;
  v_need := greatest(public._setting('game_energy_win'), public._setting('game_energy_loss'));
  v_en := public._game_energy_of(v);
  if v_en < v_need then raise exception 'Energia insufficiente: per sfidare ne servono almeno % (ora %)', v_need, floor(v_en); end if;
  if exists (select 1 from public.game_duels where day = d and attacker_id = v and defender_id = p_target) then raise exception 'Hai già sfidato questo eroe oggi'; end if;
  sim := public._game_sim(ca, cb);
  v_win := case when sim->>'winner' = 'a' then v else p_target end;
  if v_win = v then
    v_xp := greatest(1, round((40 + 2 * b.level) * least(2::numeric, greatest(0.25, b.level::numeric / a.level)))::bigint);
    rw := public._game_add_xp(v, v_xp);
    v_xp := (rw->>'xp')::bigint;
    update public.game_heroes set duels_won = duels_won + 1 where user_id = v;
  else
    rw := jsonb_build_object('xp', 0, 'levels', 0, 'level', a.level);
    update public.game_heroes set duels_lost = duels_lost + 1 where user_id = v;
  end if;
  v_cost := case when v_win = v then public._setting('game_energy_win') else public._setting('game_energy_loss') end;
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1, energy = greatest(0, v_en - v_cost), energy_at = now() where user_id = v;
  insert into public.game_duels (id, day, attacker_id, defender_id, winner_id, atk_level, def_level, xp_awarded, rounds, log)
    values (v_id, d, v, p_target, v_win, a.level, b.level, v_xp, (sim->>'rounds')::integer, sim->'log');
  select nickname into pn from public.profiles where id = p_target;
  return jsonb_build_object('id', v_id, 'won', v_win = v, 'xp', v_xp, 'levels', (rw->>'levels')::integer, 'level', (rw->>'level')::integer, 'opponent', pn,
           'opponent_level', b.level, 'rounds', sim->'rounds', 'hp_a', sim->'hp_a', 'hp_b', sim->'hp_b', 'max_a', sim->'max_a', 'max_b', sim->'max_b', 'log', sim->'log',
           'energy', round(greatest(0, v_en - v_cost), 2), 'energy_cost', v_cost);
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

-- distribuzione dei punti: 20 + 3 per livello. Aggiungere punti è sempre gratis; ridurne uno già assegnato, dopo il primo scontro, costa BC
create or replace function public.game_set_stats(p_for integer, p_des integer, p_vig integer, p_spi integer, p_frt integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); h public.game_heroes%rowtype; v_pool integer;
        v_cap integer; v_cost integer := public._setting('game_respec_cost'); v_paid boolean := false; v_less boolean;
begin
  perform public._require_module('heroes');
  if p_for is null or p_des is null or p_vig is null or p_spi is null or p_frt is null then raise exception 'Punti non validi'; end if;
  if least(p_for, p_des, p_vig, p_spi, p_frt) < 0 then raise exception 'Punti non validi'; end if;
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v for update;
  v_pool := public._game_points(h.level);
  v_cap := greatest(1, public._setting('game_stat_cap')) + public._setting('game_points_per_level') * (h.level - 1);    -- il tetto sale con i livelli
  if greatest(p_for, p_des, p_vig, p_spi, p_frt) > v_cap then raise exception 'Massimo % punti su una singola statistica', v_cap; end if;
  if p_for + p_des + p_vig + p_spi + p_frt > v_pool then raise exception 'Hai solo % punti da distribuire', v_pool; end if;
  if h.stats_set and (h.a_for, h.a_des, h.a_vig, h.a_spi, h.a_frt) = (p_for, p_des, p_vig, p_spi, p_frt) then
    return public._game_hero_json(v) || jsonb_build_object('paid', 0);   -- nessuna modifica: niente da pagare
  end if;
  v_less := p_for < h.a_for or p_des < h.a_des or p_vig < h.a_vig or p_spi < h.a_spi or p_frt < h.a_frt;
  if h.stats_set and v_less and h.fights_total > 0 and v_cost > 0 then
    perform public._ledger_move(v, -v_cost, 'game_respec', 'game_hero', null, 'gamerespec:' || v::text || ':' || (h.respec_count + 1)::text, 'La guerra degli Eroi: nuova distribuzione dei punti');
    v_paid := true;
  end if;
  update public.game_heroes set a_for = p_for, a_des = p_des, a_vig = p_vig, a_spi = p_spi, a_frt = p_frt, stats_set = true,
         respec_count = respec_count + case when h.stats_set then 1 else 0 end where user_id = v;
  return public._game_hero_json(v) || jsonb_build_object('paid', case when v_paid then v_cost else 0 end);
end $$;

-- ---------- lobby del boss ----------
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

-- uno qualunque dei presenti lo fa partire, quando ce ne sono abbastanza. I PV del boss dipendono da chi c'è.
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

-- ---------- skill dal Mercante ----------
create or replace function public.game_buy_skill(p_skill text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); k public.game_skills%rowtype; h public.game_heroes%rowtype; pv public.game_skills%rowtype;
        v_bal integer; v_id uuid := gen_random_uuid(); cur record; v_until timestamptz;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v for update;
  select * into k from public.game_skills where id = p_skill;
  if not found then raise exception 'Abilità inesistente'; end if;
  if h.level < k.min_level then raise exception 'Ti serve il livello % per questa abilità', k.min_level; end if;
  if k.kind = 'perm' then
    if exists (select 1 from public.game_hero_skills where user_id = v and skill_id = k.id) then raise exception 'Possiedi già questa abilità'; end if;
    if k.tier > 1 then
      select * into pv from public.game_skills where kind = 'perm' and stat = k.stat and tier = k.tier - 1;
      if not exists (select 1 from public.game_hero_skills where user_id = v and skill_id = pv.id) then raise exception 'Prima ti serve «%»', pv.name; end if;
    end if;
    v_bal := public._ledger_move(v, -k.price_bc, 'game_skill', 'game_skill', null, 'gameskill:' || v::text || ':' || k.id, 'Mercante degli Eroi: ' || k.name);
    if v_bal < 0 then raise exception 'Acquisto già registrato'; end if;
    insert into public.game_hero_skills (user_id, skill_id) values (v, k.id);
    return jsonb_build_object('skill', k.name, 'price', k.price_bc, 'balance', v_bal);
  end if;
  -- temporanea: un solo potenziamento attivo per slot; si può rinnovare o passare al grado più alto, non scendere
  select t.id, s.tier, s.name into cur from public.game_temp_skills t join public.game_skills s on s.id = t.skill_id
    where t.user_id = v and s.slot = k.slot and t.expires_at > now() order by s.tier desc limit 1;
  if found and cur.tier > k.tier then raise exception 'Hai già un potenziamento migliore attivo per questo equipaggiamento: «%»', cur.name; end if;
  v_bal := public._ledger_move(v, -k.price_bc, 'game_skill', 'game_skill', null, 'gametemp:' || v_id::text, 'Mercante degli Eroi: ' || k.name);
  if v_bal < 0 then raise exception 'Acquisto già registrato'; end if;
  update public.game_temp_skills t set expires_at = now() from public.game_skills s where s.id = t.skill_id and t.user_id = v and s.slot = k.slot and t.expires_at > now();
  v_until := now() + make_interval(hours => greatest(1, public._setting('game_temp_hours')));
  insert into public.game_temp_skills (id, user_id, skill_id, expires_at) values (v_id, v, k.id, v_until);
  return jsonb_build_object('skill', k.name, 'price', k.price_bc, 'balance', v_bal, 'until', v_until);
end $$;

-- ---------- permessi ----------
do $$
declare t text;
begin
  foreach t in array array['game_skills','game_hero_skills','game_temp_skills'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    if t = 'game_skills' then
      execute format('create policy %I on public.%I for select to authenticated using (public._module_on(''heroes'') or public.is_admin())', t || '_read', t);
    else
      execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid() or public.is_admin())', t || '_read', t);
    end if;
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

revoke all on function public._game_energy_max(), public._game_energy_rate(uuid), public._game_energy_of(uuid), public._game_points(integer), public._game_calc(uuid) from public, anon, authenticated;
revoke all on function public._game_ensure_day(), public._game_hero_json(uuid) from public, anon, authenticated;
revoke all on function public.game_state(), public.game_duel(uuid), public.game_boss_act(text, uuid), public.game_set_stats(integer, integer, integer, integer, integer),
  public.game_boss_join(), public.game_boss_leave(), public.game_boss_start(), public.game_buy_skill(text) from public, anon, authenticated;
grant execute on function public.game_state(), public.game_duel(uuid), public.game_boss_act(text, uuid), public.game_set_stats(integer, integer, integer, integer, integer),
  public.game_boss_join(), public.game_boss_leave(), public.game_boss_start(), public.game_buy_skill(text) to authenticated;
commit;
