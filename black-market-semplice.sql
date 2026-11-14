-- =====================================================================================
--  Black Market semplificato (migrazione 045)
--  1. Vetrina pubblica nel Black Market: usa la funzione public_showcase() che già
--     alimenta la Home (nessuna funzione nuova). La prima versione di questa migrazione
--     la sovrascriveva per errore e la Home mostrava «Duellante» e zeri: rieseguendo
--     questo file la funzione originale viene RIPRISTINATA.
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
 ('onboarding_enabled', 1,  'Primi passi: 1 = attivi (bonus ai nuovi duellanti), 0 = spenti'),
 ('onboarding_step_bc', 100, 'Primi passi: BC per ciascuno dei 4 obiettivi (foto, prima sfida, prima taglia, primo match)'),
 ('unlock_matches',    3,   'Menu: sfide concluse necessarie per mostrare Scommesse, Faction Wars e Underground (0 = sempre visibili)')
on conflict (key) do nothing;

-- ---------- 1. riparazione: ripristina public_showcase() se la prima versione di questo file l'ha sovrascritta ----------
delete from public.system_settings where key = 'showcase_public';
do $do$
begin
  if exists (select 1 from pg_proc where oid = to_regprocedure('public.public_showcase()') and prosrc like '%showcase_public%') then
    if to_regprocedure('public._public_showcase_base()') is null then
      raise exception 'public_showcase() va ripristinata ma manca _public_showcase_base(): riesegui black-market-inviti.sql e poi black-market-eroi-raid.sql';
    end if;
    execute $wrap$
create or replace function public.public_showcase() returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare s jsonb := coalesce(public._public_showcase_base(), '{}'::jsonb); g public.game_raids%rowtype; b public.game_raid_bosses%rowtype;
begin
  if public._module_on('heroes') and coalesce(public._setting('game_raid_enabled'), 0) = 1 then
    select * into g from public.game_raids where week_start = public._raid_week();
    if found then
      select * into b from public.game_raid_bosses where no = g.boss_no;
      s := s || jsonb_build_object('raid', jsonb_build_object('name', b.name, 'emoji', b.emoji, 'hp', g.hp, 'max_hp', g.max_hp, 'status', g.status,
        'ends_at', public._raid_ends_at(g.week_start), 'participants', (select count(*) from public.game_raid_damage d where d.raid_id = g.id and d.dmg > 0),
        'top', coalesce((select jsonb_agg(jsonb_build_object('n', p.nickname, 'dmg', x.dmg) order by x.dmg desc)
                 from (select * from public.game_raid_damage where raid_id = g.id and dmg > 0 order by dmg desc limit 3) x join public.profiles p on p.id = x.user_id), '[]'::jsonb)));
    else
      s := s || jsonb_build_object('raid', jsonb_build_object('status', 'waiting'));
    end if;
  end if;
  return s;
end $fn$;
    $wrap$;
    revoke all on function public.public_showcase() from public;
    grant execute on function public.public_showcase() to anon, authenticated;
    raise notice 'public_showcase() ripristinata: la Home torna a mostrare nomi e numeri.';
  end if;
end $do$;

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
