-- =====================================================================
-- MIGRAZIONE 012 — PANNELLO AMMINISTRATORE: EMAIL DEGLI UTENTI
-- Da eseguire in Supabase (SQL Editor) DOPO la 011 (black-market-ladder-formati.sql). Si può rieseguire senza danni.
--
-- Aggiunge una sola funzione, admin_user_overview():
--   * solo l'amministratore può chiamarla (organizzatori, moderatori e duellanti ricevono un errore);
--   * per ogni profilo restituisce id, email (da Supabase Auth) e se ha attivato «Accetto taglie su di me»;
--   * sola lettura: non scrive nulla, non tocca BC, wallet, registro, taglie, Ladder, Shop;
--   * il browser continua a non poter leggere la tabella auth.users: l'email passa solo da questa funzione.
-- =====================================================================
begin;
create or replace function public.admin_user_overview() returns table (id uuid, email text, wanted_enabled boolean)
language plpgsql stable security definer set search_path = public as $$
declare v uuid := public._need_role(array['admin']::public.app_role[]);
begin
  return query
    select p.id, u.email::text, p.wanted_enabled
    from public.profiles p left join auth.users u on u.id = p.id
    order by lower(p.nickname);
end $$;
revoke all on function public.admin_user_overview() from public, anon, authenticated;
grant execute on function public.admin_user_overview() to authenticated;
commit;
