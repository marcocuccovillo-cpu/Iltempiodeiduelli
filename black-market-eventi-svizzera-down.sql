-- =====================================================================
-- ANNULLAMENTO della MIGRAZIONE 032 (eventi «Torneo svizzero», durata, annullamento eventi)
-- Toglie funzioni, tabelle dei riposi e dei risultati in attesa, e le colonne nuove di events e event_participants.
-- Cosa resta: i match già creati (anche quelli dei tornei svizzeri, verificati o in attesa) e le iscrizioni: sono dati normali dell'evento;
-- i match ancora in attesa si verificano con la pagina dell'organizzatore come sempre.
-- Cosa si perde: il formato svizzero, la durata, lo stato (in corso / concluso / annullato: gli eventi annullati tornano «normali»),
-- i riposi e le vittorie a tavolino, i risultati indicati dai giocatori e non ancora confermati.
-- Nessun BC, saldo o movimento del registro viene toccato (la 032 non ne crea).
-- =====================================================================
begin;
drop trigger if exists matches_event_guard on public.matches;
drop function if exists public._trg_matches_event_guard();
drop function if exists public.swiss_state(uuid);
drop function if exists public.cancel_event(uuid, text);
drop function if exists public.swiss_decide(uuid, uuid);
drop function if exists public.swiss_dispute(uuid);
drop function if exists public.swiss_report(uuid, uuid);
drop function if exists public.swiss_finish(uuid);
drop function if exists public.swiss_next_round(uuid);
drop function if exists public.swiss_start(uuid, integer);
drop function if exists public.swiss_set_rounds(uuid, integer);
drop function if exists public.swiss_kick(uuid, uuid);
drop function if exists public.swiss_leave(uuid);
drop function if exists public.swiss_join(uuid);
drop function if exists public.create_event_ex(text, date, integer, boolean);
drop function if exists public._swiss_drop(uuid, uuid, uuid);
drop function if exists public._swiss_close(uuid, uuid, uuid);
drop function if exists public._swiss_make_round(uuid, integer, uuid);
drop function if exists public._swiss_try(uuid, uuid[], boolean);
drop function if exists public._swiss_table(uuid);
drop function if exists public._swiss_auto_rounds(integer);
drop function if exists public._swiss_today();
drop table if exists public.event_match_reports;
drop table if exists public.event_byes;
alter table public.event_participants drop column if exists dropped_at, drop column if exists dropped;
alter table public.events drop column if exists cancel_reason, drop column if exists cancelled_by, drop column if exists cancelled_at, drop column if exists finished_at,
  drop column if exists started_at, drop column if exists current_round, drop column if exists rounds_planned, drop column if exists duration_days,
  drop column if exists event_status, drop column if exists event_format;
commit;
