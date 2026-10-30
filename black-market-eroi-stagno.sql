-- =====================================================================
-- MIGRAZIONE 031 — La guerra degli Eroi: LO STAGNO (pet companion)
--   Una scheda nuova, «Lo stagno», dove ogni eroe trova il suo compagno. 30 pet in tutto (sprite pixel art originali):
--   * 3 pet BASE gratuiti, uno per stile: Ranocchio Scintilla (Assalto), Tartaruga Muschio (Baluardo), Libellula Lucente (Saggezza).
--     Si sceglie UNO dei tre, una volta sola: da quel momento è il compagno dell'eroe.
--   * Altri 27 pet in vendita per BC, in 9 gradi di 3 pet (uno per stile): più è alto il grado, più il pet costa, più è forte (bonus più alti
--     e più numerosi) e più è bello da vedere. Si compra solo dopo aver scelto il pet base.
--       grado   prezzo (BC)   livello eroe richiesto
--         1        1.500            5
--         2        4.000           15
--         3        9.000           30
--         4       20.000           50
--         5       45.000           80
--         6       90.000          120
--         7      180.000          180
--         8      350.000          260
--         9      700.000          380
--   * Un solo pet alla volta è il compagno ATTIVO (si cambia quando si vuole, dallo Stagno): è lui che dà i bonus e che guadagna esperienza.
--     Gli altri pet restano nello Stagno con il loro livello, senza perderlo.
--   * ESPERIENZA: il pet attivo guadagna il 20% dell'XP che l'eroe ottiene (impostazione game_pet_xp_pct), ovunque l'eroe prenda XP
--     (Arena, boss, dungeon, Torre). La curva è la stessa dell'eroe, e un pet non supera mai il livello dell'eroe né il livello massimo (100).
--   * BONUS: ogni pet ha da 3 a 5 bonus (percentuali sulle statistiche, XP in più, a volte ricarica dell'energia più veloce o azioni boss).
--     Salendo di livello il pet SBLOCCA bonus nuovi (ai livelli 1, 10, 25, 45 e 70) e ogni bonus CRESCE: parte da un quarto del suo valore
--     massimo e lo raggiunge al livello 100. Tutti i bonus del pet attivo entrano nelle statistiche dell'eroe, in ogni combattimento.
--   * Il pet attivo compare sul cruscotto dell'eroe (nome, livello, barra dell'esperienza).
--   * Impostazioni (Admin › Impostazioni economiche): game_pet_xp_pct (20), game_pet_max_level (100).
--   * Nel registro BC compare un nuovo tipo di movimento: game_pet (acquisto di un pet).
--   * Si può rieseguire senza danni (catalogo aggiornato, pet e livelli già posseduti intatti).
--   * Annullamento: black-market-eroi-stagno-down.sql (restituisce i BC dei pet comprati, rimette le funzioni di prima).
-- Da eseguire in Supabase (SQL Editor) DOPO le migrazioni della guerra degli Eroi (anche dopo il pacchetto «unico» dei dungeon e la Torre, se già fatte).
-- Sostituisce quattro funzioni esistenti: _game_calc (statistiche), _game_hero_json (scheda eroe), _game_add_xp (XP) e le rende «consapevoli» dei pet.
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.game_heroes') is null or to_regprocedure('public._game_calc(uuid)') is null or to_regprocedure('public._game_add_xp(uuid,bigint)') is null
     or to_regprocedure('public._game_hero_json(uuid)') is null or to_regclass('public.game_skills') is null then
    raise exception 'Prima esegui le migrazioni della guerra degli Eroi (serve almeno la 023 con le abilità). Non è stato modificato nulla.';
  end if;
end $$;

-- ---------- nuovo tipo di movimento nel registro ----------
do $$
declare d text; kinds text[]; k text;
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.ledger_entries'::regclass and conname = 'ledger_entries_kind_check';
  if d is null then raise exception 'Vincolo ledger_entries_kind_check non trovato: la migrazione non può aggiornare i tipi di movimento'; end if;
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  foreach k in array array['game_pet'] loop
    if not (k = any (kinds)) then kinds := kinds || k; end if;
  end loop;
  alter table public.ledger_entries drop constraint ledger_entries_kind_check;
  execute 'alter table public.ledger_entries add constraint ledger_entries_kind_check check (kind in ('
    || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
end $$;

insert into public.system_settings (key, value_int, description) values
 ('game_pet_xp_pct',    20,  'Pet: percentuale dell''XP dell''eroe che va al pet attivo (0–100)'),
 ('game_pet_max_level', 100, 'Pet: livello massimo di un pet (i bonus raggiungono il valore pieno a questo livello)')
