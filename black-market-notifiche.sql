-- =====================================================================
-- MIGRAZIONE 009 — NOTIFICHE (in app + push)
-- Da eseguire nel SQL Editor di Supabase DOPO 001…008. Si può rieseguire senza danni.
--
-- Cosa fa: avvisa i giocatori quando
--   * ricevono una TAGLIA            (tipo bounty_received)
--   * ricevono una SFIDA in Ladder   (tipo ladder_challenge)
--   * ricevono una SFIDA PER LA TAGLIA: una sfida in Ladder da parte di chi vuole riscuotere la taglia che hanno
--     addosso (tipo bounty_challenge)
-- Aggiunge:
--   * notifications        l'elenco delle notifiche di ciascuno (visibile solo al destinatario; si segna "letta", mai si modifica il testo)
--   * notification_prefs   cosa ricevere (tutto acceso di default)
--   * push_subscriptions   i dispositivi che hanno attivato le notifiche push (visibili solo al proprietario)
--   * push_config          la chiave PUBBLICA VAPID per le push (la chiave privata NON sta mai nel database)
--   * funzioni notif_mark_read, notif_unread_count, notif_set_prefs, push_subscribe, push_unsubscribe, push_send_test (notifica di prova a se stessi), push_public_key, admin_set_push_key
--   * due trigger "a prova di errore" su taglie e sfide Ladder: se una notifica non si riesce a scrivere, la taglia o la sfida
--     vanno comunque a buon fine (le notifiche non possono mai bloccare l'economia)
-- Cosa NON fa: non tocca wallet, taglie, riscossioni, Ladder, premi o Shop; non scrive mai nulla sui saldi. La notifica di una
-- taglia NON rivela chi l'ha messa (l'autore può essere nascosto dall'impostazione show_bounty_authors).
-- L'invio vero e proprio delle push lo fa la Edge Function send-push (file send-push.ts), collegata alla tabella notifications
-- con un Database Webhook: senza quel passaggio le notifiche restano comunque visibili nell'app.
-- Annullamento: black-market-notifiche-down.sql (conserva le notifiche già scritte).
-- =====================================================================
begin;

insert into public.system_settings (key, value_int, description) values
 ('notifications_enabled', 1, 'Notifiche: 1 = attive, 0 = spente per tutti')
on conflict (key) do nothing;

-- ---------- Tabelle ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  kind text not null check (kind in ('bounty_received','ladder_challenge','bounty_challenge','test')),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 400),
  url text not null default 'black-market.html#/notifiche' check (url ~ '^[A-Za-z0-9_./#?=&-]{1,200}$'),   -- solo percorsi interni
  ref_type text,
  ref_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  read_at timestamptz,
  pushed_at timestamptz,                                           -- scritto dalla Edge Function quando la push è partita
  unique (user_id, kind, ref_id)                                   -- niente doppioni per lo stesso evento
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);
create index if not exists notifications_unread_idx on public.notifications (user_id) where read_at is null;

create table if not exists public.notification_prefs (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  bounty boolean not null default true,        -- taglia ricevuta
  ladder boolean not null default true,        -- sfida in Ladder
  hunt boolean not null default true,          -- sfida per la mia taglia
  updated_at timestamptz not null default now()
);

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  endpoint text not null unique check (endpoint ~ '^https://' and char_length(endpoint) <= 2048),
  p256dh text not null check (char_length(p256dh) between 20 and 200),
  auth text not null check (char_length(auth) between 8 and 100),
  user_agent text check (user_agent is null or char_length(user_agent) <= 300),
  created_at timestamptz not null default now(),
  last_ok_at timestamptz
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);

create table if not exists public.push_config (                    -- una sola riga: chiave PUBBLICA per le push
  id boolean primary key default true check (id),
  vapid_public text not null check (vapid_public ~ '^[A-Za-z0-9_-]{80,100}$'),
  updated_at timestamptz not null default now()
);

