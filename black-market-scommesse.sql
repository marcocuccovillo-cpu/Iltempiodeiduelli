-- =====================================================================
-- IL TEMPIO DEI DUELLI — BLACK MARKET
-- Migrazione: SCOMMESSE sulle sfide Ladder (comprese quelle «per la taglia»).
-- Da eseguire UNA volta nel SQL Editor di Supabase, DOPO la Ladder e le sue migrazioni (serve public.ladder_matches).
-- Si può rieseguire senza danni. Annullamento: black-market-scommesse-down.sql.
--
-- Come funziona
--  * Tutti i duellanti possono puntare dei BC sulla vittoria di uno dei due sfidanti, finché la sfida è «in attesa» o «accettata».
--    Chi gioca la sfida NON può scommettere su di essa. Su una stessa sfida si possono fare PIÙ scommesse (anche sullo stesso duellante, o
--    sull'altro): ognuna è una scommessa a sé, con la quota di QUEL momento (che tiene conto anche delle puntate già fatte, comprese le tue),
--    fissata e pagata separatamente. Restano validi i limiti: puntata minima/massima per scommessa e massimo di scommesse aperte per utente.
--  * Le scommesse si chiudono appena la sfida ha un risultato inviato (o è conclusa, contestata, rifiutata, annullata). Il limite di tempo
--    dall'accettazione (bet_close_minutes) ora è SPENTO (0): si punta fino all'invio del risultato; l'amministratore può rimetterlo
--    (es. 10 = si punta solo nei primi 10 minuti dopo l'accettazione, per evitare puntate fatte guardando la partita).
--  * QUOTA (decimale, fissata al momento della puntata, mostrata prima di confermare). Tre segnali CONTANO INSIEME. Ognuno sposta la
--    probabilità di vittoria (in «log-odds», cioè in modo che le spinte si sommino senza mai superare 0–100%) con un peso scelto dall'admin:
--      logit(P) = peso_winrate·L_winrate + peso_bounty·L_bounty + peso_scommesse·L_scommesse     e poi   P = 1 / (1 + e^(−logit))
--      1) WIN RATE della Ladder nel formato della sfida: win rate = (vittorie + 0,5·pareggi + 1) / (partite + 2); formula «log5»
--         P(A) = wrA·(1−wrB) / (wrA·(1−wrB) + wrB·(1−wrA)); L_winrate = ln(P/(1−P)). Conta per intero quando ENTRAMBI hanno almeno
--         bet_min_games partite, in proporzione con meno partite, per nulla con zero partite. Peso bet_w_winrate (100% = intero).
--      2) BOUNTY VALUE: taglie attive su ciascuno. L_bounty = ln((taglie su A + s) / (taglie su B + s)), s = bet_bounty_smooth.
--         Chi ha più taglie addosso è considerato il favorito. Senza taglie vale 0. Peso bet_w_bounty (30%).
--      3) SCOMMESSE GIÀ PRESENTI su quella sfida: L_scommesse = ln((puntato su A + s) / (puntato su B + s)), s = bet_pool_smooth.
--         Più BC sono su un duellante, più è considerato il favorito e più la sua quota scende (sale quella dell'avversario): ogni
--         nuova puntata su A non può mai far salire la quota di A. Senza scommesse vale 0. Peso bet_w_pool (40%).
--      Un segnale senza dati non sposta nulla; senza nessun segnale (o con tutti i pesi a 0) la sfida è 50% e 50%.
--      La probabilità resta tra 5% e 95%; quota = 100·(1 − margine) / P (per difetto), mai sotto 1,05; il margine della casa è bet_margin_pct (10%).
--      L'elenco delle sfide mostra anche cosa dice ogni segnale e quanto ha spostato la stima, così si capisce da dove viene la quota.
--  * VINCITA: il sistema crea i BC: puntata × quota (arrotondata per difetto) accreditati automaticamente quando la sfida si chiude.
--    Se perde, la puntata è persa. Pareggio, sfida rifiutata/annullata/scaduta/annullata dall'admin: la puntata torna intera.
--  * Se l'admin CORREGGE il risultato di una sfida già chiusa, o la annulla, le scommesse vengono ricalcolate: si paga quel che manca
--    e si toglie ciò che era stato pagato di troppo, ma solo fino al saldo disponibile (come per i premi Ladder: niente saldi negativi).
--  * La liquidazione avviene dentro la chiusura della sfida (trigger), senza toccare le funzioni della Ladder. Se per qualunque motivo
--    fallisse, la sfida si chiude lo stesso e bet_sync() (chiamata dalla pagina Scommesse) liquida dopo.
--  * L'ADMIN vede tutte le scommesse (bet_admin_list): quelle ancora da pagare e, a parte, quelle già liquidate. Può REVOCARE un pagamento
--    quando vuole (bet_admin_revoke, con motivazione): i BC pagati vengono ripresi dal wallet dello scommettitore, ma solo fino al saldo
--    disponibile (niente saldi negativi: il resto resta scritto come «non recuperato»). Due modi: togliere tutto il pagamento (la puntata
--    resta persa) oppure «annulla e rimborsa» (si toglie solo la vincita e la puntata torna). Una scommessa revocata resta revocata:
--    nemmeno una successiva correzione del risultato la ripaga. Solo per scommesse già pagate (vinte o rimborsate), una volta sola.
--  * Ogni movimento di BC passa dal registro contabile (puntata, vincita, rimborso, correzione) e dall'audit.
--  Impostazioni (Admin → Impostazioni): bet_enabled, bet_margin_pct, bet_min_stake, bet_max_stake, bet_max_open, bet_min_games,
--  bet_bounty_smooth, bet_pool_smooth, bet_close_minutes, bet_w_winrate, bet_w_bounty, bet_w_pool. Nessun dato esistente cambia.
--  * Da una versione precedente (quote «a cascata»: win rate, altrimenti taglie, altrimenti scommesse): rieseguire questo file. Le scommesse
--    già piazzate restano com'erano (quota e criterio fissati); cambia solo il calcolo delle quote delle nuove puntate.
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.ladder_matches') is null or to_regclass('public.ladder_ratings') is null then
    raise exception 'Prima esegui le migrazioni della Ladder: mancano le tabelle ladder_matches / ladder_ratings. Non è stato modificato nulla.';
  end if;
end $$;

-- ---------- nuovi tipi di movimento nel registro (si aggiungono a quelli già presenti, qualunque siano) ----------
do $$
declare d text; kinds text[]; k text;
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.ledger_entries'::regclass and conname = 'ledger_entries_kind_check';
  if d is null then raise exception 'Vincolo ledger_entries_kind_check non trovato: la migrazione non può aggiornare i tipi di movimento'; end if;
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  foreach k in array array['bet_stake','bet_payout','bet_refund','bet_reversal'] loop
    if not (k = any (kinds)) then kinds := kinds || k; end if;
  end loop;
  alter table public.ledger_entries drop constraint ledger_entries_kind_check;
  execute 'alter table public.ledger_entries add constraint ledger_entries_kind_check check (kind in ('
    || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
end $$;

-- ---------- impostazioni ----------
insert into public.system_settings (key, value_int, description) values
 ('bet_enabled',       1,   'Scommesse sulle sfide Ladder: 1 = attive, 0 = spente (le scommesse già fatte vengono comunque liquidate)'),
 ('bet_margin_pct',    10,  'Scommesse: margine della casa sulle quote (%): più è alto, più le quote sono basse'),
 ('bet_min_stake',     10,  'Scommesse: puntata minima in BC'),
 ('bet_max_stake',     200, 'Scommesse: puntata massima in BC per singola scommessa'),
 ('bet_max_open',      5,   'Scommesse: massimo di scommesse aperte (non ancora liquidate) per utente'),
 ('bet_min_games',     3,   'Scommesse: partite minime di ENTRAMBI i duellanti nel formato per usare il win rate (sotto: si usa il bounty value)'),
 ('bet_bounty_smooth', 100, 'Scommesse: BC aggiunti alle taglie di ciascuno nel calcolo senza dati (più alto = quote più vicine a 50/50)'),
 ('bet_pool_smooth',   100, 'Scommesse: BC aggiunti a ciascun duellante nel calcolo dalle scommesse già presenti (più alto = le prime puntate spostano meno la quota)'),
 ('bet_close_minutes', 0,   'Scommesse: minuti dall''accettazione dopo i quali non si può più puntare (0 = fino all''invio del risultato)'),
 ('bet_w_winrate',     100, 'Scommesse: peso (in %) del win rate Ladder nel calcolo della quota (100 = intero, 0 = ignorato)'),
 ('bet_w_bounty',      30,  'Scommesse: peso (in %) del bounty value, cioè delle taglie attive sui duellanti, nel calcolo della quota (0 = ignorato)'),
 ('bet_w_pool',        40,  'Scommesse: peso (in %) delle scommesse già presenti sulla sfida nel calcolo della quota (0 = ignorato)')
on conflict (key) do nothing;
-- descrizioni aggiornate (i valori eventualmente già scelti dall'amministratore non cambiano)
update public.system_settings set description = 'Scommesse: partite di ENTRAMBI i duellanti nel formato a cui il win rate conta per intero (con meno partite conta in proporzione)' where key = 'bet_min_games';
update public.system_settings set description = 'Scommesse: BC aggiunti alle taglie di ciascun duellante nel calcolo del bounty value (più alto = le taglie spostano meno la quota)' where key = 'bet_bounty_smooth';
update public.system_settings set description = 'Scommesse: BC aggiunti alle puntate su ciascun duellante nel calcolo dalle scommesse già presenti (più alto = le prime puntate spostano meno la quota)' where key = 'bet_pool_smooth';

-- ---------- tabelle ----------
-- istante in cui la sfida è stata accettata (serve a chiudere le scommesse dopo N minuti); la scrive solo il trigger
create table if not exists public.bet_windows (
  match_id uuid primary key references public.ladder_matches(id),
  accepted_at timestamptz not null default clock_timestamp()
);

create table if not exists public.bets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  match_id uuid not null references public.ladder_matches(id),
  pick uuid not null references public.profiles(id),            -- il duellante su cui si punta la vittoria
  stake integer not null check (stake > 0),
  quota integer not null check (quota >= 100),                   -- quota decimale per 100 (235 = 2,35), fissata alla puntata
  basis text not null check (basis in ('winrate','bounty','bets','even')),
  prob_pct numeric(5,2) not null,                                -- probabilità stimata al momento della puntata
  status text not null default 'open' check (status in ('open','won','lost','refunded','revoked')),
  returned integer not null default 0 check (returned >= 0),     -- BC restituiti finora (vincita o rimborso)
  written_off integer not null default 0 check (written_off >= 0), -- BC non recuperabili in una correzione (saldo già speso)
  settle_seq integer not null default 0,
  client_request_id text not null,
  created_at timestamptz not null default clock_timestamp(),
  settled_at timestamptz,
  unique (user_id, client_request_id)
);
-- se la tabella esisteva già (versioni precedenti di questa migrazione): ammette anche i criteri «bets» e «mix» (i tre segnali insieme)
alter table public.bets drop constraint if exists bets_basis_check;
alter table public.bets add constraint bets_basis_check check (basis in ('winrate','bounty','bets','even','mix'));
-- più scommesse sulla stessa sfida: da una versione precedente (una sola per utente per sfida) si toglie il vincolo; solo quella volta il limite di tempo
-- di 10 minuti (valore predefinito di prima) passa a 0 (fino all'invio del risultato). Le scommesse già fatte non cambiano. Rieseguire non rimette nulla a posto: se l'amministratore
-- sceglie di nuovo un limite di tempo, resta quello.
do $$ begin
  if exists (select 1 from pg_constraint where conrelid = 'public.bets'::regclass and conname = 'bets_user_id_match_id_key') then
    alter table public.bets drop constraint bets_user_id_match_id_key;
    update public.system_settings set value_int = 0 where key = 'bet_close_minutes' and value_int = 10;
  end if;
end $$;
alter table public.bets add column if not exists detail jsonb;                                   -- segnali e pesi usati per la quota di questa puntata
-- versioni precedenti: ammette lo stato «revoked» e aggiunge i dati della revoca
alter table public.bets drop constraint if exists bets_status_check;
alter table public.bets add constraint bets_status_check check (status in ('open','won','lost','refunded','revoked'));
alter table public.bets add column if not exists revoked_at timestamptz;
alter table public.bets add column if not exists revoked_by uuid references public.profiles(id);
alter table public.bets add column if not exists revoke_reason text;
create index if not exists bets_match_idx on public.bets (match_id);
create index if not exists bets_user_idx on public.bets (user_id, created_at desc);

alter table public.bets enable row level security;
alter table public.bet_windows enable row level security;
drop policy if exists bets_read on public.bets;
create policy bets_read on public.bets for select to authenticated using (user_id = auth.uid() or public.is_admin());
revoke all on public.bets, public.bet_windows from anon, authenticated;
grant select on public.bets to authenticated;

-- ---------- quota ----------
create or replace function public._bet_quote(m public.ladder_matches) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  mg numeric := least(50, greatest(0, coalesce(public._setting('bet_margin_pct'), 10))) / 100.0;
  ming integer := greatest(1, coalesce(public._setting('bet_min_games'), 3));
  sm numeric := greatest(1, coalesce(public._setting('bet_bounty_smooth'), 100));
  sp numeric := greatest(1, coalesce(public._setting('bet_pool_smooth'), 100));
  k_wr numeric := greatest(0, coalesce(public._setting('bet_w_winrate'), 100)) / 100.0;
  k_bo numeric := greatest(0, coalesce(public._setting('bet_w_bounty'), 30)) / 100.0;
  k_po numeric := greatest(0, coalesce(public._setting('bet_w_pool'), 40)) / 100.0;
  pa_pool integer; pb_pool integer;
  wa integer; da integer; la integer; wb integer; db integer; lb integer; ga integer; gb integer;
  ba integer; bb integer; wra numeric; wrb numeric; pa numeric; basis text;
  p_wr numeric; p_bo numeric; p_po numeric;                 -- cosa dice ciascun segnale da solo (null = nessun dato)
  l_wr numeric := 0; l_bo numeric := 0; l_po numeric := 0;  -- quanto ciascun segnale sposta la stima (log-odds, già col suo peso)
  lo numeric;
begin
  select coalesce(max(wins), 0), coalesce(max(draws), 0), coalesce(max(losses), 0) into wa, da, la from public.ladder_ratings where user_id = m.challenger_id and format = m.format;
  select coalesce(max(wins), 0), coalesce(max(draws), 0), coalesce(max(losses), 0) into wb, db, lb from public.ladder_ratings where user_id = m.opponent_id and format = m.format;
  ga := wa + da + la; gb := wb + db + lb;
  select coalesce(sum(amount), 0)::integer into ba from public.bounties where target_id = m.challenger_id and status = 'active';
  select coalesce(sum(amount), 0)::integer into bb from public.bounties where target_id = m.opponent_id and status = 'active';
  select coalesce(sum(stake) filter (where pick = m.challenger_id), 0)::integer, coalesce(sum(stake) filter (where pick = m.opponent_id), 0)::integer
    into pa_pool, pb_pool from public.bets where match_id = m.id;
  -- 1) win rate (log5): conta per intero da bet_min_games partite del meno esperto in su, in proporzione sotto, per nulla a zero
  if least(ga, gb) > 0 then
    wra := (wa + 0.5 * da + 1) / (ga + 2.0);
    wrb := (wb + 0.5 * db + 1) / (gb + 2.0);
    p_wr := wra * (1 - wrb) / (wra * (1 - wrb) + wrb * (1 - wra));
    l_wr := k_wr * least(1, least(ga, gb)::numeric / ming) * ln(p_wr / (1 - p_wr));
  end if;
  -- 2) bounty value: chi ha più taglie addosso è il favorito
  if ba + bb > 0 then
    p_bo := (ba + sm) / (ba + bb + 2 * sm);
    l_bo := k_bo * ln((ba + sm) / (bb + sm));
  end if;
  -- 3) scommesse già presenti: più BC su un duellante = favorito (la quota di chi riceve più soldi scende)
  if pa_pool + pb_pool > 0 then
    p_po := (pa_pool + sp) / (pa_pool + pb_pool + 2 * sp);
    l_po := k_po * ln((pa_pool + sp) / (pb_pool + sp));
  end if;
  lo := l_wr + l_bo + l_po;
  if p_wr is null and p_bo is null and p_po is null then basis := 'even'; else basis := 'mix'; end if;
  pa := 1 / (1 + exp(-lo));
  pa := least(0.95, greatest(0.05, pa));
  return jsonb_build_object('basis', basis, 'p_challenger', round(pa * 100, 2), 'p_opponent', round((1 - pa) * 100, 2),
    'quota_challenger', greatest(105, floor(100 * (1 - mg) / pa))::integer,
    'quota_opponent', greatest(105, floor(100 * (1 - mg) / (1 - pa)))::integer,
    'games_challenger', ga, 'games_opponent', gb, 'bounty_challenger', ba, 'bounty_opponent', bb, 'pool_challenger', pa_pool, 'pool_opponent', pb_pool, 'margin_pct', round(mg * 100),
    'p_winrate', round(p_wr * 100, 2), 'p_bounty', round(p_bo * 100, 2), 'p_bets', round(p_po * 100, 2),
    'l_winrate', round(l_wr, 2), 'l_bounty', round(l_bo, 2), 'l_bets', round(l_po, 2));
