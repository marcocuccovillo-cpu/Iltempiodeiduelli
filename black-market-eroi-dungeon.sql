-- =====================================================================
-- MIGRAZIONE 017 — La guerra degli Eroi: mini dungeon
--   25 mini dungeon a difficoltà crescente, ognuno con 4-6 stanze e un boss finale a tema Yu-Gi-Oh!.
--   Si affrontano da soli o in gruppo (fino a 4): chi vuole giocare crea una lobby, gli altri entrano, ognuno sceglie il ruolo
--   (Tank, Danni, Supporto) e il capo della lobby fa partire il dungeon. Costo: 20 energie a testa.
--   Premi: BC, XP e equipaggiamento (un oggetto esclusivo per dungeon; i dungeon 5, 10, 15, 20 e 25 danno un oggetto EPICO).
--   La prima volta si ottiene tutto; le repliche danno BC e XP ridotti e, con una certa probabilità, un oggetto.
--   I dungeon si sbloccano uno dopo l'altro.
-- Da eseguire in Supabase (SQL Editor) DOPO la 016. Si può rieseguire. Non tocca saldi o registro già scritti.
-- Nuovo tipo di movimento BC: game_dungeon_reward (solo entrate: i dungeon CREANO BC, come i boss).
-- =====================================================================
begin;

insert into public.system_settings (key, value_int, description) values
 ('game_dng_energy',          20,  'Dungeon: energia spesa da ogni giocatore per partire'),
 ('game_dng_max_party',       4,   'Dungeon: giocatori massimi per gruppo'),
 ('game_dng_lobby_minutes',   30,  'Dungeon: minuti dopo i quali una lobby non avviata scade'),
 ('game_dng_replay_bc_pct',   25,  'Dungeon: percentuale dei BC nelle repliche (dungeon già completato)'),
 ('game_dng_replay_xp_pct',   50,  'Dungeon: percentuale dell''XP nelle repliche'),
 ('game_dng_party_bonus_pct', 10,  'Dungeon: bonus BC per ogni giocatore in più nel gruppo (%)'),
 ('game_dng_drop_replay_pct', 35,  'Dungeon: probabilità (%) di un oggetto casuale in una replica'),
 ('game_dng_drop_extra_pct',  50,  'Dungeon: probabilità (%) di un secondo oggetto casuale alla prima vittoria'),
 ('game_dng_fail_xp_pct',     20,  'Dungeon: percentuale dell''XP data come consolazione se il gruppo viene sconfitto'),
 ('game_dng_difficulty',      100, 'Dungeon: difficoltà dei nemici (%): 100 = normale')
on conflict (key) do nothing;

