-- =====================================================================
-- MIGRAZIONE 039 — LA GUERRA DEGLI EROI: RAID SETTIMANALE (sostituisce il boss del giorno)
-- Da eseguire in Supabase (SQL Editor) DOPO tutte le migrazioni precedenti (ultime: 037 inviti, 038 shop).
--
-- Come funziona
--  * Ogni settimana (da lunedì 00:00 a domenica 23:59, ora italiana) arriva UN boss gigante per tutto il Tempio, con UNA barra PV
--    condivisa: tutti attaccano lo stesso boss, ogni colpo conta per la community. 8 boss nuovi a rotazione (catalogo game_raid_bosses).
--  * PV del raid: calcolati al lunedì sugli eroi attivi nelle ultime 2 settimane (quanto possono colpire in una settimana) × difficoltà.
--    La difficoltà si adatta: se il raid cade, la settimana dopo è più dura (+10%); se scappa, più facile (−15%).
--  * Ogni giorno ogni eroe entra in battaglia con i PV pieni. Attaccare è libero ma il boss reagisce (rappresaglia): a 0 PV si è KO
--    finché un alleato non cura, oppure fino al giorno dopo. Difendi (scudo, anche a un alleato), Cura (chiunque stia combattendo oggi)
--    e Studia (debolezza del boss per TUTTI, fino a +40% di danni per la settimana) usano le azioni giornaliere (3 + oggetti).
--  * Premi IN BASE AL DANNO, quando il boss cade (subito) o a fine settimana:
--      boss sconfitto → a chi ha colpito almeno una volta: base (raid_bc_base, 350 BC) + quota del montepremi in proporzione al danno
--                       (raid_bc_pool × partecipanti, 200 BC a testa) + podio (1° +500, 2° +300, 3° +150) + XP e un oggetto
--                       (il podio ne pesca due).
--      boss scappato  → base dimezzata + montepremi ridotto alla parte di PV tolta, podio dimezzato, XP ridotta, nessun oggetto.
--    Tutto passa dal registro contabile (movimento 'game_raid_reward', una volta sola per raid e duellante) con notifica.
--  * Il boss del giorno resta nel database ma è SPENTO finché game_raid_enabled = 1 (Admin › Impostazioni): rimettendo 0 torna com'era.
--  * Badge: attacchi, cure e difese nel raid e i raid vinti contano per i badge degli Eroi già esistenti (attacchi, cure, guardie, boss).
-- Si può rieseguire. Annullamento: black-market-eroi-raid-down.sql. Test (solo su un progetto di prova vuoto): black-market-eroi-raid-test.sql.
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.game_heroes') is null or to_regprocedure('public._game_calc(uuid)') is null then
    raise exception 'Prima esegui le migrazioni della Guerra degli Eroi. Non è stato modificato nulla.';
  end if;
end $$;

-- ---------- tipi nuovi nel registro e nelle notifiche ----------
do $$
declare d text; kinds text[];
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.ledger_entries'::regclass and conname = 'ledger_entries_kind_check';
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  if not ('game_raid_reward' = any (kinds)) then
    kinds := kinds || 'game_raid_reward'::text;
    alter table public.ledger_entries drop constraint ledger_entries_kind_check;
    execute 'alter table public.ledger_entries add constraint ledger_entries_kind_check check (kind in (' || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
  end if;
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.notifications'::regclass and conname = 'notifications_kind_check';
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  if not ('raid_reward' = any (kinds)) then
    kinds := kinds || 'raid_reward'::text;
    alter table public.notifications drop constraint notifications_kind_check;
    execute 'alter table public.notifications add constraint notifications_kind_check check (kind in (' || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
  end if;
end $$;

-- ---------- impostazioni ----------
insert into public.system_settings (key, value_int, description) values
 ('game_raid_enabled',     1,   'Eroi: 1 = raid settimanale (il boss del giorno è spento), 0 = torna il boss del giorno'),
 ('game_raid_difficulty',  45,  'Raid: PV in % di quanto possono colpire in una settimana gli eroi attivi (più alto = più duro)'),
 ('game_raid_retal_pct',   6,   'Raid: PV che il boss toglie a ogni tuo attacco, in % dei tuoi PV massimi (circa 16 attacchi al giorno)'),
 ('game_raid_bc_base',     350, 'Raid: BC a chi ha colpito almeno una volta, se il boss cade'),
 ('game_raid_bc_pool',     200, 'Raid: BC per partecipante nel montepremi diviso in proporzione al danno'),
 ('game_raid_bc_top1',     500, 'Raid: BC extra al 1° per danni'),
 ('game_raid_bc_top2',     300, 'Raid: BC extra al 2° per danni'),
 ('game_raid_bc_top3',     150, 'Raid: BC extra al 3° per danni')