end $$;

-- ---------- finestra di puntata ----------
create or replace function public._bet_closes_at(m public.ladder_matches) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v_close integer := coalesce(public._setting('bet_close_minutes'), 10); v_at timestamptz;
begin
  if v_close <= 0 or m.status <> 'accepted' then return null; end if;
  select accepted_at into v_at from public.bet_windows where match_id = m.id;
  return v_at + make_interval(mins => v_close);          -- null se la sfida è stata accettata prima di questa migrazione
end $$;

create or replace function public._bet_is_open(m public.ladder_matches) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_close integer := coalesce(public._setting('bet_close_minutes'), 10); v_at timestamptz;
begin
  if m.status = 'pending' then return true; end if;
  if m.status <> 'accepted' then return false; end if;
  if v_close <= 0 then return true; end if;
  v_at := public._bet_closes_at(m);
  return v_at is not null and clock_timestamp() < v_at;
end $$;

-- ---------- liquidazione: porta ogni scommessa della sfida a ciò che il risultato attuale prevede (idempotente) ----------
create or replace function public._bet_reconcile(p_match uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare m public.ladder_matches%rowtype; b public.bets%rowtype; w uuid; v_state text; v_ret integer; v_delta integer; v_n integer := 0;
        v_bal integer; v_c integer; v_key text;
begin
  select * into m from public.ladder_matches where id = p_match;
  if not found then return 0; end if;
  if m.status = 'closed' then
    w := case m.reported_result when 'challenger' then m.challenger_id when 'opponent' then m.opponent_id end;     -- null = pareggio
  elsif m.status not in ('declined','cancelled','expired','voided') then
    return 0;                                                                                                       -- sfida ancora aperta
  end if;
  for b in select * from public.bets where match_id = p_match order by user_id for update loop                     -- ordine fisso: niente blocchi incrociati
    if b.status = 'revoked' then continue; end if;                                                                  -- pagamento revocato dall'admin: non si ripaga mai
    if m.status = 'closed' and w is not null then
      if b.pick = w then v_state := 'won'; v_ret := floor(b.stake * b.quota / 100.0)::integer; else v_state := 'lost'; v_ret := 0; end if;
    else
      v_state := 'refunded'; v_ret := b.stake;
    end if;
    if v_state = b.status and v_ret = b.returned then continue; end if;
    v_delta := v_ret - b.returned; v_c := 0; v_key := 'bet:' || b.id || ':' || b.settle_seq;
    if v_delta > 0 then
      perform public._ledger_move(b.user_id, v_delta, case when v_state = 'won' then 'bet_payout' else 'bet_refund' end, 'bet', b.id, v_key,
        case when v_state = 'won' then 'Scommessa vinta' else 'Puntata restituita' end);
    elsif v_delta < 0 then
      select balance into v_bal from public.wallets where user_id = b.user_id for update;
      v_c := least(-v_delta, v_bal);
      if v_c > 0 then
        perform public._ledger_move(b.user_id, -v_c, 'bet_reversal', 'bet', b.id, v_key, 'Scommessa ricalcolata dopo la correzione del risultato');
      end if;
    end if;
    update public.bets set status = v_state, returned = v_ret, written_off = written_off + case when v_delta < 0 then -v_delta - v_c else 0 end,
      settle_seq = settle_seq + 1, settled_at = clock_timestamp() where id = b.id;
    perform public._audit(null, 'bet_settle', 'bet', b.id::text, jsonb_build_object('status', b.status, 'returned', b.returned),
      jsonb_build_object('status', v_state, 'returned', v_ret, 'delta', v_delta, 'recovered', case when v_delta < 0 then v_c end), null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------- trigger sulle sfide Ladder: non modifica nessuna funzione della Ladder ----------
create or replace function public._bet_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'accepted' and (TG_OP = 'INSERT' or old.status is distinct from 'accepted') then
    insert into public.bet_windows (match_id) values (new.id) on conflict (match_id) do nothing;
  end if;
  if TG_OP = 'UPDATE' then
    begin
      perform public._bet_reconcile(new.id);
    exception when others then
      raise warning 'scommesse: liquidazione rimandata per la sfida %: %', new.id, sqlerrm;   -- la chiusura della sfida non deve mai fallire per colpa delle scommesse
    end;
  end if;
  return null;
end $$;
drop trigger if exists bets_on_ladder_match on public.ladder_matches;
create trigger bets_on_ladder_match after insert or update of status, reported_result on public.ladder_matches
  for each row execute function public._bet_trg();

-- ---------- puntare ----------
create or replace function public.place_bet(p_match uuid, p_pick uuid, p_stake integer, p_min_quota integer default null, p_request_id text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
        m public.ladder_matches%rowtype; e public.bets%rowtype; q jsonb; v_quota integer; v_prob numeric; v_id uuid := gen_random_uuid();
        v_min integer := greatest(1, coalesce(public._setting('bet_min_stake'), 10)); v_max integer := coalesce(public._setting('bet_max_stake'), 200);
        v_open integer := coalesce(public._setting('bet_max_open'), 5);
begin
  perform public._require_module('ladder');
  if coalesce(public._setting('bet_enabled'), 1) <> 1 then raise exception 'Le scommesse sono al momento spente'; end if;
  if p_request_id is null or char_length(p_request_id) < 8 then raise exception 'Richiesta non valida'; end if;
  select * into m from public.ladder_matches where id = p_match for share;      -- prima la sfida, poi il wallet: stesso ordine della chiusura (niente blocchi incrociati)
  if not found then raise exception 'Sfida non trovata'; end if;
  perform 1 from public.wallets where user_id = v_me for update;                 -- serializza le richieste dello stesso utente
  select * into e from public.bets where user_id = v_me and client_request_id = p_request_id;
  if found then
    return jsonb_build_object('bet_id', e.id, 'already', true, 'quota', e.quota, 'stake', e.stake, 'payout_if_win', floor(e.stake * e.quota / 100.0)::integer);
  end if;
  if v_me in (m.challenger_id, m.opponent_id) then raise exception 'Non puoi scommettere su una sfida che giochi tu'; end if;
  if p_pick is null or p_pick not in (m.challenger_id, m.opponent_id) then raise exception 'Scegli uno dei due sfidanti'; end if;
  if not public._bet_is_open(m) then raise exception 'Le scommesse su questa sfida sono chiuse'; end if;
  if p_stake is null or p_stake < v_min then raise exception 'Puntata inferiore al minimo (% BC)', v_min; end if;
  if p_stake > v_max then raise exception 'Puntata superiore al massimo (% BC)', v_max; end if;
  if (select count(*) from public.bets where user_id = v_me and status = 'open') >= v_open then
    raise exception 'Hai già % scommesse aperte: aspetta che si chiudano', v_open; end if;
  q := public._bet_quote(m);
  if p_pick = m.challenger_id then v_quota := (q->>'quota_challenger')::integer; v_prob := (q->>'p_challenger')::numeric;
  else v_quota := (q->>'quota_opponent')::integer; v_prob := (q->>'p_opponent')::numeric; end if;
  if p_min_quota is not null and v_quota < p_min_quota then
    raise exception 'La quota è cambiata: ora è %', replace(to_char(v_quota / 100.0, 'FM990.00'), '.', ','); end if;
  insert into public.bets (id, user_id, match_id, pick, stake, quota, basis, prob_pct, client_request_id, detail)
    values (v_id, v_me, p_match, p_pick, p_stake, v_quota, q->>'basis', v_prob, p_request_id, q);
  perform public._ledger_move(v_me, -p_stake, 'bet_stake', 'bet', v_id, 'betstake:' || v_id, 'Scommessa piazzata');
  perform public._audit(v_me, 'place_bet', 'bet', v_id::text, null, jsonb_build_object('match', p_match, 'pick', p_pick, 'stake', p_stake, 'quota', v_quota, 'basis', q->>'basis'), null);
  return jsonb_build_object('bet_id', v_id, 'already', false, 'quota', v_quota, 'stake', p_stake, 'payout_if_win', floor(p_stake * v_quota / 100.0)::integer, 'basis', q->>'basis',
    'on_match', (select count(*) from public.bets where user_id = v_me and match_id = p_match));
end $$;

-- ---------- lettura: sfide su cui si può scommettere, con le quote ----------
create or replace function public.bet_markets() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); r jsonb;
begin
  perform public._require_module('ladder');
  select coalesce(jsonb_agg(s.x order by s.ts desc), '[]'::jsonb) into r from (
    select m.created_at as ts, jsonb_build_object(
      'id', m.id, 'created_at', m.created_at, 'status', m.status, 'format', m.format, 'kind', m.kind,
      'challenger', m.challenger_id, 'opponent', m.opponent_id, 'challenger_name', pc.nickname, 'opponent_name', po.nickname,
      'open', public._bet_is_open(m), 'closes_at', public._bet_closes_at(m), 'quote', public._bet_quote(m),
      'can_bet', (v <> m.challenger_id and v <> m.opponent_id),
      'mine', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'pick', b.pick, 'stake', b.stake, 'quota', b.quota, 'created_at', b.created_at) order by b.created_at, b.id)
                        from public.bets b where b.match_id = m.id and b.user_id = v), '[]'::jsonb)) as x
    from public.ladder_matches m join public.profiles pc on pc.id = m.challenger_id join public.profiles po on po.id = m.opponent_id
    where m.status in ('pending','accepted') order by m.created_at desc limit 60) s;
  return r;
