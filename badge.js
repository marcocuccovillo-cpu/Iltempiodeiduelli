/* =====================================================================
   BADGE DEL TEMPIO — grafica e testi dei traguardi (Black Market + Ladder).
   Condiviso da sentiero.html e da black-market.html (profilo e dashboard).
   I traguardi NON si decidono qui: li calcola il database (funzione badge_progress, migrazione 007)
   dai dati ufficiali. Questo file si limita a disegnarli e a dare loro un nome.
   Richiede la migrazione black-market-badge.sql.
   ===================================================================== */
(function () {
  'use strict';
  var TIER = ['', 'Bronzo', 'Argento', 'Oro', 'Leggenda', 'Unico'];
  var PTS = [0, 1, 3, 6, 10, 5];                       // punti Tempio per livello
  var GRADES = [[0, 'Novizio'], [6, 'Duellante'], [18, 'Veterano'], [40, 'Maestro'], [80, 'Campione'], [140, 'Leggenda del Tempio']];
  var AREAS = [['market', 'Black Market'], ['duel', 'Match ufficiali'], ['ladder', 'Ladder'], ['special', 'Speciali']];
  var n = function (v) { return Number(v || 0).toLocaleString('it-IT'); };
  var esc = function (s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] }); };

  /* Testi: nome per livello, traguardo, icona. "thr" serve solo all'anteprima da non iscritti: i valori veri arrivano dal database. */
  var FAM = {
    taglie:    { t: 'Taglie lanciate',      ic: 'scroll', names: ['Primo Contratto', 'Mercante di Teste', 'Signore delle Taglie', 'Re del Black Market'], thr: [1, 5, 15, 40], area: 'market',
                 d: function (v) { return v == 1 ? 'Metti la tua prima taglia' : 'Metti ' + n(v) + ' taglie'; } },
    riscosse:  { t: 'Taglie riscosse',      ic: 'coins',  names: ['Incassatore', 'Esattore', 'Cacciatore di Taglie', 'Spietato'], thr: [1, 5, 15, 30], area: 'market',
                 d: function (v) { return v == 1 ? 'Riscuoti la tua prima taglia' : 'Riscuoti ' + n(v) + ' taglie'; } },
    ricercato: { t: 'Taglie sulla tua testa', ic: 'skull', names: ['Ricercato', 'Pericolo Pubblico', 'Nemico del Mercato', 'Bersaglio Leggendario'], thr: [1, 5, 15, 30], area: 'market',
                 d: function (v) { return v == 1 ? 'Ricevi la tua prima taglia' : 'Ricevi ' + n(v) + ' taglie'; } },
    bottino:   { t: 'Bottino più grosso',   ic: 'gem',    names: ['Bottino', 'Grande Colpo', 'Jackpot'], thr: [100, 300, 600], area: 'market',
                 d: function (v) { return 'Riscuoti una taglia da almeno ' + n(v) + ' BC'; } },
    ufficiali: { t: 'Vittorie ufficiali',   ic: 'cup',    names: ['Battesimo del Fuoco', 'Veterano WPA', 'Campione WPA', 'Leggenda WPA'], thr: [1, 5, 15, 40], area: 'duel',
                 d: function (v) { return v == 1 ? 'Vinci il tuo primo match ufficiale' : 'Vinci ' + n(v) + ' match ufficiali'; } },
    serie:     { t: 'Serie di vittorie',    ic: 'flame',  names: ['Tripletta', 'Inarrestabile', 'Imbattibile'], thr: [3, 5, 8], area: 'duel',
                 d: function (v) { return 'Vinci ' + n(v) + ' match ufficiali di fila'; } },
    presenza:  { t: 'Presenze agli eventi', ic: 'temple', names: ['Presente', 'Habitué', 'Colonna del Tempio', 'Pilastro Eterno'], thr: [1, 5, 15, 30], area: 'duel',
                 d: function (v) { return v == 1 ? 'Partecipa al tuo primo evento' : 'Partecipa a ' + n(v) + ' eventi'; } },
    arena:     { t: 'Vittorie in Ladder',   ic: 'swords', names: ['Prima Scalata', 'Sfidante', 'Gladiatore', 'Signore dell’Arena'], thr: [1, 10, 30, 75], area: 'ladder',
                 d: function (v) { return v == 1 ? 'Vinci la tua prima partita di Ladder' : 'Vinci ' + n(v) + ' partite di Ladder'; } },
    elo:       { t: 'Elo massimo',          ic: 'crown',  names: ['Ascesa', 'Élite', 'Maestro dell’Arena', 'Leggenda della Ladder'], thr: [1100, 1200, 1350, 1500], area: 'ladder',
                 d: function (v) { return 'Raggiungi ' + n(v) + ' punti Elo'; } },
    furia:     { t: 'Furia in Ladder',      ic: 'bolt',   names: ['Scintilla', 'Furia', 'Tempesta'], thr: [3, 5, 8], area: 'ladder',
                 d: function (v) { return 'Vinci ' + n(v) + ' partite di Ladder di fila'; } },
    caccia:    { t: 'Caccia agli avversari', ic: 'target', names: ['Caccia Aperta', 'Spazzaterra', 'Flagello'], thr: [3, 8, 15], area: 'ladder',
                 d: function (v) { return 'Batti ' + n(v) + ' avversari diversi in Ladder'; } },
    giganti:   { t: 'Ammazzagiganti',       ic: 'peak',   names: ['Ammazzagiganti', 'Cacciatore di Titani', 'Rovina degli Dei'], thr: [1, 3, 10], area: 'ladder',
                 d: function (v) { return (v == 1 ? 'Batti' : 'Batti ' + n(v) + ' volte') + ' un avversario con almeno 100 Elo più di te'; } },
    rivincita: { t: 'Rivincite',            ic: 'redo',   names: ['Rivincita', 'Vendetta Servita Fredda'], thr: [1, 5], area: 'ladder',
                 d: function (v) { return v == 1 ? 'Batti chi ti aveva già battuto' : 'Batti ' + n(v) + ' volte chi ti aveva già battuto'; } },
    iniziato:  { t: 'Iniziato',             ic: 'eye',    names: ['Iniziato', '', '', '', 'Iniziato'], thr: [1], area: 'special', d: function () { return 'Entra nel Tempio: crea il tuo profilo'; } },
    doppia:    { t: 'Doppia Anima',         ic: 'duo',    names: ['Doppia Anima', '', '', '', 'Doppia Anima'], thr: [1], area: 'special', d: function () { return 'Vinci in Ladder e riscuoti una taglia: due mondi, un solo duellante'; } },
    custode:   { t: 'Custode del Tempio',   ic: 'guard',  names: ['Custode del Tempio', '', '', '', 'Custode del Tempio'], thr: [1], area: 'special', d: function () { return 'Fai parte dello staff del Tempio'; } }
  };

  /* Icone (24×24, tratto): disegnate a mano, nessuna dipendenza esterna */
  var IC = {
    scroll: '<path d="M7 3h9l3 3v15H7z"/><path d="M10 9h6M10 13h6M10 17h3"/><circle cx="16.5" cy="17.5" r="1.6" fill="currentColor"/>',
    coins:  '<ellipse cx="12" cy="7" rx="7" ry="3"/><path d="M5 7v4c0 1.7 3.1 3 7 3s7-1.3 7-3V7M5 11v4c0 1.7 3.1 3 7 3s7-1.3 7-3v-4"/>',
    skull:  '<path d="M12 3c-4.4 0-8 3-8 7.2 0 2.3 1.1 4.2 2.8 5.5V20h2.4v-2h1.6v2h2.4v-2h1.6v2h2.4v-4.3C18.9 14.4 20 12.5 20 10.2 20 6 16.4 3 12 3z"/><circle cx="9" cy="11" r="1.7" fill="currentColor"/><circle cx="15" cy="11" r="1.7" fill="currentColor"/><path d="M12 13.5l-1 2h2z" fill="currentColor"/>',
    gem:    '<path d="M6 3h12l4 6-10 12L2 9z"/><path d="M2 9h20M9 3l3 6 3-6M12 9v12"/>',
    cup:    '<path d="M7 4h10v5a5 5 0 0 1-10 0zM7 5.5H4v2A3 3 0 0 0 7 10.5M17 5.5h3v2a3 3 0 0 1-3 3M12 14v4M8 21h8M9.5 18h5v3h-5z"/>',
    flame:  '<path d="M12 2.5c.8 3.6 5.2 5.7 5.2 10.4a5.2 5.2 0 0 1-10.4 0c0-2.1 1-3.6 2.1-4.7.1 2 1 3 2 3 0-3.2-.9-5 1.1-8.7z"/><path d="M12 21c-1.6 0-2.8-1.2-2.8-2.8 0-1.4.9-2.2 1.6-3 .3 1 .8 1.4 1.4 1.4 1 0 1.9 1.1 1.9 2.2A2.1 2.1 0 0 1 12 21z" fill="currentColor"/>',
    temple: '<path d="M3 9l9-6 9 6zM5 11.5V18M9.7 11.5V18M14.3 11.5V18M19 11.5V18M3 20.5h18M4 18h16"/>',
    swords: '<path d="M5 19L19 5M15 5h4v4M7 13l4 4M19 19L5 5M9 5H5v4M17 13l-4 4"/>',
    crown:  '<path d="M3 18l1.6-10 5 4.8L12 5l2.4 7.8 5-4.8L21 18zM3 21h18"/>',
    bolt:   '<path d="M13.5 2L5 13.2h6l-1.2 8.8L19 10.3h-6z" fill="currentColor" fill-opacity=".25"/>',
    target: '<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="3.2"/><path d="M12 1.5v5M12 17.5v5M1.5 12h5M17.5 12h5"/>',
    peak:   '<path d="M2 20l7-12 4 6 3-4 6 10z"/><path d="M9 8V3.5l3 1.2-3 1.3"/>',
    redo:   '<path d="M20 12a8 8 0 1 1-3-6.2M20 4v5h-5"/><path d="M12 8l-3 4h6z" fill="currentColor"/>',
    eye:    '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3.2" fill="currentColor"/>',
    duo:    '<circle cx="9" cy="12" r="6"/><circle cx="15" cy="12" r="6"/>',
    guard:  '<path d="M12 2.5l8 3v6c0 5-3.4 8.8-8 10.5-4.6-1.7-8-5.5-8-10.5v-6z"/><path d="M12 8l1.4 2.9 3.1.4-2.3 2.1.6 3.1-2.8-1.6-2.8 1.6.6-3.1-2.3-2.1 3.1-.4z" fill="currentColor"/>'
  };

  /* Forme della medaglia per area: esterna, interna, ritaglio */
  var SH = {
    market:  { o: 'M50 3 L91 26.5 V73.5 L50 97 L9 73.5 V26.5 Z',                                   i: 'M50 11 L84 30.5 V69.5 L50 89 L16 69.5 V30.5 Z', c: 'hex' },
    duel:    { o: 'M50 3 L90 15 V50 C90 75 72 90 50 98 C28 90 10 75 10 50 V15 Z',                   i: 'M50 10 L83 20 V50 C83 71 68 84 50 91 C32 84 17 71 17 50 V20 Z', c: 'shield' },
    ladder:  { o: 'M33 3 H67 L97 33 V67 L67 97 H33 L3 67 V33 Z',                                    i: 'M35 10 H65 L90 35 V65 L65 90 H35 L10 65 V35 Z', c: 'oct' },
    special: { o: 'M50 3 a47 47 0 1 0 .01 0 Z',                                                    i: 'M50 11 a39 39 0 1 0 .01 0 Z', c: 'circ' }
  };
  var PLATE = { market: 'pm', duel: 'pd', ladder: 'pl', special: 'ps' };
  var ICCOL = ['', '#ffd9b3', '#f4f8ff', '#fff3b8', '#d9fdff', '#ffffff'];

  var CSS = '.tdb{width:96px;height:96px;display:block;flex:none;overflow:visible;transition:transform .25s,filter .25s}.tdb.md{width:72px;height:72px}.tdb.sm{width:56px;height:56px}.tdb.xs{width:42px;height:42px}.tdb.xl{width:150px;height:150px}' +
    '.tdb.on.t1{filter:drop-shadow(0 0 5px rgba(214,125,48,.55))}.tdb.on.t2{filter:drop-shadow(0 0 6px rgba(190,205,225,.55))}.tdb.on.t3{filter:drop-shadow(0 0 8px rgba(255,200,60,.7))}' +
    '.tdb.on.t4{filter:drop-shadow(0 0 10px rgba(120,230,255,.85)) drop-shadow(0 0 16px rgba(220,110,255,.55));animation:tdbp 2.8s ease-in-out infinite}.tdb.on.t5{filter:drop-shadow(0 0 9px rgba(190,240,255,.85)) drop-shadow(0 0 14px rgba(240,170,255,.5));animation:tdbp 3.4s ease-in-out infinite}' +
    '.tdb.off{filter:grayscale(1) brightness(.5) contrast(.95);opacity:.8}.tdb .sh{opacity:0}.tdb.on.t3 .sh,.tdb.on.t4 .sh,.tdb.on.t5 .sh{opacity:1;animation:tdbs 3.6s linear infinite}.tdb.on.t4 .sh,.tdb.on.t5 .sh{animation-duration:2.4s}' +
    '@keyframes tdbs{from{transform:translateX(-70px) skewX(-20deg)}60%,to{transform:translateX(170px) skewX(-20deg)}}@keyframes tdbp{50%{transform:scale(1.045)}}' +
    '.tdb-b{all:unset;box-sizing:border-box;cursor:pointer;display:inline-flex;flex-direction:column;align-items:center;gap:6px;border-radius:14px;padding:4px;text-align:center;color:inherit;-webkit-tap-highlight-color:transparent}.tdb-b:hover .tdb.on,.tdb-b:focus-visible .tdb.on{transform:translateY(-4px) scale(1.08) rotate(-2deg)}.tdb-b:focus-visible{outline:3px solid var(--ac,#00e5ff);outline-offset:2px}' +
    '.tdb-b small{font:600 .72rem/1.15 var(--ui,system-ui);color:var(--mu,#94a3b8);max-width:76px}.tdb-b.lk small{color:#64748b}' +
    '.tdb-sec{margin:26px 0 0}.tdb-sec>h3{font:700 1.05rem var(--disp,serif);color:var(--gold,#e8b84a);margin:0 0 12px;display:flex;align-items:center;gap:10px}.tdb-sec>h3::after{content:"";flex:1;height:1px;background:linear-gradient(90deg,var(--line,rgba(0,229,255,.2)),transparent)}' +
    '.tdb-g{display:grid;gap:12px;grid-template-columns:1fr}@media(min-width:700px){.tdb-g{grid-template-columns:1fr 1fr}}' +
    '.tdb-f{padding:14px;border:1px solid var(--line,rgba(0,229,255,.2));border-radius:14px;background:linear-gradient(160deg,rgba(19,34,74,.55),var(--surf,#0b1326))}.tdb-f.done{border-color:rgba(232,184,74,.55);box-shadow:0 0 22px rgba(232,184,74,.1)}' +
    '.tdb-f header{display:flex;justify-content:space-between;gap:8px;align-items:baseline;margin-bottom:8px}.tdb-f h4{margin:0;font:700 1rem var(--disp,serif)}.tdb-f header span{font:600 .8rem var(--ui,system-ui);color:var(--mu,#94a3b8)}' +
    '.tdb-t{display:flex;flex-wrap:wrap;gap:4px 2px;justify-content:flex-start}.tdb-nx{margin:8px 0 6px;font-size:.9rem;color:var(--mu,#94a3b8)}.tdb-nx b{color:var(--tx,#e2e8f0)}.tdb-f small.pr{color:var(--mu,#94a3b8)}.tdb-hid{margin:8px 0 0;font-size:.88rem;color:#8aa0b8}' +
    '.tdb-show{display:flex;flex-wrap:wrap;gap:6px 8px;align-items:flex-start}.tdb-new{display:inline-block;margin-left:4px;padding:0 6px;border-radius:99px;background:var(--gold,#e8b84a);color:#1a1204;font-size:.62rem;font-weight:800;letter-spacing:.06em;text-transform:uppercase;vertical-align:middle}' +
    '.tdb-sum{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin-bottom:12px}.tdb-sum b{font:700 1.3rem var(--disp,serif);color:var(--gold,#e8b84a)}.tdb-sum .bar{flex:1 1 160px;min-width:120px}' +
    '.tdb-m{position:fixed;inset:0;z-index:9999;background:rgba(0,0,0,.82);display:grid;place-items:center;padding:16px;overflow-y:auto}.tdb-mb{background:radial-gradient(120% 90% at 50% 0%,#162a5c,#0b1326 60%);border:1px solid var(--ac,#00e5ff);border-radius:18px;max-width:380px;width:100%;padding:24px 20px;text-align:center;box-shadow:0 0 50px rgba(0,229,255,.25)}' +
    '.tdb-mb .tdb{margin:0 auto 10px}.tdb-mb h2{font:700 1.4rem var(--disp,serif);margin:0 0 4px;color:#fff}.tdb-mb .tr{font:700 .78rem var(--ui,system-ui);letter-spacing:.14em;text-transform:uppercase;color:var(--ac2,#6ff0ff)}.tdb-mb p{color:var(--mu,#94a3b8);margin:10px 0}.tdb-mb .btn{margin-top:6px}' +
    '@media(prefers-reduced-motion:reduce){.tdb,.tdb .sh{animation:none!important;transition:none!important}}';

  var SPRITE = '<svg id="tdbSprite" width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false"><defs>' +
    '<linearGradient id="tdg1" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffcf9e"/><stop offset=".45" stop-color="#c8742f"/><stop offset="1" stop-color="#6b3510"/></linearGradient>' +
    '<linearGradient id="tdg2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff"/><stop offset=".45" stop-color="#b4c0cf"/><stop offset="1" stop-color="#5b6779"/></linearGradient>' +
    '<linearGradient id="tdg3" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff3b0"/><stop offset=".45" stop-color="#f1bf2f"/><stop offset="1" stop-color="#8c5d06"/></linearGradient>' +
    '<linearGradient id="tdg4" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7df9ff"/><stop offset=".5" stop-color="#b784ff"/><stop offset="1" stop-color="#ff7ad9"/></linearGradient>' +
    '<linearGradient id="tdg5" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff"/><stop offset=".4" stop-color="#a5f3fc"/><stop offset="1" stop-color="#f0abfc"/></linearGradient>' +
    '<radialGradient id="tdgpm" cx=".5" cy=".35" r=".75"><stop offset="0" stop-color="#7a1a38"/><stop offset="1" stop-color="#1a0610"/></radialGradient>' +
    '<radialGradient id="tdgpd" cx=".5" cy=".35" r=".75"><stop offset="0" stop-color="#1360a8"/><stop offset="1" stop-color="#04132a"/></radialGradient>' +
    '<radialGradient id="tdgpl" cx=".5" cy=".35" r=".75"><stop offset="0" stop-color="#6a33c8"/><stop offset="1" stop-color="#150833"/></radialGradient>' +
    '<radialGradient id="tdgps" cx=".5" cy=".35" r=".75"><stop offset="0" stop-color="#12896a"/><stop offset="1" stop-color="#03201a"/></radialGradient>' +
    '<linearGradient id="tdgsh" x1="0" x2="1"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff" stop-opacity=".75"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>' +
    '<clipPath id="tdc-hex"><path d="' + SH.market.o + '"/></clipPath><clipPath id="tdc-shield"><path d="' + SH.duel.o + '"/></clipPath><clipPath id="tdc-oct"><path d="' + SH.ladder.o + '"/></clipPath><clipPath id="tdc-circ"><path d="' + SH.special.o + '"/></clipPath>' +
    '</defs></svg>';

  function init() {
    if (document.getElementById('tdbCss')) return;
    var s = document.createElement('style'); s.id = 'tdbCss'; s.textContent = CSS; document.head.appendChild(s);
    var d = document.createElement('div'); d.innerHTML = SPRITE; document.body.appendChild(d.firstChild);
  }

  /* Nome, testo e icona di una riga del database */
  function meta(r) {
    var f = FAM[r.family] || { t: r.family, ic: 'eye', names: [], area: r.area, d: function (v) { return 'Obiettivo ' + v } };
    var nm = (f.names[r.tier - 1] || f.names[0] || r.code);
    return { name: nm, desc: f.d(r.threshold), fam: f.t, ic: f.ic, tier: TIER[r.tier] || '' };
  }

  /* La medaglia: SVG con rim del livello, piastra dell'area, icona, stelline e riflesso animato */
  function medal(r, size) {
    var m = meta(r), on = !!r.earned, a = SH[r.area] || SH.market, t = r.tier, pips = '';
    if (t < 5) for (var i = 0; i < t; i++) pips += '<path d="M0-3.3l.95 2.1 2.3.25-1.7 1.6.45 2.3L0 1.9l-2 1.35.45-2.3-1.7-1.6 2.3-.25z" fill="#fff2b8" stroke="rgba(0,0,0,.7)" stroke-width=".7" transform="translate(' + (50 + (i - (t - 1) / 2) * 10) + ' 79) scale(1.2)"/>';
    var wings = t >= 4 ? '<g fill="url(#tdg' + t + ')" opacity=".9"><path d="M6 38 L-5 30 L-1 46 L-6 55 L6 55Z"/><path d="M94 38 L105 30 L101 46 L106 55 L94 55Z"/></g>' : '';
    var ring = r.area === 'special' ? '<circle cx="50" cy="50" r="43" fill="none" stroke="url(#tdg' + t + ')" stroke-width="1.6" stroke-dasharray="1.5 4.2" stroke-linecap="round" opacity=".85"/>' : '<path d="' + a.i + '" fill="none" stroke="url(#tdg' + t + ')" stroke-width="1.1" opacity=".55" transform="translate(50 50) scale(.86) translate(-50 -50)"/>';
    return '<svg class="tdb t' + t + ' ' + (on ? 'on' : 'off') + (size ? ' ' + size : '') + '" viewBox="-8 -8 116 116" role="img" aria-label="' + esc(m.name + ' — ' + m.tier + (on ? '' : ' (bloccato)')) + '">' + wings +
      '<path d="' + a.o + '" fill="url(#tdg' + t + ')" stroke="rgba(0,0,0,.55)" stroke-width="1.2"/>' +
      '<path d="' + a.i + '" fill="url(#tdgp' + PLATE[r.area].slice(1) + ')" stroke="rgba(0,0,0,.6)" stroke-width="1.6"/>' + ring +
      '<g color="' + ICCOL[t] + '" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" transform="translate(29 24) scale(1.75)">' + (IC[m.ic] || '') + '</g>' + pips +
      '<g clip-path="url(#tdc-' + a.c + ')"><rect class="sh" x="-10" y="-5" width="30" height="110" fill="url(#tdgsh)"/></g></svg>';
  }

  /* Punti e grado */
  function summary(rows) {
    var pts = 0, ok = 0, tot = 0;
    rows.forEach(function (r) { if (r.hidden) return; tot++; if (r.earned) { ok++; pts += PTS[r.tier] || 0; } });
    var gi = 0; GRADES.forEach(function (g, i) { if (pts >= g[0]) gi = i; });
    var nx = GRADES[gi + 1];
    return { pts: pts, earned: ok, total: tot, grade: GRADES[gi][1], next: nx ? nx[1] : null, toNext: nx ? nx[0] - pts : 0,
             pct: nx ? Math.min(100, (pts - GRADES[gi][0]) / (nx[0] - GRADES[gi][0]) * 100) : 100 };
  }

  var NEW_MS = 7 * 86400000;
  var isNew = function (r) { return r.earned && r.earned_at && Date.now() - new Date(r.earned_at).getTime() < NEW_MS; };
  var day = function (d) { return d ? new Date(d).toLocaleDateString('it-IT', { day: '2-digit', month: 'long', year: 'numeric' }) : ''; };

  function btn(r, size, label) {
    var m = meta(r);
    return '<button type="button" class="tdb-b' + (r.earned ? '' : ' lk') + '" data-bd="' + esc(r.code) + '" aria-label="' + esc(m.name + ', ' + m.tier + (r.earned ? ', ottenuto' : ', bloccato')) + '">' + medal(r, size) + (label ? '<small>' + esc(m.name) + (isNew(r) ? '<span class="tdb-new">nuovo</span>' : '') + '</small>' : '') + '</button>';
  }

  /* Vetrina: i badge più alti ottenuti (per il profilo e la dashboard) */
  function showcase(rows, max, size) {
    var e = rows.filter(function (r) { return r.earned; }).sort(function (a, b) { return (b.tier === 5 ? 3.5 : b.tier) - (a.tier === 5 ? 3.5 : a.tier) || (b.threshold - a.threshold) || (a.sort - b.sort); });
    if (!e.length) return '<p class="mute" style="margin:0">Nessun badge ancora: i traguardi si sbloccano giocando match ufficiali, mettendo e riscuotendo taglie, e sfidando in Ladder.</p>';
    var shown = e.slice(0, max || 8), more = e.length - shown.length;
    return '<div class="tdb-show">' + shown.map(function (r) { return btn(r, size || 'md', true) }).join('') + '</div>' + (more > 0 ? '<p class="mute" style="margin:8px 0 0;font-size:.9rem">…e altri ' + more + '.</p>' : '');
  }

  function sumBox(s) {
    return '<div class="tdb-sum"><div><span class="mute" style="font-size:.85rem">Grado</span><br><b>' + esc(s.grade) + '</b></div><div style="flex:1 1 160px;min-width:140px"><div class="bar"><i style="width:' + s.pct + '%"></i></div><small class="mute">' + n(s.pts) + ' punti Tempio · ' + s.earned + '/' + s.total + ' badge' + (s.next ? ' · ' + n(s.toNext) + ' al grado ' + esc(s.next) : ' · grado massimo') + '</small></div></div>';
  }

  /* Il muro dei traguardi, per area e famiglia */
  function wall(rows, filter) {
    var fams = {}, order = [];
    rows.forEach(function (r) { if (!fams[r.family]) { fams[r.family] = []; order.push(r.family) } fams[r.family].push(r) });
    var out = '';
    AREAS.forEach(function (ar) {
      var cards = order.filter(function (f) { return fams[f][0].area === ar[0] }).map(function (f) {
        var rs = fams[f].sort(function (a, b) { return a.tier - b.tier }), got = rs.filter(function (r) { return r.earned }), hid = rs[0].hidden, nx = rs.filter(function (r) { return !r.earned })[0], fm = FAM[f] || { t: f };
        if (filter === 'got' && !got.length) return '';
        if (filter === 'todo' && !nx) return '';
        var shown = filter === 'got' ? got : rs;
        var prog = '';
        if (hid) prog = '<p class="tdb-hid">' + (rs[0].area === 'ladder' ? 'La Ladder non è attiva: i suoi traguardi tornano visibili quando verrà riaccesa.' : 'Visibile solo al diretto interessato e allo staff.') + '</p>';
        else if (nx) prog = '<p class="tdb-nx">Prossimo: <b>' + esc(meta(nx).name) + '</b> — ' + esc(meta(nx).desc) + '</p><div class="bar"><i style="width:' + Math.min(100, nx.value / nx.threshold * 100) + '%"></i></div><small class="pr">' + n(Math.min(nx.value, nx.threshold)) + ' / ' + n(nx.threshold) + '</small>';
        else prog = '<p class="tdb-nx"><b>Famiglia completata.</b> Hai sbloccato ogni livello.</p>';
        return '<article class="tdb-f' + (!nx && !hid ? ' done' : '') + '"><header><h4>' + esc(fm.t) + '</h4><span>' + got.length + '/' + rs.length + '</span></header><div class="tdb-t">' + shown.map(function (r) { return btn(r, 'md', true) }).join('') + '</div>' + prog + '</article>';
      }).join('');
      if (cards) out += '<section class="tdb-sec"><h3>' + ar[1] + '</h3><div class="tdb-g">' + cards + '</div></section>';
    });
    return out || '<p class="mute">Nessun traguardo in questa vista.</p>';
  }

  /* I traguardi più vicini */
  function nextUp(rows, max) {
    var fam = {};
    rows.forEach(function (r) { if (r.hidden || r.earned) return; if (!fam[r.family] || r.tier < fam[r.family].tier) fam[r.family] = r; });
    var l = Object.keys(fam).map(function (k) { return fam[k] }).filter(function (r) { return r.value > 0 }).sort(function (a, b) { return b.value / b.threshold - a.value / a.threshold }).slice(0, max || 4);
    if (!l.length) return '';
    return l.map(function (r) { var m = meta(r); return '<div class="it" style="gap:12px;justify-content:flex-start;flex-wrap:nowrap"><button type="button" class="tdb-b lk" data-bd="' + esc(r.code) + '" aria-label="' + esc(m.name) + '">' + medal(r, 'xs') + '</button><div style="flex:1;min-width:0"><b>' + esc(m.name) + '</b> <span class="mute">· ' + esc(m.tier) + '</span><br><small class="mute">' + esc(m.desc) + '</small><div class="bar" style="margin-top:6px"><i style="width:' + Math.min(100, r.value / r.threshold * 100) + '%"></i></div></div><span class="mute" style="white-space:nowrap">' + n(Math.min(r.value, r.threshold)) + '/' + n(r.threshold) + '</span></div>' }).join('');
  }

  /* Scheda di dettaglio (tocco su una medaglia) */
  function detail(r) {
    var m = meta(r), md = document.createElement('div'), prog = '';
    md.className = 'tdb-m'; md.setAttribute('role', 'dialog'); md.setAttribute('aria-modal', 'true'); md.setAttribute('aria-label', m.name);
    if (r.hidden) prog = '<p>Non disponibile in questo momento.</p>';
    else if (r.earned) prog = '<p><b style="color:var(--gold,#e8b84a)">Ottenuto</b>' + (r.earned_at ? ' il ' + esc(day(r.earned_at)) : '') + '</p>';
    else prog = '<p>Progresso: <b style="color:#fff">' + n(Math.min(r.value, r.threshold)) + ' / ' + n(r.threshold) + '</b></p><div class="bar"><i style="width:' + Math.min(100, r.value / r.threshold * 100) + '%"></i></div>';
    md.innerHTML = '<div class="tdb-mb">' + medal(r, 'xl') + '<div class="tr">' + esc(m.tier) + ' · ' + esc(m.fam) + '</div><h2>' + esc(m.name) + '</h2><p>' + esc(m.desc) + '</p>' + prog + '<button type="button" class="btn ghost">Chiudi</button></div>';
    document.body.appendChild(md);
    var c = md.querySelector('.btn'); c.focus();
    function close() { md.remove(); document.removeEventListener('keydown', k) }
    function k(e) { if (e.key === 'Escape') close() }
    c.onclick = close; md.onclick = function (e) { if (e.target === md) close() }; document.addEventListener('keydown', k);
  }

  /* Collega i tocchi sulle medaglie di un contenitore alla scheda di dettaglio */
  function bind(root, getRows) {
    root.addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('[data-bd]'); if (!b || !root.contains(b)) return;
      var r = getRows().filter(function (x) { return x.code === b.dataset.bd })[0]; if (r) detail(r);
    });
  }

  /* Legge i progressi dal database; richiede la migrazione 007 */
  function load(sb, userId) {
    return sb.rpc('badge_progress', userId ? { p_user: userId } : {}).then(function (res) {
      if (res.error) { var m = res.error.message || ''; throw new Error(/could not find the function|schema cache/i.test(m) ? 'Badge non attivi: l’amministratore deve eseguire la migrazione black-market-badge.sql' : m) }
      return res.data || [];
    });
  }

  /* Anteprima per chi non ha ancora un accesso: tutti i traguardi, bloccati */
  function preview() {
    var rows = [], sortN = 0;
    Object.keys(FAM).forEach(function (k) {
      var f = FAM[k];
      f.thr.forEach(function (th, i) { rows.push({ code: k + '_' + (i + 1), family: k, area: f.area, tier: f.area === 'special' ? 5 : i + 1, metric: '', kind: 'count', threshold: th, value: 0, earned: false, earned_at: null, hidden: false, sort: sortN++ }) });
    });
    return rows;
  }

  window.TDB = { init: init, medal: medal, meta: meta, summary: summary, showcase: showcase, sumBox: sumBox, wall: wall, nextUp: nextUp, detail: detail, bind: bind, load: load, preview: preview, FAM: FAM, TIER: TIER, PTS: PTS };
})();
