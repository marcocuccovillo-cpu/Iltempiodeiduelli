-- =====================================================================
-- MIGRAZIONE 014 — La guerra degli Eroi: avatar preso da una carta Yu-Gi-Oh!
-- Da eseguire in Supabase (SQL Editor) DOPO la 013 (black-market-eroi.sql). Si può rieseguire.
-- Salva solo il NUMERO dell'immagine della carta (e il suo nome): la pagina costruisce da sola l'indirizzo dell'immagine ritagliata
-- (images.ygoprodeck.com/images/cards_cropped/<numero>.jpg). Nessun indirizzo scritto dagli utenti entra nel database.
-- Non tocca BC, wallet, registro, taglie, Ladder o Shop.
-- =====================================================================
begin;

alter table public.game_heroes add column if not exists avatar_card integer;
alter table public.game_heroes add column if not exists avatar_name text;
alter table public.game_heroes drop constraint if exists game_heroes_avatar_chk;
alter table public.game_heroes add constraint game_heroes_avatar_chk
  check ((avatar_card is null and avatar_name is null) or (avatar_card between 1 and 999999999 and char_length(avatar_name) between 1 and 80));

-- imposta (o toglie, passando null) l'avatar del proprio eroe
create or replace function public.game_set_avatar(p_card integer, p_name text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); n text := nullif(btrim(coalesce(p_name, '')), '');
begin
  perform public._require_module('heroes');
  perform public._game_ensure_hero(v);
  if p_card is null then
    update public.game_heroes set avatar_card = null, avatar_name = null where user_id = v;
    return jsonb_build_object('avatar_card', null, 'avatar_name', null);
  end if;
  if p_card < 1 or p_card > 999999999 then raise exception 'Carta non valida'; end if;
  if n is null then raise exception 'Nome della carta mancante'; end if;
  n := left(regexp_replace(n, '[[:cntrl:]]', '', 'g'), 80);
  if n = '' then raise exception 'Nome della carta mancante'; end if;
  update public.game_heroes set avatar_card = p_card, avatar_name = n where user_id = v;
  return jsonb_build_object('avatar_card', p_card, 'avatar_name', n);
end $$;

revoke all on function public.game_set_avatar(integer, text) from public, anon, authenticated;
grant execute on function public.game_set_avatar(integer, text) to authenticated;
commit;
