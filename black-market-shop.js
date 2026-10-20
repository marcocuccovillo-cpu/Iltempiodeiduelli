/* =====================================================================
   BLACK MARKET SHOP — spendi i Black Credits (BC) in premi permanenti da esporre sul profilo.
   Caricato da black-market.html dopo black-market-moduli.js e shop-art.js.
   Non tocca Most Wanted, taglie, wallet o Ladder: usa solo le funzioni della migrazione 008
   (shop_buy, shop_equip, shop_unequip, admin_shop_save_item). Prezzi, saldo e proprietà sono
   decisi SOLO dal database: qui si mostrano e si chiede; il server può rifiutare.
   ===================================================================== */
window.BM_SHOP = function (BM) {
  'use strict';
  const { R, shell, q, rpc, toast, esc, BC, when, av, pn, ask } = BM;
  const T = window.TDS;
  if (!T) { console.error('shop-art.js non caricato: Shop disattivato'); return }
  T.init();
  const isAdm = () => BM.me && BM.me.role === 'admin';
  const num = n => Number(n || 0).toLocaleString('it-IT');
  const day = d => new Date(d).toLocaleDateString('it-IT', { day: '2-digit', month: 'short', year: 'numeric' });
  const loading = '<p class="mute" role="status">Caricamento…</p>';
  const RANGE = { common: [2, 49], rare: [50, 149], epic: [150, 349], legendary: [350, 699], mythic: [700, 1000] };
  const rname = r => (T.RAR[r] || [r])[0], rcol = r => (T.RAR[r] || [0, '#9aa4b2'])[1];
  const rord = r => T.RARS.indexOf(r);

  /* ---------- stato dei filtri (solo comodità: si perde senza conseguenze) ---------- */
  const DEF = { tab: 'cat', cat: 'all', rar: 'all', max: 1000, sort: 'price', buy: false };
  let st = { ...DEF };
  try { Object.assign(st, JSON.parse(sessionStorage.getItem('bm.shop') || '{}')) } catch (e) { }
  const save = () => { try { sessionStorage.setItem('bm.shop', JSON.stringify(st)) } catch (e) { } };

  /* ---------- stile ---------- */
  const css = document.createElement('style');
  css.textContent = `
.sh-top{display:grid;gap:14px;margin-top:18px}@media(min-width:760px){.sh-top{grid-template-columns:1.1fr 1fr}}
.sh-bal{display:flex;align-items:center;gap:16px;flex-wrap:wrap}.sh-bal .big{margin:0}
.sh-filters{display:grid;gap:10px;margin:14px 0}.sh-filters .row{gap:10px;flex-wrap:wrap;align-items:center}
.sh-filters label{font-size:.82rem;color:var(--mu);display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.sh-filters select{min-height:44px}.sh-filters input[type=range]{width:min(220px,60vw);min-height:0;accent-color:var(--gold)}
.sh-grid{display:grid;gap:14px;grid-template-columns:repeat(auto-fill,minmax(min(100%,270px),1fr));margin-top:6px}
.sh-card{display:flex;flex-direction:column;gap:8px;background:var(--surf);border:1px solid var(--line);border-top:3px solid var(--rc,#9aa4b2);border-radius:14px;padding:12px;min-width:0;position:relative}
.sh-card h3{margin:0;font:700 1.08rem var(--disp);color:var(--tx);overflow-wrap:anywhere}
.sh-card p{margin:0;color:var(--mu);font-size:.9rem;line-height:1.4;flex:1}
.sh-card.r-epic{box-shadow:0 0 0 1px rgba(180,107,255,.18),0 8px 26px -14px rgba(180,107,255,.6)}
.sh-card.r-legendary{box-shadow:0 0 0 1px rgba(255,176,46,.22),0 8px 28px -12px rgba(255,176,46,.7)}
.sh-card.r-mythic{box-shadow:0 0 0 1px rgba(255,61,110,.35),0 10px 36px -10px rgba(255,61,110,.85),0 0 40px -18px rgba(124,58,237,.9);background:linear-gradient(180deg,#1a0d18,var(--surf) 55%)}
.sh-card.r-mythic .sh-pv{background:radial-gradient(90% 100% at 50% 20%,rgba(255,46,99,.22),rgba(5,1,12,.85))}
.sh-card.off{opacity:.55;filter:saturate(.6)}
.sh-meta{display:flex;gap:6px;flex-wrap:wrap}.sh-meta .tag{flex:none}
.sh-foot{display:flex;gap:8px;align-items:center;flex-wrap:wrap;justify-content:space-between;margin-top:4px}
.sh-price{font:700 1.25rem var(--disp);color:var(--gold)}
.sh-foot .btn,.sh-foot .tag{min-height:44px;display:inline-flex;align-items:center}
.sh-foot .tag{padding:0 12px}
.sh-eqtag{position:absolute;top:10px;right:10px;background:var(--gold);color:#16120a;font-size:.68rem;font-weight:800;padding:3px 9px;border-radius:99px;letter-spacing:.06em;text-transform:uppercase;z-index:3}
.sh-sec{margin:22px 0 8px;display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}.sh-sec h2{margin:0}
.sh-slots{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px;margin-top:12px}
.sh-slot{border:1px dashed var(--line);border-radius:10px;padding:8px 10px;font-size:.82rem;color:var(--mu);min-width:0}.sh-slot b{display:block;color:var(--tx);overflow-wrap:anywhere}
.sh-modal{position:fixed;inset:0;z-index:300;background:rgba(0,0,0,.72);display:grid;place-items:center;padding:16px;overflow:auto}
.sh-dlg{background:var(--surf);border:1px solid var(--gold);border-radius:16px;padding:18px;width:min(440px,100%);max-height:calc(100dvh - 32px);overflow:auto;box-shadow:0 20px 60px #000}
.sh-dlg h2{margin:0 0 4px}.sh-dlg .sh-pv{margin:10px 0}
.sh-sum{border:1px solid var(--line);border-radius:10px;overflow:hidden;margin:12px 0}.sh-sum div{display:flex;justify-content:space-between;gap:10px;padding:9px 12px;border-bottom:1px solid var(--line)}.sh-sum div:last-child{border:0;background:var(--raise);font-weight:700}
.sh-sum .neg{color:#ff8b8b}.sh-sum .pos{color:#7ee0a0}
.sh-dlg .row{gap:10px;flex-wrap:wrap}.sh-dlg .btn{flex:1;min-height:46px}
.sh-fxbtn{font-size:.82rem}
.sh-adm table{width:100%;border-collapse:collapse}.sh-form{display:grid;gap:10px;grid-template-columns:repeat(auto-fit,minmax(200px,1fr))}.sh-form label{display:grid;gap:4px;font-size:.82rem;color:var(--mu)}.sh-form .wide{grid-column:1/-1}.sh-form textarea{min-height:70px}
@media(max-width:420px){.sh-foot{flex-direction:column;align-items:stretch}.sh-foot .btn,.sh-foot .tag{justify-content:center}}
`;
  document.head.appendChild(css);

  /* ---------- dati ---------- */
  const eqOf = async uid => T.eqMap(await q(BM.sb.from('shop_equipped_v').select('*').eq('user_id', uid)));
  async function load() {
    const [items, mine, eq] = await Promise.all([
      q(BM.sb.from('shop_items').select('*').order('sort').order('price')),
      q(BM.sb.from('shop_purchases').select('*').eq('user_id', BM.me.id).order('created_at', { ascending: false })),
      eqOf(BM.me.id)]);
    return { items, owned: new Map(mine.map(p => [p.item_id, p])), eq, byId: new Map(items.map(i => [i.id, i])) };
  }
  const open = () => BM.S.shop_enabled === 1;

  /* ---------- hook per il resto del Black Market ---------- */
  BM.shopEq = async uid => { try { return await eqOf(uid) } catch (e) { return {} } };
  BM.shopHead = (p, eq, o) => T.head(p, eq, o);
  BM.navItems = (prev => () => [...(prev ? prev() : []), ...(BM.S.shop_enabled !== undefined ? [['shop', 'Shop']] : [])])(BM.navItems);

  /* ---------- schede ---------- */
  function state(it, D) {
    if (D.owned.has(it.id)) return 'owned';
    if (!it.active) return 'off';
    return 'buy';
  }
  function card(it, D, mode) {
    const s = state(it, D), p = D.owned.get(it.id), eqd = D.eq[it.category] && D.eq[it.category].item_id === it.id;
    const can = open() && BM.wallet >= it.price, lack = it.price - BM.wallet;
    let foot;
    if (s === 'owned') foot = `<span class="tag g">Posseduto</span>${eqd ? `<button class="btn ghost" data-act="shUneq" data-c="${it.category}">Rimuovi dal profilo</button>` : `<button class="btn gold" data-act="shEq" data-i="${it.id}">Equipaggia</button>`}`;
    else if (s === 'off') foot = `<span class="sh-price">${num(it.price)} <small>BC</small></span><span class="tag">Non disponibile</span>`;
    else foot = `<span class="sh-price">${num(it.price)} <small>BC</small></span>${!open() ? '<span class="tag">Shop chiuso</span>' : can ? `<button class="btn gold" data-act="shBuy" data-i="${it.id}">Acquista</button>` : `<button class="btn ghost" disabled aria-disabled="true">Ti mancano ${num(lack)} BC</button>`}`;
    const status = s === 'owned' ? '' : s === 'off' ? '' : can ? '<span class="tag g">Acquistabile</span>' : '<span class="tag r">Saldo insufficiente</span>';
    return `<article class="sh-card r-${it.rarity} ${s === 'off' ? 'off' : ''}" style="--rc:${rcol(it.rarity)}" data-item="${esc(it.id)}">
${eqd ? '<span class="sh-eqtag">Equipaggiato</span>' : ''}${T.preview(it)}
<div class="sh-meta"><span class="tag" style="color:${rcol(it.rarity)};border-color:${rcol(it.rarity)}">${rname(it.rarity)}</span><span class="tag">${T.CATN[it.category] || it.category}</span>${status}</div>
<h3>${esc(it.name)}</h3><p>${esc(it.description)}</p>
${mode === 'own' && p ? `<small class="mute">Acquistato il ${day(p.created_at)} · pagato ${BC(p.price_paid)}</small>` : ''}
<div class="sh-foot">${foot}</div></article>`;
  }

  /* ---------- pagina ---------- */
  const seg = (key, cur, opts) => `<div class="seg" style="flex-wrap:wrap">${opts.map(([v, l]) => `<button data-act="shSet" data-k="${key}" data-v="${v}" aria-pressed="${String(cur) === String(v)}">${l}</button>`).join('')}</div>`;
  const tabs = () => seg('tab', st.tab, [['cat', 'Catalogo'], ['own', 'La mia collezione'], ...(isAdm() ? [['adm', 'Gestione catalogo']] : [])]);

  R.shop = async () => {
    if (BM.S.shop_enabled === undefined) { shell('<h1 class="t">Black Market <em>Shop</em></h1><div class="box" style="margin-top:18px"><h2>Shop non ancora attivato</h2><p>Manca la migrazione del database. Un amministratore deve eseguire <b>black-market-shop.sql</b> in Supabase (dopo le migrazioni precedenti).</p></div>', 'shop'); return }
    if (st.tab === 'adm' && !isAdm()) st.tab = 'cat';
    let D;
    try { D = await load() } catch (er) { shell(`<div class="err" role="alert">Shop non disponibile: ${esc(er.message)}. Hai applicato la migrazione <b>black-market-shop.sql</b>?</div>`, 'shop'); return }
    const total = D.items.filter(i => i.active).length, nown = D.owned.size;
    const head = `<h1 class="t">Black Market <em>Shop</em></h1><p class="sub">Spendi i tuoi Black Credits in premi permanenti: restano tuoi per sempre e si mostrano sul profilo. Nessun denaro reale, nessuno scambio tra utenti.</p>
<div class="sh-top"><div class="box"><div class="sh-bal"><div><p class="mute" style="margin:0">Il tuo saldo</p><div class="big" id="sh-bal">${num(BM.wallet)} <small>BC</small></div></div><div class="mute" style="font-size:.88rem;flex:1;min-width:150px">${nown} ${nown === 1 ? 'premio' : 'premi'} nella collezione · ${total} nel catalogo${open() ? '' : '<br><b style="color:var(--ac2)">Acquisti chiusi al momento</b>'}</div></div>
<div class="row" style="margin-top:12px"><button class="btn ghost sm sh-fxbtn" data-act="shFx" aria-pressed="${T.fxOn()}">Animazioni: ${T.fxOn() ? 'accese' : 'spente (versione statica)'}</button></div></div>
<div class="box"><h2 style="margin-top:0">Come funziona</h2><p class="mute" style="margin:0;font-size:.92rem">Scegli un premio, conferma il costo e il saldo che ti resta. L'acquisto è definitivo e immediato. Puoi equipaggiare un premio per categoria e cambiarlo quando vuoi senza perderlo.</p></div></div>
<div style="margin-top:18px">${tabs()}</div>`;
    let body = '';
    if (st.tab === 'cat') body = catalogue(D);
    else if (st.tab === 'own') body = collection(D);
    else body = await adminTab(D);
    shell(head + body, 'shop');
  };

  function catalogue(D) {
    let list = D.items.filter(i => (st.cat === 'all' || i.category === st.cat) && (st.rar === 'all' || i.rarity === st.rar) && i.price <= st.max && (!st.buy || (i.active && !D.owned.has(i.id) && open() && BM.wallet >= i.price)));
    const rk = { price: (a, b) => a.price - b.price, priced: (a, b) => b.price - a.price, rar: (a, b) => rord(b.rarity) - rord(a.rarity) || b.price - a.price, name: (a, b) => a.name.localeCompare(b.name) }[st.sort] || ((a, b) => a.price - b.price);
    list = [...list].sort((a, b) => (a.active === b.active ? 0 : a.active ? -1 : 1) || rk(a, b));
    return `<div class="sh-filters"><div class="row">${seg('cat', st.cat, [['all', 'Tutte'], ...T.CATS])}</div>
<div class="row"><label>Rarità <select data-shf="rar" aria-label="Filtra per rarità"><option value="all">Tutte</option>${T.RARS.map(r => `<option value="${r}" ${st.rar === r ? 'selected' : ''}>${rname(r)} (${RANGE[r][0]}–${RANGE[r][1]} BC)</option>`).join('')}</select></label>
<label>Prezzo fino a <b id="sh-maxv" style="color:var(--gold)">${num(st.max)} BC</b> <input type="range" min="2" max="1000" step="1" value="${st.max}" data-shf="max" aria-label="Prezzo massimo"></label>
<label>Ordina <select data-shf="sort" aria-label="Ordina"><option value="price" ${st.sort === 'price' ? 'selected' : ''}>Prezzo crescente</option><option value="priced" ${st.sort === 'priced' ? 'selected' : ''}>Prezzo decrescente</option><option value="rar" ${st.sort === 'rar' ? 'selected' : ''}>Rarità</option><option value="name" ${st.sort === 'name' ? 'selected' : ''}>Nome</option></select></label>
<label style="color:var(--tx)"><input type="checkbox" data-shf="buy" ${st.buy ? 'checked' : ''} style="width:22px;min-height:0"> Solo acquistabili ora</label>
<button class="btn ghost sm" data-act="shReset">Azzera filtri</button></div></div>
<p class="mute" style="margin:0 0 10px">${list.length} ${list.length === 1 ? 'premio' : 'premi'}</p>
<div class="sh-grid">${list.map(i => card(i, D)).join('') || '<div class="box">Nessun premio con questi filtri.</div>'}</div>`;
  }

  function collection(D) {
    const mine = [...D.owned.values()].map(p => ({ p, it: D.byId.get(p.item_id) })).filter(x => x.it);
    const preview = T.head(BM.me, D.eq, { avatar: av(BM.me).replace('class="av"', 'class="av xl"'), h: 'h2', tag: `<span class="tag">${esc({ user: 'Duellante', organizer: 'Organizzatore', moderator: 'Moderatore', admin: 'Amministratore' }[BM.me.role] || '')}</span>` });
    const slots = T.CATS.map(([c, l]) => `<div class="sh-slot">${l}<b>${D.eq[c] ? esc(D.eq[c].name) : 'vuoto'}</b></div>`).join('');
    const spent = [...D.owned.values()].reduce((t, p) => t + p.price_paid, 0);
    let sections = '';
    T.CATS.forEach(([c, l]) => {
      const xs = mine.filter(x => x.it.category === c).sort((a, b) => rord(b.it.rarity) - rord(a.it.rarity) || new Date(b.p.created_at) - new Date(a.p.created_at));
      if (xs.length) sections += `<div class="sh-sec"><h2>${l}</h2><span class="mute">${xs.length} · uno slot equipaggiabile</span></div><div class="sh-grid">${xs.map(x => card(x.it, D, 'own')).join('')}</div>`;
    });
    return `<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Il tuo profilo, così come lo vedono gli altri</h2><div style="margin-top:12px">${preview}</div><div class="sh-slots">${slots}</div>
<p class="mute" style="font-size:.88rem;margin:12px 0 0">${mine.length} premi · ${BC(spent)} spesi in totale. Rimuovere un premio dal profilo non lo fa sparire: resta nella tua collezione.</p></div>
${sections || '<div class="box" style="margin-top:14px"><h2>La tua collezione è vuota</h2><p>Visita il catalogo: i premi più economici partono da 2 BC.</p><button class="btn gold" data-act="shSet" data-k="tab" data-v="cat">Vai al catalogo</button></div>'}`;
  }

  /* ---------- conferma d'acquisto ---------- */
  function modal(html) {
    closeModal();
    const m = document.createElement('div'); m.className = 'sh-modal'; m.id = 'sh-modal';
    m.innerHTML = `<div class="sh-dlg" role="dialog" aria-modal="true" aria-labelledby="sh-t">${html}</div>`;
    m.addEventListener('click', e => { if (e.target === m && !m.dataset.busy) closeModal() });
    document.body.appendChild(m); document.addEventListener('keydown', escKey);
    const f = m.querySelector('button.btn.gold,button'); if (f) f.focus();
    return m;
  }
  const escKey = e => { if (e.key === 'Escape') { const m = document.getElementById('sh-modal'); if (m && !m.dataset.busy) closeModal() } };
  function closeModal() { const m = document.getElementById('sh-modal'); if (m) m.remove(); document.removeEventListener('keydown', escKey) }

  async function buyDialog(id) {
    const items = await q(BM.sb.from('shop_items').select('*').eq('id', id));
    const it = items[0];
    if (!it || !it.active) { toast('Questo premio non è più disponibile.', 1); return BM.route() }
    const rq = crypto.randomUUID();           // una richiesta per apertura: ripetere il clic non addebita due volte
    const after = BM.wallet - it.price;
    const m = modal(`<h2 id="sh-t">Conferma acquisto</h2><p class="mute" style="margin:0">${esc(it.name)} · ${rname(it.rarity)} · ${T.CATN[it.category]}</p>${T.preview(it)}<p style="margin:0;font-size:.92rem">${esc(it.description)}</p>
<div class="sh-sum"><div><span>Costo</span><span>${BC(it.price)}</span></div><div><span>Saldo attuale</span><span>${BC(BM.wallet)}</span></div><div><span>Saldo dopo l'acquisto</span><span class="${after < 0 ? 'neg' : 'pos'}">${BC(after)}</span></div></div>
<p class="mute" style="font-size:.85rem;margin:0 0 12px">L'acquisto è definitivo e il premio resta tuo per sempre.</p><div id="sh-msg" role="alert"></div>
<div class="row"><button class="btn ghost" data-m="x">Annulla</button><button class="btn gold" data-m="ok" ${after < 0 || !open() ? 'disabled' : ''}>Conferma e paga ${BC(it.price)}</button></div>`);
    m.querySelector('[data-m=x]').onclick = closeModal;
    const ok = m.querySelector('[data-m=ok]');
    ok.onclick = async () => {
      if (m.dataset.busy) return; m.dataset.busy = '1'; ok.disabled = true; ok.textContent = 'Attendi…';
      try {
        const r = await rpc('shop_buy', { p_item: it.id, p_request_id: rq, p_expected_price: it.price });
        await BM.core();
        m.querySelector('.sh-dlg').innerHTML = `<h2 id="sh-t">${r.already ? 'Già registrato' : 'Acquisto completato'}</h2>${T.preview(it)}<p style="margin:0">${esc(it.name)} è nella tua collezione.</p>
<div class="sh-sum"><div><span>Pagato</span><span>${BC(r.price)}</span></div><div><span>Nuovo saldo</span><span>${BC(r.balance)}</span></div></div>
<div class="row"><button class="btn ghost" data-m="x">Chiudi</button><button class="btn gold" data-m="eq">Equipaggia ora</button></div>`;
        delete m.dataset.busy;
        m.querySelector('[data-m=x]').onclick = () => { closeModal(); BM.route() };
        m.querySelector('[data-m=eq]').onclick = async e => { e.target.disabled = true; try { await rpc('shop_equip', { p_item: it.id }); toast(`${it.name} equipaggiato.`) } catch (er) { toast(er.message, 1) } closeModal(); BM.route() };
      } catch (er) {
        delete m.dataset.busy; ok.disabled = false; ok.textContent = `Riprova a pagare ${BC(it.price)}`;
        const bad = /prezzo/i.test(er.message);
        m.querySelector('#sh-msg').innerHTML = `<div class="err" style="margin-bottom:10px">${esc(er.message)}</div>`;
        if (bad) { ok.disabled = true; setTimeout(() => { closeModal(); BM.route() }, 1800) }
      }
    };
  }

  /* ---------- amministrazione ---------- */
  async function adminTab(D) {
    const [pur, aud] = await Promise.all([
      q(BM.sb.from('shop_purchases').select('*').order('created_at', { ascending: false }).limit(60)),
      q(BM.sb.from('audit_logs').select('*').eq('entity', 'shop_item').order('id', { ascending: false }).limit(40))]);
    const sold = {}; pur.forEach(p => { sold[p.item_id] = (sold[p.item_id] || 0) + 1 });
    const cnt = await q(BM.sb.from('shop_purchases').select('item_id,price_paid'));
    const tot = {}; let rev = 0; cnt.forEach(p => { tot[p.item_id] = (tot[p.item_id] || 0) + 1; rev += p.price_paid });
    const auditRow = a => {
      const o = a.old_value || {}, n = a.new_value || {}, diff = [];
      if (o.price != null && n.price != null && o.price !== n.price) diff.push(`prezzo ${o.price} → ${n.price}`);
      if (o.rarity && n.rarity && o.rarity !== n.rarity) diff.push(`rarità ${o.rarity} → ${n.rarity}`);
      if (o.asset && n.asset && o.asset !== n.asset) diff.push(`asset ${o.asset} → ${n.asset}`);
      if (o.name && n.name && o.name !== n.name) diff.push('nome');
      if (o.description && n.description && o.description !== n.description) diff.push('descrizione');
      const lab = { shop_item_create: 'Creato', shop_item_update: 'Modificato', shop_item_activate: 'Riattivato', shop_item_deactivate: 'Disattivato' }[a.action] || a.action;
      return `<div class="row2"><div class="g"><b>${lab}</b> · ${esc(a.entity_id)}<small>${esc(pn(a.actor_id))} · ${when(a.created_at)}${diff.length ? ' · ' + esc(diff.join(', ')) : ''}${a.reason ? ' · ' + esc(a.reason) : ''}</small></div></div>`;
    };
    return `<div class="box sh-adm" style="margin-top:14px"><h2 style="margin-top:0">Gestione catalogo</h2>
<p class="mute" style="font-size:.9rem">Ogni modifica chiede una motivazione ed è nel registro di audit. I premi già acquistati non si cancellano e le transazioni concluse non cambiano: modificare un prezzo vale solo per i nuovi acquisti. Disattivare un premio lo toglie dalla vendita, non dagli inventari.</p>
<div class="row" style="gap:10px;flex-wrap:wrap;align-items:center"><span class="tag ${open() ? 'g' : 'r'}">${open() ? 'Acquisti aperti' : 'Acquisti chiusi'}</span><button class="btn ghost sm" data-act="shOpen" data-on="${open() ? 0 : 1}">${open() ? 'Chiudi gli acquisti' : 'Riapri gli acquisti'}</button><span class="mute" style="font-size:.88rem">${cnt.length} acquisti · ${BC(rev)} spesi dagli utenti</span></div></div>
<div class="box" style="margin-top:14px"><h2 style="margin-top:0">Premi (${D.items.length})</h2>${D.items.map(i => `<div class="row2"><div class="g"><b style="color:var(--tx)">${esc(i.name)}</b><small>${esc(i.id)} · ${T.CATN[i.category]} · asset ${esc(i.asset)} · ${tot[i.id] || 0} acquisti</small></div><span class="tag" style="color:${rcol(i.rarity)};border-color:${rcol(i.rarity)}">${rname(i.rarity)}</span><span class="val">${BC(i.price)}</span><span class="tag ${i.active ? 'g' : ''}">${i.active ? 'in vendita' : 'disattivato'}</span><button class="btn ghost sm" data-act="shEdit" data-i="${esc(i.id)}">Modifica</button><button class="btn ghost sm" data-act="shActive" data-i="${esc(i.id)}" data-on="${i.active ? 0 : 1}">${i.active ? 'Disattiva' : 'Attiva'}</button></div>`).join('')}</div>
<div class="box" style="margin-top:14px" id="sh-formbox"><h2 style="margin-top:0" id="sh-ft">Nuovo premio</h2>${form(null)}</div>
<div class="grid c2" style="margin-top:14px"><div class="box"><h2 style="margin-top:0">Ultimi acquisti</h2>${pur.map(p => `<div class="row2"><div class="g"><b style="color:var(--tx)">${esc(p.item_name)}</b><small>${esc(pn(p.user_id))} · ${when(p.created_at)}</small></div><span class="val">${BC(p.price_paid)}</span></div>`).join('') || '<p class="mute">Nessun acquisto.</p>'}</div>
<div class="box"><h2 style="margin-top:0">Storico modifiche</h2>${aud.map(auditRow).join('') || '<p class="mute">Nessuna modifica registrata.</p>'}</div></div>`;
  }
  const assetOpts = (cat, cur) => (T.ASSETS[cat] || []).map(a => `<option value="${a}" ${cur === a ? 'selected' : ''}>${a}</option>`).join('');
  function form(it) {
    const e = !!it, v = it || { id: '', name: '', description: '', category: 'pet', rarity: 'common', price: 10, asset: '', active: true, sort: 100 };
    return `<form id="sh-form" class="sh-form" onsubmit="return false"><label>Codice (a-z, 0-9, _)<input name="id" value="${esc(v.id)}" required pattern="[a-z0-9_]{3,40}" ${e ? 'readonly' : ''}></label>
<label>Nome<input name="name" value="${esc(v.name)}" required minlength="2" maxlength="40"></label>
<label>Categoria<select name="category" ${e ? 'disabled' : ''}>${T.CATS.map(([c, l]) => `<option value="${c}" ${v.category === c ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
<label>Rarità<select name="rarity">${T.RARS.map(r => `<option value="${r}" ${v.rarity === r ? 'selected' : ''}>${rname(r)} (${RANGE[r][0]}–${RANGE[r][1]} BC)</option>`).join('')}</select></label>
<label>Prezzo in BC<input name="price" type="number" min="2" max="1000" value="${v.price}" required></label>
<label>Asset grafico<select name="asset">${assetOpts(v.category, v.asset)}${v.asset && !(T.ASSETS[v.category] || []).includes(v.asset) ? `<option value="${esc(v.asset)}" selected>${esc(v.asset)}</option>` : ''}</select></label>
<label>Ordine<input name="sort" type="number" min="0" max="9999" value="${v.sort}"></label>
<label style="display:flex;gap:8px;align-items:center;color:var(--tx)"><input name="active" type="checkbox" ${v.active ? 'checked' : ''} style="width:22px;min-height:0">In vendita</label>
<label class="wide">Descrizione (5–240 caratteri)<textarea name="description" required minlength="5" maxlength="240">${esc(v.description)}</textarea></label>
<div class="wide row" style="gap:10px"><button type="button" class="btn gold" data-act="shSave">${e ? 'Salva modifiche' : 'Crea premio'}</button>${e ? '<button type="button" class="btn ghost" data-act="shNew">Annulla modifica</button>' : ''}</div></form>`;
  }

  /* ---------- azioni ---------- */
  const done = async msg => { if (msg) toast(msg); await BM.core(); BM.route() };
  const ACT = {
    shSet: el => { st[el.dataset.k] = el.dataset.v; save(); BM.route() },
    shReset: () => { st = { ...DEF, tab: st.tab }; save(); BM.route() },
    shFx: () => { T.setFx(!T.fxOn()); BM.route() },
    shBuy: el => buyDialog(el.dataset.i),
    shEq: async el => { await rpc('shop_equip', { p_item: el.dataset.i }); await done('Equipaggiato: lo vedranno tutti sul tuo profilo.') },
    shUneq: async el => { await rpc('shop_unequip', { p_category: el.dataset.c }); await done('Rimosso dal profilo: resta nella tua collezione.') },
    shOpen: async el => { const on = el.dataset.on === '1', r = ask(on ? 'Motivazione della riapertura degli acquisti:' : 'Motivazione della chiusura degli acquisti:'); if (!r) return; await rpc('admin_set_setting', { p_key: 'shop_enabled', p_value: on ? 1 : 0, p_reason: r }); await done(on ? 'Acquisti riaperti.' : 'Acquisti chiusi.') },
    shEdit: async el => { const it = (await q(BM.sb.from('shop_items').select('*').eq('id', el.dataset.i)))[0]; if (!it) return; const b = document.getElementById('sh-formbox'); b.querySelector('#sh-ft').textContent = 'Modifica: ' + it.name; b.querySelector('form').outerHTML = form(it); bindForm(); b.scrollIntoView({ behavior: 'smooth', block: 'start' }) },
    shNew: () => BM.route(),
    shActive: async el => {
      const it = (await q(BM.sb.from('shop_items').select('*').eq('id', el.dataset.i)))[0]; if (!it) return;
      const on = el.dataset.on === '1', r = ask(on ? 'Motivazione della riattivazione:' : 'Motivazione della disattivazione (gli inventari non cambiano):'); if (!r) return;
      await rpc('admin_shop_save_item', { p_id: it.id, p_name: it.name, p_description: it.description, p_category: it.category, p_rarity: it.rarity, p_price: it.price, p_asset: it.asset, p_active: on, p_sort: it.sort, p_reason: r });
      await done(on ? 'Premio rimesso in vendita.' : 'Premio disattivato: chi lo possiede lo conserva.');
    },
    shSave: async () => {
      const f = document.getElementById('sh-form'); if (!f.reportValidity()) return;
      const r = ask('Motivazione (resterà nell\'audit):'); if (!r) return;
      await rpc('admin_shop_save_item', { p_id: f.id.value.trim(), p_name: f.name.value.trim(), p_description: f.description.value.trim(), p_category: f.category.value, p_rarity: f.rarity.value, p_price: parseInt(f.price.value, 10), p_asset: f.asset.value, p_active: f.active.checked, p_sort: parseInt(f.sort.value || '100', 10), p_reason: r });
      await done('Premio salvato.');
    }
  };
  function bindForm() {
    const f = document.getElementById('sh-form'); if (!f) return;
    f.category.addEventListener('change', () => { f.asset.innerHTML = assetOpts(f.category.value, '') });
  }
  const prev = BM.act;
  BM.act = async (a, el) => { if (ACT[a]) { await ACT[a](el); return true } return prev ? prev(a, el) : false };

  /* filtri: cambiano al volo senza ricaricare i dati dal server */
  const onF = e => {
    const t = e.target, k = t && t.dataset && t.dataset.shf; if (!k) return;
    if (e.type === 'input' && k !== 'max') return;
    if (k === 'max') { st.max = parseInt(t.value, 10) || 1000; const l = document.getElementById('sh-maxv'); if (l) l.textContent = num(st.max) + ' BC'; if (e.type === 'input') return }
    else if (k === 'buy') st.buy = t.checked; else st[k] = t.value;
    save(); BM.route();
  };
  document.addEventListener('change', onF); document.addEventListener('input', onF);
  /* una piccola scorciatoia: il modulo di amministrazione del form si aggancia dopo ogni disegno */
  new MutationObserver(() => bindForm()).observe(document.getElementById('app') || document.body, { childList: true });
};