on conflict (key) do nothing;

-- ---------- catalogo dei boss del raid (8 nuovi, a rotazione) ----------
create table if not exists public.game_raid_bosses (
  no smallint primary key check (no >= 1),
  name text not null, emoji text not null, sprite text not null, tint smallint not null default 0 check (tint between 0 and 4),
  zone smallint not null default 1, lore text not null, trait text not null,
  dmg_taken numeric not null default 1, retal_mult numeric not null default 1, shield_eff numeric not null default 1, heal_eff numeric not null default 1
);
insert into public.game_raid_bosses (no, name, emoji, sprite, tint, zone, lore, trait, dmg_taken, retal_mult, shield_eff, heal_eff) values
 (1, 'Il Leviatano delle Maree Spezzate', '🐙', 'kraken', 0, 450, 'Si è svegliato sotto le fondamenta del Tempio e ha sete di duellanti.', 'Tentacoli ovunque: colpisce più forte (rappresaglia +15%), ma è lento a difendersi.', 1.05, 1.15, 1, 1),
 (2, 'Il Colosso d''Ossidiana', '🗿', 'titano', 3, 100, 'Una montagna che cammina: ogni passo apre una crepa nelle mura.', 'Pelle di vetro nero: danni −15%, ma le guardie valgono il 25% in più.', 0.85, 1, 1.25, 1),
 (3, 'La Regina delle Mille Lame', '⚔️', 'cavaliere', 4, 150, 'Non ha mai perso un duello: colleziona le spade degli sconfitti.', 'Contrattacco affilato: rappresaglia +25%, ma le cure rendono il 20% in più.', 1, 1.25, 1, 1.2),
 (4, 'Il Drago Senza Stelle', '🐉', 'drago', 3, 200, 'Ha divorato le stelle sopra Bologna. Ora il cielo è suo.', 'Scaglie del vuoto: danni −10%, cure −10%.', 0.9, 1.05, 1, 0.9),
 (5, 'L''Occhio che Non Dorme', '👁️', 'occhio', 1, 300, 'Vede ogni mossa prima che tu la faccia. Quasi ogni mossa.', 'Preveggenza: rappresaglia +10%, ma Studia scopre debolezze più facilmente.', 1, 1.1, 1, 1),
 (6, 'La Fenice d''Ombra', '🔥', 'fenice', 4, 100, 'Rinasce dalle ceneri dei mazzi bruciati.', 'Fiamme nere: le cure rendono il 25% in meno, i danni subiti +10%.', 1.1, 1, 1, 0.75),
 (7, 'L''Arconte del Vuoto', '🌀', 'arconte', 2, 700, 'Il custode di ciò che c''era prima della prima carta.', 'Vuoto: danni −20%, rappresaglia −10%.', 0.8, 0.9, 1, 1),
 (8, 'Il Titano del Tempo', '⏳', 'sovrano', 4, 450, 'Ha visto nascere e morire mille Tempi. Questo è il prossimo.', 'Eterno: tutto un po'' più difficile (danni −10%, rappresaglia +10%, guardie e cure −10%).', 0.9, 1.1, 0.9, 0.9)
on conflict (no) do update set name = excluded.name, emoji = excluded.emoji, sprite = excluded.sprite, tint = excluded.tint, zone = excluded.zone,
  lore = excluded.lore, trait = excluded.trait, dmg_taken = excluded.dmg_taken, retal_mult = excluded.retal_mult, shield_eff = excluded.shield_eff, heal_eff = excluded.heal_eff;