alter table public.ledger_entries drop constraint if exists ledger_entries_kind_check;
alter table public.ledger_entries add constraint ledger_entries_kind_check
  check (kind in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment','ladder_reward','shop_purchase','game_boss_reward','game_purchase','game_respec','game_skill','game_dungeon_reward'));

-- gli oggetti possono arrivare anche dai dungeon
alter table public.game_items add column if not exists dungeon_no smallint;
do $$
declare c record;
begin
  for c in select conname, conrelid::regclass as tbl from pg_constraint where contype = 'c' and conrelid in ('public.game_items'::regclass, 'public.game_inventory'::regclass)
                and pg_get_constraintdef(oid) like '%''start''%' and pg_get_constraintdef(oid) like '%source%' loop
    execute format('alter table %s drop constraint %I', c.tbl, c.conname);
  end loop;
end $$;
alter table public.game_items drop constraint if exists game_items_source_chk;
alter table public.game_items add constraint game_items_source_chk check (source in ('start','shop','boss','dungeon'));
alter table public.game_inventory drop constraint if exists game_inventory_source_chk;
alter table public.game_inventory add constraint game_inventory_source_chk check (source in ('start','shop','boss','dungeon'));

-- ---------- tabelle ----------
create table if not exists public.game_dungeons (
  no smallint primary key check (no >= 1),
  name text not null,
  emoji text not null,
  lore text not null,
  boss_name text not null,
  boss_emoji text not null,
  boss_lore text not null,
  rooms jsonb not null,                       -- [{name, emoji, boss}] l'ultima stanza è quella del boss
  ref_level integer not null check (ref_level >= 1),   -- livello consigliato
  min_level integer not null check (min_level >= 1),   -- livello minimo per entrare
  bc integer not null check (bc >= 0),        -- BC della prima vittoria
  xp integer not null check (xp >= 0),        -- XP della prima vittoria
  diff numeric not null default 1 check (diff > 0),   -- moltiplicatore della forza dei nemici (1 = normale)
  item_id text                                -- oggetto esclusivo della prima vittoria
);
create table if not exists public.game_runs (
  id uuid primary key default gen_random_uuid(),
  dungeon_no smallint not null references public.game_dungeons(no),
  leader_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'lobby' check (status in ('lobby','cleared','failed','cancelled')),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  result jsonb
);
create index if not exists game_runs_status_idx on public.game_runs (status, created_at);
create table if not exists public.game_run_members (
  run_id uuid not null references public.game_runs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  role text not null check (role in ('tank','dps','support')),
  joined_at timestamptz not null default now(),
  primary key (run_id, user_id)
);
create index if not exists game_run_members_user_idx on public.game_run_members (user_id);
create table if not exists public.game_dungeon_progress (
  user_id uuid not null references public.profiles(id) on delete restrict,
  dungeon_no smallint not null references public.game_dungeons(no),
  clears integer not null default 0 check (clears >= 0),
  first_clear_at timestamptz,
  last_clear_at timestamptz,
  primary key (user_id, dungeon_no)
);

-- catalogo: dungeon e oggetti esclusivi (si riscrive a ogni esecuzione: i valori sono quelli del gioco)
insert into public.game_dungeons (no, name, emoji, lore, boss_name, boss_emoji, boss_lore, rooms, ref_level, min_level, bc, xp) values
 (1, 'Foresta dei Kuriboh', '🌲', 'Una foresta fitta di creature pelose e dispettose: il primo passo di ogni duellante.', 'Kuriboh Anziano', '🐾', 'Il più vecchio e testardo dei Kuriboh: non lascia passare nessuno.', '[{"name": "Kuriboh Selvatici", "emoji": "🛡️", "boss": false}, {"name": "Cuccioli di Ombra", "emoji": "🔥", "boss": false}, {"name": "Guardie del Sottobosco", "emoji": "⚡", "boss": false}, {"name": "Kuriboh Anziano", "emoji": "🐾", "boss": true}]'::jsonb, 1, 1, 150, 132),
 (2, 'Palude degli Zombi', '🧟', 'Dalla nebbia della palude escono i duellanti che non hanno mai perso la voglia di giocare.', 'Re Zombi', '🧟', 'Un sovrano marcio che comanda le carte dei defunti.', '[{"name": "Zombi Strascicanti", "emoji": "🔥", "boss": false}, {"name": "Scheletri di Palude", "emoji": "⚡", "boss": false}, {"name": "Mummie Fradicie", "emoji": "💀", "boss": false}, {"name": "Re Zombi", "emoji": "🧟", "boss": true}]'::jsonb, 3, 1, 190, 156),
 (3, 'Rovine dei Guerrieri', '⚔️', 'Antiche arene di pietra dove i guerrieri si sfidavano a colpi di spada.', 'Guardiano Celtico Corrotto', '🛡️', 'Un campione leale, piegato da un potere oscuro.', '[{"name": "Gladiatori di Pietra", "emoji": "⚡", "boss": false}, {"name": "Arcieri Spettrali", "emoji": "💀", "boss": false}, {"name": "Cavalieri Spezzati", "emoji": "🗡️", "boss": false}, {"name": "Guardiano Celtico Corrotto", "emoji": "🛡️", "boss": true}]'::jsonb, 5, 3, 240, 180),
 (4, 'Grotta dei Draghetti', '🐲', 'Un nido caldo e rumoroso: i draghi sono piccoli, ma sputano fuoco davvero.', 'Baby Drago Infuocato', '🔥', 'Il più grosso della nidiata, e il più affamato.', '[{"name": "Draghetti Scalpitanti", "emoji": "💀", "boss": false}, {"name": "Lucertole di Brace", "emoji": "🗡️", "boss": false}, {"name": "Custodi delle Uova", "emoji": "🛡️", "boss": false}, {"name": "Baby Drago Infuocato", "emoji": "🔥", "boss": true}]'::jsonb, 7, 5, 310, 204),
 (5, 'Torre del Mago Oscuro', '🧙', 'Una torre di libri, specchi e incantesimi: il primo vero esame di magia.', 'Mago Nero', '🔮', 'Il maestro delle arti oscure, fedele al suo bastone.', '[{"name": "Apprendisti Stregoni", "emoji": "🗡️", "boss": false}, {"name": "Specchi Incantati", "emoji": "🛡️", "boss": false}, {"name": "Servitori Arcani", "emoji": "🔥", "boss": false}, {"name": "Mago Nero", "emoji": "🔮", "boss": true}]'::jsonb, 10, 8, 380, 240),
 (6, 'Miniere dei Golem', '⛏️', 'Gallerie di cristallo dove le rocce camminano e non amano i visitatori.', 'Golem di Cristallo', '💎', 'Un gigante scintillante, duro come il diamante.', '[{"name": "Golem di Roccia", "emoji": "🛡️", "boss": false}, {"name": "Pipistrelli di Gemma", "emoji": "🔥", "boss": false}, {"name": "Minatori Pietrificati", "emoji": "⚡", "boss": false}, {"name": "Golem di Roccia (guardia)", "emoji": "💀", "boss": false}, {"name": "Golem di Cristallo", "emoji": "💎", "boss": true}]'::jsonb, 13, 11, 460, 276),
 (7, 'Biblioteca Proibita', '📚', 'Scaffali infiniti di tomi sigillati: leggerne uno costa caro.', 'Custode dei Sigilli', '📜', 'Colui che sorveglia ciò che non deve essere letto.', '[{"name": "Libri Viventi", "emoji": "🔥", "boss": false}, {"name": "Spettri dell''Archivio", "emoji": "⚡", "boss": false}, {"name": "Bibliotecari Senza Volto", "emoji": "💀", "boss": false}, {"name": "Libri Viventi (guardia)", "emoji": "🗡️", "boss": false}, {"name": "Custode dei Sigilli", "emoji": "📜", "boss": true}]'::jsonb, 16, 14, 540, 312),
 (8, 'Cimitero dei Duellanti', '🪦', 'Qui riposano i duellanti dimenticati. Non tutti riposano in pace.', 'Spirito del Duellante Caduto', '👻', 'L''ultimo campione sconfitto, che cerca ancora la sua rivincita.', '[{"name": "Ombre di Duellanti", "emoji": "⚡", "boss": false}, {"name": "Lapidi Animate", "emoji": "💀", "boss": false}, {"name": "Becchini Spettrali", "emoji": "🗡️", "boss": false}, {"name": "Ombre di Duellanti (guardia)", "emoji": "🛡️", "boss": false}, {"name": "Spirito del Duellante Caduto", "emoji": "👻", "boss": true}]'::jsonb, 19, 17, 620, 348),
 (9, 'Officina Cyber', '🤖', 'Un laboratorio dove le macchine hanno imparato a duellare da sole.', 'Cyber Drago', '🤖', 'Un drago di metallo che ricalcola ogni tua mossa.', '[{"name": "Droni da Combattimento", "emoji": "💀", "boss": false}, {"name": "Cyber Sentinelle", "emoji": "🗡️", "boss": false}, {"name": "Bracci Meccanici", "emoji": "🛡️", "boss": false}, {"name": "Droni da Combattimento (guardia)", "emoji": "🔥", "boss": false}, {"name": "Cyber Drago", "emoji": "🤖", "boss": true}]'::jsonb, 22, 20, 710, 384),
 (10, 'Tempio di Anubi', '🏺', 'Corridoi di sabbia e geroglifici: la giustizia del deserto è senza pietà.', 'Faraone Oscuro', '👑', 'Il sovrano del tempio, giudice di ogni duello.', '[{"name": "Scarabei d''Oro", "emoji": "🗡️", "boss": false}, {"name": "Guardie di Anubi", "emoji": "🛡️", "boss": false}, {"name": "Sacerdoti Mummificati", "emoji": "🔥", "boss": false}, {"name": "Scarabei d''Oro (guardia)", "emoji": "⚡", "boss": false}, {"name": "Faraone Oscuro", "emoji": "👑", "boss": true}]'::jsonb, 26, 24, 810, 432),
 (11, 'Isola dei Dinosauri', '🦖', 'Una giungla preistorica dove ogni passo fa tremare la terra.', 'Re Tirannosauro', '🦖', 'Il predatore supremo dell''isola.', '[{"name": "Raptor Veloci", "emoji": "🛡️", "boss": false}, {"name": "Triceratopi Corazzati", "emoji": "🔥", "boss": false}, {"name": "Pterodattili d''Assalto", "emoji": "⚡", "boss": false}, {"name": "Raptor Veloci (guardia)", "emoji": "💀", "boss": false}, {"name": "Re Tirannosauro", "emoji": "🦖", "boss": true}]'::jsonb, 30, 28, 900, 480),
 (12, 'Abisso dei Mari', '🌊', 'Sul fondo dell''oceano, dove la luce non arriva, vivono mostri antichissimi.', 'Leviatano degli Abissi', '🐙', 'Una piovra immensa, che stritola le navi come giocattoli.', '[{"name": "Murene Elettriche", "emoji": "🔥", "boss": false}, {"name": "Sirene Abissali", "emoji": "⚡", "boss": false}, {"name": "Granchi Corazzati", "emoji": "💀", "boss": false}, {"name": "Murene Elettriche (guardia)", "emoji": "🗡️", "boss": false}, {"name": "Leviatano degli Abissi", "emoji": "🐙", "boss": true}]'::jsonb, 34, 32, 1000, 528),
 (13, 'Cattedrale degli Angeli', '⛪', 'Vetrate luminose e cori celesti: la bellezza nasconde una dura prova.', 'Arcangelo Caduto', '😇', 'Un angelo che ha perso le ali, ma non la sua forza.', '[{"name": "Cherubini Armati", "emoji": "⚡", "boss": false}, {"name": "Sentinelle d''Alabastro", "emoji": "💀", "boss": false}, {"name": "Cantori Radiosi", "emoji": "🗡️", "boss": false}, {"name": "Cherubini Armati (guardia)", "emoji": "🛡️", "boss": false}, {"name": "Arcangelo Caduto", "emoji": "😇", "boss": true}]'::jsonb, 38, 36, 1100, 576),
 (14, 'Vulcano dell''Inferno', '🌋', 'Fiumi di lava e roccia rovente: si combatte in un forno.', 'Signore delle Fiamme', '🔥', 'Un demone di fuoco che si nutre del calore del vulcano.', '[{"name": "Salamandre di Lava", "emoji": "💀", "boss": false}, {"name": "Imp Ardenti", "emoji": "🗡️", "boss": false}, {"name": "Colossi di Magma", "emoji": "🛡️", "boss": false}, {"name": "Salamandre di Lava (guardia)", "emoji": "🔥", "boss": false}, {"name": "Signore delle Fiamme", "emoji": "🔥", "boss": true}]'::jsonb, 42, 40, 1210, 624),
 (15, 'Labirinto delle Ombre', '🌀', 'Un dedalo di corridoi che cambiano forma: chi si perde, non torna.', 'Drago Nero Occhi Rossi', '🐲', 'Un drago leggendario dallo sguardo di brace.', '[{"name": "Ombre Mutevoli", "emoji": "🗡️", "boss": false}, {"name": "Minotauri Neri", "emoji": "🛡️", "boss": false}, {"name": "Echi del Labirinto", "emoji": "🔥", "boss": false}, {"name": "Ombre Mutevoli (guardia)", "emoji": "⚡", "boss": false}, {"name": "Drago Nero Occhi Rossi", "emoji": "🐲", "boss": true}]'::jsonb, 47, 45, 1320, 684),
 (16, 'Fortezza dei Cavalieri', '🏰', 'Mura altissime e armature scintillanti: l''onore si paga con il sangue.', 'Cavaliere Lucente Nero', '⚫', 'Un guerriero di rara potenza, avvolto in un''armatura nera e brillante.', '[{"name": "Cavalieri d''Acciaio", "emoji": "🛡️", "boss": false}, {"name": "Balestrieri Reali", "emoji": "🔥", "boss": false}, {"name": "Paladini Oscuri", "emoji": "⚡", "boss": false}, {"name": "Cavalieri d''Acciaio (guardia)", "emoji": "💀", "boss": false}, {"name": "Balestrieri Reali (guardia)", "emoji": "🗡️", "boss": false}, {"name": "Cavaliere Lucente Nero", "emoji": "⚫", "boss": true}]'::jsonb, 52, 50, 1430, 744),
 (17, 'Giardino Maledetto', '🥀', 'Rose bellissime, spine mortali: il giardino non perdona i distratti.', 'Regina delle Spine', '🌹', 'La signora del giardino, elegante e spietata.', '[{"name": "Rampicanti Strangolatori", "emoji": "🔥", "boss": false}, {"name": "Fate Velenose", "emoji": "⚡", "boss": false}, {"name": "Girasoli Ghignanti", "emoji": "💀", "boss": false}, {"name": "Rampicanti Strangolatori (guardia)", "emoji": "🗡️", "boss": false}, {"name": "Fate Velenose (guardia)", "emoji": "🛡️", "boss": false}, {"name": "Regina delle Spine", "emoji": "🌹", "boss": true}]'::jsonb, 57, 55, 1540, 804),
 (18, 'Ghiacciaio Eterno', '🧊', 'Un deserto di ghiaccio dove il freddo ferma anche il respiro.', 'Drago del Ghiaccio Eterno', '❄️', 'Un drago che congela tutto ciò che guarda.', '[{"name": "Lupi di Brina", "emoji": "⚡", "boss": false}, {"name": "Giganti di Neve", "emoji": "💀", "boss": false}, {"name": "Spettri Gelati", "emoji": "🗡️", "boss": false}, {"name": "Lupi di Brina (guardia)", "emoji": "🛡️", "boss": false}, {"name": "Giganti di Neve (guardia)", "emoji": "🔥", "boss": false}, {"name": "Drago del Ghiaccio Eterno", "emoji": "❄️", "boss": true}]'::jsonb, 62, 60, 1650, 864),
 (19, 'Cielo delle Tempeste', '⛈️', 'Un arcipelago di nuvole nere, tra fulmini e vento.', 'Signore del Fulmine', '⚡', 'Un re del cielo che scaglia saette a comando.', '[{"name": "Falchi della Tempesta", "emoji": "💀", "boss": false}, {"name": "Elementali del Vento", "emoji": "🗡️", "boss": false}, {"name": "Arpie Folgoranti", "emoji": "🛡️", "boss": false}, {"name": "Falchi della Tempesta (guardia)", "emoji": "🔥", "boss": false}, {"name": "Elementali del Vento (guardia)", "emoji": "⚡", "boss": false}, {"name": "Signore del Fulmine", "emoji": "⚡", "boss": true}]'::jsonb, 68, 66, 1770, 936),
 (20, 'Santuario di Exodia', '🗝️', 'Cinque sigilli, cinque custodi: chi li riunisce risveglia il Proibito.', 'Exodia il Proibito', '🖐️', 'La leggenda che nessun duellante vorrebbe mai vedere in campo.', '[{"name": "Sigilli Viventi", "emoji": "🗡️", "boss": false}, {"name": "Guardiani Spezzati", "emoji": "🛡️", "boss": false}, {"name": "Catene Animate", "emoji": "🔥", "boss": false}, {"name": "Sigilli Viventi (guardia)", "emoji": "⚡", "boss": false}, {"name": "Guardiani Spezzati (guardia)", "emoji": "💀", "boss": false}, {"name": "Exodia il Proibito", "emoji": "🖐️", "boss": true}]'::jsonb, 74, 72, 1880, 1008),
 (21, 'Piramide di Slifer', '🔺', 'Nel cuore della piramide rossa si agita una tempesta divina.', 'Slifer il Drago del Cielo', '🐉', 'Un dio-drago che squarcia i cieli con il suo ruggito.', '[{"name": "Sacerdoti del Tuono", "emoji": "🛡️", "boss": false}, {"name": "Serpenti Rossi", "emoji": "🔥", "boss": false}, {"name": "Custodi della Tempesta", "emoji": "⚡", "boss": false}, {"name": "Sacerdoti del Tuono (guardia)", "emoji": "💀", "boss": false}, {"name": "Serpenti Rossi (guardia)", "emoji": "🗡️", "boss": false}, {"name": "Slifer il Drago del Cielo", "emoji": "🐉", "boss": true}]'::jsonb, 80, 78, 2000, 1080),
 (22, 'Piramide di Obelisk', '🗿', 'Nel cuore della piramide blu, la pietra stessa prende vita.', 'Obelisk il Tormentatore', '🗿', 'Un colosso divino, i cui pugni scuotono la terra.', '[{"name": "Statue Viventi", "emoji": "🔥", "boss": false}, {"name": "Sacerdoti di Pietra", "emoji": "⚡", "boss": false}, {"name": "Sentinelle Blu", "emoji": "💀", "boss": false}, {"name": "Statue Viventi (guardia)", "emoji": "🗡️", "boss": false}, {"name": "Sacerdoti di Pietra (guardia)", "emoji": "🛡️", "boss": false}, {"name": "Obelisk il Tormentatore", "emoji": "🗿", "boss": true}]'::jsonb, 87, 85, 2130, 1164),
 (23, 'Piramide di Ra', '☀️', 'Nel cuore della piramide d''oro, il sole non tramonta mai.', 'Il Drago Alato di Ra', '☀️', 'Il dio del sole in persona, avvolto di fiamme dorate.', '[{"name": "Guardiani Solari", "emoji": "⚡", "boss": false}, {"name": "Fenici d''Oro", "emoji": "💀", "boss": false}, {"name": "Sacerdoti del Sole", "emoji": "🗡️", "boss": false}, {"name": "Guardiani Solari (guardia)", "emoji": "🛡️", "boss": false}, {"name": "Fenici d''Oro (guardia)", "emoji": "🔥", "boss": false}, {"name": "Il Drago Alato di Ra", "emoji": "☀️", "boss": true}]'::jsonb, 94, 92, 2250, 1248),
 (24, 'Dimensione del Caos', '🌌', 'Fuori dallo spazio e dal tempo, dove le regole non valgono più.', 'Mago del Caos', '🌠', 'Un mago che piega la realtà alla sua volontà.', '[{"name": "Frammenti di Caos", "emoji": "💀", "boss": false}, {"name": "Ombre Dimensionali", "emoji": "🗡️", "boss": false}, {"name": "Cavalieri del Vuoto", "emoji": "🛡️", "boss": false}, {"name": "Frammenti di Caos (guardia)", "emoji": "🔥", "boss": false}, {"name": "Ombre Dimensionali (guardia)", "emoji": "⚡", "boss": false}, {"name": "Mago del Caos", "emoji": "🌠", "boss": true}]'::jsonb, 102, 100, 2370, 1344),
 (25, 'Il Trono dei Giochi Ombra', '👁️', 'L''ultimo luogo, dove si decide chi è davvero il più grande duellante.', 'Drago Ultimate Occhi Blu', '🐉', 'Tre teste, un solo ruggito: il drago più temuto di tutti i tempi.', '[{"name": "Custodi dell''Ombra", "emoji": "🗡️", "boss": false}, {"name": "Duellanti del Vuoto", "emoji": "🛡️", "boss": false}, {"name": "Draghi Bianchi d''Ombra", "emoji": "🔥", "boss": false}, {"name": "Custodi dell''Ombra (guardia)", "emoji": "⚡", "boss": false}, {"name": "Duellanti del Vuoto (guardia)", "emoji": "💀", "boss": false}, {"name": "Drago Ultimate Occhi Blu", "emoji": "🐉", "boss": true}]'::jsonb, 110, 108, 2500, 1440)
on conflict (no) do update set name = excluded.name, emoji = excluded.emoji, lore = excluded.lore, boss_name = excluded.boss_name, boss_emoji = excluded.boss_emoji, boss_lore = excluded.boss_lore,
  rooms = excluded.rooms, ref_level = excluded.ref_level, min_level = excluded.min_level, bc = excluded.bc, xp = excluded.xp;
insert into public.game_items (id, name, slot, tier, rarity, min_level, p_for, p_des, p_vig, p_spi, p_frt, xp_pct, extra_actions, descr, source, dungeon_no) values
 ('d01', 'Lama di Kuriboh Anziano', 'weapon', 0, 'comune', 1, 5, 2, 0, 0, 0, 0, 0, 'Bottino del dungeon «Foresta dei Kuriboh».', 'dungeon', 1),
 ('d02', 'Corazza di Re Zombi', 'armor', 0, 'comune', 1, 0, 0, 7, 0, 3, 0, 0, 'Bottino del dungeon «Palude degli Zombi».', 'dungeon', 2),
 ('d03', 'Elmo di Guardiano Celtico Corrotto', 'helm', 0, 'comune', 3, 0, 0, 4, 9, 0, 0, 0, 'Bottino del dungeon «Rovine dei Guerrieri».', 'dungeon', 3),
 ('d04', 'Amuleto di Baby Drago Infuocato', 'amulet', 0, 'non_comune', 5, 0, 5, 0, 0, 11, 0, 0, 'Bottino del dungeon «Grotta dei Draghetti».', 'dungeon', 4),
 ('d05', 'Reliquia di Mago Nero', 'tool', 0, 'epico', 8, 0, 14, 0, 7, 0, 2, 0, 'Bottino del dungeon «Torre del Mago Oscuro».', 'dungeon', 5),
 ('d06', 'Lama di Golem di Cristallo', 'weapon', 0, 'non_comune', 11, 16, 8, 0, 0, 0, 0, 0, 'Bottino del dungeon «Miniere dei Golem».', 'dungeon', 6),
 ('d07', 'Corazza di Custode dei Sigilli', 'armor', 0, 'non_comune', 14, 0, 0, 18, 0, 9, 0, 0, 'Bottino del dungeon «Biblioteca Proibita».', 'dungeon', 7),
 ('d08', 'Elmo di Spirito del Duellante Caduto', 'helm', 0, 'non_comune', 17, 0, 0, 10, 20, 0, 0, 0, 'Bottino del dungeon «Cimitero dei Duellanti».', 'dungeon', 8),
 ('d09', 'Amuleto di Cyber Drago', 'amulet', 0, 'non_comune', 20, 0, 11, 0, 0, 22, 0, 0, 'Bottino del dungeon «Officina Cyber».', 'dungeon', 9),
 ('d10', 'Reliquia di Faraone Oscuro', 'tool', 0, 'epico', 24, 0, 24, 0, 12, 0, 4, 0, 'Bottino del dungeon «Tempio di Anubi».', 'dungeon', 10),
 ('d11', 'Lama di Re Tirannosauro', 'weapon', 0, 'raro', 28, 26, 13, 0, 0, 0, 0, 0, 'Bottino del dungeon «Isola dei Dinosauri».', 'dungeon', 11),
 ('d12', 'Corazza di Leviatano degli Abissi', 'armor', 0, 'raro', 32, 0, 0, 28, 0, 14, 0, 0, 'Bottino del dungeon «Abisso dei Mari».', 'dungeon', 12),
 ('d13', 'Elmo di Arcangelo Caduto', 'helm', 0, 'raro', 36, 0, 0, 15, 30, 0, 0, 0, 'Bottino del dungeon «Cattedrale degli Angeli».', 'dungeon', 13),
 ('d14', 'Amuleto di Signore delle Fiamme', 'amulet', 0, 'raro', 40, 0, 16, 0, 0, 32, 0, 0, 'Bottino del dungeon «Vulcano dell''Inferno».', 'dungeon', 14),
 ('d15', 'Reliquia di Drago Nero Occhi Rossi', 'tool', 0, 'epico', 45, 0, 34, 0, 17, 0, 5, 0, 'Bottino del dungeon «Labirinto delle Ombre».', 'dungeon', 15),
 ('d16', 'Lama di Cavaliere Lucente Nero', 'weapon', 0, 'raro', 50, 37, 18, 0, 0, 0, 0, 0, 'Bottino del dungeon «Fortezza dei Cavalieri».', 'dungeon', 16),
 ('d17', 'Corazza di Regina delle Spine', 'armor', 0, 'raro', 55, 0, 0, 39, 0, 19, 0, 0, 'Bottino del dungeon «Giardino Maledetto».', 'dungeon', 17),
 ('d18', 'Elmo di Drago del Ghiaccio Eterno', 'helm', 0, 'raro', 60, 0, 0, 20, 41, 0, 0, 0, 'Bottino del dungeon «Ghiacciaio Eterno».', 'dungeon', 18),
 ('d19', 'Amuleto di Signore del Fulmine', 'amulet', 0, 'raro', 66, 0, 21, 0, 0, 43, 0, 0, 'Bottino del dungeon «Cielo delle Tempeste».', 'dungeon', 19),
 ('d20', 'Reliquia di Exodia il Proibito', 'tool', 0, 'epico', 72, 0, 45, 0, 22, 0, 7, 0, 'Bottino del dungeon «Santuario di Exodia».', 'dungeon', 20),
 ('d21', 'Lama di Slifer il Drago del Cielo', 'weapon', 0, 'raro', 78, 47, 23, 0, 0, 0, 0, 0, 'Bottino del dungeon «Piramide di Slifer».', 'dungeon', 21),
 ('d22', 'Corazza di Obelisk il Tormentatore', 'armor', 0, 'raro', 85, 0, 0, 49, 0, 24, 0, 0, 'Bottino del dungeon «Piramide di Obelisk».', 'dungeon', 22),
 ('d23', 'Elmo di Il Drago Alato di Ra', 'helm', 0, 'raro', 92, 0, 0, 25, 51, 0, 0, 0, 'Bottino del dungeon «Piramide di Ra».', 'dungeon', 23),
 ('d24', 'Amuleto di Mago del Caos', 'amulet', 0, 'raro', 100, 0, 26, 0, 0, 53, 0, 0, 'Bottino del dungeon «Dimensione del Caos».', 'dungeon', 24),
 ('d25', 'Reliquia di Drago Ultimate Occhi Blu', 'tool', 0, 'epico', 108, 0, 56, 0, 28, 0, 9, 0, 'Bottino del dungeon «Il Trono dei Giochi Ombra».', 'dungeon', 25)
on conflict (id) do update set name = excluded.name, slot = excluded.slot, rarity = excluded.rarity, min_level = excluded.min_level, p_for = excluded.p_for, p_des = excluded.p_des, p_vig = excluded.p_vig,
  p_spi = excluded.p_spi, p_frt = excluded.p_frt, xp_pct = excluded.xp_pct, descr = excluded.descr;
update public.game_dungeons d set item_id = 'd' || lpad(d.no::text, 2, '0');

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'game_runs_nodel') then
    create trigger game_runs_nodel before delete on public.game_runs for each row execute function public._no_delete();
    create trigger game_dungeon_progress_nodel before delete on public.game_dungeon_progress for each row execute function public._no_delete();
  end if;
