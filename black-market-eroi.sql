-- =====================================================================
-- MIGRAZIONE 013 — LA GUERRA DEGLI EROI (mini gioco di ruolo multiplayer)
-- Da eseguire in Supabase (SQL Editor) DOPO la 012 (black-market-admin-utenti.sql). Si può rieseguire senza danni.
--
-- Che cosa aggiunge (tutto nel database: il browser legge e chiama funzioni, non scrive mai direttamente):
--   * Eroi (nickname del Black Market): livello 1…9999, XP, 5 statistiche (Forza, Destrezza, Vigore, Spirito, Fortuna)
--     con un numero fisso di punti abilità da distribuire; le statistiche CRESCONO COL LIVELLO nella proporzione scelta.
--   * Equipaggiamento: 5 slot (arma, armatura, elmo, amuleto, strumento), 5 oggetti base di partenza, 60 oggetti
--     acquistabili dal mercante, 10 oggetti esclusivi che cadono dai boss.
--   * Mercante: ogni giorno (mezzanotte italiana) propone 8 oggetti uguali per tutti, solo in BC (i BC spesi escono dal gioco).
--   * Arena: duelli asincroni tra eroi; chi vince guadagna SOLO XP (nessun BC).
--   * Boss del giorno (10 boss di difficoltà crescente): tutta la community lo combatte insieme (attacco, guardia, cura, studio).
--     Se viene sconfitto, ogni partecipante riceve 100 BC, XP doppia e un oggetto casuale. Se non lo si sconfigge, il giorno
--     dopo torna lo stesso boss; se lo si sconfigge, il giorno dopo arriva il successivo.
--   * Modulo «heroes» ACCESO per impostazione iniziale (si spegne da Admin › Moduli aggiuntivi; controllato anche qui).
-- BC: gli unici movimenti nuovi sono 'game_boss_reward' (+100 per partecipante, una volta sola per boss), 'game_purchase' e
-- 'game_respec' (addebiti). Passano tutti da _ledger_move, quindi saldi e registro restano coerenti.
-- =====================================================================
begin;

-- ---------- impostazioni (modificabili da Admin › Impostazioni economiche) ----------
insert into public.system_settings (key, value_int, description) values
 ('module_heroes',         1,   'La guerra degli Eroi: 1 = attiva, 0 = spenta'),
 ('game_stat_points',      20,  'Eroi: punti abilità da distribuire'),
 ('game_stat_cap',         10,  'Eroi: massimo di punti su una singola statistica'),
 ('game_daily_actions',    3,   'Eroi: azioni al giorno contro il boss'),
 ('game_daily_fights',     5,   'Eroi: duelli al giorno in Arena'),
 ('game_boss_bc',          100, 'Eroi: BC a ogni partecipante per boss sconfitto'),
 ('game_boss_min_actions', 2,   'Eroi: azioni minime per contare come partecipante al boss'),
 ('game_boss_difficulty',  100, 'Eroi: difficoltà dei boss in % (100 = normale, 150 = più duri)'),
 ('game_respec_cost',      100, 'Eroi: BC per ridistribuire i punti abilità dopo il primo scontro')
on conflict (key) do nothing;

