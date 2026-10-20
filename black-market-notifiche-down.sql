-- =====================================================================
-- ANNULLAMENTO della migrazione 009 (black-market-notifiche.sql).
-- Cosa fa: toglie i due trigger (da subito taglie e sfide non generano più notifiche), le funzioni e l'impostazione notifications_enabled.
-- Cosa NON fa: le tabelle notifications, notification_prefs, push_subscriptions e push_config RESTANO con tutto il loro contenuto
-- (nessuno storico si cancella); senza le funzioni nessuno può più segnare notifiche come lette né registrare dispositivi,
-- e l'app mostra il Black Market senza la sezione Notifiche. Taglie, sfide, wallet e Shop non cambiano in nessun modo.
-- Se hai collegato il Database Webhook alla Edge Function send-push, toglilo dalla Dashboard (Database → Webhooks).
-- Per rimettere le notifiche basta rieseguire black-market-notifiche.sql: le notifiche già scritte ricompaiono intatte.
-- =====================================================================
begin;
drop trigger if exists notify_bounty on public.bounties;
drop trigger if exists notify_ladder on public.ladder_matches;
drop function if exists public._trg_notify_bounty();
drop function if exists public._trg_notify_ladder();
drop function if exists public._notify(uuid, text, text, text, text, text, uuid);
drop function if exists public.notif_mark_read(uuid);
drop function if exists public.notif_unread_count();
drop function if exists public.notif_set_prefs(boolean, boolean, boolean);
drop function if exists public.push_subscribe(text, text, text, text);
drop function if exists public.push_unsubscribe(text);
drop function if exists public.push_send_test();
drop function if exists public.push_public_key();
drop function if exists public.admin_set_push_key(text, text);
delete from public.system_settings where key = 'notifications_enabled';
commit;