end $$;

-- ---------- funzioni interne ----------
create or replace function public._game_dng_cost() returns integer language sql stable as $$ select greatest(1, public._setting('game_dng_energy')) $$;

-- un dungeon è aperto se è il primo o se si è già completato il precedente
create or replace function public._game_dng_open(p_user uuid, p_no integer) returns boolean language sql stable security definer set search_path = public as $$
  select p_no = 1 or exists (select 1 from public.game_dungeon_progress where user_id = p_user and dungeon_no = p_no - 1 and clears > 0) $$;

create or replace function public._game_dng_expire() returns void language sql security definer set search_path = public as $$
  update public.game_runs set status = 'cancelled', finished_at = now()
   where status = 'lobby' and created_at < now() - make_interval(mins => greatest(1, public._setting('game_dng_lobby_minutes'))) $$;

create or replace function public._game_dng_run_json(p_run uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('run_id', r.id, 'dungeon_no', r.dungeon_no, 'leader_id', r.leader_id, 'status', r.status, 'created_at', r.created_at,
    'expires_at', r.created_at + make_interval(mins => greatest(1, public._setting('game_dng_lobby_minutes'))),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'nickname', p.nickname, 'avatar', p.avatar, 'role', m.role, 'level', h.level) order by m.joined_at, m.user_id)
                         from public.game_run_members m join public.profiles p on p.id = m.user_id join public.game_heroes h on h.user_id = m.user_id where m.run_id = r.id), '[]'::jsonb))
  from public.game_runs r where r.id = p_run $$;

