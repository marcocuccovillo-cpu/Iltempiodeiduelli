/* =====================================================================
   BLACK MARKET — EVENTI «TORNEO SVIZZERO»: lobby, turni, risultati dei giocatori, durata e annullamento degli eventi
   Si aggancia alle pagine #/events e #/e/<evento> di black-market.html. Richiede la migrazione black-market-eventi-svizzera.sql:
   senza, queste funzioni restituiscono false e la pagina funziona esattamente come prima.
   Il database decide tutto (accoppiamenti, punti, chi può fare cosa): qui si mostra e si chiede, niente si calcola dal browser.
   ===================================================================== */
window.BM_SWISS = function (BM) {
  'use strict';
  const { R, shell, q, rpc, toast, esc, route } = BM;
  const $app = document.getElementById('app');
  const sbx = () => BM.sb;
  let ready = null;
  const probe = async () => {
    if (ready !== null) return ready;
    try {
      const r = await q(sbx().from('events').select('*').limit(1));
      if (r.length) ready = 'event_format' in r[0];
      else { await q(sbx().from('events').select('event_format,event_status').limit(1)); ready = true; }
    } catch (e) { ready = false; }
    return ready;
  };
  const fd = d => d ? new Date(d + 'T12:00:00').toLocaleDateString('it-IT', { day: '2-digit', month: 'short', year: 'numeric' }) : '';
  const nlink = (id, nick) => `<a href="#/p/${esc(id)}">${esc(nick)}</a>`;
  const ST = { open: 'Iscrizioni aperte', running: 'In corso', finished: 'Concluso', cancelled: 'Annullato' };

  if (!document.getElementById('sw-style')) {
    const st = document.createElement('style');
    st.id = 'sw-style';
    st.textContent = `
.sw-badges{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0 0}
.sw-st{display:inline-block;font-size:.72rem;font-weight:700;letter-spacing:.06em;text-transform:uppercase;padding:2px 9px;border-radius:99px;border:1px solid var(--line);color:var(--mu)}
.sw-st.open{color:#7fe0a7;border-color:#7fe0a7}.sw-st.running{color:var(--gold);border-color:var(--gold)}.sw-st.finished{color:#9bc1ff;border-color:#9bc1ff}.sw-st.cancelled{color:#ff8f9d;border-color:#ff8f9d}
.sw-ban{padding:12px 14px;border-radius:12px;border:1px solid var(--gold);background:rgba(212,168,67,.1);margin-top:14px}
.sw-ban.bad{border-color:#ff8f9d;background:rgba(255,84,104,.1)}.sw-ban.good{border-color:#7fe0a7;background:rgba(74,222,155,.08)}
.sw-ban b{color:var(--tx)}.sw-ban p{margin:4px 0 0}
.sw-mine{margin-top:14px;padding:14px;border:2px solid var(--gold);border-radius:14px;background:rgba(212,168,67,.08)}
.sw-mine h2{margin:0 0 6px}.sw-vs{font:600 1.15rem var(--disp);overflow-wrap:anywhere}
.sw-act{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}.sw-act .btn{min-height:46px}
.sw-pl{display:flex;flex-wrap:wrap;gap:8px;margin:0;padding:0;list-style:none}
.sw-pl li{display:flex;align-items:center;gap:6px;padding:6px 10px;border:1px solid var(--line);border-radius:99px;background:var(--raise)}
.sw-pl li.me{border-color:var(--gold)}.sw-pl li a{color:var(--tx);text-decoration:none;font-weight:700}
.sw-pl li button{background:none;border:0;color:#ff8f9d;font-size:1rem;cursor:pointer;min-width:32px;min-height:32px}
.sw-tbl{width:100%;border-collapse:collapse;font-size:.92rem}.sw-tbl th{color:var(--mu);font-weight:600;text-align:right;padding:6px 6px;border-bottom:1px solid var(--line);white-space:nowrap}
.sw-tbl td{white-space:nowrap;padding:8px 6px;border-top:1px solid var(--line);text-align:right;font-variant-numeric:tabular-nums}.sw-tbl th:nth-child(2),.sw-tbl td:nth-child(2){text-align:left;width:100%;white-space:normal}
.sw-tbl td:first-child,.sw-tbl th:first-child{text-align:center}.sw-tbl tr.me td{background:rgba(212,168,67,.08)}.sw-tbl tr.out td{opacity:.5}.sw-tbl td b{color:var(--gold)}
.sw-tbl a{color:var(--tx);text-decoration:none;font-weight:700}
.sw-m{display:flex;flex-wrap:wrap;align-items:center;gap:8px 12px;padding:10px 0;border-top:1px solid var(--line)}.sw-m:first-of-type{border-top:0}
.sw-m .g{flex:1 1 200px;min-width:0;overflow-wrap:anywhere}.sw-m small{display:block;color:var(--mu)}.sw-m .w{color:var(--gold);font-weight:700}
.sw-f{display:grid;gap:10px;margin-top:10px}.sw-f .r{display:flex;flex-wrap:wrap;gap:8px;align-items:center}.sw-f input[type=number]{max-width:110px}
.sw-f label{display:flex;align-items:center;gap:8px;cursor:pointer}.sw-f label input{width:auto;min-width:22px;min-height:22px}
@media(max-width:520px){.sw-tbl{font-size:.85rem}.sw-tbl th,.sw-tbl td{padding:7px 4px}}
`;
    document.head.appendChild(st);
  }

  /* ---------- elenco eventi (con creazione) ---------- */
  const evBadge = e => {
    const f = e.event_format === 'swiss', s = e.event_status || 'open';
    const o = [];
    if (f) o.push('<span class="tag g">Svizzero</span>');
    if (s === 'cancelled') o.push('<span class="sw-st cancelled">Annullato</span>');
    else if (f && s === 'running') o.push(`<span class="sw-st running">Turno ${e.current_round} di ${e.rounds_planned}</span>`);
    else if (f && s === 'finished') o.push('<span class="sw-st finished">Concluso</span>');
    else if (f && s === 'open') o.push('<span class="sw-st open">Iscrizioni aperte</span>');
    return o.join(' ');
  };
  const dur = e => e.duration_days ? ` · ${e.duration_days} ${e.duration_days === 1 ? 'giorno' : 'giorni'} (fino al ${fd(new Date(new Date(e.event_date + 'T12:00:00').getTime() + (e.duration_days - 1) * 86400000).toISOString().slice(0, 10))})` : '';

  BM.swissEvents = async () => {
    if (!(await probe())) return false;
    const [ev, lev] = await Promise.all([
      q(sbx().from('events').select('*').neq('source', 'ladder').order('event_date', { ascending: false }).limit(60)),
      q(sbx().from('events').select('*').eq('source', 'ladder').order('event_date', { ascending: false }).limit(10))]);
    const me = BM.me, org = me.role == 'organizer' || me.role == 'admin';
    const list = [...ev.filter(e => e.event_status !== 'cancelled'), ...ev.filter(e => e.event_status === 'cancelled')];
    shell(`<h1 class="t">Eventi e <em>match WPA</em></h1><p class="sub">I match verificati dall’organizzatore e le vittorie della Ladder confermate dai due giocatori fanno incassare le taglie <b>in automatico</b>: il vincitore le riceve nel momento in cui il match è verificato.</p>
 ${org ? `<form id="ne" class="box" style="margin-top:18px"><h2>Nuovo evento</h2><div class="sw-f">
   <div class="r"><input id="en" placeholder="Nome evento" required minlength="3" maxlength="80" style="flex:1;min-width:200px" aria-label="Nome evento"><input id="ed" type="date" value="${new Date().toISOString().slice(0, 10)}" style="max-width:170px" aria-label="Data di inizio"></div>
   <div class="r"><label for="edu" style="gap:6px">Durata <input id="edu" type="number" min="1" max="90" value="7" required style="max-width:90px"> giorni</label><span class="mute" style="font-size:.88rem">contando il giorno di inizio</span></div>
   <label><input id="esw" type="checkbox" checked> <span><b>Torneo svizzero con lobby</b><small class="mute" style="display:block">I giocatori si iscrivono da soli, tu avvii il torneo e generi i turni; i risultati li registrano i giocatori. Senza la spunta l’evento resta com’era: aggiungi i match a mano.</small></span></label>
   <div class="r"><button class="btn gold">Crea evento</button></div></div></form>` : ''}
 <div class="box" style="margin-top:14px">${list.map(e => `<div class="row2"><div class="g"><a href="#/e/${e.id}">${esc(e.name)}</a><small>${fd(e.event_date)}${dur(e)} · organizzato da ${esc(BM.pn(e.created_by))}</small>${evBadge(e) ? `<div class="sw-badges">${evBadge(e)}</div>` : ''}</div></div>`).join('') || '<p class="mute">Nessun evento registrato.</p>'}</div>
 ${lev.length ? `<div class="box" style="margin-top:14px"><h2>Match della Ladder (ufficiali)</h2><p class="mute" style="font-size:.9rem;margin-top:0">Le vittorie in Ladder confermate diventano match WPA nell’evento del giorno.</p>${lev.map(e => `<div class="row2"><div class="g"><a href="#/e/${e.id}">${esc(e.name)}</a><small>${e.event_date} · automatico</small></div></div>`).join('')}</div>` : ''}`, 'events');
    const f = document.getElementById('ne');
    if (f) f.onsubmit = async x => {
      x.preventDefault();
      try {
        const sw = document.getElementById('esw').checked;
        const id = await rpc('create_event_ex', { p_name: document.getElementById('en').value, p_date: document.getElementById('ed').value, p_days: parseInt(document.getElementById('edu').value, 10) || null, p_swiss: sw });
        location.hash = '#/e/' + id;
      } catch (er) { toast(er.message, 1); }
    };
    return true;
  };

  /* ---------- pagina di un torneo svizzero ---------- */
  let cur = null, poll = null, busy = false, EL = null;
  const getEl = async id => { try { return await rpc('swiss_elo', { p_event: id }); } catch (e) { return null; } };   // senza la migrazione 033 non c'è: la pagina resta com'era
  const sg = n => (n > 0 ? '+' : n < 0 ? '−' : '±') + Math.abs(n);
  const eloOf = id => { const p = EL && EL.players.find(x => x.user_id === id); return p ? p.elo : (EL ? 1000 : null); };
  const matchLine = (m, s, org) => {
    const meId = s.me.id, mine = m.a === meId || m.b === meId;
    let st = '';
    if (m.status === 'verified') {
      const x = EL && EL.matches.find(y => y.match_id === m.id);
      st = `<small>Concluso · vince <span class="w">${esc(m.winner === m.a ? m.a_nick : m.b_nick)}</span>${x ? ` · Elo ${esc(m.a_nick)} ${sg(x.a_delta)}, ${esc(m.b_nick)} ${sg(x.b_delta)}` : ''}</small>`;
    }
    else if (m.disputed) st = '<small style="color:#ff8f9d">Risultato contestato: decide l’organizzatore</small>';
    else if (m.reported_by) st = `<small>${esc(m.reported_winner === m.a ? m.a_nick : m.b_nick)} indicato come vincitore · in attesa di conferma</small>`;
    else st = '<small>In attesa del risultato</small>';
    const dec = org && m.status === 'pending' && s.event.status === 'running'
      ? `<div class="sw-act" style="margin:0"><button class="btn sm ghost" data-act="sw_dec" data-m="${m.id}" data-w="${m.a}" data-n="${esc(m.a_nick)}">${esc(m.a_nick)} vince</button><button class="btn sm ghost" data-act="sw_dec" data-m="${m.id}" data-w="${m.b}" data-n="${esc(m.b_nick)}">${esc(m.b_nick)} vince</button></div>` : '';
    return `<div class="sw-m"><div class="g">${nlink(m.a, m.a_nick)} <span class="mute">vs</span> ${nlink(m.b, m.b_nick)}${mine ? ' <span class="tag g">tuo</span>' : ''}${st}</div>${dec}</div>`;
  };
  const myCard = (s) => {
    const e = s.event, meId = s.me.id;
    if (e.status !== 'running' || !s.rounds.length || s.me.dropped) return '';
    const r = s.rounds[0];
    const m = r.matches.find(x => x.status === 'pending' && (x.a === meId || x.b === meId));
    if (!m) {
      const b = r.byes.find(x => x.user_id === meId);
      if (b) return `<div class="sw-mine"><h2>Turno ${r.round}</h2><p style="margin:0">${b.kind === 'bye' ? '<b>Riposi in questo turno</b>: ti vengono assegnati 3 punti, non devi giocare.' : '<b>Vittoria a tavolino</b>: il tuo avversario si è ritirato, 3 punti per te.'}</p></div>`;
      return '';
    }
    const opp = m.a === meId ? m.b_nick : m.a_nick, oppId = m.a === meId ? m.b : m.a, wn = m.reported_winner === m.a ? m.a_nick : m.b_nick;
    let body;
    if (m.disputed) body = `<p style="margin:6px 0 0"><b>Il risultato è contestato.</b> Lo decide l’organizzatore: attendi.</p>`;
    else if (!m.reported_by) body = `<p style="margin:6px 0 0">Quando avete finito, indica chi ha vinto. Il risultato diventa valido quando lo conferma anche ${esc(opp)}.</p>
      <div class="sw-act"><button class="btn gold" data-act="sw_rep" data-m="${m.id}" data-w="${meId}">Ho vinto io</button><button class="btn ghost" data-act="sw_rep" data-m="${m.id}" data-w="${oppId}">Ha vinto ${esc(opp)}</button></div>`;
    else if (m.reported_by === meId) body = `<p style="margin:6px 0 0">Hai indicato che ha vinto <b>${esc(wn)}</b>. In attesa che ${esc(opp)} confermi.</p>
      <div class="sw-act"><button class="btn ghost sm" data-act="sw_rep" data-m="${m.id}" data-w="${m.reported_winner === meId ? oppId : meId}">Correggi: ha vinto ${esc(m.reported_winner === meId ? opp : 'io')}</button></div>`;
    else body = `<p style="margin:6px 0 0">${esc(opp)} indica che ha vinto <b>${esc(wn)}</b>. È corretto?</p>
      <div class="sw-act"><button class="btn gold" data-act="sw_rep" data-m="${m.id}" data-w="${m.reported_winner}">Confermo</button><button class="btn ghost" data-act="sw_disp" data-m="${m.id}">Non è corretto</button></div>`;
    return `<div class="sw-mine"><h2>Il tuo match · turno ${r.round}</h2><div class="sw-vs">${esc(BM.pn(meId))} <span class="mute">vs</span> ${nlink(oppId, opp)}</div>${body}</div>`;
  };
  const standings = s => {
    const meId = s.me.id, p = s.players;
    if (!p.length) return '<p class="mute">Nessun iscritto.</p>';
    return `<div style="overflow-x:auto"><table class="sw-tbl"><thead><tr><th>#</th><th>Giocatore</th><th title="Vittorie – sconfitte">V–S</th><th>Punti</th><th title="Somma dei punti degli avversari: spareggio">Spar.</th></tr></thead><tbody>${p.map(x =>
      `<tr class="${x.user_id === meId ? 'me' : ''} ${x.dropped ? 'out' : ''}"><td>${x.rank}</td><td>${nlink(x.user_id, x.nickname)}${x.dropped ? ' <span class="mute">(ritirato)</span>' : ''}${eloOf(x.user_id) != null ? `<small class="mute" style="display:block;font-size:.76rem">Elo ${eloOf(x.user_id)}</small>` : ''}${x.byes ? ` <span class="mute" title="riposi o vittorie a tavolino">+${x.byes}</span>` : ''}</td><td>${x.wins}–${x.losses}</td><td><b>${x.points}</b></td><td>${x.omw}</td></tr>`).join('')}</tbody></table></div>
      <p class="mute" style="font-size:.84rem;margin:8px 0 0">3 punti a vittoria (anche per il riposo o la vittoria a tavolino), 0 a sconfitta. A parità conta la somma dei punti degli avversari affrontati.${EL && EL.counts ? ` I match verificati contano anche per l’<b>Elo ${esc(EL.format)}</b> della Ladder.` : ''}</p>`;
  };
  const view = s => {
    const e = s.event, can = s.can, org = s.is_organizer, running = e.status === 'running', meId = s.me.id;
    const head = `<p><a href="#/events">← Eventi</a></p><h1 class="t" style="font-size:2.2rem">${esc(e.name)}</h1>
      <p class="sub">${fd(e.date)} · organizzatore: ${nlink(e.organizer_id, e.organizer || '?')}${e.duration_days ? ` · durata ${e.duration_days} ${e.duration_days === 1 ? 'giorno' : 'giorni'} (fino al ${fd(e.ends_on)})` : ''}</p>
      <div class="sw-badges"><span class="tag g">Torneo svizzero</span><span class="sw-st ${e.status}">${ST[e.status]}${running ? ` · turno ${e.current_round} di ${e.rounds_planned}` : ''}</span></div>`;
    let ban = '';
    if (e.status === 'cancelled') ban = `<div class="sw-ban bad"><b>Evento annullato</b>${e.cancel_reason ? `<p>Motivo: ${esc(e.cancel_reason)}</p>` : ''}<p class="mute">I match già verificati restano validi; le iscrizioni sono state tolte se non si era giocato nulla.</p></div>`;
    else if (e.status === 'finished') ban = `<div class="sw-ban good"><b>Torneo concluso</b>${s.players[0] ? `<p>Primo in classifica: <b>${esc(s.players[0].nickname)}</b> con ${s.players[0].points} punti.</p>` : ''}</div>`;
    else if (e.expired) ban = `<div class="sw-ban bad"><b>La durata dell’evento è terminata</b><p>Non si possono creare altri turni: i risultati in corso si registrano ancora e l’organizzatore può concludere il torneo.</p></div>`;
    else if (e.status === 'open') ban = `<div class="sw-ban"><b>Iscrizioni aperte</b><p>Iscritti: <b>${s.n_active}</b>. Il torneo parte quando l’organizzatore lo avvia. Con ${s.n_active} giocatori i turni saranno ${s.auto_rounds} (a meno che l’organizzatore ne scelga un altro numero).</p></div>`;
    const eloNote = EL && EL.counts && e.status !== 'cancelled' ? `<p class="mute" style="margin:8px 0 0;font-size:.9rem">Ogni match verificato di questo torneo modifica anche il tuo <b>Elo ${esc(EL.format)}</b> della Ladder.</p>` : '';

    const join = can.join ? `<div class="sw-act"><button class="btn gold" data-act="sw_join" data-e="${e.id}">Iscriviti al torneo</button></div>` : '';
    const leave = can.leave ? `<div class="sw-act"><button class="btn ghost sm" data-act="sw_leave" data-e="${e.id}">${e.status === 'open' ? 'Annulla la mia iscrizione' : 'Ritirati dal torneo'}</button></div>` : '';
    const lobby = e.status === 'open' || e.status === 'cancelled' && !s.rounds.length
      ? `<div class="box" style="margin-top:14px"><h2>Iscritti (${s.n_active})</h2>${s.players.length ? `<ul class="sw-pl">${s.players.map(x => `<li class="${x.user_id === meId ? 'me' : ''}">${nlink(x.user_id, x.nickname)}${org && e.status === 'open' ? `<button data-act="sw_kick" data-e="${e.id}" data-u="${x.user_id}" data-n="${esc(x.nickname)}" aria-label="Togli ${esc(x.nickname)}">✕</button>` : ''}</li>`).join('')}</ul>` : '<p class="mute">Nessun iscritto per ora.</p>'}${join}${leave}</div>` : '';

    let orgBox = '';
    if (org && (e.status === 'open' || running)) {
      const why = running && s.pending > 0 ? `Mancano ancora <b>${s.pending}</b> ${s.pending === 1 ? 'risultato' : 'risultati'} nel turno ${e.current_round}: i giocatori devono registrarli, oppure decidili tu qui sotto.`
        : running && e.current_round >= e.rounds_planned && !e.expired ? `Tutti i ${e.rounds_planned} turni previsti sono stati giocati: concludi il torneo oppure aumenta il numero di turni.` : '';
      orgBox = `<div class="box" style="margin-top:14px"><h2>Pannello organizzatore</h2><div class="sw-f">
        ${e.status === 'open' ? `<div class="r"><label for="swr" style="gap:6px">Turni <input id="swr" type="number" min="1" max="${s.max_rounds}" placeholder="${s.auto_rounds}" style="max-width:90px"></label><span class="mute" style="font-size:.88rem">vuoto = automatico (${s.auto_rounds} con ${s.n_active} iscritti); massimo ${s.max_rounds}</span></div>
          <div class="r"><button class="btn gold" data-act="sw_start" data-e="${e.id}" ${can.start ? '' : 'disabled'}>Avvia il torneo</button>${can.start ? '' : `<span class="mute">${s.n_active < 2 ? 'Servono almeno 2 iscritti.' : 'La durata dell’evento è terminata.'}</span>`}</div>`
        : `${why ? `<p style="margin:0">${why}</p>` : ''}
          <div class="r"><button class="btn gold" data-act="sw_next" data-e="${e.id}" ${can.next ? '' : 'disabled'}>Genera il turno ${Math.min(e.current_round + 1, 99)}</button><button class="btn ghost" data-act="sw_finish" data-e="${e.id}" ${can.finish ? '' : 'disabled'}>Concludi il torneo</button></div>
          <div class="r"><label for="swr" style="gap:6px">Turni previsti <input id="swr" type="number" min="${Math.max(1, e.current_round)}" max="${s.max_rounds}" value="${e.rounds_planned}" style="max-width:90px"></label><button class="btn ghost sm" data-act="sw_rounds" data-e="${e.id}">Cambia</button></div>`}
        </div></div>`;
    }
    const extra = org && (running || e.status === 'finished') ? `<div class="sw-act"><button class="btn ghost sm" data-act="award" data-e="${e.id}">Assegna ricompense partecipazione</button></div>` : '';
    const cancel = can.cancel ? `<div class="box" style="margin-top:14px"><h2>Annulla l’evento</h2><p class="mute" style="margin:0 0 8px;font-size:.92rem">L’evento resta in elenco come «Annullato». I match ancora da giocare vengono tolti; quelli già verificati restano.${EL && EL.counts ? ' L’Elo guadagnato in questo torneo viene tolto.' : ''}</p><button class="btn ghost sm" data-act="sw_cancel" data-e="${e.id}">Annulla evento</button></div>` : '';

    const rounds = s.rounds.map(r => `<div style="margin-top:6px"><h3 style="margin:10px 0 2px;font-size:1rem">Turno ${r.round}${r.round === e.current_round && running ? ' · in corso' : ''}</h3>${r.matches.map(m => matchLine(m, s, org)).join('')}${r.byes.map(b => `<div class="sw-m"><div class="g">${nlink(b.user_id, b.nickname)}<small>${b.kind === 'bye' ? 'Riposa (3 punti)' : 'Vittoria a tavolino (avversario ritirato, 3 punti)'}</small></div></div>`).join('')}</div>`).join('');
    const how = BM.fold ? BM.fold('sw_how', 'Come funziona', `<ul style="margin:0;padding-left:1.2em;line-height:1.5"><li>I giocatori si <b>iscrivono da soli</b> finché il torneo non parte. Solo l’<b>organizzatore</b> lo avvia e genera i turni.</li><li>Ogni turno sfidi un avversario con un punteggio simile; <b>nessuno incontra due volte la stessa persona</b> (se si può evitare). Con un numero dispari di giocatori uno riposa e prende comunque 3 punti.</li><li>A fine partita <b>uno dei due indica chi ha vinto e l’altro conferma</b>. Se non siete d’accordo decide l’organizzatore.</li><li>L’organizzatore genera il turno dopo solo quando <b>tutti i risultati</b> del turno sono registrati.</li><li>Se ti ritiri non vieni più accoppiato e il tuo avversario in corso vince a tavolino.</li></ul>`) : '';
    shell(`${head}${eloNote}${ban}${myCard(s)}${lobby}${orgBox}
      ${e.status !== 'open' && s.players.length ? `<div class="box" style="margin-top:14px"><h2>Classifica</h2>${standings(s)}${leave}</div>` : ''}
      ${s.rounds.length ? `<div class="box" style="margin-top:14px"><h2>Turni e risultati</h2>${rounds}</div>` : ''}
      ${extra}${cancel}<div style="margin-top:14px">${how}</div>`, 'events');
  };
  const draw = async (id) => {
    const [s, el] = await Promise.all([rpc('swiss_state', { p_event: id }), getEl(id)]);
    EL = el;
    cur = { id, key: JSON.stringify([s, el]) };
    view(s);
  };
  const startPoll = id => {
    clearInterval(poll);
    poll = setInterval(async () => {
      if (location.hash !== '#/e/' + id) { clearInterval(poll); poll = null; return; }
      if (document.hidden || busy) return;
      const ae = document.activeElement;
      if (ae && /^(INPUT|TEXTAREA|SELECT)$/.test(ae.tagName)) return;
      try {
        const [s, el] = await Promise.all([rpc('swiss_state', { p_event: id }), getEl(id)]);
        const key = JSON.stringify([s, el]);
        if (cur && cur.id === id && cur.key !== key) { cur.key = key; EL = el; view(s); }
      } catch (e) { /* si riprova al giro dopo */ }
    }, 10000);
  };
  BM.swissEvent = async id => {
    if (!(await probe())) return false;
    const evs = await q(sbx().from('events').select('event_format').eq('id', id));
    if (!evs[0] || evs[0].event_format !== 'swiss') return false;
    await draw(id);
    startPoll(id);
    return true;
  };

  /* ---------- eventi «a mano»: durata e annullamento sulla pagina di sempre ---------- */
  BM.swissExtra = e => {
    if (!ready) return;
    const sub = $app.querySelector('.sub');
    if (!sub) return;
    const org = BM.me && (BM.me.role === 'admin' || e.created_by === BM.me.id) && e.source !== 'ladder';
    if (e.duration_days) sub.insertAdjacentHTML('beforeend', ` · durata ${e.duration_days} ${e.duration_days === 1 ? 'giorno' : 'giorni'} (fino al ${fd(new Date(new Date(e.event_date + 'T12:00:00').getTime() + (e.duration_days - 1) * 86400000).toISOString().slice(0, 10))})`);
    if (e.event_status === 'cancelled') {
      sub.insertAdjacentHTML('afterend', `<div class="sw-ban bad"><b>Evento annullato</b>${e.cancel_reason ? `<p>Motivo: ${esc(e.cancel_reason)}</p>` : ''}</div>`);
      const f = document.getElementById('nm');
      if (f) { const p = f.nextElementSibling; if (p && p.tagName === 'P') p.remove(); f.remove(); }
    } else if (org) {
      sub.insertAdjacentHTML('afterend', `<div class="sw-act"><button class="btn ghost sm" data-act="sw_cancel" data-e="${e.id}">Annulla evento</button></div>`);
    }
  };

  /* ---------- azioni ---------- */
  const after = async (id) => { busy = false; if (id && location.hash === '#/e/' + id) { await route(); } };
  const ACT = {
    async sw_join(el) { busy = true; try { await rpc('swiss_join', { p_event: el.dataset.e }); toast('Sei iscritto al torneo.'); } finally { await after(el.dataset.e); } },
    async sw_leave(el) {
      if (!confirm('Vuoi davvero uscire dal torneo? Se è già iniziato non potrai rientrare.')) return;
      busy = true; try { await rpc('swiss_leave', { p_event: el.dataset.e }); toast('Hai lasciato il torneo.'); } finally { await after(el.dataset.e); }
    },
    async sw_kick(el) {
      if (!confirm('Togliere ' + el.dataset.n + ' dal torneo?')) return;
      busy = true; try { await rpc('swiss_kick', { p_event: el.dataset.e, p_user: el.dataset.u }); toast('Giocatore tolto.'); } finally { await after(el.dataset.e); }
    },
    async sw_start(el) {
      const v = (document.getElementById('swr') || {}).value, r = v ? parseInt(v, 10) : null;
      if (!confirm('Avviare il torneo? Le iscrizioni si chiudono e il sistema crea il primo turno.')) return;
      busy = true; try { const x = await rpc('swiss_start', { p_event: el.dataset.e, p_rounds: r }); toast(`Torneo avviato: ${x.rounds} turni, primo turno creato.`); } finally { await after(el.dataset.e); }
    },
    async sw_next(el) { busy = true; try { const x = await rpc('swiss_next_round', { p_event: el.dataset.e }); toast(`Turno ${x.round} creato${x.rematches ? ' (con ' + x.rematches + ' rimatch inevitabili)' : ''}.`); } finally { await after(el.dataset.e); } },
    async sw_finish(el) {
      if (!confirm('Concludere il torneo? Non si potranno più creare turni.')) return;
      busy = true; try { await rpc('swiss_finish', { p_event: el.dataset.e }); toast('Torneo concluso.'); } finally { await after(el.dataset.e); }
    },
    async sw_rounds(el) {
      const v = parseInt((document.getElementById('swr') || {}).value, 10);
      busy = true; try { await rpc('swiss_set_rounds', { p_event: el.dataset.e, p_rounds: v }); toast('Turni previsti aggiornati.'); } finally { await after(el.dataset.e); }
    },
    async sw_rep(el) { busy = true; try { const x = await rpc('swiss_report', { p_match: el.dataset.m, p_winner: el.dataset.w }); toast(x.state === 'closed' ? 'Risultato confermato.' : x.state === 'disputed' ? 'Risultati discordanti: decide l’organizzatore.' : 'Risultato indicato: attendi la conferma dell’avversario.'); } finally { busy = false; if (cur) await after(cur.id); } },
    async sw_disp(el) {
      if (!confirm('Contestare il risultato? Lo deciderà l’organizzatore.')) return;
      busy = true; try { await rpc('swiss_dispute', { p_match: el.dataset.m }); toast('Risultato contestato.'); } finally { busy = false; if (cur) await after(cur.id); }
    },
    async sw_dec(el) {
      if (!confirm('Registrare la vittoria di ' + el.dataset.n + '? Non potrà più essere modificata.')) return;
      busy = true; try { await rpc('swiss_decide', { p_match: el.dataset.m, p_winner: el.dataset.w }); toast('Risultato registrato.'); } finally { busy = false; if (cur) await after(cur.id); }
    },
    async sw_cancel(el) {
      const r = prompt('Annullare l’evento?' + (EL && EL.counts && cur && cur.id === el.dataset.e ? ' L’Elo guadagnato in questo torneo verrà tolto.' : '') + ' Scrivi un motivo (facoltativo) e conferma. Premi Annulla per lasciare tutto com’è.');
      if (r === null) return;
      busy = true;
      try {
        const x = await rpc('cancel_event', { p_event: el.dataset.e, p_reason: r.trim() || null });
        toast(`Evento annullato (${x.pending_removed} match da giocare tolti, ${x.verified_kept} verificati restano).`);
      } finally { busy = false; await route(); }
    }
  };
  const prevAct = BM.act;
  BM.act = async (a, el) => {
    if (ACT[a]) { try { await ACT[a](el); } catch (er) { toast(er.message, 1); } return true; }
    return prevAct ? prevAct(a, el) : false;
  };
};
