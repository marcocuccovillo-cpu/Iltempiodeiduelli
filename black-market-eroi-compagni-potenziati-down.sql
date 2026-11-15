-- Annulla la migrazione 047: livello massimo dei compagni di nuovo 100 e bonus ai valori di prima.
-- I compagni già saliti oltre il 100 conservano il livello, ma i bonus tornano quelli del livello 100.
begin;
update public.system_settings set value_int = 100 where key = 'game_pet_max_level';
do $do$
declare fn regprocedure; def text;
  old constant text := 'public._game_pet_value(ln.max_value, ln.unlock_level, hp.level, public._game_pet_max_level())';
  new constant text := 'public._game_pet_line_value(ln.max_value, ln.base_max, ln.effect, ln.unlock_level, hp.level)';
begin
  foreach fn in array array['public._game_pet_bonus(uuid)', 'public._game_pet_card(uuid)', 'public.game_pet_state()']::regprocedure[] loop
    def := pg_get_functiondef(fn); if position(new in def) > 0 then execute replace(def, new, old); end if;
  end loop;
end $do$;
drop function if exists public._game_pet_line_value(integer, integer, text, integer, integer);
update public.game_pet_lines set max_value = base_max where base_max is not null;
alter table public.game_pet_lines drop column if exists base_max;
commit;