-- oggetto casuale (non esclusivo) per un giocatore: comune, non comune o raro, più raro andando avanti coi dungeon
create or replace function public._game_dng_pool_item(p_user uuid, p_no integer) returns text language plpgsql security definer set search_path = public as $$
declare v_tot numeric; v_r numeric; v_id text;
begin
  select coalesce(sum(c.w), 0) into v_tot from (
    select (case i.rarity when 'comune' then greatest(0, 60 - 6 * p_no) when 'non_comune' then 30 else least(70, 4 * p_no) end) as w
      from public.game_items i, (select level from public.game_heroes where user_id = p_user) h
     where i.source = 'shop' and i.rarity in ('comune','non_comune','raro') and i.min_level <= h.level + 8
       and not exists (select 1 from public.game_inventory g where g.user_id = p_user and g.item_id = i.id)) c;
  if v_tot <= 0 then return null; end if;
  v_r := random() * v_tot;
  select x.id into v_id from (
    select c.id, sum(c.w) over (order by c.id) as cum from (
      select i.id, (case i.rarity when 'comune' then greatest(0, 60 - 6 * p_no) when 'non_comune' then 30 else least(70, 4 * p_no) end) as w
        from public.game_items i, (select level from public.game_heroes where user_id = p_user) h
       where i.source = 'shop' and i.rarity in ('comune','non_comune','raro') and i.min_level <= h.level + 8
         and not exists (select 1 from public.game_inventory g where g.user_id = p_user and g.item_id = i.id)) c where c.w > 0) x
   where x.cum >= v_r order by x.cum limit 1;
  return v_id;