on conflict (key) do nothing;

-- ---------- tabelle (chiuse al browser) ----------
create table if not exists public.game_pets (
  id text primary key,
  no smallint not null unique check (no between 1 and 999),
  name text not null,
  family text not null,
  tier smallint not null check (tier between 0 and 9),
  variant text not null check (variant in ('a','b','c')),          -- a = Assalto, b = Baluardo, c = Saggezza
  sprite text not null,
  price_bc integer not null check (price_bc >= 0),
  min_level integer not null check (min_level >= 1),
  starter boolean not null default false,
  lore text,
  check ((starter and price_bc = 0) or (not starter and price_bc > 0))
);
create table if not exists public.game_pet_lines (
  pet_id text not null references public.game_pets(id) on delete cascade,
  pos smallint not null check (pos between 1 and 8),
  effect text not null check (effect in ('for','des','vig','spi','frt','xp','actions','fights')),
  max_value smallint not null check (max_value >= 1),
  unlock_level smallint not null check (unlock_level >= 1),
  primary key (pet_id, pos)
);
create table if not exists public.game_hero_pets (
  user_id uuid not null references public.profiles(id) on delete restrict,
  pet_id text not null references public.game_pets(id),
  level integer not null default 1 check (level >= 1),
  xp bigint not null default 0 check (xp >= 0),
  total_xp bigint not null default 0 check (total_xp >= 0),
  active boolean not null default false,
  acquired_at timestamptz not null default clock_timestamp(),
  primary key (user_id, pet_id)
);
create unique index if not exists game_hero_pets_one_active on public.game_hero_pets (user_id) where active;
do $$ declare t text; begin
  foreach t in array array['game_pets','game_pet_lines','game_hero_pets'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- ---------- catalogo ----------
insert into public.game_pets (id, no, name, family, tier, variant, sprite, price_bc, min_level, starter, lore) values
 ('pet_ranocchio', 1, 'Ranocchio Scintilla', 'Tuono', 0, 'a', 'ranocchio', 0, 1, true, 'Salta da una ninfea all’altra lasciando scintille: dicono porti fortuna ai duellanti.'),
 ('pet_tartaruga', 2, 'Tartaruga Muschio', 'Roccia', 0, 'b', 'tartaruga', 0, 1, true, 'Il suo guscio è così vecchio che ci è cresciuto sopra un piccolo giardino.'),
 ('pet_libellula', 3, 'Libellula Lucente', 'Insetto', 0, 'c', 'libellula', 0, 1, true, 'Di notte la sua coda si accende e guida i viandanti fuori dalla nebbia.'),
 ('pet_gatto', 4, 'Gatto d’Inchiostro', 'Bestia', 1, 'a', 'gatto', 1500, 5, false, 'Nato da una goccia caduta da un mazzo antico: lascia impronte viola dove passa.'),
 ('pet_lumaca', 5, 'Chiocciola Corazzata', 'Insetto', 1, 'b', 'lumaca', 1500, 5, false, 'Lenta, ma nessuno è mai riuscito a scalfirle il guscio d’acciaio.'),
 ('pet_fatina', 6, 'Fata Lanterna', 'Fata', 1, 'c', 'fatina', 1500, 5, false, 'Porta una lanterna che non si spegne mai e illumina i sentieri più bui.'),
 ('pet_volpe', 7, 'Volpe Ardente', 'Pyro', 2, 'a', 'volpe', 4000, 15, false, 'La sua coda è una fiamma gentile: scalda le mani, ma brucia chi la tocca per gioco.'),
 ('pet_granchio', 8, 'Granchio di Cristallo', 'Acqua', 2, 'b', 'granchio', 4000, 15, false, 'Le chele di cristallo riflettono i colpi come specchi.'),
 ('pet_gufo', 9, 'Gufo Sapiente', 'Bestia Alata', 2, 'c', 'gufo', 4000, 15, false, 'Ha letto ogni regolamento del Tempio, e ricorda anche gli errata.'),
 ('pet_lupo', 10, 'Lupo Tempesta', 'Tuono', 3, 'a', 'lupo', 9000, 30, false, 'Ulula e il cielo risponde: la saetta sul petto è la sua firma.'),
 ('pet_sasso', 11, 'Sasso Vivente', 'Roccia', 3, 'b', 'sasso', 9000, 30, false, 'Sembra un masso qualunque, finché non apre gli occhi.'),
 ('pet_mago', 12, 'Piccolo Incantatore', 'Incantatore', 3, 'c', 'mago', 9000, 30, false, 'Apprendista di un mago che nessuno ha mai visto: il cappello è più grande di lui.'),
 ('pet_draghetto', 13, 'Cucciolo di Drago', 'Drago', 4, 'a', 'draghetto', 20000, 50, false, 'Sputa solo scintille, per ora. Dategli tempo.'),
 ('pet_cavaliere', 14, 'Cavaliere Minuscolo', 'Guerriero', 4, 'b', 'cavaliere', 20000, 50, false, 'Giura fedeltà a chiunque gli offra una mela, e la mantiene per sempre.'),
 ('pet_spettro', 15, 'Spettro Lunare', 'Zombie', 4, 'c', 'spettro', 20000, 50, false, 'Compare solo quando c’è la luna, e accompagna i duellanti stanchi.'),
 ('pet_grifone', 16, 'Grifone Dorato', 'Bestia Alata', 5, 'a', 'grifone', 45000, 80, false, 'Vigila sulle vette del Tempio: una sua piuma vale più di un tesoro.'),
 ('pet_leviatano', 17, 'Leviatano Cucciolo', 'Pesce', 5, 'b', 'leviatano', 45000, 80, false, 'Un cucciolo di mostro marino che crede di essere un pesciolino.'),
 ('pet_fenice', 18, 'Fenice Cucciola', 'Pyro', 5, 'c', 'fenice', 45000, 80, false, 'Ogni volta che cade, rinasce più brillante di prima.'),
 ('pet_drago_oscuro', 19, 'Drago d’Ombra', 'Drago', 6, 'a', 'drago_oscuro', 90000, 120, false, 'Si nasconde nelle ombre dei mazzi proibiti e vede ciò che gli altri ignorano.'),
 ('pet_automa', 20, 'Automa d’Ottone', 'Macchina', 6, 'b', 'automa', 90000, 120, false, 'Costruito da un artigiano dimenticato: funziona a ingranaggi e a lealtà.'),
 ('pet_unicorno', 21, 'Unicorno Astrale', 'Bestia', 6, 'c', 'unicorno', 90000, 120, false, 'Il suo corno è una stella caduta: dove poggia lo zoccolo nascono fiori.'),
 ('pet_idra', 22, 'Idra Minore', 'Rettile', 7, 'a', 'idra', 180000, 180, false, 'Tre teste, tre opinioni, un solo appetito.'),
 ('pet_guardiano', 23, 'Guardiano di Giada', 'Guerriero', 7, 'b', 'guardiano', 180000, 180, false, 'Statua sacra risvegliata da un duello antico: protegge la soglia del Tempio.'),
 ('pet_serafino', 24, 'Serafino Minore', 'Fata', 7, 'c', 'serafino', 180000, 180, false, 'Canta a bocca chiusa: chi lo ascolta ritrova il coraggio.'),
 ('pet_drago_tuono', 25, 'Drago della Tempesta', 'Drago', 8, 'a', 'drago_tuono', 350000, 260, false, 'Quando sbatte le ali il cielo si carica: poi arriva il fulmine.'),
 ('pet_cerbero', 26, 'Cerbero Cucciolo', 'Demone', 8, 'b', 'cerbero', 350000, 260, false, 'Tre teste da educare, tre ciotole da riempire, una sola fedeltà.'),
 ('pet_sfinge', 27, 'Sfinge Arcana', 'Incantatore', 8, 'c', 'sfinge', 350000, 260, false, 'Pone un enigma a ogni sfidante: chi risponde bene vince la partita.'),
 ('pet_drago_celeste', 28, 'Drago Celeste', 'Drago', 9, 'a', 'drago_celeste', 700000, 380, false, 'Vola sopra le nuvole dove il tempo si ferma: le sue ali sono fatte di alba.'),
 ('pet_tartaruga_cosmica', 29, 'Tartaruga Cosmica', 'Divinità', 9, 'b', 'tartaruga_cosmica', 700000, 380, false, 'Sul suo guscio gira un piccolo universo, con tanto di albero.'),
 ('pet_spirito', 30, 'Spirito del Tempio', 'Divinità', 9, 'c', 'spirito', 700000, 380, false, 'L’anima stessa del Tempio dei Duelli: si mostra solo a chi l’ha onorato davvero.')
on conflict (id) do update set no = excluded.no, name = excluded.name, family = excluded.family, tier = excluded.tier, variant = excluded.variant,
  sprite = excluded.sprite, price_bc = excluded.price_bc, min_level = excluded.min_level, starter = excluded.starter, lore = excluded.lore;
insert into public.game_pet_lines (pet_id, pos, effect, max_value, unlock_level) values
 ('pet_ranocchio', 1, 'for', 8, 1),
 ('pet_ranocchio', 2, 'des', 6, 10),
 ('pet_ranocchio', 3, 'vig', 4, 25),
 ('pet_tartaruga', 1, 'vig', 8, 1),
 ('pet_tartaruga', 2, 'frt', 6, 10),
 ('pet_tartaruga', 3, 'for', 4, 25),
 ('pet_libellula', 1, 'spi', 8, 1),
 ('pet_libellula', 2, 'xp', 3, 10),
 ('pet_libellula', 3, 'des', 6, 25),
 ('pet_gatto', 1, 'for', 12, 1),
 ('pet_gatto', 2, 'des', 9, 10),
 ('pet_gatto', 3, 'vig', 6, 25),
 ('pet_lumaca', 1, 'vig', 12, 1),
 ('pet_lumaca', 2, 'frt', 10, 10),
 ('pet_lumaca', 3, 'for', 6, 25),
 ('pet_fatina', 1, 'spi', 12, 1),
 ('pet_fatina', 2, 'xp', 5, 10),
 ('pet_fatina', 3, 'des', 8, 25),
 ('pet_volpe', 1, 'for', 16, 1),
 ('pet_volpe', 2, 'des', 12, 10),
 ('pet_volpe', 3, 'vig', 8, 25),
 ('pet_granchio', 1, 'vig', 16, 1),
 ('pet_granchio', 2, 'frt', 13, 10),
 ('pet_granchio', 3, 'for', 8, 25),
 ('pet_gufo', 1, 'spi', 16, 1),
 ('pet_gufo', 2, 'xp', 6, 10),
 ('pet_gufo', 3, 'des', 11, 25),
 ('pet_lupo', 1, 'for', 20, 1),
 ('pet_lupo', 2, 'des', 15, 10),
 ('pet_lupo', 3, 'vig', 10, 25),
 ('pet_lupo', 4, 'xp', 5, 45),
 ('pet_sasso', 1, 'vig', 20, 1),
 ('pet_sasso', 2, 'frt', 16, 10),
 ('pet_sasso', 3, 'for', 10, 25),
 ('pet_sasso', 4, 'xp', 4, 45),
 ('pet_mago', 1, 'spi', 20, 1),
 ('pet_mago', 2, 'xp', 8, 10),
 ('pet_mago', 3, 'des', 14, 25),
 ('pet_mago', 4, 'fights', 1, 45),
 ('pet_draghetto', 1, 'for', 24, 1),
 ('pet_draghetto', 2, 'des', 18, 10),
 ('pet_draghetto', 3, 'vig', 12, 25),
 ('pet_draghetto', 4, 'xp', 6, 45),
 ('pet_cavaliere', 1, 'vig', 24, 1),
 ('pet_cavaliere', 2, 'frt', 19, 10),
 ('pet_cavaliere', 3, 'for', 12, 25),
 ('pet_cavaliere', 4, 'xp', 5, 45),
 ('pet_spettro', 1, 'spi', 24, 1),
 ('pet_spettro', 2, 'xp', 10, 10),
 ('pet_spettro', 3, 'des', 17, 25),
 ('pet_spettro', 4, 'fights', 1, 45),
 ('pet_grifone', 1, 'for', 28, 1),
 ('pet_grifone', 2, 'des', 21, 10),
 ('pet_grifone', 3, 'vig', 14, 25),
 ('pet_grifone', 4, 'xp', 7, 45),
 ('pet_leviatano', 1, 'vig', 28, 1),
 ('pet_leviatano', 2, 'frt', 22, 10),
 ('pet_leviatano', 3, 'for', 14, 25),
 ('pet_leviatano', 4, 'xp', 6, 45),
 ('pet_fenice', 1, 'spi', 28, 1),
 ('pet_fenice', 2, 'xp', 11, 10),
 ('pet_fenice', 3, 'des', 20, 25),
 ('pet_fenice', 4, 'fights', 1, 45),
 ('pet_drago_oscuro', 1, 'for', 32, 1),
 ('pet_drago_oscuro', 2, 'des', 24, 10),
 ('pet_drago_oscuro', 3, 'vig', 16, 25),
 ('pet_drago_oscuro', 4, 'xp', 8, 45),
 ('pet_automa', 1, 'vig', 32, 1),
 ('pet_automa', 2, 'frt', 26, 10),
 ('pet_automa', 3, 'for', 16, 25),
 ('pet_automa', 4, 'xp', 6, 45),
 ('pet_unicorno', 1, 'spi', 32, 1),
 ('pet_unicorno', 2, 'xp', 13, 10),
 ('pet_unicorno', 3, 'des', 22, 25),
 ('pet_unicorno', 4, 'fights', 1, 45),
 ('pet_idra', 1, 'for', 36, 1),
 ('pet_idra', 2, 'des', 27, 10),
 ('pet_idra', 3, 'vig', 18, 25),
 ('pet_idra', 4, 'xp', 9, 45),
 ('pet_idra', 5, 'frt', 9, 70),
 ('pet_guardiano', 1, 'vig', 36, 1),
 ('pet_guardiano', 2, 'frt', 29, 10),
 ('pet_guardiano', 3, 'for', 18, 25),
 ('pet_guardiano', 4, 'xp', 7, 45),
 ('pet_guardiano', 5, 'spi', 14, 70),
 ('pet_serafino', 1, 'spi', 36, 1),
 ('pet_serafino', 2, 'xp', 14, 10),
 ('pet_serafino', 3, 'des', 25, 25),
 ('pet_serafino', 4, 'fights', 1, 45),
 ('pet_serafino', 5, 'vig', 18, 70),
 ('pet_drago_tuono', 1, 'for', 40, 1),
 ('pet_drago_tuono', 2, 'des', 30, 10),
 ('pet_drago_tuono', 3, 'vig', 20, 25),
 ('pet_drago_tuono', 4, 'xp', 10, 45),
 ('pet_drago_tuono', 5, 'actions', 1, 70),
 ('pet_cerbero', 1, 'vig', 40, 1),
 ('pet_cerbero', 2, 'frt', 32, 10),
 ('pet_cerbero', 3, 'for', 20, 25),
 ('pet_cerbero', 4, 'xp', 8, 45),
 ('pet_cerbero', 5, 'spi', 16, 70),
 ('pet_sfinge', 1, 'spi', 40, 1),
 ('pet_sfinge', 2, 'xp', 16, 10),
 ('pet_sfinge', 3, 'des', 28, 25),
 ('pet_sfinge', 4, 'fights', 2, 45),
 ('pet_sfinge', 5, 'vig', 20, 70),
 ('pet_drago_celeste', 1, 'for', 44, 1),
 ('pet_drago_celeste', 2, 'des', 33, 10),
 ('pet_drago_celeste', 3, 'vig', 22, 25),
 ('pet_drago_celeste', 4, 'xp', 11, 45),
 ('pet_drago_celeste', 5, 'actions', 1, 70),
 ('pet_tartaruga_cosmica', 1, 'vig', 44, 1),
 ('pet_tartaruga_cosmica', 2, 'frt', 35, 10),
 ('pet_tartaruga_cosmica', 3, 'for', 22, 25),
 ('pet_tartaruga_cosmica', 4, 'xp', 9, 45),
 ('pet_tartaruga_cosmica', 5, 'spi', 18, 70),
 ('pet_spirito', 1, 'spi', 44, 1),
 ('pet_spirito', 2, 'xp', 18, 10),
 ('pet_spirito', 3, 'des', 31, 25),
 ('pet_spirito', 4, 'fights', 2, 45),
 ('pet_spirito', 5, 'vig', 22, 70)
on conflict (pet_id, pos) do update set effect = excluded.effect, max_value = excluded.max_value, unlock_level = excluded.unlock_level;

-- ---------- regole ----------
create or replace function public._game_pet_xp_pct() returns integer language sql stable security definer set search_path = public as $$ select greatest(0, least(100, public._setting('game_pet_xp_pct'))) $$;
create or replace function public._game_pet_max_level() returns integer language sql stable security definer set search_path = public as $$ select greatest(2, least(500, public._setting('game_pet_max_level'))) $$;

-- valore di un bonus a un dato livello del pet: 0 prima dello sblocco; poi parte da un quarto del massimo e lo raggiunge al livello massimo (mai meno di 1)
create or replace function public._game_pet_value(p_max integer, p_unlock integer, p_level integer, p_maxlvl integer) returns integer language sql immutable as $$
  select case when p_level < p_unlock then 0
              else greatest(1, floor(p_max * (0.25 + 0.75 * (least(p_level, p_maxlvl) - p_unlock)::numeric / greatest(1, p_maxlvl - p_unlock))))::integer end $$;

-- bonus totali del pet ATTIVO di un eroe (tutti zero se non ne ha)
create or replace function public._game_pet_bonus(p_user uuid)
returns table (pf integer, pd integer, pv integer, ps integer, pr integer, px integer, pa integer, pq integer)
language sql stable security definer set search_path = public as $$
  with l as (select ln.effect, public._game_pet_value(ln.max_value, ln.unlock_level, hp.level, public._game_pet_max_level()) as v
             from public.game_hero_pets hp join public.game_pet_lines ln on ln.pet_id = hp.pet_id where hp.user_id = p_user and hp.active)
  select coalesce(sum(v) filter (where effect = 'for'), 0)::integer, coalesce(sum(v) filter (where effect = 'des'), 0)::integer, coalesce(sum(v) filter (where effect = 'vig'), 0)::integer,
         coalesce(sum(v) filter (where effect = 'spi'), 0)::integer, coalesce(sum(v) filter (where effect = 'frt'), 0)::integer, coalesce(sum(v) filter (where effect = 'xp'), 0)::integer,
         coalesce(sum(v) filter (where effect = 'actions'), 0)::integer, coalesce(sum(v) filter (where effect = 'fights'), 0)::integer from l $$;

-- scheda del pet attivo (per il cruscotto): null se l'eroe non ne ha
create or replace function public._game_pet_card(p_user uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', g.id, 'name', g.name, 'family', g.family, 'tier', g.tier, 'sprite', g.sprite, 'level', hp.level, 'xp', hp.xp, 'xp_need', public._game_xp_need(hp.level),
           'max_level', public._game_pet_max_level(), 'at_cap', hp.level >= least(public._game_pet_max_level(), (select h.level from public.game_heroes h where h.user_id = p_user)),
           'lines', coalesce((select jsonb_agg(jsonb_build_object('effect', ln.effect, 'unlock', ln.unlock_level, 'max', ln.max_value,
                      'value', public._game_pet_value(ln.max_value, ln.unlock_level, hp.level, public._game_pet_max_level())) order by ln.pos)
                    from public.game_pet_lines ln where ln.pet_id = g.id), '[]'::jsonb))
  from public.game_hero_pets hp join public.game_pets g on g.id = hp.pet_id where hp.user_id = p_user and hp.active $$;

-- il pet attivo guadagna una quota dell'XP appena ottenuta dall'eroe (si chiama da _game_add_xp)
create or replace function public._game_pet_gain(p_user uuid, p_hero_xp bigint) returns void language plpgsql security definer set search_path = public as $$
declare hp public.game_hero_pets%rowtype; hl integer; cap integer; add_ bigint;
begin
  add_ := floor(greatest(0, coalesce(p_hero_xp, 0)) * public._game_pet_xp_pct() / 100.0)::bigint;
  if add_ <= 0 then return; end if;
  select * into hp from public.game_hero_pets where user_id = p_user and active for update;
  if not found then return; end if;
  select level into hl from public.game_heroes where user_id = p_user;
  cap := least(public._game_pet_max_level(), coalesce(hl, 1));            -- un pet non supera l'eroe né il livello massimo
  if hp.level >= cap then
    update public.game_hero_pets set xp = 0 where user_id = p_user and pet_id = hp.pet_id and xp <> 0;
    return;
  end if;
  hp.xp := hp.xp + add_;
  while hp.level < cap and hp.xp >= public._game_xp_need(hp.level) loop
    hp.xp := hp.xp - public._game_xp_need(hp.level); hp.level := hp.level + 1;
  end loop;
  if hp.level >= cap then hp.xp := 0; end if;
  update public.game_hero_pets set level = hp.level, xp = hp.xp, total_xp = total_xp + add_ where user_id = p_user and pet_id = hp.pet_id;
end $$;

-- ---------- le tre funzioni esistenti, ora consapevoli dei pet ----------
-- statistiche reali: oggetti + abilità + POTENZIAMENTI + bonus del pet attivo
create or replace function public._game_calc(p_user uuid)
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
  pb as (select * from public._game_pet_bonus(p_user)),
  t as (select b.pf + k.kf + pb.pf as tf, b.pd + k.kd + pb.pd as td, b.pv + k.kv + pb.pv as tv, b.ps + k.ks + pb.ps as ts, b.pr + k.kr + pb.pr as tr, b.px + pb.px as px, b.pa + pb.pa as pa, b.pq + pb.pq as pq from b, k, pb),
  s as (select h.level,
          round((5 + h.a_for::numeric * h.level) * (100 + t.tf) / 100)::bigint as sf,
          round((5 + h.a_des::numeric * h.level) * (100 + t.td) / 100)::bigint as sd,
          round((5 + h.a_vig::numeric * h.level) * (100 + t.tv) / 100)::bigint as sv,
          round((5 + h.a_spi::numeric * h.level) * (100 + t.ts) / 100)::bigint as ss,
          round((5 + h.a_frt::numeric * h.level) * (100 + t.tr) / 100)::bigint as sr,
          t.tf, t.td, t.tv, t.ts, t.tr, t.px, t.pa, t.pq from h, t)
  select s.level, s.sf, s.sd, s.sv, s.ss, s.sr, 50 + 12 * s.sv, s.px::integer, s.pa::integer, s.pq::integer, s.tf::integer, s.td::integer, s.tv::integer, s.ts::integer, s.tr::integer from s $$;

-- scheda dell'eroe: aggiunge il campo «pet» (il pet attivo, per il cruscotto)
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
    'respec_count', h.respec_count, 'fights_total', h.fights_total, 'pet', public._game_pet_card(h.user_id),
    'equipped', coalesce((select jsonb_object_agg(e.slot, jsonb_build_object('id', i.id, 'name', i.name, 'rarity', i.rarity, 'tier', i.tier, 'min_level', i.min_level,
        'p_for', i.p_for, 'p_des', i.p_des, 'p_vig', i.p_vig, 'p_spi', i.p_spi, 'p_frt', i.p_frt, 'xp_pct', i.xp_pct, 'extra_actions', i.extra_actions, 'extra_fights', i.extra_fights, 'descr', i.descr))
      from public.game_equipped e join public.game_items i on i.id = e.item_id where e.user_id = h.user_id), '{}'::jsonb),
    'perm_skills', coalesce((select jsonb_agg(k.name order by k.stat, k.tier) from public.game_hero_skills s join public.game_skills k on k.id = s.skill_id where s.user_id = h.user_id), '[]'::jsonb),
    'temp_skills', coalesce((select jsonb_agg(jsonb_build_object('name', k.name, 'slot', k.slot, 'until', t.expires_at) order by t.expires_at)
                             from public.game_temp_skills t join public.game_skills k on k.id = t.skill_id where t.user_id = h.user_id and t.expires_at > now()), '[]'::jsonb))
  from public.game_heroes h join public.profiles p on p.id = h.user_id
  cross join lateral public._game_calc(h.user_id) c
  where h.user_id = p_user $$;

