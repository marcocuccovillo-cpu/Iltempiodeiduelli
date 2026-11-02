-- =====================================================================
-- MIGRAZIONE 037 — INVITI E VETRINA PUBBLICA
-- Da eseguire in Supabase (SQL Editor) DOPO tutte le migrazioni precedenti (ultima: 036, black-market-eroi-arena.sql).
--
-- 1. CODICE INVITO
--    * Ogni duellante ha un codice (6 caratteri) e un link da condividere: index.html?invito=CODICE.
--    * Chi si registra dal link (entro 7 giorni dall'iscrizione e prima di aver giocato) resta collegato a chi l'ha invitato.
--    * Al PRIMO match giocato dall'invitato (Ladder conclusa o match ufficiale verificato) contro qualcuno che NON sia chi l'ha invitato:
--        chi invita riceve 200 BC  (movimento 'invite_reward'),
--        l'invitato riceve 100 BC  (movimento 'invite_bonus'), in più dei 1000 di benvenuto.
--      Una volta sola per invitato (chiave di idempotenza nel registro). Massimo 10 inviti premiati per chi invita: oltre, l'invitato
--      riceve comunque il suo bonus. Importi e limiti si cambiano da Admin › Impostazioni (invite_*), come gli altri.
--    * Badge nuovi «Reclutatore» (1, 3, 5, 10 amici portati che hanno giocato), area Community: funzione badge_progress_invite.
--    * Notifica a chi invita quando l'amico gioca il primo match.
-- 2. VETRINA PUBBLICA
--    * public_showcase(): una sola funzione in SOLA LETTURA, chiamabile anche senza account, per la Home. Restituisce SOLO dati già
--      visibili a tutti gli iscritti: nickname e avatar, classifica Ladder, Most Wanted (solo chi ha dato il consenso alle taglie),
--      ultimi risultati Ladder, boss del giorno, prossimi eventi, numeri generali. Mai email, saldi, scommesse o registro.
--    * invite_info(codice): dice solo il nickname di chi ha invitato (per il banner «X ti ha invitato»).
--
-- Garanzie: non cancella e non modifica dati esistenti; i BC si muovono solo con _ledger_move (registro + audit); un problema negli
-- inviti non può bloccare la chiusura di un match (l'errore viene registrato come avviso e il match si chiude normalmente).
-- Si può rieseguire. Annullamento: black-market-inviti-down.sql. Test (solo su un progetto di prova vuoto): black-market-inviti-test.sql.
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.ladder_matches') is null or to_regprocedure('public._notify(uuid,text,text,text,text,text,uuid)') is null then
    raise exception 'Prima esegui le migrazioni della Ladder e delle notifiche. Non è stato modificato nulla.';
  end if;
end $$;

-- ---------- nuovi tipi di movimento nel registro e di notifica (si aggiungono a quelli presenti, qualunque siano) ----------
do $$
declare d text; kinds text[]; k text;
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.ledger_entries'::regclass and conname = 'ledger_entries_kind_check';
  if d is null then raise exception 'Vincolo ledger_entries_kind_check non trovato'; end if;
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  foreach k in array array['invite_reward','invite_bonus'] loop
    if not (k = any (kinds)) then kinds := kinds || k; end if;
  end loop;
  alter table public.ledger_entries drop constraint ledger_entries_kind_check;
  execute 'alter table public.ledger_entries add constraint ledger_entries_kind_check check (kind in ('
    || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';

  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.notifications'::regclass and conname = 'notifications_kind_check';
  if d is null then raise exception 'Vincolo notifications_kind_check non trovato'; end if;
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  if not ('invite_reward' = any (kinds)) then kinds := kinds || 'invite_reward'::text; end if;
  alter table public.notifications drop constraint notifications_kind_check;
  execute 'alter table public.notifications add constraint notifications_kind_check check (kind in ('
    || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
end $$;

-- ---------- impostazioni (modificabili da Admin › Impostazioni) ----------
insert into public.system_settings (key, value_int, description) values
 ('invite_enabled',      1,   'Inviti: 1 = attivi, 0 = spenti (i codici restano, non si collegano nuovi amici e non si pagano premi)'),
 ('invite_reward_bc',    200, 'Inviti: BC a chi invita quando l''amico gioca il primo match'),
 ('invite_bonus_bc',     100, 'Inviti: BC extra all''invitato al primo match (oltre al bonus di benvenuto)'),
 ('invite_max_rewards',  10,  'Inviti: massimo inviti premiati per duellante'),
 ('invite_redeem_days',  7,   'Inviti: giorni dall''iscrizione entro cui si può inserire un codice')
on conflict (key) do nothing;

-- ---------- tabelle ----------
create table if not exists public.invite_codes (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
  created_at timestamptz not null default clock_timestamp()
);
create table if not exists public.invites (
  invitee_id uuid primary key references public.profiles(id) on delete restrict,   -- un solo «padrino» per duellante
  inviter_id uuid not null references public.profiles(id) on delete restrict,
  code text not null,
  created_at timestamptz not null default clock_timestamp(),
  rewarded_at timestamptz,                -- quando l'invitato ha giocato il primo match valido
  inviter_paid integer not null default 0 check (inviter_paid >= 0),
  invitee_paid integer not null default 0 check (invitee_paid >= 0),
  check (invitee_id <> inviter_id)
);
create index if not exists invites_inviter_idx on public.invites (inviter_id, rewarded_at);

alter table public.invite_codes enable row level security;
alter table public.invites enable row level security;
drop policy if exists invite_codes_read on public.invite_codes;
create policy invite_codes_read on public.invite_codes for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists invites_read on public.invites;
create policy invites_read on public.invites for select to authenticated using (inviter_id = auth.uid() or invitee_id = auth.uid() or public.is_admin());
revoke all on public.invite_codes, public.invites from public, anon, authenticated;
grant select on public.invite_codes, public.invites to authenticated;

-- ---------- il mio codice e i miei inviti ----------
create or replace function public.my_invite() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid(); c text; a text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i integer; tries integer := 0;
begin
  if v is null then raise exception 'Accesso richiesto'; end if;
  if not exists (select 1 from public.profiles where id = v) then raise exception 'Crea prima il profilo'; end if;
  select code into c from public.invite_codes where user_id = v;
  while c is null loop
    tries := tries + 1; if tries > 50 then raise exception 'Impossibile generare un codice, riprova'; end if;
    c := ''; for i in 1..6 loop c := c || substr(a, 1 + floor(random() * length(a))::int, 1); end loop;
    begin
      insert into public.invite_codes (user_id, code) values (v, c);
    exception when unique_violation then
      select code into c from public.invite_codes where user_id = v;     -- creato in parallelo, oppure codice già usato da altri: si riprova
    end;
  end loop;
  return jsonb_build_object(
    'code', c,
    'enabled', coalesce(public._setting('invite_enabled'), 1) = 1,
    'reward', coalesce(public._setting('invite_reward_bc'), 200),
    'bonus', coalesce(public._setting('invite_bonus_bc'), 100),
    'max', coalesce(public._setting('invite_max_rewards'), 10),
    'earned', coalesce((select sum(inviter_paid) from public.invites where inviter_id = v), 0),
    'friends', coalesce((select jsonb_agg(jsonb_build_object('nickname', p.nickname, 'played', i.rewarded_at is not null, 'paid', i.inviter_paid, 'at', i.created_at) order by i.created_at desc)
                           from public.invites i join public.profiles p on p.id = i.invitee_id where i.inviter_id = v), '[]'::jsonb),
    'invited_by', (select p.nickname from public.invites i join public.profiles p on p.id = i.inviter_id where i.invitee_id = v),
    'can_redeem', not exists (select 1 from public.invites where invitee_id = v)
                  and (select created_at from public.profiles where id = v) > now() - make_interval(days => coalesce(public._setting('invite_redeem_days'), 7))
                  and not public._invite_has_played(v, null)
  );
end $$;

-- ha già giocato almeno un match valido (Ladder conclusa o match ufficiale verificato), escluso eventualmente un avversario
create or replace function public._invite_has_played(p_user uuid, p_not uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.ladder_matches m where m.status = 'closed' and p_user in (m.challenger_id, m.opponent_id)
                    and (p_not is null or p_not not in (m.challenger_id, m.opponent_id)))
      or exists (select 1 from public.matches m where m.status = 'verified' and p_user in (m.player_a, m.player_b)
                    and (p_not is null or p_not not in (m.player_a, m.player_b)))
$$;

-- per il banner «X ti ha invitato»: solo il nickname, anche senza account
create or replace function public.invite_info(p_code text) returns jsonb language sql stable security definer set search_path = public as $$
  select case when coalesce(public._setting('invite_enabled'), 1) <> 1 then null else
    (select jsonb_build_object('nickname', p.nickname, 'bonus', coalesce(public._setting('invite_bonus_bc'), 100), 'welcome', coalesce(public._setting('initial_bonus'), 0))
       from public.invite_codes c join public.profiles p on p.id = c.user_id
      where c.code = upper(btrim(p_code)) and not p.suspended) end
$$;

-- l'invitato inserisce il codice (in automatico dal link, oppure a mano dal Black Market)
create or replace function public.redeem_invite(p_code text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid(); c text := upper(btrim(coalesce(p_code, ''))); v_inv uuid; v_nick text; v_created timestamptz; v_susp boolean;
begin
  if v is null then raise exception 'Accesso richiesto'; end if;
  if coalesce(public._setting('invite_enabled'), 1) <> 1 then raise exception 'Gli inviti non sono attivi'; end if;
  select created_at, suspended into v_created, v_susp from public.profiles where id = v;
  if not found then raise exception 'Crea prima il profilo'; end if;
  if v_susp then raise exception 'Account sospeso'; end if;
  if exists (select 1 from public.invites where invitee_id = v) then
    return jsonb_build_object('ok', false, 'already', true, 'inviter', (select p.nickname from public.invites i join public.profiles p on p.id = i.inviter_id where i.invitee_id = v));
  end if;
  select ic.user_id, p.nickname into v_inv, v_nick from public.invite_codes ic join public.profiles p on p.id = ic.user_id where ic.code = c and not p.suspended;
  if v_inv is null then raise exception 'Codice invito non valido'; end if;
  if v_inv = v then raise exception 'Non puoi usare il tuo stesso codice'; end if;
  if exists (select 1 from public.invites where invitee_id = v_inv and inviter_id = v) then raise exception 'Vi siete già invitati a vicenda'; end if;
  if v_created < now() - make_interval(days => coalesce(public._setting('invite_redeem_days'), 7)) then
    raise exception 'Il codice si può inserire solo nei primi % giorni dall''iscrizione', coalesce(public._setting('invite_redeem_days'), 7); end if;
  if public._invite_has_played(v, null) then raise exception 'Il codice si inserisce prima del primo match'; end if;
  insert into public.invites (invitee_id, inviter_id, code) values (v, v_inv, c);
  perform public._audit(v, 'redeem_invite', 'invite', v::text, null, jsonb_build_object('inviter', v_inv, 'code', c), null);
  return jsonb_build_object('ok', true, 'inviter', v_nick, 'bonus', coalesce(public._setting('invite_bonus_bc'), 100));
end $$;

-- premio: si chiama dai trigger quando un match si chiude; p_other = l'avversario di quel match
create or replace function public._invite_check(p_user uuid, p_other uuid, p_ref_type text, p_ref uuid) returns void language plpgsql security definer set search_path = public as $$
declare r public.invites%rowtype; v_rew integer; v_bon integer; v_paid_count integer; v_nick text; v_pay integer := 0; v_bpay integer := 0;
begin
  select * into r from public.invites where invitee_id = p_user and rewarded_at is null for update;
  if not found then return; end if;
  if coalesce(public._setting('invite_enabled'), 1) <> 1 then return; end if;
  if p_other = r.inviter_id then return; end if;                       -- giocare contro chi ti ha invitato non conta
  if exists (select 1 from public.profiles where id in (p_user, r.inviter_id) and suspended) then return; end if;
  v_rew := greatest(coalesce(public._setting('invite_reward_bc'), 200), 0);
  v_bon := greatest(coalesce(public._setting('invite_bonus_bc'), 100), 0);
  select count(*) into v_paid_count from public.invites where inviter_id = r.inviter_id and inviter_paid > 0;
  select nickname into v_nick from public.profiles where id = p_user;
  if v_rew > 0 and v_paid_count < coalesce(public._setting('invite_max_rewards'), 10) then
    if public._ledger_move(r.inviter_id, v_rew, 'invite_reward', 'invite', p_user, 'invite:reward:' || p_user, 'Invito: ' || v_nick || ' ha giocato il primo match') >= 0 then v_pay := v_rew; end if;
  end if;
  if v_bon > 0 then
    if public._ledger_move(p_user, v_bon, 'invite_bonus', 'invite', p_user, 'invite:bonus:' || p_user, 'Bonus invito: primo match giocato') >= 0 then v_bpay := v_bon; end if;
  end if;
  update public.invites set rewarded_at = clock_timestamp(), inviter_paid = v_pay, invitee_paid = v_bpay where invitee_id = p_user;
  perform public._audit(null, 'invite_reward', 'invite', p_user::text, null,
    jsonb_build_object('inviter', r.inviter_id, 'inviter_paid', v_pay, 'invitee_paid', v_bpay, 'ref_type', p_ref_type, 'ref', p_ref), null);
  perform public._notify(r.inviter_id, 'invite_reward', 'Il tuo invito ha funzionato',
    v_nick || ' ha giocato il primo match' || case when v_pay > 0 then ': +' || v_pay || ' BC per te.' else '. Hai già raggiunto il massimo di inviti premiati.' end,
    'black-market.html#/invita', 'invite', p_user);
end $$;

create or replace function public._trg_invite_ladder() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'closed' and old.status is distinct from 'closed' then
    begin
      perform public._invite_check(new.challenger_id, new.opponent_id, 'ladder_match', new.id);
      perform public._invite_check(new.opponent_id, new.challenger_id, 'ladder_match', new.id);
    exception when others then raise warning 'Inviti: premio non assegnato (%)', sqlerrm;   -- il match si chiude comunque
    end;
  end if;
  return null;
end $$;
drop trigger if exists invite_on_ladder on public.ladder_matches;
create trigger invite_on_ladder after update of status on public.ladder_matches for each row execute function public._trg_invite_ladder();

create or replace function public._trg_invite_match() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'verified' and (tg_op = 'INSERT' or old.status is distinct from 'verified') then
    begin
      perform public._invite_check(new.player_a, new.player_b, 'match', new.id);
      perform public._invite_check(new.player_b, new.player_a, 'match', new.id);
    exception when others then raise warning 'Inviti: premio non assegnato (%)', sqlerrm;
    end;
  end if;
  return null;
end $$;
drop trigger if exists invite_on_match on public.matches;
create trigger invite_on_match after insert or update of status on public.matches for each row execute function public._trg_invite_match();

-- ---------- badge «Reclutatore» (stesse colonne di badge_progress / badge_progress_extra) ----------
create or replace function public.badge_progress_invite(p_user uuid default null)
returns table (code text, family text, area text, tier smallint, metric text, kind text, threshold bigint, value bigint,
               earned boolean, earned_at timestamptz, hidden boolean, sort integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_u uuid := coalesce(p_user, auth.uid()); v_n bigint; v_ts timestamptz[];
begin
  if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
  if v_u is null or not exists (select 1 from public.profiles pr where pr.id = v_u) then return; end if;
  select count(*), array_agg(i.rewarded_at order by i.rewarded_at) into v_n, v_ts
    from public.invites i where i.inviter_id = v_u and i.rewarded_at is not null;
  return query
  select 'c_recluta_' || t.tier, 'c_recluta'::text, 'community'::text, t.tier::smallint, 'c_recluta'::text, 'count'::text, t.thr::bigint, v_n,
         v_n >= t.thr, case when v_n >= t.thr then v_ts[t.thr] end, false, 2000 + t.tier
    from (values (1, 1), (2, 3), (3, 5), (4, 10)) as t(tier, thr)
   order by t.tier;
end $$;

-- ---------- vetrina pubblica per la Home (anche senza account) ----------
create or replace function public.public_showcase() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Europe/Rome')::date; out jsonb; ids uuid[] := '{}';
        v_lad jsonb := '{}'::jsonb; v_res jsonb := '[]'::jsonb; v_mw jsonb := '[]'::jsonb; v_boss jsonb; v_ev jsonb := '[]'::jsonb; f text;
begin
  -- Ladder: prime 5 per formato (solo chi ha giocato), ultimi risultati
  if public._module_on('ladder') then
    foreach f in array array['Advanced','Edison'] loop
      v_lad := v_lad || jsonb_build_object(f, coalesce((select jsonb_agg(jsonb_build_object('id', x.user_id, 'elo', x.elo, 'w', x.wins, 'd', x.draws, 'l', x.losses) order by x.elo desc, x.wins desc)
        from (select r.* from public.ladder_ratings r join public.profiles p on p.id = r.user_id
               where r.format = f and not p.suspended and r.wins + r.draws + r.losses > 0 order by r.elo desc, r.wins desc limit 5) x), '[]'::jsonb));
    end loop;
    select coalesce(jsonb_agg(jsonb_build_object('a', m.challenger_id, 'b', m.opponent_id, 'res', m.reported_result, 'score', m.reported_score, 'fmt', m.format, 'at', m.closed_at) order by m.closed_at desc), '[]'::jsonb)
      into v_res from (select * from public.ladder_matches where status = 'closed' order by closed_at desc limit 6) m;
  end if;
  -- Most Wanted: solo chi ha dato il consenso (most_wanted_v esclude già i sospesi)
  select coalesce(jsonb_agg(jsonb_build_object('id', w.id, 'value', w.bounty_value, 'count', w.active_count) order by w.bounty_value desc), '[]'::jsonb)
    into v_mw from (select * from public.most_wanted_v mw where exists (select 1 from public.profiles p where p.id = mw.id and p.wanted_enabled) order by bounty_value desc limit 3) w;
  -- boss del giorno
  if public._module_on('heroes') then
    select jsonb_build_object('name', b.name, 'emoji', b.emoji, 'no', b.no, 'level', d.boss_level, 'status',
             case when exists (select 1 from public.game_lobbies l where l.day = d.day and l.status = 'defeated') then 'defeated' else d.status end,
             'lobbies', (select count(*) from public.game_lobbies l where l.day = d.day),
             'heroes', (select count(distinct h.user_id) from public.game_day_heroes h where h.day = d.day))
      into v_boss from public.game_days d join public.game_bosses b on b.no = d.boss_no where d.day = v_today;
    if v_boss is null then v_boss := jsonb_build_object('status', 'sleeping'); end if;
    v_boss := v_boss || jsonb_build_object('total_heroes', (select count(*) from public.game_heroes h join public.profiles p on p.id = h.user_id where not p.suspended),
                                           'top_level', (select max(h.level) from public.game_heroes h join public.profiles p on p.id = h.user_id where not p.suspended));
  end if;
  -- prossimi eventi (organizzatori, non le giornate automatiche della Ladder)
  select coalesce(jsonb_agg(jsonb_build_object('name', e.name, 'date', e.event_date, 'status', e.event_status, 'players', (select count(*) from public.event_participants ep where ep.event_id = e.id and not ep.dropped)) order by e.event_date), '[]'::jsonb)
    into v_ev from (select * from public.events where source <> 'ladder' and event_date >= v_today and event_status in ('open','running') order by event_date limit 3) e;

  -- nickname e avatar di tutti i duellanti citati (una volta sola)
  select array_agg(distinct x::uuid) into ids from (
    select jsonb_array_elements(v_lad->'Advanced')->>'id' as x union all select jsonb_array_elements(v_lad->'Edison')->>'id'
    union all select jsonb_array_elements(v_res)->>'a' union all select jsonb_array_elements(v_res)->>'b'
    union all select jsonb_array_elements(v_mw)->>'id') q where x is not null;

  out := jsonb_build_object(
    'at', now(),
    'stats', jsonb_build_object(
      'players', (select count(*) from public.profiles where not suspended),
      'new_week', (select count(*) from public.profiles where not suspended and created_at > now() - interval '7 days'),
      'matches_week', (select count(*) from public.ladder_matches where status = 'closed' and closed_at > now() - interval '7 days')
                      + (select count(*) from public.matches where status = 'verified' and source <> 'ladder' and verified_at > now() - interval '7 days'),
      'bounty_total', coalesce((select sum(bounty_value) from public.most_wanted_v), 0)),
    'ladder', v_lad, 'results', v_res, 'wanted', v_mw, 'boss', v_boss, 'events', v_ev,
    'people', coalesce((select jsonb_object_agg(p.id, jsonb_build_object('n', p.nickname, 'a', p.avatar, 'i', p.avatar_img)) from public.profiles p where p.id = any (coalesce(ids, '{}'))), '{}'::jsonb)
  );
  return out;
end $$;

-- ---------- permessi ----------
revoke all on function public.my_invite(), public.redeem_invite(text), public.invite_info(text), public._invite_has_played(uuid, uuid),
  public._invite_check(uuid, uuid, text, uuid), public._trg_invite_ladder(), public._trg_invite_match(),
  public.badge_progress_invite(uuid), public.public_showcase() from public, anon, authenticated;
grant execute on function public.my_invite(), public.redeem_invite(text), public.badge_progress_invite(uuid) to authenticated;
grant execute on function public.invite_info(text), public.public_showcase() to anon, authenticated;

commit;