end $$;

create or replace function public.bet_mine() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); r jsonb;
begin
  select coalesce(jsonb_agg(s.x order by s.ts desc), '[]'::jsonb) into r from (
    select b.created_at as ts, jsonb_build_object(
      'id', b.id, 'match', b.match_id, 'status', b.status, 'stake', b.stake, 'quota', b.quota, 'basis', b.basis, 'prob_pct', b.prob_pct,
      'returned', b.returned, 'written_off', b.written_off, 'detail', b.detail, 'revoked_at', b.revoked_at, 'created_at', b.created_at, 'settled_at', b.settled_at,
      'pick', b.pick, 'pick_name', pp.nickname, 'challenger_name', pc.nickname, 'opponent_name', po.nickname,
      'match_status', m.status, 'result', m.reported_result, 'format', m.format, 'kind', m.kind) as x
    from public.bets b join public.ladder_matches m on m.id = b.match_id
      join public.profiles pp on pp.id = b.pick join public.profiles pc on pc.id = m.challenger_id join public.profiles po on po.id = m.opponent_id
    where b.user_id = v order by b.created_at desc limit 80) s;
  return r;
end $$;

-- liquida le scommesse rimaste aperte su sfide già concluse (rete di sicurezza: normalmente le chiude il trigger)
create or replace function public.bet_sync() returns integer language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  perform public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  for r in select distinct b.match_id from public.bets b join public.ladder_matches m on m.id = b.match_id
           where b.status = 'open' and m.status in ('closed','declined','cancelled','expired','voided') order by b.match_id loop
    n := n + public._bet_reconcile(r.match_id);
  end loop;
  return n;
