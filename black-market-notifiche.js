/* =====================================================================
   BLACK MARKET — NOTIFICHE (migrazione 009)
   Pagina #/notifiche: elenco delle notifiche (taglia ricevuta, sfida in Ladder, sfida per la taglia),
   cosa ricevere, attivazione delle notifiche PUSH su questo dispositivo, notifica di prova.
   In alto a destra c'è la campanella con il numero delle notifiche non lette.
   Le notifiche nascono nel database (trigger); le push le invia la Edge Function send-push.
   Se la migrazione manca, la voce di menu non compare e il resto del Black Market non cambia.
   ===================================================================== */
window.BM_NOTIF = function (BM) {
  'use strict';
  const { R, shell, q, rpc, toast, esc, when } = BM;
  const KIND = { bounty_received: ['Taglia', 'r'], ladder_challenge: ['Ladder', 'g'], bounty_challenge: ['Sfida per la taglia', 'g'], test: ['Prova', ''] };
  const isAdm = () => BM.me && BM.me.role === 'admin';
  const present = () => BM.S && BM.S.notifications_enabled !== undefined;
  const on = () => present() && BM.S.notifications_enabled === 1;

  /* ---------- campanella in alto a destra, con il numero delle non lette ---------- */
  let unread = 0, last = null, lastAt = 0, bell = null;
  const BELL = '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9a6 6 0 0 1 12 0c0 6 2.5 7.5 2.5 7.5h-17S6 15 6 9z"/><path d="M10 20a2 2 0 0 0 4 0"/></svg>';
  const paint = () => {
    if (!bell) return;
    const show = on() && !!BM.me; bell.hidden = !show; document.documentElement.classList.toggle('has-bell', show); if (!show) return;
    const t = unread > 99 ? '99+' : String(unread), cur = location.hash.indexOf('#/notifiche') === 0, key = t + '|' + cur;
    if (bell.dataset.k === key) return; bell.dataset.k = key;   // nessun ridisegno se non è cambiato nulla
    bell.setAttribute('aria-label', unread > 0 ? `Notifiche: ${unread} non lette` : 'Notifiche');
    bell.innerHTML = BELL + (unread > 0 ? `<span class="nb" aria-hidden="true">${t}</span>` : '');
    if (cur) bell.setAttribute('aria-current', 'page'); else bell.removeAttribute('aria-current');
  };
  async function refresh(force) {
    if (!on() || !BM.me || (!force && Date.now() - lastAt < 20000)) return;
    lastAt = Date.now();
    try {
      const n = await rpc('notif_unread_count', {});
      if (last !== null && n > last) toast('Hai una nuova notifica.');
      last = unread = n; paint();
    } catch (e) { /* offline o migrazione assente: nessun rumore */ }
  }
  const css = document.createElement('style');
  css.textContent = `.nf-bell{position:fixed;top:5px;right:10px;z-index:950;display:grid;place-items:center;width:46px;height:46px;padding:0;border-radius:12px;border:1px solid var(--line);background:rgba(3,8,22,.92);color:var(--cy2);cursor:pointer;backdrop-filter:blur(8px)}
.nf-bell[hidden]{display:none}.nf-bell:hover,.nf-bell[aria-current]{border-color:var(--ac);color:var(--ac)}
.nb{position:absolute;top:-6px;right:-6px;display:grid;place-items:center;min-width:20px;height:20px;padding:0 5px;border-radius:99px;border:2px solid #030816;background:#e5304a;color:#fff;font:700 .72rem var(--ui);line-height:1;box-sizing:content-box}
@media(min-width:720px){.nf-bell{top:14px;right:18px}html.has-bell .bm-nav{margin-right:56px}}
.nf-item{border-left:3px solid transparent;padding-left:10px}.nf-item.un{border-left-color:var(--gold);background:rgba(212,168,67,.06)}
.nf-item b{color:var(--tx)}.nf-st{display:flex;gap:10px;align-items:center;flex-wrap:wrap}`;
  document.head.appendChild(css);
  bell = document.createElement('button'); bell.type = 'button'; bell.className = 'nf-bell'; bell.hidden = true; bell.setAttribute('aria-label', 'Notifiche');
  bell.onclick = () => { location.hash = '#/notifiche' };
  document.body.appendChild(bell);
  BM.navItems = (prev => () => { refresh(); paint(); return prev ? prev() : [] })(BM.navItems);
  setInterval(() => { if (!document.hidden) refresh(true) }, 60000);
  setInterval(paint, 1500);   // la campanella sparisce da sola quando si esce dall'account
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(true) });
  window.addEventListener('hashchange', paint);

  /* ---------- push: stato di questo dispositivo ---------- */
  const supported = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  const b64u8 = s => { const p = '='.repeat((4 - s.length % 4) % 4), b = (s + p).replace(/-/g, '+').replace(/_/g, '/'), r = atob(b); return Uint8Array.from([...r].map(c => c.charCodeAt(0))) };
  const swReady = () => Promise.race([navigator.serviceWorker.ready, new Promise((_, no) => setTimeout(() => no(new Error('Il servizio di notifica non è pronto: ricarica la pagina e riprova.')), 8000))]);
  async function localSub() { try { return await (await swReady()).pushManager.getSubscription() } catch (e) { return null } }
  async function enablePush() {
    const pub = await rpc('push_public_key', {});
    if (!pub) throw new Error('Le notifiche push non sono ancora attivate dall\'amministratore.');
    if (!supported()) throw new Error('Questo browser non supporta le notifiche push.');
    const perm = await Notification.requestPermission();
    if (perm !== 'granted') throw new Error('Permesso negato: abilita le notifiche per questo sito dalle impostazioni del browser.');
    const reg = await swReady();
    let sub = await reg.pushManager.getSubscription();
    try { if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64u8(pub) }) }
    catch (e) { if (e && e.name === 'InvalidStateError' && sub) { await sub.unsubscribe(); sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64u8(pub) }) } else throw e }
    const j = sub.toJSON();
    await rpc('push_subscribe', { p_endpoint: j.endpoint, p_p256dh: j.keys && j.keys.p256dh, p_auth: j.keys && j.keys.auth, p_ua: (navigator.userAgent || '').slice(0, 200) });
  }
  async function disablePush() {
    const sub = await localSub();
    if (sub) { const ep = sub.endpoint; await sub.unsubscribe(); await rpc('push_unsubscribe', { p_endpoint: ep }) }
  }

  /* ---------- pagina ---------- */
  const where = u => { const h = String(u || '').split('#')[1]; return h ? '#' + h : '#/notifiche' };
  R.notifiche = async () => {
    if (!present()) { shell('<h1 class="t"><em>Notifiche</em></h1><div class="box" style="margin-top:18px"><h2>Notifiche non ancora attivate</h2><p>Manca la migrazione del database. Un amministratore deve eseguire <b>black-market-notifiche.sql</b> in Supabase (dopo le migrazioni precedenti).</p></div>', 'notifiche'); return }
    let items, prefs, key = null;
    try { [items, prefs, key] = await Promise.all([q(BM.sb.from('notifications').select('*').order('created_at', { ascending: false }).limit(60)), q(BM.sb.from('notification_prefs').select('*').eq('user_id', BM.me.id)), rpc('push_public_key', {})]) }
    catch (er) { shell(`<div class="err" role="alert">Notifiche non disponibili: ${esc(er.message)}. Hai applicato la migrazione <b>black-market-notifiche.sql</b>?</div>`, 'notifiche'); return }
    const pr = prefs[0] || { bounty: true, ladder: true, hunt: true };
    const sub = supported() ? await localSub() : null, perm = supported() ? Notification.permission : 'unsupported';
    if (sub && key && perm === 'granted') { try { await rpc('push_subscribe', { p_endpoint: sub.endpoint, p_p256dh: sub.toJSON().keys.p256dh, p_auth: sub.toJSON().keys.auth, p_ua: (navigator.userAgent || '').slice(0, 200) }) } catch (e) { /* già collegato o al limite */ } }   // se sullo stesso telefono entra un altro account, il dispositivo passa a lui
    let st;
    if (!supported()) st = `<p class="mute" style="margin:0">Questo browser non supporta le notifiche push. <b>Su iPhone e iPad</b> bisogna prima installare il Tempio sulla schermata Home (Condividi → Aggiungi alla schermata Home) e aprirlo da lì. Intanto le notifiche qui sotto funzionano sempre.</p>`;
    else if (perm === 'denied') st = '<p style="margin:0">Hai bloccato le notifiche per questo sito. Riattivale dalle impostazioni del browser (icona del lucchetto accanto all\'indirizzo), poi torna qui.</p>';
    else if (!key) st = '<p class="mute" style="margin:0">Le notifiche push non sono ancora attivate dall\'amministratore del Tempio. Quelle qui sotto funzionano già dentro l\'app.</p>';
    else if (sub && perm === 'granted') st = `<div class="nf-st"><span class="tag g">Attive su questo dispositivo</span><button class="btn ghost sm" data-act="nfTest">Invia una notifica di prova</button><button class="btn ghost sm" data-act="nfOff">Disattiva</button></div><p class="mute" style="font-size:.88rem;margin:8px 0 0">Riceverai un avviso anche ad app chiusa. Se la prova non arriva entro qualche secondo, controlla che le notifiche del browser non siano silenziate.</p>`;
    else st = '<div class="nf-st"><button class="btn gold" data-act="nfOn">Attiva le notifiche su questo dispositivo</button></div><p class="mute" style="font-size:.88rem;margin:8px 0 0">Il browser chiederà il permesso. Puoi attivarle su più dispositivi (telefono, Chromebook…).</p>';
    const un = items.filter(n => !n.read_at).length;
    shell(`<h1 class="t"><em>Notifiche</em></h1><p class="sub">Ti avvisiamo quando ricevi una taglia, una sfida in Ladder o una sfida per riscuotere la taglia che hai addosso.</p>
<div class="box" style="margin-top:18px"><h2 style="margin-top:0">Notifiche sul dispositivo</h2>${st}</div>
<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Cosa vuoi ricevere</h2>
 <label style="display:flex;gap:10px;align-items:center;font-weight:600;margin-bottom:8px"><input type="checkbox" data-nfp="bounty" ${pr.bounty ? 'checked' : ''} style="width:22px;min-height:0"> Quando ricevo una taglia</label>
 <label style="display:flex;gap:10px;align-items:center;font-weight:600;margin-bottom:8px"><input type="checkbox" data-nfp="ladder" ${pr.ladder ? 'checked' : ''} style="width:22px;min-height:0"> Quando qualcuno mi sfida in Ladder</label>
 <label style="display:flex;gap:10px;align-items:center;font-weight:600"><input type="checkbox" data-nfp="hunt" ${pr.hunt ? 'checked' : ''} style="width:22px;min-height:0"> Quando qualcuno mi sfida per riscuotere la mia taglia</label>
 <p class="mute" style="font-size:.85rem;margin:10px 0 0">Le scelte si salvano subito. La notifica di una taglia non dice mai chi l'ha messa.</p></div>
${isAdm() ? `<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Amministratore: invio push</h2><p style="margin:0 0 8px">Chiave pubblica VAPID: ${key ? '<span class="tag g">impostata</span>' : '<span class="tag r">mancante</span>'} <span class="mute" style="font-size:.88rem">— senza chiave le push non si possono attivare. Procedura completa nel README, sezione «Notifiche push».</span></p><div class="row" style="gap:8px"><input id="nfk" placeholder="Incolla qui la chiave pubblica (inizia con B…)" style="flex:1;min-width:200px" aria-label="Chiave pubblica VAPID"><button class="btn sm" data-act="nfKey">Salva chiave</button></div></div>` : ''}
<div class="box" style="margin-top:14px"><div class="row" style="justify-content:space-between;gap:10px"><h2 style="margin:0">Le tue notifiche${un ? ` <span class="tag g">${un} nuove</span>` : ''}</h2>${un ? '<button class="btn ghost sm" data-act="nfAll">Segna tutte come lette</button>' : ''}</div>
${items.map(n => `<div class="row2 nf-item ${n.read_at ? '' : 'un'}"><div class="g"><b>${esc(n.title)}</b><small style="display:block;color:var(--tx);opacity:.85;margin:2px 0">${esc(n.body)}</small><small>${when(n.created_at)}</small></div><span class="tag ${(KIND[n.kind] || [])[1] || ''}">${(KIND[n.kind] || [n.kind])[0]}</span><button class="btn ghost sm" data-act="nfOpen" data-i="${n.id}" data-h="${esc(where(n.url))}">Apri</button></div>`).join('') || '<p class="mute">Nessuna notifica per ora. Quando qualcuno ti metterà una taglia o ti sfiderà, la vedrai qui.</p>'}</div>`, 'notifiche');
    lastAt = 0; refresh(true);
  };

  /* ---------- azioni ---------- */
  const ACT = {
    nfOn: async el => { el.disabled = true; try { await enablePush(); toast('Notifiche attivate su questo dispositivo.'); } catch (er) { toast(er.message, 1) } BM.route() },
    nfOff: async () => { await disablePush(); toast('Notifiche disattivate su questo dispositivo.'); BM.route() },
    nfTest: async () => { await rpc('push_send_test', {}); toast('Prova inviata: dovrebbe arrivare tra pochi secondi.'); setTimeout(() => BM.route(), 1500) },
    nfAll: async () => { await rpc('notif_mark_read', {}); BM.route() },
    nfOpen: async el => { if (el.closest('.nf-item.un')) { unread = Math.max(0, unread - 1); last = unread; paint() } try { await rpc('notif_mark_read', { p_id: el.dataset.i }) } catch (e) { /* non blocca l'apertura */ } location.hash = el.dataset.h || '#/notifiche' },
    nfKey: async () => { const k = document.getElementById('nfk').value.trim(); if (!k) { toast('Incolla la chiave pubblica.', 1); return } const r = BM.ask('Motivazione (resterà nell\'audit):'); if (!r) return; await rpc('admin_set_push_key', { p_key: k, p_reason: r }); toast('Chiave salvata.'); BM.route() }
  };
  const prev = BM.act;
  BM.act = async (a, el) => { if (ACT[a]) { await ACT[a](el); return true } return prev ? prev(a, el) : false };
  document.addEventListener('change', async e => {
    const t = e.target; if (!t || !t.dataset || !t.dataset.nfp) return;
    const v = k => document.querySelector(`[data-nfp="${k}"]`).checked;
    try { await rpc('notif_set_prefs', { p_bounty: v('bounty'), p_ladder: v('ladder'), p_hunt: v('hunt') }); toast('Preferenze salvate.') }
    catch (er) { toast(er.message, 1); BM.route() }
  });
};