-- ---------- Punto unico di scrittura di una notifica (interno, non esposto) ----------
create or replace function public._notify(p_user uuid, p_kind text, p_title text, p_body text, p_url text, p_ref_type text, p_ref uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
begin
  if coalesce(public._setting('notifications_enabled'), 1) <> 1 then return; end if;
  select case p_kind when 'bounty_received' then coalesce(bounty, true) when 'ladder_challenge' then coalesce(ladder, true) else coalesce(hunt, true) end
    into v_ok from public.notification_prefs where user_id = p_user;
  if not found then v_ok := true; end if;                                              -- nessuna preferenza salvata = tutto acceso
  if not v_ok then return; end if;
  insert into public.notifications (user_id, kind, title, body, url, ref_type, ref_id) values (p_user, p_kind, p_title, p_body, p_url, p_ref_type, p_ref)
    on conflict (user_id, kind, ref_id) do nothing;
end $$;

-- ---------- Trigger: taglia ricevuta (mai bloccante, non rivela l'autore) ----------
create or replace function public._trg_notify_bounty() returns trigger language plpgsql security definer set search_path = public as $$
declare v_total integer;
begin
  begin
    if new.status = 'active' then
      select coalesce(sum(amount), 0)::integer into v_total from public.bounties where target_id = new.target_id and status = 'active';
      perform public._notify(new.target_id, 'bounty_received', 'Nuova taglia su di te',
        format('Una taglia da %s BC è stata messa su di te. Bounty Value attuale: %s BC.', new.amount, v_total),
        'black-market.html#/p/' || new.target_id, 'bounty', new.id);
    end if;
  exception when others then null;                                                     -- una notifica non deve mai far fallire una taglia
  end;
  return null;
end $$;
drop trigger if exists notify_bounty on public.bounties;
create trigger notify_bounty after insert on public.bounties for each row execute function public._trg_notify_bounty();

-- ---------- Trigger: sfida in Ladder (con variante "sfida per la taglia") ----------
create or replace function public._trg_notify_ladder() returns trigger language plpgsql security definer set search_path = public as $$
declare v_nick text; v_hunt integer; v_pref boolean;
begin
  begin
    if new.status = 'pending' then
      select nickname into v_nick from public.profiles where id = new.challenger_id;
      select coalesce(sum(amount), 0)::integer into v_hunt from public.bounties          -- la parte che il cacciatore potrebbe davvero incassare
        where target_id = new.opponent_id and status = 'active' and creator_id <> new.challenger_id;
      select coalesce(hunt, true) into v_pref from public.notification_prefs where user_id = new.opponent_id;
      if not found then v_pref := true; end if;
      if v_hunt > 0 and v_pref then
        perform public._notify(new.opponent_id, 'bounty_challenge', 'Sfida per la tua taglia!',
          format('%s ti ha sfidato in Ladder (%s) per riscuotere la taglia da %s BC che hai addosso.', coalesce(v_nick, 'Un duellante'), new.format, v_hunt),
          'black-market.html#/ladder', 'ladder_match', new.id);
      else                                                                              -- senza taglia (o con "sfida per la taglia" spento) è una sfida Ladder normale
        perform public._notify(new.opponent_id, 'ladder_challenge', 'Nuova sfida in Ladder',
          format('%s ti ha sfidato in Ladder (%s).', coalesce(v_nick, 'Un duellante'), new.format),
          'black-market.html#/ladder', 'ladder_match', new.id);
      end if;
    end if;
  exception when others then null;
  end;
  return null;
end $$;
drop trigger if exists notify_ladder on public.ladder_matches;
create trigger notify_ladder after insert on public.ladder_matches for each row execute function public._trg_notify_ladder();

-- ---------- Funzioni del giocatore ----------
create or replace function public.notif_mark_read(p_id uuid default null) returns integer language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]); n integer;
begin
  update public.notifications set read_at = clock_timestamp() where user_id = v and read_at is null and (p_id is null or id = p_id);
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.notif_unread_count() returns integer language plpgsql stable security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
begin
  return (select count(*)::integer from public.notifications where user_id = v and read_at is null);
end $$;

create or replace function public.notif_set_prefs(p_bounty boolean, p_ladder boolean, p_hunt boolean) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
begin
  insert into public.notification_prefs (user_id, bounty, ladder, hunt) values (v, coalesce(p_bounty, true), coalesce(p_ladder, true), coalesce(p_hunt, true))
    on conflict (user_id) do update set bounty = coalesce(p_bounty, public.notification_prefs.bounty), ladder = coalesce(p_ladder, public.notification_prefs.ladder),
                                        hunt = coalesce(p_hunt, public.notification_prefs.hunt), updated_at = now();
end $$;

