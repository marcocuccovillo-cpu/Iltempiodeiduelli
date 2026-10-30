-- =====================================================================
-- MIGRAZIONE 029 — La guerra degli Eroi: LA TORRE INFINITA
--   Una torre con infiniti piani da scalare, da soli, un piano alla volta. Ogni piano è un combattimento contro un nemico che
--   cresce di piano in piano; ogni 10 piani c'è un BOSS con il suo aspetto (12 boss diversi che poi tornano più forti: «Risvegliato»,
--   «Ancestrale», «Eterno»…). Il combattimento usa le stesse regole dei duelli in Arena (stessa simulazione, stessi dadi), tutto lato server.
--   * Si combatte sempre il piano successivo al migliore raggiunto. Vinci → sali e incassi i premi di quel piano (una volta sola, mai ripetibili);
--     perdi → resti dove sei e puoi riprovare appena hai l'energia. Il piano si vede prima, con la stima delle probabilità di vittoria.
--   * Costo: energia (impostazione «game_tower_energy», 6), per vittoria e per sconfitta. La ricarica al livello (sotto il livello 100) vale anche qui.
--   * Premi di ogni piano: BC e XP che crescono con il piano (circa come i dungeon, a parità di energia); i piani boss danno 5 volte i BC e 3 volte l'XP.
--     Ai boss dei piani 10, 20, … 600 un oggetto esclusivo (60 reliquie: armi, armature, elmi, amuleti e ogni 5 una reliquia mitica con bonus XP).
--   * Difficoltà: il nemico del piano N ha la forza di un eroe di livello N (fino al piano 10 più debole, per i principianti); alcuni piani hanno
--     un «tratto» (Corazzato, Furioso, Veloce, Mistico, Anziano, Fragile) che cambia le statistiche e si vede in anticipo.
--   * Classifica dei piani, «prima conquista» di ogni piano boss e cronologia dei tuoi tentativi.
--   * Impostazioni (Admin › Impostazioni economiche): game_tower_energy (6), game_tower_bc_pct (100), game_tower_xp_pct (100), game_tower_difficulty (100).
--   * Si può rieseguire senza danni. Non tocca BC, registro, livelli o progressi già scritti. Annullamento: black-market-eroi-torre-down.sql
-- Da eseguire in Supabase (SQL Editor) DOPO le altre migrazioni della guerra degli Eroi (anche dopo il pacchetto «unico» dei dungeon 56–100).
-- I BC della Torre usano il tipo di movimento già esistente «game_dungeon_reward» (con riferimento «game_tower»): la Torre CREA BC, come boss e dungeon.
-- =====================================================================
begin;

insert into public.system_settings (key, value_int, description) values
 ('game_tower_energy',     6,   'Torre: energia spesa a ogni tentativo (vinto o perso)'),
 ('game_tower_bc_pct',     100, 'Torre: percentuale dei BC dei piani (100 = normale)'),
 ('game_tower_xp_pct',     100, 'Torre: percentuale dell''XP dei piani (100 = normale)'),
 ('game_tower_difficulty', 100, 'Torre: difficoltà dei nemici (%): 100 = normale')
on conflict (key) do nothing;

alter table public.game_items drop constraint if exists game_items_source_chk;
alter table public.game_items add constraint game_items_source_chk check (source in ('start','shop','boss','dungeon','tower'));
alter table public.game_inventory drop constraint if exists game_inventory_source_chk;
alter table public.game_inventory add constraint game_inventory_source_chk check (source in ('start','shop','boss','dungeon','tower'));

-- ---------- tabelle (tutte chiuse al browser: si passa solo dalle funzioni) ----------
create table if not exists public.game_tower (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  best_floor integer not null default 0 check (best_floor >= 0),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  reached_at timestamptz,
  updated_at timestamptz not null default now()
);
create table if not exists public.game_tower_fights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  floor integer not null check (floor >= 1),
  won boolean not null,
  rounds integer not null,
  hero_hp bigint not null,
  enemy_hp bigint not null,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists game_tower_fights_user_idx on public.game_tower_fights (user_id, created_at desc);
create table if not exists public.game_tower_firsts (            -- chi ha conquistato per primo un piano boss
  floor integer primary key check (floor >= 1),
  user_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);
create table if not exists public.game_tower_bosses (
  no smallint primary key check (no between 1 and 12),
  name text not null,
  fem boolean not null,
  gen text not null,
  emoji text not null,
  sprite text not null,
  lore text not null,
  trait text not null,
  w_for numeric not null, w_des numeric not null, w_vig numeric not null, w_spi numeric not null, w_frt numeric not null,
  check (abs(w_for + w_des + w_vig + w_spi + w_frt - 1) < 0.001)
);
create table if not exists public.game_tower_items (
  floor integer primary key check (floor >= 10 and floor % 10 = 0),
  item_id text not null unique references public.game_items(id) on delete restrict
);

alter table public.game_tower enable row level security;
alter table public.game_tower_fights enable row level security;
alter table public.game_tower_firsts enable row level security;
alter table public.game_tower_bosses enable row level security;
alter table public.game_tower_items enable row level security;
revoke all on public.game_tower, public.game_tower_fights, public.game_tower_firsts, public.game_tower_bosses, public.game_tower_items from public, anon, authenticated;

