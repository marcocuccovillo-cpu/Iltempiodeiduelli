-- =====================================================================
-- ANNULLAMENTO della migrazione 008 (black-market-shop.sql).
-- Cosa fa: toglie le funzioni dello Shop, la vista e l'impostazione shop_enabled.
-- Cosa NON fa (lo storico non si cancella mai):
--   * le tabelle shop_items, shop_purchases e shop_equipped RESTANO: catalogo, acquisti e inventari non vengono eliminati
--     (senza le funzioni nessuno può più comprare o equipaggiare, l'app mostra il Black Market senza Shop);
--   * i movimenti 'shop_purchase' già scritti nel registro contabile restano e i saldi restano come sono;
--     la regola sui tipi di movimento torna quella precedente ma vale solo per i NUOVI movimenti (constraint NOT VALID).
-- Per rimettere lo Shop basta rieseguire black-market-shop.sql: gli acquisti già fatti ricompaiono intatti.
-- =====================================================================
begin;
drop view if exists public.shop_equipped_v;
drop function if exists public.shop_buy(text, text, integer);
drop function if exists public.shop_equip(text);
drop function if exists public.shop_unequip(text);
drop function if exists public.admin_shop_save_item(text, text, text, text, text, integer, text, boolean, integer, text);
alter table public.ledger_entries drop constraint if exists ledger_entries_kind_check;
alter table public.ledger_entries add constraint ledger_entries_kind_check
  check (kind in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment','ladder_reward')) not valid;
delete from public.system_settings where key = 'shop_enabled';
commit;