create or replace function public.push_subscribe(p_endpoint text, p_p256dh text, p_auth text, p_ua text default null) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
begin
  if p_endpoint is null or p_endpoint !~ '^https://' or char_length(p_endpoint) > 2048 then raise exception 'Dispositivo non valido'; end if;
  if p_p256dh is null or p_auth is null then raise exception 'Chiavi del dispositivo mancanti'; end if;
  if not exists (select 1 from public.push_subscriptions where endpoint = p_endpoint and user_id = v)
     and (select count(*) from public.push_subscriptions where user_id = v) >= 10 then raise exception 'Hai già 10 dispositivi collegati: disattiva le notifiche su uno di questi'; end if;
  begin
    insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent) values (v, p_endpoint, p_p256dh, p_auth, left(p_ua, 300))
      on conflict (endpoint) do update set user_id = v, p256dh = excluded.p256dh, auth = excluded.auth, user_agent = excluded.user_agent;   -- stesso dispositivo, nuovo account: passa a chi ha fatto l'accesso
  exception when check_violation then raise exception 'Dati del dispositivo non validi'; end;
end $$;

create or replace function public.push_unsubscribe(p_endpoint text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
begin
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = v;     -- solo il proprio dispositivo
end $$;

create or replace function public.push_send_test() returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','admin']::public.app_role[]);
begin
  if coalesce(public._setting('notifications_enabled'), 1) <> 1 then raise exception 'Le notifiche sono spente'; end if;
  if exists (select 1 from public.notifications where user_id = v and kind = 'test' and created_at > clock_timestamp() - interval '20 seconds') then
    raise exception 'Aspetta qualche secondo prima di una nuova prova'; end if;
  insert into public.notifications (user_id, kind, title, body, url, ref_type, ref_id)
    values (v, 'test', 'Notifica di prova', 'Se vedi questo messaggio, le notifiche funzionano su questo dispositivo.', 'black-market.html#/notifiche', 'test', gen_random_uuid());
end $$;

create or replace function public.push_public_key() returns text language sql stable security definer set search_path = public as $$
  select vapid_public from public.push_config where id
$$;

create or replace function public.admin_set_push_key(p_key text, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]); o text;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  if p_key is null or p_key !~ '^[A-Za-z0-9_-]{80,100}$' then raise exception 'Chiave pubblica VAPID non valida'; end if;
  select vapid_public into o from public.push_config where id;
  insert into public.push_config (id, vapid_public) values (true, p_key) on conflict (id) do update set vapid_public = p_key, updated_at = now();
  perform public._audit(v, 'set_push_key', 'push_config', 'vapid', case when o is null then null else jsonb_build_object('public', o) end, jsonb_build_object('public', p_key), btrim(p_reason));
end $$;

-- ---------- Row Level Security e permessi ----------
alter table public.notifications enable row level security;
alter table public.notification_prefs enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.push_config enable row level security;
drop policy if exists notifications_own on public.notifications;
create policy notifications_own on public.notifications for select to authenticated using (user_id = auth.uid());
drop policy if exists notification_prefs_own on public.notification_prefs;
create policy notification_prefs_own on public.notification_prefs for select to authenticated using (user_id = auth.uid());
drop policy if exists push_subscriptions_own on public.push_subscriptions;
create policy push_subscriptions_own on public.push_subscriptions for select to authenticated using (user_id = auth.uid());
-- push_config: nessuna policy di lettura diretta; la chiave pubblica si legge solo con push_public_key()

revoke all on public.notifications, public.notification_prefs, public.push_subscriptions, public.push_config from public, anon, authenticated;
grant select on public.notifications, public.notification_prefs, public.push_subscriptions to authenticated;
revoke all on function public._notify(uuid, text, text, text, text, text, uuid), public._trg_notify_bounty(), public._trg_notify_ladder() from public, anon, authenticated;
revoke all on function public.notif_mark_read(uuid), public.notif_unread_count(), public.notif_set_prefs(boolean, boolean, boolean),
  public.push_subscribe(text, text, text, text), public.push_unsubscribe(text), public.push_send_test(), public.push_public_key(), public.admin_set_push_key(text, text) from public, anon, authenticated;
grant execute on function public.notif_mark_read(uuid), public.notif_unread_count(), public.notif_set_prefs(boolean, boolean, boolean),
  public.push_subscribe(text, text, text, text), public.push_unsubscribe(text), public.push_send_test(), public.push_public_key(), public.admin_set_push_key(text, text) to authenticated;
commit;