-- ---------- catalogo: boss e reliquie (si riscrive a ogni esecuzione) ----------
insert into public.game_tower_bosses (no, name, fem, gen, emoji, sprite, lore, trait, w_for, w_des, w_vig, w_spi, w_frt) values
 (1, 'Golem di Carta', false, 'del Golem di Carta', '🗿', 'golem', 'Un colosso di mazzi ripiegati: ogni carta che lo compone è una partita mai finita.', 'Corpo massiccio: tantissimi punti vita.', 0.3, 0.05, 0.45, 0.05, 0.15),
 (2, 'Drago delle Pergamene', false, 'del Drago delle Pergamene', '🐉', 'drago', 'Striscia tra i rotoli proibiti e sputa inchiostro bollente su chi sale troppo in fretta.', 'Soffio d’inchiostro: colpi molto potenti.', 0.4, 0.15, 0.25, 0.05, 0.15),
 (3, 'Strega delle Lanterne', true, 'della Strega delle Lanterne', '🧙', 'strega', 'Cuce le anime smarrite in lanterne e le appende lungo le scale della Torre.', 'Magia vitale: si cura a ogni turno.', 0.2, 0.25, 0.15, 0.3, 0.1),
 (4, 'Cavaliere dell’Eclissi', false, 'del Cavaliere dell’Eclissi', '⚔️', 'cavaliere', 'Un’armatura vuota che combatte nel buio: nessuno ha mai visto cosa c’è sotto l’elmo.', 'Armatura nera: schiva e resiste ai colpi.', 0.3, 0.1, 0.3, 0.0, 0.3),
 (5, 'Idra dei Mazzi', true, 'dell’Idra dei Mazzi', '🐍', 'idra', 'Ogni testa pesca una carta diversa, e nessuna delle tre promette niente di buono.', 'Tre teste: forza e vigore alti.', 0.35, 0.1, 0.35, 0.1, 0.1),
 (6, 'Fenice di Cenere', true, 'della Fenice di Cenere', '🔥', 'fenice', 'Brucia a ogni duello e ogni volta rinasce più furiosa di prima.', 'Rinascita: veloce e capace di curarsi.', 0.25, 0.3, 0.15, 0.25, 0.05),
 (7, 'Sovrano delle Ossa', false, 'del Sovrano delle Ossa', '💀', 'sovrano', 'Il re dei duellanti caduti, con una corona forgiata da mille sconfitte.', 'Maestà ossea: equilibrato e spietato.', 0.3, 0.1, 0.3, 0.1, 0.2),
 (8, 'Sentinella Cieca', true, 'della Sentinella Cieca', '👁️', 'occhio', 'Un solo occhio, che vede ogni tua mossa prima ancora che tu la faccia.', 'Sguardo fulmineo: colpi critici frequenti.', 0.2, 0.35, 0.2, 0.05, 0.2),
 (9, 'Titano di Cristallo', false, 'del Titano di Cristallo', '💎', 'titano', 'Nato dalla pressione di mille torri una sull’altra, riflette ogni colpo che riceve.', 'Corazza di cristallo: quasi impossibile da schivare, durissimo.', 0.35, 0.0, 0.4, 0.0, 0.25),
 (10, 'Kraken Notturno', false, 'del Kraken Notturno', '🐙', 'kraken', 'Emerge dai sotterranei allagati: i suoi tentacoli arrivano a ogni piano.', 'Mille tentacoli: forza e resistenza.', 0.35, 0.15, 0.3, 0.1, 0.1),
 (11, 'Arcidemone Scarlatto', false, 'dell’Arcidemone Scarlatto', '😈', 'demone', 'Firma ogni patto con il fuoco, e non ha mai pagato un conto in vita sua.', 'Furia infernale: attacchi devastanti.', 0.45, 0.2, 0.2, 0.05, 0.1),
 (12, 'Arconte del Tempio', false, 'dell’Arconte del Tempio', '👼', 'arconte', 'Custode ultimo del Tempio: giudica chiunque osi salire fin quassù.', 'Giudizio finale: bilanciato in tutto.', 0.25, 0.2, 0.25, 0.15, 0.15)
on conflict (no) do update set name = excluded.name, fem = excluded.fem, gen = excluded.gen, emoji = excluded.emoji, sprite = excluded.sprite,
  lore = excluded.lore, trait = excluded.trait, w_for = excluded.w_for, w_des = excluded.w_des, w_vig = excluded.w_vig, w_spi = excluded.w_spi, w_frt = excluded.w_frt;

