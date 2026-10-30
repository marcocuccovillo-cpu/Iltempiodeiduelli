-- =====================================================================
-- MIGRAZIONE 030 — La guerra degli Eroi: ABILITÀ PERMANENTI, gradi dal 5° all'8°
--   Il Mercante vende 20 abilità permanenti (5 statistiche × 4 gradi, da +3% a +12%, fino a 10.000 BC e livello 70). Questa migrazione aggiunge
--   altri 4 gradi per ogni statistica (20 abilità nuove, per un totale di 40), pensati per chi ha già comprato tutto e per i livelli alti (fino al 600):
--
--       grado   bonus   prezzo (BC)   livello richiesto      (bonus totale di una statistica con tutti gli 8 gradi: +109%)
--         5     +15%      25.000          100
--         6     +18%      60.000          170
--         7     +22%     150.000          260
--         8     +26%     400.000          400
--
--   * Stesse regole di prima: si comprano in ordine (prima il grado precedente), una sola volta, per sempre; solo BC, che escono dal gioco.
--   * Nessuna modifica a funzioni o tabelle: la pagina e il database leggono già il catalogo così com'è. Cambiano solo i testi di eroi.html.
--   * I prezzi e i livelli si possono cambiare dopo, con un normale «update public.game_skills set price_bc = … where id = '…'».
--   * Si può rieseguire senza danni (le righe si aggiornano, nulla si duplica; chi ha già comprato non perde niente).
--   * Annullamento: black-market-eroi-abilita-gradi-down.sql (rifiuta se qualcuno ha già comprato uno dei nuovi gradi: i BC spesi non si possono restituire in automatico).
-- Da eseguire in Supabase (SQL Editor) DOPO le migrazioni della guerra degli Eroi (la 023 «v2» con le abilità basta).
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.game_skills') is null or to_regclass('public.game_hero_skills') is null then
    raise exception 'Prima esegui le migrazioni della guerra degli Eroi: manca il catalogo delle abilità. Non è stato modificato nulla.';
  end if;
  if (select count(*) from public.game_skills where kind = 'perm' and tier <= 4) < 20 then
    raise exception 'Il catalogo delle abilità permanenti non è completo (servono i 4 gradi di base per ogni statistica). Non è stato modificato nulla.';
  end if;
end $$;

insert into public.game_skills (id, name, kind, stat, slot, tier, price_bc, min_level, p_for, p_des, p_vig, p_spi, p_frt, descr) values
  ('sk_for_5','Braccio del Colosso','perm','for',null,5,25000,100,15,0,0,0,0,'Allenamento permanente: +15% Forza, per sempre.'),
  ('sk_for_6','Ira del Vulcano','perm','for',null,6,60000,170,18,0,0,0,0,'Allenamento permanente: +18% Forza, per sempre.'),
  ('sk_for_7','Colpo Leggendario','perm','for',null,7,150000,260,22,0,0,0,0,'Allenamento permanente: +22% Forza, per sempre.'),
  ('sk_for_8','Forza Divina','perm','for',null,8,400000,400,26,0,0,0,0,'Allenamento permanente: +26% Forza, per sempre.'),
  ('sk_des_5','Passo d''Ombra','perm','des',null,5,25000,100,0,15,0,0,0,'Allenamento permanente: +15% Destrezza, per sempre.'),
  ('sk_des_6','Lama del Vento','perm','des',null,6,60000,170,0,18,0,0,0,'Allenamento permanente: +18% Destrezza, per sempre.'),
  ('sk_des_7','Maestro del Tempo','perm','des',null,7,150000,260,0,22,0,0,0,'Allenamento permanente: +22% Destrezza, per sempre.'),
  ('sk_des_8','Sguardo del Fato','perm','des',null,8,400000,400,0,26,0,0,0,'Allenamento permanente: +26% Destrezza, per sempre.'),
  ('sk_vig_5','Cuore di Pietra','perm','vig',null,5,25000,100,0,0,15,0,0,'Allenamento permanente: +15% Vigore, per sempre.'),
  ('sk_vig_6','Tempra Immortale','perm','vig',null,6,60000,170,0,0,18,0,0,'Allenamento permanente: +18% Vigore, per sempre.'),
  ('sk_vig_7','Vita Inesauribile','perm','vig',null,7,150000,260,0,0,22,0,0,'Allenamento permanente: +22% Vigore, per sempre.'),
  ('sk_vig_8','Corpo Indistruttibile','perm','vig',null,8,400000,400,0,0,26,0,0,'Allenamento permanente: +26% Vigore, per sempre.'),
  ('sk_spi_5','Fiamma Interiore','perm','spi',null,5,25000,100,0,0,0,15,0,'Allenamento permanente: +15% Spirito, per sempre.'),
  ('sk_spi_6','Mente Illuminata','perm','spi',null,6,60000,170,0,0,0,18,0,'Allenamento permanente: +18% Spirito, per sempre.'),
  ('sk_spi_7','Spirito Antico','perm','spi',null,7,150000,260,0,0,0,22,0,'Allenamento permanente: +22% Spirito, per sempre.'),
  ('sk_spi_8','Coscienza Cosmica','perm','spi',null,8,400000,400,0,0,0,26,0,'Allenamento permanente: +26% Spirito, per sempre.'),
  ('sk_frt_5','Muro di Volontà','perm','frt',null,5,25000,100,0,0,0,0,15,'Allenamento permanente: +15% Fortezza, per sempre.'),
  ('sk_frt_6','Egida Interiore','perm','frt',null,6,60000,170,0,0,0,0,18,'Allenamento permanente: +18% Fortezza, per sempre.'),
  ('sk_frt_7','Cittadella dell''Anima','perm','frt',null,7,150000,260,0,0,0,0,22,'Allenamento permanente: +22% Fortezza, per sempre.'),
  ('sk_frt_8','Fortezza Inviolabile','perm','frt',null,8,400000,400,0,0,0,0,26,'Allenamento permanente: +26% Fortezza, per sempre.')
on conflict (id) do update set name = excluded.name, tier = excluded.tier, price_bc = excluded.price_bc, min_level = excluded.min_level,
  p_for = excluded.p_for, p_des = excluded.p_des, p_vig = excluded.p_vig, p_spi = excluded.p_spi, p_frt = excluded.p_frt, descr = excluded.descr;

commit;
