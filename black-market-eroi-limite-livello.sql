-- =====================================================================
-- MIGRAZIONE 025 — La guerra degli Eroi: limite di livello impostabile dall'amministratore (da 100 a 9999)
--   * Nuova impostazione «game_level_cap» (Admin › Impostazioni economiche › «Livello massimo degli eroi»), predefinita 9999
--     = tutto come prima. Il valore deve stare tra 100 e 9999: il controllo è nel database, quindi vale per qualsiasi via di modifica.
--   * Arrivati al limite l'eroe non sale più (resta al livello massimo, l'XP in eccesso si perde, il totale XP continua a contare).
--   * Abbassare il limite NON toglie livelli a nessuno: chi è già sopra il nuovo limite resta dov'è ma smette di salire.
--     Rialzando il limite tutti riprendono a salire da dove erano.
--   * Ogni modifica passa da admin_set_setting, quindi finisce nell'audit con autore e motivazione.
-- Da eseguire in Supabase (SQL Editor) DOPO la 024. Si può rieseguire. Non tocca BC, registro, livelli, XP o energia già assegnati.
-- =====================================================================
begin;

insert into public.system_settings (key, value_int, description) values
 ('game_level_cap', 9999, 'Eroi: livello massimo raggiungibile (da 100 a 9999)')
on conflict (key) do nothing;
update public.system_settings set description = 'Eroi: livello massimo raggiungibile (da 100 a 9999)' where key = 'game_level_cap';

-- limite in vigore: sempre un numero tra 100 e 9999 (anche se la riga mancasse o fosse stata alterata)
create or replace function public._game_level_cap() returns integer language sql stable security definer set search_path = public as $$
  select least(9999, greatest(100, coalesce((select value_int from public.system_settings where key = 'game_level_cap'), 9999))) $$;

-- validazione nel database: nessun client, funzione o SQL manuale può salvare un limite fuori da 100…9999
create or replace function public._game_cap_check() returns trigger language plpgsql as $$
begin
  if new.key = 'game_level_cap' and (new.value_int is null or new.value_int < 100 or new.value_int > 9999) then
    raise exception 'Il livello massimo deve essere un numero intero tra 100 e 9999';
  end if;
  return new;
end $$;
drop trigger if exists game_level_cap_check on public.system_settings;
create trigger game_level_cap_check before insert or update of key, value_int on public.system_settings
  for each row execute function public._game_cap_check();

-- XP: come nella 023 (ricarica dell'energia salendo di livello), ma con il limite impostabile al posto del 9999 fisso
create or replace function public._game_add_xp(p_user uuid, p_xp bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare h public.game_heroes%rowtype; pct integer; add_ bigint; gained integer := 0; cap integer := public._game_level_cap();
begin
  select * into h from public.game_heroes where user_id = p_user for update;
  if not found then raise exception 'Eroe inesistente'; end if;
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
  if gained > 0 then      -- salire di livello ricarica la batteria dell'energia al 100%
    update public.game_heroes set energy = public._game_energy_max(), energy_at = now() where user_id = p_user;
  end if;
  return jsonb_build_object('xp', add_, 'levels', gained, 'level', h.level, 'energy_full', gained > 0, 'cap', cap);
end $$;

revoke all on function public._game_level_cap() from public, anon, authenticated;
revoke all on function public._game_cap_check() from public, anon, authenticated;
revoke all on function public._game_add_xp(uuid, bigint) from public, anon, authenticated;
commit;
