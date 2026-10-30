-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione 035: correzione del bug «cambio un oggetto che velocizza l'energia e perdo energia».
-- Da eseguire UNA volta nel SQL Editor di Supabase, dopo le migrazioni degli Eroi (serve almeno black-market-eroi-v2.sql).
-- Si può rieseguire senza danni.
--
-- IL BUG
--  L'energia di un eroe si calcola come «energia salvata + ore passate dall'ultimo salvataggio × velocità di recupero di ADESSO».
--  Gli oggetti con «+duelli» (gli strumenti) rendono il recupero più veloce (+25% a punto). Cambiando oggetto, la nuova velocità veniva
--  applicata con effetto retroattivo a tutto il tempo già passato: togliendo l'oggetto veloce l'energia già accumulata «scendeva»,
--  e alla prima azione (un duello, un dungeon) il valore più basso veniva salvato: la perdita diventava definitiva anche rimettendo l'oggetto.
--
-- LA CORREZIONE
--  Prima di ogni cambio di equipaggiamento (indossare, sostituire, togliere un oggetto) l'energia maturata fino a quel momento viene
--  «incassata» alla velocità di allora: da lì in poi la nuova velocità vale solo per il tempo futuro. Vale anche se un amministratore
--  cambia il «+duelli» di un oggetto del catalogo. È un controllo del database (trigger), quindi vale per qualunque funzione cambi
--  l'equipaggiamento. Nessuna colonna o tabella nuova. Nessun movimento di BC.
--  NON recupera l'energia già persa in passato dai giocatori (non è ricostruibile).
--  ANNULLAMENTO: black-market-eroi-energia-oggetti-down.sql
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.game_equipped') is null or to_regclass('public.game_items') is null
     or to_regprocedure('public._game_energy_of(uuid)') is null or to_regprocedure('public._game_energy_rate(uuid)') is null then
    raise exception 'Prima esegui le migrazioni degli Eroi (black-market-eroi-v2.sql e successive): manca il calcolo dell''energia. Non è stato modificato nulla.';
  end if;
end $$;

-- incassa l'energia maturata fino ad ora (alla velocità in vigore adesso)
create or replace function public._game_energy_checkpoint(p_user uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  update public.game_heroes set energy = public._game_energy_of(p_user), energy_at = now() where user_id = p_user;
end $$;

-- cambia l'equipaggiamento di un eroe: PRIMA del cambio si incassa l'energia
create or replace function public._trg_equipped_energy() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public._game_energy_checkpoint(case when tg_op = 'DELETE' then old.user_id else new.user_id end);
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists game_equipped_energy on public.game_equipped;
create trigger game_equipped_energy before insert or update or delete on public.game_equipped for each row execute function public._trg_equipped_energy();

-- un amministratore cambia il «+duelli» di un oggetto: prima si incassa l'energia di chi lo indossa
create or replace function public._trg_items_energy() returns trigger language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  if old.extra_fights is distinct from new.extra_fights then
    for u in select e.user_id from public.game_equipped e where e.item_id = old.id loop
      perform public._game_energy_checkpoint(u);
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists game_items_energy on public.game_items;
create trigger game_items_energy before update of extra_fights on public.game_items for each row execute function public._trg_items_energy();

revoke all on function public._game_energy_checkpoint(uuid), public._trg_equipped_energy(), public._trg_items_energy() from public, anon, authenticated;
commit;
