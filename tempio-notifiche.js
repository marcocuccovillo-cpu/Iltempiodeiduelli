/* =====================================================================
   IL TEMPIO DEI DUELLI — CAMPANELLA NOTIFICHE SU TUTTE LE PAGINE
   Mostra in alto a destra la campanella con il numero delle notifiche non lette
   (taglie ricevute, sfide in Ladder, sfide per la taglia) su Home, Sentiero, Gestisci torneo,
   Match Pro e Deck Analyzer. Toccandola si apre la pagina Notifiche del Black Market.
   Il Black Market ha già la sua campanella (black-market-notifiche.js): questo file non va caricato lì.

   Come lavora, con discrezione:
   - se non c'è un accesso salvato sul dispositivo non fa nulla: non scarica niente e non contatta nessuno;
   - altrimenti carica la stessa libreria di accesso del Black Market, usa lo stesso account (stesso accesso unico)
     e chiede al database solo due cose: se le notifiche sono attive e quante non ne ha lette;
   - non scrive nulla, non legge il contenuto delle notifiche, non muove BC;
   - se la migrazione 009 manca o qualcosa non risponde, la campanella semplicemente non compare.
   Le notifiche push (ad app chiusa) non dipendono da questo file: le gestisce il service worker (sw.js).
   ===================================================================== */
(function () {
  'use strict';
  var URL_SB = 'https://ceujhsmdvbcoszehbhxp.supabase.co', KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNldWpoc21kdmJjb3N6ZWhiaHhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI0MDk4OTMsImV4cCI6MjEwNzk4NTg5M30.b9qzjnHZQJTbZCVY-3xPrQPQd_HdqKqKJALZFlrNUj4';
  var LIB = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js';
  var TARGET = 'black-market.html#/notifiche';
  if (window.__tempioNotif) return; window.__tempioNotif = 1;
  if (/black-market\.html$/.test(location.pathname)) return;   // lì c'è già la sua campanella

  function hasSession() {
    try { for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); if (/^sb-.*-auth-token$/.test(k)) return true; } } catch (e) { /* storage bloccato */ }
    return false;
  }
  if (!hasSession()) return;
  document.documentElement.classList.add('has-bell');   // su computer lascia subito lo spazio alla campanella: niente scatti quando compare
  var cssDone = false;

  var sb = null, bell = null, unread = 0, last = null, timer = 0, lastAt = 0, ok = false;
  var BELL = '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9a6 6 0 0 1 12 0c0 6 2.5 7.5 2.5 7.5h-17S6 15 6 9z"/><path d="M10 20a2 2 0 0 0 4 0"/></svg>';

  function css() {
    if (cssDone) return; cssDone = true;
    var s = document.createElement('style');
    s.textContent = '.nf-bell{position:fixed;top:5px;right:10px;z-index:950;display:grid;place-items:center;width:46px;height:46px;padding:0;border-radius:12px;border:1px solid var(--line,#12304d);background:rgba(3,8,22,.92);color:var(--cy2,#6ff0ff);cursor:pointer;backdrop-filter:blur(8px)}' +
      '.nf-bell[hidden]{display:none}.nf-bell:hover{border-color:var(--ac,#00e5ff);color:var(--ac,#00e5ff)}' +
      '.nb{position:absolute;top:-6px;right:-6px;display:grid;place-items:center;min-width:20px;height:20px;padding:0 5px;border-radius:99px;border:2px solid #030816;background:#e5304a;color:#fff;font:700 .72rem system-ui,sans-serif;line-height:1;box-sizing:content-box}' +
      '.nf-toast{position:fixed;left:50%;bottom:20px;transform:translateX(-50%);z-index:960;max-width:min(92vw,420px);padding:12px 16px;border-radius:12px;border:1px solid var(--ac,#00e5ff);background:#030816;color:#fff;font:600 .95rem system-ui,sans-serif;box-shadow:0 6px 24px rgba(0,0,0,.5)}' +
      '@media(min-width:720px){.nf-bell{top:14px;right:18px}html.has-bell{padding-top:64px}html.has-bell .tabs{padding-right:68px}}';
    document.head.appendChild(s);
  }
  function paint() {
    if (!bell) return;
    bell.hidden = !ok; document.documentElement.classList.toggle('has-bell', ok); if (!ok) return;
    var t = unread > 99 ? '99+' : String(unread);
    if (bell.dataset.k === t) return; bell.dataset.k = t;
    bell.setAttribute('aria-label', unread > 0 ? 'Notifiche: ' + unread + ' non lette' : 'Notifiche');
    bell.innerHTML = BELL + (unread > 0 ? '<span class="nb" aria-hidden="true">' + t + '</span>' : '');
  }
  function toast(msg) {
    var d = document.createElement('div'); d.className = 'nf-toast'; d.setAttribute('role', 'status'); d.textContent = msg;
    d.onclick = function () { location.href = TARGET };
    document.body.appendChild(d); setTimeout(function () { d.remove() }, 5000);
  }
  function make() {
    css();
    bell = document.createElement('button'); bell.type = 'button'; bell.className = 'nf-bell'; bell.hidden = true; bell.setAttribute('aria-label', 'Notifiche');
    bell.onclick = function () { location.href = TARGET };
    document.body.appendChild(bell);
  }
  function refresh(force) {
    if (!sb || (!force && Date.now() - lastAt < 20000)) return;
    lastAt = Date.now();
    sb.auth.getSession().then(function (r) {
      if (!r || !r.data || !r.data.session) { ok = false; paint(); return null; }
      return sb.from('system_settings').select('value_int').eq('key', 'notifications_enabled').then(function (s) {
        var on = !s.error && s.data && s.data[0] && s.data[0].value_int === 1;
        if (!on) { ok = false; paint(); return null; }
        return sb.rpc('notif_unread_count', {}).then(function (c) {
          if (c.error || typeof c.data !== 'number') { ok = false; paint(); return; }
          if (last !== null && c.data > last) toast('Hai una nuova notifica.');
          last = unread = c.data; ok = true; paint();
        });
      });
    }).catch(function () { /* offline: nessun rumore */ });
  }
  function start() {
    if (!window.supabase || !window.supabase.createClient) return;
    try { sb = window.supabase.createClient(URL_SB, KEY, { auth: { persistSession: true, autoRefreshToken: true } }); } catch (e) { return; }
    make(); refresh(true);
    setInterval(function () { if (!document.hidden) refresh(true) }, 60000);
    document.addEventListener('visibilitychange', function () { if (!document.hidden) refresh(true) });
    sb.auth.onAuthStateChange(function (ev) { if (ev === 'SIGNED_OUT') { ok = false; paint(); } else if (ev === 'SIGNED_IN') refresh(true); });
  }
  function boot() {
    css();
    if (window.supabase) { start(); return; }
    var s = document.createElement('script'); s.src = LIB; s.async = true; s.onload = start; s.onerror = function () { /* senza rete: niente campanella */ };
    document.head.appendChild(s);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
