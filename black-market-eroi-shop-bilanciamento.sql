-- =====================================================================
-- MIGRAZIONE 038 — LA GUERRA DEGLI EROI: BILANCIAMENTO DELL'EQUIPAGGIAMENTO DELLO SHOP
-- Da eseguire in Supabase (SQL Editor) DOPO tutte le migrazioni precedenti.
--
-- Problema: le statistiche degli oggetti dello shop crescono molto meno di quelle dei dungeon. Dal livello 65 in su un oggetto
-- leggendario o mitico del mercante vale meno di un RARO di dungeon dello stesso livello (il mitico di livello 500 ne vale il 56%).
-- Regola nuova (la stessa curva dei dungeon): potenza di riferimento al livello L = 5,94 × L^0,568, cioè quanto vale in media un
-- oggetto RARO di dungeon di quel livello. Ogni oggetto dello shop riceve la potenza di riferimento × il fattore della sua rarità:
--     comune 0,85 · non comune 0,90 · raro 0,95 · epico 1,00 · leggendario 1,08 · mitico 1,20
--   Restano un gradino sotto le ricompense dei dungeon della stessa rarità (che si guadagnano giocando), ma battono sempre quelle
--   di rarità inferiore dello stesso livello.
--   Gli STRUMENTI dello shop hanno in più XP, azioni contro il boss e ricarica dell'energia: per loro il valore è il 60% di quello sopra.
-- Anche i due oggetti LEGGENDARI dei boss (livello 200 e 500), rimasti molto indietro, passano al fattore 1,15.
-- Come: le statistiche di ogni oggetto crescono in proporzione (resta la sua «personalità», es. arma = Forza + Destrezza);
-- nessun valore scende; bonus speciali (XP, azioni, ricarica energia), prezzi e livello richiesto restano identici.
-- Effetto immediato anche sugli oggetti già comprati e indossati (le statistiche si leggono dal catalogo).
-- I valori di prima sono salvati in game_items_bal_backup: black-market-eroi-shop-bilanciamento-down.sql li rimette.
-- Si può rieseguire (riparte sempre dai valori originali salvati).
-- =====================================================================
begin;

create table if not exists public.game_items_bal_backup (
  id text primary key references public.game_items(id),
  p_for smallint not null, p_des smallint not null, p_vig smallint not null, p_spi smallint not null, p_frt smallint not null,
  saved_at timestamptz not null default now()
);
alter table public.game_items_bal_backup enable row level security;
revoke all on public.game_items_bal_backup from public, anon, authenticated;

-- salva i valori originali (una volta sola: rieseguendo il file non si sovrascrivono)
insert into public.game_items_bal_backup (id, p_for, p_des, p_vig, p_spi, p_frt)
  select id, p_for, p_des, p_vig, p_spi, p_frt from public.game_items
   where source = 'shop' or (source = 'boss' and rarity = 'leggendario')
on conflict (id) do nothing;

do $$
declare r record; v_tot int; v_target int; v_new int[]; v_old int[]; i int; v_sum int; v_big int; n int := 0;
begin
  for r in
    select g.id, g.slot, g.rarity, g.min_level, g.source, b.p_for, b.p_des, b.p_vig, b.p_spi, b.p_frt
      from public.game_items g join public.game_items_bal_backup b on b.id = g.id
  loop
    v_old := array[r.p_for, r.p_des, r.p_vig, r.p_spi, r.p_frt];
    v_tot := r.p_for + r.p_des + r.p_vig + r.p_spi + r.p_frt;
    if v_tot <= 0 then continue; end if;
    v_target := round(5.94 * power(r.min_level, 0.568)
      * case when r.source = 'boss' then 1.15
             else case r.rarity when 'comune' then 0.85 when 'non_comune' then 0.90 when 'raro' then 0.95 when 'epico' then 1.00
                                when 'leggendario' then 1.08 when 'mitico' then 1.20 else 1 end end
      * case when r.slot = 'tool' and r.source = 'shop' then 0.60 else 1 end);
    v_target := greatest(v_target, v_tot);                    -- nessun oggetto diventa più debole
    v_new := array[0,0,0,0,0]; v_sum := 0; v_big := 1;
    for i in 1..5 loop
      v_new[i] := round(v_old[i]::numeric * v_target / v_tot);
      v_sum := v_sum + v_new[i];
      if v_old[i] > v_old[v_big] then v_big := i; end if;
    end loop;
    v_new[v_big] := v_new[v_big] + (v_target - v_sum);        -- arrotondamenti: il totale torna esatto sulla statistica principale
    update public.game_items set p_for = v_new[1], p_des = v_new[2], p_vig = v_new[3], p_spi = v_new[4], p_frt = v_new[5]
     where id = r.id and (p_for, p_des, p_vig, p_spi, p_frt) is distinct from (v_new[1], v_new[2], v_new[3], v_new[4], v_new[5]);
    if found then n := n + 1; end if;
  end loop;
  raise notice 'Bilanciamento shop: % oggetti aggiornati', n;
end $$;

commit;
