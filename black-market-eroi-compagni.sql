-- =====================================================================
-- MIGRAZIONE 043 — La guerra degli Eroi: NUOVI COMPAGNI DELLO STAGNO (gradi 10–14, fino al livello 600)
-- Da eseguire in Supabase (SQL Editor) DOPO la migrazione 031 (Lo stagno). Non dipende dalla 041/042 (Mappa, Villaggi).
--   15 compagni nuovi, 3 per grado (uno per stile: Assalto, Baluardo, Saggezza), sprite pixel art originali in eroi-pet.js:
--       grado   prezzo (BC)   livello eroe   compagni
--        10     1.100.000        420        Chimera Ruggente · Golem d’Ossidiana · Medusa Abissale
--        11     1.600.000        460        Kirin del Lampo · Scarabeo d’Ambra · Kitsune Lunare
--        12     2.400.000        500        Wyrm di Magma · Kraken Bambino · Gatto delle Nebulose
--        13     3.500.000        550        Drago del Vuoto · Behemoth Corazzato · Arcangelo di Luce
--        14     5.000.000        600        Drago Primordiale · Guardiano dell’Eclissi · Albero del Mondo
--   BONUS: continuano la scala dei gradi 1–9 (il bonus principale sale di 4 punti a grado: 48% al grado 10 … 64% al grado 14).
--     Gradi 10–11: 5 bonus come il grado 9. Gradi 12–14: un 6° bonus che si sblocca al livello 90 del compagno.
--     Assalto: Forza, Destrezza, Vigore, XP, +1 azione · Baluardo: Vigore, Fortezza, Forza, XP, Spirito · Saggezza: Spirito, XP, Destrezza, ricarica energia, Vigore.
--   Si comprano nello Stagno come gli altri (dopo aver scelto il compagno base); regole, esperienza e livelli non cambiano.
--   Si può rieseguire (aggiorna il catalogo, non tocca i compagni già posseduti). Annullamento: black-market-eroi-compagni-down.sql.
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.game_pets') is null then
    raise exception 'Prima esegui la migrazione 031 (black-market-eroi-stagno.sql). Non è stato modificato nulla.';
  end if;
end $$;

-- i gradi ora arrivano a 14
do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid = 'public.game_pets'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%tier%' loop
    execute format('alter table public.game_pets drop constraint %I', c);
  end loop;
  alter table public.game_pets add constraint game_pets_tier_check check (tier between 0 and 14);
end $$;

