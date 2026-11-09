-- =====================================================================
-- ANNULLAMENTO DELLA MIGRAZIONE 041 (Mappa dei terreni e Locanda)
-- Spegne la Mappa e la Locanda togliendo le funzioni. I tavoli dei dadi ancora aperti vengono chiusi e la posta torna a chi l'ha messa.
-- Le tabelle (chi possiede quali terreni, storico) NON vengono cancellate: riapplicando la 041 tutto torna com'era.
-- Per cancellare anche i dati, dopo questo file: drop table public.game_tavern_log, public.game_dice, public.game_tavern_round_got,
-- public.game_tavern_rounds, public.game_tavern_rest, public.game_tavern_presence, public.game_land_owners, public.game_land, public.game_map_regions;
-- =====================================================================
begin;
do $$ declare d record; begin
  if to_regclass('public.game_dice') is not null then
    for d in select * from public.game_dice where status = 'open' for update loop
      perform public._ledger_move(d.creator_id, d.stake, 'game_dice_refund', 'game_dice', null, 'dice:' || d.id || ':refund', 'Dadi: Locanda chiusa, posta restituita');
      update public.game_dice set status = 'cancelled', done_at = now() where id = d.id;
    end loop;
  end if;
end $$;
drop function if exists public.game_map_state();
drop function if exists public.game_land_buy(integer);
drop function if exists public.game_land_upgrade(integer);
drop function if exists public.game_land_collect();
drop function if exists public.game_tavern_state();
drop function if exists public.game_tavern_rest();
drop function if exists public.game_tavern_round();
drop function if exists public.game_dice_open(integer);
drop function if exists public.game_dice_cancel(bigint);
drop function if exists public.game_dice_join(bigint);
drop function if exists public._dice_expire();
drop function if exists public._tavern_log(uuid, text, text);
drop function if exists public._tavern_energy(uuid, integer);
drop function if exists public._map_check(uuid);
drop function if exists public._land_collect(uuid);
drop function if exists public._land_pending(uuid);
drop function if exists public._land_daily(uuid);
drop function if exists public._land_upcost(integer);
drop function if exists public._land_mult(integer);
delete from public.system_settings where key = 'game_map_enabled';
commit;