-- i nuovi tipi di movimento BC
alter table public.ledger_entries drop constraint if exists ledger_entries_kind_check;
alter table public.ledger_entries add constraint ledger_entries_kind_check
  check (kind in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment','ladder_reward','shop_purchase','game_boss_reward','game_purchase','game_respec'));

-- l'interruttore del modulo accetta anche «heroes»
create or replace function public.admin_set_module(p_module text, p_enabled boolean, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o integer;
begin
  if p_module not in ('hall_of_fame','faction_wars','underground','ladder','heroes') then raise exception 'Modulo sconosciuto'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select value_int into o from public.system_settings where key = 'module_' || p_module for update;
  if not found then raise exception 'Impostazione inesistente: esegui le migrazioni precedenti'; end if;
  update public.system_settings set value_int = case when p_enabled then 1 else 0 end, updated_at = now(), updated_by = v where key = 'module_' || p_module;
  perform public._audit(v, 'set_module', 'module', p_module, jsonb_build_object('enabled', o = 1), jsonb_build_object('enabled', p_enabled), p_reason);
end $$;

-- ---------- tabelle ----------
create table if not exists public.game_heroes (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  level integer not null default 1 check (level between 1 and 9999),
  xp bigint not null default 0 check (xp >= 0),                       -- XP dentro il livello corrente
  total_xp bigint not null default 0 check (total_xp >= 0),
  a_for smallint not null default 0 check (a_for >= 0),               -- punti abilità assegnati
  a_des smallint not null default 0 check (a_des >= 0),
  a_vig smallint not null default 0 check (a_vig >= 0),
  a_spi smallint not null default 0 check (a_spi >= 0),
  a_frt smallint not null default 0 check (a_frt >= 0),
  stats_set boolean not null default false,
  arena_open boolean not null default true,                           -- si può essere sfidati in Arena
  duels_won integer not null default 0,
  duels_lost integer not null default 0,                              -- sfide lanciate e perse
  bosses_beaten integer not null default 0,
  fights_total integer not null default 0,                            -- scontri fatti (duelli + azioni contro il boss)
  respec_count integer not null default 0,
  created_at timestamptz not null default now(),
  last_active_at timestamptz not null default now()
);

create table if not exists public.game_items (
  id text primary key,
  name text not null,
  slot text not null check (slot in ('weapon','armor','helm','amulet','tool')),
  tier smallint not null,
  rarity text not null check (rarity in ('base','comune','non_comune','raro','epico','leggendario','mitico')),
  min_level integer not null check (min_level >= 1),
  price_bc integer check (price_bc is null or price_bc > 0),
  p_for smallint not null default 0, p_des smallint not null default 0, p_vig smallint not null default 0, p_spi smallint not null default 0, p_frt smallint not null default 0,  -- bonus in % sulla statistica
  xp_pct smallint not null default 0,
  extra_actions smallint not null default 0,
  extra_fights smallint not null default 0,
  descr text,
  source text not null check (source in ('start','shop','boss')),
  boss_no smallint,
  check ((source = 'shop') = (price_bc is not null))
);

create table if not exists public.game_inventory (
  user_id uuid not null references public.profiles(id) on delete restrict,
  item_id text not null references public.game_items(id),
  source text not null check (source in ('start','shop','boss')),
  acquired_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

create table if not exists public.game_equipped (
  user_id uuid not null,
  slot text not null check (slot in ('weapon','armor','helm','amulet','tool')),
  item_id text not null,
  primary key (user_id, slot),
  foreign key (user_id, item_id) references public.game_inventory(user_id, item_id) on delete restrict
);

create table if not exists public.game_bosses (
  no smallint primary key check (no >= 1),
  name text not null, emoji text not null, lore text not null, trait text not null,
  coverage numeric not null check (coverage > 0),       -- quanta parte della potenza dei giocatori attivi serve per batterlo
  retal numeric not null check (retal > 0),             -- colpo di rappresaglia, in frazione dei PV dell'eroe
  dmg_taken numeric not null default 1, shield_eff numeric not null default 1, heal_eff numeric not null default 1
);

create table if not exists public.game_days (
  day date primary key,
  boss_no smallint not null references public.game_bosses(no),
  cycle integer not null default 0,
  boss_level integer not null default 1,
  max_hp bigint not null check (max_hp > 0),
  hp bigint not null check (hp >= 0),
  shield bigint not null default 0 check (shield >= 0),
  weak smallint not null default 0 check (weak between 0 and 40),     -- debolezza scoperta (% di danno in più)
  status text not null default 'open' check (status in ('open','defeated','escaped')),
  defeated_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.game_day_heroes (
  day date not null references public.game_days(day) on update cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  hp bigint not null check (hp >= 0),
  max_hp bigint not null check (max_hp > 0),
  actions_used smallint not null default 0,
  dmg bigint not null default 0,
  healed bigint not null default 0,
  shielded bigint not null default 0,
  studied integer not null default 0,
  primary key (day, user_id)
);

create table if not exists public.game_day_log (
  id bigserial primary key,
  day date not null references public.game_days(day) on update cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check (action in ('attack','guard','heal','study')),
  amount bigint not null default 0,
  target_id uuid references public.profiles(id) on delete restrict,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists game_day_log_idx on public.game_day_log (day, id desc);

create table if not exists public.game_merchant_offers (
  day date not null,
  item_id text not null references public.game_items(id),
  price integer not null check (price > 0),
  discounted boolean not null default false,
  primary key (day, item_id)
);

create table if not exists public.game_duels (
  id uuid primary key default gen_random_uuid(),
  day date not null,
  attacker_id uuid not null references public.profiles(id) on delete restrict,
  defender_id uuid not null references public.profiles(id) on delete restrict,
  winner_id uuid not null references public.profiles(id) on delete restrict,
  atk_level integer not null, def_level integer not null,
  xp_awarded bigint not null default 0,
  rounds integer not null,
  log jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  check (attacker_id <> defender_id),
  unique (day, attacker_id, defender_id)
);
create index if not exists game_duels_att_idx on public.game_duels (attacker_id, day);
create index if not exists game_duels_def_idx on public.game_duels (defender_id, created_at desc);

create table if not exists public.game_rewards (
  id uuid primary key default gen_random_uuid(),
  day date not null,
  user_id uuid not null references public.profiles(id) on delete restrict,
  boss_no smallint not null,
  bc integer not null default 0,
  xp bigint not null default 0,
  item_id text references public.game_items(id),
  levels_gained integer not null default 0,
  created_at timestamptz not null default now(),
  unique (day, user_id)                                  -- un solo premio per boss e per eroe: impedisce doppi pagamenti
);

-- storico protetto: non si cancella
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'game_duels_nodel') then
    create trigger game_duels_nodel before delete on public.game_duels for each row execute function public._no_delete();
    create trigger game_rewards_nodel before delete on public.game_rewards for each row execute function public._no_delete();
    create trigger game_log_nodel before delete on public.game_day_log for each row execute function public._no_delete();
  end if;
end $$;

-- ---------- catalogo (oggetti e boss) ----------
insert into public.game_items (id, name, slot, tier, rarity, min_level, price_bc, p_for, p_des, p_vig, p_spi, p_frt, xp_pct, extra_actions, extra_fights, descr, source, boss_no) values
  ('s_weapon','Spada d''Addestramento','weapon',0,'base',1,null,1,0,0,0,0,0,0,0,'La prima lama di ogni novizio.','start',null),
  ('s_armor','Tunica da Novizio','armor',0,'base',1,null,0,0,1,0,0,0,0,0,'Stoffa robusta, niente di più.','start',null),
  ('s_helm','Cappuccio di Stoffa','helm',0,'base',1,null,0,0,0,1,0,0,0,0,'Ripara dal sole, non dai colpi.','start',null),
  ('s_amulet','Ciondolo di Legno','amulet',0,'base',1,null,0,0,0,0,1,0,0,0,'Un portafortuna intagliato a mano.','start',null),
  ('s_tool','Torcia del Novizio','tool',0,'base',1,null,0,1,0,0,0,0,0,0,'Fa luce nei corridoi del Tempio.','start',null),
  ('w01','Daga di Ferro','weapon',1,'comune',1,70,3,2,0,0,0,0,0,0,null,'shop',null),
  ('w02','Spada Corta d''Acciaio','weapon',2,'comune',3,180,6,3,0,0,0,0,0,0,null,'shop',null),
  ('w03','Lama del Pellegrino','weapon',3,'non_comune',6,360,9,4,0,0,0,0,0,0,null,'shop',null),
  ('w04','Scimitarra delle Dune','weapon',4,'non_comune',10,660,13,6,0,0,0,0,0,0,null,'shop',null),
  ('w05','Spadone del Guardiano','weapon',5,'raro',15,1080,17,8,0,0,0,0,0,0,null,'shop',null),
  ('w06','Lama di Ossidiana','weapon',6,'raro',22,1680,22,11,0,0,0,0,0,0,null,'shop',null),
  ('w07','Falcione Runico','weapon',7,'epico',32,2640,28,14,0,0,0,0,0,0,null,'shop',null),
  ('w08','Katana dell''Alba','weapon',8,'epico',45,4080,34,17,0,0,0,0,0,0,null,'shop',null),
  ('w09','Lama Celeste','weapon',9,'leggendario',65,6240,41,20,0,0,0,0,0,0,null,'shop',null),
  ('w10','Spada del Tempio Perduto','weapon',10,'leggendario',100,9600,49,24,0,0,0,0,0,0,null,'shop',null),
  ('w11','Frammento d''Eclissi','weapon',11,'mitico',200,18000,60,30,0,0,0,0,0,0,null,'shop',null),
  ('w12','Lama del Re Eterno','weapon',12,'mitico',500,42000,75,38,0,0,0,0,0,0,null,'shop',null),
  ('a01','Gilet di Cuoio','armor',1,'comune',1,65,0,0,3,0,2,0,0,0,null,'shop',null),
  ('a02','Giaco di Maglia','armor',2,'comune',3,165,0,0,6,0,3,0,0,0,null,'shop',null),
  ('a03','Corazza di Bronzo','armor',3,'non_comune',6,330,0,0,9,0,4,0,0,0,null,'shop',null),
  ('a04','Armatura del Custode','armor',4,'non_comune',10,605,0,0,13,0,6,0,0,0,null,'shop',null),
  ('a05','Piastre di Ferro Nero','armor',5,'raro',15,990,0,0,17,0,8,0,0,0,null,'shop',null),
  ('a06','Veste delle Mille Rune','armor',6,'raro',22,1540,0,0,22,0,11,0,0,0,null,'shop',null),
  ('a07','Armatura di Scaglie','armor',7,'epico',32,2420,0,0,28,0,14,0,0,0,null,'shop',null),
  ('a08','Corazza di Mithril','armor',8,'epico',45,3740,0,0,34,0,17,0,0,0,null,'shop',null),
  ('a09','Manto della Sentinella Lunare','armor',9,'leggendario',65,5720,0,0,41,0,20,0,0,0,null,'shop',null),
  ('a10','Armatura Aurorale','armor',10,'leggendario',100,8800,0,0,49,0,24,0,0,0,null,'shop',null),
  ('a11','Corazza dell''Eclissi','armor',11,'mitico',200,16500,0,0,60,0,30,0,0,0,null,'shop',null),
  ('a12','Armatura del Primo Duellante','armor',12,'mitico',500,38500,0,0,75,0,38,0,0,0,null,'shop',null),
  ('h01','Cappuccio Rinforzato','helm',1,'comune',1,55,0,0,2,3,0,0,0,0,null,'shop',null),
  ('h02','Elmo di Ferro','helm',2,'comune',3,135,0,0,3,6,0,0,0,0,null,'shop',null),
  ('h03','Elmo del Pellegrino','helm',3,'non_comune',6,270,0,0,4,9,0,0,0,0,null,'shop',null),
  ('h04','Cerchio d''Argento','helm',4,'non_comune',10,495,0,0,6,13,0,0,0,0,null,'shop',null),
  ('h05','Elmo del Custode','helm',5,'raro',15,810,0,0,8,17,0,0,0,0,null,'shop',null),
  ('h06','Maschera Runica','helm',6,'raro',22,1260,0,0,11,22,0,0,0,0,null,'shop',null),
  ('h07','Corona di Spine Lunari','helm',7,'epico',32,1980,0,0,14,28,0,0,0,0,null,'shop',null),
  ('h08','Elmo dell''Alba','helm',8,'epico',45,3060,0,0,17,34,0,0,0,0,null,'shop',null),
  ('h09','Diadema Stellare','helm',9,'leggendario',65,4680,0,0,20,41,0,0,0,0,null,'shop',null),
  ('h10','Elmo del Tempio','helm',10,'leggendario',100,7200,0,0,24,49,0,0,0,0,null,'shop',null),
  ('h11','Corona dell''Eclissi','helm',11,'mitico',200,13500,0,0,30,60,0,0,0,0,null,'shop',null),
  ('h12','Corona dei Mille Duelli','helm',12,'mitico',500,31500,0,0,38,75,0,0,0,0,null,'shop',null),
  ('m01','Ciondolo d''Osso','amulet',1,'comune',1,60,0,2,0,0,3,0,0,0,null,'shop',null),
  ('m02','Talismano di Rame','amulet',2,'comune',3,150,0,3,0,0,6,0,0,0,null,'shop',null),
  ('m03','Amuleto del Viandante','amulet',3,'non_comune',6,300,0,4,0,0,9,0,0,0,null,'shop',null),
  ('m04','Sigillo d''Argento','amulet',4,'non_comune',10,550,0,6,0,0,13,0,0,0,null,'shop',null),
  ('m05','Pendente Lunare','amulet',5,'raro',15,900,0,8,0,0,17,0,0,0,null,'shop',null),
  ('m06','Occhio di Giada','amulet',6,'raro',22,1400,0,11,0,0,22,0,0,0,null,'shop',null),
  ('m07','Amuleto del Drago','amulet',7,'epico',32,2200,0,14,0,0,28,0,0,0,null,'shop',null),
  ('m08','Talismano Solare','amulet',8,'epico',45,3400,0,17,0,0,34,0,0,0,null,'shop',null),
  ('m09','Cuore di Cristallo','amulet',9,'leggendario',65,5200,0,20,0,0,41,0,0,0,null,'shop',null),
  ('m10','Gemma del Tempio','amulet',10,'leggendario',100,8000,0,24,0,0,49,0,0,0,null,'shop',null),
  ('m11','Sigillo dell''Eclissi','amulet',11,'mitico',200,15000,0,30,0,0,60,0,0,0,null,'shop',null),
  ('m12','Amuleto del Duello Eterno','amulet',12,'mitico',500,35000,0,38,0,0,75,0,0,0,null,'shop',null),
  ('t01','Torcia Fumosa','tool',1,'comune',1,80,0,2,0,1,0,0,0,0,null,'shop',null),
  ('t02','Fiaschetta del Viandante','tool',2,'comune',3,195,0,4,0,2,0,0,0,0,null,'shop',null),
  ('t03','Bussola Incantata','tool',3,'non_comune',6,390,0,5,0,3,0,2,0,0,null,'shop',null),
  ('t04','Clessidra di Sabbia','tool',4,'non_comune',10,715,0,8,0,4,0,3,0,1,null,'shop',null),
  ('t05','Lanterna delle Anime','tool',5,'raro',15,1170,0,10,0,5,0,4,0,1,null,'shop',null),
  ('t06','Grimorio Consumato','tool',6,'raro',22,1820,0,13,0,7,0,6,0,1,null,'shop',null),
  ('t07','Pergamena del Sapiente','tool',7,'epico',32,2860,0,17,0,8,0,8,0,1,null,'shop',null),
  ('t08','Orologio Runico','tool',8,'epico',45,4420,0,20,0,10,0,10,1,2,null,'shop',null),
  ('t09','Prisma d''Aurora','tool',9,'leggendario',65,6760,0,25,0,12,0,12,1,2,null,'shop',null),
  ('t10','Chiave del Tempio','tool',10,'leggendario',100,10400,0,29,0,15,0,15,1,2,null,'shop',null),
  ('t11','Sfera dell''Eclissi','tool',11,'mitico',200,19500,0,36,0,18,0,20,1,3,null,'shop',null),
  ('t12','Reliquia del Tempo','tool',12,'mitico',500,45500,0,45,0,22,0,25,1,3,null,'shop',null),
  ('b01','Cuore di Granito','amulet',3,'epico',6,null,0,5,0,0,10,0,0,0,'Il cuore ancora caldo del Custode Smarrito.','boss',1),
  ('b02','Zanna del Ragno Lunare','weapon',4,'epico',10,null,15,7,0,0,0,0,0,0,'Una zanna che brilla alla luce della luna.','boss',2),
  ('b03','Pagina Sussurrante','tool',5,'epico',15,null,0,12,0,6,0,5,0,0,'Una pagina che mormora segreti a chi la legge.','boss',3),
  ('b04','Pelle di Chimera','armor',6,'epico',22,null,0,0,25,0,13,0,0,0,'Tre pelli in una: leone, capra e serpente.','boss',4),
  ('b05','Elmo Senza Volto','helm',7,'epico',32,null,0,0,16,32,0,0,0,0,'Chi lo indossa non ha più paura di niente.','boss',5),
  ('b06','Dente dell''Idra Nera','weapon',8,'epico',45,null,39,20,0,0,0,0,0,0,'Ogni dente ricresce più affilato.','boss',6),
  ('b07','Sigillo del Lich','tool',9,'epico',65,null,0,28,0,14,0,12,0,2,'Il sigillo che teneva chiuso il Tempio.','boss',7),
  ('b08','Scaglie dell''Eclissi','armor',10,'epico',100,null,0,0,56,0,28,0,0,0,'Scaglie nere che bevono la luce.','boss',8),
  ('b09','Perla dell''Abisso','amulet',11,'leggendario',200,null,0,34,0,0,69,0,0,0,'Dentro la perla si muove un oceano.','boss',9),
  ('b10','Lama Primordiale','weapon',12,'leggendario',500,null,86,43,0,0,0,0,0,0,'La lama con cui è cominciato il primo duello.','boss',10)
on conflict (id) do nothing;

insert into public.game_bosses (no, name, emoji, lore, trait, coverage, retal, dmg_taken, shield_eff, heal_eff) values
  (1,'Il Custode Smarrito','🗿','Un golem di pietra che ha dimenticato cosa doveva proteggere. Colpisce piano, ma non si ferma mai.','Pelle di granito: subisce il 15% di danni in meno.',0.3,0.1,0.85,1.0,1.0),
  (2,'Il Ragno Lunare','🕷️','Tesse ragnatele d''argento tra le colonne del Tempio e aspetta che qualcuno ci inciampi.','Veleno lunare: le cure rendono il 20% in meno.',0.4,0.12,1.0,1.0,0.8),
  (3,'Lo Spettro della Biblioteca','👻','Custodiva i libri dei duellanti antichi. Ora li difende con il rancore.','Incorporeo: le Guardie valgono il 25% in meno.',0.5,0.15,1.0,0.75,1.0),
  (4,'La Chimera delle Rovine','🦁','Leone, capra e serpente in un solo corpo. Ognuna delle tre teste ha fame.','Tre teste: danni -10% e cure -10%.',0.6,0.18,0.9,1.0,0.9),
  (5,'Il Cavaliere Senza Volto','⚔️','Nessuno ha mai visto il suo viso. Nessuno ha mai vinto un duello contro di lui, finora.','Armatura nera: danni -20%.',0.7,0.21,0.8,1.0,1.0),
  (6,'L''Idra delle Sabbie Nere','🐍','Taglia una testa e ne spuntano due. Il trucco è colpire tutti insieme.','Rigenera: le cure rendono il 25% in meno.',0.8,0.25,1.0,1.0,0.75),
  (7,'Il Lich Arcimago del Sigillo','🧙','Ha sigillato il Tempio per mille anni. Qualcuno ha rotto il sigillo, e adesso è arrabbiato.','Scudo arcano: le Guardie valgono il 40% in meno.',0.9,0.29,1.0,0.6,1.0),
  (8,'Il Drago dell''Eclissi','🐉','Quando le sue ali coprono il sole, il Tempio resta al buio per un giorno intero.','Scaglie d''ombra: danni -20%, Guardie -20%.',1.0,0.33,0.8,0.8,1.0),
  (9,'Il Titano dell''Abisso','🌊','Sale dalle profondità sotto il Tempio. Ogni suo passo fa tremare le fondamenta.','Mole colossale: danni -25%, cure -20%.',1.1,0.38,0.75,1.0,0.8),
  (10,'Il Duellante Primordiale','👁️','Il primo che abbia mai giocato una carta. Aspetta da sempre qualcuno alla sua altezza.','Maestria assoluta: danni, Guardie e cure -20%.',1.25,0.45,0.8,0.8,0.8)
on conflict (no) do nothing;

-- ---------- funzioni di servizio (non esposte al browser) ----------
create or replace function public._game_today() returns date language sql stable as $$ select (now() at time zone 'Europe/Rome')::date $$;
create or replace function public._game_next_reset() returns timestamptz language sql stable as $$ select ((public._game_today() + 1)::timestamp at time zone 'Europe/Rome') $$;
create or replace function public._game_xp_need(p_level integer) returns bigint language sql immutable as $$ select 100 + 10::bigint * p_level $$;

-- statistiche reali di un eroe: base 5 + punti × livello, poi i bonus % dell'equipaggiamento
create or replace function public._game_calc(p_user uuid)
returns table (level integer, s_for bigint, s_des bigint, s_vig bigint, s_spi bigint, s_frt bigint, max_hp bigint, xp_pct integer, extra_actions integer, extra_fights integer)
language sql stable security definer set search_path = public as $$
  with h as (select * from public.game_heroes where user_id = p_user),
  b as (select coalesce(sum(i.p_for),0) pf, coalesce(sum(i.p_des),0) pd, coalesce(sum(i.p_vig),0) pv, coalesce(sum(i.p_spi),0) ps, coalesce(sum(i.p_frt),0) pr,
               coalesce(sum(i.xp_pct),0) px, coalesce(sum(i.extra_actions),0) pa, coalesce(sum(i.extra_fights),0) pq
        from public.game_equipped e join public.game_items i on i.id = e.item_id where e.user_id = p_user),
  s as (select h.level,
          round((5 + h.a_for::numeric * h.level) * (100 + b.pf) / 100)::bigint as sf,
          round((5 + h.a_des::numeric * h.level) * (100 + b.pd) / 100)::bigint as sd,
          round((5 + h.a_vig::numeric * h.level) * (100 + b.pv) / 100)::bigint as sv,
          round((5 + h.a_spi::numeric * h.level) * (100 + b.ps) / 100)::bigint as ss,
          round((5 + h.a_frt::numeric * h.level) * (100 + b.pr) / 100)::bigint as sr,
          b.px, b.pa, b.pq from h, b)
  select s.level, s.sf, s.sd, s.sv, s.ss, s.sr, 50 + 12 * s.sv, s.px::integer, s.pa::integer, s.pq::integer from s $$;

-- XP: applica il bonus degli strumenti, sale di livello quante volte serve (tetto 9999)
create or replace function public._game_add_xp(p_user uuid, p_xp bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare h public.game_heroes%rowtype; pct integer; add_ bigint; gained integer := 0;
begin
  select * into h from public.game_heroes where user_id = p_user for update;
  if not found then raise exception 'Eroe inesistente'; end if;
  select xp_pct into pct from public._game_calc(p_user);
  add_ := greatest(0, p_xp) * (100 + coalesce(pct, 0)) / 100;
  if h.level < 9999 then
    h.xp := h.xp + add_;
    while h.level < 9999 and h.xp >= public._game_xp_need(h.level) loop
      h.xp := h.xp - public._game_xp_need(h.level); h.level := h.level + 1; gained := gained + 1;
    end loop;
    if h.level >= 9999 then h.xp := 0; end if;
  end if;
  update public.game_heroes set level = h.level, xp = h.xp, total_xp = total_xp + add_ where user_id = p_user;
  return jsonb_build_object('xp', add_, 'levels', gained, 'level', h.level);
end $$;

-- crea l'eroe al primo accesso, con l'equipaggiamento base già indossato
create or replace function public._game_ensure_hero(p_user uuid) returns void language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  insert into public.game_heroes (user_id) values (p_user) on conflict (user_id) do nothing;
  get diagnostics n = row_count;
  if n > 0 then
    insert into public.game_inventory (user_id, item_id, source) select p_user, id, 'start' from public.game_items where source = 'start' on conflict do nothing;
    insert into public.game_equipped (user_id, slot, item_id) select p_user, slot, id from public.game_items where source = 'start' on conflict do nothing;
  end if;
end $$;

-- il mercante del giorno: 8 oggetti (uno per slot + 3 a caso), uguali per tutti, uno scontato del 25%
create or replace function public._game_ensure_merchant(p_day date) returns void language plpgsql security definer set search_path = public as $$
declare v_max integer; v_disc text;
begin
  if exists (select 1 from public.game_merchant_offers where day = p_day) then return; end if;
  perform pg_advisory_xact_lock(hashtext('game_merchant'));
  if exists (select 1 from public.game_merchant_offers where day = p_day) then return; end if;
  select greatest(10, ceil(coalesce(max(level), 1) * 1.5)::integer) into v_max from public.game_heroes;
  insert into public.game_merchant_offers (day, item_id, price)
    select p_day, x.id, x.price_bc from (
      select distinct on (slot) id, slot, price_bc from public.game_items
      where source = 'shop' and min_level <= v_max order by slot, md5(p_day::text || id)) x;
  insert into public.game_merchant_offers (day, item_id, price)
    select p_day, i.id, i.price_bc from public.game_items i
    where i.source = 'shop' and i.min_level <= v_max
      and not exists (select 1 from public.game_merchant_offers o where o.day = p_day and o.item_id = i.id)
    order by md5(p_day::text || 'x' || i.id) limit 3;
  select item_id into v_disc from public.game_merchant_offers where day = p_day order by md5(p_day::text || 'sconto' || item_id) limit 1;
  update public.game_merchant_offers set price = greatest(1, round(price * 0.75)::integer), discounted = true where day = p_day and item_id = v_disc;
end $$;

-- il boss di oggi: se ieri è stato sconfitto passa al successivo, altrimenti si ripresenta lo stesso
create or replace function public._game_ensure_day() returns date language plpgsql security definer set search_path = public as $$
declare d date := public._game_today(); last_ public.game_days%rowtype; v_idx integer; v_cycle integer; v_nb integer; bo public.game_bosses%rowtype;
        r record; n integer := 0; sum_hit numeric := 0; sum_lvl numeric := 0; v_lvl integer; v_hit numeric; v_acts integer; v_hp bigint;
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
  update public.game_days set status = 'escaped' where status = 'open' and day < d;
  select * into bo from public.game_bosses where no = v_idx;
  for r in select h.user_id from public.game_heroes h join public.profiles p on p.id = h.user_id
           where h.stats_set and not p.suspended and h.last_active_at >= now() - interval '7 days' order by h.user_id loop
    select s_for * 3, level into v_hit, v_lvl from public._game_calc(r.user_id);
    n := n + 1; sum_hit := sum_hit + v_hit; sum_lvl := sum_lvl + v_lvl;
  end loop;
  if n = 0 then sum_hit := 27; sum_lvl := 1; n := 1; end if;
  if n < 3 then sum_hit := sum_hit / n * 3; end if;      -- come se fossero almeno 3 giocatori
  v_acts := greatest(1, public._setting('game_daily_actions'));
  v_hp := greatest(50, ceil(sum_hit * v_acts * bo.coverage * (1 + 0.25 * v_cycle) * greatest(10, public._setting('game_boss_difficulty')) / 100.0))::bigint;
  insert into public.game_days (day, boss_no, cycle, boss_level, max_hp, hp) values (d, v_idx, v_cycle, greatest(1, round(sum_lvl / n)::integer), v_hp, v_hp);
  return d;
end $$;

-- oggetti che l'eroe può ricevere in premio (peso per rarità; gli esclusivi del boss pesano 4 volte)
create or replace function public._game_cands(p_user uuid, p_boss integer) returns table (id text, w numeric) language sql stable security definer set search_path = public as $$
  select i.id, (case i.rarity when 'comune' then 50 when 'non_comune' then 30 when 'raro' then 14 when 'epico' then 5 when 'leggendario' then 1.2 else 0.25 end)
                * (case when i.source = 'boss' then 4 else 1 end)
  from public.game_items i, (select level from public.game_heroes where user_id = p_user) h
  where (i.source = 'shop' or (i.source = 'boss' and i.boss_no = p_boss)) and i.min_level <= h.level + 8
    and not exists (select 1 from public.game_inventory g where g.user_id = p_user and g.item_id = i.id) $$;

create or replace function public._game_draw_item(p_user uuid, p_boss integer) returns text language plpgsql security definer set search_path = public as $$
declare v_r numeric; v_tot numeric; v_id text;
begin
  select coalesce(sum(w), 0) into v_tot from public._game_cands(p_user, p_boss);
  if v_tot <= 0 then return null; end if;
  v_r := random() * v_tot;
  select x.id into v_id from (select c.id, sum(c.w) over (order by c.id) as cum from public._game_cands(p_user, p_boss) c) x where x.cum >= v_r order by x.cum limit 1;
  return v_id;
end $$;

-- il boss è caduto: premi UNA volta sola a chi ha partecipato (almeno N azioni)
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

-- scontro tra due eroi: a turni, fino a 60 colpi; restituisce vincitore e cronaca
create or replace function public._game_sim(a jsonb, b jsonb) returns jsonb language plpgsql volatile as $$
declare hpa bigint := (a->>'max_hp')::bigint; hpb bigint := (b->>'max_hp')::bigint; ma bigint := hpa; mb bigint := hpb;
        la numeric := 5 + 10 * (a->>'level')::numeric; lb numeric := 5 + 10 * (b->>'level')::numeric;
        first_a boolean := (a->>'s_des')::bigint >= (b->>'s_des')::bigint;
        i integer; turn_a boolean; dmg bigint; crit boolean; dodge boolean; log jsonb := '[]'::jsonb; w text; rounds integer := 0;
        s_for numeric; s_des numeric; l_att numeric; s_spi numeric; s_frt numeric; l_def numeric;
begin
  for i in 1..60 loop
    turn_a := case when first_a then i % 2 = 1 else i % 2 = 0 end;
    if turn_a then
      s_for := (a->>'s_for')::numeric; s_des := (a->>'s_des')::numeric; l_att := la; s_spi := (a->>'s_spi')::numeric; s_frt := (b->>'s_frt')::numeric; l_def := lb;
    else
      s_for := (b->>'s_for')::numeric; s_des := (b->>'s_des')::numeric; l_att := lb; s_spi := (b->>'s_spi')::numeric; s_frt := (a->>'s_frt')::numeric; l_def := la;
    end if;
    dodge := random() < least(0.5, 0.03 + 0.35 * s_frt / l_def);
    crit := random() < least(0.6, 0.05 + 0.4 * s_des / l_att);
    dmg := case when dodge then 0 else greatest(1, round(s_for * 3 * (0.85 + 0.3 * random()) * (case when crit then 1.6 else 1 end))::bigint) end;
    if turn_a then
      hpb := greatest(0, hpb - dmg); hpa := least(ma, hpa + s_spi::bigint);
    else
      hpa := greatest(0, hpa - dmg); hpb := least(mb, hpb + s_spi::bigint);
    end if;
    rounds := i;
    log := log || jsonb_build_array(jsonb_build_object('w', case when turn_a then 'a' else 'b' end, 'd', dmg, 'c', crit and not dodge, 'x', dodge, 'ha', hpa, 'hb', hpb));
    exit when hpa <= 0 or hpb <= 0;
  end loop;
  w := case when hpb <= 0 then 'a' when hpa <= 0 then 'b'
            when hpa::numeric / ma > hpb::numeric / mb then 'a' else 'b' end;     -- a tempo scaduto vince chi ha più PV in proporzione; pari = difensore
  return jsonb_build_object('winner', w, 'rounds', rounds, 'hp_a', hpa, 'hp_b', hpb, 'max_a', ma, 'max_b', mb, 'log', log);
end $$;

-- scheda di un eroe (per sé e per gli altri)
create or replace function public._game_hero_json(p_user uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'user_id', h.user_id, 'nickname', p.nickname, 'avatar', p.avatar,
    'level', h.level, 'xp', h.xp, 'xp_need', public._game_xp_need(h.level),
    'alloc', jsonb_build_object('for', h.a_for, 'des', h.a_des, 'vig', h.a_vig, 'spi', h.a_spi, 'frt', h.a_frt),
    'stats', jsonb_build_object('for', c.s_for, 'des', c.s_des, 'vig', c.s_vig, 'spi', c.s_spi, 'frt', c.s_frt),
    'max_hp', c.max_hp, 'xp_pct', c.xp_pct, 'extra_actions', c.extra_actions, 'extra_fights', c.extra_fights,
    'stats_set', h.stats_set, 'arena_open', h.arena_open, 'duels_won', h.duels_won, 'duels_lost', h.duels_lost, 'bosses_beaten', h.bosses_beaten,
    'respec_count', h.respec_count, 'fights_total', h.fights_total,
    'equipped', coalesce((select jsonb_object_agg(e.slot, jsonb_build_object('id', i.id, 'name', i.name, 'rarity', i.rarity, 'tier', i.tier, 'min_level', i.min_level,
        'p_for', i.p_for, 'p_des', i.p_des, 'p_vig', i.p_vig, 'p_spi', i.p_spi, 'p_frt', i.p_frt, 'xp_pct', i.xp_pct, 'extra_actions', i.extra_actions, 'extra_fights', i.extra_fights, 'descr', i.descr))
      from public.game_equipped e join public.game_items i on i.id = e.item_id where e.user_id = h.user_id), '{}'::jsonb))
  from public.game_heroes h join public.profiles p on p.id = h.user_id
  cross join lateral public._game_calc(h.user_id) c
  where h.user_id = p_user $$;

-- ---------- funzioni chiamate dal browser ----------
-- Tutto lo stato del gioco in una sola chiamata (crea l'eroe, il boss e il mercante del giorno se mancano)
create or replace function public.game_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date; dy public.game_days%rowtype; bo public.game_bosses%rowtype; prev public.game_days%rowtype; c record; dh public.game_day_heroes%rowtype;
  v_acts integer; v_fights integer; v_found boolean;
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
  return jsonb_build_object(
    'me', public._game_hero_json(v),
    'today', d, 'next_reset', public._game_next_reset(),
    'settings', jsonb_build_object('points', public._setting('game_stat_points'), 'cap', public._setting('game_stat_cap'), 'actions', public._setting('game_daily_actions'),
        'fights', public._setting('game_daily_fights'), 'boss_bc', public._setting('game_boss_bc'), 'min_actions', public._setting('game_boss_min_actions'),
        'respec_cost', public._setting('game_respec_cost')),
    'boss', jsonb_build_object(
        'no', bo.no, 'name', bo.name, 'emoji', bo.emoji, 'lore', bo.lore, 'trait', bo.trait, 'total', (select count(*) from public.game_bosses),
        'cycle', dy.cycle, 'level', dy.boss_level, 'hp', dy.hp, 'max_hp', dy.max_hp, 'shield', dy.shield, 'weak', dy.weak, 'status', dy.status,
        'retal', bo.retal, 'defeated_at', dy.defeated_at,
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
    'duels', jsonb_build_object('used', v_fights, 'limit', greatest(0, public._setting('game_daily_fights')) + c.extra_fights,
        'recent', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'attacker', pa.nickname, 'defender', pd.nickname, 'winner', pw.nickname, 'attacker_id', q.attacker_id, 'defender_id', q.defender_id,
                    'xp', q.xp_awarded, 'rounds', q.rounds, 'atk_level', q.atk_level, 'def_level', q.def_level, 'at', q.created_at) order by q.created_at desc)
                  from (select * from public.game_duels where attacker_id = v or defender_id = v order by created_at desc limit 10) q
                  join public.profiles pa on pa.id = q.attacker_id join public.profiles pd on pd.id = q.defender_id join public.profiles pw on pw.id = q.winner_id), '[]'::jsonb)),
    'rewards', coalesce((select jsonb_agg(jsonb_build_object('day', r.day, 'boss', b.name, 'emoji', b.emoji, 'bc', r.bc, 'xp', r.xp, 'item', it.name, 'item_rarity', it.rarity, 'levels', r.levels_gained) order by r.created_at desc)
                  from (select * from public.game_rewards where user_id = v order by created_at desc limit 5) r join public.game_bosses b on b.no = r.boss_no left join public.game_items it on it.id = r.item_id), '[]'::jsonb)
  );
end $$;

-- distribuzione dei punti abilità (gratis la prima volta e finché non si è combattuto; poi costa BC)
create or replace function public.game_set_stats(p_for integer, p_des integer, p_vig integer, p_spi integer, p_frt integer) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); h public.game_heroes%rowtype;
        v_pool integer := public._setting('game_stat_points'); v_cap integer := greatest(1, public._setting('game_stat_cap')); v_cost integer := public._setting('game_respec_cost'); v_paid boolean := false;
begin
  perform public._require_module('heroes');
  if p_for is null or p_des is null or p_vig is null or p_spi is null or p_frt is null then raise exception 'Punti non validi'; end if;
  if least(p_for, p_des, p_vig, p_spi, p_frt) < 0 then raise exception 'Punti non validi'; end if;
  if greatest(p_for, p_des, p_vig, p_spi, p_frt) > v_cap then raise exception 'Massimo % punti su una singola statistica', v_cap; end if;
  if p_for + p_des + p_vig + p_spi + p_frt > v_pool then raise exception 'Hai solo % punti da distribuire', v_pool; end if;
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v for update;
  if h.stats_set and (h.a_for, h.a_des, h.a_vig, h.a_spi, h.a_frt) = (p_for, p_des, p_vig, p_spi, p_frt) then
    return public._game_hero_json(v);                                  -- nessuna modifica: niente da pagare
  end if;
  if h.stats_set and h.fights_total > 0 and v_cost > 0 then
    perform public._ledger_move(v, -v_cost, 'game_respec', 'game_hero', null, 'gamerespec:' || v::text || ':' || (h.respec_count + 1)::text, 'La guerra degli Eroi: nuova distribuzione dei punti');
    v_paid := true;
  end if;
  update public.game_heroes set a_for = p_for, a_des = p_des, a_vig = p_vig, a_spi = p_spi, a_frt = p_frt, stats_set = true,
         respec_count = respec_count + case when h.stats_set then 1 else 0 end where user_id = v;
  return public._game_hero_json(v) || jsonb_build_object('paid', case when v_paid then v_cost else 0 end);
end $$;

create or replace function public.game_set_arena_open(p_open boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  update public.game_heroes set arena_open = coalesce(p_open, true) where user_id = v;
  return public._game_hero_json(v);
end $$;

create or replace function public.game_equip(p_item text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); it public.game_items%rowtype; h public.game_heroes%rowtype;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v;
  select i.* into it from public.game_items i join public.game_inventory g on g.item_id = i.id and g.user_id = v where i.id = p_item;
  if not found then raise exception 'Non possiedi questo oggetto'; end if;
  if h.level < it.min_level then raise exception 'Ti serve il livello % per indossarlo', it.min_level; end if;
  insert into public.game_equipped (user_id, slot, item_id) values (v, it.slot, it.id)
    on conflict (user_id, slot) do update set item_id = excluded.item_id;
  return public._game_hero_json(v);
end $$;

-- acquisto dal mercante di oggi: i BC escono dal gioco (nessuno li riceve)
create or replace function public.game_buy(p_item text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date; o public.game_merchant_offers%rowtype; it public.game_items%rowtype; h public.game_heroes%rowtype; v_bal integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  d := public._game_today(); perform public._game_ensure_merchant(d);
  select * into h from public.game_heroes where user_id = v for update;
  select * into o from public.game_merchant_offers where day = d and item_id = p_item;
  if not found then raise exception 'Oggi il mercante non vende questo oggetto'; end if;
  select * into it from public.game_items where id = p_item;
  if exists (select 1 from public.game_inventory where user_id = v and item_id = p_item) then raise exception 'Possiedi già questo oggetto'; end if;
  if h.level < it.min_level then raise exception 'Ti serve il livello % per acquistarlo', it.min_level; end if;
  v_bal := public._ledger_move(v, -o.price, 'game_purchase', 'game_item', null, 'gamebuy:' || v::text || ':' || p_item, 'Mercante degli Eroi: ' || it.name);
  if v_bal < 0 then raise exception 'Acquisto già registrato'; end if;
  insert into public.game_inventory (user_id, item_id, source) values (v, p_item, 'shop');
  return jsonb_build_object('item', it.name, 'price', o.price, 'balance', v_bal);
end $$;

-- azione contro il boss del giorno: attack | guard | heal | study
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
  if dy.status <> 'open' then raise exception 'Il boss di oggi è già stato sconfitto: torna domani'; end if;
  select * into bo from public.game_bosses where no = dy.boss_no;
  select * into c from public._game_calc(v);
  insert into public.game_day_heroes (day, user_id, hp, max_hp) values (d, v, c.max_hp, c.max_hp) on conflict do nothing;
  select * into dh from public.game_day_heroes where day = d and user_id = v for update;
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

-- duello in Arena: vince chi ha più PV alla fine; chi lancia la sfida e vince guadagna XP (solo XP)
create or replace function public.game_duel(p_target uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  d date := public._game_today(); a public.game_heroes%rowtype; b public.game_heroes%rowtype; ca jsonb; cb jsonb; sim jsonb; v_lim integer; v_used integer;
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
  v_lim := greatest(0, public._setting('game_daily_fights')) + (ca->>'extra_fights')::integer;
  select count(*) into v_used from public.game_duels where day = d and attacker_id = v;
  if v_used >= v_lim then raise exception 'Hai finito i duelli di oggi (%): torna domani', v_lim; end if;
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
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1 where user_id = v;
  insert into public.game_duels (id, day, attacker_id, defender_id, winner_id, atk_level, def_level, xp_awarded, rounds, log)
    values (v_id, d, v, p_target, v_win, a.level, b.level, v_xp, (sim->>'rounds')::integer, sim->'log');
  select nickname into pn from public.profiles where id = p_target;
  return jsonb_build_object('id', v_id, 'won', v_win = v, 'xp', v_xp, 'levels', (rw->>'levels')::integer, 'level', (rw->>'level')::integer, 'opponent', pn,
           'opponent_level', b.level, 'rounds', sim->'rounds', 'hp_a', sim->'hp_a', 'hp_b', sim->'hp_b', 'max_a', sim->'max_a', 'max_b', sim->'max_b', 'log', sim->'log',
           'left', greatest(0, v_lim - v_used - 1));
end $$;

-- chi si può sfidare in Arena (i più vicini al tuo livello per primi)
create or replace function public.game_arena_list() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); d date := public._game_today(); v_lvl integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select level into v_lvl from public.game_heroes where user_id = v;
  return coalesce((select jsonb_agg(x order by (x->>'gap')::integer, (x->>'level')::integer desc, x->>'nickname') from (
    select jsonb_build_object('user_id', h.user_id, 'nickname', p.nickname, 'avatar', p.avatar, 'level', h.level, 'bosses_beaten', h.bosses_beaten, 'duels_won', h.duels_won,
             'power', c.s_for + c.s_des + c.s_vig + c.s_spi + c.s_frt, 'gap', abs(h.level - v_lvl),
             'fought_today', exists (select 1 from public.game_duels q where q.day = d and q.attacker_id = v and q.defender_id = h.user_id)) as x
    from public.game_heroes h join public.profiles p on p.id = h.user_id cross join lateral public._game_calc(h.user_id) c
    where h.user_id <> v and h.stats_set and h.arena_open and not p.suspended order by abs(h.level - v_lvl), h.level desc limit 60) t), '[]'::jsonb);
end $$;

-- scheda di un altro eroe (equipaggiamento e statistiche sono pubblici)
create or replace function public.game_hero(p_user uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); r jsonb;
begin
  perform public._require_module('heroes');
  r := public._game_hero_json(p_user);
  if r is null then raise exception 'Eroe inesistente'; end if;
  return r;
end $$;

-- ---------- classifica, permessi e accessi ----------
create or replace view public.game_leaderboard_v as
  select h.user_id, p.nickname, p.avatar, h.level, h.xp, h.total_xp, h.duels_won, h.duels_lost, h.bosses_beaten,
         rank() over (order by h.level desc, h.xp desc, h.bosses_beaten desc) as rank
  from public.game_heroes h join public.profiles p on p.id = h.user_id
  where not p.suspended and h.stats_set and public._module_on('heroes');

do $$
declare t text;
begin
  foreach t in array array['game_heroes','game_items','game_inventory','game_equipped','game_bosses','game_days','game_day_heroes','game_day_log','game_merchant_offers','game_duels','game_rewards'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    if t in ('game_inventory','game_rewards') then
      execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid() or public.is_admin())', t || '_read', t);
    else
      execute format('create policy %I on public.%I for select to authenticated using (public._module_on(''heroes'') or public.is_admin())', t || '_read', t);
    end if;
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;
revoke all on public.game_leaderboard_v from public, anon, authenticated;
grant select on public.game_leaderboard_v to authenticated;
revoke all on sequence public.game_day_log_id_seq from public, anon, authenticated;

revoke all on function public._game_today(), public._game_next_reset(), public._game_xp_need(integer), public._game_calc(uuid), public._game_add_xp(uuid, bigint),
  public._game_ensure_hero(uuid), public._game_ensure_merchant(date), public._game_ensure_day(), public._game_cands(uuid, integer), public._game_draw_item(uuid, integer),
  public._game_finish_boss(date), public._game_sim(jsonb, jsonb), public._game_hero_json(uuid) from public, anon, authenticated;
revoke all on function public.game_state(), public.game_set_stats(integer, integer, integer, integer, integer), public.game_set_arena_open(boolean), public.game_equip(text),
  public.game_buy(text), public.game_boss_act(text, uuid), public.game_duel(uuid), public.game_arena_list(), public.game_hero(uuid), public.admin_set_module(text, boolean, text) from public, anon, authenticated;
grant execute on function public.game_state(), public.game_set_stats(integer, integer, integer, integer, integer), public.game_set_arena_open(boolean), public.game_equip(text),
  public.game_buy(text), public.game_boss_act(text, uuid), public.game_duel(uuid), public.game_arena_list(), public.game_hero(uuid), public.admin_set_module(text, boolean, text) to authenticated;
commit;