insert into public.game_pets (id, no, name, family, tier, variant, sprite, price_bc, min_level, starter, lore) values
 ('pet_chimera', 31, 'Chimera Ruggente', 'Bestia', 10, 'a', 'chimera', 1100000, 420, false, 'Leone, drago e serpente in un corpo solo: litigano su tutto, tranne su chi attaccare.'),
 ('pet_golem_ossidiana', 32, 'Golem d’Ossidiana', 'Roccia', 10, 'b', 'golem_ossidiana', 1100000, 420, false, 'Vetro di vulcano raffreddato in un attimo: dentro il petto il fuoco non si è mai spento.'),
 ('pet_medusa', 33, 'Medusa Abissale', 'Acqua', 10, 'c', 'medusa', 1100000, 420, false, 'Brilla nel buio degli abissi e sussurra a chi la segue i segreti delle maree.'),
 ('pet_kirin', 34, 'Kirin del Lampo', 'Tuono', 11, 'a', 'kirin', 1600000, 460, false, 'Galoppa sulle nuvole senza toccarle: dove passa, il temporale si inchina.'),
 ('pet_scarabeo', 35, 'Scarabeo d’Ambra', 'Insetto', 11, 'b', 'scarabeo', 1600000, 460, false, 'Ha dormito mille anni in una goccia d’ambra; ora non si stanca mai di proteggere.'),
 ('pet_kitsune', 36, 'Kitsune Lunare', 'Bestia', 11, 'c', 'kitsune', 1600000, 460, false, 'Ogni sua coda custodisce un ricordo dei duelli che ha visto: le sta ancora contando.'),
 ('pet_wyrm_magma', 37, 'Wyrm di Magma', 'Drago', 12, 'a', 'wyrm_magma', 2400000, 500, false, 'Nuota nella lava come gli altri nell’acqua, e ne esce più caldo di prima.'),
 ('pet_kraken', 38, 'Kraken Bambino', 'Pesce', 12, 'b', 'kraken', 2400000, 500, false, 'Otto braccia per stringere, nessuna per lasciare andare chi ha giurato di difendere.'),
 ('pet_gatto_nebulosa', 39, 'Gatto delle Nebulose', 'Divinità', 12, 'c', 'gatto_nebulosa', 2400000, 500, false, 'Nel suo pelo si accendono stelle nuove: quando fa le fusa, nasce una costellazione.'),
 ('pet_drago_vuoto', 40, 'Drago del Vuoto', 'Drago', 13, 'a', 'drago_vuoto', 3500000, 550, false, 'Viene da dove finiscono le mappe: il suo ruggito non fa rumore, ma lo senti lo stesso.'),
 ('pet_behemoth', 41, 'Behemoth Corazzato', 'Bestia', 13, 'b', 'behemoth', 3500000, 550, false, 'Quando si addormenta lo scambiano per una collina; quando si sveglia, la collina sei tu.'),
 ('pet_arcangelo', 42, 'Arcangelo di Luce', 'Fata', 13, 'c', 'arcangelo', 3500000, 550, false, 'Scende solo per i duellanti che non si sono mai arresi, e non se ne va più.'),
 ('pet_drago_primordiale', 43, 'Drago Primordiale', 'Divinità', 14, 'a', 'drago_primordiale', 5000000, 600, false, 'Il primo drago, nato prima delle carte: ogni altro drago porta un po’ del suo fuoco.'),
 ('pet_eclissi', 44, 'Guardiano dell’Eclissi', 'Guerriero', 14, 'b', 'eclissi', 5000000, 600, false, 'Tiene il sole e la luna nello stesso cielo: finché veglia lui, la notte non vince.'),
 ('pet_albero_mondo', 45, 'Albero del Mondo', 'Divinità', 14, 'c', 'albero_mondo', 5000000, 600, false, 'Piccolo così, ma le sue radici toccano ogni Tempio del mondo. Sorride a chi lo annaffia.')
on conflict (id) do update set no = excluded.no, name = excluded.name, family = excluded.family, tier = excluded.tier, variant = excluded.variant,
  sprite = excluded.sprite, price_bc = excluded.price_bc, min_level = excluded.min_level, starter = excluded.starter, lore = excluded.lore;

