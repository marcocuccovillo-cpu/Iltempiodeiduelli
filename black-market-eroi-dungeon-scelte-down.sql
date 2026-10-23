-- ANNULLAMENTO DELLA MIGRAZIONE 026 (La guerra degli Eroi: 30 dungeon a scelte).
-- Rimette i dungeon come erano dopo la 025: i soli 25 dungeon classici.
--   · le partite a scelte ancora in corso vengono chiuse (l'energia già spesa non torna indietro);
--   · i dungeon 26-55, i loro percorsi, finali scoperti, progressi e partite vengono tolti: senza il motore a scelte non si potrebbero giocare;
--   · i BC già guadagnati restano (il registro non si tocca; le righe «game_dungeon_reward» restano);
--   · gli oggetti esclusivi d26-d55 già vinti restano negli zaini dei giocatori e continuano a funzionare;
--   · tornano le funzioni della 017/023 per i dungeon classici (game_dungeon_start e game_dungeon_state originali).
-- Per rimettere tutto basta rieseguire black-market-eroi-dungeon-scelte.sql.
begin;

update public.game_runs set status = 'failed', finished_at = now() where status = 'active';

-- niente più partite, progressi e finali dei dungeon 26-55
delete from public.game_runs where dungeon_no in (select no from public.game_dungeons where kind = 'path');
delete from public.game_dungeon_progress where dungeon_no in (select no from public.game_dungeons where kind = 'path');
drop table if exists public.game_dungeon_endings;
drop table if exists public.game_dungeon_graphs;
-- gli oggetti restano, ma non sono più legati a un dungeon che non c'è più
update public.game_items set dungeon_no = null where id in (select item_id from public.game_dungeons where kind = 'path' and item_id is not null);
delete from public.game_dungeons where kind = 'path';

-- funzioni nuove
drop function if exists public.game_dungeon_choose(uuid, text);
drop function if exists public.game_dungeon_abandon(uuid);
drop function if exists public._game_dng_clash(jsonb, jsonb, numeric, numeric, integer);
drop function if exists public._game_dng_fx(jsonb, jsonb);
drop function if exists public._game_dng_advance(jsonb, jsonb, integer);
drop function if exists public._game_dng_view(uuid);
drop function if exists public._game_dng_settle(uuid, boolean, jsonb);
drop function if exists public._game_dng_expire_active();

-- le funzioni originali tornano al loro nome
drop function if exists public.game_dungeon_start(uuid);
drop function if exists public.game_dungeon_state();
alter function public._game_dng_start_classic(uuid) rename to game_dungeon_start;
alter function public._game_dng_state_base() rename to game_dungeon_state;

-- controllo originale (senza il blocco «dungeon in corso»)
CREATE OR REPLACE FUNCTION public._game_dng_check(p_user uuid, p_no integer, p_role text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- permessi come prima
revoke all on function public.game_dungeon_start(uuid), public.game_dungeon_state() from public, anon;
grant execute on function public.game_dungeon_start(uuid), public.game_dungeon_state() to authenticated;
revoke all on function public._game_dng_check(uuid, integer, text) from public, anon, authenticated;

-- tabelle e colonne
drop index if exists public.game_runs_active_idx;
alter table public.game_runs drop constraint if exists game_runs_status_chk;
alter table public.game_runs add constraint game_runs_status_check check (status in ('lobby','cleared','failed','cancelled'));
alter table public.game_runs drop column if exists state;
alter table public.game_runs drop column if exists last_move_at;
alter table public.game_dungeons drop constraint if exists game_dungeons_kind_chk;
alter table public.game_dungeons drop column if exists kind;

delete from public.system_settings where key = 'game_dng_path_minutes';

commit;