-- XP: come prima, e in più il pet attivo guadagna la sua quota
create or replace function public._game_add_xp(p_user uuid, p_xp bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare h public.game_heroes%rowtype; pct integer; add_ bigint; gained integer := 0; cap integer := public._game_level_cap(); lvl0 integer; refill boolean := false;
begin
  select * into h from public.game_heroes where user_id = p_user for update;
  if not found then raise exception 'Eroe inesistente'; end if;
  lvl0 := h.level;          -- livello di partenza: è questo che decide se la ricarica è ancora attiva
  select xp_pct into pct from public._game_calc(p_user);
  add_ := greatest(0, p_xp) * (100 + coalesce(pct, 0)) / 100;
  if h.level < cap then
    h.xp := h.xp + add_;
    while h.level < cap and h.xp >= public._game_xp_need(h.level) loop
      h.xp := h.xp - public._game_xp_need(h.level); h.level := h.level + 1; gained := gained + 1;
    end loop;
    if h.level >= cap then h.xp := 0; end if;
  else
    h.xp := 0;      -- già al limite (o oltre, se il limite è stato abbassato): il livello non cambia, l'XP in eccesso non si accumula
  end if;
  update public.game_heroes set level = h.level, xp = h.xp, total_xp = total_xp + add_ where user_id = p_user;
  if gained > 0 and lvl0 < public._game_refill_below_level() then      -- salire di livello ricarica la batteria al 100%, ma solo se si partiva sotto il livello 100
    update public.game_heroes set energy = public._game_energy_max(), energy_at = now() where user_id = p_user;
    refill := true;
  end if;
  perform public._game_pet_gain(p_user, add_);          -- il compagno guadagna una quota dell'XP dell'eroe (impostazione game_pet_xp_pct, 20%)
  return jsonb_build_object('xp', add_, 'levels', gained, 'level', h.level, 'energy_full', refill, 'cap', cap);
end $$;

-- ---------- Lo stagno: stato per la pagina ----------
create or replace function public.game_pet_state() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); hl integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select level into hl from public.game_heroes where user_id = v;
  return jsonb_build_object('chosen', exists (select 1 from public.game_hero_pets where user_id = v), 'hero_level', hl,
    'xp_pct', public._game_pet_xp_pct(), 'max_level', public._game_pet_max_level(), 'active', public._game_pet_card(v),
    'pets', (select jsonb_agg(jsonb_build_object('id', g.id, 'no', g.no, 'name', g.name, 'family', g.family, 'tier', g.tier, 'variant', g.variant, 'sprite', g.sprite,
               'price', g.price_bc, 'min_level', g.min_level, 'starter', g.starter, 'lore', g.lore,
               'owned', hp.user_id is not null, 'active', coalesce(hp.active, false), 'level', hp.level, 'xp', hp.xp, 'xp_need', case when hp.user_id is not null then public._game_xp_need(hp.level) end,
               'lines', (select jsonb_agg(jsonb_build_object('effect', ln.effect, 'unlock', ln.unlock_level, 'max', ln.max_value,
                           'value', case when hp.user_id is not null then public._game_pet_value(ln.max_value, ln.unlock_level, hp.level, public._game_pet_max_level()) end) order by ln.pos)
                         from public.game_pet_lines ln where ln.pet_id = g.id)) order by g.no)
             from public.game_pets g left join public.game_hero_pets hp on hp.pet_id = g.id and hp.user_id = v));
