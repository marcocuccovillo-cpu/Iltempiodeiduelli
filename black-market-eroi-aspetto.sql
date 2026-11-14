-- =====================================================================
-- MIGRAZIONE 044 — La guerra degli Eroi: ASPETTO DELL'EROE (sprite personalizzabile)
-- Da eseguire in Supabase (SQL Editor) DOPO le migrazioni della guerra degli Eroi (basta la 030 o successive).
--   Ogni eroe può scegliere come appare il suo personaggio pixel art (cruscotto, Torre, Raid, Locanda):
--     skin   colore della pelle      0–5
--     hair   colore dei capelli      0–7
--     hs     taglio                  0 corti · 1 lunghi · 2 cresta · 3 elmo
--     armor  colore dell'armatura    0–7
--     cape   colore del mantello     0–7, 8 = senza mantello
--     weapon arma                    0 spada · 1 ascia · 2 bastone magico · 3 lancia
--   È solo estetica: non cambia statistiche né BC. Gratis, si cambia quando si vuole.
--   game_set_look(p_look) salva l'aspetto (valori fuori dai limiti scartati); game_looks(p_users) restituisce gli aspetti di più eroi.
-- Si può rieseguire. Annullamento: black-market-eroi-aspetto-down.sql.
-- =====================================================================
begin;

create table if not exists public.game_hero_looks (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  look jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.game_hero_looks enable row level security;
revoke all on public.game_hero_looks from public, anon, authenticated;

create or replace function public.game_set_look(p_look jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]); out jsonb := '{}'::jsonb; k text; n integer;
  lim jsonb := '{"skin":6,"hair":8,"hs":4,"armor":8,"cape":9,"weapon":4}';
begin
  perform public._require_module('heroes');
  if p_look is null or jsonb_typeof(p_look) <> 'object' then raise exception 'Aspetto non valido'; end if;
  for k in select jsonb_object_keys(lim) loop
    if p_look ? k and jsonb_typeof(p_look->k) = 'number' then
      n := floor((p_look->>k)::numeric)::integer;
      if n >= 0 and n < (lim->>k)::integer then out := out || jsonb_build_object(k, n); end if;
    end if;
  end loop;
  insert into public.game_hero_looks (user_id, look, updated_at) values (v, out, now())
  on conflict (user_id) do update set look = excluded.look, updated_at = now();
  return jsonb_build_object('ok', true, 'look', out);
end $$;

create or replace function public.game_looks(p_users uuid[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v uuid := public._need_role(array['user','organizer','moderator','admin']::public.app_role[]);
begin
  perform public._require_module('heroes');
  return coalesce((select jsonb_object_agg(l.user_id::text, l.look) from public.game_hero_looks l
                    where l.user_id = any ((coalesce(p_users, array[]::uuid[]))[1:300])), '{}'::jsonb);
end $$;

revoke all on function public.game_set_look(jsonb) from public, anon;
revoke all on function public.game_looks(uuid[]) from public, anon;
grant execute on function public.game_set_look(jsonb) to authenticated;
grant execute on function public.game_looks(uuid[]) to authenticated;

commit;