end $$;

-- riepilogo per l'amministratore: quanto circola
create or replace function public.bet_admin_stats() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]);
begin
  return (select jsonb_build_object(
    'open_count', count(*) filter (where status = 'open'), 'open_stake', coalesce(sum(stake) filter (where status = 'open'), 0),
    'bets_total', count(*), 'staked_total', coalesce(sum(stake), 0), 'returned_total', coalesce(sum(returned), 0),
    'house_net', coalesce(sum(stake) filter (where status <> 'open'), 0) - coalesce(sum(returned), 0), 'written_off', coalesce(sum(written_off), 0),
    'revoked_count', count(*) filter (where status = 'revoked'))
    from public.bets);
end $$;

-- ---------- admin: tutte le scommesse (da pagare / liquidate) ----------
create or replace function public.bet_admin_list() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); r_open jsonb; r_done jsonb; n_open integer; n_done integer;
begin
  select count(*) filter (where status = 'open'), count(*) filter (where status <> 'open') into n_open, n_done from public.bets;
  select coalesce(jsonb_agg(s.x order by s.ts), '[]'::jsonb) into r_open from (
    select b.created_at as ts, public._bet_admin_row(b) as x from public.bets b where b.status = 'open' order by b.created_at limit 500) s;
  select coalesce(jsonb_agg(s.x order by s.ts desc), '[]'::jsonb) into r_done from (
    select coalesce(b.settled_at, b.created_at) as ts, public._bet_admin_row(b) as x from public.bets b where b.status <> 'open'
      order by coalesce(b.settled_at, b.created_at) desc limit 300) s;
  return jsonb_build_object('open', r_open, 'settled', r_done, 'open_count', n_open, 'settled_count', n_done);
