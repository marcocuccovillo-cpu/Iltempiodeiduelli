/* =====================================================================
   BLACK MARKET — SCOMMESSE sulle sfide Ladder (comprese quelle «per la taglia»)
   Pagina #/bets: si punta sulla vittoria di uno dei due sfidanti, si vedono le scommesse in corso e quelle chiuse.
   Il database decide tutto (quote, finestra di puntata, vincite, rimborsi): qui si mostra e si chiede, nessun importo si calcola o si scrive
   dal browser; la «vincita possibile» mostrata è solo un'anteprima (puntata × quota, per difetto) e il database ricalcola.
   Richiede la migrazione black-market-scommesse.sql e il modulo Ladder acceso.
   ===================================================================== */
window.BM_BETS = function (BM) {
  'use strict';
  const { R, shell, q, rpc, toast, esc, BC, when, av } = BM;
  const S = () => BM.S || {};
  const ladderOn = () => S().module_ladder == 1;
  const ready = () => S().bet_enabled !== undefined;               // la riga esiste solo dopo la migrazione
  const minS = () => S().bet_min_stake ?? 10;
  const maxS = () => S().bet_max_stake ?? 200;
  const num = n => Number(n || 0).toLocaleString('it-IT');
  const qt = c => (c / 100).toLocaleString('it-IT', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const pc = n => Number(n).toLocaleString('it-IT', { maximumFractionDigits: 1 }) + '%';
  const hhmm = d => new Date(d).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' });
  const KN = { ladder: 'Ladder normale', bounty: 'Per la taglia', both: 'Ladder + taglia' };
  const ST = { pending: 'in attesa che accetti', accepted: 'accettata: si gioca' };
  const BASIS = { mix: 'da win rate, taglie e scommesse insieme', even: 'alla pari (nessun dato)', winrate: 'dal win rate in Ladder', bounty: 'dal valore delle taglie', bets: 'dalle scommesse già presenti' };
  const sig = x => 1 / (1 + Math.exp(-x));
  /* «Come è calcolata»: cosa dice ognuno dei tre segnali e di quanti punti sposta la stima (da solo), con il suo peso */
  const why = m => {
    const qd = m.quote, a = esc(m.challenger_name), b = esc(m.opponent_name);
    const row = (name, wKey, wDef, data, l) => {
      if (data === null) return `<tr><td>${name}</td><td class="mute" colspan="2">nessun dato: non conta</td></tr>`;
      const pts = Math.round((sig(l) - 0.5) * 100), w = S()[wKey] ?? wDef;
      const eff = w <= 0 ? 'spento' : Math.abs(pts) < 1 ? 'nessuno spostamento' : `${pts > 0 ? a : b} +${Math.abs(pts)} punti`;
      return `<tr><td>${name}</td><td>${data}</td><td>${eff} <span class="mute">(peso ${w}%)</span></td></tr>`;
    };
    const wr = qd.p_winrate === null || qd.p_winrate === undefined ? null : `${a} ${pc(qd.p_winrate)} · ${b} ${pc(100 - qd.p_winrate)} <span class="mute">(${qd.games_challenger} e ${qd.games_opponent} partite)</span>`;
    const bo = (qd.bounty_challenger || 0) + (qd.bounty_opponent || 0) > 0 ? `${a} ${BC(qd.bounty_challenger || 0)} · ${b} ${BC(qd.bounty_opponent || 0)}` : null;
    const po = (qd.pool_challenger || 0) + (qd.pool_opponent || 0) > 0 ? `${a} ${BC(qd.pool_challenger || 0)} · ${b} ${BC(qd.pool_opponent || 0)}` : null;
    return `<details style="margin-top:6px"><summary class="mute" style="cursor:pointer;font-size:.85rem">Come è calcolata questa quota</summary>
<table style="width:100%;font-size:.85rem;border-collapse:collapse;margin-top:6px"><tbody>
${row('Win rate Ladder', 'bet_w_winrate', 100, wr, qd.l_winrate || 0)}${row('Taglie (bounty value)', 'bet_w_bounty', 30, bo, qd.l_bounty || 0)}${row('Scommesse già presenti', 'bet_w_pool', 40, po, qd.l_bets || 0)}
</tbody></table><p class="mute" style="font-size:.8rem;margin:6px 0 0">I tre effetti si sommano. Poi si toglie il margine della casa (${qd.margin_pct ?? 10}%). Più BC vengono puntati su uno, più la sua quota scende.</p></details>`;
  };
  const MS = { pending: 'in attesa che accetti', accepted: 'accettata', reported: 'risultato inviato', closed: 'chiusa', declined: 'rifiutata', cancelled: 'annullata', expired: 'scaduta', voided: 'annullata dall\'admin', disputed: 'contestata' };
  const missing = er => /could not find the function|schema cache|does not exist/i.test(er.message || '');
  const reqIds = new Map();                                         // stessa richiesta se si riprova: nessun doppio addebito
  const reqId = k => { if (!reqIds.has(k)) reqIds.set(k, (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2)) + '-bet'); return reqIds.get(k); };

  const prevNav = BM.navItems;
  BM.navItems = () => [...(prevNav ? prevNav() : []), ...(ladderOn() && ready() && S().bet_enabled == 1 ? [['bets', 'Scommesse']] : [])];

  const head = `<h1 class="t">Scom<em>messe</em></h1><p class="sub">Punta BC sulla vittoria di un duellante nelle sfide Ladder. Se vince ricevi puntata × quota, se perde la puntata è persa; pareggio o sfida non giocata: la puntata ti torna.</p>`;
  const how = () => BM.fold('bets-how', 'Come funziona', `<ul class="mute" style="margin:0;padding-left:20px;line-height:1.6">
<li><b>La quota</b> tiene conto di <b>tre cose insieme</b>: il <b>win rate</b> in Ladder nel formato della sfida (pesa per intero se entrambi hanno almeno ${S().bet_min_games ?? 3} partite, meno se ne hanno meno), il <b>valore delle taglie</b> che hanno addosso (chi ne ha di più è considerato il favorito) e le <b>scommesse già presenti</b> su quella sfida (più BC sono su un duellante, più la sua quota scende). Un fattore senza dati non conta. È fissata quando punti.</li>
<li><b>Puntata</b> da ${BC(minS())} a ${BC(maxS())}, una sola scommessa per sfida, al massimo ${S().bet_max_open ?? 5} aperte insieme. Chi gioca la sfida non può scommettere su di essa.</li>
<li><b>Si punta</b> finché la sfida è in attesa o appena accettata${(S().bet_close_minutes ?? 10) > 0 ? ` (entro ${S().bet_close_minutes ?? 10} minuti dall'accettazione)` : ''}, mai dopo l'invio del risultato.</li>
<li><b>La vincita arriva da sola</b> appena la sfida si chiude. Se l'amministratore corregge un risultato, le scommesse vengono ricalcolate.</li></ul>`, { style: 'margin-top:14px' });
  const off = msg => shell(head + `<div class="box" style="margin-top:18px"><h2>${msg[0]}</h2><p>${msg[1]}</p><a class="btn ghost" href="#/">Torna alla dashboard</a></div>`, 'bets');

  /* ---------- una sfida su cui puntare ---------- */
  const pickBtn = (m, side) => {
    const qd = m.quote, id = side === 'c' ? m.challenger : m.opponent, nm = side === 'c' ? m.challenger_name : m.opponent_name;
    const quota = side === 'c' ? qd.quota_challenger : qd.quota_opponent, p = side === 'c' ? qd.p_challenger : qd.p_opponent;
    return `<button class="btn gold" style="flex:1;min-width:130px;flex-direction:column;line-height:1.25" data-act="betPick" data-m="${m.id}" data-p="${id}" data-n="${esc(nm)}" data-q="${quota}"><span>${esc(nm)}</span><b style="font-size:1.25rem">${qt(quota)}</b><small style="color:inherit;opacity:.85;font-weight:600">${pc(p)} stimato</small></button>`;
  };
  const market = m => {
    const head2 = `<b>${esc(m.challenger_name)}</b> <span class="mute">vs</span> <b>${esc(m.opponent_name)}</b><small>${esc(m.format)} · ${KN[m.kind] || ''} · ${ST[m.status] || ''} · ${when(m.created_at)}</small>`;
    let body;
    if (m.mine) {
      const who = m.mine.pick === m.challenger ? m.challenger_name : m.opponent_name;
      body = `<p style="margin:8px 0 0">La tua scommessa: <b>${BC(m.mine.stake)}</b> su <b>${esc(who)}</b> a quota <b>${qt(m.mine.quota)}</b> · vincita possibile <b>${BC(Math.floor(m.mine.stake * m.mine.quota / 100))}</b></p>`;
    } else if (!m.can_bet) {
      body = `<p class="mute" style="margin:8px 0 0">Giochi tu questa sfida: non puoi scommettere su di essa.</p>`;
    } else if (!m.open) {
      body = `<p class="mute" style="margin:8px 0 0">Scommesse chiuse per questa sfida.</p>`;
    } else {
      body = `<div class="row" style="gap:10px;margin-top:10px;flex-wrap:wrap">${pickBtn(m, 'c')}${pickBtn(m, 'o')}</div>
<p class="mute" style="font-size:.85rem;margin:6px 0 0">Quota ${BASIS[m.quote.basis] || ''}${(m.quote.pool_challenger || 0) + (m.quote.pool_opponent || 0) > 0 ? ` · puntati finora: ${esc(m.challenger_name)} ${BC(m.quote.pool_challenger || 0)}, ${esc(m.opponent_name)} ${BC(m.quote.pool_opponent || 0)}` : ''}${m.closes_at ? ` · si punta fino alle ${hhmm(m.closes_at)}` : ''}</p>${why(m)}
<div class="bet-panel" data-m="${m.id}" hidden style="margin-top:10px;border-top:1px solid var(--line,#444);padding-top:10px">
  <label for="bs-${m.id}">Puntata su <b class="bet-who"></b> (BC)</label>
  <div class="row" style="gap:10px;align-items:center;flex-wrap:wrap"><input id="bs-${m.id}" class="bet-stake" type="number" inputmode="numeric" min="${minS()}" max="${maxS()}" step="1" value="${Math.min(maxS(), Math.max(minS(), 50))}" style="width:120px">
  <span class="bet-win mute"></span></div>
  <div class="row" style="gap:10px;margin-top:10px"><button class="btn gold sm" data-act="betGo" data-m="${m.id}">Conferma puntata</button><button class="btn ghost sm" data-act="betCancel" data-m="${m.id}">Annulla</button></div>
</div>`;
    }
    return `<div class="row2" style="align-items:stretch;flex-direction:column"><div class="g" style="flex:none;width:100%">${head2}</div><div style="flex:none;width:100%">${body}</div></div>`;
  };

  /* ---------- una mia scommessa ---------- */
  const mine = b => {
    const st = { open: ['In corso', ''], won: ['Vinta', 'pos'], lost: ['Persa', 'neg'], refunded: ['Restituita', ''], revoked: ['Revocata', 'neg'] }[b.status] || [b.status, ''];
    const res = b.status === 'revoked' ? ` · pagamento revocato dall'amministratore${b.returned > 0 ? `, ti restano ${BC(b.returned)} (puntata restituita)` : ''}` : b.status === 'won' ? ` · incassati <b class="pos">${BC(b.returned)}</b>` : b.status === 'refunded' ? ` · tornati ${BC(b.returned)}` : b.status === 'lost' ? ` · persi ${BC(b.stake)}` : ` · vincita possibile ${BC(Math.floor(b.stake * b.quota / 100))}`;
    const note = b.written_off > 0 ? `<br><small class="mute">Dopo una correzione del risultato ${BC(b.written_off)} non sono stati recuperati perché già spesi.</small>` : '';
    return `<div class="row2"><div class="g"><b>${esc(b.challenger_name)}</b> <span class="mute">vs</span> <b>${esc(b.opponent_name)}</b><small>${esc(b.format)} · ${KN[b.kind] || ''} · ${when(b.created_at)}</small>
      Su <b>${esc(b.pick_name)}</b> · ${BC(b.stake)} a quota ${qt(b.quota)}${res}${note}</div><span class="tag ${st[1]}">${st[0]}</span></div>`;
  };

  /* ---------- solo admin: scommesse da pagare e pagate, con la revoca ---------- */
  const admMeta = b => `<small>${esc(b.challenger_name)} vs ${esc(b.opponent_name)} · ${esc(b.format)} · ${KN[b.kind] || ''} · sfida ${MS[b.match_status] || esc(b.match_status)} · ${when(b.created_at)}</small>`;
  const admOpen = b => `<div class="row2"><div class="g"><b>${esc(b.user_name)}</b> ha puntato <b>${BC(b.stake)}</b> su <b>${esc(b.pick_name)}</b> a quota ${qt(b.quota)}${admMeta(b)}Vincita possibile <b>${BC(Math.floor(b.stake * b.quota / 100))}</b></div><span class="tag">Da pagare</span></div>`;
  const admPaid = b => {
    const st = { won: ['Vinta', 'pos'], lost: ['Persa', 'neg'], refunded: ['Restituita', ''], revoked: ['Revocata', 'neg'] }[b.status] || [b.status, ''];
    let info, btns = '';
    if (b.status === 'revoked') info = `Pagamento revocato${b.revoked_at ? ' il ' + when(b.revoked_at) : ''}${b.revoke_reason ? ': «' + esc(b.revoke_reason) + '»' : ''}${b.returned > 0 ? ` · restano ${BC(b.returned)} (puntata)` : ''}`;
    else if (b.status === 'won') info = `${BC(b.stake)} → pagati <b class="pos">${BC(b.returned)}</b>`;
    else if (b.status === 'refunded') info = `puntata restituita ${BC(b.returned)}`;
    else info = `puntati ${BC(b.stake)}, nessun pagamento`;
    if (b.status === 'won' || b.status === 'refunded') {
      const mk = (mode, label, amt) => `<button class="btn ghost sm" data-act="betRevoke" data-id="${b.id}" data-mode="${mode}" data-amt="${amt}" data-who="${esc(b.user_name)}">${label}</button>`;
      btns = `<div class="row" style="gap:8px;margin-top:8px;flex-wrap:wrap">${mk('full', b.status === 'won' ? 'Revoca vincita' : 'Revoca rimborso', b.returned)}${b.status === 'won' && b.returned > b.stake ? mk('refund', 'Annulla e rimborsa puntata', b.returned - b.stake) : ''}</div><small class="mute">Saldo attuale di ${esc(b.user_name)}: ${BC(b.balance)}</small>`;
    }
    const wo = b.written_off > 0 ? `<br><small class="mute">${BC(b.written_off)} non recuperati perché già spesi.</small>` : '';
    return `<div class="row2"><div class="g"><b>${esc(b.user_name)}</b> · su <b>${esc(b.pick_name)}</b> a quota ${qt(b.quota)}${admMeta(b)}${info}${wo}${btns}</div><span class="tag ${st[1]}">${st[0]}</span></div>`;
  };
  const admBox = al => `<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Solo admin: scommesse da pagare (${al.open_count})</h2>${al.open.map(admOpen).join('') || '<p class="mute" style="margin:0">Nessuna scommessa in attesa di pagamento.</p>'}${al.open_count > al.open.length ? `<p class="mute">Mostrate le prime ${al.open.length}.</p>` : ''}</div>
${BM.fold('bets-adm-paid', 'Solo admin: scommesse pagate', (al.settled.map(admPaid).join('') || '<p class="mute" style="margin:0">Ancora nessuna scommessa liquidata.</p>') + (al.settled_count > al.settled.length ? `<p class="mute">Mostrate le ultime ${al.settled.length}.</p>` : ''), { style: 'margin-top:14px', count: al.settled_count })}`;

  R.bets = async () => {
    if (!ladderOn()) return off(['Ladder non attiva', 'Le scommesse riguardano le sfide Ladder, che al momento sono spente.']);
    if (!ready()) return off(['Scommesse non ancora disponibili', 'Manca la migrazione del database «scommesse»: un amministratore deve eseguire <code>black-market-scommesse.sql</code> in Supabase.']);
    if (S().bet_enabled != 1) return off(['Scommesse spente', 'Un amministratore le ha messe in pausa. Le scommesse già fatte vengono comunque liquidate.']);
    shell(head + '<p class="mute" role="status">Caricamento…</p>', 'bets');
    try {
      try { await rpc('bet_sync', {}) } catch (e) { /* rete di sicurezza: non blocca la pagina */ }
      const isAdm = BM.me.role === 'admin';
      const [ms, my, adm, al] = await Promise.all([rpc('bet_markets', {}), rpc('bet_mine', {}), isAdm ? rpc('bet_admin_stats', {}).catch(() => null) : null, isAdm ? rpc('bet_admin_list', {}).catch(() => null) : null]);
      const open = my.filter(b => b.status === 'open'), done = my.filter(b => b.status !== 'open');
      const won = done.filter(b => b.status === 'won').reduce((t, b) => t + b.returned - b.stake, 0), lost = done.filter(b => b.status === 'lost').reduce((t, b) => t - b.stake, 0);
      shell(`${head}
<div class="stats" style="margin-top:14px"><div class="stat"><b>${BC(BM.wallet)}</b><span>Il tuo saldo</span></div><div class="stat"><b>${open.length}</b><span>Scommesse in corso (${BC(open.reduce((t, b) => t + b.stake, 0))} puntati)</span></div><div class="stat"><b>${(won + lost) >= 0 ? '+' : '−'}${num(Math.abs(won + lost))}</b><span>Risultato delle scommesse chiuse</span></div></div>
${how()}
<div class="box" style="margin-top:14px"><div class="row" style="justify-content:space-between;align-items:center"><h2 style="margin:0">Sfide su cui puntare (${ms.length})</h2><button class="btn ghost sm" data-act="betReload">Aggiorna</button></div>
${ms.map(market).join('') || '<p class="mute" style="margin:10px 0 0">Nessuna sfida aperta al momento. Quando qualcuno lancia una sfida in Ladder compare qui.</p>'}</div>
<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Le mie scommesse (${my.length})</h2>${my.map(mine).join('') || '<p class="mute" style="margin:0">Non hai ancora scommesso.</p>'}</div>
${adm ? `<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Solo admin: quanto circola</h2><p style="margin:0">${adm.bets_total} scommesse · puntati in totale ${BC(adm.staked_total)} · restituiti ${BC(adm.returned_total)} · <b>risultato per la casa ${BC(adm.house_net)}</b> (le liquidate) · aperte ${adm.open_count} (${BC(adm.open_stake)} bloccati)${adm.revoked_count ? ` · pagamenti revocati ${adm.revoked_count}` : ''}${adm.written_off ? ` · non recuperati ${BC(adm.written_off)}` : ''}.<br><small class="mute">I BC vinti sono creati dal sistema: un risultato per la casa molto negativo significa quote troppo generose; si alza «bet_margin_pct» in Admin → Impostazioni.</small></p></div>` : ''}
${al ? admBox(al) : ''}`, 'bets');
    } catch (er) {
      shell(head + `<div class="err" role="alert">${missing(er) ? 'Manca la migrazione «scommesse»: un amministratore deve eseguire black-market-scommesse.sql in Supabase.' : 'Qualcosa è andato storto: ' + esc(er.message)}</div>`, 'bets');
    }
  };

  /* ---------- azioni ---------- */
  const panel = id => document.querySelector(`.bet-panel[data-m="${id}"]`);
  const preview = p => {
    const st = parseInt(p.querySelector('.bet-stake').value, 10), qd = +p.dataset.q, w = p.querySelector('.bet-win');
    w.innerHTML = Number.isFinite(st) && st > 0 ? `Se vince ricevi <b>${BC(Math.floor(st * qd / 100))}</b>` : '';
  };
  document.addEventListener('input', e => { if (e.target.classList && e.target.classList.contains('bet-stake')) { const p = e.target.closest('.bet-panel'); if (p) preview(p) } });
  const done = async msg => { await BM.core(); toast(msg); BM.route() };
  const ACT = {
    betPick: async el => {
      const p = panel(el.dataset.m); if (!p) return;
      p.dataset.p = el.dataset.p; p.dataset.q = el.dataset.q; p.dataset.n = el.dataset.n;
      p.querySelector('.bet-who').textContent = el.dataset.n + ' (quota ' + qt(+el.dataset.q) + ')';
      p.hidden = false; preview(p); p.querySelector('.bet-stake').focus();
    },
    betCancel: async el => { const p = panel(el.dataset.m); if (p) p.hidden = true },
    betReload: async () => { BM.route() },
    betRevoke: async el => {
      const refund = el.dataset.mode === 'refund', amt = +el.dataset.amt, who = el.dataset.who;
      const why = prompt(refund ? `Annulla la vincita di ${who} (la puntata resta restituita). Motivazione (min. 5 caratteri):` : `Revoca il pagamento a ${who}: i BC vengono ripresi dal suo wallet. Motivazione (min. 5 caratteri):`);
      if (why === null) return;
      if (why.trim().length < 5) throw new Error('Motivazione obbligatoria (almeno 5 caratteri).');
      if (!confirm(`Riprendere ${num(amt)} BC da ${who}?\nSe ne ha già speso una parte, si riprende solo ciò che c'è (il resto resta scritto come «non recuperato»). L'operazione non si ripete e la scommessa non verrà più pagata.`)) return;
      const r = await rpc('bet_admin_revoke', { p_bet: el.dataset.id, p_reason: why.trim(), p_refund_stake: refund });
      await done(r.not_recovered > 0 ? `Revocato: ripresi ${num(r.recovered)} BC, ${num(r.not_recovered)} BC non recuperabili (già spesi).` : `Revocato: ripresi ${num(r.recovered)} BC.`);
    },
    betGo: async el => {
      const p = panel(el.dataset.m); if (!p || !p.dataset.p) throw new Error('Scegli prima su chi puntare.');
      const st = parseInt(p.querySelector('.bet-stake').value, 10);
      if (!Number.isFinite(st) || st < minS() || st > maxS()) throw new Error(`La puntata deve essere tra ${minS()} e ${maxS()} BC.`);
      if (st > BM.wallet) throw new Error('Non hai abbastanza BC.');
      const quota = +p.dataset.q;
      if (!confirm(`Puntare ${st} BC su ${p.dataset.n} a quota ${qt(quota)}?\nSe vince ricevi ${Math.floor(st * quota / 100)} BC, altrimenti perdi la puntata.`)) return;
      const k = [el.dataset.m, p.dataset.p, st].join('|');
      let r;
      try { r = await rpc('place_bet', { p_match: el.dataset.m, p_pick: p.dataset.p, p_stake: st, p_min_quota: quota, p_request_id: reqId(k) }) }
      catch (er) { if (!/rete|network|fetch/i.test(er.message || '')) reqIds.delete(k); throw er }
      reqIds.delete(k);
      await done(r.already ? 'Scommessa già registrata.' : `Scommessa piazzata: ${st} BC a quota ${qt(r.quota)}.`);
    }
  };
  const prevAct = BM.act;
  BM.act = async (a, el) => {
    if (ACT[a]) { try { await ACT[a](el) } catch (er) { toast(er.message, 1) } return true }
    return prevAct ? prevAct(a, el) : false;
  };
};
