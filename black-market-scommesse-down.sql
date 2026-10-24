-- =====================================================================
-- ANNULLAMENTO delle scommesse (black-market-scommesse.sql).
-- Prima di togliere tutto, le scommesse ancora APERTE vengono rimborsate per intero (nessun BC resta bloccato).
-- Lo storico delle scommesse già liquidate si perde con la tabella; i movimenti già scritti nel registro contabile restano (il registro
-- non si cancella) e anche i quattro tipi di movimento restano ammessi nel vincolo del registro: servono a quelle righe.
-- =====================================================================
begin;

do $$
declare b record; n integer := 0;
begin
  if to_regclass('public.bets') is not null then
    for b in select id, user_id, stake, returned from public.bets where status = 'open' order by user_id, id for update loop
      perform public._ledger_move(b.user_id, b.stake - b.returned, 'bet_refund', 'bet', b.id, 'betdown:' || b.id, 'Puntata restituita: scommesse disattivate');
      n := n + 1;
    end loop;
    if n > 0 then perform public._audit(null, 'bet_down_refund', 'bet', null, null, jsonb_build_object('refunded_bets', n), 'annullamento della migrazione scommesse'); end if;
  end if;
end $$;

drop trigger if exists bets_on_ladder_match on public.ladder_matches;
drop function if exists public.place_bet(uuid, uuid, integer, integer, text);
drop function if exists public.bet_markets();
drop function if exists public.bet_mine();
drop function if exists public.bet_sync();
drop function if exists public.bet_admin_stats();
drop function if exists public._bet_trg();
drop function if exists public._bet_reconcile(uuid);
drop function if exists public._bet_is_open(public.ladder_matches);
drop function if exists public._bet_closes_at(public.ladder_matches);
drop function if exists public._bet_quote(public.ladder_matches);
drop table if exists public.bets;
drop table if exists public.bet_windows;
delete from public.system_settings where key in ('bet_enabled','bet_margin_pct','bet_min_stake','bet_max_stake','bet_max_open','bet_min_games','bet_bounty_smooth','bet_pool_smooth','bet_close_minutes','bet_w_winrate','bet_w_bounty','bet_w_pool');

commit;