insert into public.game_items (id, name, slot, tier, rarity, min_level, p_for, p_des, p_vig, p_spi, p_frt, xp_pct, extra_actions, descr, source) values
 ('tw10', 'Lama del Golem di Carta', 'weapon', 0, 'raro', 9, 12, 6, 0, 0, 0, 0, 0, 'Bottino del piano 10 della Torre Infinita.', 'tower'),
 ('tw20', 'Corazza del Drago delle Pergamene', 'armor', 0, 'raro', 18, 0, 0, 18, 0, 9, 0, 0, 'Bottino del piano 20 della Torre Infinita.', 'tower'),
 ('tw30', 'Elmo della Strega delle Lanterne', 'helm', 0, 'raro', 27, 0, 0, 12, 24, 0, 0, 0, 'Bottino del piano 30 della Torre Infinita.', 'tower'),
 ('tw40', 'Amuleto del Cavaliere dell’Eclissi', 'amulet', 0, 'raro', 36, 0, 14, 0, 0, 28, 0, 0, 'Bottino del piano 40 della Torre Infinita.', 'tower'),
 ('tw50', 'Reliquia dell’Idra dei Mazzi', 'tool', 0, 'mitico', 45, 0, 45, 0, 22, 0, 7, 0, 'Bottino del piano 50 della Torre Infinita.', 'tower'),
 ('tw60', 'Lama della Fenice di Cenere', 'weapon', 0, 'raro', 54, 36, 18, 0, 0, 0, 0, 0, 'Bottino del piano 60 della Torre Infinita.', 'tower'),
 ('tw70', 'Corazza del Sovrano delle Ossa', 'armor', 0, 'raro', 63, 0, 0, 40, 0, 20, 0, 0, 'Bottino del piano 70 della Torre Infinita.', 'tower'),
 ('tw80', 'Elmo della Sentinella Cieca', 'helm', 0, 'raro', 72, 0, 0, 22, 43, 0, 0, 0, 'Bottino del piano 80 della Torre Infinita.', 'tower'),
 ('tw90', 'Amuleto del Titano di Cristallo', 'amulet', 0, 'raro', 81, 0, 24, 0, 0, 47, 0, 0, 'Bottino del piano 90 della Torre Infinita.', 'tower'),
 ('tw100', 'Reliquia del Kraken Notturno', 'tool', 0, 'mitico', 90, 0, 69, 0, 34, 0, 10, 0, 'Bottino del piano 100 della Torre Infinita.', 'tower'),
 ('tw110', 'Lama dell’Arcidemone Scarlatto', 'weapon', 0, 'raro', 99, 53, 26, 0, 0, 0, 0, 0, 'Bottino del piano 110 della Torre Infinita.', 'tower'),
 ('tw120', 'Corazza dell’Arconte del Tempio', 'armor', 0, 'raro', 108, 0, 0, 56, 0, 28, 0, 0, 'Bottino del piano 120 della Torre Infinita.', 'tower'),
 ('tw130', 'Elmo del Golem di Carta Risvegliato', 'helm', 0, 'raro', 117, 0, 0, 30, 59, 0, 0, 0, 'Bottino del piano 130 della Torre Infinita.', 'tower'),
 ('tw140', 'Amuleto del Drago delle Pergamene Risvegliato', 'amulet', 0, 'raro', 126, 0, 30, 0, 0, 61, 0, 0, 'Bottino del piano 140 della Torre Infinita.', 'tower'),
 ('tw150', 'Reliquia della Strega delle Lanterne Risvegliata', 'tool', 0, 'mitico', 135, 0, 88, 0, 44, 0, 12, 0, 'Bottino del piano 150 della Torre Infinita.', 'tower'),
 ('tw160', 'Lama del Cavaliere dell’Eclissi Risvegliato', 'weapon', 0, 'epico', 144, 75, 38, 0, 0, 0, 0, 0, 'Bottino del piano 160 della Torre Infinita.', 'tower'),
 ('tw170', 'Corazza dell’Idra dei Mazzi Risvegliata', 'armor', 0, 'epico', 153, 0, 0, 78, 0, 39, 0, 0, 'Bottino del piano 170 della Torre Infinita.', 'tower'),
 ('tw180', 'Elmo della Fenice di Cenere Risvegliata', 'helm', 0, 'epico', 162, 0, 0, 40, 81, 0, 0, 0, 'Bottino del piano 180 della Torre Infinita.', 'tower'),
 ('tw190', 'Amuleto del Sovrano delle Ossa Risvegliato', 'amulet', 0, 'epico', 171, 0, 42, 0, 0, 83, 0, 0, 'Bottino del piano 190 della Torre Infinita.', 'tower'),
 ('tw200', 'Reliquia della Sentinella Cieca Risvegliata', 'tool', 0, 'mitico', 180, 0, 105, 0, 52, 0, 15, 0, 'Bottino del piano 200 della Torre Infinita.', 'tower'),
 ('tw210', 'Lama del Titano di Cristallo Risvegliato', 'weapon', 0, 'epico', 189, 89, 44, 0, 0, 0, 0, 0, 'Bottino del piano 210 della Torre Infinita.', 'tower'),
 ('tw220', 'Corazza del Kraken Notturno Risvegliato', 'armor', 0, 'epico', 198, 0, 0, 91, 0, 46, 0, 0, 'Bottino del piano 220 della Torre Infinita.', 'tower'),
 ('tw230', 'Elmo dell’Arcidemone Scarlatto Risvegliato', 'helm', 0, 'epico', 207, 0, 0, 47, 94, 0, 0, 0, 'Bottino del piano 230 della Torre Infinita.', 'tower'),
 ('tw240', 'Amuleto dell’Arconte del Tempio Risvegliato', 'amulet', 0, 'epico', 216, 0, 48, 0, 0, 96, 0, 0, 'Bottino del piano 240 della Torre Infinita.', 'tower'),
 ('tw250', 'Reliquia del Golem di Carta Ancestrale', 'tool', 0, 'mitico', 225, 0, 121, 0, 60, 0, 17, 0, 'Bottino del piano 250 della Torre Infinita.', 'tower'),
 ('tw260', 'Lama del Drago delle Pergamene Ancestrale', 'weapon', 0, 'epico', 234, 101, 50, 0, 0, 0, 0, 0, 'Bottino del piano 260 della Torre Infinita.', 'tower'),
 ('tw270', 'Corazza della Strega delle Lanterne Ancestrale', 'armor', 0, 'epico', 243, 0, 0, 104, 0, 52, 0, 0, 'Bottino del piano 270 della Torre Infinita.', 'tower'),
 ('tw280', 'Elmo del Cavaliere dell’Eclissi Ancestrale', 'helm', 0, 'epico', 252, 0, 0, 53, 106, 0, 0, 0, 'Bottino del piano 280 della Torre Infinita.', 'tower'),
 ('tw290', 'Amuleto dell’Idra dei Mazzi Ancestrale', 'amulet', 0, 'epico', 261, 0, 54, 0, 0, 108, 0, 0, 'Bottino del piano 290 della Torre Infinita.', 'tower'),
 ('tw300', 'Reliquia della Fenice di Cenere Ancestrale', 'tool', 0, 'mitico', 270, 0, 135, 0, 68, 0, 20, 0, 'Bottino del piano 300 della Torre Infinita.', 'tower'),
 ('tw310', 'Lama del Sovrano delle Ossa Ancestrale', 'weapon', 0, 'epico', 279, 113, 56, 0, 0, 0, 0, 0, 'Bottino del piano 310 della Torre Infinita.', 'tower'),
 ('tw320', 'Corazza della Sentinella Cieca Ancestrale', 'armor', 0, 'epico', 288, 0, 0, 115, 0, 58, 0, 0, 'Bottino del piano 320 della Torre Infinita.', 'tower'),
 ('tw330', 'Elmo del Titano di Cristallo Ancestrale', 'helm', 0, 'epico', 297, 0, 0, 58, 117, 0, 0, 0, 'Bottino del piano 330 della Torre Infinita.', 'tower'),
 ('tw340', 'Amuleto del Kraken Notturno Ancestrale', 'amulet', 0, 'epico', 306, 0, 60, 0, 0, 119, 0, 0, 'Bottino del piano 340 della Torre Infinita.', 'tower'),
 ('tw350', 'Reliquia dell’Arcidemone Scarlatto Ancestrale', 'tool', 0, 'mitico', 315, 0, 149, 0, 74, 0, 22, 0, 'Bottino del piano 350 della Torre Infinita.', 'tower'),
 ('tw360', 'Lama dell’Arconte del Tempio Ancestrale', 'weapon', 0, 'leggendario', 324, 137, 68, 0, 0, 0, 0, 0, 'Bottino del piano 360 della Torre Infinita.', 'tower'),
 ('tw370', 'Corazza del Golem di Carta Eterno', 'armor', 0, 'leggendario', 333, 0, 0, 140, 0, 70, 0, 0, 'Bottino del piano 370 della Torre Infinita.', 'tower'),
 ('tw380', 'Elmo del Drago delle Pergamene Eterno', 'helm', 0, 'leggendario', 342, 0, 0, 71, 142, 0, 0, 0, 'Bottino del piano 380 della Torre Infinita.', 'tower'),
 ('tw390', 'Amuleto della Strega delle Lanterne Eterna', 'amulet', 0, 'leggendario', 351, 0, 72, 0, 0, 144, 0, 0, 'Bottino del piano 390 della Torre Infinita.', 'tower'),
 ('tw400', 'Reliquia del Cavaliere dell’Eclissi Eterno', 'tool', 0, 'mitico', 360, 0, 161, 0, 80, 0, 25, 0, 'Bottino del piano 400 della Torre Infinita.', 'tower'),
 ('tw410', 'Lama dell’Idra dei Mazzi Eterna', 'weapon', 0, 'leggendario', 369, 149, 74, 0, 0, 0, 0, 0, 'Bottino del piano 410 della Torre Infinita.', 'tower'),
 ('tw420', 'Corazza della Fenice di Cenere Eterna', 'armor', 0, 'leggendario', 378, 0, 0, 151, 0, 76, 0, 0, 'Bottino del piano 420 della Torre Infinita.', 'tower'),
 ('tw430', 'Elmo del Sovrano delle Ossa Eterno', 'helm', 0, 'leggendario', 387, 0, 0, 76, 153, 0, 0, 0, 'Bottino del piano 430 della Torre Infinita.', 'tower'),
 ('tw440', 'Amuleto della Sentinella Cieca Eterna', 'amulet', 0, 'leggendario', 396, 0, 78, 0, 0, 155, 0, 0, 'Bottino del piano 440 della Torre Infinita.', 'tower'),
 ('tw450', 'Reliquia del Titano di Cristallo Eterno', 'tool', 0, 'mitico', 405, 0, 173, 0, 86, 0, 27, 0, 'Bottino del piano 450 della Torre Infinita.', 'tower'),
 ('tw460', 'Lama del Kraken Notturno Eterno', 'weapon', 0, 'leggendario', 414, 160, 80, 0, 0, 0, 0, 0, 'Bottino del piano 460 della Torre Infinita.', 'tower'),
 ('tw470', 'Corazza dell’Arcidemone Scarlatto Eterno', 'armor', 0, 'leggendario', 423, 0, 0, 162, 0, 81, 0, 0, 'Bottino del piano 470 della Torre Infinita.', 'tower'),
 ('tw480', 'Elmo dell’Arconte del Tempio Eterno', 'helm', 0, 'leggendario', 432, 0, 0, 82, 164, 0, 0, 0, 'Bottino del piano 480 della Torre Infinita.', 'tower'),
 ('tw490', 'Amuleto del Golem di Carta Primordiale', 'amulet', 0, 'leggendario', 441, 0, 83, 0, 0, 166, 0, 0, 'Bottino del piano 490 della Torre Infinita.', 'tower'),
 ('tw500', 'Reliquia del Drago delle Pergamene Primordiale', 'tool', 0, 'mitico', 450, 0, 185, 0, 92, 0, 30, 0, 'Bottino del piano 500 della Torre Infinita.', 'tower'),
 ('tw510', 'Lama della Strega delle Lanterne Primordiale', 'weapon', 0, 'leggendario', 459, 170, 85, 0, 0, 0, 0, 0, 'Bottino del piano 510 della Torre Infinita.', 'tower'),
 ('tw520', 'Corazza del Cavaliere dell’Eclissi Primordiale', 'armor', 0, 'leggendario', 468, 0, 0, 172, 0, 86, 0, 0, 'Bottino del piano 520 della Torre Infinita.', 'tower'),
 ('tw530', 'Elmo dell’Idra dei Mazzi Primordiale', 'helm', 0, 'leggendario', 477, 0, 0, 87, 174, 0, 0, 0, 'Bottino del piano 530 della Torre Infinita.', 'tower'),
 ('tw540', 'Amuleto della Fenice di Cenere Primordiale', 'amulet', 0, 'leggendario', 486, 0, 88, 0, 0, 176, 0, 0, 'Bottino del piano 540 della Torre Infinita.', 'tower'),
 ('tw550', 'Reliquia del Sovrano delle Ossa Primordiale', 'tool', 0, 'mitico', 495, 0, 196, 0, 98, 0, 32, 0, 'Bottino del piano 550 della Torre Infinita.', 'tower'),
 ('tw560', 'Lama della Sentinella Cieca Primordiale', 'weapon', 0, 'leggendario', 504, 180, 90, 0, 0, 0, 0, 0, 'Bottino del piano 560 della Torre Infinita.', 'tower'),
 ('tw570', 'Corazza del Titano di Cristallo Primordiale', 'armor', 0, 'leggendario', 513, 0, 0, 182, 0, 91, 0, 0, 'Bottino del piano 570 della Torre Infinita.', 'tower'),
 ('tw580', 'Elmo del Kraken Notturno Primordiale', 'helm', 0, 'leggendario', 522, 0, 0, 92, 184, 0, 0, 0, 'Bottino del piano 580 della Torre Infinita.', 'tower'),
 ('tw590', 'Amuleto dell’Arcidemone Scarlatto Primordiale', 'amulet', 0, 'leggendario', 531, 0, 93, 0, 0, 186, 0, 0, 'Bottino del piano 590 della Torre Infinita.', 'tower'),
 ('tw600', 'Reliquia dell’Arconte del Tempio Primordiale', 'tool', 0, 'mitico', 540, 0, 207, 0, 104, 0, 35, 0, 'Bottino del piano 600 della Torre Infinita.', 'tower')