end $$;

-- simulazione: il gruppo attraversa le stanze una dopo l'altra. Ruoli: Tank (più PV, attira i colpi, subisce meno), Danni (colpisce forte),
-- Supporto (cura l'alleato più ferito ogni round). Tra una stanza e l'altra il gruppo si riposa (+25% PV, chi era KO torna con il 25%).
create or replace function public._game_dng_sim(p_members jsonb, p_no integer) returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare d public.game_dungeons%rowtype; n integer := jsonb_array_length(p_members); nr integer;
  nm text[]; rl text[]; ids text[]; hp numeric[]; mx numeric[]; sf numeric[]; sd numeric[]; ss numeric[]; sr numeric[]; lv numeric[];
  dealt numeric[]; taken numeric[]; healed numeric[];
  j integer; k integer; r integer; rounds integer; alive integer; tgt integer; pick integer; tank integer; heal_t integer; atk_n integer;
  ref_p numeric; ref_for numeric; ref_hp numeric; diff numeric; hits numeric; apct numeric; e_hp numeric; e_max numeric; e_atk numeric; dmg numeric; best numeric; amt numeric; crit boolean;
  rooms jsonb := '[]'::jsonb; mem jsonb; win boolean := true; cleared integer := 0; ok boolean; rm jsonb;
begin
  select * into d from public.game_dungeons where no = p_no;
  if not found then raise exception 'Dungeon inesistente'; end if;
  nr := jsonb_array_length(d.rooms);
  for j in 1..n loop
    nm[j] := p_members->(j-1)->>'nickname'; rl[j] := p_members->(j-1)->>'role'; ids[j] := p_members->(j-1)->>'user_id';
    mx[j] := (p_members->(j-1)->>'max_hp')::numeric * case rl[j] when 'tank' then 1.3 else 1 end; hp[j] := mx[j];
    sf[j] := (p_members->(j-1)->>'s_for')::numeric; sd[j] := (p_members->(j-1)->>'s_des')::numeric; ss[j] := (p_members->(j-1)->>'s_spi')::numeric; sr[j] := (p_members->(j-1)->>'s_frt')::numeric;
    lv[j] := (p_members->(j-1)->>'level')::numeric;
  end loop;
  -- eroe di riferimento al livello consigliato (40% dei punti in Forza, 30% in Vigore)
  ref_p := 20 + 3 * (d.ref_level - 1);
  ref_for := 5 + 0.4 * ref_p * d.ref_level;
  ref_hp := 50 + 12 * (5 + 0.3 * ref_p * d.ref_level);
  diff := d.diff * (0.8 + 0.55 * (1 - exp(-(d.ref_level - 1) / 25.0))) * greatest(10, public._setting('game_dng_difficulty')) / 100.0;
  for r in 1..nr loop
    hits := case when r = nr then 18 else 5 + 0.8 * (r - 1) end;
    apct := case when r = nr then 0.115 else 0.045 + 0.006 * (r - 1) end;
    e_max := hits * 3 * ref_for * (1 + 1.3 * (n - 1)) * diff; e_hp := e_max;
    e_atk := ref_hp * apct * diff;
    for j in 1..n loop dealt[j] := 0; taken[j] := 0; healed[j] := 0; end loop;
    rounds := 0;
    loop
      rounds := rounds + 1;
      exit when rounds > 60;
      for j in 1..n loop
        if hp[j] > 0 then
          crit := random() < least(0.6, 0.05 + 0.4 * sd[j] / (5 + 10 * lv[j]));
          dmg := sf[j] * 3 * (0.85 + 0.3 * random()) * (case when crit then 1.6 else 1 end) * (case rl[j] when 'dps' then 1.4 when 'tank' then 0.7 else 0.5 end);
          e_hp := e_hp - dmg; dealt[j] := dealt[j] + dmg;
          if rl[j] = 'support' then
            heal_t := null; best := 2;
            for k in 1..n loop if hp[k] > 0 and hp[k] / mx[k] < best then best := hp[k] / mx[k]; heal_t := k; end if; end loop;
            if heal_t is not null and best < 1 then
              amt := least(mx[heal_t] - hp[heal_t], ss[j] * 1.0 * (0.9 + 0.2 * random()));
              hp[heal_t] := hp[heal_t] + amt; healed[j] := healed[j] + amt;
            end if;
          end if;
        end if;
      end loop;
      exit when e_hp <= 0;
      atk_n := n;
      for k in 1..atk_n loop
        alive := 0; tank := null;
        for j in 1..n loop if hp[j] > 0 then alive := alive + 1; if rl[j] = 'tank' then tank := j; end if; end if; end loop;
        exit when alive = 0;
        if tank is not null and random() < 0.6 then tgt := tank;
        else
          pick := 1 + floor(random() * alive)::integer; tgt := null;
          for j in 1..n loop if hp[j] > 0 then pick := pick - 1; if pick = 0 then tgt := j; exit; end if; end if; end loop;
        end if;
        if not (random() < least(0.5, 0.03 + 0.35 * sr[tgt] / (5 + 10 * lv[tgt]))) then
          dmg := e_atk * (0.9 + 0.2 * random()) * case when rl[tgt] = 'tank' then 0.7 else 1 end;
          hp[tgt] := greatest(0, hp[tgt] - dmg); taken[tgt] := taken[tgt] + dmg;
        end if;
      end loop;
      ok := false; for j in 1..n loop if hp[j] > 0 then ok := true; end if; end loop;
      exit when not ok;
    end loop;
    mem := '[]'::jsonb;
    for j in 1..n loop
      mem := mem || jsonb_build_array(jsonb_build_object('user_id', ids[j], 'nickname', nm[j], 'role', rl[j], 'dealt', round(dealt[j]), 'taken', round(taken[j]), 'healed', round(healed[j]), 'hp', round(hp[j]), 'max_hp', round(mx[j]), 'ko', hp[j] <= 0));
    end loop;
    rm := d.rooms->(r-1);
    rooms := rooms || jsonb_build_array(jsonb_build_object('no', r, 'name', rm->>'name', 'emoji', rm->>'emoji', 'boss', r = nr, 'cleared', e_hp <= 0, 'rounds', rounds, 'enemy_hp', round(e_max), 'members', mem));
    if e_hp <= 0 then
      cleared := cleared + 1;
      for j in 1..n loop hp[j] := case when hp[j] <= 0 then 0.25 * mx[j] else least(mx[j], hp[j] + 0.25 * mx[j]) end; end loop;
    else
      win := false; exit;
    end if;
  end loop;
  return jsonb_build_object('win', win, 'rooms', rooms, 'rooms_cleared', cleared, 'rooms_total', nr);
end $$;

-- ---------- stato ----------
create or replace function public.game_dungeon_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); h public.game_heroes%rowtype; my uuid; cleared integer; en numeric;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  perform public._game_dng_expire();
  select * into h from public.game_heroes where user_id = v;
  select m.run_id into my from public.game_run_members m join public.game_runs r on r.id = m.run_id where m.user_id = v and r.status = 'lobby' limit 1;
  select count(*) into cleared from public.game_dungeon_progress where user_id = v and clears > 0;
  en := public._game_energy_of(v);
  return jsonb_build_object(
    'cost', public._game_dng_cost(), 'max_party', public._setting('game_dng_max_party'), 'energy', round(en, 2),
    'replay_bc_pct', public._setting('game_dng_replay_bc_pct'), 'replay_xp_pct', public._setting('game_dng_replay_xp_pct'), 'party_bonus_pct', public._setting('game_dng_party_bonus_pct'),
    'lobby_minutes', public._setting('game_dng_lobby_minutes'),
    'cleared', cleared, 'total', (select count(*) from public.game_dungeons),
    'next_epic_in', case when cleared >= 25 then 0 else 5 - (cleared % 5) end,
    'dungeons', coalesce((select jsonb_agg(jsonb_build_object('no', d.no, 'name', d.name, 'emoji', d.emoji, 'lore', d.lore, 'boss_name', d.boss_name, 'boss_emoji', d.boss_emoji, 'boss_lore', d.boss_lore,
        'rooms', d.rooms, 'ref_level', d.ref_level, 'min_level', d.min_level, 'bc', d.bc, 'xp', d.xp,
        'open', public._game_dng_open(v, d.no::integer), 'level_ok', h.level >= d.min_level, 'clears', coalesce(p.clears, 0),
        'item', (select jsonb_build_object('id', i.id, 'name', i.name, 'slot', i.slot, 'rarity', i.rarity, 'min_level', i.min_level, 'p_for', i.p_for, 'p_des', i.p_des, 'p_vig', i.p_vig, 'p_spi', i.p_spi, 'p_frt', i.p_frt, 'xp_pct', i.xp_pct, 'extra_actions', i.extra_actions, 'extra_fights', i.extra_fights,
                    'owned', exists (select 1 from public.game_inventory g where g.user_id = v and g.item_id = i.id)) from public.game_items i where i.id = d.item_id)) order by d.no)
        from public.game_dungeons d left join public.game_dungeon_progress p on p.user_id = v and p.dungeon_no = d.no), '[]'::jsonb),
    'lobbies', coalesce((select jsonb_agg(public._game_dng_run_json(r.id) order by r.created_at desc) from public.game_runs r where r.status = 'lobby'), '[]'::jsonb),
    'my_run', case when my is null then null else public._game_dng_run_json(my) end,
    'last_result', (select jsonb_build_object('run_id', r.id, 'dungeon_no', r.dungeon_no, 'status', r.status, 'finished_at', r.finished_at, 'result', r.result)
                      from public.game_runs r join public.game_run_members m on m.run_id = r.id and m.user_id = v
                     where r.status in ('cleared','failed') and r.finished_at > now() - interval '1 day' order by r.finished_at desc limit 1));
