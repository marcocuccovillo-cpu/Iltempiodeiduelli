// =====================================================================
// send-push.ts — Edge Function di Supabase che invia le notifiche PUSH ("Il Tempio Dei Duelli").
//
// NON è una pagina del sito: questo file non serve a GitHub Pages. Si incolla in Supabase:
//   Dashboard → Edge Functions → Create a new function → nome: send-push → incolla questo file → Deploy.
// Poi (una volta sola) si collega alla tabella delle notifiche — i passi completi sono nel README, sezione «Notifiche push».
//
// Come lavora: il Database Webhook (INSERT sulla tabella notifications) la chiama a ogni nuova notifica; la funzione
// controlla il segreto condiviso, rilegge la notifica dal database (non si fida del testo ricevuto), prende i dispositivi
// DEL DESTINATARIO e invia la push cifrata (Web Push, VAPID). I dispositivi non più validi (404/410) vengono tolti.
// Non muove mai BC e non scrive su nulla se non pushed_at/last_ok_at e la rimozione dei dispositivi scaduti.
//
// Segreti da impostare (Edge Functions → send-push → Secrets; SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY ci sono già):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY   generate con:  npx web-push generate-vapid-keys
//   VAPID_SUBJECT                         per esempio  mailto:tuo@indirizzo.it
//   PUSH_WEBHOOK_SECRET                   una stringa lunga a caso, la stessa che metti nell'intestazione del Webhook
// La chiave PRIVATA resta solo qui: nel database e nel sito va solo quella pubblica.
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// confronto a tempo costante del segreto
function same(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });

export async function handle(req, env, sb, wp) {
  if (req.method !== "POST") return json({ error: "metodo non consentito" }, 405);
  if (!env.secret || !same(req.headers.get("x-webhook-secret") || "", env.secret)) return json({ error: "non autorizzato" }, 401);
  let body;
  try { body = await req.json(); } catch (_) { return json({ error: "JSON non valido" }, 400); }
  const id = body && body.record && body.record.id;
  if (body?.type !== "INSERT" || body?.table !== "notifications" || typeof id !== "string" || !UUID.test(id)) return json({ error: "evento non valido" }, 400);

  // si rilegge dal database: titolo, testo e destinatario non si prendono dal messaggio ricevuto
  const { data: n, error: e1 } = await sb.from("notifications").select("id,user_id,kind,title,body,url,pushed_at").eq("id", id).maybeSingle();
  if (e1) return json({ error: "lettura notifica fallita" }, 500);
  if (!n) return json({ skipped: "notifica inesistente" });
  if (n.pushed_at) return json({ skipped: "già inviata" });
  const { data: subs, error: e2 } = await sb.from("push_subscriptions").select("id,endpoint,p256dh,auth").eq("user_id", n.user_id);
  if (e2) return json({ error: "lettura dispositivi fallita" }, 500);
  if (!subs || !subs.length) return json({ sent: 0, devices: 0 });

  const payload = JSON.stringify({ title: n.title, body: n.body, url: n.url, tag: n.kind + ":" + n.id });
  let sent = 0, removed = 0, failed = 0;
  await Promise.all(subs.map(async (s) => {
    try {
      await wp.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400, urgency: "high" });
      sent++;
      await sb.from("push_subscriptions").update({ last_ok_at: new Date().toISOString() }).eq("id", s.id);
    } catch (err) {
      if (err && (err.statusCode === 404 || err.statusCode === 410)) { removed++; await sb.from("push_subscriptions").delete().eq("id", s.id); }   // dispositivo disinstallato o permesso revocato
      else failed++;
    }
  }));
  if (sent > 0) await sb.from("notifications").update({ pushed_at: new Date().toISOString() }).eq("id", n.id);
  return json({ sent, removed, failed, devices: subs.length });
}

// avvio su Supabase (non parte durante i test)
if (typeof Deno !== "undefined" && Deno.serve && !Deno.env.get("PUSH_TEST")) {
  const env = { secret: Deno.env.get("PUSH_WEBHOOK_SECRET") };
  const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
  webpush.setVapidDetails(Deno.env.get("VAPID_SUBJECT") || "mailto:admin@example.com", Deno.env.get("VAPID_PUBLIC_KEY"), Deno.env.get("VAPID_PRIVATE_KEY"));
  Deno.serve((req) => handle(req, env, sb, webpush));
}