on conflict (id) do update set name = excluded.name, slot = excluded.slot, rarity = excluded.rarity, min_level = excluded.min_level, p_for = excluded.p_for, p_des = excluded.p_des,
  p_vig = excluded.p_vig, p_spi = excluded.p_spi, p_frt = excluded.p_frt, xp_pct = excluded.xp_pct, descr = excluded.descr;

insert into public.game_tower_items (floor, item_id) values
 (10, 'tw10'),
 (20, 'tw20'),
 (30, 'tw30'),
 (40, 'tw40'),
 (50, 'tw50'),
 (60, 'tw60'),
 (70, 'tw70'),
 (80, 'tw80'),
 (90, 'tw90'),
 (100, 'tw100'),
 (110, 'tw110'),
 (120, 'tw120'),
 (130, 'tw130'),
 (140, 'tw140'),
 (150, 'tw150'),
 (160, 'tw160'),
 (170, 'tw170'),
 (180, 'tw180'),
 (190, 'tw190'),
 (200, 'tw200'),
 (210, 'tw210'),
 (220, 'tw220'),
 (230, 'tw230'),
 (240, 'tw240'),
 (250, 'tw250'),
 (260, 'tw260'),
 (270, 'tw270'),
 (280, 'tw280'),
 (290, 'tw290'),
 (300, 'tw300'),
 (310, 'tw310'),
 (320, 'tw320'),
 (330, 'tw330'),
 (340, 'tw340'),
 (350, 'tw350'),
 (360, 'tw360'),
 (370, 'tw370'),
 (380, 'tw380'),
 (390, 'tw390'),
 (400, 'tw400'),
 (410, 'tw410'),
 (420, 'tw420'),
 (430, 'tw430'),
 (440, 'tw440'),
 (450, 'tw450'),
 (460, 'tw460'),
 (470, 'tw470'),
 (480, 'tw480'),
 (490, 'tw490'),
 (500, 'tw500'),
 (510, 'tw510'),
 (520, 'tw520'),
 (530, 'tw530'),
 (540, 'tw540'),
 (550, 'tw550'),
 (560, 'tw560'),
 (570, 'tw570'),
 (580, 'tw580'),
 (590, 'tw590'),
 (600, 'tw600')
