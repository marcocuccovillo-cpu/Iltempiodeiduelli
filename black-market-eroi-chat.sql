-- =====================================================================
-- LA GUERRA DEGLI EROI — CHAT PUBBLICA E «CHI È ONLINE» (da eseguire DOPO black-market-eroi-boss-attacco.sql)
--
-- Aggiunge, SOLO dentro La guerra degli Eroi:
--  * una chat unica, visibile a tutti gli eroi (nessun messaggio privato, nessuna stanza);
--  * la presenza: chi ha la pagina del gioco aperta risulta «online» (si vede in Classifica e nella Chat).
-- Regole:
--  * messaggi da 1 a 300 caratteri (spazi e caratteri di controllo ripuliti; i caratteri invisibili/di inversione testo sono tolti);
--  * al massimo 1 messaggio ogni 2 secondi e 20 al minuto per persona;
--  * si conservano gli ultimi 500 messaggi e comunque non oltre 7 giorni;
--  * online = visto negli ultimi 90 secondi (la pagina si segnala ogni 40 secondi);
--  * moderatori e amministratori possono nascondere un messaggio (con motivazione, scritta nell'audit);
--  * i messaggi di un account sospeso non si vedono più.
-- Garanzie: le due tabelle non sono leggibili né scrivibili direttamente dal browser (solo tramite le funzioni qui sotto);
-- la chat non tocca BC, XP, energia, oggetti, boss, dungeon, Ladder, taglie né notifiche; con il modulo «heroes» spento
-- tutte le funzioni (tranne «nascondi») rifiutano l'operazione. Si può rieseguire.
-- Annullamento: black-market-eroi-chat-down.sql
-- =====================================================================
begin;

create table if not exists public.game_chat (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 300),
  created_at timestamptz not null default clock_timestamp(),
  hidden boolean not null default false,
  hidden_by uuid references public.profiles(id) on delete set null,
  hidden_at timestamptz
);
create index if not exists game_chat_user_idx on public.game_chat (user_id, created_at desc);
create index if not exists game_chat_at_idx on public.game_chat (created_at);
alter table public.game_chat enable row level security;
revoke all on public.game_chat from public, anon, authenticated;

create table if not exists public.game_presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  seen_at timestamptz not null default clock_timestamp()
);
alter table public.game_presence enable row level security;
revoke all on public.game_presence from public, anon, authenticated;

-- invio di un messaggio
create or replace function public.game_chat_send(p_text text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  t text; r public.game_chat%rowtype; nick text;
begin
  perform public._require_module('heroes');
  t := coalesce(p_text, '');
  t := regexp_replace(t, '[\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]', '', 'g');      -- invisibili e inversione del testo
  t := regexp_replace(t, '[[:cntrl:]]', ' ', 'g');
  t := left(btrim(regexp_replace(t, '\s+', ' ', 'g')), 300);
  if char_length(t) < 1 then raise exception 'Scrivi qualcosa'; end if;
  perform pg_advisory_xact_lock(hashtext('game_chat:' || v::text));                       -- stessi limiti anche con invii simultanei
  if exists (select 1 from public.game_chat where user_id = v and created_at > clock_timestamp() - interval '2 seconds') then
    raise exception 'Troppo veloce: aspetta un attimo';
  end if;
  if (select count(*) from public.game_chat where user_id = v and created_at > clock_timestamp() - interval '1 minute') >= 20 then
    raise exception 'Troppi messaggi: aspetta qualche secondo';
  end if;
  insert into public.game_chat (user_id, body) values (v, t) returning * into r;
  insert into public.game_presence (user_id, seen_at) values (v, clock_timestamp())
    on conflict (user_id) do update set seen_at = excluded.seen_at;
  delete from public.game_chat where id <= r.id - 500;
  delete from public.game_chat where created_at < clock_timestamp() - interval '7 days';
  select nickname into nick from public.profiles where id = v;
  return jsonb_build_object('id', r.id, 'u', v, 'n', nick, 'at', extract(epoch from r.created_at)::bigint, 't', r.body);
end $$;

-- elenco messaggi: senza parametro gli ultimi 60; con p_after solo i nuovi (al massimo 100)
create or replace function public.game_chat_list(p_after bigint default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
begin
  perform public._require_module('heroes');
  return jsonb_build_object(
    'me', v,
    'staff', exists (select 1 from public.profiles where id = v and role in ('moderator','admin')),
    'last_id', coalesce((select max(c.id) from public.game_chat c join public.profiles p on p.id = c.user_id where not c.hidden and not p.suspended), 0),
    'msgs', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.id) from (
        select c.id, c.user_id as u, p.nickname as n, extract(epoch from c.created_at)::bigint as at, c.body as t, h.avatar_card as ac, h.avatar_name as an
        from public.game_chat c join public.profiles p on p.id = c.user_id left join public.game_heroes h on h.user_id = c.user_id
        where not c.hidden and not p.suspended and (p_after is null or c.id > p_after)
        order by c.id desc
        limit case when p_after is null then 60 else 100 end) m), '[]'::jsonb));
end $$;

-- «ci sono»: la pagina la chiama all'apertura e ogni 40 secondi; restituisce l'ultimo messaggio visibile (per il contatore dei non letti)
create or replace function public.game_presence_ping() returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
begin
  perform public._require_module('heroes');
  insert into public.game_presence (user_id, seen_at) values (v, clock_timestamp())
    on conflict (user_id) do update set seen_at = excluded.seen_at;
  delete from public.game_presence where seen_at < clock_timestamp() - interval '1 day';
  return jsonb_build_object('last_id', coalesce((select max(c.id) from public.game_chat c join public.profiles p on p.id = c.user_id where not c.hidden and not p.suspended), 0));
end $$;

-- chi è online adesso (visto negli ultimi 90 secondi): solo id, nickname e avatar
create or replace function public.game_online() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
begin
  perform public._require_module('heroes');
  return coalesce((
    select jsonb_agg(jsonb_build_object('u', s.user_id, 'n', s.nickname, 'ac', s.avatar_card, 'an', s.avatar_name) order by lower(s.nickname), s.user_id) from (
      select g.user_id, p.nickname, h.avatar_card, h.avatar_name
      from public.game_presence g join public.profiles p on p.id = g.user_id left join public.game_heroes h on h.user_id = g.user_id
      where g.seen_at > clock_timestamp() - interval '90 seconds' and not p.suspended) s), '[]'::jsonb);
end $$;

-- moderazione: nasconde un messaggio (moderatori e amministratori), con motivazione, scritta nell'audit
create or replace function public.game_chat_hide(p_id bigint, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['moderator','admin']::public.app_role[]); c public.game_chat%rowtype;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then raise exception 'Motivazione obbligatoria'; end if;
  select * into c from public.game_chat where id = p_id for update;
  if not found then raise exception 'Messaggio inesistente'; end if;
  if c.hidden then raise exception 'Messaggio già nascosto'; end if;
  update public.game_chat set hidden = true, hidden_by = v, hidden_at = clock_timestamp() where id = p_id;
  perform public._audit(v, 'game_chat_hide', 'game_chat', p_id::text, jsonb_build_object('user_id', c.user_id, 'body', c.body), jsonb_build_object('hidden', true), btrim(p_reason));
end $$;

revoke all on function public.game_chat_send(text), public.game_chat_list(bigint), public.game_presence_ping(), public.game_online(), public.game_chat_hide(bigint, text) from public, anon;
grant execute on function public.game_chat_send(text), public.game_chat_list(bigint), public.game_presence_ping(), public.game_online(), public.game_chat_hide(bigint, text) to authenticated;
commit;