-- ---------- tabelle del raid ----------
create table if not exists public.game_raids (
  id bigserial primary key,
  week_start date not null unique,                     -- lunedì (ora italiana)
  boss_no smallint not null references public.game_raid_bosses(no),
  cycle integer not null default 0,
  diff numeric not null default 1 check (diff > 0),    -- difficoltà adattiva
  max_hp bigint not null check (max_hp > 0),
  hp bigint not null check (hp >= 0),
  weak smallint not null default 0 check (weak between 0 and 40),
  heroes_at_start integer not null default 0,
  status text not null default 'open' check (status in ('open', 'defeated', 'escaped')),
  defeated_at timestamptz,
  settled_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.game_raid_days (      -- stato di oggi di ogni eroe nel raid (PV pieni ogni giorno)
  raid_id bigint not null references public.game_raids(id),
  day date not null,
  user_id uuid not null references public.profiles(id) on delete restrict,
  hp bigint not null, max_hp bigint not null, shield bigint not null default 0,
  actions_used smallint not null default 0,
  primary key (raid_id, day, user_id)
);
create table if not exists public.game_raid_damage (    -- totali della settimana (classifica)
  raid_id bigint not null references public.game_raids(id),
  user_id uuid not null references public.profiles(id) on delete restrict,
  dmg bigint not null default 0, hits integer not null default 0, heals bigint not null default 0, guards bigint not null default 0, studied integer not null default 0,
  last_at timestamptz not null default now(),
  primary key (raid_id, user_id)
);
create index if not exists game_raid_damage_rank on public.game_raid_damage (raid_id, dmg desc);
create table if not exists public.game_raid_log (
  id bigserial primary key,
  raid_id bigint not null references public.game_raids(id),
  user_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check (action in ('attack', 'guard', 'heal', 'study')),
  amount bigint not null default 0, target_id uuid references public.profiles(id), note text,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists game_raid_log_idx on public.game_raid_log (raid_id, id desc);
create index if not exists game_raid_log_user on public.game_raid_log (user_id, action);
create table if not exists public.game_raid_rewards (
  raid_id bigint not null references public.game_raids(id),
  user_id uuid not null references public.profiles(id) on delete restrict,
  rank integer not null, dmg bigint not null, won boolean not null,
  bc integer not null default 0, xp bigint not null default 0, item_id text references public.game_items(id), item2_id text references public.game_items(id),
  levels_gained integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (raid_id, user_id)
);

do $$ declare t text; begin
  foreach t in array array['game_raid_bosses','game_raids','game_raid_days','game_raid_damage','game_raid_log','game_raid_rewards'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
create policy game_raid_bosses_read on public.game_raid_bosses for select to authenticated using (true);
create policy game_raids_read on public.game_raids for select to authenticated using (public._module_on('heroes') or public.is_admin());
create policy game_raid_damage_read on public.game_raid_damage for select to authenticated using (public._module_on('heroes') or public.is_admin());
create policy game_raid_log_read on public.game_raid_log for select to authenticated using (public._module_on('heroes') or public.is_admin());
create policy game_raid_rewards_read on public.game_raid_rewards for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy game_raid_days_read on public.game_raid_days for select to authenticated using (public._module_on('heroes') or public.is_admin());
grant select on public.game_raid_bosses, public.game_raids, public.game_raid_damage, public.game_raid_log, public.game_raid_rewards, public.game_raid_days to authenticated;

-- ---------- il boss del giorno è spento finché il raid è attivo ----------
create or replace function public._trg_raid_blocks_daily() returns trigger language plpgsql as $$
begin
  if coalesce(public._setting('game_raid_enabled'), 0) = 1 then
    raise exception 'Il boss del giorno è stato sostituito dal Raid settimanale: trovi il boss nella scheda Raid';
  end if;
  return new;
end $$;
drop trigger if exists game_day_heroes_raid on public.game_day_heroes;
create trigger game_day_heroes_raid before insert on public.game_day_heroes for each row execute function public._trg_raid_blocks_daily();

-- ---------- funzioni interne ----------
create or replace function public._raid_week(p_day date default null) returns date language sql stable as $$
  select date_trunc('week', coalesce(p_day, (now() at time zone 'Europe/Rome')::date))::date $$;
create or replace function public._raid_ends_at(p_week date) returns timestamptz language sql stable as $$
  select ((p_week + 7)::timestamp at time zone 'Europe/Rome') $$;

-- quanto può colpire un eroe in una settimana (attacchi prima di finire KO, ogni giorno, per 7 giorni)
create or replace function public._raid_capacity(p_user uuid) returns numeric language sql stable security definer set search_path = public as $$
  select c.s_for * 3 * 1.1 * (100.0 / greatest(1, public._setting('game_raid_retal_pct'))) * 7 from public._game_calc(p_user) c $$;

-- premi: idempotente (settled_at); p_won = il boss è caduto
create or replace function public._raid_settle(p_raid bigint) returns void language plpgsql security definer set search_path = public as $$
declare g public.game_raids%rowtype; b public.game_raid_bosses%rowtype; r record; v_n integer; v_tot numeric; v_won boolean; v_frac numeric;
        v_base integer; v_pool numeric; v_bc integer; v_xp bigint; v_it text; v_it2 text; rw jsonb; v_lv integer; v_bonus integer;
begin
  select * into g from public.game_raids where id = p_raid for update;
  if not found or g.settled_at is not null then return; end if;
  select * into b from public.game_raid_bosses where no = g.boss_no;
  v_won := g.status = 'defeated';
  v_frac := case when v_won then 1 else greatest(0, least(1, 1 - g.hp::numeric / g.max_hp)) end;
  select count(*), coalesce(sum(d.dmg), 0) into v_n, v_tot from public.game_raid_damage d join public.profiles p on p.id = d.user_id
   where d.raid_id = g.id and d.dmg > 0 and not p.suspended;
  v_base := round(coalesce(public._setting('game_raid_bc_base'), 350) * case when v_won then 1 else 0.5 end);
  v_pool := coalesce(public._setting('game_raid_bc_pool'), 200)::numeric * v_n * v_frac;
  for r in select d.user_id, d.dmg, row_number() over (order by d.dmg desc, d.last_at) as rk
             from public.game_raid_damage d join public.profiles p on p.id = d.user_id
            where d.raid_id = g.id and d.dmg > 0 and not p.suspended order by d.dmg desc, d.last_at loop
    v_bonus := case r.rk when 1 then public._setting('game_raid_bc_top1') when 2 then public._setting('game_raid_bc_top2') when 3 then public._setting('game_raid_bc_top3') else 0 end;
    v_bc := v_base + round(v_pool * r.dmg / greatest(v_tot, 1)) + round(coalesce(v_bonus, 0) * case when v_won then 1 else 0.5 end);
    select level into v_lv from public.game_heroes where user_id = r.user_id;
    v_xp := (40 + 2 * coalesce(v_lv, 1)) * case when v_won then 10 else 4 end;
    v_it := null; v_it2 := null;
    if v_won then
      v_it := public._game_draw_item(r.user_id, ((g.boss_no - 1) % 10) + 1);
      if v_it is not null then insert into public.game_inventory (user_id, item_id, source) values (r.user_id, v_it, 'boss'); end if;
      if r.rk <= 3 then
        v_it2 := public._game_draw_item(r.user_id, ((g.boss_no - 1) % 10) + 1);
        if v_it2 is not null then insert into public.game_inventory (user_id, item_id, source) values (r.user_id, v_it2, 'boss'); end if;
      end if;
    end if;
    if v_bc > 0 then
      perform public._ledger_move(r.user_id, v_bc, 'game_raid_reward', 'game_raid', null, 'raid:' || g.id || ':' || r.user_id,
        'Raid: ' || b.name || case when v_won then ' sconfitto' else ' scappato' end || ' (' || r.rk || '° per danni)');
    end if;
    rw := public._game_add_xp(r.user_id, v_xp);
    insert into public.game_raid_rewards (raid_id, user_id, rank, dmg, won, bc, xp, item_id, item2_id, levels_gained)
      values (g.id, r.user_id, r.rk, r.dmg, v_won, v_bc, coalesce((rw->>'xp')::bigint, v_xp), v_it, v_it2, coalesce((rw->>'levels')::integer, 0))
      on conflict do nothing;
    if v_won then update public.game_heroes set bosses_beaten = bosses_beaten + 1 where user_id = r.user_id; end if;
    perform public._notify(r.user_id, 'raid_reward', case when v_won then 'Raid vinto!' else 'Il boss del raid è scappato' end,
      b.name || case when v_won then ' è caduto. ' else ': tolto il ' || round(v_frac * 100) || '% dei PV. ' end || 'Sei ' || r.rk || '° per danni: +' || v_bc || ' BC.',
      'eroi.html#boss', 'game_raid', null);
  end loop;
  update public.game_raids set settled_at = clock_timestamp() where id = g.id;
end $$;

-- il raid di questa settimana (lo crea al primo accesso del lunedì e chiude quello vecchio)
create or replace function public._raid_ensure() returns bigint language plpgsql security definer set search_path = public as $$
declare w date := public._raid_week(); g public.game_raids%rowtype; prev public.game_raids%rowtype; v_no integer; v_cycle integer; v_diff numeric;
        v_nb integer; v_cap numeric := 0; v_n integer := 0; r record; v_hp bigint; b public.game_raid_bosses%rowtype;
begin
  select * into g from public.game_raids where week_start = w;
  if found then return g.id; end if;
  perform pg_advisory_xact_lock(hashtext('game_raid'));
  select * into g from public.game_raids where week_start = w;
  if found then return g.id; end if;
  -- chiude e premia i raid passati ancora aperti
  for prev in select * from public.game_raids where week_start < w and settled_at is null order by week_start loop
    update public.game_raids set status = 'escaped' where id = prev.id and status = 'open';
    perform public._raid_settle(prev.id);
  end loop;
  select count(*) into v_nb from public.game_raid_bosses;
  select * into prev from public.game_raids where week_start < w order by week_start desc limit 1;
  if not found then v_no := 1; v_cycle := 0; v_diff := 1;
  else
    v_no := prev.boss_no + 1; v_cycle := prev.cycle;
    if v_no > v_nb then v_no := 1; v_cycle := v_cycle + 1; end if;
    v_diff := greatest(0.3, least(5, prev.diff * case when prev.status = 'defeated' then 1.10 else 0.85 end));
  end if;
  select * into b from public.game_raid_bosses where no = v_no;
  for r in select h.user_id from public.game_heroes h join public.profiles p on p.id = h.user_id
            where h.stats_set and not p.suspended and h.last_active_at > now() - interval '14 days' loop
    v_cap := v_cap + public._raid_capacity(r.user_id); v_n := v_n + 1;
  end loop;
  v_hp := greatest(1000, ceil(v_cap * greatest(5, public._setting('game_raid_difficulty')) / 100.0 * v_diff / b.dmg_taken))::bigint;
  insert into public.game_raids (week_start, boss_no, cycle, diff, max_hp, hp, heroes_at_start) values (w, v_no, v_cycle, v_diff, v_hp, v_hp, v_n)
    returning * into g;
  return g.id;
end $$;

-- stato di oggi dell'eroe nel raid (PV pieni al primo ingresso del giorno)
create or replace function public._raid_me(p_raid bigint, p_user uuid) returns public.game_raid_days language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Europe/Rome')::date; x public.game_raid_days%rowtype; c record;
begin
  select * into x from public.game_raid_days where raid_id = p_raid and day = d and user_id = p_user for update;
  if found then return x; end if;
  select * into c from public._game_calc(p_user);
  insert into public.game_raid_days (raid_id, day, user_id, hp, max_hp) values (p_raid, d, p_user, c.max_hp, c.max_hp)
    on conflict do nothing;
  select * into x from public.game_raid_days where raid_id = p_raid and day = d and user_id = p_user for update;
  return x;
end $$;

-- ---------- azione nel raid ----------
create or replace function public.game_raid_act(p_action text, p_target uuid default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date := (now() at time zone 'Europe/Rome')::date; rid bigint; g public.game_raids%rowtype; b public.game_raid_bosses%rowtype; h public.game_heroes%rowtype; c record;
  me public.game_raid_days%rowtype; th public.game_raid_days%rowtype; v_lim integer; ref numeric; amt bigint := 0; crit boolean := false; dodge boolean := false;
  raw numeric; took bigint := 0; absorbed bigint := 0; v_hp bigint; v_dead boolean := false; v_note text; v_target uuid; v_weak integer; rw jsonb;
begin
  perform public._require_module('heroes');
  if coalesce(public._setting('game_raid_enabled'), 0) <> 1 then raise exception 'Il raid non è attivo'; end if;
  if p_action is null or p_action not in ('attack','guard','heal','study') then raise exception 'Azione non valida'; end if;
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v;
  if not h.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  rid := public._raid_ensure();
  select * into g from public.game_raids where id = rid for update;
  if g.status <> 'open' then raise exception 'Il boss di questa settimana è già caduto: il prossimo arriva lunedì'; end if;
  select * into b from public.game_raid_bosses where no = g.boss_no;
  select * into c from public._game_calc(v);
  me := public._raid_me(rid, v);
  v_lim := greatest(1, public._setting('game_daily_actions')) + c.extra_actions;
  if p_action <> 'attack' and me.actions_used >= v_lim then raise exception 'Hai usato tutte le azioni di supporto di oggi: l''attacco resta sempre libero'; end if;
  if me.hp <= 0 then raise exception 'Sei KO: un alleato deve curarti, oppure torni in forze domani'; end if;
  ref := 5 + 10 * c.level;

  if p_action = 'attack' then
    crit := random() < least(0.6, 0.05 + 0.4 * c.s_des / ref);
    amt := greatest(1, round(c.s_for * 3 * (0.85 + 0.3 * random()) * (case when crit then 1.6 else 1 end) * (1 + g.weak / 100.0) * b.dmg_taken)::bigint);
    amt := least(amt, g.hp);
    v_hp := g.hp - amt;
    update public.game_raids set hp = v_hp where id = g.id;
    v_dead := v_hp = 0;
    if not v_dead then
      dodge := random() < least(0.5, 0.03 + 0.35 * c.s_frt / ref);
      if not dodge then
        raw := me.max_hp * greatest(1, public._setting('game_raid_retal_pct')) / 100.0 * b.retal_mult * (1 + 0.1 * g.cycle) * (0.85 + 0.3 * random());
        absorbed := least(me.shield, round(raw)::bigint);
        took := greatest(0, round(raw)::bigint - absorbed);
        update public.game_raid_days set shield = shield - absorbed, hp = greatest(0, hp - took) where raid_id = rid and day = d and user_id = v;
      end if;
    end if;
    v_note := case when v_dead then 'colpo finale' when dodge then 'schivata' when crit then 'critico' end;
    insert into public.game_raid_damage (raid_id, user_id, dmg, hits) values (rid, v, amt, 1)
      on conflict (raid_id, user_id) do update set dmg = game_raid_damage.dmg + excluded.dmg, hits = game_raid_damage.hits + 1, last_at = now();
  elsif p_action = 'guard' then
    v_target := coalesce(p_target, v);
    if v_target <> v then
      select * into th from public.game_raid_days where raid_id = rid and day = d and user_id = v_target for update;
      if not found then raise exception 'Questo eroe oggi non sta combattendo nel raid'; end if;
    end if;
    amt := greatest(1, round(c.s_vig * 4 * b.shield_eff * (0.9 + 0.2 * random()))::bigint);
    update public.game_raid_days set shield = shield + amt where raid_id = rid and day = d and user_id = v_target;
    insert into public.game_raid_damage (raid_id, user_id, guards) values (rid, v, amt)
      on conflict (raid_id, user_id) do update set guards = game_raid_damage.guards + excluded.guards, last_at = now();
  elsif p_action = 'heal' then
    v_target := coalesce(p_target, v);
    select * into th from public.game_raid_days where raid_id = rid and day = d and user_id = v_target for update;
    if not found then raise exception 'Questo eroe oggi non sta combattendo nel raid'; end if;
    if th.hp >= th.max_hp then raise exception 'Non ha bisogno di cure'; end if;
    amt := greatest(1, round(c.s_spi * 6 * b.heal_eff * (0.9 + 0.2 * random()))::bigint);
    amt := least(amt, th.max_hp - th.hp);
    v_note := case when th.hp <= 0 then 'rianimato' end;
    update public.game_raid_days set hp = hp + amt where raid_id = rid and day = d and user_id = v_target;
    insert into public.game_raid_damage (raid_id, user_id, heals) values (rid, v, amt)
      on conflict (raid_id, user_id) do update set heals = game_raid_damage.heals + excluded.heals, last_at = now();
  else
    if g.weak >= 40 then raise exception 'La community ha già scoperto tutte le debolezze di questo boss'; end if;
    v_weak := least(2 + round(6 * least(1, c.s_des / ref))::integer + case when g.boss_no = 5 then 2 else 0 end, 40 - g.weak);
    amt := v_weak;
    update public.game_raids set weak = weak + v_weak where id = g.id;
    insert into public.game_raid_damage (raid_id, user_id, studied) values (rid, v, v_weak)
      on conflict (raid_id, user_id) do update set studied = game_raid_damage.studied + excluded.studied, last_at = now();
  end if;

  if p_action <> 'attack' then update public.game_raid_days set actions_used = actions_used + 1 where raid_id = rid and day = d and user_id = v; end if;
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1 where user_id = v;
  insert into public.game_raid_log (raid_id, user_id, action, amount, target_id, note) values (rid, v, p_action, amt, v_target, v_note);
  if v_dead then
    update public.game_raids set status = 'defeated', defeated_at = now() where id = g.id;
    perform public._raid_settle(g.id);
  end if;

  select * into g from public.game_raids where id = rid;
  select * into me from public.game_raid_days where raid_id = rid and day = d and user_id = v;
  rw := null;
  if v_dead then
    select jsonb_build_object('bc', r.bc, 'xp', r.xp, 'rank', r.rank, 'levels', r.levels_gained,
             'item', (select name from public.game_items where id = r.item_id), 'item2', (select name from public.game_items where id = r.item2_id))
      into rw from public.game_raid_rewards r where r.raid_id = rid and r.user_id = v;
  end if;
  return jsonb_build_object('action', p_action, 'amount', amt, 'crit', crit, 'dodge', dodge, 'taken', took, 'absorbed', absorbed, 'note', v_note,
    'target', v_target, 'my_hp', me.hp, 'my_max_hp', me.max_hp, 'my_shield', me.shield, 'ko', me.hp <= 0,
    'raid_hp', g.hp, 'raid_max_hp', g.max_hp, 'weak', g.weak, 'defeated', g.status = 'defeated',
    'actions_left', greatest(0, v_lim - me.actions_used), 'reward', rw);
end $$;

-- ---------- stato del raid per la pagina ----------
create or replace function public.game_raid_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := (now() at time zone 'Europe/Rome')::date;
  rid bigint; g public.game_raids%rowtype; b public.game_raid_bosses%rowtype; me public.game_raid_days%rowtype; c record; v_lim integer; v_tot numeric; v_n integer;
  prev public.game_raids%rowtype; out jsonb;
begin
  perform public._require_module('heroes');
  if coalesce(public._setting('game_raid_enabled'), 0) <> 1 then return jsonb_build_object('enabled', false); end if;
  rid := public._raid_ensure();
  select * into g from public.game_raids where id = rid;
  select * into b from public.game_raid_bosses where no = g.boss_no;
  select * into me from public.game_raid_days where raid_id = rid and day = d and user_id = v;
  select * into c from public._game_calc(v);
  v_lim := greatest(1, public._setting('game_daily_actions')) + coalesce(c.extra_actions, 0);
  select coalesce(sum(dmg), 0), count(*) filter (where dmg > 0) into v_tot, v_n from public.game_raid_damage where raid_id = rid;
  select * into prev from public.game_raids where week_start < g.week_start order by week_start desc limit 1;
  out := jsonb_build_object('enabled', true,
    'raid', jsonb_build_object('id', g.id, 'week_start', g.week_start, 'ends_at', public._raid_ends_at(g.week_start), 'status', g.status, 'defeated_at', g.defeated_at,
       'hp', g.hp, 'max_hp', g.max_hp, 'weak', g.weak, 'cycle', g.cycle, 'heroes_at_start', g.heroes_at_start, 'participants', v_n, 'total_dmg', v_tot,
       'boss', jsonb_build_object('no', b.no, 'name', b.name, 'emoji', b.emoji, 'sprite', b.sprite, 'tint', b.tint, 'zone', b.zone, 'lore', b.lore, 'trait', b.trait),
       'total_bosses', (select count(*) from public.game_raid_bosses)),
    'me', jsonb_build_object('in_today', me.user_id is not null, 'hp', coalesce(me.hp, c.max_hp), 'max_hp', coalesce(me.max_hp, c.max_hp), 'shield', coalesce(me.shield, 0),
       'actions_left', greatest(0, v_lim - coalesce(me.actions_used, 0)), 'actions_max', v_lim, 'ko', coalesce(me.hp, 1) <= 0,
       'dmg', coalesce((select dmg from public.game_raid_damage where raid_id = rid and user_id = v), 0),
       'hits', coalesce((select hits from public.game_raid_damage where raid_id = rid and user_id = v), 0),
       'rank', (select x.rk from (select user_id, row_number() over (order by dmg desc, last_at) rk from public.game_raid_damage where raid_id = rid and dmg > 0) x where x.user_id = v)),
    'top', coalesce((select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'nickname', p.nickname, 'dmg', x.dmg, 'hits', x.hits, 'heals', x.heals, 'guards', x.guards) order by x.dmg desc, x.last_at)
       from (select * from public.game_raid_damage where raid_id = rid and dmg > 0 order by dmg desc, last_at limit 10) x join public.profiles p on p.id = x.user_id), '[]'::jsonb),
    'today', coalesce((select jsonb_agg(jsonb_build_object('user_id', t.user_id, 'nickname', p.nickname, 'hp', t.hp, 'max_hp', t.max_hp, 'shield', t.shield) order by (t.hp::numeric / greatest(t.max_hp, 1)), p.nickname)
       from public.game_raid_days t join public.profiles p on p.id = t.user_id where t.raid_id = rid and t.day = d), '[]'::jsonb),
    'log', coalesce((select jsonb_agg(jsonb_build_object('nickname', p.nickname, 'user_id', l.user_id, 'action', l.action, 'amount', l.amount, 'note', l.note,
                       'target', (select nickname from public.profiles where id = l.target_id), 'at', l.created_at) order by l.id desc)
       from (select * from public.game_raid_log where raid_id = rid order by id desc limit 15) l join public.profiles p on p.id = l.user_id), '[]'::jsonb),
    'rules', jsonb_build_object('bc_base', public._setting('game_raid_bc_base'), 'bc_pool', public._setting('game_raid_bc_pool'),
       'top', jsonb_build_array(public._setting('game_raid_bc_top1'), public._setting('game_raid_bc_top2'), public._setting('game_raid_bc_top3')), 'retal_pct', public._setting('game_raid_retal_pct')),
    'my_reward', (select jsonb_build_object('bc', r.bc, 'xp', r.xp, 'rank', r.rank, 'won', r.won, 'item', (select name from public.game_items where id = r.item_id), 'item2', (select name from public.game_items where id = r.item2_id))
       from public.game_raid_rewards r where r.raid_id = rid and r.user_id = v),
    'previous', case when prev.id is null then null else jsonb_build_object('status', prev.status, 'boss', (select name from public.game_raid_bosses where no = prev.boss_no),
       'emoji', (select emoji from public.game_raid_bosses where no = prev.boss_no),
       'pct', round(100 * (1 - prev.hp::numeric / prev.max_hp)),
       'mine', (select jsonb_build_object('bc', r.bc, 'rank', r.rank) from public.game_raid_rewards r where r.raid_id = prev.id and r.user_id = v)) end
  );
  return out;
end $$;

-- ---------- badge: il raid conta per i badge degli Eroi già esistenti ----------
do $$ begin
  if to_regprocedure('public.badge_progress_extra(uuid)') is not null and to_regprocedure('public._badge_progress_extra_base(uuid)') is null then
    alter function public.badge_progress_extra(uuid) rename to _badge_progress_extra_base;
  end if;
end $$;
do $$ begin
  if to_regprocedure('public._badge_progress_extra_base(uuid)') is not null then
    execute $f$
    create or replace function public.badge_progress_extra(p_user uuid default null)
    returns table (code text, family text, area text, tier smallint, metric text, kind text, threshold bigint, value bigint,
                   earned boolean, earned_at timestamptz, hidden boolean, sort integer)
    language plpgsql stable security definer set search_path = public as $b$
    #variable_conflict use_column
    declare v_u uuid := coalesce(p_user, auth.uid()); v_self boolean;
    begin
      if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
      return query
      with base as (select * from public._badge_progress_extra_base(p_user)),
      ex as (
        select 'e_attacchi'::text as m, count(*)::bigint as n from public.game_raid_log l where l.user_id = v_u and l.action = 'attack'
        union all select 'e_cure', count(*) from public.game_raid_log l where l.user_id = v_u and l.action = 'heal'
        union all select 'e_guardia', count(*) from public.game_raid_log l where l.user_id = v_u and l.action = 'guard'
        union all select 'e_boss', count(*) from public.game_raid_rewards r where r.user_id = v_u and r.won)
      select b.code, b.family, b.area, b.tier, b.metric, b.kind, b.threshold,
             case when b.hidden or ex.n is null or ex.n = 0 then b.value else b.value + ex.n end,
             case when b.hidden then b.earned else coalesce(b.value + coalesce(ex.n, 0) >= b.threshold, b.earned) end,
             b.earned_at, b.hidden, b.sort
        from base b left join ex on ex.m = b.metric
       order by b.sort;
    end $b$;
    $f$;
    revoke all on function public.badge_progress_extra(uuid) from public, anon;
    grant execute on function public.badge_progress_extra(uuid) to authenticated;
    revoke all on function public._badge_progress_extra_base(uuid) from public, anon, authenticated;
  end if;
end $$;

-- ---------- vetrina della Home: aggiunge il raid (stessa funzione della 037, con una voce in più) ----------
do $$ begin
  if to_regprocedure('public.public_showcase()') is not null and to_regprocedure('public._public_showcase_base()') is null then
    alter function public.public_showcase() rename to _public_showcase_base;
  end if;
end $$;
create or replace function public.public_showcase() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s jsonb := coalesce(public._public_showcase_base(), '{}'::jsonb); g public.game_raids%rowtype; b public.game_raid_bosses%rowtype;
begin
  if public._module_on('heroes') and coalesce(public._setting('game_raid_enabled'), 0) = 1 then
    select * into g from public.game_raids where week_start = public._raid_week();
    if found then
      select * into b from public.game_raid_bosses where no = g.boss_no;
      s := s || jsonb_build_object('raid', jsonb_build_object('name', b.name, 'emoji', b.emoji, 'hp', g.hp, 'max_hp', g.max_hp, 'status', g.status,
        'ends_at', public._raid_ends_at(g.week_start), 'participants', (select count(*) from public.game_raid_damage d where d.raid_id = g.id and d.dmg > 0),
        'top', coalesce((select jsonb_agg(jsonb_build_object('n', p.nickname, 'dmg', x.dmg) order by x.dmg desc)
                 from (select * from public.game_raid_damage where raid_id = g.id and dmg > 0 order by dmg desc limit 3) x join public.profiles p on p.id = x.user_id), '[]'::jsonb)));
    else
      s := s || jsonb_build_object('raid', jsonb_build_object('status', 'waiting'));
    end if;
  end if;
  return s;
end $$;

-- ---------- permessi ----------
revoke all on function public._raid_week(date), public._raid_ends_at(date), public._raid_capacity(uuid), public._raid_settle(bigint), public._raid_ensure(),
  public._raid_me(bigint, uuid), public.game_raid_act(text, uuid), public.game_raid_state(), public._trg_raid_blocks_daily() from public, anon, authenticated;
grant execute on function public.game_raid_act(text, uuid), public.game_raid_state() to authenticated;
do $$ begin
  if to_regprocedure('public._public_showcase_base()') is not null then
    revoke all on function public._public_showcase_base() from public, anon, authenticated;
    revoke all on function public.public_showcase() from public;
    grant execute on function public.public_showcase() to anon, authenticated;
  end if;
end $$;

commit;
