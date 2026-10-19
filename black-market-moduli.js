/* =====================================================================
   BLACK MARKET — MODULI AGGIUNTIVI: Hall of Fame, Faction Wars, Underground Challenges
   Caricato da black-market.html PRIMA dello script principale. Non tocca Most Wanted,
   taglie, wallet o registro: aggiunge solo nuove pagine (#/hof, #/factions, #/challenges)
   e un blocco nel pannello Admin. Ogni modulo compare solo se l'interruttore è acceso
   (system_settings.module_*), e comunque il database rifiuta le operazioni a modulo spento.
   Richiede la migrazione black-market-moduli.sql.
   ===================================================================== */
window.BM_MODULES = function (BM) {
  'use strict';
  const { R, shell, q, rpc, toast, esc, BC, when, av, pn, ask } = BM;
  const MODS = [['hall_of_fame', 'Hall of Fame', 'hof'], ['faction_wars', 'Faction Wars', 'factions'], ['underground', 'Underground', 'challenges']];
  const on = k => BM.S['module_' + k] == 1;
  const isOrg = () => BM.me && BM.me.role !== 'user';
  const isAdm = () => BM.me && BM.me.role === 'admin';
  const day = d => d ? new Date(d.length === 10 ? d + 'T12:00:00' : d).toLocaleDateString('it-IT', { day: '2-digit', month: 'short', year: 'numeric' }) : 'n/d';
  const num = n => Number(n || 0).toLocaleString('it-IT');
  const pct = (w, l) => (w + l) ? Math.round(100 * w / (w + l)) + '%' : 'n/d';
  const loading = '<p class="mute" role="status">Caricamento…</p>';
  const empty = t => `<p class="mute">${t}</p>`;
  const hl = id => id ? `<a href="#/hof/${id}">${esc(pn(id))}</a>` : 'n/d';
  const tag = (t, c) => `<span class="tag ${c || ''}">${esc(t)}</span>`;
  const store = {
    get: (k, d) => { try { return sessionStorage.getItem(k) || d } catch (e) { return d } },
    set: (k, v) => { try { sessionStorage.setItem(k, v) } catch (e) { } }
  };
  const seg = (key, cur, opts, act) => `<div class="seg" style="margin:18px 0;flex-wrap:wrap">${opts.map(([v, l]) => `<button data-act="${act}" data-k="${key}" data-v="${v}" aria-pressed="${cur === v}">${l}</button>`).join('')}</div>`;
  const off = (name, cur) => shell(`<h1 class="t">${name}</h1><div class="box" style="margin-top:20px"><h2>Modulo non attivo</h2><p>Questa sezione non è al momento disponibile. Un amministratore può attivarla dal pannello Admin.</p><a class="btn ghost" href="#/">Torna alla dashboard</a></div>`, cur);
  const fail = (er, cur) => shell(`<div class="err" role="alert">Qualcosa è andato storto: ${esc(er.message)}</div>`, cur || '');

  /* ---------- navigazione: solo moduli accesi ---------- */
  BM.navItems = () => MODS.filter(m => on(m[0])).map(m => [m[2], m[1]]);

  /* =============================== HALL OF FAME =============================== */
  const REC = { most_wins: ['Più vittorie ufficiali', ''], most_events: ['Più eventi disputati', ''], longest_win_streak: ['Serie di vittorie consecutive più lunga', ''], biggest_claim: ['Riscossione più alta', 'BC'] };
  const MIL = { wins_1: 'Prima vittoria ufficiale', wins_10: '10 vittorie ufficiali', wins_25: '25 vittorie ufficiali', wins_50: '50 vittorie ufficiali', wins_100: '100 vittorie ufficiali', first_claim: 'Prima taglia riscossa' };
  const hofHead = '<h1 class="t">Hall of <em>Fame</em></h1><p class="sub">Archivio dei risultati ufficiali: ogni numero deriva dai match verificati e dalle riscossioni registrate. Se un dato non esiste, non viene mostrato.</p>';

  R.hof = async id => {
    if (!on('hall_of_fame')) return off('Hall of <em>Fame</em>', 'hof');
    shell(hofHead + loading, 'hof');
    try { return id ? await hofPlayer(id) : await hofHome() } catch (er) { fail(er, 'hof') }
  };

  async function hofHome() {
    const tab = store.get('bm.hof.tab', 'rank'), sort = store.get('bm.hof.sort', 'wins');
    const tabs = seg('bm.hof.tab', tab, [['rank', 'Classifica'], ['records', 'Record'], ['events', 'Eventi'], ['rivals', 'Rivalità'], ['claims', 'Riscossioni'], ['seasons', 'Stagioni']], 'store');
    let body = '';
    if (tab === 'rank') {
      const rows = (await q(BM.sb.from('hof_player_stats_v').select('*'))).filter(r => r.wins + r.losses + r.events_participated > 0);
      const key = { wins: r => r.wins, rate: r => (r.wins + r.losses ? r.wins / (r.wins + r.losses) : -1), events: r => r.events_participated, claims: r => r.bounty_payout_total }[sort] || (r => r.wins);
      rows.sort((a, b) => key(b) - key(a) || b.wins - a.wins || a.nickname.localeCompare(b.nickname));
      body = seg('bm.hof.sort', sort, [['wins', 'Vittorie'], ['rate', '% vittorie'], ['events', 'Eventi'], ['claims', 'BC riscossi']], 'store') +
        `<div class="box">${rows.map((r, i) => `<div class="row2"><span class="rank">${i + 1}</span>${av({ nickname: r.nickname, avatar: r.avatar })}<div class="g"><a href="#/hof/${r.player_id}">${esc(r.nickname)}</a><small>${r.wins}V · ${r.losses}S · ${pct(r.wins, r.losses)} vittorie · ${r.events_participated} eventi${r.bounty_claims ? ' · ' + r.bounty_claims + (r.bounty_claims == 1 ? ' taglia riscossa' : ' taglie riscosse') : ''}</small></div><span class="val">${sort === 'rate' ? pct(r.wins, r.losses) : sort === 'events' ? r.events_participated : sort === 'claims' ? BC(r.bounty_payout_total) : r.wins}</span></div>`).join('') || empty('Nessun risultato ufficiale registrato. La classifica comparirà dopo i primi match verificati.')}</div>`;
    } else if (tab === 'records') {
      const [recs, mil] = await Promise.all([q(BM.sb.from('hof_records_v').select('*')), q(BM.sb.from('hof_milestones_v').select('*').order('achieved_at', { ascending: false }).limit(40))]);
      body = `<div class="grid c2"><div class="box"><h2>Record permanenti</h2>${recs.map(r => `<div class="row2"><div class="g">${REC[r.record_key] ? REC[r.record_key][0] : esc(r.record_key)}<small>${hl(r.holder_id)}</small></div><span class="val">${num(r.value)}${REC[r.record_key] && REC[r.record_key][1] ? ' <small>' + REC[r.record_key][1] + '</small>' : ''}</span></div>`).join('') || empty('Nessun record ancora registrato.')}</div>
      <div class="box"><h2>Traguardi raggiunti</h2>${mil.map(m => `<div class="row2"><div class="g">${hl(m.player_id)}<small>${MIL[m.milestone] || esc(m.milestone)} · ${day(m.achieved_at)}</small></div></div>`).join('') || empty('Nessun traguardo ancora raggiunto.')}</div></div>`;
    } else if (tab === 'events') {
      const [evs, ms] = await Promise.all([q(BM.sb.from('hof_events_v').select('*').order('event_date', { ascending: false }).limit(60)), q(BM.sb.from('hof_matches_v').select('*').order('round').limit(1500))]);
      const by = {}; ms.forEach(m => (by[m.event_id] = by[m.event_id] || []).push(m));
      body = `<div class="box">${evs.map(e => `<details class="row2" style="display:block"><summary style="cursor:pointer;min-height:44px;display:flex;align-items:center;gap:10px"><span class="g"><b>${esc(e.name)}</b><small>${day(e.event_date)} · ${e.participants} partecipanti · ${e.matches_verified}/${e.matches_total} match verificati</small></span></summary>${(by[e.event_id] || []).map(m => `<div class="row2"><div class="g">T${m.round} · ${hl(m.winner_id)} ha battuto ${hl(m.loser_id)}<small>verificato il ${day(m.verified_at)}</small></div></div>`).join('') || empty('Nessun match verificato in questo evento.')}</details>`).join('') || empty('Nessun evento registrato.')}</div>`;
    } else if (tab === 'rivals') {
      const rows = await q(BM.sb.from('hof_rivalries_v').select('*').order('matches', { ascending: false }).limit(40));
      body = `<div class="box">${rows.map(r => `<div class="row2"><div class="g">${hl(r.player_1)} vs ${hl(r.player_2)}<small>${r.matches} match ufficiali · ultimo ${day(r.last_at)}</small></div><span class="val">${r.player_1_wins}–${r.player_2_wins}</span></div>`).join('') || empty(`Nessuna rivalità: servono almeno ${BM.S.hof_rivalry_min_matches ?? 3} match ufficiali tra gli stessi due duellanti.`)}</div>`;
    } else if (tab === 'claims') {
      const rows = await q(BM.sb.from('hof_claims_v').select('*').order('payout', { ascending: false }).limit(40));
      body = `<div class="box">${rows.map(c => `<div class="row2"><div class="g">${hl(c.winner_id)} ha riscosso la taglia su ${hl(c.target_id)}<small>${day(c.created_at)}${c.refunded ? ' · ' + BC(c.refunded) + ' restituiti' : ''}</small></div><span class="val">${BC(c.payout)}</span></div>`).join('') || empty('Nessuna riscossione registrata.')}</div>`;
    } else {
      const ss = await q(BM.sb.from('seasons').select('*').order('starts_on', { ascending: false }));
      const sel = store.get('bm.hof.season', ss[0] ? ss[0].id : '');
      let rows = [];
      if (sel && ss.some(s => s.id === sel)) rows = (await q(BM.sb.from('hof_season_stats_v').select('*').eq('season_id', sel))).filter(r => r.wins + r.losses + r.events_participated > 0).sort((a, b) => b.wins - a.wins || a.nickname.localeCompare(b.nickname));
      body = ss.length ? seg('bm.hof.season', sel, ss.map(s => [s.id, esc(s.name)]), 'store') + `<div class="box">${rows.map((r, i) => `<div class="row2"><span class="rank">${i + 1}</span><div class="g">${hl(r.player_id)}<small>${r.wins}V · ${r.losses}S · ${r.events_participated} eventi · ${pct(r.wins, r.losses)}</small></div><span class="val">${r.wins}</span></div>`).join('') || empty('Nessun risultato ufficiale in questa stagione.')}</div>`
        : `<div class="box">${empty('Nessuna stagione definita. Un amministratore può crearla dal pannello Admin.')}</div>`;
    }
    shell(hofHead + tabs + body, 'hof');
  }

  async function hofPlayer(id) {
    const sb = BM.sb;
    const [st, ms, rec, mil, cl, rv, ss, sst] = await Promise.all([
      q(sb.from('hof_player_stats_v').select('*').eq('player_id', id)),
      q(sb.from('hof_matches_v').select('*').or(`player_a.eq.${id},player_b.eq.${id}`).order('verified_at', { ascending: false }).limit(30)),
      q(sb.from('hof_records_v').select('*').eq('holder_id', id)),
      q(sb.from('hof_milestones_v').select('*').eq('player_id', id).order('achieved_at')),
      q(sb.from('hof_claims_v').select('*').or(`winner_id.eq.${id},target_id.eq.${id}`).order('created_at', { ascending: false }).limit(15)),
      q(sb.from('hof_rivalries_v').select('*').or(`player_1.eq.${id},player_2.eq.${id}`).order('matches', { ascending: false })),
      q(sb.from('seasons').select('*').order('starts_on', { ascending: false })),
      q(sb.from('hof_season_stats_v').select('*').eq('player_id', id))
    ]);
    const s = st[0];
    if (!s) return shell(`<p><a href="#/hof">← Hall of Fame</a></p><div class="box"><h2>Dati non disponibili</h2><p>Per questo duellante non ci sono dati ufficiali.</p></div>`, 'hof');
    const sname = Object.fromEntries(ss.map(x => [x.id, x.name]));
    shell(`<p><a href="#/hof">← Hall of Fame</a></p><div class="row" style="gap:16px">${av({ nickname: s.nickname, avatar: s.avatar })}<div><h1 class="t" style="font-size:2.2rem">${esc(s.nickname)}</h1><a href="#/p/${id}">Profilo Black Market</a></div></div>
    <div class="grid c3" style="margin-top:20px"><div class="box"><p class="mute" style="margin:0">Vittorie / sconfitte</p><div class="big">${s.wins}<small> V</small> ${s.losses}<small> S</small></div><small class="mute">${pct(s.wins, s.losses)} di vittorie${s.wins + s.losses ? '' : ' (nessun match ufficiale)'}</small></div>
    <div class="box"><p class="mute" style="margin:0">Eventi disputati</p><div class="big">${s.events_participated}</div></div>
    <div class="box"><p class="mute" style="margin:0">Taglie riscosse</p><div class="big">${s.bounty_claims}</div><small class="mute">${BC(s.bounty_payout_total)} in totale</small></div></div>
    <div class="grid c2" style="margin-top:14px"><div class="box"><h2>Record e traguardi</h2>${rec.map(r => `<div class="row2"><div class="g">${tag('record', 'g')} ${REC[r.record_key] ? REC[r.record_key][0] : esc(r.record_key)}</div><span class="val">${num(r.value)}</span></div>`).join('')}${mil.map(m => `<div class="row2"><div class="g">${MIL[m.milestone] || esc(m.milestone)}<small>${day(m.achieved_at)}</small></div></div>`).join('')}${rec.length + mil.length ? '' : empty('Nessun record o traguardo ancora raggiunto.')}</div>
    <div class="box"><h2>Per stagione</h2>${sst.filter(x => x.wins + x.losses + x.events_participated > 0).map(x => `<div class="row2"><div class="g">${esc(sname[x.season_id] || 'Stagione')}<small>${x.wins}V · ${x.losses}S · ${x.events_participated} eventi</small></div><span class="val">${x.wins}</span></div>`).join('') || empty('Nessun dato di stagione disponibile.')}</div></div>
    <div class="grid c2" style="margin-top:14px"><div class="box"><h2>Rivalità</h2>${rv.map(r => { const o = r.player_1 === id ? r.player_2 : r.player_1, a = r.player_1 === id ? r.player_1_wins : r.player_2_wins, b = r.player_1 === id ? r.player_2_wins : r.player_1_wins; return `<div class="row2"><div class="g">contro ${hl(o)}<small>${r.matches} match ufficiali</small></div><span class="val">${a}–${b}</span></div>` }).join('') || empty('Nessuna rivalità con abbastanza match ufficiali.')}</div>
    <div class="box"><h2>Riscossioni</h2>${cl.map(c => `<div class="row2"><div class="g">${c.winner_id === id ? 'ha riscosso su ' + hl(c.target_id) : 'taglia riscossa da ' + hl(c.winner_id)}<small>${day(c.created_at)}</small></div><span class="val">${BC(c.payout)}</span></div>`).join('') || empty('Nessuna riscossione registrata.')}</div></div>
    <div class="box" style="margin-top:14px"><h2>Ultimi match ufficiali</h2>${ms.map(m => `<div class="row2"><div class="g">${esc(m.event_name)} · T${m.round}<small>${hl(m.winner_id)} ha battuto ${hl(m.loser_id)} · ${day(m.verified_at)}</small></div>${tag(m.winner_id === id ? 'Vittoria' : 'Sconfitta', m.winner_id === id ? 'g' : 'r')}</div>`).join('') || empty('Nessun match ufficiale.')}</div>`, 'hof');
  }

  /* =============================== FACTION WARS =============================== */
  const facHead = '<h1 class="t">Faction <em>Wars</em></h1>';
  const myFaction = async () => (await q(BM.sb.from('faction_members').select('faction_id,role').eq('user_id', BM.me.id).is('left_at', null)))[0] || null;

  R.factions = async id => {
    if (!on('faction_wars')) return off('Faction <em>Wars</em>', 'factions');
    shell(facHead + loading, 'factions');
    try { return id ? await facDetail(id) : await facHome() } catch (er) { fail(er, 'factions') }
  };

  async function facHome() {
    const sb = BM.sb, ss = await q(sb.from('seasons').select('*').order('starts_on', { ascending: false }));
    let sel = store.get('bm.fac.season', 'all'); if (sel !== 'all' && !ss.some(s => s.id === sel)) sel = 'all';
    const [rows, mine] = await Promise.all([q(sel === 'all' ? sb.from('faction_standings_v').select('*').is('season_id', null) : sb.from('faction_standings_v').select('*').eq('season_id', sel)), myFaction()]);
    rows.sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name));
    const ppw = BM.S.faction_points_per_win ?? 3;
    shell(`${facHead}<p class="sub">Squadre di duellanti. Il punteggio nasce solo dai match ufficiali verificati: <b>${ppw} punti</b> per ogni vittoria su un avversario di un'altra fazione. Non ha alcun legame con i Black Credits e non assegna premi.</p>
    ${seg('bm.fac.season', sel, [['all', 'Sempre'], ...ss.map(s => [s.id, esc(s.name)])], 'store')}
    <div class="box">${rows.map(f => `<div class="row2"><span class="rank">${f.rank}</span><span class="av" aria-hidden="true">${esc(f.symbol || f.name[0].toUpperCase())}</span><div class="g"><a href="#/factions/${f.faction_id}">${esc(f.name)}</a>${f.status !== 'active' ? ' ' + tag('sciolta', 'r') : ''}<small>${f.wins} vittorie · ${f.members} ${f.members == 1 ? 'membro' : 'membri'}</small></div><span class="val">${f.points} <small>pt</small></span></div>`).join('') || empty('Nessuna fazione ancora. Fonda la prima!')}</div>
    ${mine ? `<div class="note" style="margin-top:14px">Fai parte di una fazione. <a href="#/factions/${mine.faction_id}">Apri la tua fazione</a></div>` : `
    <form id="fnew" class="box cols" style="grid-template-columns:1fr;margin-top:14px;max-width:560px"><h2>Fonda una fazione</h2>
    <div><label for="fn">Nome (3–30 caratteri)</label><input id="fn" required minlength="3" maxlength="30"></div>
    <div><label for="fd">Descrizione (facoltativa)</label><input id="fd" maxlength="200"></div>
    <div><label for="fs">Simbolo: una o due lettere o un'emoji (facoltativo)</label><input id="fs" maxlength="8" style="max-width:140px"></div>
    <p class="mute" style="font-size:.9rem;margin:0">Puoi appartenere a una sola fazione alla volta. Dopo l'uscita vale un periodo di attesa di ${BM.S.faction_cooldown_days ?? 7} giorni; massimo ${BM.S.faction_max_members ?? 20} membri.</p>
    <button class="btn gold" type="submit">Fonda la fazione</button></form>`}`, 'factions');
    const f = document.getElementById('fnew');
    if (f) f.onsubmit = async e => {
      e.preventDefault(); const b = f.querySelector('button'); b.disabled = true;
      try { const id = await rpc('create_faction', { p_name: f.fn.value, p_description: f.fd.value || null, p_symbol: f.fs.value || null }); toast('Fazione fondata.'); location.hash = '#/factions/' + id }
      catch (er) { toast(er.message, 1); b.disabled = false }
    };
  }

  async function facDetail(id) {
    const sb = BM.sb;
    const [fs, mem, st, sm, mine, ss] = await Promise.all([
      q(sb.from('factions').select('*').eq('id', id)), q(sb.from('faction_members_v').select('*').eq('faction_id', id)),
      q(sb.from('faction_standings_v').select('*').eq('faction_id', id)), q(sb.from('faction_scored_matches_v').select('*').eq('faction_id', id).order('verified_at', { ascending: false }).limit(25)),
      myFaction(), q(sb.from('seasons').select('*').order('starts_on', { ascending: false }))]);
    const f = fs[0];
    if (!f) return shell('<p><a href="#/factions">← Fazioni</a></p><div class="err">Fazione non trovata.</div>', 'factions');
    const leader = mem.find(m => m.role === 'leader'), iAmLeader = !!mine && mine.faction_id === id && mine.role === 'leader', member = !!mine && mine.faction_id === id;
    const tot = st.find(x => x.season_id === null), sname = Object.fromEntries(ss.map(s => [s.id, s.name]));
    mem.sort((a, b) => (b.role === 'leader') - (a.role === 'leader') || b.wins_for_faction - a.wins_for_faction);
    shell(`<p><a href="#/factions">← Fazioni</a></p><div class="row" style="gap:16px"><span class="av" style="width:56px;height:56px;font-size:1.5rem" aria-hidden="true">${esc(f.symbol || f.name[0].toUpperCase())}</span><div><h1 class="t" style="font-size:2.2rem">${esc(f.name)}</h1>${f.status !== 'active' ? tag('sciolta dal ' + day(f.disbanded_at), 'r') : ''}</div></div>
    ${f.description ? `<p class="sub">${esc(f.description)}</p>` : ''}
    <div class="grid c3" style="margin-top:18px"><div class="box"><p class="mute" style="margin:0">Punteggio complessivo</p><div class="big">${tot ? tot.points : 0}<small> pt</small></div><small class="mute">${tot ? 'posizione ' + tot.rank : 'nessun risultato'}</small></div><div class="box"><p class="mute" style="margin:0">Vittorie ufficiali</p><div class="big">${tot ? tot.wins : 0}</div></div><div class="box"><p class="mute" style="margin:0">Membri</p><div class="big">${mem.length}</div><small class="mute">${leader ? 'capo: ' + esc(leader.nickname) : ''}</small></div></div>
    <div class="row" style="margin-top:14px">${f.status === 'active' && !mine ? `<button class="btn gold" data-act="facJoin" data-f="${id}">Unisciti alla fazione</button>` : ''}${member ? `<button class="btn ghost" data-act="facLeave">Lascia la fazione</button>` : ''}${iAmLeader ? `<button class="btn ghost" data-act="facEdit" data-f="${id}">Modifica descrizione e simbolo</button>` : ''}</div>
    <div class="grid c2" style="margin-top:14px"><div class="box"><h2>Membri</h2>${mem.map(m => `<div class="row2">${av(m)}<div class="g">${esc(m.nickname)} ${m.role === 'leader' ? tag('capo', 'g') : ''}<small>dal ${day(m.joined_at)} · ${m.wins_for_faction} vittorie per la fazione</small></div>${iAmLeader && m.role !== 'leader' ? `<button class="btn ghost sm" data-act="facLead" data-u="${m.user_id}">Cedi la guida</button><button class="btn ghost sm" data-act="facKick" data-u="${m.user_id}">Rimuovi</button>` : ''}</div>`).join('') || empty('Nessun membro attivo.')}</div>
    <div class="box"><h2>Storico per stagione</h2>${st.filter(x => x.season_id).map(x => `<div class="row2"><div class="g">${esc(sname[x.season_id] || 'Stagione')}<small>posizione ${x.rank} · ${x.wins} vittorie</small></div><span class="val">${x.points} pt</span></div>`).join('') || empty('Nessuna stagione con risultati.')}</div></div>
    <div class="box" style="margin-top:14px"><h2>Ultimi match che hanno dato punti</h2>${sm.map(m => `<div class="row2"><div class="g">${hl(m.winner_id)}<small>${day(m.verified_at)}</small></div><span class="val">+${m.points}</span></div>`).join('') || empty('Nessun match ufficiale ha ancora dato punti.')}</div>`, 'factions');
  }

  /* =========================== UNDERGROUND CHALLENGES =========================== */
  const CST = { pending: ['In attesa', ''], accepted: ['Accettata', 'g'], declined: ['Rifiutata', 'r'], cancelled: ['Annullata', 'r'], expired: ['Scaduta', 'r'], in_progress: ['In corso', 'g'], completed: ['Completata', 'g'] };
  const chHead = '<h1 class="t">Underground <em>Challenges</em></h1><p class="sub">Sfide dirette tra duellanti. <b>Una sfida non è un match ufficiale</b>: accettarla non assegna vittorie, punti fazione o Black Credits. Conta solo se il match collegato viene verificato da un organizzatore.</p>';
  const chRow = (c, extra) => `<div class="row2"><div class="g" style="flex-basis:210px">${hl(c.challenger_id)} <span class="mute">sfida</span> ${hl(c.opponent_id)}<small>${day(c.created_at)}${c.message ? ' · “' + esc(c.message) + '”' : ''}${c.status === 'pending' ? ' · scade ' + day(c.expires_at) : ''}${c.match_status ? ' · match ' + (c.match_status === 'verified' ? 'verificato, vincitore ' + esc(pn(c.match_winner_id)) : 'in attesa di verifica') : ''}${c.cancel_reason ? ' · ' + esc(c.cancel_reason) : ''}</small></div>${tag(CST[c.status][0], CST[c.status][1])}${extra || ''}</div>`;

  R.challenges = async () => {
    if (!on('underground')) return off('Underground <em>Challenges</em>', 'challenges');
    shell(chHead + loading, 'challenges');
    try {
      try { await rpc('expire_challenges', {}) } catch (e) { /* la scadenza è solo manutenzione */ }
      const sb = BM.sb, me = BM.me;
      const [ch, ms, evs] = await Promise.all([q(sb.from('challenges_v').select('*').order('created_at', { ascending: false }).limit(200)),
        isOrg() ? q(sb.from('matches').select('id,event_id,round,player_a,player_b,status,created_at').order('created_at', { ascending: false }).limit(300)) : [],
        isOrg() ? q(sb.from('events').select('id,name').limit(200)) : []]);
      const en = Object.fromEntries(evs.map(e => [e.id, e.name])), linked = new Set(ch.filter(c => c.match_id).map(c => c.match_id));
      const open = c => ['pending', 'accepted', 'in_progress'].includes(c.status);
      const incoming = ch.filter(c => c.status === 'pending' && c.opponent_id === me.id);
      const mine = ch.filter(c => open(c) && (c.challenger_id === me.id || c.opponent_id === me.id) && !incoming.includes(c));
      const follow = isOrg() ? ch.filter(c => c.status === 'accepted' || c.status === 'in_progress') : [];
      const closed = ch.filter(c => !open(c)).slice(0, 30);
      const cand = [...BM.P.values()].filter(p => p.id !== me.id && !p.suspended).sort((a, b) => a.nickname.localeCompare(b.nickname));
      const matchOpts = c => ms.filter(m => ((m.player_a === c.challenger_id && m.player_b === c.opponent_id) || (m.player_a === c.opponent_id && m.player_b === c.challenger_id)) && !linked.has(m.id) && new Date(m.created_at) >= new Date(c.responded_at));
      shell(`${chHead}
      <form id="cnew" class="box row" style="margin-top:18px" data-rq="${crypto.randomUUID()}"><select id="co" required aria-label="Avversario" style="flex:1;min-width:180px"><option value="">Scegli l'avversario…</option>${cand.map(p => `<option value="${p.id}">${esc(p.nickname)}</option>`).join('')}</select><input id="cm" maxlength="140" placeholder="Messaggio (facoltativo)" style="flex:2;min-width:200px"><button class="btn gold" type="submit">Lancia la sfida</button></form>
      ${incoming.length ? `<div class="box" style="margin-top:14px"><h2>Ti hanno sfidato (${incoming.length})</h2>${incoming.map(c => chRow(c, `<button class="btn gold sm" data-act="chAcc" data-c="${c.id}">Accetta</button><button class="btn ghost sm" data-act="chDec" data-c="${c.id}">Rifiuta</button>`)).join('')}</div>` : ''}
      <div class="box" style="margin-top:14px"><h2>Le tue sfide aperte</h2>${mine.map(c => chRow(c, (c.status === 'pending' && c.challenger_id === me.id) || c.status === 'accepted' ? `<button class="btn ghost sm" data-act="chCan" data-c="${c.id}">Annulla</button>` : '')).join('') || empty('Nessuna sfida aperta.')}</div>
      ${isOrg() ? `<div class="box" style="margin-top:14px"><h2>Da seguire (organizzatori)</h2><p class="mute" style="font-size:.92rem">Collega il match giocato e, dopo la <b>verifica ufficiale</b> dell'evento, conferma la sfida.</p>${follow.map(c => {
        if (c.status === 'accepted') { const o = matchOpts(c); return chRow(c, o.length ? `<select id="lm-${c.id}" aria-label="Match da collegare">${o.map(m => `<option value="${m.id}">${esc(en[m.event_id] || 'Evento')} · T${m.round} · ${m.status === 'verified' ? 'verificato' : 'in attesa'}</option>`).join('')}</select><button class="btn sm" data-act="chLink" data-c="${c.id}">Collega</button>` : '<small class="mute">Nessun match tra i due giocatori dopo l\'accettazione: registralo da <a href="#/events">Eventi</a>.</small>') }
        return chRow(c, c.match_status === 'verified' ? `<button class="btn gold sm" data-act="chDone" data-c="${c.id}">Conferma sfida</button>` : `<button class="btn sm" disabled title="Verifica prima il match nell'evento">In attesa di verifica</button><a class="btn ghost sm" href="#/e/${(ms.find(m => m.id === c.match_id) || {}).event_id || ''}">Apri evento</a>`) }).join('') || empty('Nessuna sfida da seguire.')}</div>` : ''}
      <div class="box" style="margin-top:14px"><h2>Storico</h2>${closed.map(c => chRow(c)).join('') || empty('Ancora nessuna sfida conclusa.')}</div>`, 'challenges');
      const f = document.getElementById('cnew');
      f.onsubmit = async e => {
        e.preventDefault(); const b = f.querySelector('button[type=submit]'); b.disabled = true;
        try { await rpc('create_challenge', { p_opponent: f.co.value, p_message: f.cm.value || null, p_request_id: f.dataset.rq }); toast('Sfida lanciata.'); BM.route() }
        catch (er) { toast(er.message, 1); b.disabled = false }
      };
    } catch (er) { fail(er, 'challenges') }
  };

  /* ============================== AZIONI (clic) ============================== */
  const done = async (msg) => { toast(msg); await BM.core(); BM.route() };
  const ACT = {
    store: async el => { store.set(el.dataset.k, el.dataset.v); BM.route() },
    facJoin: async el => { await rpc('join_faction', { p_faction: el.dataset.f }); await done('Ora fai parte della fazione.') },
    facLeave: async () => { if (!confirm('Lasciare la fazione? Dovrai attendere prima di entrare in un\'altra. I punti già ottenuti restano alla fazione.')) return; await rpc('leave_faction', {}); await done('Hai lasciato la fazione.') },
    facEdit: async () => { const d = prompt('Nuova descrizione (max 200 caratteri, vuoto = nessuna):'); if (d === null) return; const s = prompt('Simbolo (max 8 caratteri, vuoto = iniziale):'); if (s === null) return; await rpc('update_faction', { p_description: d.trim() || null, p_symbol: s.trim() || null }); await done('Fazione aggiornata.') },
    facLead: async el => { if (!confirm('Cedere la guida della fazione? Diventerai un membro semplice.')) return; await rpc('transfer_faction_leadership', { p_user: el.dataset.u }); await done('Guida ceduta.') },
    facKick: async el => { if (!confirm('Rimuovere questo membro dalla fazione?')) return; await rpc('kick_faction_member', { p_user: el.dataset.u }); await done('Membro rimosso.') },
    chAcc: async el => { await rpc('respond_challenge', { p_id: el.dataset.c, p_accept: true }); await done('Sfida accettata. Un organizzatore registrerà il match.') },
    chDec: async el => { if (!confirm('Rifiutare la sfida?')) return; await rpc('respond_challenge', { p_id: el.dataset.c, p_accept: false }); await done('Sfida rifiutata.') },
    chCan: async el => { if (!confirm('Annullare la sfida?')) return; await rpc('cancel_challenge', { p_id: el.dataset.c }); await done('Sfida annullata.') },
    chLink: async el => { const m = document.getElementById('lm-' + el.dataset.c).value; await rpc('link_challenge_match', { p_id: el.dataset.c, p_match: m }); await done('Match collegato. La sfida è in corso.') },
    chDone: async el => { if (!confirm('Confermare la sfida? Il risultato ufficiale è quello già verificato nell\'evento.')) return; await rpc('complete_challenge', { p_id: el.dataset.c }); await done('Sfida completata.') },
    /* amministrazione */
    modTog: async el => { const r = ask((el.dataset.on === '1' ? 'Motivazione dell\'attivazione' : 'Motivazione della disattivazione') + ' del modulo:'); if (!r) return; await rpc('admin_set_module', { p_module: el.dataset.m, p_enabled: el.dataset.on === '1', p_reason: r }); await done('Modulo aggiornato.') },
    seasonNew: async () => { const f = document.getElementById('sn'); if (!f.reportValidity()) return; const r = ask('Motivazione:'); if (!r) return; await rpc('admin_create_season', { p_name: f.sname.value, p_start: f.sfrom.value, p_end: f.sto.value, p_reason: r }); await done('Stagione creata.') },
    afRename: async el => { const n = prompt('Nuovo nome della fazione:'); if (!n) return; const r = ask('Motivazione:'); if (!r) return; await rpc('admin_faction_rename', { p_faction: el.dataset.f, p_name: n, p_reason: r }); await done('Fazione rinominata.') },
    afDisband: async el => { if (!confirm('Sciogliere la fazione? Storico e punti restano consultabili.')) return; const r = ask('Motivazione:'); if (!r) return; await rpc('admin_faction_disband', { p_faction: el.dataset.f, p_reason: r }); await done('Fazione sciolta.') },
    afMove: async () => { const u = document.getElementById('mvu').value, f = document.getElementById('mvf').value; if (!u || !f) { toast('Scegli duellante e fazione.', 1); return } const r = ask('Motivazione dello spostamento:'); if (!r) return; await rpc('admin_faction_move_member', { p_user: u, p_faction: f, p_reason: r }); await done('Membro spostato.') },
    afExc: async el => { const r = ask('Motivazione dell\'esclusione dal punteggio:'); if (!r) return; await rpc('admin_faction_exclude_match', { p_match: el.dataset.m, p_reason: r }); await done('Match escluso dal punteggio delle fazioni.') },
    afInc: async el => { const r = ask('Motivazione del reintegro:'); if (!r) return; await rpc('admin_faction_include_match', { p_match: el.dataset.m, p_reason: r }); await done('Match reintegrato.') },
    acCan: async el => { const r = ask('Motivazione dell\'annullamento:'); if (!r) return; await rpc('admin_cancel_challenge', { p_id: el.dataset.c, p_reason: r }); await done('Sfida annullata.') }
  };
  /* chiamato da black-market.html per ogni clic con data-act; ritorna true se gestito qui */
  BM.act = async (a, el) => { if (!ACT[a]) return false; await ACT[a](el); return true };

  /* ============================ PANNELLO AMMINISTRATORE ============================ */
  BM.adminExt = async box => {
    box.innerHTML = '<div class="box" style="margin-top:14px"><h2>Moduli aggiuntivi</h2>' + loading + '</div>';
    try {
      const sb = BM.sb, anyOn = MODS.some(m => on(m[0]));
      const [ss, fs, mem, sm, ex, ch, au] = await Promise.all([
        anyOn ? q(sb.from('seasons').select('*').order('starts_on', { ascending: false })) : [],
        on('faction_wars') ? q(sb.from('factions').select('*').order('created_at')) : [],
        on('faction_wars') ? q(sb.from('faction_members').select('user_id,faction_id').is('left_at', null)) : [],
        on('faction_wars') ? q(sb.from('faction_scored_matches_v').select('*').order('verified_at', { ascending: false }).limit(20)) : [],
        on('faction_wars') ? q(sb.from('faction_match_exclusions').select('*').order('created_at', { ascending: false }).limit(20)) : [],
        on('underground') ? q(sb.from('challenges_v').select('*').in('status', ['pending', 'accepted', 'in_progress']).order('created_at', { ascending: false }).limit(50)) : [],
        q(sb.from('audit_logs').select('*').in('action', ['set_module', 'create_season', 'create_faction', 'rename_faction', 'disband_faction', 'join_faction', 'leave_faction', 'kick_member', 'move_faction_member', 'transfer_leadership', 'update_faction', 'exclude_match_from_factions', 'include_match_in_factions', 'create_challenge', 'accept_challenge', 'decline_challenge', 'cancel_challenge', 'admin_cancel_challenge', 'link_challenge_match', 'complete_challenge', 'expire_challenges']).order('id', { ascending: false }).limit(30))]);
      const act = fs.filter(f => f.status === 'active'), users = [...BM.P.values()].sort((a, b) => a.nickname.localeCompare(b.nickname));
      const fname = Object.fromEntries(fs.map(f => [f.id, f.name])), inF = new Set(mem.map(m => m.user_id));
      box.innerHTML = `<div class="box" style="margin-top:14px"><h2>Moduli aggiuntivi</h2><p class="mute" style="font-size:.92rem">Gli interruttori sono verificati anche dal database: a modulo spento le operazioni vengono rifiutate. Ogni cambio chiede una motivazione ed è registrato nell'audit.</p>
      ${MODS.map(m => `<div class="row2"><div class="g">${m[1]}<small>${on(m[0]) ? 'Attivo: visibile a tutti gli utenti' : 'Disattivato: nascosto, operazioni bloccate'}</small></div>${tag(on(m[0]) ? 'attivo' : 'spento', on(m[0]) ? 'g' : '')}<button class="btn ${on(m[0]) ? 'ghost' : 'gold'} sm" data-act="modTog" data-m="${m[0]}" data-on="${on(m[0]) ? 0 : 1}">${on(m[0]) ? 'Disattiva' : 'Attiva'}</button></div>`).join('')}</div>
      ${anyOn ? `<div class="box" style="margin-top:14px"><h2>Stagioni</h2>${ss.map(s => `<div class="row2"><div class="g">${esc(s.name)}<small>${day(s.starts_on)} → ${day(s.ends_on)}</small></div></div>`).join('') || empty('Nessuna stagione definita.')}
        <form id="sn" class="row" style="margin-top:10px" onsubmit="return false"><input name="sname" placeholder="Nome stagione" required minlength="3" maxlength="40" style="flex:1;min-width:160px" aria-label="Nome stagione"><input name="sfrom" type="date" required aria-label="Inizio"><input name="sto" type="date" required aria-label="Fine"><button type="button" class="btn gold sm" data-act="seasonNew">Crea stagione</button></form><p class="mute" style="font-size:.88rem">Le stagioni non possono sovrapporsi e non si cancellano.</p></div>` : ''}
      ${on('faction_wars') ? `<div class="box" style="margin-top:14px"><h2>Fazioni</h2>${act.map(f => `<div class="row2"><div class="g"><a href="#/factions/${f.id}">${esc(f.name)}</a><small>${mem.filter(m => m.faction_id === f.id).length} membri</small></div><button class="btn ghost sm" data-act="afRename" data-f="${f.id}">Rinomina</button><button class="btn ghost sm" data-act="afDisband" data-f="${f.id}">Sciogli</button></div>`).join('') || empty('Nessuna fazione attiva.')}
        ${act.length ? `<div class="row" style="margin-top:10px"><select id="mvu" aria-label="Duellante"><option value="">Sposta duellante…</option>${users.map(u => `<option value="${u.id}">${esc(u.nickname)}${inF.has(u.id) ? ' (in una fazione)' : ''}</option>`).join('')}</select><select id="mvf" aria-label="Fazione di destinazione"><option value="">verso la fazione…</option>${act.map(f => `<option value="${f.id}">${esc(f.name)}</option>`).join('')}</select><button class="btn sm" data-act="afMove">Sposta</button></div>` : ''}</div>
        <div class="grid c2" style="margin-top:14px"><div class="box"><h2>Match che danno punti (ultimi 20)</h2>${sm.map(m => `<div class="row2"><div class="g">${esc(pn(m.winner_id))} → ${esc(fname[m.faction_id] || 'fazione')}<small>${day(m.verified_at)} · +${m.points}</small></div><button class="btn ghost sm" data-act="afExc" data-m="${m.match_id}">Escludi</button></div>`).join('') || empty('Nessuno.')}</div>
        <div class="box"><h2>Match esclusi dal punteggio</h2>${ex.map(x => `<div class="row2"><div class="g">${esc(x.reason)}<small>${day(x.created_at)}</small></div><button class="btn ghost sm" data-act="afInc" data-m="${x.match_id}">Reintegra</button></div>`).join('') || empty('Nessuna esclusione.')}</div></div>` : ''}
      ${on('underground') ? `<div class="box" style="margin-top:14px"><h2>Moderazione sfide aperte (${ch.length})</h2>${ch.map(c => chRow(c, `<button class="btn ghost sm" data-act="acCan" data-c="${c.id}">Annulla</button>`)).join('') || empty('Nessuna sfida aperta.')}</div>` : ''}
      <div class="box" style="margin-top:14px"><h2>Audit dei moduli (ultimi 30)</h2>${au.map(a => `<div class="row2"><div class="g"><b>${esc(a.action)}</b> · ${esc(pn(a.actor_id))}<small>${when(a.created_at)}${a.reason ? ' · ' + esc(a.reason) : ''}</small></div></div>`).join('') || empty('Nessun evento registrato.')}</div>`;
    } catch (er) {
      box.innerHTML = `<div class="err" role="alert" style="margin-top:14px">Moduli aggiuntivi non disponibili: ${esc(er.message)}. Hai applicato la migrazione <b>black-market-moduli.sql</b>?</div>`;
    }
  };
};