on conflict (floor) do update set item_id = excluded.item_id;

-- ---------- funzioni interne ----------
-- tratto del piano (a volte nessuno): cambia le statistiche del nemico, si conosce in anticipo. I piani boss non ne hanno.
create or replace function public._game_tower_affix(p_floor integer) returns jsonb language sql immutable set search_path = public as $$
  select case when p_floor % 10 = 0 then null else
    case ((greatest(1, p_floor) * 7 + greatest(1, p_floor) / 5 + 3) % 10)
      when 4 then jsonb_build_object('key', 'corazzato', 'name', 'Corazzato', 'descr', 'Vigore +35%, Fortezza +20%', 'vig', 1.35, 'frt', 1.2)
      when 5 then jsonb_build_object('key', 'furioso', 'name', 'Furioso', 'descr', 'Forza +30%, Vigore −10%', 'for', 1.3, 'vig', 0.9)
      when 6 then jsonb_build_object('key', 'veloce', 'name', 'Veloce', 'descr', 'Destrezza +60%, Fortezza +30%', 'des', 1.6, 'frt', 1.3)
      when 7 then jsonb_build_object('key', 'mistico', 'name', 'Mistico', 'descr', 'Si cura molto (Spirito ×3), Vigore +10%', 'spi', 3, 'vig', 1.1)
      when 8 then jsonb_build_object('key', 'anziano', 'name', 'Anziano', 'descr', 'Tutte le statistiche +15%', 'for', 1.15, 'des', 1.15, 'vig', 1.15, 'spi', 1.15, 'frt', 1.15)
      when 9 then jsonb_build_object('key', 'fragile', 'name', 'Fragile', 'descr', 'Forza +25%, Vigore −30%', 'for', 1.25, 'vig', 0.7)
      else null end
  end $$;