end $$;

-- ---------- scegliere il pet base (una volta sola) ----------
create or replace function public.game_pet_choose(p_pet text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); g public.game_pets%rowtype;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  perform 1 from public.game_heroes where user_id = v for update;
  select * into g from public.game_pets where id = p_pet;
  if not found then raise exception 'Compagno inesistente'; end if;
  if not g.starter then raise exception 'Questo compagno non è tra i tre di base: lo trovi in vendita nello Stagno'; end if;
  if exists (select 1 from public.game_hero_pets where user_id = v) then raise exception 'Hai già scelto il tuo compagno'; end if;
  insert into public.game_hero_pets (user_id, pet_id, active) values (v, g.id, true);
  return jsonb_build_object('pet', g.name, 'card', public._game_pet_card(v));
end $$;

-- ---------- comprare un pet ----------
create or replace function public.game_pet_buy(p_pet text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); g public.game_pets%rowtype; h public.game_heroes%rowtype; v_bal integer;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select * into h from public.game_heroes where user_id = v for update;
  select * into g from public.game_pets where id = p_pet;
  if not found then raise exception 'Compagno inesistente'; end if;
  if g.starter then raise exception 'I tre compagni base non si comprano: se ne sceglie uno nello Stagno'; end if;
  if not exists (select 1 from public.game_hero_pets where user_id = v) then raise exception 'Prima scegli il tuo compagno base nello Stagno'; end if;
  if exists (select 1 from public.game_hero_pets where user_id = v and pet_id = g.id) then raise exception 'Possiedi già questo compagno'; end if;
  if h.level < g.min_level then raise exception 'Ti serve il livello % per questo compagno', g.min_level; end if;
  v_bal := public._ledger_move(v, -g.price_bc, 'game_pet', 'game_pet', null, 'gamepet:' || v::text || ':' || g.id || ':' || gen_random_uuid()::text, 'Lo stagno: ' || g.name);
  insert into public.game_hero_pets (user_id, pet_id, active) values (v, g.id, false);
  return jsonb_build_object('pet', g.name, 'price', g.price_bc, 'balance', v_bal);