end $$;

-- ---------- lobby ----------
-- controlli comuni per creare una lobby o entrare in una
create or replace function public._game_dng_check(p_user uuid, p_no integer, p_role text) returns void language plpgsql security definer set search_path = public as $$
declare h public.game_heroes%rowtype; d public.game_dungeons%rowtype;
begin
  if p_role is null or p_role not in ('tank','dps','support') then raise exception 'Scegli un ruolo: Tank, Danni o Supporto'; end if;
  select * into d from public.game_dungeons where no = p_no;
  if not found then raise exception 'Dungeon inesistente'; end if;
  select * into h from public.game_heroes where user_id = p_user;
  if not h.stats_set then raise exception 'Prima assegna i tuoi punti abilità'; end if;
  if not public._game_dng_open(p_user, p_no) then raise exception 'Dungeon bloccato: completa prima il precedente'; end if;
  if h.level < d.min_level then raise exception 'Serve il livello % per questo dungeon', d.min_level; end if;
  if public._game_energy_of(p_user) < public._game_dng_cost() then raise exception 'Energia insufficiente: per un dungeon ne servono % (ora %)', public._game_dng_cost(), floor(public._game_energy_of(p_user)); end if;
  if exists (select 1 from public.game_run_members m join public.game_runs r on r.id = m.run_id where m.user_id = p_user and r.status = 'lobby') then raise exception 'Sei già in una lobby: esci prima'; end if;
