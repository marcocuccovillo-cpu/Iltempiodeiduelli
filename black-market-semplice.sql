-- =====================================================================================
--  Black Market semplificato (migrazione 045)
--  1. Vetrina pubblica: classifica Ladder, Most Wanted e ultimi risultati visibili
--     anche a chi non ha un account (funzione public_showcase, nessun dato privato).
--  2. Primi passi: 4 obiettivi per i nuovi duellanti (foto, prima sfida, prima taglia,
--     primo match concluso), ognuno paga un bonus di BC una sola volta.
--  3. Impostazione unlock_matches: quante sfide concluse servono perché l'app mostri
--     Scommesse, Faction Wars e Underground nel menu (solo interfaccia, nessun blocco nel database).
--  Si può rieseguire senza danni. Annulla con black-market-semplice-down.sql
-- =====================================================================================
begin;

-- ---------- nuovo tipo di movimento: bonus dei primi passi ----------
do $$
declare d text; kinds text[];
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.ledger_entries'::regclass and conname = 'ledger_entries_kind_check';
  if d is null then raise exception 'Vincolo ledger_entries_kind_check non trovato'; end if;
  select array_agg(m[1]) into kinds from regexp_matches(d, '''([^'']+)''', 'g') as m;
  if not ('onboarding_bonus' = any (kinds)) then kinds := kinds || 'onboarding_bonus'::text; end if;
  alter table public.ledger_entries drop constraint ledger_entries_kind_check;
  execute 'alter table public.ledger_entries add constraint ledger_entries_kind_check check (kind in ('
    || (select string_agg(quote_literal(x), ',') from unnest(kinds) as x) || '))';
end $$;

-- ---------- impostazioni (modificabili da Admin › Impostazioni) ----------
insert into public.system_settings (key, value_int, description) values
 ('showcase_public',   1,   'Vetrina: 1 = classifica e Most Wanted visibili anche senza account, 0 = solo dopo l''accesso'),
 ('onboarding_enabled', 1,  'Primi passi: 1 = attivi (bonus ai nuovi duellanti), 0 = spenti'),
 ('onboarding_step_bc', 100, 'Primi passi: BC per ciascuno dei 4 obiettivi (foto, prima sfida, prima taglia, primo match)'),
 ('unlock_matches',    3,   'Menu: sfide concluse necessarie per mostrare Scommesse, Faction Wars e Underground (0 = sempre visibili)')
on conflict (key) do nothing;

-- ---------- 1. vetrina pubblica ----------
create or replace function public.public_showcase()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_on integer; v jsonb;
begin
  select value_int into v_on from public.system_settings where key = 'showcase_public';
  if coalesce(v_on, 1) <> 1 then return jsonb_build_object('on', false); end if;
  select jsonb_build_object(
    'on', true,
    'ladder', coalesce((select jsonb_object_agg(f, rows) from (
        select s.format as f, jsonb_agg(jsonb_build_object('nick', s.nickname, 'avatar', s.avatar, 'elo', s.elo, 'rank', s.rank,
                 'w', s.wins, 'd', s.draws, 'l', s.losses) order by s.rank) as rows
        from public.ladder_standings_v s join public.profiles p on p.id = s.user_id
        where not p.suspended and s.rank <= 10 and s.format is not null
        group by s.format) x), '{}'::jsonb),
    'wanted', coalesce((select jsonb_agg(jsonb_build_object('nick', w.nickname, 'avatar', w.avatar, 'value', w.bounty_value, 'count', w.active_count) order by w.bounty_value desc)
        from (select w.* from public.most_wanted_v w join public.profiles p on p.id = w.id where not p.suspended order by w.bounty_value desc limit 10) w), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(r order by r->>'at' desc) from (
        select jsonb_build_object('a', pa.nickname, 'b', pb.nickname, 'res', m.reported_result, 'score', m.reported_score, 'format', m.format, 'at', m.closed_at) as r
        from public.ladder_matches m join public.profiles pa on pa.id = m.challenger_id join public.profiles pb on pb.id = m.opponent_id
        where m.status = 'closed' order by m.closed_at desc limit 8) x), '[]'::jsonb),
    'counts', jsonb_build_object(
        'players', (select count(*) from public.profiles where not suspended),
        'bounty_bc', (select coalesce(sum(amount), 0) from public.bounties where status = 'active'),
        'matches_30d', (select count(*) from public.ladder_matches where status = 'closed' and closed_at > now() - interval '30 days')),
    'welcome_bc', (select value_int from public.system_settings where key = 'initial_bonus')
  ) into v;
  return v;