-- il nemico di un piano: sempre lo stesso per lo stesso piano (nessun segreto: si vede in anticipo)
create or replace function public._game_tower_enemy(p_floor integer) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n integer := greatest(1, p_floor); is_boss boolean := n % 10 = 0; k integer := n / 10; fam integer; tier integer := least(3, (n - 1) / 100); cyc integer;
  bs public.game_tower_bosses%rowtype; af jsonb; m numeric; pts numeric := 20 + 3 * (n - 1); w numeric[]; s numeric[]; j integer; lab text;
  dif numeric := greatest(1, public._setting('game_tower_difficulty')) / 100.0; nm text; emo text; spr text; lore text; trait text;
  fams text[] := array['melma','pipistrello','scheletro','goblin','lupo','spettro','ragno','elementale'];
  emos text[] := array['🟢','🦇','💀','👺','🐺','👻','🕷️','🪨'];
  ws numeric[] := array[.20,.05,.45,.15,.15,  .25,.35,.10,.10,.20,  .35,.15,.25,0,.25,  .30,.30,.20,.05,.15,  .35,.30,.20,0,.15,  .20,.25,.15,.25,.15,  .30,.30,.15,.10,.15,  .30,.05,.35,.10,.20];
  nms text[] := array['Melma Verde','Melma Acida','Melma Abissale','Melma Primordiale',
                      'Pipistrello Cieco','Pipistrello d’Ombra','Pipistrello Sanguigno','Pipistrello Spettrale',
                      'Scheletro Errante','Scheletro Guerriero','Scheletro Cavaliere','Scheletro Maledetto',
                      'Goblin Ladro','Goblin Predone','Goblin Sciamano','Goblin Condottiero',
                      'Lupo Grigio','Lupo Nero','Lupo Spettrale','Lupo Ancestrale',
                      'Spettro Pallido','Spettro Lamentoso','Spettro Gelido','Spettro Antico',
                      'Ragno Tessitore','Ragno Velenoso','Ragno Gigante','Ragno dell’Abisso',
                      'Elementale di Pietra','Elementale di Brace','Elementale di Gelo','Elementale di Tempesta'];
  cm text[] := array['', 'Risvegliato', 'Ancestrale', 'Eterno', 'Primordiale', 'Supremo']; cf text[] := array['', 'Risvegliata', 'Ancestrale', 'Eterna', 'Primordiale', 'Suprema'];
begin
  if is_boss then
    select * into bs from public.game_tower_bosses where no = ((k - 1) % 12) + 1;
    cyc := (k - 1) / 12;
    lab := case when cyc < 6 then (case when bs.fem then cf[cyc + 1] else cm[cyc + 1] end) else (case when bs.fem then cf[6] else cm[6] end) || ' ' || (cyc - 6 + 2) end;
    nm := bs.name || case when lab = '' then '' else ' ' || lab end; emo := bs.emoji; spr := bs.sprite; lore := bs.lore; trait := bs.trait;
    w := array[bs.w_for, bs.w_des, bs.w_vig, bs.w_spi, bs.w_frt]; m := 1.15; tier := least(3, cyc);
  else
    fam := ((n * 5 + n / 7) % 8);
    nm := nms[fam * 4 + tier + 1]; emo := emos[fam + 1]; spr := fams[fam + 1]; lore := null; trait := null;
    w := array[ws[fam * 5 + 1], ws[fam * 5 + 2], ws[fam * 5 + 3], ws[fam * 5 + 4], ws[fam * 5 + 5]];
    m := least(1, 0.6 + 0.04 * n); af := public._game_tower_affix(n);
  end if;
  s := array[0, 0, 0, 0, 0];
  for j in 1..5 loop
    s[j] := greatest(1, round((5 + pts * w[j] * n) * m * dif * coalesce((af->>(array['for','des','vig','spi','frt'])[j])::numeric, 1)));
  end loop;
  return jsonb_build_object('floor', n, 'boss', is_boss, 'name', nm, 'emoji', emo, 'sprite', spr, 'tier', tier, 'cycle', case when is_boss then cyc else null end, 'lore', lore, 'trait', trait,
    'affix', case when af is null then null else jsonb_build_object('key', af->>'key', 'name', af->>'name', 'descr', af->>'descr') end,
    'level', n, 's_for', s[1], 's_des', s[2], 's_vig', s[3], 's_spi', s[4], 's_frt', s[5], 'max_hp', 50 + 12 * s[3]);
end $$;