end $$;

create or replace function public.game_dungeon_create(p_dungeon integer, p_role text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); v_run uuid := gen_random_uuid();
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  perform 1 from public.game_heroes where user_id = v for update;
  perform public._game_dng_expire();
  perform public._game_dng_check(v, p_dungeon, p_role);
  insert into public.game_runs (id, dungeon_no, leader_id) values (v_run, p_dungeon, v);
  insert into public.game_run_members (run_id, user_id, role) values (v_run, v, p_role);
  return public._game_dng_run_json(v_run);
end $$;

create or replace function public.game_dungeon_join(p_run uuid, p_role text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); r public.game_runs%rowtype; n integer; v_max integer := greatest(1, public._setting('game_dng_max_party'));
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  perform 1 from public.game_heroes where user_id = v for update;
  perform public._game_dng_expire();
  select * into r from public.game_runs where id = p_run for update;
  if not found or r.status <> 'lobby' then raise exception 'Questa lobby non esiste più o è già partita'; end if;
  perform public._game_dng_check(v, r.dungeon_no::integer, p_role);
  select count(*) into n from public.game_run_members where run_id = p_run;
  if n >= v_max then raise exception 'La lobby è piena'; end if;
  if p_role = 'tank' and exists (select 1 from public.game_run_members where run_id = p_run and role = 'tank') then raise exception 'C’è già un Tank in questo gruppo'; end if;
  if p_role = 'support' and exists (select 1 from public.game_run_members where run_id = p_run and role = 'support') then raise exception 'C’è già un Supporto in questo gruppo'; end if;
  if p_role = 'dps' and (select count(*) from public.game_run_members where run_id = p_run and role = 'dps') >= greatest(1, v_max - 2) then raise exception 'Non c’è più posto per i Danni in questo gruppo'; end if;
  insert into public.game_run_members (run_id, user_id, role) values (p_run, v, p_role);
  return public._game_dng_run_json(p_run);
end $$;

create or replace function public.game_dungeon_role(p_run uuid, p_role text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); r public.game_runs%rowtype; v_max integer := greatest(1, public._setting('game_dng_max_party'));
begin
  perform public._require_module('heroes');
  if p_role is null or p_role not in ('tank','dps','support') then raise exception 'Scegli un ruolo: Tank, Danni o Supporto'; end if;
  select * into r from public.game_runs where id = p_run for update;
  if not found or r.status <> 'lobby' then raise exception 'Questa lobby non esiste più o è già partita'; end if;
  if not exists (select 1 from public.game_run_members where run_id = p_run and user_id = v) then raise exception 'Non sei in questa lobby'; end if;
  if p_role = 'tank' and exists (select 1 from public.game_run_members where run_id = p_run and role = 'tank' and user_id <> v) then raise exception 'C’è già un Tank in questo gruppo'; end if;
  if p_role = 'support' and exists (select 1 from public.game_run_members where run_id = p_run and role = 'support' and user_id <> v) then raise exception 'C’è già un Supporto in questo gruppo'; end if;
  if p_role = 'dps' and (select count(*) from public.game_run_members where run_id = p_run and role = 'dps' and user_id <> v) >= greatest(1, v_max - 2) then raise exception 'Non c’è più posto per i Danni in questo gruppo'; end if;
  update public.game_run_members set role = p_role where run_id = p_run and user_id = v;
  return public._game_dng_run_json(p_run);
end $$;

create or replace function public.game_dungeon_leave(p_run uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); r public.game_runs%rowtype; nxt uuid;
begin
  perform public._require_module('heroes');
  select * into r from public.game_runs where id = p_run for update;
  if not found or r.status <> 'lobby' then raise exception 'Questa lobby non esiste più o è già partita'; end if;
  if not exists (select 1 from public.game_run_members where run_id = p_run and user_id = v) then raise exception 'Non sei in questa lobby'; end if;
  delete from public.game_run_members where run_id = p_run and user_id = v;
  select user_id into nxt from public.game_run_members where run_id = p_run order by joined_at, user_id limit 1;
  if nxt is null then
    update public.game_runs set status = 'cancelled', finished_at = now() where id = p_run;
    return jsonb_build_object('closed', true);
  end if;
  if r.leader_id = v then update public.game_runs set leader_id = nxt where id = p_run; end if;
  return jsonb_build_object('closed', false, 'run', public._game_dng_run_json(p_run));
end $$;

-- ---------- partenza, scontro e premi ----------
create or replace function public.game_dungeon_start(p_run uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); r public.game_runs%rowtype; d public.game_dungeons%rowtype; m record; c record;
  v_cost integer := public._game_dng_cost(); n integer; mem jsonb := '[]'::jsonb; sim jsonb; win boolean; res jsonb; outm jsonb := '[]'::jsonb; dropped jsonb := '[]'::jsonb;
  pr public.game_dungeon_progress%rowtype; first_ boolean; v_bc integer; v_xp bigint; rw jsonb; its jsonb; v_it text; nm text; bonus numeric; v_cleared integer; milestone boolean;
  v_lvl integer;
