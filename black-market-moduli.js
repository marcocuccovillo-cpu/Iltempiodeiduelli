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
  const ROLE = { user: 'Duellante', organizer: 'Organizzatore', moderator: 'Moderatore', admin: 'Amministratore' };
  const MODS = [['ladder', 'Ladder', 'ladder'], ['hall_of_fame', 'Hall of Fame', 'hof'], ['faction_wars', 'Faction Wars', 'factions'], ['underground', 'Underground', 'challenges']];
  const on = k => BM.S['module_' + k] == 1;
  const isOrg = () => BM.me && (BM.me.role === 'organizer' || BM.me.role === 'admin');
  const isStaff = () => BM.me && (BM.me.role === 'moderator' || BM.me.role === 'admin');
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
  BM.navItems = () => [...MODS.filter(m => on(m[0])).map(m => [m[2], m[1]]), ...(isStaff() ? [['mod', 'Funzioni Mod']] : [])];

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


  /* ============== BADGE: vetrina nel profilo e nella dashboard (grafica in badge.js, calcolo nel database) ============== */
  let bdRows = [];
  BM.badgeBox = async (uid, own) => {
    if (!window.TDB) return '';
    try {
      TDB.init();
      const rows = await TDB.load(BM.sb, uid);
      bdRows = rows;
      const sm = TDB.summary(rows);
      return `<div class="box" id="bdBox" style="margin-top:14px"><h2>Badge e traguardi</h2>${TDB.sumBox(sm)}${TDB.showcase(rows, own ? 6 : 10, 'md')}` +
        (own ? '<p style="margin:14px 0 0"><a class="btn ghost sm" href="sentiero.html">Tutti i traguardi nel Sentiero</a></p>' : '') + '</div>';
    } catch (er) {
      return BM.me && BM.me.role === 'admin' ? `<div class="box" style="margin-top:14px"><h2>Badge e traguardi</h2><p class="mute" style="margin:0">${esc(er.message)}</p></div>` : '';
    }
  };
  (document.getElementById('app') || document).addEventListener('click', e => {
    const b = e.target.closest && e.target.closest('#bdBox [data-bd]'); if (!b || !window.TDB) return;
    const r = bdRows.filter(x => x.code === b.dataset.bd)[0]; if (r) TDB.detail(r);
  });

  /* ============== PROFILO IN DASHBOARD: avatar + statistiche personali ============== */
  const tile = (v, l) => `<div class="stat"><b>${v}</b><span>${l}</span></div>`;
  BM.dashHero = async () => {
    const me = BM.me, sb = BM.sb, id = me.id;
    let tiles = '', note = '', pend = [], pendVal = new Map();
    try {
      const [ms, bs, ss, mw, lad, lrw, pend0] = await Promise.all([
        q(sb.from('matches').select('event_id,winner_id').eq('status', 'verified').or(`player_a.eq.${id},player_b.eq.${id}`)),
        q(sb.from('bounties').select('amount,status').eq('creator_id', id)),
        q(sb.from('bounty_settlements').select('payout').eq('winner_id', id)),
        q(sb.from('most_wanted_v').select('bounty_value,active_count').eq('id', id)),
        on('ladder') ? q(sb.from('ladder_standings_v').select('*').eq('user_id', id)) : Promise.resolve([]),
        on('ladder') ? q(sb.from('ledger_entries').select('amount').eq('kind', 'ladder_reward').eq('user_id', id)) : Promise.resolve([]),
        on('ladder') ? q(sb.from('ladder_matches').select('*').eq('status', 'pending').eq('opponent_id', id).order('created_at', { ascending: false }).limit(5)).catch(() => []) : Promise.resolve([])]);
      pend = pend0.filter(m => !m.expires_at || new Date(m.expires_at) > Date.now()); pendVal = new Map([[id, mw[0] ? mw[0].bounty_value : 0]]);
      const w = ms.filter(m => m.winner_id === id).length, l = ms.length - w, ev = new Set(ms.map(m => m.event_id)).size;
      const placed = bs.filter(b => b.status !== 'cancelled'), got = ss.reduce((t, x) => t + x.payout, 0);
      tiles = tile(BC(BM.wallet), 'Saldo') +
        tile(ms.length ? `${w}V · ${l}S` : 'n/d', 'Match ufficiali' + (ms.length ? ` · ${pct(w, l)}` : '')) +
        tile(ev || 'n/d', 'Eventi giocati') +
        tile(mw[0] ? BC(mw[0].bounty_value) : '0 BC', 'Taglie su di te' + (mw[0] ? ` (${mw[0].active_count})` : '')) +
        tile(placed.length, 'Taglie lanciate' + (placed.length ? ` · ${BC(placed.reduce((t, b) => t + b.amount, 0))}` : '')) +
        tile(ss.length, 'Taglie riscosse' + (ss.length ? ` · ${BC(got)}` : ''));
      if (on('ladder')) {
        const fm = (await BM.hasV11()) ? ['Advanced', 'Edison'] : [null];   // con la migrazione 011 c'è un Elo per formato
        fm.forEach(f => { const r = f ? lad.find(x => x.format === f) : lad[0]; tiles += tile(r ? r.elo : 'n/d', 'Elo ' + (f || 'Ladder') + (r ? ` · #${r.rank} · ${r.wins}V ${r.draws}P ${r.losses}S` : ' · non ancora classificato')) });
      }
      if (on('ladder')) tiles += tile(BC(lrw.reduce((t, x) => t + x.amount, 0)), 'Guadagnati in Ladder' + (lrw.length ? ` · ${lrw.length} vittorie premiate` : ''));
    } catch (er) { note = `<p class="mute">Statistiche non disponibili: ${esc(er.message)}</p>` }
    const btns = `<div class="row" style="margin-top:10px"><a class="btn gold sm" href="#/p/${id}">Il mio profilo e le taglie</a><button class="btn ghost sm" data-act="avPick">${me.avatar_img ? 'Cambia foto' : 'Aggiungi foto'}</button>${me.avatar_img ? '<button class="btn ghost sm" data-act="avDel">Rimuovi foto</button>' : ''}<input id="avf" type="file" accept="image/*" hidden></div>`;
    const eq = BM.shopEq ? await BM.shopEq(id) : null;   /* Shop: premi equipaggiati (se ce ne sono) */
    const who = BM.shopHead && eq && Object.keys(eq).length
      ? BM.shopHead(me, eq, { avatar: av(me).replace('class="av"', 'class="av xl"'), h: 'h2', tag: `<span class="tag">${ROLE[me.role]}</span>`, extra: btns, petSize: 104 })
      : `<div style="display:flex;gap:16px;align-items:center">${av(me).replace('class="av"', 'class="av xl"')}<div style="min-width:0;flex:1"><h2 style="margin:0;font-size:1.6rem;color:var(--tx);overflow-wrap:anywhere">${esc(me.nickname)}</h2><span class="tag">${ROLE[me.role]}</span>${btns}</div></div>`;
    return BM.incomingBox(pend, pendVal, { mt: 22 }) + `<div class="box" style="margin-top:22px">${who}
      <div class="stats" style="margin-top:16px">${tiles}</div>${note}<p class="mute" style="font-size:.85rem;margin:12px 0 0">Statistiche calcolate dai match ufficiali verificati, dalle taglie e dalla Ladder. Dove non ci sono dati compare “n/d”.</p></div>` + await BM.badgeBox(id, true);
  };
  const toAvatar = async file => {
    let bmp;
    try { bmp = await createImageBitmap(file) } catch (e) { throw new Error('Formato immagine non supportato: scegli una foto JPG o PNG') }
    const N = 128, c = document.createElement('canvas'); c.width = c.height = N;
    const side = Math.min(bmp.width, bmp.height), sx = (bmp.width - side) / 2, sy = (bmp.height - side) / 2, g = c.getContext('2d');
    g.fillStyle = '#000'; g.fillRect(0, 0, N, N); g.drawImage(bmp, sx, sy, side, side, 0, 0, N, N);
    let url = '';
    for (const qa of [0.85, 0.72, 0.58, 0.45]) { url = c.toDataURL('image/jpeg', qa); if (url.length <= 22000) break }
    if (url.length > 22000) throw new Error('Immagine troppo complessa: scegline un\'altra');
    return url;
  };
  const avErr = er => /could not find the function|schema cache/i.test(er.message) ? new Error('Funzione non trovata: esegui prima la migrazione black-market-ladder.sql') : er;
  document.addEventListener('change', async e => {
    if (!e.target || e.target.id !== 'avf' || !e.target.files || !e.target.files[0]) return;
    try { const img = await toAvatar(e.target.files[0]); await rpc('set_my_avatar_img', { p_img: img }).catch(er => { throw avErr(er) }); await BM.core(); toast('Foto del profilo aggiornata.'); BM.route() }
    catch (er) { toast(er.message, 1) }
  });

  /* =================================== LADDER =================================== */
  const FMT = ['Advanced', 'Edison'];
  const KN = { ladder: 'Ladder normale', bounty: 'Per la taglia', both: 'Ladder + taglia' };
  const KT = { ladder: '', bounty: 'r', both: 'g' };
  const LST = { pending: ['In attesa', ''], accepted: ['Da giocare', 'g'], reported: ['Da confermare', 'g'], disputed: ['Contestato', 'r'], closed: ['Concluso', 'g'], declined: ['Rifiutata', 'r'], cancelled: ['Annullata', 'r'], expired: ['Scaduta', 'r'], voided: ['Annullato', 'r'] };
  const rwS = () => { const S = BM.S || {}; return { on: (S.ladder_reward_enabled ?? 1) === 1, bc: S.ladder_reward_bc ?? 20, day: S.ladder_reward_max_day ?? 3, pair: S.ladder_reward_pair_day ?? 1, wpa: (S.ladder_wpa_matches ?? 1) === 1, hold: S.ladder_claim_hold_hours ?? 24 } };
  /* la migrazione 011 (formati, Elo separati, tipo di sfida) è presente? Si controlla una volta; finché manca, la pagina funziona come prima */
  let v11 = null;
  const hasV11 = async () => { if (v11 === true) return true; try { await q(BM.sb.from('ladder_standings_v').select('format').limit(1)); v11 = true } catch (e) { v11 = false } return v11 };
  BM.hasV11 = hasV11;
  const kName = m => m.kind ? KN[m.kind] : '';
  const ldHead = () => { const r = rwS(); return '<h1 class="t">La <em>Ladder</em></h1><p class="sub">Sfide dirette in <b>Advanced</b> ed <b>Edison</b>, con una classifica Elo per ciascun formato: parti da 1000 in entrambi. Il risultato lo invia uno e lo <b>conferma l\'altro</b>.' + (r.on ? ` Ogni vittoria confermata in una sfida di Ladder <b>genera ${r.bc} Black Credits</b> per il vincitore (creati dal sistema, non tolti allo sconfitto)` : '') + (r.wpa ? (r.on ? ' e' : ' Ogni vittoria confermata') + ' diventa un <b>match WPA ufficiale</b>.' : (r.on ? '.' : '')) + '</p>' };
  const outcomeOpts = m => `<option value="challenger|2-0">Vince ${esc(pn(m.challenger_id))} 2-0</option><option value="challenger|2-1">Vince ${esc(pn(m.challenger_id))} 2-1</option><option value="opponent|0-2">Vince ${esc(pn(m.opponent_id))} 2-0</option><option value="opponent|1-2">Vince ${esc(pn(m.opponent_id))} 2-1</option><option value="draw|1-1">Pareggio 1-1</option>`;
  const outcomeText = m => m.reported_result === 'draw' ? 'pareggio 1-1' : `ha vinto ${esc(pn(m.reported_result === 'challenger' ? m.challenger_id : m.opponent_id))} ${m.reported_result === 'challenger' ? m.reported_score : m.reported_score.split('-').reverse().join('-')}`;
  const dlt = n => `<span class="${n >= 0 ? 'pos' : 'neg'}">${n >= 0 ? '+' : ''}${n}</span>`;
  const lrow = (m, extra) => `<div class="row2"><div class="g">${esc(pn(m.challenger_id))} <span class="mute">vs</span> ${esc(pn(m.opponent_id))}<small>${esc(m.format)}${kName(m) ? ' · ' + kName(m) : ''} · ${when(m.created_at)}${m.message ? ' · “' + esc(m.message) + '”' : ''}${m.status === 'reported' ? ' · ' + outcomeText(m) : ''}${m.dispute_reason ? ' · contestazione: ' + esc(m.dispute_reason) : ''}</small></div>${tag(LST[m.status][0], LST[m.status][1])}${extra || ''}</div>`;
  /* cosa c'è in gioco, spiegato a chi riceve la sfida (value = taglie che ha addosso) */
  const stake = (m, value) => {
    const r = rwS(), el = `l'Elo ${esc(m.format)}${r.on ? ' e +' + r.bc + ' BC al vincitore' : ''}`, tg = value > 0 ? `le tue taglie (in tutto ${BC(value)})` : 'le taglie che hai addosso';
    if (m.kind === 'bounty') return `<b>Solo per la taglia</b>: se perdi, chi ti ha sfidato potrà riscuotere ${tg}. L'Elo non cambia.`;
    if (m.kind === 'both') return `<b>Ladder + taglia</b>: in gioco ${el}, e se perdi chi ti ha sfidato potrà riscuotere ${tg}.`;
    if (m.kind === 'ladder') return `<b>Ladder normale</b>: in gioco ${el}. Le taglie che hai addosso non c'entrano.`;
    return '';
  };
  /* pannello "Ti hanno sfidato": usato nella pagina Ladder e in dashboard; i pulsanti restano gli stessi (ldAcc / ldDec) */
  BM.incomingBox = (incoming, vals, opt) => incoming.length ? `<div class="box" id="ldin" style="margin-top:${(opt && opt.mt) || 18}px;border-color:var(--gold)"><h2 style="margin-top:0">${incoming.length === 1 ? 'Hai 1 sfida da accettare' : 'Hai ' + incoming.length + ' sfide da accettare'}</h2><p class="mute" style="font-size:.9rem;margin-top:0">Puoi accettare o rifiutare. Se non rispondi la sfida scade da sola dopo ${(BM.S && BM.S.ladder_expiry_days) || 7} giorni.</p>${incoming.map(m => `<div class="row2" style="align-items:flex-start"><div class="g"><b>${esc(pn(m.challenger_id))}</b> ti sfida in <b>${esc(m.format)}</b><small style="display:block;color:var(--tx);opacity:.9;margin:3px 0">${stake(m, vals && vals.get(m.opponent_id))}</small><small>${when(m.created_at)}${m.message ? ' · “' + esc(m.message) + '”' : ''}</small></div><div class="row" style="gap:8px;flex:none"><button class="btn gold sm" data-act="ldAcc" data-c="${m.id}">Accetta</button><button class="btn ghost sm" data-act="ldDec" data-c="${m.id}">Rifiuta</button></div></div>`).join('')}</div>` : '';

  R.ladder = async () => {
    if (!on('ladder')) return off('La <em>Ladder</em>', 'ladder');
    shell(ldHead() + loading, 'ladder');
    try {
      try { await rpc('ladder_expire', {}) } catch (e) { /* manutenzione */ }
      const sb = BM.sb, me = BM.me, V = await hasV11();
      const [st, ms, mw, mine0] = await Promise.all([q(sb.from('ladder_standings_v').select('*').order('rank').limit(400)), q(sb.from('ladder_matches').select('*').order('created_at', { ascending: false }).limit(200)),
        q(sb.from('most_wanted_v').select('id,bounty_value')), q(sb.from('bounties').select('target_id,amount').eq('creator_id', me.id).eq('status', 'active'))]);
      const isMine = m => m.challenger_id === me.id || m.opponent_id === me.id;
      const incoming = ms.filter(m => m.status === 'pending' && m.opponent_id === me.id);
      const outgoing = ms.filter(m => m.status === 'pending' && m.challenger_id === me.id);
      const toPlay = ms.filter(m => m.status === 'accepted' && isMine(m));
      const toConfirm = ms.filter(m => m.status === 'reported' && isMine(m));
      const disputed = ms.filter(m => m.status === 'disputed' && isMine(m));
      const fsel = V ? store.get('ldfmt', FMT[0]) : null, FM = V ? FMT : [null];
      const stF = f => V ? st.filter(r => r.format === f) : st;
      const closed = f => ms.filter(m => m.status === 'closed' && (!V || m.format === f)).sort((a, b) => new Date(b.closed_at) - new Date(a.closed_at)).slice(0, 15);
      const myRow = f => stF(f).find(r => r.user_id === me.id);
      const eloOf = (f, id) => (stF(f).find(r => r.user_id === id) || {}).elo;
      const val = new Map(mw.map(r => [r.id, r.bounty_value])), own = new Map();
      mine0.forEach(b => own.set(b.target_id, (own.get(b.target_id) || 0) + b.amount));
      const claim = id => Math.max(0, (val.get(id) || 0) - (own.get(id) || 0));      // quanto potrei incassare io (le mie quote mi tornano indietro)
      const cand = [...BM.P.values()].filter(p => p.id !== me.id && !p.suspended).sort((a, b) => a.nickname.localeCompare(b.nickname));
      const rw = rwS(), now = Date.now(), rewardedToday = ms.filter(m => m.status === 'closed' && m.reward_user === me.id && m.reward_amount > 0 && now - new Date(m.closed_at) < 864e5).length;
      const myVal = new Map([[me.id, val.get(me.id) || 0]]);
      const eloBox = V ? `<div class="stats" style="margin-top:0">${FMT.map(f => { const r = myRow(f); return `<div class="stat"><b>${r ? r.elo : 1000}</b><span>Elo ${f}${r ? ` · #${r.rank} · ${r.wins}V ${r.draws}P ${r.losses}S` : ' · non ancora classificato'}</span></div>` }).join('')}</div>`
        : (() => { const r = myRow(null); return `<div class="row" style="gap:16px">${av(me)}<div class="g"><b>${esc(me.nickname)}</b><small class="mute" style="display:block">${r ? `${r.wins}V · ${r.draws}P · ${r.losses}S · ${r.matches} match` : 'Non ancora classificato: gioca il tuo primo match'}</small></div><span class="val">${r ? r.elo : 1000} <small>Elo</small></span></div>` })();
      const stRows = f => stF(f).map(r => `<div class="row2 ldr" data-n="${esc(r.nickname.toLowerCase())}"><span class="rank">${r.rank}</span>${av(BM.P.get(r.user_id) || { nickname: r.nickname, avatar: r.avatar })}<div class="g"><a href="#/p/${r.user_id}">${esc(r.nickname)}</a><small>${r.wins}V · ${r.draws}P · ${r.losses}S</small></div><span class="val">${r.elo}</span>${r.user_id !== me.id ? `<button class="btn ghost sm" data-act="ldPick" data-u="${r.user_id}"${f ? ` data-f="${f}"` : ''}>Sfida</button>` : ''}</div>`).join('') || empty(V ? `Nessuna partita conclusa in ${f}: la classifica comparirà dopo il primo risultato confermato.` : 'Nessun match concluso: la classifica comparirà dopo il primo risultato confermato.');
      const resRows = f => closed(f).map(m => { const dr = m.reported_result === 'draw', wn = m.reported_result === 'challenger' ? m.challenger_id : m.opponent_id, ls = wn === m.challenger_id ? m.opponent_id : m.challenger_id, noElo = m.kind === 'bounty';
        return `<div class="row2"><div class="g">${dr ? esc(pn(m.challenger_id)) + ' e ' + esc(pn(m.opponent_id)) + ' pareggiano' : esc(pn(wn)) + ' ha battuto ' + esc(pn(ls))}<small>${esc(m.format)}${kName(m) ? ' · ' + kName(m) : ''} · ${when(m.closed_at)}${noElo ? ' · nessun Elo in gioco' : ` · ${esc(pn(m.challenger_id))} ${dlt(m.elo_challenger_delta)} · ${esc(pn(m.opponent_id))} ${dlt(m.elo_opponent_delta)}`}${m.reward_amount > 0 ? ` · <span class="pos">+${m.reward_amount} BC a ${esc(pn(m.reward_user))}</span>` : ''}${m.official_match_id ? ' · match WPA' : ''}</small></div></div>` }).join('') || empty(V ? `Ancora nessun risultato in ${f}.` : 'Ancora nessun risultato.');
      const tabs = V ? seg('ldfmt', fsel, FMT.map(f => [f, f]), 'store') : '';
      shell(`${ldHead()}
      ${BM.incomingBox(incoming, myVal)}
      <div class="box" style="margin-top:18px"><h2 style="margin-top:0">Il tuo Elo</h2>${eloBox}</div>
      <form id="ldnew" class="box" style="margin-top:14px;display:grid;gap:10px" data-rq="${crypto.randomUUID()}"><h2 style="margin:0">Lancia una sfida</h2>
        <div class="row" style="gap:10px;flex-wrap:wrap"><select id="ldo" required aria-label="Avversario" style="flex:2;min-width:180px"><option value="">Scegli il duellante…</option>${cand.map(p => `<option value="${p.id}">${esc(p.nickname)}${V ? '' : ' · ' + (eloOf(null, p.id) ? eloOf(null, p.id) + ' Elo' : 'non classificato')}${claim(p.id) > 0 ? ' · taglia ' + claim(p.id) + ' BC' : ''}</option>`).join('')}</select>
        ${V ? `<select id="ldf" aria-label="Formato" required style="flex:1;min-width:120px">${FMT.map(f => `<option${f === fsel ? ' selected' : ''}>${f}</option>`).join('')}</select>` : `<input type="hidden" id="ldf" value="Advanced">`}</div>
        ${V ? `<div><label for="ldk">Tipo di sfida</label><select id="ldk" required style="width:100%"><option value="">Scegli prima il duellante…</option></select><p id="ldkh" class="mute" style="font-size:.88rem;margin:6px 0 0"></p></div>` : '<p class="mute" style="font-size:.88rem;margin:0">Per scegliere il formato e il tipo di sfida un amministratore deve eseguire la migrazione <b>black-market-ladder-formati.sql</b>.</p>'}
        <input id="ldm" maxlength="140" placeholder="Messaggio (facoltativo)"><button class="btn gold" type="submit">Lancia la sfida</button></form>
      ${toPlay.length ? `<div class="box" style="margin-top:14px"><h2>Da giocare (${toPlay.length})</h2><p class="mute" style="font-size:.9rem;margin-top:0">Dopo il duello, uno dei due invia il risultato; l'altro lo conferma.</p>${toPlay.map(m => lrow(m, `<select id="lr-${m.id}" aria-label="Risultato">${outcomeOpts(m)}</select><button class="btn sm" data-act="ldRep" data-c="${m.id}">Invia risultato</button><button class="btn ghost sm" data-act="ldCan" data-c="${m.id}">Annulla</button>`)).join('')}</div>` : ''}
      ${toConfirm.length ? `<div class="box" style="margin-top:14px"><h2>Risultati da confermare (${toConfirm.length})</h2>${toConfirm.map(m => lrow(m, m.reported_by === me.id ? '<small class="mute">attende la conferma dell\'avversario</small>' : `<button class="btn gold sm" data-act="ldConf" data-c="${m.id}">Conferma</button><button class="btn ghost sm" data-act="ldDisp" data-c="${m.id}">Contesta</button>`)).join('')}</div>` : ''}
      ${disputed.length ? `<div class="box" style="margin-top:14px"><h2>Contestati</h2><p class="mute" style="font-size:.9rem;margin-top:0">Decide un amministratore.</p>${disputed.map(m => lrow(m)).join('')}</div>` : ''}
      ${outgoing.length ? `<div class="box" style="margin-top:14px"><h2>Sfide inviate</h2>${outgoing.map(m => lrow(m, `<button class="btn ghost sm" data-act="ldCan" data-c="${m.id}">Annulla</button>`)).join('')}</div>` : ''}
      ${tabs}
      <div class="box" style="margin-top:${V ? 0 : 14}px"><h2 style="margin-top:0">Classifica${V ? ' ' + fsel : ''}</h2><input id="lds" type="search" placeholder="Cerca giocatore…" aria-label="Cerca giocatore" style="margin-bottom:8px">${stRows(V ? fsel : null)}</div>
      <div class="box" style="margin-top:14px"><h2 style="margin-top:0">Ultimi risultati${V ? ' ' + fsel : ''}</h2>${resRows(V ? fsel : null)}</div>
      <div class="box" style="margin-top:14px"><h2 style="margin-top:0">Come funzionano premi e taglie</h2><ul class="mute" style="margin:0;padding-left:20px;font-size:.92rem;line-height:1.5">${V ? `<li><b>Ladder normale</b>: conta per l'Elo del formato${rw.on ? ` e dà <b>+${rw.bc} BC</b> al vincitore` : ''}. Le taglie non c'entrano.</li><li><b>Per la taglia</b>: solo il match WPA ufficiale con cui, se vinci, riscuoti la taglia. Nessun Elo e nessun premio Ladder. Disponibile solo se l'avversario ha una taglia che puoi incassare.</li><li><b>Ladder + taglia</b>: tutte e due le cose insieme.</li>` : (rw.on ? `<li><b>+${rw.bc} BC</b> per ogni vittoria confermata (pareggi e sconfitte non danno BC).</li>` : '')}${rw.on ? `<li>Premio Ladder: massimo ${rw.day} vittorie premiate nelle 24 ore e ${rw.pair} per avversario.</li>` : '<li>I premi in BC sono al momento sospesi.</li>'}${rw.wpa ? `<li>La vittoria è registrata come <b>match WPA ufficiale</b>: conta per Hall of Fame e Faction Wars. Per evitare accordi, una taglia vinta con un match Ladder si riscuote dopo ${rw.hold} ore e conta un solo match ufficiale al giorno per coppia.</li>` : ''}<li>Il pareggio e le partite oltre i limiti contano comunque per l'Elo.</li></ul>${rw.on ? `<p style="margin:10px 0 0"><b>Le tue vittorie premiate nelle ultime 24 ore:</b> ${rewardedToday}/${rw.day}</p>` : ''}</div>`, 'ladder');
      const f = document.getElementById('ldnew');
      /* tipo di sfida: le voci dipendono da quante taglie incassabili ha l'avversario (il database ricontrolla tutto) */
      const fillKinds = () => {
        const k = document.getElementById('ldk'); if (!k) return;
        const id = f.ldo.value, c = id ? claim(id) : 0, keep = k.value, nick = id ? esc(pn(id)) : '';
        k.innerHTML = !id ? '<option value="">Scegli prima il duellante…</option>' : `<option value="">Scegli il tipo di sfida…</option><option value="ladder">Ladder normale (Elo${rw.on ? ' e +' + rw.bc + ' BC' : ''}, nessuna taglia)</option>` +
          (c > 0 ? `<option value="bounty">Per la taglia (puoi incassare ${c} BC, nessun Elo)</option><option value="both">Ladder + taglia (Elo e ${c} BC)</option>` : '');
        if ([...k.options].some(o => o.value === keep)) k.value = keep;
        const h = document.getElementById('ldkh');
        if (h) h.innerHTML = !id ? '' : c > 0 ? `${nick} ha addosso ${val.get(id)} BC di taglie${own.get(id) ? `, di cui ${own.get(id)} tuoi (ti tornano indietro, non sono un guadagno)` : ''}: potresti incassarne ${c}.` : `${nick} non ha taglie che tu possa incassare: la sfida può essere solo una Ladder normale.`;
      };
      f.ldo.onchange = fillKinds; fillKinds();
      f.onsubmit = async e => { e.preventDefault(); const b = f.querySelector('button[type=submit]'); b.disabled = true;
        try {
          const a = { p_opponent: f.ldo.value, p_format: f.ldf.value, p_message: f.ldm.value || null, p_request_id: f.dataset.rq };
          const kn = document.getElementById('ldk'); if (kn) { if (!kn.value) throw new Error('Scegli il tipo di sfida'); a.p_kind = kn.value }
          await rpc('ladder_challenge', a); toast('Sfida lanciata: l\'avversario riceverà una notifica.'); BM.route() }
        catch (er) { toast(er.message, 1); b.disabled = false } };
      const sInp = document.getElementById('lds');
      sInp.oninput = () => { const t = sInp.value.trim().toLowerCase(); document.querySelectorAll('.ldr').forEach(r => r.hidden = !!t && !r.dataset.n.includes(t)) };
    } catch (er) { fail(er, 'ladder') }
  };

  /* ============================== FUNZIONI MOD ============================== */
  R.mod = async () => {
    const head = '<h1 class="t">Funzioni <em>Mod</em></h1><p class="sub">Strumenti per moderatori e amministratori: verificare le vittorie, decidere i match della Ladder, gestire le taglie, rimuovere un duellante. Ogni azione chiede una motivazione (o una conferma) ed è registrata nell\'audit. Nulla viene cancellato.</p>';
    if (!isStaff()) return shell('<div class="err">Area riservata a moderatori e amministratori.</div>', '');
    shell(head + loading, 'mod');
    try {
      const sb = BM.sb, me = BM.me, imMod = me.role === 'moderator';
      const [pm, evs, lad, bn] = await Promise.all([
        q(sb.from('matches').select('id,event_id,round,player_a,player_b,status,created_at,source').eq('status', 'pending').order('created_at', { ascending: false }).limit(100)),
        q(sb.from('events').select('id,name').limit(300)),
        on('ladder') ? q(sb.from('ladder_matches').select('*').in('status', ['pending', 'accepted', 'reported', 'disputed']).order('created_at', { ascending: false }).limit(80)) : Promise.resolve([]),
        q(sb.from('bounties').select('id,creator_id,target_id,amount,message,status,created_at').in('status', ['active', 'under_review']).order('created_at', { ascending: false }).limit(80))]);
      const en = Object.fromEntries(evs.map(e => [e.id, e.name]));
      const mine = m => imMod && (m.challenger_id === me.id || m.opponent_id === me.id || m.player_a === me.id || m.player_b === me.id);
      const rank = { disputed: 0, reported: 1, accepted: 2, pending: 3 };
      lad.sort((a, b) => rank[a.status] - rank[b.status]);
      const users = [...BM.P.values()].filter(u => u.id !== me.id).sort((a, b) => (b.suspended - a.suspended) || a.nickname.localeCompare(b.nickname));
      const protectedU = u => imMod && (u.role === 'admin' || u.role === 'moderator');
      const disputed = lad.filter(m => m.status === 'disputed').length;
      shell(`${head}
      <div class="box" style="margin-top:18px"><h2 style="margin-top:0">Match ufficiali da verificare (${pm.length})</h2><p class="mute" style="font-size:.9rem;margin-top:0">Scegli il vincitore dopo aver controllato il risultato. Una verifica non si modifica più e sblocca la riscossione delle taglie. Non puoi verificare un match in cui giochi tu.</p>
      ${pm.map(m => `<div class="row2"><div class="g">T${m.round} · ${esc(pn(m.player_a))} <span class="mute">vs</span> ${esc(pn(m.player_b))}<small>${esc(en[m.event_id] || 'evento')} · ${when(m.created_at)}</small></div>${mine(m) ? '<small class="mute">è un tuo match: lo verifica un collega</small>' : `<button class="btn sm" data-act="modWin" data-m="${m.id}" data-w="${m.player_a}">${esc(pn(m.player_a))} vince</button><button class="btn sm" data-act="modWin" data-m="${m.id}" data-w="${m.player_b}">${esc(pn(m.player_b))} vince</button>`}</div>`).join('') || empty('Nessun match in attesa di verifica.')}</div>
      ${on('ladder') ? `<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Ladder: match da gestire (${lad.length}${disputed ? ' · ' + disputed + ' contestati' : ''})</h2><p class="mute" style="font-size:.9rem;margin-top:0">Decidi il risultato dei match contestati o fermi, oppure annulla le sfide abbandonate. Il risultato deciso chiude il match (Elo, premio e match WPA come per una conferma normale).</p>${lad.map(m => lrow(m, mine(m) ? '<small class="mute">è un tuo match</small>' : (m.status === 'reported' || m.status === 'disputed' || m.status === 'accepted' ? `<select id="lar-${m.id}" aria-label="Esito">${outcomeOpts(m)}</select><button class="btn sm" data-act="ldAdmRes" data-c="${m.id}">Decidi</button>` : '') + `<button class="btn ghost sm" data-act="ldAdmVoid" data-c="${m.id}">Annulla</button>`)).join('') || empty('Nessun match da gestire.')}</div>` : '<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Ladder</h2><p class="mute" style="margin:0">La Ladder è al momento spenta: solo un amministratore può riattivarla.</p></div>'}
      <div class="box" style="margin-top:14px"><h2 style="margin-top:0">Taglie attive (${bn.length})</h2><p class="mute" style="font-size:.9rem;margin-top:0"><b>Revisione</b> sospende la riscossione sul bersaglio mentre controlli; <b>Annulla</b> chiude la taglia e restituisce al creatore solo i BC che aveva versato. ${imMod ? 'Non puoi gestire le taglie che hai creato o che ti riguardano.' : ''}</p>
      ${bn.map(b => `<div class="row2"><div class="g">${esc(pn(b.creator_id))} → ${esc(pn(b.target_id))}<small>${BC(b.amount)} · ${when(b.created_at)}${b.message ? ' · “' + esc(b.message) + '”' : ''}</small></div>${b.status === 'under_review' ? tag('in revisione', 'r') : ''}${imMod && (b.creator_id === me.id || b.target_id === me.id) ? '<small class="mute">ti riguarda</small>' : `<button class="btn ghost sm" data-act="review" data-b="${b.id}" data-on="${b.status === 'under_review' ? 0 : 1}">${b.status === 'under_review' ? 'Togli revisione' : 'Revisione'}</button><button class="btn ghost sm" data-act="cancelb" data-b="${b.id}">Annulla</button>`}</div>`).join('') || empty('Nessuna taglia attiva.')}</div>
      <div class="box" style="margin-top:14px"><h2 style="margin-top:0">Rimuovi un duellante</h2><p class="mute" style="font-size:.9rem;margin-top:0">La rimozione è una <b>sospensione</b>: l'account non può più agire e non si può sfidare, ma match, saldi e registro restano intatti e si può riattivare. ${imMod ? 'I moderatori non possono sospendere amministratori o altri moderatori.' : ''}</p>
      <input id="mus" type="search" placeholder="Cerca duellante…" aria-label="Cerca duellante" style="margin-bottom:8px">
      ${users.map(u => `<div class="row2 mur" data-n="${esc(u.nickname.toLowerCase())}">${av(u)}<div class="g">${esc(u.nickname)}<small>${ROLE[u.role] || u.role}${u.suspended ? ' · SOSPESO' : ''}</small></div>${protectedU(u) ? '<small class="mute">protetto</small>' : `<button class="btn ${u.suspended ? 'ghost' : 'danger'} sm" data-act="susp" data-u="${u.id}" data-on="${u.suspended ? 0 : 1}">${u.suspended ? 'Riattiva' : 'Rimuovi (sospendi)'}</button>`}</div>`).join('') || empty('Nessun altro utente.')}</div>`, 'mod');
      const inp = document.getElementById('mus');
      inp.oninput = () => { const t = inp.value.trim().toLowerCase(); document.querySelectorAll('.mur').forEach(r => r.hidden = !!t && !r.dataset.n.includes(t)) };
    } catch (er) {
      fail(/could not find|schema cache|invalid input value for enum/i.test(er.message) ? new Error('Funzioni Mod non disponibili: esegui la migrazione black-market-moderatore.sql') : er, 'mod');
    }
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
    modWin: async el => { if (!confirm(`Registrare la vittoria di ${pn(el.dataset.w)}? La verifica non si può modificare.`)) return; await rpc('mod_verify_match', { p_match: el.dataset.m, p_winner: el.dataset.w }); await done('Match verificato.') },
    avPick: async () => { const i = document.getElementById('avf'); if (i) i.click() },
    avDel: async () => { if (!confirm('Rimuovere la foto del profilo?')) return; await rpc('set_my_avatar_img', { p_img: null }).catch(er => { throw avErr(er) }); await BM.core(); toast('Foto rimossa.'); BM.route() },
    ldAcc: async el => { await rpc('ladder_respond', { p_id: el.dataset.c, p_accept: true }); await done('Sfida accettata: ora giocate e inviate il risultato.') },
    ldDec: async el => { if (!confirm('Rifiutare la sfida?')) return; await rpc('ladder_respond', { p_id: el.dataset.c, p_accept: false }); await done('Sfida rifiutata.') },
    ldCan: async el => { if (!confirm('Annullare la sfida?')) return; await rpc('ladder_cancel', { p_id: el.dataset.c }); await done('Sfida annullata.') },
    ldRep: async el => { const [r, sc] = document.getElementById('lr-' + el.dataset.c).value.split('|'); await rpc('ladder_report', { p_id: el.dataset.c, p_result: r, p_score: sc }); await done('Risultato inviato: ora deve confermarlo l\'avversario.') },
    ldConf: async el => { const r = await rpc('ladder_confirm', { p_id: el.dataset.c }); await done(`Risultato confermato. Elo: ${r.challenger_delta >= 0 ? '+' : ''}${r.challenger_delta} / ${r.opponent_delta >= 0 ? '+' : ''}${r.opponent_delta}.` + (r.reward > 0 ? ` Il vincitore riceve +${r.reward} BC.` : r.reward_note ? ` Nessun premio in BC: ${r.reward_note}.` : '') + (r.official_match ? ' Registrato come match WPA.' : '')) },
    ldDisp: async el => { const r = ask('Perché contesti il risultato? (almeno 5 caratteri)'); if (!r) return; await rpc('ladder_dispute', { p_id: el.dataset.c, p_reason: r }); await done('Contestazione inviata: deciderà un amministratore.') },
    ldPick: async el => { const f = document.getElementById('ldo'); if (f) { f.value = el.dataset.u; const ff = document.getElementById('ldf'); if (ff && el.dataset.f) ff.value = el.dataset.f; f.dispatchEvent(new Event('change')); f.scrollIntoView({ behavior: 'smooth', block: 'center' }); f.focus() } },
    ldAdmRes: async el => { const sel = document.getElementById('lar-' + el.dataset.c).value.split('|'); const r = ask('Motivazione della decisione:'); if (!r) return; const res = await rpc('admin_ladder_resolve', { p_id: el.dataset.c, p_result: sel[0], p_score: sel[1], p_reason: r }); await done('Match risolto e Elo aggiornato.' + (res.reward > 0 ? ` Premio di ${res.reward} BC al vincitore.` : '') + (res.official_match ? ' Registrato come match WPA.' : '')) },
    ldAdmVoid: async el => { if (!confirm('Annullare il match senza modificare l\'Elo?')) return; const r = ask('Motivazione dell\'annullamento:'); if (!r) return; await rpc('admin_ladder_void', { p_id: el.dataset.c, p_reason: r }); await done('Match annullato.') },
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
      const sb = BM.sb, anyOn = on('hall_of_fame') || on('faction_wars');
      const [ss, fs, mem, sm, ex, ch, au, lad] = await Promise.all([
        anyOn ? q(sb.from('seasons').select('*').order('starts_on', { ascending: false })) : [],
        on('faction_wars') ? q(sb.from('factions').select('*').order('created_at')) : [],
        on('faction_wars') ? q(sb.from('faction_members').select('user_id,faction_id').is('left_at', null)) : [],
        on('faction_wars') ? q(sb.from('faction_scored_matches_v').select('*').order('verified_at', { ascending: false }).limit(20)) : [],
        on('faction_wars') ? q(sb.from('faction_match_exclusions').select('*').order('created_at', { ascending: false }).limit(20)) : [],
        on('underground') ? q(sb.from('challenges_v').select('*').in('status', ['pending', 'accepted', 'in_progress']).order('created_at', { ascending: false }).limit(50)) : [],
        q(sb.from('audit_logs').select('*').in('action', ['set_module', 'create_season', 'create_faction', 'rename_faction', 'disband_faction', 'join_faction', 'leave_faction', 'kick_member', 'move_faction_member', 'transfer_leadership', 'update_faction', 'exclude_match_from_factions', 'include_match_in_factions', 'create_challenge', 'accept_challenge', 'decline_challenge', 'cancel_challenge', 'admin_cancel_challenge', 'link_challenge_match', 'complete_challenge', 'expire_challenges', 'ladder_challenge', 'ladder_accept', 'ladder_decline', 'ladder_cancel', 'ladder_report', 'ladder_confirm', 'ladder_dispute', 'admin_ladder_resolve', 'admin_ladder_void', 'ladder_expire']).order('id', { ascending: false }).limit(30)),
        on('ladder') ? q(sb.from('ladder_matches').select('*').in('status', ['pending', 'accepted', 'reported', 'disputed']).order('created_at', { ascending: false }).limit(60)) : []]);
      const act = fs.filter(f => f.status === 'active'), users = [...BM.P.values()].sort((a, b) => a.nickname.localeCompare(b.nickname));
      const fname = Object.fromEntries(fs.map(f => [f.id, f.name])), inF = new Set(mem.map(m => m.user_id));
      box.innerHTML = `<div class="box" style="margin-top:14px"><h2>Moduli aggiuntivi</h2><p class="mute" style="font-size:.92rem">Gli interruttori sono verificati anche dal database: a modulo spento le operazioni vengono rifiutate. Ogni cambio chiede una motivazione ed è registrato nell'audit.</p>
      ${MODS.concat([['heroes', 'La guerra degli Eroi', 'heroes']]).map(m => `<div class="row2"><div class="g">${m[1]}<small>${on(m[0]) ? 'Attivo: visibile a tutti gli utenti' : 'Disattivato: nascosto, operazioni bloccate'}</small></div>${tag(on(m[0]) ? 'attivo' : 'spento', on(m[0]) ? 'g' : '')}<button class="btn ${on(m[0]) ? 'ghost' : 'gold'} sm" data-act="modTog" data-m="${m[0]}" data-on="${on(m[0]) ? 0 : 1}">${on(m[0]) ? 'Disattiva' : 'Attiva'}</button></div>`).join('')}</div>
      ${anyOn ? `<div class="box" style="margin-top:14px"><h2>Stagioni</h2>${ss.map(s => `<div class="row2"><div class="g">${esc(s.name)}<small>${day(s.starts_on)} → ${day(s.ends_on)}</small></div></div>`).join('') || empty('Nessuna stagione definita.')}
        <form id="sn" class="row" style="margin-top:10px" onsubmit="return false"><input name="sname" placeholder="Nome stagione" required minlength="3" maxlength="40" style="flex:1;min-width:160px" aria-label="Nome stagione"><input name="sfrom" type="date" required aria-label="Inizio"><input name="sto" type="date" required aria-label="Fine"><button type="button" class="btn gold sm" data-act="seasonNew">Crea stagione</button></form><p class="mute" style="font-size:.88rem">Le stagioni non possono sovrapporsi e non si cancellano.</p></div>` : ''}
      ${on('faction_wars') ? `<div class="box" style="margin-top:14px"><h2>Fazioni</h2>${act.map(f => `<div class="row2"><div class="g"><a href="#/factions/${f.id}">${esc(f.name)}</a><small>${mem.filter(m => m.faction_id === f.id).length} membri</small></div><button class="btn ghost sm" data-act="afRename" data-f="${f.id}">Rinomina</button><button class="btn ghost sm" data-act="afDisband" data-f="${f.id}">Sciogli</button></div>`).join('') || empty('Nessuna fazione attiva.')}
        ${act.length ? `<div class="row" style="margin-top:10px"><select id="mvu" aria-label="Duellante"><option value="">Sposta duellante…</option>${users.map(u => `<option value="${u.id}">${esc(u.nickname)}${inF.has(u.id) ? ' (in una fazione)' : ''}</option>`).join('')}</select><select id="mvf" aria-label="Fazione di destinazione"><option value="">verso la fazione…</option>${act.map(f => `<option value="${f.id}">${esc(f.name)}</option>`).join('')}</select><button class="btn sm" data-act="afMove">Sposta</button></div>` : ''}</div>
        <div class="grid c2" style="margin-top:14px"><div class="box"><h2>Match che danno punti (ultimi 20)</h2>${sm.map(m => `<div class="row2"><div class="g">${esc(pn(m.winner_id))} → ${esc(fname[m.faction_id] || 'fazione')}<small>${day(m.verified_at)} · +${m.points}</small></div><button class="btn ghost sm" data-act="afExc" data-m="${m.match_id}">Escludi</button></div>`).join('') || empty('Nessuno.')}</div>
        <div class="box"><h2>Match esclusi dal punteggio</h2>${ex.map(x => `<div class="row2"><div class="g">${esc(x.reason)}<small>${day(x.created_at)}</small></div><button class="btn ghost sm" data-act="afInc" data-m="${x.match_id}">Reintegra</button></div>`).join('') || empty('Nessuna esclusione.')}</div></div>` : ''}
      ${on('ladder') ? `<div class="box" style="margin-top:14px"><h2>Ladder: match da gestire (${lad.length})</h2><p class="mute" style="font-size:.9rem;margin-top:0">Risolvi i contestati o i risultati fermi; annulla le sfide abbandonate. L'Elo cambia solo quando un match viene chiuso.</p>${lad.map(m => lrow(m, (m.status === 'reported' || m.status === 'disputed' || m.status === 'accepted' ? `<select id="lar-${m.id}" aria-label="Esito">${outcomeOpts(m)}</select><button class="btn sm" data-act="ldAdmRes" data-c="${m.id}">Risolvi</button>` : '') + `<button class="btn ghost sm" data-act="ldAdmVoid" data-c="${m.id}">Annulla</button>`)).join('') || empty('Nessun match da gestire.')}</div>` : ''}
      ${on('underground') ? `<div class="box" style="margin-top:14px"><h2>Moderazione sfide aperte (${ch.length})</h2>${ch.map(c => chRow(c, `<button class="btn ghost sm" data-act="acCan" data-c="${c.id}">Annulla</button>`)).join('') || empty('Nessuna sfida aperta.')}</div>` : ''}
      <div class="box" style="margin-top:14px"><h2>Audit dei moduli (ultimi 30)</h2>${au.map(a => `<div class="row2"><div class="g"><b>${esc(a.action)}</b> · ${esc(pn(a.actor_id))}<small>${when(a.created_at)}${a.reason ? ' · ' + esc(a.reason) : ''}</small></div></div>`).join('') || empty('Nessun evento registrato.')}</div>`;
      BM.foldify(box, { 'Moduli aggiuntivi': 'mod-switch', 'Stagioni': 'mod-seasons', 'Fazioni': 'mod-factions', 'Match che danno punti': 'mod-fscored', 'Match esclusi': 'mod-fexcl', 'Ladder: match da gestire': 'mod-ladder', 'Moderazione sfide': 'mod-chal', 'Audit dei moduli': 'mod-audit' });
    } catch (er) {
      box.innerHTML = `<div class="err" role="alert" style="margin-top:14px">Moduli aggiuntivi non disponibili: ${esc(er.message)}. Hai applicato la migrazione <b>black-market-moduli.sql</b>?</div>`;
    }
  };
};