-- stima dello scontro: rapporto tra il tempo che il nemico impiega ad abbattere l'eroe e quello dell'eroe con il nemico (>1: l'eroe è favorito)
create or replace function public._game_tower_ratio(p_hero jsonb, p_enemy jsonb) returns numeric language plpgsql immutable set search_path = public as $$
declare hl numeric := (p_hero->>'level')::numeric; el numeric := (p_enemy->>'level')::numeric; dh numeric; de numeric; ch numeric; ce numeric; dpt_h numeric; dpt_e numeric; t_h numeric; t_e numeric;
begin
  dh := least(0.5, 0.03 + 0.35 * (p_hero->>'s_frt')::numeric / (5 + 10 * hl));      -- schivata dell'eroe contro il nemico
  de := least(0.5, 0.03 + 0.35 * (p_enemy->>'s_frt')::numeric / (5 + 10 * el));     -- schivata del nemico contro l'eroe
  ch := least(0.6, 0.05 + 0.4 * (p_hero->>'s_des')::numeric / (5 + 10 * hl));
  ce := least(0.6, 0.05 + 0.4 * (p_enemy->>'s_des')::numeric / (5 + 10 * el));
  dpt_h := (1 - de) * 3 * (p_hero->>'s_for')::numeric * (1 + 0.6 * ch);
  dpt_e := (1 - dh) * 3 * (p_enemy->>'s_for')::numeric * (1 + 0.6 * ce);
  t_h := (p_enemy->>'max_hp')::numeric / greatest(dpt_h - (p_enemy->>'s_spi')::numeric, dpt_h * 0.05, 0.000001);
  t_e := (p_hero->>'max_hp')::numeric / greatest(dpt_e - (p_hero->>'s_spi')::numeric, dpt_e * 0.05, 0.000001);
  return t_e / t_h;
end $$;
create or replace function public._game_tower_chance(p_ratio numeric) returns integer language sql immutable set search_path = public as $$
  select greatest(1, least(99, round(100 / (1 + power(greatest(p_ratio, 0.000001), -2.8)))::integer)) $$;

-- premi del piano (la prima e unica volta che lo si vince)
create or replace function public._game_tower_reward(p_floor integer) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'bc', least(50000000, round((20 + 4::numeric * p_floor) * (case when p_floor % 10 = 0 then 5 else 1 end) * public._setting('game_tower_bc_pct') / 100.0)::bigint),
    'xp', round((60 + 3::numeric * p_floor) * (case when p_floor % 10 = 0 then 3 else 1 end) * public._setting('game_tower_xp_pct') / 100.0)::bigint,
    'item', (select jsonb_build_object('id', i.id, 'name', i.name, 'slot', i.slot, 'rarity', i.rarity, 'min_level', i.min_level, 'p_for', i.p_for, 'p_des', i.p_des, 'p_vig', i.p_vig,
                                       'p_spi', i.p_spi, 'p_frt', i.p_frt, 'xp_pct', i.xp_pct)
               from public.game_tower_items t join public.game_items i on i.id = t.item_id where t.floor = p_floor)) $$;

create or replace function public._game_tower_card(p_hero jsonb, p_floor integer) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e jsonb := public._game_tower_enemy(p_floor); r numeric := public._game_tower_ratio(p_hero, e);
begin
  return e || jsonb_build_object('ratio', round(r, 3), 'chance', public._game_tower_chance(r), 'reward', public._game_tower_reward(p_floor));
end $$;

-- ---------- stato della Torre ----------
create or replace function public.game_tower_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  t public.game_tower%rowtype; ca jsonb; best integer; fl integer; en numeric; cost integer := greatest(1, public._setting('game_tower_energy')); hs public.game_heroes%rowtype;
  nb integer; prev jsonb := '[]'::jsonb; j integer; rank_ integer; lvl integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select * into hs from public.game_heroes where user_id = v;
  select * into t from public.game_tower where user_id = v;
  best := coalesce(t.best_floor, 0); fl := best + 1;
  select to_jsonb(x) into ca from public._game_calc(v) x;
  en := public._game_energy_of(v);
  for j in fl + 1..fl + 4 loop
    prev := prev || jsonb_build_array(public._game_tower_card(ca, j) - 'reward' - 'lore' - 'trait');
  end loop;
  nb := ((best / 10) + 1) * 10;
  select count(*) + 1 into rank_ from public.game_tower o join public.profiles p on p.id = o.user_id
   where not p.suspended and (o.best_floor > best or (o.best_floor = best and o.reached_at < t.reached_at)) and o.best_floor > 0 and best > 0;
  return jsonb_build_object(
    'best_floor', best, 'next_floor', fl, 'wins', coalesce(t.wins, 0), 'losses', coalesce(t.losses, 0), 'rank', case when best > 0 then rank_ else null end,
    'stats_set', hs.stats_set, 'cost', cost, 'energy', round(en, 2), 'energy_max', public._game_energy_max(),
    'enemy', public._game_tower_card(ca, fl), 'boss_floor', nb, 'boss_in', nb - best,
    'boss', case when nb = fl then null else public._game_tower_card(ca, nb) - 'lore' - 'trait' end,
    'upcoming', prev,
    'recent', coalesce((select jsonb_agg(jsonb_build_object('floor', x.floor, 'won', x.won, 'rounds', x.rounds, 'at', x.created_at) order by x.created_at desc)
                          from (select * from public.game_tower_fights where user_id = v order by created_at desc limit 8) x), '[]'::jsonb),
    'top', coalesce((select jsonb_agg(jsonb_build_object('rank', q.rk, 'user_id', q.user_id, 'nickname', q.nickname, 'avatar', q.avatar, 'level', q.level, 'best_floor', q.best_floor, 'reached_at', q.reached_at) order by q.rk, q.nickname)
                       from (select o.user_id, p.nickname, p.avatar, h.level, o.best_floor, o.reached_at,
                                    rank() over (order by o.best_floor desc, o.reached_at asc) rk
                               from public.game_tower o join public.profiles p on p.id = o.user_id join public.game_heroes h on h.user_id = o.user_id
                              where o.best_floor > 0 and not p.suspended) q where q.rk <= 15), '[]'::jsonb),
    'hall', coalesce((select jsonb_agg(jsonb_build_object('floor', x.floor, 'nickname', x.nickname, 'avatar', x.avatar, 'boss', x.bname, 'at', x.created_at) order by x.created_at desc)
                        from (select f.floor, p.nickname, p.avatar, f.created_at, public._game_tower_enemy(f.floor)->>'name' as bname
                                from public.game_tower_firsts f join public.profiles p on p.id = f.user_id order by f.created_at desc limit 8) x), '[]'::jsonb));