end $$;

create or replace function public._bet_admin_row(b public.bets) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', b.id, 'user_id', b.user_id, 'user_name', pu.nickname, 'balance', coalesce(w.balance, 0), 'status', b.status, 'stake', b.stake, 'quota', b.quota,
    'returned', b.returned, 'written_off', b.written_off, 'created_at', b.created_at, 'settled_at', b.settled_at, 'revoked_at', b.revoked_at, 'revoke_reason', b.revoke_reason,
    'pick', b.pick, 'pick_name', pp.nickname, 'challenger_name', pc.nickname, 'opponent_name', po.nickname, 'match', b.match_id,
    'match_status', m.status, 'result', m.reported_result, 'format', m.format, 'kind', m.kind)
  from public.ladder_matches m join public.profiles pu on pu.id = b.user_id join public.profiles pp on pp.id = b.pick
    join public.profiles pc on pc.id = m.challenger_id join public.profiles po on po.id = m.opponent_id
    left join public.wallets w on w.user_id = b.user_id
  where m.id = b.match_id $$;

-- ---------- admin: revoca di un pagamento ----------
-- p_refund_stake = false: si toglie tutto ciò che è stato pagato (la puntata resta persa);
-- p_refund_stake = true : si toglie solo la vincita e la puntata resta restituita («annulla la scommessa»).
create or replace function public.bet_admin_revoke(p_bet uuid, p_reason text, p_refund_stake boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); b public.bets%rowtype; v_target integer; v_need integer; v_bal integer; v_c integer := 0;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into b from public.bets where id = p_bet for update;
  if not found then raise exception 'Scommessa non trovata'; end if;
  if b.status = 'revoked' then raise exception 'Pagamento già revocato'; end if;
  if b.status = 'open' then raise exception 'Scommessa non ancora pagata: non c''è niente da revocare'; end if;
  if b.returned <= 0 then raise exception 'Questa scommessa non ha pagato nulla: non c''è niente da revocare'; end if;
  v_target := case when coalesce(p_refund_stake, false) then b.stake else 0 end;
  v_need := b.returned - v_target;
  if v_need <= 0 then raise exception 'Con la puntata restituita non c''è nulla da togliere'; end if;
  select balance into v_bal from public.wallets where user_id = b.user_id for update;
  v_c := least(v_need, coalesce(v_bal, 0));
  if v_c > 0 then
    perform public._ledger_move(b.user_id, -v_c, 'bet_reversal', 'bet', b.id, 'betrev:' || b.id,
      case when coalesce(p_refund_stake, false) then 'Vincita della scommessa revocata dall''amministratore' else 'Pagamento della scommessa revocato dall''amministratore' end);
  end if;
  update public.bets set status = 'revoked', returned = v_target, written_off = written_off + (v_need - v_c), settle_seq = settle_seq + 1,
    revoked_at = clock_timestamp(), revoked_by = v, revoke_reason = btrim(p_reason) where id = b.id;
  perform public._audit(v, 'bet_revoke', 'bet', b.id::text, jsonb_build_object('status', b.status, 'returned', b.returned),
    jsonb_build_object('status', 'revoked', 'returned', v_target, 'recovered', v_c, 'not_recovered', v_need - v_c, 'refund_stake', coalesce(p_refund_stake, false)), btrim(p_reason));
  return jsonb_build_object('bet_id', b.id, 'recovered', v_c, 'not_recovered', v_need - v_c, 'returned', v_target);
end $$;

revoke all on function public._bet_quote(public.ladder_matches), public._bet_closes_at(public.ladder_matches), public._bet_is_open(public.ladder_matches),
  public._bet_reconcile(uuid), public._bet_trg(), public._bet_admin_row(public.bets) from public, anon, authenticated;
revoke all on function public.place_bet(uuid, uuid, integer, integer, text), public.bet_markets(), public.bet_mine(), public.bet_sync(), public.bet_admin_stats(),
  public.bet_admin_list(), public.bet_admin_revoke(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.place_bet(uuid, uuid, integer, integer, text), public.bet_markets(), public.bet_mine(), public.bet_sync(), public.bet_admin_stats(),
  public.bet_admin_list(), public.bet_admin_revoke(uuid, text, boolean) to authenticated;

commit;
