-- =====================================================================
-- MIGRAZIONE 024 — La guerra degli Eroi: ricarica dell'energia, SOLO per l'amministratore
--   game_admin_refill_energy() riporta al 100% l'energia dell'eroe di CHI LA CHIAMA, ma solo se è un amministratore attivo.
--   Moderatori, organizzatori, duellanti e amministratori sospesi ricevono un errore e non cambia nulla.
--   Ogni uso finisce nell'audit (energia prima e dopo). Nella pagina la voce compare solo all'amministratore (scheda Eroe).
-- Da eseguire in Supabase (SQL Editor) DOPO la 023. Si può rieseguire. Non tocca BC, registro, livelli o XP.
-- =====================================================================
begin;

create or replace function public.game_admin_refill_energy() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); v_old numeric; v_max integer := public._game_energy_max();
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  select public._game_energy_of(v) into v_old;
  update public.game_heroes set energy = v_max, energy_at = now() where user_id = v;
  perform public._audit(v, 'admin_game_refill_energy', 'game_hero', v::text, jsonb_build_object('energy', round(v_old, 2)), jsonb_build_object('energy', v_max), 'Ricarica energia (amministratore)');
  return jsonb_build_object('energy', v_max, 'before', round(v_old, 2));
end $$;

revoke all on function public.game_admin_refill_energy() from public, anon, authenticated;
grant execute on function public.game_admin_refill_energy() to authenticated;
commit;
