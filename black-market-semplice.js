/* =====================================================================
   BLACK MARKET SEMPLIFICATO
   - #/sfida[/<duellante>]: UN solo modo per sfidare qualcuno. Si sceglie l'avversario,
     il formato e cosa c'è in palio (Classificata, Solo taglia, Classificata + taglia,
     Underground). Sotto usa le stesse funzioni di prima (ladder_challenge, create_challenge).
   - Primi passi: 4 obiettivi con bonus in BC per i nuovi duellanti (scheda Oggi).
   - Pallino sulla scheda Sfide quando c'è qualcosa da fare.
   - Vetrina pubblica (chi non ha un account vede classifica e ricercati).
   Primi passi e vetrina richiedono la migrazione black-market-semplice.sql (045):
   senza, la pagina funziona lo stesso e queste due parti non compaiono.
   ===================================================================== */
(function () {
  'use strict';
  const num = n => Number(n || 0).toLocaleString('it-IT');
  const day = d => new Date(d).toLocaleDateString('it-IT', { day: '2-digit', month: 'short' });

  /* ---------------- vetrina pubblica (senza account) ---------------- */
  let scCache = null, scAt = 0;
  window.BM_SHOWCASE = async (sb, el, o) => {
    if (!el) return;
    const esc = o.esc;
    try {
      if (!scCache || Date.now() - scAt > 60000) {
        const { data, error } = await sb.rpc('public_showcase');
        if (error) throw error;
        scCache = data; scAt = Date.now();
      }
    } catch (e) { return }                                    // migrazione 045 non eseguita: niente vetrina
    const d = scCache; if (!d || !d.on || !el.isConnected) return;
    const fm = Object.keys(d.ladder || {}).sort(), avs = r => `<span class="av" aria-hidden="true">${esc(r.avatar || (r.nick || '?')[0].toUpperCase())}</span>`;
    let f = fm[0];
    const lad = () => (d.ladder[f] || []).map(r => `<div class="row2"><span class="rank">${r.rank}</span>${avs(r)}<div class="g"><b>${esc(r.nick)}</b><small>${r.w}V · ${r.d}P · ${r.l}S</small></div><span class="val">${r.elo}</span></div>`).join('') || '<p class="mute bmd-empty">Ancora nessun classificato.</p>';
    const res = r => r.res === 'draw' ? `<b>${esc(r.a)}</b> e <b>${esc(r.b)}</b> pareggiano` : r.res === 'challenger' ? `<b>${esc(r.a)}</b> batte ${esc(r.b)}` : `<b>${esc(r.b)}</b> batte ${esc(r.a)}`;
    const sc = r => !r.score ? '' : r.res === 'opponent' ? r.score.split('-').reverse().join('-') : r.score;
    const c = d.counts || {};
    el.innerHTML = `<div class="sc">
<div class="sc-k"><span><b>${num(c.players)}</b> duellanti</span><span><b>${num(c.bounty_bc)}</b> BC in taglie</span><span><b>${num(c.matches_30d)}</b> sfide in 30 giorni</span></div>
<div class="bmd-cols">
<section class="bmd-s"><div class="bmd-h"><h2>🏆 Classifica Ladder</h2></div>${fm.length > 1 ? `<div class="seg bmd-seg">${fm.map(x => `<button type="button" data-scf="${esc(x)}" aria-pressed="${x === f}">${esc(x)}</button>`).join('')}</div>` : ''}<div class="sc-l">${lad()}</div></section>
<section class="bmd-s"><div class="bmd-h"><h2>🎯 Più ricercati</h2></div>${(d.wanted || []).map((r, i) => `<div class="row2"><span class="rank">${i + 1}</span>${avs(r)}<div class="g"><b>${esc(r.nick)}</b><small>${r.count} ${r.count == 1 ? 'taglia' : 'taglie'}</small></div><span class="val">${num(r.value)} BC</span></div>`).join('') || '<p class="mute bmd-empty">Nessuna taglia attiva.</p>'}</section>
</div>
${(d.recent || []).length ? `<section class="bmd-s" style="margin-top:14px"><div class="bmd-h"><h2>⚔️ Ultime sfide</h2></div>${d.recent.map(r => `<div class="row2"><div class="g">${res(r)}${sc(r) ? ' · ' + esc(sc(r)) : ''}<small>${esc(r.format || '')} · ${day(r.at)}</small></div></div>`).join('')}</section>` : ''}
<p class="sc-cta">Registrati e ricevi <b>${num(d.welcome_bc || 1000)} BC</b> di benvenuto per sfidare chiunque qui sopra.</p></div>`;
    el.querySelectorAll('[data-scf]').forEach(b => b.onclick = () => {
      f = b.dataset.scf; el.querySelectorAll('[data-scf]').forEach(x => x.setAttribute('aria-pressed', x === b)); el.querySelector('.sc-l').innerHTML = lad();
    });
  };

  /* ---------------- dentro il Black Market ---------------- */
  window.BM_SIMPLE = function (BM) {
    const { R, shell, q, rpc, toast, esc, av } = BM;
    const S = () => BM.S || {};
    const ladderOn = () => S().module_ladder == 1, ugOn = () => S().module_underground == 1;
    const FMT = ['Advanced', 'Edison'], OPEN = ['pending', 'accepted', 'reported', 'disputed'];

    /* primi passi + sblocco del menu (onboarding_state); null se la migrazione 045 manca */
    let ob = null, obAt = 0;
    BM.onb = async (fresh) => {
      if (ob && !fresh && Date.now() - obAt < 30000) return ob;
      try { ob = await rpc('onboarding_state', {}); obAt = Date.now() } catch (e) { ob = null }
      return ob;
    };

    /* pallino sulla scheda Sfide: sfide da accettare, da giocare o da confermare */
    let todo = 0, todoAt = 0, todoBusy = false;
    const paintDot = () => document.querySelectorAll('.bm-dot').forEach(d => { d.hidden = !todo; d.textContent = todo > 9 ? '9+' : todo });
    BM.afterShell = () => {
      paintDot();
      if (todoBusy || Date.now() - todoAt < 45000 || !ladderOn() || !BM.me) return;
      todoBusy = true;
      const me = BM.me.id, c = b => b.then(r => { if (r.error) throw r.error; return r.count || 0 });
      const base = () => BM.sb.from('ladder_matches').select('id', { count: 'exact', head: true });
      Promise.all([c(base().eq('status', 'pending').eq('opponent_id', me)),
        c(base().eq('status', 'accepted').or(`challenger_id.eq.${me},opponent_id.eq.${me}`)),
        c(base().eq('status', 'reported').neq('reported_by', me).or(`challenger_id.eq.${me},opponent_id.eq.${me}`))])
        .then(n => { todo = n[0] + n[1] + n[2]; todoAt = Date.now(); paintDot() }).catch(() => { todoAt = Date.now() }).finally(() => { todoBusy = false });
    };
    const resetTodo = () => { todoAt = 0 };

    /* ogni pulsante «Sfida» (Most Wanted, Oggi, profilo, classifica) porta qui */
    BM.huntBtn = (id, label) => {
      if (!BM.me || id === BM.me.id || !(ladderOn() || ugOn())) return '';
      const p = BM.P.get(id); if (!p || p.suspended) return '';
      return `<a class="btn gold sm" href="#/sfida/${id}">${esc(label || 'Sfida')}</a>`;
    };
    const hunt = R.hunt;
    R.hunt = async id => id ? R.sfida(id) : hunt ? hunt() : R.sfida();

    /* ================== #/sfida ================== */
    R.sfida = async arg => {
      const head = '<h1 class="t">Lancia una <em>sfida</em></h1>';
      if (!ladderOn() && !ugOn()) return shell(`${head}<div class="box" style="margin-top:14px"><p style="margin:0">Le sfide non sono attive in questo momento.</p></div>`, 'sfida');
      shell(head + '<p class="mute" role="status">Caricamento…</p>', 'sfida');
      const [raw, qs] = String(arg || '').split('?'), id = raw && BM.P.has(raw) ? raw : '', qf = new URLSearchParams(qs || '').get('f');
      const me = BM.me, sb = BM.sb, V = ladderOn() && BM.hasV11 ? await BM.hasV11() : false;
      const [st, mw, own0, open0] = await Promise.all([
        ladderOn() ? q(sb.from('ladder_standings_v').select('*')).catch(() => []) : [],
        q(sb.from('most_wanted_v').select('id,bounty_value')).catch(() => []),
        q(sb.from('bounties').select('target_id,amount').eq('creator_id', me.id).eq('status', 'active')).catch(() => []),
        ladderOn() ? q(sb.from('ladder_matches').select('id,challenger_id,opponent_id,status').in('status', OPEN).or(`challenger_id.eq.${me.id},opponent_id.eq.${me.id}`)).catch(() => []) : []]);
      const val = new Map(mw.map(r => [r.id, r.bounty_value])), own = new Map();
      own0.forEach(b => own.set(b.target_id, (own.get(b.target_id) || 0) + b.amount));
      const claim = u => Math.max(0, (val.get(u) || 0) - (own.get(u) || 0));
      const elo = (f, u) => (st.find(r => r.user_id === u && (!V || r.format === f)) || {}).elo;
      let fmt = FMT.includes(qf) ? qf : (sessionStorage.getItem('ldfmt') || FMT[0]);

      /* ---------- passo 1: chi sfidi? ---------- */
      if (!id) {
        const cand = [...BM.P.values()].filter(p => p.id !== me.id && !p.suspended);
        const mine = elo(fmt, me.id) || 1000;
        const near = cand.filter(p => elo(fmt, p.id)).sort((a, b) => Math.abs(elo(fmt, a.id) - mine) - Math.abs(elo(fmt, b.id) - mine)).slice(0, 4);
        const hot = cand.filter(p => claim(p.id) > 0 && !near.includes(p)).sort((a, b) => claim(b.id) - claim(a.id)).slice(0, 4);
        const row = p => { const e = V ? FMT.map(f => elo(f, p.id)).filter(Boolean) : [elo(null, p.id)].filter(Boolean), c = claim(p.id);
          return `<a class="row2 sf-p" href="#/sfida/${p.id}" data-n="${esc(p.nickname.toLowerCase())}">${av(p)}<div class="g"><b>${esc(p.nickname)}</b><small>${e.length ? 'Elo ' + e.join(' / ') : 'Non classificato'}${c > 0 ? ` · <span style="color:var(--gold)">🎯 ${num(c)} BC</span>` : ''}</small></div><span class="sf-go" aria-hidden="true">›</span></a>` };
        shell(`${head}<p class="sub">Passo 1 di 2 · Scegli chi sfidare.</p>
<input id="sfq" type="search" placeholder="Cerca un duellante…" aria-label="Cerca un duellante" style="margin-top:14px">
<div id="sfsug">${near.length ? `<section class="bmd-s" style="margin-top:12px"><div class="bmd-h"><h2>Al tuo livello</h2></div>${near.map(row).join('')}</section>` : ''}
${hot.length ? `<section class="bmd-s" style="margin-top:12px"><div class="bmd-h"><h2>🎯 Con una taglia da incassare</h2></div>${hot.map(row).join('')}</section>` : ''}</div>
<section class="bmd-s" style="margin-top:12px"><div class="bmd-h"><h2>Tutti i duellanti</h2></div><div id="sfall">${cand.sort((a, b) => a.nickname.localeCompare(b.nickname)).map(row).join('') || '<p class="mute bmd-empty">Ancora nessun altro duellante.</p>'}</div></section>`, 'sfida');
        const qi = document.getElementById('sfq');
        qi.oninput = () => { const t = qi.value.trim().toLowerCase(); document.getElementById('sfsug').hidden = !!t; document.querySelectorAll('#sfall .sf-p').forEach(r => r.hidden = !!t && !r.dataset.n.includes(t)) };
        return;
      }

      /* ---------- passo 2: formato e posta ---------- */
      const p = BM.P.get(id), c = claim(id), busy = open0.find(m => OPEN.includes(m.status) && (m.challenger_id === id || m.opponent_id === id));
      const rwOn = (S().ladder_reward_enabled ?? 1) === 1, rwBc = S().ladder_reward_bc ?? 20;
      const K = [];
      if (ladderOn() && !busy) {
        K.push(['ladder', '⚔️', 'Classificata', `Conta per l'Elo${rwOn ? ` · +${rwBc} BC a chi vince` : ''}`]);
        if (V && c > 0) { K.push(['both', '🔥', 'Classificata + taglia', `Elo e ${num(c)} BC se vinci`]); K.push(['bounty', '🎯', 'Solo per la taglia', `${num(c)} BC se vinci · l'Elo non cambia`]) }
      }
      if (ugOn()) K.push(['ug', '🥷', 'Underground', 'Sfida libera, senza Elo né BC: conta solo se la giocate a un evento']);
      let kind = (K.find(k => k[0] === 'both') || K[0] || [])[0];
      const paint = () => {
        const isUg = kind === 'ug';
        document.getElementById('sfk').innerHTML = K.map(([k, i, l, d]) => `<button type="button" class="sf-k" data-k="${k}" aria-pressed="${k === kind}"><i aria-hidden="true">${i}</i><span><b>${l}</b><small>${d}</small></span></button>`).join('');
        const fw = document.getElementById('sffw'); if (fw) fw.hidden = isUg || !V;
        document.querySelectorAll('#sff button').forEach(b => b.setAttribute('aria-pressed', b.dataset.f === fmt));
        const k = K.find(x => x[0] === kind);
        document.getElementById('sfsum').innerHTML = !k ? '' : `Sfidi <b>${esc(p.nickname)}</b>${isUg || !V ? '' : ` in <b>${fmt}</b>`} · ${k[2]}. ${esc(p.nickname)} riceve una notifica e può accettare o rifiutare.`;
        document.querySelectorAll('#sfk .sf-k').forEach(b => b.onclick = () => { kind = b.dataset.k; paint() });
      };
      shell(`${head}<p class="sub">Passo 2 di 2 · Formato e cosa c'è in palio.</p>
<section class="bmd-me sf-who" style="margin-top:14px"><div class="bmd-id">${av(p).replace('class="av"', 'class="av xl"')}<div class="bmd-nm"><h1>${esc(p.nickname)}</h1><small class="mute">${ladderOn() ? (V ? FMT.map(f => `${f} ${elo(f, id) || '—'}`).join(' · ') : 'Elo ' + (elo(null, id) || '—')) : ''}${c > 0 ? ` · 🎯 ${num(c)} BC` : ''}</small><div class="bmd-lk"><a href="#/sfida">Cambia avversario</a><a href="#/p/${id}">Profilo</a></div></div></div></section>
${busy ? `<div class="note" style="margin-top:12px">Con ${esc(p.nickname)} hai già una sfida in Ladder aperta. <a href="#/sfide">Vai alle tue sfide</a>.</div>` : ''}
${K.length ? `<form id="sff2" class="bmd-s" style="margin-top:12px;display:grid;gap:14px" data-rq="${crypto.randomUUID()}">
<div id="sffw"><h2 class="sf-h">Formato</h2><div class="seg" id="sff">${FMT.map(f => `<button type="button" data-f="${f}" aria-pressed="${f === fmt}">${f}</button>`).join('')}</div></div>
<div><h2 class="sf-h">Cosa c'è in palio</h2><div id="sfk" class="sf-ks"></div></div>
<div><label for="sfm">Messaggio (facoltativo)</label><input id="sfm" maxlength="140" placeholder="${c > 0 ? 'Vengo a prendere la tua taglia!' : 'Ci vediamo al tavolo!'}"></div>
<p id="sfsum" class="mute" style="margin:0;font-size:.9rem"></p>
<button class="btn gold" type="submit" style="min-height:52px;font-size:1.05rem">⚔️ Lancia la sfida</button></form>` : ''}`, 'sfida');
      if (!K.length) return;
      document.querySelectorAll('#sff button').forEach(b => b.onclick = () => { fmt = b.dataset.f; try { sessionStorage.setItem('ldfmt', fmt) } catch (e) {} paint() });
      paint();
      const f = document.getElementById('sff2');
      f.onsubmit = async e => {
        e.preventDefault(); const b = f.querySelector('button[type=submit]'); b.disabled = true;
        const msg = document.getElementById('sfm').value.trim() || null;
        try {
          if (kind === 'ug') await rpc('create_challenge', { p_opponent: id, p_message: msg, p_request_id: f.dataset.rq });
          else { const a = { p_opponent: id, p_format: V ? fmt : 'Advanced', p_message: msg, p_request_id: f.dataset.rq }; if (V) a.p_kind = kind; await rpc('ladder_challenge', a) }
          toast(`Sfida lanciata: ${p.nickname} riceverà una notifica.`); resetTodo(); BM.onb(true); location.hash = '#/sfide';
        } catch (er) { toast(er.message, 1); b.disabled = false }
      };
    };

    /* ================== primi passi (scheda Oggi) ================== */
    const STEPS = { photo: ['📷', 'Aggiungi una foto', 'Così gli altri ti riconoscono', null], challenge: ['⚔️', 'Lancia la tua prima sfida', 'Scegli un avversario', '#/sfida'],
      bounty: ['🎯', 'Metti la tua prima taglia', 'Su un rivale da battere', '#/new'], match: ['🏁', 'Concludi il tuo primo match', 'Giocate e confermate il risultato', '#/sfide'] };
    const dash = R[''];
    R[''] = async (...a) => {
      await dash(...a);
      const o = await BM.onb(true);
      const box = document.querySelector('#app .bmd-onb');
      if (!o || !o.on || !box || !box.isConnected) return;
      const ss = o.steps.filter(s => STEPS[s.step]); if (ss.every(s => s.claimed)) return;
      const n = ss.filter(s => s.claimed).length;
      box.innerHTML = `<section class="bmd-s onb"><div class="bmd-h"><h2>🚀 Primi passi</h2><span class="mute" style="font-size:.85rem">${n}/${ss.length} · +${num(o.bc)} BC l'uno</span></div>
<div class="onb-bar"><i style="width:${Math.round(100 * n / ss.length)}%"></i></div>
${ss.map(s => { const [i, t, d, href] = STEPS[s.step];
        const btn = s.claimed ? '<span class="onb-ok" aria-label="Fatto">✓</span>' : s.done ? `<button class="btn gold sm" data-act="onbClaim" data-s="${s.step}">Ritira +${num(o.bc)}</button>`
          : href ? `<a class="btn ghost sm" href="${href}">Vai</a>` : '<button class="btn ghost sm" data-act="avPick">Vai</button>';
        return `<div class="onb-r${s.claimed ? ' done' : ''}"><i aria-hidden="true">${i}</i><span><b>${t}</b><small>${d}</small></span>${btn}</div>` }).join('')}</section>`;
    };

    /* ================== azioni ================== */
    const prevAct = BM.act;
    BM.act = async (a, el) => {
      if (prevAct && await prevAct(a, el)) return true;
      if (a === 'onbClaim') {
        el.disabled = true;
        try { const r = await rpc('onboarding_claim', { p_step: el.dataset.s }); toast(r.bc ? `+${num(r.bc)} BC: obiettivo completato!` : 'Bonus già ritirato.'); await BM.core(); BM.route() }
        catch (er) { toast(er.message, 1); el.disabled = false }
        return true;
      }
      return false;
    };

    /* stile delle parti nuove */
    const css = document.createElement('style');
    css.textContent = `.sf-p{color:var(--tx)!important;text-decoration:none}.sf-p:hover{background:var(--raise)}.sf-p[hidden]{display:none}.sf-go{color:var(--mu);font-size:1.4rem}
.sf-who{grid-template-columns:1fr}.sf-who small{display:block}
.sf-h{margin:0 0 8px!important;font-size:.95rem!important;color:var(--mu)!important;font-family:var(--ui)!important;letter-spacing:.06em;text-transform:uppercase}
#sff button{flex:1}
.sf-ks{display:grid;gap:8px}
.sf-k{display:flex;align-items:center;gap:12px;width:100%;padding:12px 14px;border:1.5px solid var(--line);border-radius:14px;background:var(--raise);color:var(--tx);text-align:left;font:inherit;cursor:pointer}
.sf-k i{font-style:normal;font-size:1.5rem;flex:none}.sf-k b{display:block;font:700 1rem var(--ui)}.sf-k small{display:block;color:var(--mu);font-size:.82rem;line-height:1.3}
.sf-k[aria-pressed=true]{border-color:var(--gold);background:rgba(212,168,67,.14)}.sf-k[aria-pressed=true] b{color:var(--gold)}
.onb{border-color:rgba(212,168,67,.55);background:linear-gradient(160deg,rgba(212,168,67,.12),transparent 60%),var(--surf)}
.onb-bar{height:6px;margin:6px 0 4px;border-radius:9px;background:var(--raise);overflow:hidden}.onb-bar i{display:block;height:100%;background:var(--gold);border-radius:9px}
.onb-r{display:flex;align-items:center;gap:12px;padding:10px 0;border-top:1px solid var(--line)}.onb-r:first-of-type{border-top:0}
.onb-r>i{font-style:normal;font-size:1.3rem;width:30px;text-align:center;flex:none}.onb-r span{flex:1;min-width:0}.onb-r b{display:block;font-size:.95rem}.onb-r small{color:var(--mu);font-size:.8rem}
.onb-r.done{opacity:.55}.onb-r.done b{text-decoration:line-through}.onb-ok{color:#4ade9b;font-weight:800;font-size:1.2rem;padding:0 10px}
.onb-r .btn{min-height:36px;flex:none}
.sc{margin-top:18px}.sc-k{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px}.sc-k span{flex:1 1 100px;padding:10px 12px;border:1px solid var(--line);border-radius:12px;background:var(--surf);color:var(--mu);font-size:.8rem}.sc-k b{display:block;color:var(--gold);font:600 1.25rem var(--disp)}
.sc .row2 b{color:var(--tx)}.sc-cta{margin:14px 0 0;padding:12px 14px;border:1px dashed rgba(212,168,67,.6);border-radius:12px;text-align:center}.sc-cta b{color:var(--gold)}`;
    document.head.appendChild(css);
  };
})();
