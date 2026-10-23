-- ANNULLAMENTO DELLA MIGRAZIONE 025: torna il livello massimo fisso a 9999. Non tocca livelli, XP o energia già assegnati.
begin;

drop trigger if exists game_level_cap_check on public.system_settings;
drop function if exists public._game_cap_check();

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
  if gained > 0 then      -- salire di livello ricarica la batteria dell'energia al 100%
    update public.game_heroes set energy = public._game_energy_max(), energy_at = now() where user_id = p_user;
  end if;
  return jsonb_build_object('xp', add_, 'levels', gained, 'level', h.level, 'energy_full', gained > 0);
end $$;

drop function if exists public._game_level_cap();
delete from public.system_settings where key = 'game_level_cap';
revoke all on function public._game_add_xp(uuid, bigint) from public, anon, authenticated;
commit;