insert into public.game_pet_lines (pet_id, pos, effect, max_value, unlock_level) values
 ('pet_chimera', 1, 'for', 48, 1),
 ('pet_chimera', 2, 'des', 36, 10),
 ('pet_chimera', 3, 'vig', 24, 25),
 ('pet_chimera', 4, 'xp', 12, 45),
 ('pet_chimera', 5, 'actions', 1, 70),
 ('pet_golem_ossidiana', 1, 'vig', 48, 1),
 ('pet_golem_ossidiana', 2, 'frt', 38, 10),
 ('pet_golem_ossidiana', 3, 'for', 24, 25),
 ('pet_golem_ossidiana', 4, 'xp', 10, 45),
 ('pet_golem_ossidiana', 5, 'spi', 20, 70),
 ('pet_medusa', 1, 'spi', 48, 1),
 ('pet_medusa', 2, 'xp', 19, 10),
 ('pet_medusa', 3, 'des', 34, 25),
 ('pet_medusa', 4, 'fights', 2, 45),
 ('pet_medusa', 5, 'vig', 24, 70),
 ('pet_kirin', 1, 'for', 52, 1),
 ('pet_kirin', 2, 'des', 39, 10),
 ('pet_kirin', 3, 'vig', 26, 25),
 ('pet_kirin', 4, 'xp', 13, 45),
 ('pet_kirin', 5, 'actions', 1, 70),
 ('pet_scarabeo', 1, 'vig', 52, 1),
 ('pet_scarabeo', 2, 'frt', 41, 10),
 ('pet_scarabeo', 3, 'for', 26, 25),
 ('pet_scarabeo', 4, 'xp', 11, 45),
 ('pet_scarabeo', 5, 'spi', 22, 70),
 ('pet_kitsune', 1, 'spi', 52, 1),
 ('pet_kitsune', 2, 'xp', 20, 10),
 ('pet_kitsune', 3, 'des', 37, 25),
 ('pet_kitsune', 4, 'fights', 2, 45),
 ('pet_kitsune', 5, 'vig', 26, 70),
 ('pet_wyrm_magma', 1, 'for', 56, 1),
 ('pet_wyrm_magma', 2, 'des', 42, 10),
 ('pet_wyrm_magma', 3, 'vig', 28, 25),
 ('pet_wyrm_magma', 4, 'xp', 14, 45),
 ('pet_wyrm_magma', 5, 'actions', 1, 70),
 ('pet_wyrm_magma', 6, 'frt', 16, 90),
 ('pet_kraken', 1, 'vig', 56, 1),
 ('pet_kraken', 2, 'frt', 44, 10),
 ('pet_kraken', 3, 'for', 28, 25),
 ('pet_kraken', 4, 'xp', 12, 45),
 ('pet_kraken', 5, 'spi', 24, 70),
 ('pet_kraken', 6, 'des', 18, 90),
 ('pet_gatto_nebulosa', 1, 'spi', 56, 1),
 ('pet_gatto_nebulosa', 2, 'xp', 21, 10),
 ('pet_gatto_nebulosa', 3, 'des', 40, 25),
 ('pet_gatto_nebulosa', 4, 'fights', 2, 45),
 ('pet_gatto_nebulosa', 5, 'vig', 28, 70),
 ('pet_gatto_nebulosa', 6, 'for', 16, 90),
 ('pet_drago_vuoto', 1, 'for', 60, 1),
 ('pet_drago_vuoto', 2, 'des', 45, 10),
 ('pet_drago_vuoto', 3, 'vig', 30, 25),
 ('pet_drago_vuoto', 4, 'xp', 15, 45),
 ('pet_drago_vuoto', 5, 'actions', 1, 70),
 ('pet_drago_vuoto', 6, 'frt', 18, 90),
 ('pet_behemoth', 1, 'vig', 60, 1),
 ('pet_behemoth', 2, 'frt', 47, 10),
 ('pet_behemoth', 3, 'for', 30, 25),
 ('pet_behemoth', 4, 'xp', 13, 45),
 ('pet_behemoth', 5, 'spi', 26, 70),
 ('pet_behemoth', 6, 'des', 20, 90),
 ('pet_arcangelo', 1, 'spi', 60, 1),
 ('pet_arcangelo', 2, 'xp', 22, 10),
 ('pet_arcangelo', 3, 'des', 43, 25),
 ('pet_arcangelo', 4, 'fights', 2, 45),
 ('pet_arcangelo', 5, 'vig', 30, 70),
 ('pet_arcangelo', 6, 'for', 18, 90),
 ('pet_drago_primordiale', 1, 'for', 64, 1),
 ('pet_drago_primordiale', 2, 'des', 48, 10),
 ('pet_drago_primordiale', 3, 'vig', 32, 25),
 ('pet_drago_primordiale', 4, 'xp', 16, 45),
 ('pet_drago_primordiale', 5, 'actions', 1, 70),
 ('pet_drago_primordiale', 6, 'frt', 20, 90),
 ('pet_eclissi', 1, 'vig', 64, 1),
 ('pet_eclissi', 2, 'frt', 50, 10),
 ('pet_eclissi', 3, 'for', 32, 25),
 ('pet_eclissi', 4, 'xp', 14, 45),
 ('pet_eclissi', 5, 'spi', 28, 70),
 ('pet_eclissi', 6, 'des', 22, 90),
 ('pet_albero_mondo', 1, 'spi', 64, 1),
 ('pet_albero_mondo', 2, 'xp', 23, 10),
 ('pet_albero_mondo', 3, 'des', 46, 25),
 ('pet_albero_mondo', 4, 'fights', 2, 45),
 ('pet_albero_mondo', 5, 'vig', 32, 70),
 ('pet_albero_mondo', 6, 'for', 20, 90)
on conflict (pet_id, pos) do update set effect = excluded.effect, max_value = excluded.max_value, unlock_level = excluded.unlock_level;

commit;
