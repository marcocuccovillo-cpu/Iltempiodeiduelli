/* =====================================================================
   BLACK MARKET — TESSERA DEL DUELLANTE (per i tag NFC)
   Ogni duellante ha una tessera: #/t/<id>. Si scrive il link su un tag NFC (da regalare, da attaccare al deck box…):
   chi lo tocca col telefono apre la tessera con i dati del duellante (Elo per formato, posizione, record, taglie,
   scontri diretti) e può sfidarlo subito in Ladder normale o in Ladder + taglia.
   - #/t/<id>     la tessera; se è la tua, in fondo c'è il link da scrivere sul tag.
   - #/tessere    (amministratore) l'elenco dei duellanti per scrivere i tag uno dopo l'altro.
   Scrittura del tag direttamente dall'app con Chrome su Android (Web NFC); altrove si copia il link e lo si scrive con NFC Tools.
   Nessuna regola nuova: la sfida usa ladder_challenge come la Caccia alle taglie. Nessuna migrazione.
   ===================================================================== */
window.BM_CARD = function (BM) {
  'use strict';
  const { R, shell, q, rpc, toast, esc, BC, when, av } = BM;
  const FMT = ['Advanced', 'Edison'];
  const OPEN = ['pending', 'accepted', 'reported', 'disputed'];
  const STAT = { pending: 'in attesa di risposta', accepted: 'accettata: da giocare', reported: 'risultato da confermare', disputed: 'risultato contestato' };
  const num = n => Number(n || 0).toLocaleString('it-IT');
  const ladderOn = () => BM.S && BM.S.module_ladder == 1;
  const isAdm = () => BM.me && BM.me.role === 'admin';
  const url = id => location.origin + location.pathname + '#/t/' + id;
  const canNfc = () => 'NDEFReader' in window;
  let fmt = (() => { try { return localStorage.getItem('bm.card.fmt') || 'Advanced' } catch (e) { return 'Advanced' } })();

  /* stile della tessera (una volta sola) */
  if (!document.getElementById('bmCardCss')) {
    const st = document.createElement('style'); st.id = 'bmCardCss';
    st.textContent = `
.tc{position:relative;overflow:hidden;padding:20px 18px 18px;border-radius:20px;border:1.5px solid var(--gold);
 background:radial-gradient(120% 90% at 100% 0,rgba(212,168,67,.22),transparent 55%),radial-gradient(90% 80% at 0 100%,rgba(120,80,200,.22),transparent 60%),linear-gradient(160deg,#1b1526,#0d0a14);
 box-shadow:0 0 0 1px rgba(0,0,0,.6) inset,0 18px 40px rgba(0,0,0,.5)}
.tc:after{content:"";position:absolute;inset:0;pointer-events:none;background:linear-gradient(115deg,transparent 30%,rgba(255,255,255,.07) 45%,transparent 60%);background-size:250% 100%;animation:tcShine 6s ease-in-out infinite}
@keyframes tcShine{0%,60%{background-position:120% 0}100%{background-position:-120% 0}}@media(prefers-reduced-motion:reduce){.tc:after{animation:none}}
.tc-top{display:flex;justify-content:space-between;align-items:center;font:700 .7rem var(--ui,system-ui);letter-spacing:.14em;text-transform:uppercase;color:var(--gold)}
.tc-who{display:flex;gap:16px;align-items:center;margin-top:14px}.tc-who h2{margin:0;font-size:1.7rem;overflow-wrap:anywhere;line-height:1.1}.tc-who small{display:block;color:var(--mu,#9a93ab);margin-top:4px}
.tc-elo{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin-top:16px}
.tc-e{padding:12px;border-radius:14px;background:rgba(255,255,255,.04);border:1px solid var(--line)}.tc-e span{display:block;font-size:.72rem;letter-spacing:.08em;text-transform:uppercase;color:var(--mu,#9a93ab)}
.tc-e b{display:block;font-size:1.9rem;line-height:1.1;margin-top:2px}.tc-e small{color:var(--mu,#9a93ab)}.tc-e.on{border-color:var(--gold);background:rgba(212,168,67,.08)}
.tc-bounty{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-top:10px;padding:10px 12px;border-radius:14px;border:1px dashed rgba(224,83,63,.7);background:rgba(224,83,63,.08)}
.tc-bounty b{font-size:1.25rem;color:#ff9a8c}
.tc-h2h{display:flex;align-items:center;justify-content:center;gap:14px;margin-top:10px;font-size:.92rem}.tc-h2h b{font-size:1.3rem}
.tc-act{display:grid;gap:10px}.tc-act .seg{margin:0}.tc-big{display:grid;gap:10px;grid-template-columns:1fr 1fr}@media(max-width:480px){.tc-big{grid-template-columns:1fr}}
.tc-big .btn{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;padding:14px 12px;font-size:1rem;line-height:1.25;text-align:center}.tc-big .btn small{display:block;font-weight:500;font-size:.78rem;opacity:.85}
.tc-res{display:flex;gap:6px;flex-wrap:wrap}.tc-res i{font-style:normal;display:inline-grid;place-items:center;width:30px;height:30px;border-radius:9px;font-weight:700}
.tc-res i.w{background:rgba(70,200,120,.18);color:#7be3a5}.tc-res i.l{background:rgba(224,83,63,.18);color:#ff9a8c}.tc-res i.d{background:rgba(255,255,255,.08)}
.tc-nfc{display:grid;gap:10px}.tc-url{font:500 .8rem ui-monospace,monospace;padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.05);border:1px solid var(--line);overflow-wrap:anywhere}
.tc-wait{display:flex;gap:10px;align-items:center;padding:12px;border-radius:12px;border:1px solid var(--gold);background:rgba(212,168,67,.08)}
.tc-wait span{font-size:1.6rem;animation:tcPulse 1.2s ease-in-out infinite}@keyframes tcPulse{50%{transform:scale(1.2)}}
.tc-list .row2 .btn{white-space:nowrap}`;
    document.head.appendChild(st);
  }

  /* ---------- scrittura del tag NFC ---------- */
  let nfcAbort = null;
  async function writeTag(id, btn) {
    const box = document.getElementById('tcWait-' + id) || document.getElementById('tcWait');
    if (!canNfc()) {
      try { await navigator.clipboard.writeText(url(id)); toast('Link copiato: scrivilo sul tag con un\'app come NFC Tools.') }
      catch (e) { toast('Copia il link qui sopra e scrivilo sul tag con un\'app come NFC Tools.', 1) }
      return;
    }
    if (nfcAbort) { nfcAbort.abort(); nfcAbort = null }
    const lock = document.getElementById('tcLock') && document.getElementById('tcLock').checked;
    nfcAbort = new AbortController(); const sig = nfcAbort.signal;
    const t = setTimeout(() => { if (nfcAbort) nfcAbort.abort() }, 30000);
    if (box) { box.hidden = false; box.innerHTML = `<span aria-hidden="true">📡</span><div><b>Avvicina il tag al retro del telefono</b><small class="mute" style="display:block">Tienilo fermo finché non compare la conferma (30 secondi al massimo).</small></div>` }
    if (btn) btn.disabled = true;
    try {
      const nd = new NDEFReader();
      await nd.write({ records: [{ recordType: 'url', data: url(id) }] }, { signal: sig, overwrite: true });
      if (lock && nd.makeReadOnly) await nd.makeReadOnly({ signal: sig });
      if (box) box.innerHTML = `<span aria-hidden="true">✅</span><div><b>Tag scritto${lock ? ' e bloccato' : ''}!</b><small class="mute" style="display:block">Toccalo con un telefono per provarlo: si apre la tessera di ${esc((BM.P.get(id) || {}).nickname || '')}.</small></div>`;
      toast('Tag NFC scritto.');
    } catch (er) {
      const m = er && er.name === 'AbortError' ? 'Tempo scaduto: nessun tag avvicinato.' : er && er.name === 'NotAllowedError' ? 'Permesso NFC negato: consentilo a Chrome e riprova.' : er && er.name === 'NotSupportedError' ? 'Questo telefono non può scrivere tag NFC dal browser: usa NFC Tools con il link.' : 'Scrittura non riuscita: ' + (er && er.message || er);
      if (box) box.innerHTML = `<span aria-hidden="true">⚠️</span><div><b>${esc(m)}</b></div>`;
    } finally { clearTimeout(t); nfcAbort = null; if (btn) btn.disabled = false }
  }
  const nfcBox = (id, mine) => `<div class="box tc-nfc" style="margin-top:14px"><h2 style="margin:0">📇 ${mine ? 'La tua tessera NFC' : 'Tessera NFC di ' + esc((BM.P.get(id) || {}).nickname || '')}</h2>
<p class="mute" style="margin:0">Scrivi questo link su un tag NFC: chi lo tocca col telefono apre questa tessera e può sfidare ${mine ? 'te' : 'questo duellante'} subito.</p>
<div class="tc-url" id="tcUrl">${esc(url(id))}</div>
${canNfc() ? `<label style="display:flex;gap:8px;align-items:flex-start;font-size:.88rem"><input type="checkbox" id="tcLock"> <span>Blocca il tag dopo averlo scritto, così nessuno può cambiarlo. <b>Non si potrà più riscrivere.</b></span></label>` : ''}
<div class="row" style="gap:8px;flex-wrap:wrap"><button class="btn gold" data-act="tcWrite" data-u="${id}">${canNfc() ? '📡 Scrivi su un tag NFC' : '📋 Copia il link'}</button>${canNfc() ? '<button class="btn ghost" data-act="tcCopy" data-u="' + id + '">📋 Copia il link</button>' : ''}${isAdm() ? '<a class="btn ghost" href="#/tessere">Tutte le tessere</a>' : ''}</div>
<div class="tc-wait" id="tcWait" hidden></div>
${canNfc() ? '' : '<p class="mute" style="margin:0;font-size:.85rem">Da qui il browser non può scrivere i tag (serve Chrome su Android). Con un\'app come <b>NFC Tools</b>: Scrivi › Aggiungi un record › URL › incolla il link › Scrivi, poi avvicina il tag.</p>'}</div>`;

  /* ---------- #/t/<id>: la tessera ---------- */
  async function card(id) {
    const me = BM.me, sb = BM.sb, p = BM.P.get(id);
    if (!p || p.suspended) return shell('<div class="err">Questa tessera non appartiene a nessun duellante attivo.</div>', 'ladder');
    const mine = id === me.id, lad = ladderOn();
    const V = lad && BM.hasV11 ? await BM.hasV11() : false;
    const [mw, myB, st, h2h, last, ms] = await Promise.all([
      q(sb.from('most_wanted_v').select('*').eq('id', id)),
      mine ? Promise.resolve([]) : q(sb.from('bounties').select('amount,status,target_id').eq('creator_id', me.id).eq('target_id', id).eq('status', 'active')),
      lad ? q(sb.from('ladder_standings_v').select('*').in('user_id', mine ? [id] : [id, me.id])).catch(() => []) : Promise.resolve([]),
      lad && !mine ? q(sb.from('ladder_matches').select('*').or(`and(challenger_id.eq.${me.id},opponent_id.eq.${id}),and(challenger_id.eq.${id},opponent_id.eq.${me.id})`).order('created_at', { ascending: false }).limit(60)).catch(() => []) : Promise.resolve([]),
      lad ? q(sb.from('ladder_matches').select('*').eq('status', 'closed').or(`challenger_id.eq.${id},opponent_id.eq.${id}`).order('closed_at', { ascending: false }).limit(8)).catch(() => []) : Promise.resolve([]),
      q(sb.from('matches').select('winner_id').eq('status', 'verified').or(`player_a.eq.${id},player_b.eq.${id}`)).catch(() => [])]);
    const w = mw[0] || { bounty_value: 0, active_count: 0 };
    const own = myB.reduce((t, b) => t + b.amount, 0), gain = Math.max(0, w.bounty_value - own);
    const row = (u, f) => st.find(r => r.user_id === u && (!V || r.format === f));
    const resOf = (m, u) => m.reported_result === 'draw' ? 'd' : ((m.reported_result === 'challenger') === (m.challenger_id === u) ? 'w' : 'l');
    const closed = h2h.filter(m => m.status === 'closed'), open = h2h.find(m => OPEN.includes(m.status));
    const hw = closed.filter(m => resOf(m, me.id) === 'w').length, hl = closed.filter(m => resOf(m, me.id) === 'l').length, hd = closed.length - hw - hl;
    const ofW = ms.filter(m => m.winner_id === id).length;
    const eq = BM.shopEq ? await BM.shopEq(id).catch(() => null) : null;
    const head = BM.shopHead && eq && Object.keys(eq).length
      ? BM.shopHead(p, eq, { avatar: av(p).replace('class="av"', 'class="av xl"'), h: 'h2', tag: '', extra: '', petSize: 96 })
      : `<div class="tc-who">${av(p).replace('class="av"', 'class="av xl"')}<div style="min-width:0"><h2>${esc(p.nickname)}</h2><small>${ms.length ? `${num(ofW)} vittorie su ${num(ms.length)} match ufficiali` : 'Nessun match ufficiale, per ora'}</small></div></div>`;
    const elo = (V ? FMT : [null]).map(f => { const r = row(id, f), m = !mine ? row(me.id, f) : null;
      return `<div class="tc-e${f && f === fmt && !mine ? ' on' : ''}"><span>Elo ${f || 'Ladder'}</span><b>${r ? num(r.elo) : '—'}</b><small>${r ? `#${r.rank} · ${r.wins}V ${r.draws}P ${r.losses}S` : 'non classificato'}${m ? ` · tu ${num(m.elo)}` : ''}</small></div>` }).join('');
    const form = last.slice(0, 8).map(m => { const r = resOf(m, id); return `<i class="${r}" title="${esc(m.format)} · ${when(m.closed_at)}">${r === 'w' ? 'V' : r === 'l' ? 'S' : 'P'}</i>` }).join('');
    const rq = crypto.randomUUID();
    const act = mine ? '' : !lad ? `<div class="box" style="margin-top:14px"><p class="mute" style="margin:0">La Ladder è spenta: per ora non si possono lanciare sfide.</p></div>`
      : open ? `<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Sfida già aperta</h2><p style="margin:0 0 10px">Tra voi c'è già una sfida ${esc(open.format)}: <b>${STAT[open.status]}</b>${open.challenger_id === id ? ' (ti ha sfidato lui)' : ''}.</p><a class="btn gold" href="#/ladder">Vai alla Ladder</a></div>`
      : `<div class="box tc-act" style="margin-top:14px" id="tcAct" data-rq="${rq}"><h2 style="margin:0">⚔️ Sfida ${esc(p.nickname)}</h2>
${V ? `<div class="seg" role="group" aria-label="Formato">${FMT.map(f => `<button type="button" data-act="tcFmt" data-v="${f}" aria-pressed="${f === fmt}">${f}</button>`).join('')}</div>` : ''}
<input id="tcMsg" maxlength="140" placeholder="Messaggio (facoltativo)" aria-label="Messaggio della sfida">
<div class="tc-big"><button class="btn ghost" data-act="tcGo" data-k="ladder" data-u="${id}">⚔️ Sfida in Ladder<small>in gioco l'Elo ${V ? 'del formato' : ''} e il premio Ladder</small></button>
${V ? `<button class="btn gold" data-act="tcGo" data-k="both" data-u="${id}" ${gain > 0 ? '' : 'disabled'}>🎯 Ladder + taglia<small>${gain > 0 ? `Elo e fino a ${BC(gain)} di taglia` : 'non ha taglie che puoi incassare'}</small></button>` : ''}</div>
<p class="mute" style="margin:0;font-size:.85rem">${esc(p.nickname)} riceve una notifica e vede il tipo di sfida prima di accettare. Il risultato si inserisce poi nella <a href="#/ladder">Ladder</a>.</p></div>`;
    shell(`<div class="tc" style="margin-top:6px"><div class="tc-top"><span>Tessera del duellante</span><span>Il Tempio dei Duelli</span></div>${head}
<div class="tc-elo">${elo}</div>
${w.bounty_value > 0 ? `<div class="tc-bounty"><span>🎯 Taglia sulla sua testa<small class="mute" style="display:block">${w.active_count} ${w.active_count == 1 ? 'taglia attiva' : 'taglie attive'}</small></span><b>${BC(w.bounty_value)}</b></div>` : ''}
${!mine && closed.length ? `<div class="tc-h2h"><span>Tu</span><b style="color:#7be3a5">${hw}</b><span class="mute">–</span><b>${hd}</b><span class="mute">–</span><b style="color:#ff9a8c">${hl}</b><span>${esc(p.nickname)}</span></div><p class="mute" style="text-align:center;margin:2px 0 0;font-size:.8rem">scontri diretti in Ladder (vinte – pari – perse)</p>` : ''}
${form ? `<div style="margin-top:14px"><small class="mute">Ultime partite in Ladder</small><div class="tc-res" style="margin-top:6px">${form}</div></div>` : ''}
<div class="row" style="gap:8px;margin-top:14px;flex-wrap:wrap"><a class="btn ghost sm" href="#/p/${id}">Profilo e taglie</a>${!mine && w.bounty_value >= 0 ? `<a class="btn ghost sm" href="#/new/${id}">Metti una taglia</a>` : ''}</div></div>
${act}${mine || isAdm() ? nfcBox(id, mine) : ''}`, 'ladder');
  }

  /* ---------- #/tessere: elenco per l'amministratore ---------- */
  async function list() {
    if (!isAdm()) return shell('<div class="err">Solo l\'amministratore può vedere tutte le tessere.</div>', 'ladder');
    const st = ladderOn() ? await q(BM.sb.from('ladder_standings_v').select('user_id,elo,format,rank')).catch(() => []) : [];
    const best = new Map(); st.forEach(r => { const b = best.get(r.user_id); if (!b || r.elo > b.elo) best.set(r.user_id, r) });
    const all = [...BM.P.values()].filter(p => !p.suspended).sort((a, b) => (best.has(b.id) - best.has(a.id)) || ((best.get(b.id) || {}).elo || 0) - ((best.get(a.id) || {}).elo || 0) || a.nickname.localeCompare(b.nickname));
    shell(`<h1 class="t">Tessere <em>NFC</em></h1><p class="sub">Scrivi la tessera di ogni duellante su un tag: chi lo tocca apre i suoi dati e può sfidarlo in Ladder o Ladder + taglia.${canNfc() ? ' Premi «Scrivi» e avvicina il tag al telefono.' : ' Da questo browser non si scrivono i tag: copia il link e usa un\'app come NFC Tools (serve Chrome su Android per scrivere da qui).'}</p>
${canNfc() ? '<label class="box" style="display:flex;gap:8px;align-items:flex-start;font-size:.9rem;margin-top:14px"><input type="checkbox" id="tcLock"> <span>Blocca ogni tag dopo averlo scritto (nessuno potrà cambiarlo, ma nemmeno tu).</span></label>' : ''}
<div class="tc-wait" id="tcWait" hidden style="margin-top:12px;position:sticky;top:8px;z-index:3"></div>
<div class="box tc-list" style="margin-top:14px">${all.map(p => { const b = best.get(p.id); return `<div class="row2">${av(p)}<div class="g"><a href="#/t/${p.id}">${esc(p.nickname)}</a><small>${b ? `in Ladder · Elo ${b.elo}${b.format ? ' ' + esc(b.format) : ''}` : 'non ancora in Ladder'}</small></div><button class="btn ${canNfc() ? 'gold' : 'ghost'} sm" data-act="tcWrite" data-u="${p.id}">${canNfc() ? '📡 Scrivi' : '📋 Link'}</button></div>` }).join('')}</div>`, 'ladder');
  }

  R.t = async id => { try { return id ? await card(id) : await card(BM.me.id) } catch (er) { shell(`<div class="err" role="alert">Qualcosa è andato storto: ${esc(er.message)}</div>`, 'ladder') } };
  R.tessere = async () => { try { await list() } catch (er) { shell(`<div class="err" role="alert">Qualcosa è andato storto: ${esc(er.message)}</div>`, 'ladder') } };

  /* il profilo #/p/<id> porta alla tessera */
  const P0 = R.p;
  if (P0) R.p = async id => {
    await P0(id);
    const h = document.querySelector('main h1, .t');
    if (h && BM.P.get(id)) { const a = document.createElement('div'); a.className = 'row'; a.style.cssText = 'gap:8px;margin:10px 0 0'; a.innerHTML = `<a class="btn ghost sm" href="#/t/${id}">📇 Tessera${id === BM.me.id || isAdm() ? ' NFC' : ''}${id !== BM.me.id && ladderOn() ? ' e sfida' : ''}</a>`; h.insertAdjacentElement('afterend', a) }
  };

  document.addEventListener('click', async e => {
    const el = e.target.closest('[data-act^="tc"]'); if (!el) return;
    const a = el.dataset.act;
    if (a === 'tcFmt') { fmt = el.dataset.v; try { localStorage.setItem('bm.card.fmt', fmt) } catch (x) { }
      document.querySelectorAll('[data-act="tcFmt"]').forEach(b => b.setAttribute('aria-pressed', b.dataset.v === fmt));
      document.querySelectorAll('.tc-e').forEach(c => c.classList.toggle('on', c.querySelector('span').textContent.endsWith(fmt))); return }
    if (a === 'tcCopy') { try { await navigator.clipboard.writeText(url(el.dataset.u)); toast('Link della tessera copiato.') } catch (x) { toast('Copia il link a mano.', 1) } return }
    if (a === 'tcWrite') { writeTag(el.dataset.u, el); return }
    if (a === 'tcGo') {
      const box = document.getElementById('tcAct'), id = el.dataset.u, k = el.dataset.k, p = BM.P.get(id);
      if (el.dataset.armed !== '1') {
        document.querySelectorAll('[data-act="tcGo"]').forEach(b => { b.dataset.armed = ''; b.classList.remove('arm') });
        el.dataset.armed = '1'; const old = el.innerHTML; el.innerHTML = `Confermi? Tocca ancora<small>${k === 'both' ? 'Ladder + taglia' : 'Ladder'} · ${esc(fmt)}</small>`;
        setTimeout(() => { if (el.isConnected && el.dataset.armed === '1') { el.dataset.armed = ''; el.innerHTML = old } }, 5000); return }
      el.disabled = true;
      try {
        const args = { p_opponent: id, p_format: (await BM.hasV11()) ? fmt : 'Advanced', p_message: (document.getElementById('tcMsg').value || '').trim() || null, p_request_id: box.dataset.rq };
        if (await BM.hasV11()) args.p_kind = k;
        await rpc('ladder_challenge', args);
        toast(`Sfida lanciata: ${p ? p.nickname : 'il duellante'} riceverà una notifica.`); BM.route();
      } catch (er) { toast(er.message, 1); el.disabled = false; el.dataset.armed = '' }
    }
  });
};