end $$;

-- ---------- scegliere il compagno attivo ----------
create or replace function public.game_pet_activate(p_pet text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); g public.game_pets%rowtype;
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  perform 1 from public.game_heroes where user_id = v for update;
  select * into g from public.game_pets where id = p_pet;
  if not found or not exists (select 1 from public.game_hero_pets where user_id = v and pet_id = g.id) then raise exception 'Non possiedi questo compagno'; end if;
  update public.game_hero_pets set active = false where user_id = v and active and pet_id <> g.id;
  update public.game_hero_pets set active = true where user_id = v and pet_id = g.id;
  return jsonb_build_object('pet', g.name, 'card', public._game_pet_card(v));
end $$;

revoke all on function public._game_pet_xp_pct(), public._game_pet_max_level(), public._game_pet_value(integer, integer, integer, integer), public._game_pet_bonus(uuid),
  public._game_pet_card(uuid), public._game_pet_gain(uuid, bigint) from public, anon, authenticated;
revoke all on function public._game_calc(uuid), public._game_hero_json(uuid), public._game_add_xp(uuid, bigint) from public, anon, authenticated;
revoke all on function public.game_pet_state(), public.game_pet_choose(text), public.game_pet_buy(text), public.game_pet_activate(text) from public, anon;
grant execute on function public.game_pet_state(), public.game_pet_choose(text), public.game_pet_buy(text), public.game_pet_activate(text) to authenticated;
commit;
