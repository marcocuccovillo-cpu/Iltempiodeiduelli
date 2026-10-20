-- =====================================================================
-- MIGRAZIONE 008 — BLACK MARKET SHOP
-- Da eseguire nel SQL Editor di Supabase DOPO 001…007. Si può rieseguire senza danni.
--
-- Cosa fa: uno Shop dove i BC già esistenti si spendono per premi virtuali PERMANENTI (pet, titoli, cornici, aure,
-- emblemi, effetti), da collezionare ed equipaggiare sul profilo. Aggiunge:
--   * shop_items      catalogo (prezzi e testi modificabili solo dall'amministratore, mai cancellato)
--   * shop_purchases  registro acquisti = inventario (solo inserimenti, mai modificato né cancellato)
--   * shop_equipped   un oggetto equipaggiato per categoria (solo di oggetti posseduti)
--   * shop_equipped_v vista pubblica con gli oggetti equipaggiati (per i profili pubblici)
--   * funzioni shop_buy / shop_equip / shop_unequip e admin_shop_save_item
-- Il pagamento passa dall'UNICO punto che muove i saldi (_ledger_move) con un nuovo tipo di movimento, 'shop_purchase':
-- addebito e assegnazione dell'oggetto avvengono nella stessa transazione, quindi riescono insieme o falliscono insieme.
-- Cosa NON fa: non crea BC (l'unico effetto sul saldo è un addebito), non permette scambi tra utenti, non tocca taglie,
-- Ladder, premi, riscossioni né le funzioni economiche esistenti. Gli oggetti posseduti restano per sempre anche se il
-- premio viene disattivato; i prezzi pagati restano scritti negli acquisti e nel registro.
-- Annullamento: black-market-shop-down.sql (conserva acquisti e movimenti già avvenuti).
-- =====================================================================
begin;

-- Nuovo tipo di movimento nel registro contabile (unico cambiamento a una regola esistente)
alter table public.ledger_entries drop constraint if exists ledger_entries_kind_check;
alter table public.ledger_entries add constraint ledger_entries_kind_check
  check (kind in ('initial_bonus','bounty_stake','bounty_payout','bounty_refund','participation_reward','admin_adjustment','ladder_reward','shop_purchase'));

insert into public.system_settings (key, value_int, description) values
 ('shop_enabled', 1, 'Shop: 1 = acquisti aperti, 0 = acquisti chiusi (equipaggiare resta possibile)')
on conflict (key) do nothing;

-- ---------- Tabelle ----------
create table if not exists public.shop_items (
  id text primary key check (id ~ '^[a-z0-9_]{3,40}$'),
  name text not null check (char_length(btrim(name)) between 2 and 40),
  description text not null check (char_length(btrim(description)) between 5 and 240),
  category text not null check (category in ('pet','title','frame','aura','emblem','effect')),
  rarity text not null check (rarity in ('common','rare','epic','legendary','mythic')),
  price integer not null,
  asset text not null check (asset ~ '^[a-z0-9_]{2,40}$'),     -- chiave della grafica (vedi shop-art.js)
  active boolean not null default true,
  sort integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- fasce di prezzo per rarità
  constraint shop_items_price_by_rarity check (
       (rarity = 'common'    and price between 2 and 49)
    or (rarity = 'rare'      and price between 50 and 149)
    or (rarity = 'epic'      and price between 150 and 349)
    or (rarity = 'legendary' and price between 350 and 699)
    or (rarity = 'mythic'    and price between 700 and 1000))
);

create table if not exists public.shop_purchases (            -- registro acquisti = inventario: SOLO inserimenti
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  item_id text not null references public.shop_items(id) on delete restrict,
  category text not null,                                       -- copia della categoria al momento dell'acquisto
  item_name text not null,                                      -- copia del nome
  price_paid integer not null check (price_paid > 0),           -- prezzo realmente addebitato
  client_request_id text not null check (char_length(client_request_id) >= 8),
  created_at timestamptz not null default clock_timestamp(),
  unique (user_id, item_id),                                    -- ogni oggetto si possiede una sola volta
  unique (user_id, client_request_id),                          -- richiesta duplicata = un solo acquisto
  unique (user_id, item_id, category)
);
create index if not exists shop_purchases_user_idx on public.shop_purchases (user_id, created_at desc);
create index if not exists shop_purchases_item_idx on public.shop_purchases (item_id);

create table if not exists public.shop_equipped (
  user_id uuid not null references public.profiles(id) on delete restrict,
  category text not null check (category in ('pet','title','frame','aura','emblem','effect')),
  item_id text not null,
  equipped_at timestamptz not null default now(),
  primary key (user_id, category),                              -- un solo oggetto per categoria
  foreign key (user_id, item_id, category) references public.shop_purchases (user_id, item_id, category) on delete restrict
);                                                              -- si può equipaggiare solo ciò che si possiede

drop trigger if exists shop_items_no_delete on public.shop_items;
create trigger shop_items_no_delete before delete on public.shop_items for each row execute function public._no_delete();
drop trigger if exists shop_purchases_immutable on public.shop_purchases;
create trigger shop_purchases_immutable before update or delete on public.shop_purchases for each row execute function public._immutable();
drop trigger if exists shop_purchases_no_truncate on public.shop_purchases;
create trigger shop_purchases_no_truncate before truncate on public.shop_purchases for each statement execute function public._immutable();

create or replace view public.shop_equipped_v as
  select e.user_id, e.category, e.item_id, i.name, i.description, i.rarity, i.asset, e.equipped_at
  from public.shop_equipped e join public.shop_items i on i.id = e.item_id;

-- ---------- Funzioni ----------
-- Acquisto: controlli, addebito e assegnazione nella stessa transazione.
create or replace function public.shop_buy(p_item text, p_request_id text, p_expected_price integer default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
        it public.shop_items%rowtype; pr public.shop_purchases%rowtype; v_id uuid := gen_random_uuid(); v_bal integer;
begin
  perform 1 from public.wallets where user_id = v_me for update;                 -- serializza le richieste dello stesso utente
  if coalesce(public._setting('shop_enabled'), 1) <> 1 then raise exception 'Lo Shop è chiuso al momento'; end if;
  if p_request_id is null or char_length(p_request_id) < 8 then raise exception 'Richiesta non valida'; end if;
  select * into pr from public.shop_purchases where user_id = v_me and client_request_id = p_request_id;
  if found then                                                                   -- richiesta duplicata: nessun secondo addebito
    return jsonb_build_object('purchase_id', pr.id, 'item', pr.item_id, 'price', pr.price_paid, 'already', true,
                              'balance', (select balance from public.wallets where user_id = v_me));
  end if;
  select * into it from public.shop_items where id = p_item for share;
  if not found then raise exception 'Premio inesistente'; end if;
  if not it.active then raise exception 'Questo premio non è disponibile'; end if;
  if p_expected_price is not null and p_expected_price <> it.price then raise exception 'Il prezzo è cambiato: ricarica lo Shop'; end if;
  if exists (select 1 from public.shop_purchases where user_id = v_me and item_id = it.id) then raise exception 'Possiedi già questo premio'; end if;
  insert into public.shop_purchases (id, user_id, item_id, category, item_name, price_paid, client_request_id)
    values (v_id, v_me, it.id, it.category, it.name, it.price, p_request_id);
  v_bal := public._ledger_move(v_me, -it.price, 'shop_purchase', 'shop_purchase', v_id, 'shop:' || v_id, 'Shop: ' || it.name);   -- rifiuta se il saldo non basta
  return jsonb_build_object('purchase_id', v_id, 'item', it.id, 'price', it.price, 'already', false, 'balance', v_bal);
end $$;

create or replace function public.shop_equip(p_item text) returns void
language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._need_role(array['user','organizer','admin']::public.app_role[]); pr public.shop_purchases%rowtype;
begin
  select * into pr from public.shop_purchases where user_id = v_me and item_id = p_item;
  if not found then raise exception 'Non possiedi questo premio'; end if;
  insert into public.shop_equipped (user_id, category, item_id) values (v_me, pr.category, pr.item_id)
    on conflict (user_id, category) do update set item_id = excluded.item_id, equipped_at = now();
end $$;

create or replace function public.shop_unequip(p_category text) returns void
language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
begin
  delete from public.shop_equipped where user_id = v_me and category = p_category;   -- l'oggetto resta nell'inventario
end $$;

-- Amministrazione: crea o modifica un premio (mai cancellarlo). Ogni modifica finisce nel registro di audit.
create or replace function public.admin_shop_save_item(p_id text, p_name text, p_description text, p_category text, p_rarity text,
  p_price integer, p_asset text, p_active boolean, p_sort integer, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o public.shop_items%rowtype; n public.shop_items%rowtype;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into o from public.shop_items where id = p_id for update;
  if not found then
    insert into public.shop_items (id, name, description, category, rarity, price, asset, active, sort)
      values (p_id, btrim(p_name), btrim(p_description), p_category, p_rarity, p_price, p_asset, coalesce(p_active, true), coalesce(p_sort, 100));
    select * into n from public.shop_items where id = p_id;
    perform public._audit(v, 'shop_item_create', 'shop_item', p_id, null, to_jsonb(n), btrim(p_reason));
  else
    if p_category is distinct from o.category then raise exception 'La categoria di un premio non si può cambiare'; end if;
    update public.shop_items set name = btrim(p_name), description = btrim(p_description), rarity = p_rarity, price = p_price, asset = p_asset,
           active = coalesce(p_active, o.active), sort = coalesce(p_sort, o.sort), updated_at = now() where id = p_id;
    select * into n from public.shop_items where id = p_id;
    perform public._audit(v, case when o.active and not n.active then 'shop_item_deactivate' when not o.active and n.active then 'shop_item_activate' else 'shop_item_update' end,
                          'shop_item', p_id, to_jsonb(o), to_jsonb(n), btrim(p_reason));
  end if;
end $$;

-- ---------- Row Level Security e permessi ----------
alter table public.shop_items enable row level security;
alter table public.shop_purchases enable row level security;
alter table public.shop_equipped enable row level security;
drop policy if exists shop_items_read on public.shop_items;
create policy shop_items_read on public.shop_items for select to authenticated using (true);
drop policy if exists shop_purchases_read on public.shop_purchases;
create policy shop_purchases_read on public.shop_purchases for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists shop_equipped_read on public.shop_equipped;
create policy shop_equipped_read on public.shop_equipped for select to authenticated using (true);   -- gli oggetti equipaggiati sono pubblici (profilo)

revoke all on public.shop_items, public.shop_purchases, public.shop_equipped, public.shop_equipped_v from public, anon, authenticated;
grant select on public.shop_items, public.shop_purchases, public.shop_equipped, public.shop_equipped_v to authenticated;
revoke all on function public.shop_buy(text, text, integer), public.shop_equip(text), public.shop_unequip(text),
  public.admin_shop_save_item(text, text, text, text, text, integer, text, boolean, integer, text) from public, anon, authenticated;
grant execute on function public.shop_buy(text, text, integer), public.shop_equip(text), public.shop_unequip(text),
  public.admin_shop_save_item(text, text, text, text, text, integer, text, boolean, integer, text) to authenticated;

-- ---------- Catalogo iniziale (39 premi; modificabile dall'amministrazione senza toccare il codice) ----------
insert into public.shop_items (id, name, description, category, rarity, price, asset, sort) values
 ('titolo_novizio', 'Novizio del Tempio', 'Un titolo semplice sotto il tuo nome: ogni leggenda comincia da qui.', 'title', 'common', 2, 'titolo_novizio', 10),
 ('pet_gelatina', 'Gelatina Cucciola', 'Una piccola creatura gelatinosa che saltella accanto al tuo nome.', 'pet', 'common', 5, 'pet_gelatina', 20),
 ('titolo_notturno', 'Duellante Notturno', 'Per chi gioca quando il Tempio è silenzioso.', 'title', 'common', 8, 'titolo_notturno', 30),
 ('emblema_carta', 'Emblema della Carta', 'Un piccolo distintivo a forma di carta, accanto al tuo nickname.', 'emblem', 'common', 10, 'emblema_carta', 40),
 ('cornice_pietra', 'Cornice di Pietra', 'Un anello di roccia grezza attorno al tuo avatar.', 'frame', 'common', 12, 'cornice_pietra', 50),
 ('titolo_collezionista', 'Collezionista', 'Mostra che sai riconoscere un buon affare.', 'title', 'common', 15, 'titolo_collezionista', 60),
 ('pet_fantasmino', 'Fantasmino Curioso', 'Un fantasmino timido che ti segue fluttuando.', 'pet', 'common', 18, 'pet_fantasmino', 70),
 ('emblema_stella', 'Emblema Stellare', 'Una stella a cinque punte che brilla piano.', 'emblem', 'common', 20, 'emblema_stella', 80),
 ('cornice_bronzo', 'Cornice di Bronzo', 'Un bordo di bronzo lucidato, sobrio e solido.', 'frame', 'common', 25, 'cornice_bronzo', 90),
 ('aura_bagliore', 'Bagliore Tenue', 'Un alone morbido e discreto attorno al tuo profilo.', 'aura', 'common', 30, 'aura_bagliore', 100),
 ('fx_scintille', 'Scintille', 'Minuscole scintille dorate che salgono dal tuo profilo.', 'effect', 'common', 35, 'fx_scintille', 110),
 ('fx_luce_pulsante', 'Luce Pulsante', 'Un bagliore che respira lentamente sullo sfondo del profilo.', 'effect', 'rare', 60, 'fx_luce_pulsante', 120),
 ('emblema_teschio', 'Emblema del Teschio', 'Un teschio stilizzato: il segno dei duellanti più temuti.', 'emblem', 'rare', 65, 'emblema_teschio', 130),
 ('cornice_runica', 'Cornice Runica', 'Rune d''argento incise attorno all''avatar.', 'frame', 'rare', 75, 'cornice_runica', 140),
 ('titolo_cacciatore', 'Cacciatore di Taglie', 'Il titolo di chi non lascia scappare un bersaglio.', 'title', 'rare', 80, 'titolo_cacciatore', 150),
 ('pet_draghetto_ebano', 'Draghetto d''Ebano', 'Un piccolo drago nero dagli occhi rossi, già pieno di carattere.', 'pet', 'rare', 90, 'pet_draghetto_ebano', 160),
 ('cornice_neon', 'Cornice Neon', 'Un anello luminoso che pulsa di luce ciano.', 'frame', 'rare', 100, 'cornice_neon', 170),
 ('aura_ciano', 'Aura Ciano', 'Un velo di energia ciano che avvolge il profilo.', 'aura', 'rare', 110, 'aura_ciano', 180),
 ('pet_apprendista_ombra', 'Apprendista Ombra', 'Un giovane mago incappucciato con un bastone stellato.', 'pet', 'rare', 120, 'pet_apprendista_ombra', 190),
 ('emblema_occhio_arcano', 'Emblema dell''Occhio Arcano', 'Un occhio che tutto vede, racchiuso in un triangolo di luce.', 'emblem', 'epic', 150, 'emblema_occhio_arcano', 200),
 ('titolo_signore_ombre', 'Signore delle Ombre', 'Un titolo scuro e prestigioso, con riflessi viola.', 'title', 'epic', 170, 'titolo_signore_ombre', 210),
 ('cornice_fiamma', 'Cornice di Fiamma', 'Un anello di fuoco vivo che danza attorno all''avatar.', 'frame', 'epic', 180, 'cornice_fiamma', 220),
 ('pet_sentinella_millenaria', 'Sentinella Millenaria', 'Un guardiano di pietra e oro con un solo occhio sempre aperto.', 'pet', 'epic', 200, 'pet_sentinella_millenaria', 230),
 ('aura_vortice_viola', 'Vortice Viola', 'Un vortice di energia viola che gira attorno al profilo.', 'aura', 'epic', 220, 'aura_vortice_viola', 240),
 ('pet_drago_spettrale', 'Drago Spettrale', 'Un drago fantasma, trasparente e gelido, dagli occhi azzurri.', 'pet', 'epic', 240, 'pet_drago_spettrale', 250),
 ('fx_braci', 'Braci Ardenti', 'Braci rosse che salgono dal profilo come da un falò.', 'effect', 'epic', 260, 'fx_braci', 260),
 ('pet_fenice_oscura', 'Fenice Oscura', 'Una fenice nera dalle fiamme viola, rinata dalle ceneri.', 'pet', 'epic', 290, 'pet_fenice_oscura', 270),
 ('emblema_corona', 'Corona del Tempio', 'Una corona dorata: l''emblema di chi ha lasciato il segno.', 'emblem', 'legendary', 360, 'emblema_corona', 280),
 ('aura_sole_dorato', 'Sole Dorato', 'Raggi dorati che si irradiano dal tuo profilo.', 'aura', 'legendary', 380, 'aura_sole_dorato', 290),
 ('titolo_leggenda', 'Leggenda del Tempio', 'Il titolo che tutti vorrebbero leggere sotto il proprio nome.', 'title', 'legendary', 400, 'titolo_leggenda', 300),
 ('cornice_aurea_regale', 'Cornice Aurea Regale', 'Oro massiccio e gemme, con un riflesso che gira piano.', 'frame', 'legendary', 450, 'cornice_aurea_regale', 310),
 ('pet_drago_abissi', 'Drago degli Abissi', 'Un drago marino dalle scaglie blu notte e dagli occhi bioluminescenti.', 'pet', 'legendary', 480, 'pet_drago_abissi', 320),
 ('pet_drago_astrale', 'Drago Astrale', 'Un drago di luce stellare, con ali di costellazioni.', 'pet', 'legendary', 550, 'pet_drago_astrale', 330),
 ('pet_fenice_celestiale', 'Fenice Celestiale', 'Una fenice bianca e dorata, simbolo di rinascita e di luce.', 'pet', 'legendary', 620, 'pet_fenice_celestiale', 340),
 ('titolo_sovrano_apocalisse', 'Sovrano dell''Apocalisse', 'Un titolo che incute timore, in lettere di fuoco e viola.', 'title', 'mythic', 720, 'titolo_sovrano_apocalisse', 350),
 ('pet_drago_ombre_eterne', 'Drago delle Ombre Eterne', 'Un drago nato dal buio, avvolto da ombre che non si dissolvono mai.', 'pet', 'mythic', 780, 'pet_drago_ombre_eterne', 360),
 ('aura_eclissi', 'Aura dell''Eclissi', 'Un''eclissi totale attorno al tuo profilo, con una corona di fuoco.', 'aura', 'mythic', 850, 'aura_eclissi', 370),
 ('cornice_eclissi', 'Cornice dell''Eclissi', 'Un anello nero incoronato da fiamme rosso-viola.', 'frame', 'mythic', 900, 'cornice_eclissi', 380),
 ('pet_drago_apocalittico', 'Drago Apocalittico', 'Il boss finale: armatura nera, corna imponenti, occhi incandescenti, ali gigantesche e fiamme rosso-viola. Il premio più prestigioso del Tempio.', 'pet', 'mythic', 1000, 'pet_drago_apocalittico', 390)
on conflict (id) do nothing;

commit;
