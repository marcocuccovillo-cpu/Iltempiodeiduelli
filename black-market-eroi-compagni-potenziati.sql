-- =====================================================================================
--  La guerra degli Eroi — Compagni potenziati (migrazione 047)
--  1. Livello massimo dei compagni: da 100 a 200 (impostazione game_pet_max_level).
--     Un compagno continua a non poter superare il livello del suo eroe.
--  2. Bonus dei compagni RADDOPPIATI: Forza, Destrezza, Vigore, Spirito, Fortezza e XP.
--     Le azioni boss al giorno passano da +1 a +2.
--     La RICARICA DELL'ENERGIA resta com'è: stesso valore e stessa crescita (piena al livello 100).
--  Nessuno perde nulla: a ogni livello un bonus vale almeno quanto prima, di solito di più
--  (a livello 100 fino al 25% in più, a livello 200 il doppio).
--  Il valore di partenza di ogni bonus viene salvato in «base_max»: per questo il file si può
--  rieseguire senza raddoppiare due volte. Annulla con black-market-eroi-compagni-potenziati-down.sql
-- =====================================================================================
begin;

alter table public.game_pet_lines add column if not exists base_max smallint;
update public.game_pet_lines set base_max = max_value where base_max is null;      -- solo la prima volta (e per eventuali compagni aggiunti dopo)

update public.game_pet_lines set max_value = case
    when effect in ('for','des','vig','spi','frt','xp') then base_max * 2
    when effect = 'actions' then base_max + 1
    else base_max end;                                                                -- 'fights' = ricarica energia: invariata

-- valore di un bonus a un certo livello del compagno:
--   · ricarica dell'energia: come prima (piena al livello 100);
--   · tutti gli altri: la nuova curva fino al livello massimo, ma MAI meno di quanto valeva prima a quel livello.
create or replace function public._game_pet_line_value(p_max integer, p_base integer, p_effect text, p_unlock integer, p_level integer) returns integer
language sql stable security definer set search_path = public as $$
  select case when p_effect = 'fights' then public._game_pet_value(p_max, p_unlock, p_level, least(100, public._game_pet_max_level()))
              else greatest(public._game_pet_value(coalesce(p_base, p_max), p_unlock, p_level, least(100, public._game_pet_max_level())),
                            public._game_pet_value(p_max, p_unlock, p_level, public._game_pet_max_level())) end $$;
revoke all on function public._game_pet_line_value(integer, integer, text, integer, integer) from public, anon, authenticated;
do $do$
declare fn regprocedure; def text; n integer := 0;
  old constant text := 'public._game_pet_value(ln.max_value, ln.unlock_level, hp.level, public._game_pet_max_level())';
  new constant text := 'public._game_pet_line_value(ln.max_value, ln.base_max, ln.effect, ln.unlock_level, hp.level)';
begin
  foreach fn in array array['public._game_pet_bonus(uuid)', 'public._game_pet_card(uuid)', 'public.game_pet_state()']::regprocedure[] loop
    def := pg_get_functiondef(fn);
    if position(old in def) > 0 then execute replace(def, old, new); n := n + 1; end if;
    if position(new in pg_get_functiondef(fn)) = 0 then raise exception 'Funzione % non aggiornata: mandami questo messaggio', fn; end if;
  end loop;
  raise notice 'Funzioni dei compagni aggiornate: %', n;
end $do$;

update public.system_settings set value_int = 200,
       description = 'Pet: livello massimo di un pet (i bonus raggiungono il valore pieno a questo livello)'
 where key = 'game_pet_max_level' and value_int < 200;

commit;

-- conferma
select 'OK — livello massimo ' || (select value_int from public.system_settings where key = 'game_pet_max_level')
    || ' · bonus più alto ' || (select max(max_value) from public.game_pet_lines where effect <> 'fights') || '%'
    || ' · ricarica energia invariata: ' || (select bool_and(max_value = base_max) from public.game_pet_lines where effect = 'fights') as risultato;