end $$;

-- ---------- un tentativo: si combatte il piano successivo al migliore ----------
create or replace function public.game_tower_climb() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  hs public.game_heroes%rowtype; t public.game_tower%rowtype; ca jsonb; en jsonb; sim jsonb; fl integer; v_en numeric; cost integer := greatest(1, public._setting('game_tower_energy'));
  won boolean; rw jsonb := jsonb_build_object('xp', 0, 'levels', 0, 'energy_full', false); price jsonb; v_bc bigint := 0; v_xp bigint := 0; v_id uuid := gen_random_uuid(); item jsonb := null;
  v_first boolean := false; v_new public.game_tower%rowtype; v_item text; v_lvl integer; r numeric;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select * into hs from public.game_heroes where user_id = v for update;                 -- un tentativo alla volta per eroe
  if not hs.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  insert into public.game_tower (user_id) values (v) on conflict (user_id) do nothing;
  select * into t from public.game_tower where user_id = v for update;
  fl := t.best_floor + 1;
  v_en := public._game_energy_of(v);
  if v_en < cost then raise exception 'Energia insufficiente: per salire ne servono % (ora %)', cost, floor(v_en); end if;
  select to_jsonb(x) into ca from public._game_calc(v) x;
  en := public._game_tower_enemy(fl);
  r := public._game_tower_ratio(ca, en);
  sim := public._game_sim(ca, en);
  won := sim->>'winner' = 'a';
  if won then
    price := public._game_tower_reward(fl);
    v_bc := (price->>'bc')::bigint;
    if v_bc > 0 then
      perform public._ledger_move(v, v_bc::integer, 'game_dungeon_reward', 'game_tower', v_id, 'gametower:' || v::text || ':' || fl::text, 'La guerra degli Eroi: Torre Infinita, piano ' || fl);
    end if;
    rw := public._game_add_xp(v, (price->>'xp')::bigint);
    v_xp := (rw->>'xp')::bigint;
    if price->'item' is not null and price->'item' <> 'null'::jsonb then
      v_item := price->'item'->>'id';
      insert into public.game_inventory (user_id, item_id, source) values (v, v_item, 'tower') on conflict do nothing;
      item := price->'item';
    end if;
    if fl % 10 = 0 then
      insert into public.game_tower_firsts (floor, user_id) values (fl, v) on conflict (floor) do nothing;
      v_first := exists (select 1 from public.game_tower_firsts where floor = fl and user_id = v);
    end if;
    update public.game_tower set best_floor = fl, wins = wins + 1, reached_at = clock_timestamp(), updated_at = clock_timestamp() where user_id = v;
  else
    update public.game_tower set losses = losses + 1, updated_at = clock_timestamp() where user_id = v;
  end if;
  update public.game_heroes set last_active_at = now(), fights_total = fights_total + 1,
         energy = case when coalesce((rw->>'energy_full')::boolean, false) then public._game_energy_max() else greatest(0, v_en - cost) end, energy_at = now() where user_id = v;
  insert into public.game_tower_fights (id, user_id, floor, won, rounds, hero_hp, enemy_hp) values (v_id, v, fl, won, (sim->>'rounds')::integer, (sim->>'hp_a')::bigint, (sim->>'hp_b')::bigint);
  select level into v_lvl from public.game_heroes where user_id = v;
  select * into v_new from public.game_tower where user_id = v;
  return jsonb_build_object('won', won, 'floor', fl, 'enemy', en - 's_for' - 's_des' - 's_vig' - 's_spi' - 's_frt' || jsonb_build_object('ratio', round(r, 3), 'chance', public._game_tower_chance(r)),
    'rounds', sim->'rounds', 'log', sim->'log', 'hp_a', sim->'hp_a', 'hp_b', sim->'hp_b', 'max_a', sim->'max_a', 'max_b', sim->'max_b',
    'bc', v_bc, 'xp', v_xp, 'levels', coalesce((rw->>'levels')::integer, 0), 'level', v_lvl, 'energy_full', coalesce((rw->>'energy_full')::boolean, false), 'energy_cost', cost,
    'item', item, 'first_global', v_first, 'best_floor', v_new.best_floor, 'next_floor', v_new.best_floor + 1);
end $$;

-- ---------- permessi ----------
revoke all on function public._game_tower_affix(integer), public._game_tower_enemy(integer), public._game_tower_ratio(jsonb, jsonb), public._game_tower_chance(numeric),
  public._game_tower_reward(integer), public._game_tower_card(jsonb, integer) from public, anon, authenticated;
revoke all on function public.game_tower_state(), public.game_tower_climb() from public, anon;
grant execute on function public.game_tower_state(), public.game_tower_climb() to authenticated;

commit;