end $$;
revoke all on function public.public_showcase() from public;
grant execute on function public.public_showcase() to anon, authenticated;

-- ---------- 2. primi passi ----------
create or replace function public._onboarding_done(p_user uuid, p_step text)
returns boolean language sql stable security definer set search_path = public as $$
  select case p_step
    when 'photo'     then exists (select 1 from public.profiles where id = p_user and avatar_img is not null)
    when 'challenge' then exists (select 1 from public.ladder_matches where challenger_id = p_user and status not in ('cancelled'))
    when 'bounty'    then exists (select 1 from public.bounties where creator_id = p_user and status <> 'cancelled')
    when 'match'     then exists (select 1 from public.ladder_matches where status = 'closed' and p_user in (challenger_id, opponent_id))
                       or exists (select 1 from public.matches where status = 'verified' and p_user in (player_a, player_b))
    else false end
$$;
revoke all on function public._onboarding_done(uuid, text) from public;

create or replace function public.onboarding_state()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  v_on integer; v_bc integer; v_unlock integer; v_played integer; steps jsonb := '[]'::jsonb; s text;
begin
  select value_int into v_on from public.system_settings where key = 'onboarding_enabled';
  select value_int into v_bc from public.system_settings where key = 'onboarding_step_bc';
  select value_int into v_unlock from public.system_settings where key = 'unlock_matches';
  select count(*) into v_played from public.ladder_matches where status = 'closed' and v in (challenger_id, opponent_id);
  foreach s in array array['photo','challenge','bounty','match'] loop
    steps := steps || jsonb_build_object('step', s, 'done', public._onboarding_done(v, s),
      'claimed', exists (select 1 from public.ledger_entries where idempotency_key = 'onb:' || s || ':' || v));
  end loop;
  return jsonb_build_object('on', coalesce(v_on, 1) = 1, 'bc', coalesce(v_bc, 100), 'steps', steps,
    'played', v_played, 'unlock', coalesce(v_unlock, 3));
end $$;
revoke all on function public.onboarding_state() from public;
grant execute on function public.onboarding_state() to authenticated;

create or replace function public.onboarding_claim(p_step text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
  v_on integer; v_bc integer; v_bal integer;
begin
  if p_step is null or p_step not in ('photo','challenge','bounty','match') then raise exception 'Obiettivo sconosciuto'; end if;
  select value_int into v_on from public.system_settings where key = 'onboarding_enabled';
  if coalesce(v_on, 1) <> 1 then raise exception 'I primi passi non sono attivi'; end if;
  if not public._onboarding_done(v, p_step) then raise exception 'Obiettivo non ancora completato'; end if;
  select coalesce(value_int, 100) into v_bc from public.system_settings where key = 'onboarding_step_bc';
  v_bc := coalesce(v_bc, 100);
  if v_bc <= 0 then return jsonb_build_object('ok', true, 'bc', 0, 'already', false); end if;
  v_bal := public._ledger_move(v, v_bc, 'onboarding_bonus', 'onboarding', null, 'onb:' || p_step || ':' || v,
    'Primi passi: ' || case p_step when 'photo' then 'foto del profilo' when 'challenge' then 'prima sfida' when 'bounty' then 'prima taglia' else 'primo match' end);
  return jsonb_build_object('ok', true, 'bc', case when v_bal = -1 then 0 else v_bc end, 'already', v_bal = -1);
end $$;
revoke all on function public.onboarding_claim(text) from public;
grant execute on function public.onboarding_claim(text) to authenticated;

commit;