begin
  perform public._require_module('heroes');
  select * into r from public.game_runs where id = p_run for update;
  if not found or r.status <> 'lobby' then raise exception 'Questa lobby non esiste più o è già partita'; end if;
  if r.leader_id <> v then raise exception 'Solo il capo della lobby può far partire il dungeon'; end if;
  perform public._game_dng_expire();
  if (select status from public.game_runs where id = p_run) <> 'lobby' then raise exception 'La lobby è scaduta: creane una nuova'; end if;
  select * into d from public.game_dungeons where no = r.dungeon_no;
  -- si blocca in ordine fisso e si tolgono (con avviso) i giocatori che non possono più partire
  for m in select gm.user_id, gm.role from public.game_run_members gm where gm.run_id = p_run order by gm.user_id loop perform 1 from public.game_heroes where user_id = m.user_id for update; end loop;
  for m in select gm.user_id, gm.role, p.nickname, p.suspended from public.game_run_members gm join public.profiles p on p.id = gm.user_id where gm.run_id = p_run order by gm.joined_at, gm.user_id loop
    if m.suspended or public._game_energy_of(m.user_id) < v_cost then
      if m.user_id = v then raise exception 'Energia insufficiente: per un dungeon ne servono % (ora %)', v_cost, floor(public._game_energy_of(v)); end if;
      delete from public.game_run_members where run_id = p_run and user_id = m.user_id;
      dropped := dropped || jsonb_build_array(m.nickname);
    end if;
  end loop;
  select count(*) into n from public.game_run_members where run_id = p_run;
  for m in select gm.user_id, gm.role, p.nickname from public.game_run_members gm join public.profiles p on p.id = gm.user_id where gm.run_id = p_run order by gm.joined_at, gm.user_id loop
    select * into c from public._game_calc(m.user_id);
    update public.game_heroes set energy = greatest(0, public._game_energy_of(m.user_id) - v_cost), energy_at = now(), last_active_at = now(), fights_total = fights_total + 1 where user_id = m.user_id;
    mem := mem || jsonb_build_array(jsonb_build_object('user_id', m.user_id, 'nickname', m.nickname, 'role', m.role, 'level', c.level, 'max_hp', c.max_hp,
                                                       's_for', c.s_for, 's_des', c.s_des, 's_spi', c.s_spi, 's_frt', c.s_frt));
  end loop;
  sim := public._game_dng_sim(mem, r.dungeon_no::integer);
  win := (sim->>'win')::boolean;
  bonus := 1 + public._setting('game_dng_party_bonus_pct') / 100.0 * (n - 1);
  for m in select gm.user_id, gm.role, p.nickname from public.game_run_members gm join public.profiles p on p.id = gm.user_id where gm.run_id = p_run order by gm.joined_at, gm.user_id loop
    its := '[]'::jsonb; v_bc := 0; milestone := false;
    if win then
      select * into pr from public.game_dungeon_progress where user_id = m.user_id and dungeon_no = d.no;
      first_ := not found or pr.clears = 0;
      v_bc := round(d.bc * bonus * case when first_ then 1 else public._setting('game_dng_replay_bc_pct') / 100.0 end)::integer;
      v_xp := round(d.xp * case when first_ then 1 else public._setting('game_dng_replay_xp_pct') / 100.0 end)::bigint;
      if first_ then
        if not exists (select 1 from public.game_inventory where user_id = m.user_id and item_id = d.item_id) then
          insert into public.game_inventory (user_id, item_id, source) values (m.user_id, d.item_id, 'dungeon');
          select jsonb_build_object('id', i.id, 'name', i.name, 'rarity', i.rarity, 'slot', i.slot, 'exclusive', true) into rw from public.game_items i where i.id = d.item_id;
          its := its || jsonb_build_array(rw);
        end if;
        if random() * 100 < public._setting('game_dng_drop_extra_pct') then v_it := public._game_dng_pool_item(m.user_id, d.no::integer); end if;
      else
        v_it := null;
        if random() * 100 < public._setting('game_dng_drop_replay_pct') then v_it := public._game_dng_pool_item(m.user_id, d.no::integer); end if;
      end if;
      if v_it is not null then
        insert into public.game_inventory (user_id, item_id, source) values (m.user_id, v_it, 'dungeon') on conflict do nothing;
        select jsonb_build_object('id', i.id, 'name', i.name, 'rarity', i.rarity, 'slot', i.slot, 'exclusive', false) into rw from public.game_items i where i.id = v_it;
        its := its || jsonb_build_array(rw);
      end if;
      v_it := null;
      if v_bc > 0 then
        perform public._ledger_move(m.user_id, v_bc, 'game_dungeon_reward', 'game_run', p_run, 'gamedng:' || p_run::text || ':' || m.user_id::text, 'La guerra degli Eroi: dungeon «' || d.name || '» completato');
      end if;
      insert into public.game_dungeon_progress (user_id, dungeon_no, clears, first_clear_at, last_clear_at) values (m.user_id, d.no, 1, now(), now())
        on conflict (user_id, dungeon_no) do update set clears = public.game_dungeon_progress.clears + 1, last_clear_at = now(),
                                                       first_clear_at = coalesce(public.game_dungeon_progress.first_clear_at, now());
      select count(*) into v_cleared from public.game_dungeon_progress where user_id = m.user_id and clears > 0;
      milestone := first_ and v_cleared % 5 = 0;
    else
      first_ := false; v_xp := round(d.xp * public._setting('game_dng_fail_xp_pct') / 100.0)::bigint;
    end if;
    rw := public._game_add_xp(m.user_id, v_xp);
    select level into v_lvl from public.game_heroes where user_id = m.user_id;
    outm := outm || jsonb_build_array(jsonb_build_object('user_id', m.user_id, 'nickname', m.nickname, 'role', m.role, 'first', first_, 'bc', v_bc, 'xp', (rw->>'xp')::bigint, 'levels', (rw->>'levels')::integer,
                                                        'level', v_lvl, 'items', its, 'milestone', milestone));
  end loop;
  res := jsonb_build_object('win', win, 'rooms', sim->'rooms', 'rooms_cleared', (sim->>'rooms_cleared')::integer, 'rooms_total', (sim->>'rooms_total')::integer,
                            'members', outm, 'dropped', dropped, 'party_bonus', round((bonus - 1) * 100), 'cost', v_cost);
  update public.game_runs set status = case when win then 'cleared' else 'failed' end, started_at = clock_timestamp(), finished_at = clock_timestamp(), result = res where id = p_run;
  return jsonb_build_object('run_id', p_run, 'dungeon_no', d.no, 'status', case when win then 'cleared' else 'failed' end, 'result', res);
end $$;

-- ---------- permessi ----------
do $$
declare t text;
begin
  foreach t in array array['game_dungeons','game_runs','game_run_members','game_dungeon_progress'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
  drop policy if exists game_dungeons_read on public.game_dungeons;
  create policy game_dungeons_read on public.game_dungeons for select to authenticated using (public._module_on('heroes') or public.is_admin());
  drop policy if exists game_dungeon_progress_read on public.game_dungeon_progress;
  create policy game_dungeon_progress_read on public.game_dungeon_progress for select to authenticated using (user_id = auth.uid() and (public._module_on('heroes') or public.is_admin()));
end $$;
revoke all on public.game_dungeons, public.game_runs, public.game_run_members, public.game_dungeon_progress from public, anon, authenticated;
grant select on public.game_dungeons, public.game_dungeon_progress to authenticated;
revoke all on function public._game_dng_cost(), public._game_dng_open(uuid, integer), public._game_dng_expire(), public._game_dng_run_json(uuid), public._game_dng_pool_item(uuid, integer),
                public._game_dng_sim(jsonb, integer), public._game_dng_check(uuid, integer, text) from public, anon, authenticated;
revoke all on function public.game_dungeon_state(), public.game_dungeon_create(integer, text), public.game_dungeon_join(uuid, text), public.game_dungeon_role(uuid, text),
                public.game_dungeon_leave(uuid), public.game_dungeon_start(uuid) from public, anon;
grant execute on function public.game_dungeon_state(), public.game_dungeon_create(integer, text), public.game_dungeon_join(uuid, text), public.game_dungeon_role(uuid, text),
                public.game_dungeon_leave(uuid), public.game_dungeon_start(uuid) to authenticated;
commit;
