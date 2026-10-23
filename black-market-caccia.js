/* =====================================================================
   BLACK MARKET — CACCIA ALLE TAGLIE
   Permette di SFIDARE chi ha una taglia addosso e di riscuotere dopo la vittoria.
   Non introduce regole nuove: usa la Ladder e la riscossione che esistono già.
     1. «Sfida» (Most Wanted, dashboard, profilo) → pagina #/hunt/<duellante> → sfida in Ladder (ladder_challenge)
     2. lo sfidato accetta, si gioca, uno invia il risultato e l'altro lo conferma (Ladder)
     3. la vittoria è un match WPA ufficiale e, alla conferma, la taglia si riscuote subito da sola (dalla migrazione 019; con un'attesa impostata resta a mano con claim_bounty)
   La pagina #/hunt (senza nome) elenca i ricercati e le taglie pronte da riscuotere.
   Il database decide tutto: qui si mostra e si chiede, nessun importo si calcola o si scrive dal browser.
   Serve il modulo Ladder acceso.
   ===================================================================== */
window.BM_HUNT = function (BM) {
  'use strict';
  const { R, shell, q, rpc, toast, esc, BC, when, av } = BM;
  const ladderOn = () => BM.S && BM.S.module_ladder == 1;
  const hold = () => (BM.S && BM.S.ladder_claim_hold_hours) ?? 24;
  const FMT = ['Advanced', 'Edison'];
  const OPEN = ['pending', 'accepted', 'reported', 'disputed'];
  const STAT = { pending: 'in attesa che accetti', accepted: 'accettata: da giocare', reported: 'risultato da confermare', disputed: 'risultato contestato' };
  const num = n => Number(n || 0).toLocaleString('it-IT');
  const left = ms => { const m = Math.ceil(ms / 60000), h = Math.floor(m / 60); return h >= 1 ? `${h} h ${m % 60} min` : `${m} min` };

  /* pulsante riusabile (Most Wanted, dashboard, profilo) */
  BM.huntBtn = (id, label) => {
    if (!BM.me || id === BM.me.id || !ladderOn()) return '';
    const p = BM.P.get(id); if (!p || p.suspended) return '';
    return `<a class="btn gold sm" href="#/hunt/${id}">${esc(label || 'Sfida')}</a>`;
  };
  const off = () => shell(`<h1 class="t">Caccia alle <em>taglie</em></h1><div class="box" style="margin-top:18px"><h2>Ladder non attiva</h2><p>Le sfide per le taglie passano dalla Ladder, che al momento è spenta. Puoi comunque riscuotere una taglia vincendo un match ufficiale in un evento (pagina <a href="#/events">Eventi</a>).</p></div>`, 'wanted');

  const steps = () => `<ol class="steps" style="margin:12px 0 0;padding-left:20px;line-height:1.55">
<li><b>Scegli formato e tipo di sfida</b> (Advanced o Edison; «per la taglia» oppure «Ladder + taglia») e lanciala. Lo sfidato riceve una notifica e vede il tipo prima di rispondere.</li>
<li><b>Se accetta, giocate</b>. Può anche rifiutare o lasciar scadere la sfida: in quel caso la taglia resta lì dov'è.</li>
<li><b>Uno invia il risultato, l'altro lo conferma</b>. Se vinci, il match diventa un match WPA ufficiale.</li>
${hold() > 0 ? `<li><b>Dopo ${hold()} ore riscuoti la taglia</b> da questa pagina (attesa anti-accordi). La parte che hai messo tu ti torna indietro, il resto è tuo.</li>` : `<li><b>Se vinci, la taglia è tua subito</b>: appena l'altro conferma il risultato viene riscossa da sola. La parte che hai messo tu ti torna indietro, il resto è tuo.</li>`}</ol>`;

  /* ---------- #/hunt/<id>: sfida un ricercato ---------- */
  async function target(id) {
    const p = BM.P.get(id), me = BM.me, sb = BM.sb;
    if (!p || p.suspended || id === me.id) return shell('<div class="err">Duellante non disponibile per una sfida.</div>', 'wanted');
    const [mw, mine, ms, st] = await Promise.all([
      q(sb.from('most_wanted_v').select('*').eq('id', id)),
      q(sb.from('bounties').select('amount,status,target_id').eq('creator_id', me.id)),
      q(sb.from('ladder_matches').select('*').order('created_at', { ascending: false }).limit(200)),
      q(sb.from('ladder_standings_v').select('*').order('rank').limit(200))]);
    const w = mw[0] || { bounty_value: 0, active_count: 0 };
    const own = mine.filter(b => b.target_id === id && b.status === 'active').reduce((t, b) => t + b.amount, 0);
    const gain = Math.max(0, w.bounty_value - own);
    const V = BM.hasV11 ? await BM.hasV11() : false;
    const eloTxt = uid => V ? FMT.map(f => { const r = st.find(x => x.user_id === uid && x.format === f); return r ? `${r.elo} ${f}` : null }).filter(Boolean).join(' · ') : ((st.find(r => r.user_id === uid) || {}).elo || '');
    const elo = eloTxt(id), myElo = eloTxt(me.id);
    const open = ms.find(m => OPEN.includes(m.status) && ((m.challenger_id === me.id && m.opponent_id === id) || (m.challenger_id === id && m.opponent_id === me.id)));
    const rq = crypto.randomUUID();
    shell(`<h1 class="t">Sfida per la <em>taglia</em></h1><p class="sub">Sfida ${esc(p.nickname)} in Ladder: se lo batti puoi riscuotere le taglie che ha addosso.</p>
<div class="box" style="margin-top:18px"><div class="row" style="gap:16px;align-items:center">${av(p).replace('class="av"', 'class="av xl"')}<div class="g" style="min-width:0"><a href="#/p/${id}" style="font:700 1.4rem var(--disp);color:var(--tx);text-decoration:none">${esc(p.nickname)}</a><small class="mute" style="display:block">${elo ? `Elo: ${elo}` : 'Non ancora classificato in Ladder'}${myElo ? ` · tu: ${myElo}` : ''}</small></div></div>
<div class="stats" style="margin-top:14px"><div class="stat"><b>${BC(w.bounty_value)}</b><span>Bounty Value (${w.active_count} ${w.active_count == 1 ? 'taglia attiva' : 'taglie attive'})</span></div>
<div class="stat"><b>${BC(gain)}</b><span>${own ? `che potresti incassare (le tue quote, ${BC(own)}, ti tornano indietro)` : 'che potresti incassare vincendo'}</span></div></div>
${w.bounty_value ? '' : '<p class="mute" style="margin:12px 0 0">Al momento non ci sono taglie su questo duellante: sarebbe una normale sfida in Ladder.</p>'}</div>
<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Come funziona</h2>${steps()}</div>
${open ? `<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Sfida già aperta</h2><p style="margin:0 0 10px">Tra voi c'è già una sfida: <b>${STAT[open.status]}</b>${open.challenger_id === id ? ' (ti ha sfidato lui)' : ''}.</p><a class="btn gold" href="#/ladder">Vai alla Ladder</a></div>`
        : `<form id="hf" class="box" style="margin-top:14px;display:grid;gap:10px;max-width:560px" data-rq="${rq}"><h2 style="margin:0">Lancia la sfida</h2>
<div><label for="hfm">Formato</label><select id="hfm">${FMT.map(f => `<option>${f}</option>`).join('')}</select></div>
${V ? `<div><label for="hfk">Tipo di sfida</label><select id="hfk" required><option value="">Scegli il tipo di sfida…</option><option value="ladder">Ladder normale (Elo, nessuna taglia)</option>${gain > 0 ? `<option value="bounty">Per la taglia (puoi incassare ${gain} BC, nessun Elo)</option><option value="both">Ladder + taglia (Elo e ${gain} BC)</option>` : ''}</select>
<p class="mute" style="font-size:.88rem;margin:6px 0 0">${gain > 0 ? '<b>Per la taglia</b>: conta solo il match ufficiale con cui riscuoti. <b>Ladder + taglia</b>: in gioco anche l\'Elo del formato e il premio Ladder. <b>Ladder normale</b>: nessuna taglia in gioco.' : 'Su questo duellante non c\'è niente che tu possa incassare: la sfida può essere solo una Ladder normale.'}</p></div>` : ''}
<div><label for="hms">Messaggio (facoltativo)</label><input id="hms" maxlength="140" value="${w.bounty_value ? 'Vengo a prendere la tua taglia!' : ''}"></div>
<button class="btn gold" type="submit">Lancia la sfida</button></form>`}`, 'wanted');
    const f = document.getElementById('hf');
    if (f) f.onsubmit = async e => {
      e.preventDefault(); const b = f.querySelector('button[type=submit]'); b.disabled = true;
      try {
        const a = { p_opponent: id, p_format: document.getElementById('hfm').value, p_message: document.getElementById('hms').value.trim() || null, p_request_id: f.dataset.rq };
        const k = document.getElementById('hfk'); if (k) { if (!k.value) throw new Error('Scegli il tipo di sfida'); a.p_kind = k.value }
        await rpc('ladder_challenge', a); toast('Sfida lanciata: ' + p.nickname + ' riceverà una notifica.'); BM.route() }
      catch (er) { toast(er.message, 1); b.disabled = false }
    };
  }

  /* ---------- #/hunt: ricercati e taglie da riscuotere ---------- */
  async function overview() {
    const me = BM.me, sb = BM.sb;
    const [mw, wins, sett, ms] = await Promise.all([
      q(sb.from('most_wanted_v').select('*').order('bounty_value', { ascending: false })),
      q(sb.from('matches').select('*').eq('source', 'ladder').eq('status', 'verified').eq('winner_id', me.id).order('verified_at', { ascending: false }).limit(40)),
      q(sb.from('bounty_settlements').select('match_id').eq('winner_id', me.id)),
      q(sb.from('ladder_matches').select('*').order('created_at', { ascending: false }).limit(200))]);
    const done = new Set(sett.map(s => s.match_id)), val = new Map(mw.map(r => [r.id, r]));
    const claim = wins.filter(m => !done.has(m.id) && m.bounty_eligible !== false).map(m => ({ m, t: m.player_a === me.id ? m.player_b : m.player_a })).filter(x => (val.get(x.t) || {}).bounty_value > 0);
    const now = Date.now();
    const openWith = id => ms.find(m => OPEN.includes(m.status) && ((m.challenger_id === me.id && m.opponent_id === id) || (m.challenger_id === id && m.opponent_id === me.id)));
    const list = mw.filter(r => r.id !== me.id && !(BM.P.get(r.id) || {}).suspended);
    shell(`<h1 class="t">Caccia alle <em>taglie</em></h1><p class="sub">Sfida chi ha una taglia addosso. ${hold() > 0 ? `Se vinci in Ladder, dopo ${hold()} ore puoi riscuoterla.` : 'Se vinci in Ladder, la taglia è tua subito, appena l\'avversario conferma il risultato.'}</p>
<div class="box" style="margin-top:18px"><h2 style="margin-top:0">Come funziona</h2>${steps()}</div>
<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Taglie da riscuotere${claim.length ? ` (${claim.length})` : ''}</h2>${claim.map(({ m, t }) => {
      const at = new Date(m.verified_at).getTime() + hold() * 3600000, ready = now >= at, r = val.get(t);
      return `<div class="row2"><div class="g">Hai battuto <a href="#/p/${t}">${esc(BM.pn(t))}</a><small>${when(m.verified_at)} · ora ha ${BC(r.bounty_value)} di taglie${ready ? '' : ` · disponibile tra ${left(at - now)}`}</small></div>${ready ? `<button class="btn gold sm" data-act="claim" data-m="${m.id}">Riscuoti</button>` : '<span class="tag">in attesa</span>'}</div>`;
    }).join('') || `<p class="mute" style="margin:0">Niente da riscuotere.${hold() > 0 ? ' Quando batti in Ladder un duellante con una taglia, la trovi qui.' : ' Le taglie vinte in Ladder si riscuotono da sole alla conferma; qui compaiono solo quelle rimaste in sospeso (per esempio se la taglia era in revisione).'}</p>`}</div>
<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Ricercati (${list.length})</h2>${list.map((r, i) => { const o = openWith(r.id); return `<div class="row2"><span class="rank">${i + 1}</span>${av(BM.P.get(r.id))}<div class="g"><a href="#/p/${r.id}">${esc(r.nickname)}</a><small>${r.active_count} ${r.active_count == 1 ? 'taglia attiva' : 'taglie attive'}</small></div><span class="val">${BC(r.bounty_value)}</span>${o ? '<a class="btn ghost sm" href="#/ladder">Sfida aperta</a>' : BM.huntBtn(r.id, 'Sfida')}</div>` }).join('') || '<p class="mute" style="margin:0">Nessun ricercato al momento: metti una taglia da «Metti una taglia».</p>'}</div>`, 'wanted');
  }

  R.hunt = async id => {
    if (!ladderOn()) return off();
    try { return id ? await target(id) : await overview() }
    catch (er) { shell(`<div class="err" role="alert">Qualcosa è andato storto: ${esc(er.message)}</div>`, 'wanted') }
  };
};
