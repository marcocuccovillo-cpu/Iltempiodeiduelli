/* =====================================================================
   BLACK MARKET — INVITA AMICI e CONDIVISIONI
   * Pagina #/invita: il tuo codice, il link, «Invia su WhatsApp», gli amici portati e quanto hai guadagnato; campo per inserire
     un codice se sei appena arrivato.
   * Codice dal link (index.html?invito=…): lo inserisce da solo appena hai il profilo.
   * Dashboard: riquadro «Invita» e, se hai vinto in Ladder nelle ultime 48 ore, «Condividi la vittoria».
   * Most Wanted: «Condividi i ricercati». Taglia appena pubblicata: «Condividila nel gruppo».
   Richiede la migrazione black-market-inviti.sql (senza, la pagina spiega cosa manca e il resto del Black Market non cambia).
   Il database decide tutto (premi, limiti, validità dei codici): qui si mostra e si chiede.
   ===================================================================== */
window.BM_INVITE = function (BM) {
  'use strict';
  const { R, shell, rpc, toast, esc, BC } = BM;
  const num = n => Number(n || 0).toLocaleString('it-IT');
  const store = (k, v) => { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v) } catch (e) {} };
  const read = k => { try { return localStorage.getItem(k) } catch (e) { return null } };
  const missing = er => /could not find the function|schema cache/i.test(er && er.message || '');
  let info = null;                                   // risultato di my_invite (una volta per visita)

  const css = document.createElement('style');
  css.textContent = `.iv-code{display:flex;align-items:center;justify-content:center;gap:12px;margin:10px 0 14px;padding:14px;border:2px dashed var(--gold);border-radius:16px;background:rgba(212,168,67,.08)}
.iv-code b{font:700 2rem/1 var(--disp);letter-spacing:.18em;color:var(--gold)}
.iv-link{width:100%;font:500 .9rem var(--ui);padding:10px 12px;border-radius:12px;border:1px solid var(--line);background:#07070a;color:var(--tx)}
.iv-steps{list-style:none;margin:0;padding:0;display:grid;gap:8px}.iv-steps li{display:flex;gap:10px;align-items:flex-start;line-height:1.35}
.iv-steps i{font-style:normal;flex:none;width:28px;height:28px;border-radius:50%;display:grid;place-items:center;background:rgba(212,168,67,.18);color:var(--gold);font-weight:700}
.iv-pro{display:flex;gap:14px;align-items:center;border:1.5px solid rgba(74,222,155,.45);background:linear-gradient(135deg,rgba(74,222,155,.12),rgba(212,168,67,.06));border-radius:16px;padding:14px 16px;margin-top:16px}
.iv-pro .e{font-size:2rem;flex:none}.iv-pro .g{flex:1;min-width:0}.iv-pro b{color:#4ade9b}
.iv-sheet{position:fixed;left:50%;bottom:16px;transform:translateX(-50%);z-index:90;width:min(460px,calc(100% - 24px));padding:14px 16px;border-radius:18px;border:1.5px solid var(--gold);background:#141217;box-shadow:0 12px 40px rgba(0,0,0,.6);display:flex;gap:12px;align-items:center;animation:ivUp .25s ease-out}
.iv-sheet p{margin:0;flex:1;font-size:.95rem;line-height:1.3}.iv-sheet .x{background:none;border:0;color:var(--mu);font-size:1.4rem;min-width:40px;min-height:40px;cursor:pointer}
@keyframes ivUp{from{transform:translate(-50%,20px);opacity:0}}
.btn.wa{background:#25d366;color:#05230f;border-color:#25d366}.btn.wa:hover{background:#3be07a}`;
  document.head.appendChild(css);

  async function load(force) {
    if (info && !force) return info;
    info = await rpc('my_invite', {});
    store('tempio.mycode', info.code);
    return info;
  }
  /* codice arrivato dal link: si usa appena c'è un profilo */
  async function autoRedeem() {
    const c = read('tempio.invito'); if (!c) return;
    try {
      const r = await rpc('redeem_invite', { p_code: c });
      store('tempio.invito', null);
      if (r && r.ok) { info = null; toast(`Invito di ${r.inviter} registrato: +${num(r.bonus)} BC extra al tuo primo match!`) }
    } catch (er) {
      if (missing(er) || /Failed to fetch|NetworkError/i.test(er.message)) return;          // si riprova alla prossima visita
      store('tempio.invito', null);
      if (!/tuo stesso codice/.test(er.message)) toast('Codice invito non usato: ' + er.message, 1);
    }
  }

  /* riquadro in basso «Condividi su WhatsApp»: serve un tocco vero per aprire il menu di condivisione del telefono */
  BM.offerShare = (label, o) => {
    if (!window.TempioShare) return;
    document.querySelectorAll('.iv-sheet').forEach(x => x.remove());
    const d = document.createElement('div'); d.className = 'iv-sheet'; d.setAttribute('role', 'dialog'); d.setAttribute('aria-label', 'Condividi');
    d.innerHTML = `<p>${esc(label)}</p><button type="button" class="btn wa sm">WhatsApp</button><button type="button" class="x" aria-label="Chiudi">×</button>`;
    document.body.appendChild(d);
    const t = setTimeout(() => d.remove(), 20000);
    d.querySelector('.wa').onclick = () => { clearTimeout(t); d.remove(); window.TempioShare.share(o) };
    d.querySelector('.x').onclick = () => { clearTimeout(t); d.remove() };
  };

  const waBtn = (act, label) => `<button type="button" class="btn wa" data-act="${act}">${label || 'Invia su WhatsApp'}</button>`;
  const inviteMsg = i => `Ti aspetto al Tempio dei Duelli, la nostra app Yu-Gi-Oh! di Bologna: Ladder con premi, taglie sui rivali e un GDR con boss e dungeon. Registrati col mio invito: ${num(i ? i.bonus : 100)} BC extra al tuo primo match!`;

  /* ---------- #/invita ---------- */
  R.invita = async () => {
    await autoRedeem();
    let i;
    try { i = await load(true) } catch (er) {
      if (missing(er)) return shell(`<h1 class="t">Invita <em>amici</em></h1><div class="box" style="margin-top:18px"><h2>Inviti non ancora attivi</h2><p>L'amministratore deve eseguire la migrazione <b>black-market-inviti.sql</b> in Supabase.</p></div>`, 'invita');
      throw er;
    }
    const played = i.friends.filter(f => f.played).length, waiting = i.friends.length - played, left = Math.max(0, i.max - i.friends.filter(f => f.paid > 0).length);
    shell(`<h1 class="t">Invita <em>amici</em></h1><p class="sub">Porta nel Tempio chi è nel gruppo ma non ha ancora l'app. Guadagnate tutti e due.</p>
    ${!i.enabled ? '<div class="err" style="margin-top:14px">Gli inviti sono sospesi dall\'amministratore: il codice resta valido per quando torneranno attivi.</div>' : ''}
    <div class="grid c2" style="margin-top:18px">
     <div class="box"><h2>Il tuo codice</h2>
      <div class="iv-code"><b>${esc(i.code)}</b></div>
      <input class="iv-link" id="ivl" readonly value="${esc(window.TempioShare ? window.TempioShare.link() : '')}" aria-label="Il tuo link d'invito">
      <div class="row" style="margin-top:12px">${waBtn('ivWa')}<button type="button" class="btn ghost" data-act="ivCopy">Copia link</button>${window.TempioShare ? '<button type="button" class="btn ghost" data-act="ivCard">Invia con immagine</button>' : ''}</div>
     </div>
     <div class="box"><h2>Come funziona</h2><ol class="iv-steps">
      <li><i>1</i><span>Mandi il link nel gruppo o in privato.</span></li>
      <li><i>2</i><span>L'amico si registra dal link: <b>1000 BC</b> di benvenuto come tutti.</span></li>
      <li><i>3</i><span>Al suo <b>primo match</b> (Ladder o torneo) contro chiunque tranne te: <b style="color:var(--gold)">+${num(i.reward)} BC a te</b> e <b style="color:var(--gold)">+${num(i.bonus)} BC a lui</b>.</span></li>
     </ol><p class="mute" style="font-size:.88rem;margin:12px 0 0">Premiati fino a ${num(i.max)} amici (ne restano ${num(left)}). Ogni amico portato conta per i badge <b>Reclutatore</b>.</p></div>
    </div>
    <div class="grid c2" style="margin-top:14px">
     <div class="box"><h2>I tuoi amici</h2>
      <div class="row" style="gap:18px;margin-bottom:8px"><div><div class="big" style="font-size:1.8rem">${num(played)}</div><small class="mute">hanno giocato</small></div><div><div class="big" style="font-size:1.8rem">${num(waiting)}</div><small class="mute">da far giocare</small></div><div><div class="big" style="font-size:1.8rem">${num(i.earned)} <small>BC</small></div><small class="mute">guadagnati</small></div></div>
      ${i.friends.length ? i.friends.map(f => `<div class="row2"><div class="g"><b>${esc(f.nickname)}</b><small>${f.played ? (f.paid > 0 ? `ha giocato · +${num(f.paid)} BC per te` : 'ha giocato (oltre il massimo di inviti premiati)') : 'iscritto: sfidalo o portalo a un torneo… ma non contro di te!'}</small></div><span class="val">${f.played ? '✅' : '⏳'}</span></div>`).join('') : '<p class="mute">Nessuno ancora. Il primo è il più facile: chi ti chiede sempre «come si usa l\'app?»</p>'}
     </div>
     <div class="box"><h2>${i.invited_by ? 'Ti ha invitato' : 'Hai un codice?'}</h2>
      ${i.invited_by ? `<p><b>${esc(i.invited_by)}</b> ti ha portato nel Tempio.</p>` : i.can_redeem ? `<form id="ivf" class="row" style="gap:8px"><input id="ivc" maxlength="6" required placeholder="ABC123" autocomplete="off" autocapitalize="characters" style="flex:1;min-width:0;text-transform:uppercase;letter-spacing:.15em"><button class="btn gold">Usa codice</button></form><p class="mute" style="font-size:.88rem">Vale nei primi giorni dall'iscrizione e prima del tuo primo match.</p>` : '<p class="mute">Il codice di un amico si inserisce solo da nuovi iscritti, prima del primo match.</p>'}
     </div>
    </div>`, 'invita');
    const f = document.getElementById('ivf');
    if (f) f.onsubmit = async e => { e.preventDefault(); try { const r = await rpc('redeem_invite', { p_code: document.getElementById('ivc').value.trim() }); toast(r.ok ? `Fatto! Invitato da ${r.inviter}: +${num(r.bonus)} BC al tuo primo match.` : `Sei già collegato a ${r.inviter}.`); R.invita() } catch (er) { toast(er.message, 1) } };
  };

  /* ---------- dashboard: riquadro invito + ultima vittoria in Ladder ---------- */
  const dash = R[''];
  R[''] = async (...a) => {
    try { await autoRedeem() } catch (er) {}
    await dash(...a);
    try { await dashExtras() } catch (er) { console.warn('Inviti: riquadri della dashboard non mostrati', er) }   // un extra non deve mai bloccare la dashboard
  };
  /* il punto d'aggancio si cerca DOPO ogni attesa: nel frattempo la pagina può essere stata ridisegnata */
  const spot = () => { const app = document.getElementById('app'), g = app && (app.querySelector('.bmd-slot') || app.querySelector('.grid')); return g && g.isConnected && g.parentNode ? g : null };
  async function dashExtras() {
    let i = null; try { i = await load() } catch (er) { return }
    if (location.hash.replace(/^#\/?/, '') !== '') return;            // nel frattempo si è cambiata pagina
    let anchor = spot(); if (!anchor || document.querySelector('#app .iv-pro')) return;
    const box = document.createElement('div');
    box.className = 'iv-pro';
    box.innerHTML = `<span class="e" aria-hidden="true">🤝</span><div class="g"><b>+${num(i.reward)} BC</b> per ogni amico che porti nel Tempio<br><small class="mute">${i.friends.length ? `${i.friends.filter(f => f.played).length} su ${i.friends.length} hanno già giocato` : 'Più duellanti = più sfide, più taglie, più boss abbattuti.'}</small></div><a class="btn wa sm" href="#/invita">Invita</a>`;
    anchor.parentNode.insertBefore(box, anchor);
    /* ultima vittoria in Ladder (48 ore) */
    if (BM.S.module_ladder != 1 || !window.TempioShare) return;
    const me = BM.me.id, since = new Date(Date.now() - 48 * 3600e3).toISOString();
    const ms = await BM.q(BM.sb.from('ladder_matches').select('*').eq('status', 'closed').gte('closed_at', since).or(`challenger_id.eq.${me},opponent_id.eq.${me}`).order('closed_at', { ascending: false }).limit(5));
    const w = ms.find(m => (m.reported_result === 'challenger' && m.challenger_id === me) || (m.reported_result === 'opponent' && m.opponent_id === me));
    if (!w || read('tempio.sharedwin') === w.id || !box.isConnected || !box.parentNode) return;
    const opp = BM.pn(w.challenger_id === me ? w.opponent_id : w.challenger_id), d = w.challenger_id === me ? w.elo_challenger_delta : w.elo_opponent_delta;
    const sc = w.challenger_id === me ? w.reported_score : String(w.reported_score || '').split('-').reverse().join('-');
    const vb = document.createElement('div'); vb.className = 'iv-pro'; vb.style.borderColor = 'rgba(167,139,250,.55)';
    vb.innerHTML = `<span class="e" aria-hidden="true">⚔️</span><div class="g"><b style="color:var(--ac2,#c9b8ff)">Hai battuto ${esc(opp)}</b> in Ladder ${esc(w.format)}${sc ? ' · ' + esc(sc) : ''}<br><small class="mute">Fallo sapere al gruppo</small></div><button type="button" class="btn wa sm" data-act="ivWin" data-m="${w.id}">Condividi</button>`;
    vb.dataset.o = opp; vb.dataset.d = d == null ? '' : d; vb.dataset.s = sc || ''; vb.dataset.f = w.format;
    box.parentNode.insertBefore(vb, box.nextSibling);
  }

  /* ---------- Most Wanted: condividi i ricercati ---------- */
  const wanted = R.wanted;
  R.wanted = async (...a) => {
    await wanted(...a);
    if (!window.TempioShare) return;
    const h = document.querySelector('#app h1.t'); if (!h || !h.parentNode) return;
    const b = document.createElement('div'); b.className = 'row'; b.style.marginTop = '10px';
    b.innerHTML = '<button type="button" class="btn wa sm" data-act="ivWanted">Condividi i ricercati</button>';
    const sub = h.nextElementSibling && h.nextElementSibling.classList.contains('sub') ? h.nextElementSibling : h;
    if (sub.parentNode) sub.parentNode.insertBefore(b, sub.nextSibling);
  };

  /* ---------- profilo: taglia appena pubblicata ---------- */
  const prof = R.p;
  R.p = async (...a) => {
    await prof(...a);
    let nb = null; try { nb = JSON.parse(sessionStorage.getItem('bm.newbounty') || 'null') } catch (e) {}
    if (!nb || nb.target !== a[0]) return;
    sessionStorage.removeItem('bm.newbounty');
    const nick = BM.pn(nb.target);
    BM.offerShare(`Taglia da ${num(nb.amount)} BC su ${nick}: dillo al gruppo!`, { kind: 'Nuova taglia', emoji: '🎯', title: nick, sub: `Taglia di ${num(nb.amount)} BC`, tone: 'red',
      text: 'Chi lo batte in un match ufficiale incassa il montepremi.', msg: `🎯 Ho messo una taglia di ${num(nb.amount)} BC su ${nick} nel Black Market del Tempio. Chi lo batte incassa!` });
  };

  /* ---------- azioni ---------- */
  const prevAct = BM.act;
  BM.act = async (a, el) => {
    if (prevAct && await prevAct(a, el)) return true;
    if (a === 'ivWa') { const i = await load(); window.TempioShare ? window.TempioShare.text(inviteMsg(i)) : window.open('https://wa.me/?text=' + encodeURIComponent(inviteMsg(i)), '_blank'); return true }
    if (a === 'ivCopy') { const v = document.getElementById('ivl').value; try { await navigator.clipboard.writeText(v); toast('Link copiato.') } catch (e) { const x = document.getElementById('ivl'); x.select(); toast('Tieni premuto sul link per copiarlo.') } return true }
    if (a === 'ivCard') { const i = await load(); window.TempioShare.share({ kind: 'Sei invitato', big: `+${num(i.bonus)} BC`, title: `${BM.me.nickname} ti invita`, sub: 'nel Tempio dei Duelli', text: 'Ladder con premi, taglie sui rivali e un GDR con boss e dungeon.', tone: 'gold', msg: inviteMsg(i) }); return true }
    if (a === 'ivWin') {
      const c = el.closest('.iv-pro'), d = c.dataset.d;
      store('tempio.sharedwin', el.dataset.m);
      window.TempioShare.share({ kind: 'Vittoria in Ladder', emoji: '⚔️', title: `${BM.me.nickname} batte ${c.dataset.o}`, sub: `Ladder ${c.dataset.f}${c.dataset.s ? ' · ' + c.dataset.s : ''}`,
        stats: d !== '' ? [['Elo', (d >= 0 ? '+' : '') + d]] : null, msg: `⚔️ Ho battuto ${c.dataset.o} nella Ladder del Tempio${c.dataset.s ? ' (' + c.dataset.s + ')' : ''}! Chi è il prossimo?` });
      return true;
    }
    if (a === 'ivWanted') {
      const rows = await BM.q(BM.sb.from('most_wanted_v').select('*').order('bounty_value', { ascending: false }).limit(3));
      if (!rows.length) { toast('Nessuna taglia attiva da condividere.', 1); return true }
      window.TempioShare.share({ kind: 'Most Wanted', emoji: '🎯', title: rows[0].nickname, sub: `Ricercato n. 1 · ${num(rows[0].bounty_value)} BC`, tone: 'red',
        stats: rows.map((r, n) => [`${n + 1}. ${r.nickname}`, num(r.bounty_value) + ' BC']), msg: `🎯 I più ricercati del Tempio: ${rows.map(r => `${r.nickname} (${num(r.bounty_value)} BC)`).join(', ')}. Chi li batte incassa!` });
      return true;
    }
    return false;
  };

  /* voce nel menu delle sezioni */
  BM.navItems = (prev => () => [...(prev ? prev() : []), ['invita', 'Invita amici']])(BM.navItems);
};
