/* =====================================================================
   BLACK MARKET SHOP — 60 PREMI AGGIUNTIVI (grafica originale in SVG/CSS)
   Pet, cornici, aure, emblemi, effetti e titoli a tema Yu-Gi-Oh!-fantasy e fantasy puro.
   Tutti i disegni sono originali: nessuna carta, personaggio o marchio reale.
   File autonomo: non dipende da shop-art.js e non lo modifica.
     SHOP_EXTRA.items            → i 60 premi (chiave, nome, categoria, rarità, prezzo, descrizione)
     SHOP_EXTRA.svg(chiave, o)   → SVG 120×120 del premio (pet, cornice, aura, emblema, effetto); o = {anim:true|false}
     SHOP_EXTRA.title(chiave, testo) → HTML del titolo con il suo stile
     SHOP_EXTRA.init()           → inserisce gli stili (una volta sola)
   Le animazioni si spengono con «anim:false» e con l'impostazione «riduci movimento» del dispositivo.
   ===================================================================== */
(function () {
  'use strict';
  var N = 0;
  var esc = function (s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] }); };
  var rnd = function (i) { var x = Math.sin(i * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };

  var CSS = '.xa{width:100%;height:100%;display:block;overflow:visible}' +
    '.xa .spin{transform-origin:60px 60px;animation:xaSpin 16s linear infinite}.xa .spinr{transform-origin:60px 60px;animation:xaSpin 26s linear infinite reverse}' +
    '.xa .pulse{transform-origin:60px 60px;animation:xaPulse 3.2s ease-in-out infinite}.xa .float{animation:xaFloat 3.6s ease-in-out infinite}' +
    '.xa .flick{animation:xaFlick 1.3s ease-in-out infinite alternate}.xa .tw{animation:xaTw 2.4s ease-in-out infinite}' +
    '.xa .fall{animation:xaFall 3.4s linear infinite}.xa .drift{animation:xaDrift 4.2s ease-in-out infinite alternate}' +
    '.xa .blink{transform-box:fill-box;transform-origin:center;animation:xaBlink 4.5s infinite}' +
    '@keyframes xaSpin{to{transform:rotate(360deg)}}@keyframes xaPulse{50%{transform:scale(1.07);opacity:.82}}' +
    '@keyframes xaFloat{50%{transform:translateY(-3px)}}@keyframes xaFlick{from{opacity:.35}to{opacity:1}}' +
    '@keyframes xaTw{0%,100%{opacity:.15;transform:scale(.6)}50%{opacity:1;transform:scale(1.1)}}' +
    '@keyframes xaFall{from{transform:translate(0,-30px);opacity:0}15%{opacity:1}85%{opacity:1}to{transform:translate(8px,140px);opacity:0}}' +
    '@keyframes xaDrift{from{transform:translateX(-4px)}to{transform:translateX(4px)}}' +
    '@keyframes xaBlink{0%,93%,100%{transform:scaleY(1)}96%{transform:scaleY(.1)}}' +
    '.xa.st *,.xa.st{animation:none!important}.xa.st .tw{opacity:.8;transform:none}' +
    '@media(prefers-reduced-motion:reduce){.xa *{animation:none!important}}' +
    '.xt{font-family:var(--disp,Cinzel,serif);font-weight:700;letter-spacing:.06em;-webkit-background-clip:text;background-clip:text;color:transparent;-webkit-text-fill-color:transparent;display:inline-block}' +
    '.xt.sh{animation:xaTs 4s linear infinite;background-size:220% 100%}@keyframes xaTs{to{background-position:-220% 0}}@media(prefers-reduced-motion:reduce){.xt.sh{animation:none}}';
  function init() {
    if (typeof document === 'undefined' || document.getElementById('xaCss')) return;
    var s = document.createElement('style'); s.id = 'xaCss'; s.textContent = CSS; document.head.appendChild(s);
  }

  /* ---------- piccoli attrezzi per disegnare ---------- */
  function lin(id, a, b, c, d) { return '<linearGradient id="' + id + '" x1="0" y1="0" x2="' + (d ? 0 : 1) + '" y2="1"><stop offset="0" stop-color="' + a + '"/>' + (c ? '<stop offset=".5" stop-color="' + b + '"/><stop offset="1" stop-color="' + c + '"/>' : '<stop offset="1" stop-color="' + b + '"/>') + '</linearGradient>'; }
  function rad(id, a, b, c) { return '<radialGradient id="' + id + '" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="' + a + '"/>' + (c ? '<stop offset=".6" stop-color="' + b + '"/><stop offset="1" stop-color="' + c + '" stop-opacity="0"/>' : '<stop offset="1" stop-color="' + b + '" stop-opacity="0"/>') + '</radialGradient>'; }
  function star(x, y, r, fill, cls, delay) { var p = ''; for (var i = 0; i < 8; i++) { var a = i * Math.PI / 4 - Math.PI / 2, rr = i % 2 ? r * .38 : r; p += (i ? 'L' : 'M') + (x + Math.cos(a) * rr).toFixed(1) + ' ' + (y + Math.sin(a) * rr).toFixed(1); } return '<path d="' + p + 'Z" fill="' + fill + '"' + (cls ? ' class="' + cls + '" style="transform-box:fill-box;transform-origin:center;animation-delay:' + (delay || 0) + 's"' : '') + '/>'; }
  function eye(x, y, r, col, glow) { return '<circle cx="' + x + '" cy="' + y + '" r="' + (r * 1.9) + '" fill="' + glow + '" opacity=".45" class="flick"/><ellipse cx="' + x + '" cy="' + y + '" rx="' + r + '" ry="' + r * .8 + '" fill="' + col + '" class="blink"/><ellipse cx="' + x + '" cy="' + y + '" rx="' + r * .25 + '" ry="' + r * .7 + '" fill="#1a0008"/>'; }
  function ring(r, w, stroke, extra) { return '<circle cx="60" cy="60" r="' + r + '" fill="none" stroke="' + stroke + '" stroke-width="' + w + '"' + (extra || '') + '/>'; }
  function spokes(n, r1, r2, stroke, w, extra) { var p = ''; for (var i = 0; i < n; i++) { var a = i * 2 * Math.PI / n; p += 'M' + (60 + Math.cos(a) * r1).toFixed(1) + ' ' + (60 + Math.sin(a) * r1).toFixed(1) + 'L' + (60 + Math.cos(a) * r2).toFixed(1) + ' ' + (60 + Math.sin(a) * r2).toFixed(1); } return '<path d="' + p + '" fill="none" stroke="' + stroke + '" stroke-width="' + w + '" stroke-linecap="round"' + (extra || '') + '/>'; }
  function polar(n, r, fn) { var o = ''; for (var i = 0; i < n; i++) { var a = i * 2 * Math.PI / n - Math.PI / 2; o += fn(60 + Math.cos(a) * r, 60 + Math.sin(a) * r, a * 180 / Math.PI + 90, i); } return o; }

  /* ---------- il catalogo: chiave, categoria, rarità, prezzo, nome, descrizione ---------- */
  var I = [];
  function add(k, c, r, p, n, d, t) { I.push({ key: k, cat: c, rarity: r, price: p, name: n, desc: d, title: t || null }); }
  /* PET */
  add('xp_pipistrello', 'pet', 'comune', 39, 'Pipistrello Runico', 'Un pipistrello notturno con una runa che pulsa sul petto: ti segue ovunque sul profilo.');
  add('xp_golem', 'pet', 'comune', 47, 'Golem di Cristallo', 'Un piccolo golem di cristallo azzurro, testardo e brillante. Non cade mai.');
  add('xp_volpe', 'pet', 'raro', 117, 'Volpe delle Nove Code', 'Nove code di fuoco fatuo e un sorriso furbo: la compagna dei duellanti più astuti.');
  add('xp_cavaliere', 'pet', 'raro', 131, 'Cavaliere d’Argento', 'Un minuscolo cavaliere in armatura d’argento che veglia sul tuo profilo con la spada sguainata.');
  add('xp_lupo', 'pet', 'raro', 143, 'Lupo delle Tempeste', 'Il pelo carico di elettricità e gli occhi di ghiaccio: ulula quando arriva il temporale.');
  add('xp_grifone', 'pet', 'epico', 227, 'Grifone d’Oro', 'Testa d’aquila, corpo di leone e ali di luce dorata. Un guardiano fiero e leale.');
  add('xp_sfinge', 'pet', 'epico', 263, 'Sfinge del Deserto Eterno', 'Custodisce enigmi vecchi di mille anni: chi non li risolve resta fuori dal tempio.');
  add('xp_idra', 'pet', 'epico', 319, 'Idra a Tre Teste', 'Tre teste, tre sguardi, nessuna pietà. Tagliane una e il tuo profilo ne guadagna altre due.');
  add('xp_drago_cremisi', 'pet', 'leggendario', 489, 'Drago dell’Alba Cremisi', 'Un drago rosso come il cielo prima della battaglia, con ali di brace e artigli d’ossidiana.');
  add('xp_cerbero', 'pet', 'leggendario', 566, 'Cerbero degli Inferi', 'Tre teste e tre criniere di fiamma viola: sorveglia le porte del Tempio più oscuro.');
  add('xp_leviatano', 'pet', 'leggendario', 649, 'Leviatano Etereo', 'Un serpente marino di luce e nebbia che nuota nell’aria sopra il tuo nome.');
  add('xp_arcidemone', 'pet', 'mitico', 799, 'Arcidemone Cornuto', 'Corna d’ebano, ali di pipistrello e occhi d’oro fuso: un signore del caos in miniatura.');
  add('xp_drago_cosmico', 'pet', 'mitico', 949, 'Drago Cosmico del Vuoto', 'Il suo corpo è un pezzo di notte stellata. Dove passa, le costellazioni si spostano.');
  add('xp_ouroboros', 'pet', 'divino', 2500, 'Ouroboros Cosmico', 'Il drago che morde la propria coda: un anello infinito di stelle, il companion più raro del Tempio.');
  /* CORNICI */
  add('xf_rovi', 'frame', 'comune', 29, 'Cornice di Rovi e Spine', 'Rovi neri con spine e boccioli cremisi attorno al tuo avatar.');
  add('xf_rune', 'frame', 'raro', 89, 'Cornice Runica', 'Un anello di rune d’argento che si accendono una dopo l’altra.');
  add('xf_ghiaccio', 'frame', 'raro', 129, 'Cornice di Ghiaccio Eterno', 'Cristalli di ghiaccio azzurro che non si sciolgono mai.');
  add('xf_drago', 'frame', 'epico', 199, 'Cornice Draconica', 'Scaglie di drago bronzo con quattro artigli che stringono l’avatar.');
  add('xf_fulmini', 'frame', 'epico', 279, 'Cornice di Fulmini', 'Un anello di archi elettrici che scoccano lungo il bordo.');
  add('xf_millennio', 'frame', 'leggendario', 459, 'Cornice del Millennio Dorato', 'Oro massiccio, gemme e un occhio ornamentale in alto: la cornice dei collezionisti.');
  add('xf_infernale', 'frame', 'leggendario', 599, 'Cornice delle Fiamme Infere', 'Fiamme rosso-viola che salgono lungo l’anello e non si spengono.');
  add('xf_siderale', 'frame', 'mitico', 849, 'Cornice Siderale', 'Un anello di stelle e pianeti in orbita attorno al tuo avatar.');
  add('xf_vuoto', 'frame', 'mitico', 979, 'Cornice del Vuoto', 'Una crepa nello spazio: il bordo del tuo avatar si piega verso il nulla.');
  add('xf_eclissi', 'frame', 'divino', 1800, 'Cornice dell’Eclissi Divina', 'Un’eclissi totale con corona di luce e raggi dorati: la cornice più prestigiosa del Tempio.');
  /* AURE */
  add('xa_braci', 'aura', 'comune', 44, 'Aura di Braci', 'Piccole braci calde che salgono lente attorno al profilo.');
  add('xa_druidica', 'aura', 'raro', 99, 'Aura Druidica', 'Foglie e luci verdi che danzano come in una foresta antica.');
  add('xa_gelida', 'aura', 'raro', 139, 'Aura Gelida', 'Un respiro di gelo azzurro con cristalli che ruotano piano.');
  add('xa_tempesta', 'aura', 'epico', 189, 'Aura Tempestosa', 'Nubi scure e lampi viola attorno a te: la tempesta ti appartiene.');
  add('xa_sacra', 'aura', 'epico', 299, 'Aura Sacra', 'Un alone dorato con raggi di luce che ruotano come un’aureola.');
  add('xa_infernale', 'aura', 'leggendario', 419, 'Aura Infernale', 'Un anello di fiamme rosso-viola che ruggisce attorno al profilo.');
  add('xa_astrale', 'aura', 'leggendario', 679, 'Aura Astrale', 'Un velo di aurora boreale e stelle cadenti, in tutti i colori della notte.');
  add('xa_caos', 'aura', 'mitico', 739, 'Aura del Caos', 'Vortici magenta e turchesi che si inseguono senza regole.');
  add('xa_galattica', 'aura', 'mitico', 989, 'Aura Galattica', 'Una piccola galassia a spirale ruota attorno al tuo profilo.');
  add('xa_singolarita', 'aura', 'divino', 2200, 'Aura della Singolarità', 'Un buco nero con disco di accrescimento e luce piegata: l’aura definitiva.');
  /* EMBLEMI */
  add('xe_guardiano', 'emblem', 'comune', 19, 'Rune del Guardiano', 'Lo scudo con tre rune: il simbolo di chi difende il Tempio.');
  add('xe_mago', 'emblem', 'comune', 33, 'Sigillo del Mago', 'Un esagramma d’argento con una gemma al centro.');
  add('xe_spada', 'emblem', 'raro', 69, 'Spada e Scudo', 'Una spada incrociata a uno scudo: l’emblema di chi non arretra.');
  add('xe_occhio', 'emblem', 'raro', 119, 'Occhio Ierofante', 'Un occhio dorato in un triangolo, simbolo dei veggenti.');
  add('xe_stella', 'emblem', 'epico', 169, 'Stella del Duellante', 'Una stella a quattro punte incisa nel metallo blu.');
  add('xe_corona', 'emblem', 'epico', 239, 'Corona Spezzata', 'Una corona d’oro crepata: chi la porta ha perso un regno e ne ha conquistato un altro.');
  add('xe_ali', 'emblem', 'leggendario', 389, 'Ali dell’Araldo', 'Due grandi ali bianche attorno a una gemma celeste.');
  add('xe_teschio', 'emblem', 'leggendario', 529, 'Teschio Coronato', 'Un teschio con corona e occhi di brace: il re dei morti non dimentica.');
  add('xe_drago', 'emblem', 'mitico', 719, 'Sigillo del Drago Antico', 'Un drago che si avvolge su sé stesso dentro un cerchio di rune.');
  add('xe_infinito', 'emblem', 'mitico', 899, 'Emblema dell’Infinito', 'Il segno dell’infinito, luminoso e senza fine, su un disco di notte.');
  /* TITOLI */
  add('xt_cacciatore', 'title', 'comune', 35, 'Cacciatore di Draghi', 'Il titolo di chi ha già affrontato qualcosa di più grosso di lui.', { a: '#ffb36b', b: '#ff6b35', g: 'rgba(255,120,50,.45)' });
  add('xt_custode', 'title', 'raro', 79, 'Custode delle Rune', 'Per chi conosce i segni antichi e li protegge.', { a: '#cfe3ff', b: '#8fb4ff', g: 'rgba(140,180,255,.5)' });
  add('xt_stregone', 'title', 'raro', 109, 'Stregone Errante', 'Nessuna dimora, mille incantesimi.', { a: '#d9a8ff', b: '#8b5cf6', g: 'rgba(170,110,255,.5)' });
  add('xt_signore', 'title', 'epico', 179, 'Signore del Mazzo', 'Ogni carta al suo posto, ogni mano sotto controllo.', { a: '#fff2b0', b: '#f1bf2f', g: 'rgba(241,191,47,.5)' });
  add('xt_eroe', 'title', 'epico', 259, 'Eroe della Leggenda', 'Il suo nome sarà cantato nelle taverne del Tempio.', { a: '#a5f3fc', b: '#22d3ee', g: 'rgba(34,211,238,.5)' });
  add('xt_caos', 'title', 'leggendario', 449, 'Maestro del Caos', 'Perde il controllo solo quando vuole.', { a: '#ff7ad9', b: '#7df9ff', g: 'rgba(220,120,255,.55)', s: 1 });
  add('xt_re', 'title', 'leggendario', 619, 'Re dei Duellanti', 'Il trono è vuoto solo finché non arriva lui.', { a: '#fff3b0', b: '#e8b84a', g: 'rgba(255,200,60,.6)', s: 1 });
  add('xt_imperatore', 'title', 'mitico', 769, 'Imperatore dell’Abisso', 'Regna dove la luce non arriva.', { a: '#ff5a7a', b: '#8b1d6b', g: 'rgba(255,60,120,.55)', s: 1 });
  add('xt_dio', 'title', 'mitico', 969, 'Dio dei Duelli', 'Non gioca le carte: le scrive.', { a: '#ffffff', b: '#7df9ff', g: 'rgba(160,240,255,.7)', s: 1 });
  add('xt_sovrano', 'title', 'divino', 3000, 'Eterno Sovrano del Tempio', 'Il titolo che nessuno ha mai davvero tolto a chi lo porta.', { a: '#ffffff', b: '#ffd36b', c: '#ff7ad9', g: 'rgba(255,220,120,.8)', s: 1 });
  /* EFFETTI */
  add('xx_scintille', 'effect', 'comune', 31, 'Scintille Dorate', 'Stelline d’oro che si accendono e si spengono sul profilo.');
  add('xx_piume', 'effect', 'raro', 97, 'Piume di Fenice', 'Piume incandescenti che cadono piano e si spengono prima di toccare terra.');
  add('xx_fulmini', 'effect', 'epico', 209, 'Fulmini Viola', 'Saette viola che guizzano ai lati del profilo.');
  add('xx_neve', 'effect', 'epico', 289, 'Neve Mistica', 'Fiocchi di neve azzurra che scendono come una magia.');
  add('xx_meteore', 'effect', 'leggendario', 569, 'Pioggia di Meteore', 'Meteore che solcano il cielo del tuo profilo, una dopo l’altra.');
  add('xx_anime', 'effect', 'mitico', 929, 'Tempesta di Anime', 'Spiriti luminosi che girano in cerchio attorno a te, sussurrando.');

  var ART = {};

  /* ======================= PET ======================= */
  function dragon(P, o) {   /* drago stilizzato riusato da più pet: corpo, ali, corna, occhi, soffio */
    var d = '', c = o;
    d += '<defs>' + lin(P + 'b', c.b1, c.b2, c.b3) + lin(P + 'w', c.w1, c.w2) + rad(P + 'g', c.glow, c.glow2) + '</defs>';
    d += '<ellipse cx="60" cy="64" rx="46" ry="40" fill="url(#' + P + 'g)" class="pulse"/>';
    d += '<g class="float">';
    /* ali */
    d += '<path d="M44 58 C22 34 8 40 4 22 C20 24 30 30 40 44 C34 36 38 28 36 20 C46 30 50 42 52 52Z" fill="url(#' + P + 'w)" stroke="' + c.ln + '" stroke-width="1.2"/>';
    d += '<path d="M76 58 C98 34 112 40 116 22 C100 24 90 30 80 44 C86 36 82 28 84 20 C74 30 70 42 68 52Z" fill="url(#' + P + 'w)" stroke="' + c.ln + '" stroke-width="1.2"/>';
    /* coda */
    d += '<path d="M66 92 C84 96 94 88 100 98 C90 98 80 104 64 100Z" fill="url(#' + P + 'b)" stroke="' + c.ln + '" stroke-width="1.2"/>';
    /* corpo */
    d += '<path d="M60 44 C44 44 38 58 40 74 C42 90 50 100 60 100 C70 100 78 90 80 74 C82 58 76 44 60 44Z" fill="url(#' + P + 'b)" stroke="' + c.ln + '" stroke-width="1.4"/>';
    d += '<path d="M60 62 C52 64 50 76 52 86 C54 94 66 94 68 86 C70 76 68 64 60 62Z" fill="' + c.belly + '" opacity=".85"/>';
    d += '<path d="M54 70h12M53 76h14M54 82h12" stroke="' + c.ln + '" stroke-width="1" opacity=".5"/>';
    /* artigli */
    d += '<path d="M46 98l-3 5M50 100l-1 5M70 100l1 5M74 98l3 5" stroke="' + c.horn + '" stroke-width="2.2" stroke-linecap="round"/>';
    /* testa */
    d += '<path d="M60 18 C46 18 40 28 41 38 C42 48 50 54 60 54 C70 54 78 48 79 38 C80 28 74 18 60 18Z" fill="url(#' + P + 'b)" stroke="' + c.ln + '" stroke-width="1.4"/>';
    d += '<path d="M52 46 C54 52 66 52 68 46 C66 50 54 50 52 46Z" fill="' + c.belly + '" opacity=".8"/><circle cx="56.5" cy="47" r=".9" fill="#000" opacity=".6"/><circle cx="63.5" cy="47" r=".9" fill="#000" opacity=".6"/>';
    /* corna */
    d += c.horns || '<path d="M44 26 C36 20 34 10 30 6 C38 8 46 14 50 22Z" fill="' + c.horn + '" stroke="' + c.ln + '" stroke-width="1"/><path d="M76 26 C84 20 86 10 90 6 C82 8 74 14 70 22Z" fill="' + c.horn + '" stroke="' + c.ln + '" stroke-width="1"/>';
    d += eye(52, 34, 3.4, c.eye, c.eyeg) + eye(68, 34, 3.4, c.eye, c.eyeg);
    d += (c.extra || '');
    d += '</g>';
    return d;
  }
  var petFns = {
    xp_pipistrello: function (P) {
      return '<defs>' + lin(P + 'b', '#5b3a8a', '#2a1646') + rad(P + 'g', '#a78bfa', '#7c3aed') + '</defs><ellipse cx="60" cy="62" rx="42" ry="34" fill="url(#' + P + 'g)" opacity=".5" class="pulse"/><g class="float">' +
        '<path d="M60 56 C44 44 24 44 8 56 C16 56 20 62 22 70 C28 62 36 64 40 72 C46 64 54 66 60 76 C66 66 74 64 80 72 C84 64 92 62 98 70 C100 62 104 56 112 56 C96 44 76 44 60 56Z" fill="url(#' + P + 'b)" stroke="#c4b5fd" stroke-width="1.2"/>' +
        '<path d="M60 40 C50 40 46 50 47 60 C48 74 54 84 60 84 C66 84 72 74 73 60 C74 50 70 40 60 40Z" fill="#3b2268" stroke="#c4b5fd" stroke-width="1.2"/>' +
        '<path d="M50 44l-6-14 12 8zM70 44l6-14-12 8z" fill="#3b2268" stroke="#c4b5fd" stroke-width="1.2"/>' +
        '<path d="M60 62l5 6-5 6-5-6z" fill="none" stroke="#fde047" stroke-width="1.6" class="flick"/><circle cx="60" cy="68" r="1.6" fill="#fde047" class="flick"/>' +
        eye(54, 52, 2.6, '#fde047', '#facc15') + eye(66, 52, 2.6, '#fde047', '#facc15') + '<path d="M57 60l1.6 3 1.4-3 1.4 3 1.6-3" stroke="#fff" stroke-width="1" fill="none"/></g>';
    },
    xp_golem: function (P) {
      return '<defs>' + lin(P + 'b', '#bff4ff', '#4cc3ee', '#1d6fa5') + rad(P + 'g', '#7dd3fc', '#38bdf8') + '</defs><ellipse cx="60" cy="64" rx="40" ry="40" fill="url(#' + P + 'g)" opacity=".5" class="pulse"/><g class="float">' +
        '<path d="M60 14l22 18 10 30-14 34-18 10-18-10-14-34 10-30z" fill="url(#' + P + 'b)" stroke="#e0f7ff" stroke-width="1.4"/>' +
        '<path d="M60 14l-8 22 8 16 8-16zM38 32l14 4M82 32l-14 4M28 62l24-10 8 0 24 10M60 52l-4 28 4 22 4-22zM28 62l14 34M92 62l-14 34" fill="none" stroke="#e0f7ff" stroke-width="1" opacity=".7"/>' +
        '<path d="M60 14l-8 22 8 16z" fill="#fff" opacity=".25"/>' + eye(50, 62, 4, '#fef08a', '#fde047') + eye(70, 62, 4, '#fef08a', '#fde047') +
        '<path d="M52 78h16" stroke="#0c4a6e" stroke-width="2" stroke-linecap="round"/><path d="M20 70l-8 6 6 12 10-6zM100 70l8 6-6 12-10-6z" fill="#7dd3fc" stroke="#e0f7ff" stroke-width="1.2"/></g>';
    },
    xp_volpe: function (P) {
      var t = '';
      for (var i = 0; i < 9; i++) { var a = -64 + i * 16; t += '<g transform="rotate(' + a + ' 60 84)"><path d="M60 84 C50 60 52 36 60 18 C68 36 70 60 60 84Z" fill="url(#' + P + 't)" stroke="#fff7ed" stroke-width=".8" opacity=".95"/><path d="M60 24 C57 30 57 36 60 42 C63 36 63 30 60 24Z" fill="#7dd3fc" class="flick" style="animation-delay:' + (i * .12) + 's"/></g>'; }
      return '<defs>' + lin(P + 't', '#fb923c', '#ea580c', '#fff7ed') + lin(P + 'b', '#fdba74', '#ea580c') + rad(P + 'g', '#7dd3fc', '#38bdf8') + '</defs><ellipse cx="60" cy="62" rx="48" ry="42" fill="url(#' + P + 'g)" opacity=".35" class="pulse"/><g class="float">' + t +
        '<path d="M60 52 C46 52 42 68 44 84 C46 98 54 104 60 104 C66 104 74 98 76 84 C78 68 74 52 60 52Z" fill="url(#' + P + 'b)" stroke="#7c2d12" stroke-width="1.2"/>' +
        '<path d="M60 70 C54 72 52 84 56 94 C60 98 64 94 64 94 C68 84 66 72 60 70Z" fill="#fff7ed"/>' +
        '<path d="M60 30 C48 30 42 38 42 48 C42 56 50 62 60 62 C70 62 78 56 78 48 C78 38 72 30 60 30Z" fill="url(#' + P + 'b)" stroke="#7c2d12" stroke-width="1.2"/>' +
        '<path d="M44 38l-4-20 16 12zM76 38l4-20-16 12z" fill="#ea580c" stroke="#7c2d12" stroke-width="1.2"/><path d="M45 34l-1-10 8 6zM75 34l1-10-8 6z" fill="#fff7ed"/>' +
        '<path d="M52 54c4 6 12 6 16 0 0 6-4 10-8 10s-8-4-8-10z" fill="#fff7ed"/><ellipse cx="60" cy="55" rx="2.6" ry="1.8" fill="#1c1917"/>' +
        eye(52, 46, 2.6, '#7dd3fc', '#38bdf8') + eye(68, 46, 2.6, '#7dd3fc', '#38bdf8') + '</g>';
    },
    xp_cavaliere: function (P) {
      return '<defs>' + lin(P + 'a', '#f8fafc', '#94a3b8', '#475569') + rad(P + 'g', '#bae6fd', '#38bdf8') + '</defs><ellipse cx="60" cy="64" rx="40" ry="44" fill="url(#' + P + 'g)" opacity=".4" class="pulse"/><g class="float">' +
        '<path d="M60 14c8-6 18-4 22 4-8-2-12 2-14 8z" fill="#ef4444" stroke="#7f1d1d" stroke-width="1"/>' +
        '<path d="M44 48 C44 30 50 22 60 22 C70 22 76 30 76 48 L76 56 L44 56Z" fill="url(#' + P + 'a)" stroke="#1e293b" stroke-width="1.4"/><path d="M46 44h28v8H46z" fill="#0f172a"/><path d="M60 22v34M46 48h28" stroke="#1e293b" stroke-width="1"/>' +
        eye(54, 48, 1.6, '#7dd3fc', '#38bdf8') + eye(66, 48, 1.6, '#7dd3fc', '#38bdf8') +
        '<path d="M40 58h40l4 14-6 30H42l-6-30z" fill="url(#' + P + 'a)" stroke="#1e293b" stroke-width="1.4"/><path d="M60 58v44M44 72h32" stroke="#1e293b" stroke-width="1" opacity=".6"/><path d="M60 66l4 5-4 5-4-5z" fill="#38bdf8"/>' +
        '<path d="M28 60l10-4 4 14-8 8z" fill="url(#' + P + 'a)" stroke="#1e293b" stroke-width="1.2"/>' +
        '<path d="M92 24l4 4-26 54-6-2z" fill="#e2e8f0" stroke="#1e293b" stroke-width="1.2"/><path d="M66 80l-6 2 2 8 6-2z" fill="#b45309"/><path d="M62 92l8 18" stroke="#78350f" stroke-width="3" stroke-linecap="round"/>' +
        '<path d="M16 62 C16 52 30 50 36 58 L36 84 C36 96 22 100 16 90Z" fill="#1e3a8a" stroke="#e2e8f0" stroke-width="1.6"/><path d="M26 60v36" stroke="#e2e8f0" stroke-width="1.2"/>' +
        '<path d="M44 104h12v8H44zM64 104h12v8H64z" fill="#475569" stroke="#1e293b" stroke-width="1"/></g>';
    },
    xp_lupo: function (P) {
      var bolts = '';
      for (var i = 0; i < 5; i++) { var x = 22 + i * 19; bolts += '<path d="M' + x + ' 14l-5 14 7-1-5 15 12-18-7 1 5-11z" fill="#fde047" stroke="#facc15" stroke-width=".6" class="flick" style="animation-delay:' + (i * .22) + 's"/>'; }
      return '<defs>' + lin(P + 'b', '#94a3b8', '#475569', '#1e293b') + rad(P + 'g', '#a5b4fc', '#6366f1') + '</defs><ellipse cx="60" cy="66" rx="48" ry="44" fill="url(#' + P + 'g)" opacity=".45" class="pulse"/><g class="float">' + bolts +
        '<path d="M60 40 C40 40 28 58 28 78 C28 98 44 110 60 110 C76 110 92 98 92 78 C92 58 80 40 60 40Z" fill="url(#' + P + 'b)" stroke="#e2e8f0" stroke-width="1.2"/>' +
        '<path d="M34 48l-6-26 22 14zM86 48l6-26-22 14z" fill="url(#' + P + 'b)" stroke="#e2e8f0" stroke-width="1.2"/><path d="M36 44l-3-12 10 7zM84 44l3-12-10 7z" fill="#818cf8"/>' +
        '<path d="M44 78 C44 92 52 100 60 100 C68 100 76 92 76 78 C72 84 66 86 60 86 C54 86 48 84 44 78Z" fill="#e2e8f0"/><path d="M54 84l6-6 6 6-6 4z" fill="#0f172a"/><path d="M60 88v8M54 96c4 3 8 3 12 0" stroke="#0f172a" stroke-width="1.2" fill="none"/>' +
        eye(46, 68, 4, '#7dd3fc', '#38bdf8') + eye(74, 68, 4, '#7dd3fc', '#38bdf8') + '<path d="M44 60l8 4M76 60l-8 4" stroke="#0f172a" stroke-width="2" stroke-linecap="round"/></g>';
    },
    xp_grifone: function (P) {
      return '<defs>' + lin(P + 'b', '#fde68a', '#f59e0b', '#92400e') + lin(P + 'w', '#fff7d1', '#f5b72d') + rad(P + 'g', '#fde047', '#f59e0b') + '</defs><ellipse cx="60" cy="62" rx="52" ry="44" fill="url(#' + P + 'g)" opacity=".4" class="pulse"/><g class="float">' +
        '<path d="M46 62C26 40 8 46 2 24 22 26 36 32 42 48 36 38 38 28 34 18 48 28 54 44 54 58Z" fill="url(#' + P + 'w)" stroke="#92400e" stroke-width="1.2"/><path d="M74 62C94 40 112 46 118 24 98 26 84 32 78 48 84 38 82 28 86 18 72 28 66 44 66 58Z" fill="url(#' + P + 'w)" stroke="#92400e" stroke-width="1.2"/>' +
        '<path d="M60 58 C44 58 38 74 40 88 C42 102 52 108 60 108 C68 108 78 102 80 88 C82 74 76 58 60 58Z" fill="url(#' + P + 'b)" stroke="#78350f" stroke-width="1.4"/><path d="M80 90 C96 90 102 80 98 70 C96 82 88 84 80 82Z" fill="#b45309"/>' +
        '<path d="M60 22 C48 22 42 32 44 42 C46 52 54 58 60 58 C66 58 74 52 76 42 C78 32 72 22 60 22Z" fill="#fff7d1" stroke="#78350f" stroke-width="1.4"/><path d="M52 24l-8-12 16 6zM68 24l8-12-16 6z" fill="#f59e0b" stroke="#78350f" stroke-width="1"/>' +
        '<path d="M54 42 C54 52 58 60 60 64 C62 60 66 52 66 42 C64 46 56 46 54 42Z" fill="#f59e0b" stroke="#78350f" stroke-width="1.2"/><path d="M60 44v14" stroke="#78350f" stroke-width="1"/>' +
        eye(52, 36, 2.8, '#dc2626', '#f87171') + eye(68, 36, 2.8, '#dc2626', '#f87171') + '<path d="M46 104l-4 8M52 108l-2 6M68 108l2 6M74 104l4 8" stroke="#78350f" stroke-width="2.2" stroke-linecap="round"/></g>';
    },
    xp_sfinge: function (P) {
      return '<defs>' + lin(P + 'b', '#fcd9a0', '#d49a52', '#8a5a22') + lin(P + 'h', '#1e3a8a', '#fbbf24') + rad(P + 'g', '#fbbf24', '#f59e0b') + '</defs><ellipse cx="60" cy="68" rx="52" ry="40" fill="url(#' + P + 'g)" opacity=".35" class="pulse"/><g class="float">' +
        '<path d="M14 96 C14 76 30 68 46 70 L96 70 C108 70 112 82 108 96 L108 104 L14 104Z" fill="url(#' + P + 'b)" stroke="#6b4414" stroke-width="1.4"/><path d="M96 70c10-2 16 4 14 14 0 8-4 12-8 14" fill="none" stroke="#6b4414" stroke-width="1.4"/><path d="M26 104v-14M36 104v-10" stroke="#6b4414" stroke-width="1.4"/>' +
        '<path d="M30 40 C30 22 42 12 60 12 C78 12 90 22 90 40 L96 88 L24 88Z" fill="url(#' + P + 'h)" stroke="#fbbf24" stroke-width="1.4"/><path d="M36 30h48M34 44h52M32 58h56M30 72h60" stroke="#fbbf24" stroke-width="1.6" opacity=".9"/>' +
        '<path d="M42 38 C42 28 50 22 60 22 C70 22 78 28 78 38 C78 52 70 66 60 66 C50 66 42 52 42 38Z" fill="url(#' + P + 'b)" stroke="#6b4414" stroke-width="1.4"/>' +
        '<path d="M60 12l-4 10h8z" fill="#ef4444" stroke="#fbbf24" stroke-width="1"/><path d="M60 22 C56 16 56 10 60 6 C64 10 64 16 60 22Z" fill="#10b981" stroke="#fbbf24" stroke-width=".8"/>' +
        eye(52, 40, 2.4, '#10b981', '#34d399') + eye(68, 40, 2.4, '#10b981', '#34d399') + '<path d="M48 36l8 1M72 36l-8 1M56 56c3 2 5 2 8 0" stroke="#3b2208" stroke-width="1.4" fill="none" stroke-linecap="round"/><path d="M56 66l-2 22 6 8 6-8-2-22" fill="#1e3a8a" stroke="#fbbf24" stroke-width="1.2"/></g>';
    },
    xp_idra: function (P) {
      function head(x, y, s, col, ey) { return '<g transform="translate(' + x + ' ' + y + ') scale(' + s + ')"><path d="M0 0 C-10 0 -14 8 -12 16 C-10 24 -4 28 0 28 C4 28 10 24 12 16 C14 8 10 0 0 0Z" fill="' + col + '" stroke="#052e1a" stroke-width="1.4"/><path d="M-8 4l-6-10 12 6zM8 4l6-10-12 6z" fill="#ca8a04"/>' + eye(-5, 11, 2.4, ey, '#fde047') + eye(5, 11, 2.4, ey, '#fde047') + '<path d="M-4 22h8" stroke="#052e1a" stroke-width="1.2"/><path d="M0 28l-2 6 2-2 2 2z" fill="#ef4444"/></g>'; }
      return '<defs>' + lin(P + 'b', '#4ade80', '#15803d', '#064e3b') + rad(P + 'g', '#86efac', '#22c55e') + '</defs><ellipse cx="60" cy="68" rx="52" ry="44" fill="url(#' + P + 'g)" opacity=".4" class="pulse"/><g class="float">' +
        '<path d="M60 108 C30 108 22 88 36 70 C44 60 50 56 54 46" fill="none" stroke="url(#' + P + 'b)" stroke-width="12" stroke-linecap="round"/><path d="M60 108 C90 108 98 88 84 70 C76 60 70 56 66 46" fill="none" stroke="url(#' + P + 'b)" stroke-width="12" stroke-linecap="round"/><path d="M60 100 C60 80 60 66 60 50" fill="none" stroke="url(#' + P + 'b)" stroke-width="13" stroke-linecap="round"/>' +
        '<path d="M60 108 C44 108 38 100 38 92 L82 92 C82 100 76 108 60 108Z" fill="#064e3b" opacity=".55"/>' + head(52, 22, .95, 'url(#' + P + 'b)', '#f97316').replace('translate(52 22)', 'translate(32 40)') + head(60, 6, 1.1, 'url(#' + P + 'b)', '#facc15').replace('translate(60 6)', 'translate(60 12)') + head(88, 40, .95, 'url(#' + P + 'b)', '#f97316').replace('translate(88 40)', 'translate(88 40)') + '</g>';
    },
    xp_drago_cremisi: function (P) {
      return dragon(P, { b1: '#ff6b5a', b2: '#c1121f', b3: '#4a0410', w1: '#ff9248', w2: '#8d0f1b', ln: '#2a0208', belly: '#ffd7a1', horn: '#f3e3c3', eye: '#ffd60a', eyeg: '#ff8a00', glow: '#ff5a36', glow2: '#ff2e1f' });
    },
    xp_cerbero: function (P) {
      function head(x, y, s) { return '<g transform="translate(' + x + ' ' + y + ') scale(' + s + ')"><path d="M-16 4 C-18 -8 -10 -18 0 -18 C10 -18 18 -8 16 4 C18 14 8 22 0 22 C-8 22 -18 14 -16 4Z" fill="url(#' + P + 'b)" stroke="#0b0214" stroke-width="1.4"/><path d="M-14 -8l-6-14 14 8zM14 -8l6-14-14 8z" fill="#2a1048" stroke="#0b0214" stroke-width="1.2"/><path d="M-9 8 C-8 18 8 18 9 8 C6 12 -6 12 -9 8Z" fill="#c4b5fd"/><ellipse cx="0" cy="9" rx="3" ry="2" fill="#0b0214"/>' + eye(-7, -2, 2.8, '#fb923c', '#f97316') + eye(7, -2, 2.8, '#fb923c', '#f97316') + '<path d="M-3 18l1 5 2-3 2 3 1-5z" fill="#ef4444"/></g>'; }
      var fl = ''; for (var i = 0; i < 7; i++) { var x = 26 + i * 11.3; fl += '<path d="M' + x + ' 56c-5-8 4-14 0-22 8 6 10 14 6 22z" fill="#a855f7" class="flick" style="animation-delay:' + (i * .16) + 's" opacity=".9"/>'; }
      return '<defs>' + lin(P + 'b', '#4a2a72', '#241040', '#0b0214') + rad(P + 'g', '#c084fc', '#7e22ce') + '</defs><ellipse cx="60" cy="70" rx="54" ry="44" fill="url(#' + P + 'g)" opacity=".5" class="pulse"/><g class="float">' + fl +
        '<path d="M60 56 C34 56 26 76 30 92 C34 106 48 112 60 112 C72 112 86 106 90 92 C94 76 86 56 60 56Z" fill="url(#' + P + 'b)" stroke="#0b0214" stroke-width="1.4"/><path d="M48 104l-4 8M60 108v6M72 104l4 8" stroke="#d8b4fe" stroke-width="2.2" stroke-linecap="round"/>' +
        head(30, 52, .8) + head(90, 52, .8) + head(60, 38, 1.05) + '</g>';
    },
    xp_leviatano: function (P) {
      var sc = ''; for (var i = 0; i < 6; i++) sc += '<circle cx="' + (30 + i * 12) + '" cy="' + (88 - Math.sin(i * 1.1) * 14) + '" r="2.4" fill="#e0f7ff" class="tw" style="animation-delay:' + (i * .3) + 's"/>';
      return '<defs>' + lin(P + 'b', '#a5f3fc', '#22d3ee', '#0e7490') + rad(P + 'g', '#67e8f9', '#06b6d4') + '</defs><ellipse cx="60" cy="64" rx="54" ry="46" fill="url(#' + P + 'g)" opacity=".35" class="pulse"/><g class="float">' +
        '<path d="M10 100 C26 70 40 110 58 84 C74 62 62 44 80 32" fill="none" stroke="url(#' + P + 'b)" stroke-width="16" stroke-linecap="round"/><path d="M10 100 C26 70 40 110 58 84 C74 62 62 44 80 32" fill="none" stroke="#ecfeff" stroke-width="2" stroke-linecap="round" stroke-dasharray="1 7" opacity=".9"/>' +
        '<path d="M16 106l-10 6 14-2zM30 84l-4-14 10 8z" fill="#22d3ee" opacity=".8"/>' + sc +
        '<path d="M70 38 C72 22 90 18 104 24 C112 28 112 40 104 46 C94 54 76 54 70 38Z" fill="url(#' + P + 'b)" stroke="#083344" stroke-width="1.4"/><path d="M80 24l-6-12 14 6zM94 22l2-12 8 12z" fill="#0e7490" stroke="#083344" stroke-width="1"/><path d="M84 46c8 4 16 2 22-4" fill="none" stroke="#083344" stroke-width="1.2"/>' +
        eye(92, 32, 3.2, '#fde047', '#facc15') + '<path d="M104 30l8-4M104 36l8 2" stroke="#e0f7ff" stroke-width="1.4" stroke-linecap="round"/></g>';
    },
    xp_arcidemone: function (P) {
      return dragon(P, { b1: '#6b2a4f', b2: '#2d0f2a', b3: '#0f0210', w1: '#7a1d3a', w2: '#1a0210', ln: '#0a0108', belly: '#5a1a3e', horn: '#f5e1b5', eye: '#ffd24a', eyeg: '#ffb300', glow: '#e11d74', glow2: '#7c1d6f',
        horns: '<path d="M43 28 C30 24 24 12 26 -2 C32 6 42 10 52 18Z" fill="#f5e1b5" stroke="#0a0108" stroke-width="1.2"/><path d="M77 28 C90 24 96 12 94 -2 C88 6 78 10 68 18Z" fill="#f5e1b5" stroke="#0a0108" stroke-width="1.2"/><path d="M48 22 C44 12 46 4 52 0 C52 8 54 14 58 18Z" fill="#d6b97a" stroke="#0a0108" stroke-width="1"/><path d="M72 22 C76 12 74 4 68 0 C68 8 66 14 62 18Z" fill="#d6b97a" stroke="#0a0108" stroke-width="1"/>',
        extra: '<path d="M52 52l3 4 5-3 5 3 3-4" fill="#fff" stroke="#0a0108" stroke-width=".8"/><path d="M60 2 L62 -6 L64 2z" fill="#ffd24a" class="flick"/>' });
    },
    xp_drago_cosmico: function (P) {
      var st = ''; for (var i = 0; i < 16; i++) st += star(30 + rnd(i) * 60, 40 + rnd(i + 40) * 56, 1.6 + rnd(i + 9) * 1.6, '#fff', 'tw', (rnd(i + 3) * 2).toFixed(2));
      return dragon(P, { b1: '#6d28d9', b2: '#1e1b4b', b3: '#020617', w1: '#22d3ee', w2: '#4c1d95', ln: '#c4b5fd', belly: '#312e81', horn: '#a5f3fc', eye: '#e0f2fe', eyeg: '#22d3ee', glow: '#8b5cf6', glow2: '#0ea5e9', extra: '<g clip-path="inset(0)">' + st + '</g>' });
    },
    xp_ouroboros: function (P) {
      var sc = ''; for (var i = 0; i < 26; i++) { var a = i * 2 * Math.PI / 26; sc += '<path d="M' + (60 + Math.cos(a) * 38).toFixed(1) + ' ' + (60 + Math.sin(a) * 38).toFixed(1) + 'l' + (Math.cos(a + 1.2) * 6).toFixed(1) + ' ' + (Math.sin(a + 1.2) * 6).toFixed(1) + '" stroke="#ffd36b" stroke-width="1.6" stroke-linecap="round" opacity=".85"/>'; }
      var st = ''; for (var j = 0; j < 14; j++) { var aa = rnd(j) * 6.28, rr = rnd(j + 7) * 24; st += star(60 + Math.cos(aa) * rr, 60 + Math.sin(aa) * rr, 1.4 + rnd(j + 2) * 1.4, '#fff', 'tw', (rnd(j + 5) * 2).toFixed(2)); }
      return '<defs>' + lin(P + 'b', '#fff1a8', '#f59e0b', '#7c2d12') + rad(P + 'g', '#c4b5fd', '#6d28d9') + rad(P + 'c', '#312e81', '#020617') + '</defs>' +
        '<circle cx="60" cy="60" r="56" fill="url(#' + P + 'g)" opacity=".55" class="pulse"/><circle cx="60" cy="60" r="30" fill="url(#' + P + 'c)"/>' + st + '<g class="spinr" opacity=".9">' + sc + '</g>' +
        '<g class="spin"><circle cx="60" cy="60" r="38" fill="none" stroke="url(#' + P + 'b)" stroke-width="13"/><circle cx="60" cy="60" r="38" fill="none" stroke="#7c2d12" stroke-width="13" stroke-dasharray="2 9" opacity=".35"/></g>' +
        '<path d="M60 14 C48 10 38 16 38 26 C38 36 50 38 60 34Z" fill="url(#' + P + 'b)" stroke="#431407" stroke-width="1.6"/><path d="M44 14l-8-10 14 4zM54 12l-2-10 8 8z" fill="#fde68a" stroke="#431407" stroke-width="1"/>' + eye(48, 22, 2.8, '#ef4444', '#f87171') +
        '<path d="M66 14 C78 12 86 18 84 22" fill="none" stroke="url(#' + P + 'b)" stroke-width="11" stroke-linecap="round"/><path d="M60 34 l-4 4 6 -1z" fill="#fff"/><path d="M62 36l6 6" stroke="#ef4444" stroke-width="1.6" stroke-linecap="round"/>';
    }
  };
  Object.keys(petFns).forEach(function (k) { ART[k] = petFns[k]; });

  /* ======================= CORNICI ======================= */
  function frameBase(P, c1, c2, c3, w, r) { return '<defs>' + lin(P + 'f', c1, c2, c3) + '</defs><circle cx="60" cy="60" r="' + (r || 46) + '" fill="none" stroke="url(#' + P + 'f)" stroke-width="' + w + '"/>'; }
  var frameFns = {
    xf_rovi: function (P) {
      var th = polar(16, 47, function (x, y, a, i) { return '<path d="M0 0l-3-9 6 0z" fill="#e2e8f0" transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + (a + (i % 2 ? 20 : -20)).toFixed(0) + ')"/>'; });
      var bd = polar(6, 47, function (x, y, a, i) { return '<circle cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" r="4.2" fill="#e11d48" stroke="#4c0519" stroke-width="1"/><circle cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" r="1.6" fill="#fda4af"/>'; });
      return frameBase(P, '#4b5563', '#1f2937', '#0b0f14', 6) + '<path d="M60 14c14 0 28 6 36 18M96 32c10 12 12 28 6 42M102 74c-6 14-18 24-32 28" fill="none" stroke="#111827" stroke-width="3" opacity=".6"/><g class="spin" style="animation-duration:60s">' + th + bd + '</g>';
    },
    xf_rune: function (P) {
      var ru = polar(12, 47, function (x, y, a, i) { return '<g transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + a.toFixed(0) + ')"><rect x="-4.5" y="-5" width="9" height="10" rx="1.5" fill="#1e293b" stroke="#cbd5e1" stroke-width="1"/><path d="M-2 -3l4 3-4 3M2 -3v6" stroke="#7dd3fc" stroke-width="1.2" fill="none" class="tw" style="animation-delay:' + (i * .2) + 's"/></g>'; });
      return frameBase(P, '#e2e8f0', '#94a3b8', '#475569', 4) + ring(52, 1, '#cbd5e1', ' opacity=".6"') + ring(41, 1, '#cbd5e1', ' opacity=".5"') + ru;
    },
    xf_ghiaccio: function (P) {
      var cr = polar(14, 47, function (x, y, a, i) { var h = 9 + (i % 3) * 4; return '<path d="M-3 0L0 -' + h + 'L3 0z" fill="#e0f7ff" stroke="#38bdf8" stroke-width=".8" transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + a.toFixed(0) + ')"/>'; });
      return '<defs>' + rad(P + 'g', '#67e8f9', '#0ea5e9') + '</defs><circle cx="60" cy="60" r="56" fill="url(#' + P + 'g)" opacity=".3" class="pulse"/>' + frameBase(P, '#f0fdff', '#7dd3fc', '#0369a1', 6) + '<g class="spin" style="animation-duration:80s">' + cr + '</g>' + star(14, 22, 5, '#fff', 'tw', 0) + star(104, 96, 4, '#fff', 'tw', 1);
    },
    xf_drago: function (P) {
      var sc = polar(30, 47, function (x, y, a) { return '<path d="M-3.5 -2 Q0 -6 3.5 -2 Q0 5 -3.5 -2z" fill="#b45309" stroke="#431407" stroke-width=".6" transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + a.toFixed(0) + ')"/>'; });
      var cl = polar(4, 48, function (x, y, a) { return '<path d="M-5 0 C-5 -8 0 -14 0 -14 C0 -14 5 -8 5 0z" fill="#fde68a" stroke="#431407" stroke-width="1" transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + (a + 180).toFixed(0) + ')"/>'; });
      return frameBase(P, '#fcd34d', '#b45309', '#431407', 7) + sc + cl;
    },
    xf_fulmini: function (P) {
      var arcs = ''; for (var i = 0; i < 8; i++) { var a = i * Math.PI / 4 + .2, a2 = a + .6; var x1 = 60 + Math.cos(a) * 47, y1 = 60 + Math.sin(a) * 47, x2 = 60 + Math.cos(a2) * 47, y2 = 60 + Math.sin(a2) * 47, mx = 60 + Math.cos((a + a2) / 2) * 56, my = 60 + Math.sin((a + a2) / 2) * 56; arcs += '<path d="M' + x1.toFixed(1) + ' ' + y1.toFixed(1) + ' L' + ((x1 + mx) / 2 + 3).toFixed(1) + ' ' + ((y1 + my) / 2 - 3).toFixed(1) + ' L' + mx.toFixed(1) + ' ' + my.toFixed(1) + ' L' + ((x2 + mx) / 2 - 3).toFixed(1) + ' ' + ((y2 + my) / 2 + 3).toFixed(1) + ' L' + x2.toFixed(1) + ' ' + y2.toFixed(1) + '" fill="none" stroke="#fde047" stroke-width="2" stroke-linejoin="round" class="flick" style="animation-delay:' + (i * .17) + 's"/>'; }
      return '<defs>' + rad(P + 'g', '#c4b5fd', '#7c3aed') + '</defs><circle cx="60" cy="60" r="58" fill="url(#' + P + 'g)" opacity=".35" class="pulse"/>' + frameBase(P, '#a78bfa', '#4c1d95', '#1e1b4b', 6) + ring(47, 1.4, '#e9d5ff', ' opacity=".8"') + arcs;
    },
    xf_millennio: function (P) {
      var gm = polar(8, 47, function (x, y, a, i) { return '<path d="M0 -5l5 5-5 5-5-5z" fill="' + (i % 2 ? '#38bdf8' : '#ef4444') + '" stroke="#78350f" stroke-width="1" transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + a.toFixed(0) + ')"/>'; });
      return '<defs>' + rad(P + 'g', '#fde047', '#f59e0b') + '</defs><circle cx="60" cy="60" r="58" fill="url(#' + P + 'g)" opacity=".3" class="pulse"/>' + frameBase(P, '#fff3b0', '#eab308', '#854d0e', 8) + ring(52, 1.2, '#fff3b0', ' opacity=".8"') + ring(42, 1.2, '#78350f', ' opacity=".7"') + gm +
        '<g transform="translate(60 8)"><path d="M-12 0 C-6 -9 6 -9 12 0 C6 9 -6 9 -12 0Z" fill="#fff7d1" stroke="#78350f" stroke-width="1.4"/><circle r="4.2" fill="#0f172a"/><circle r="2" fill="#7dd3fc" class="flick"/><path d="M0 9v10" stroke="#78350f" stroke-width="1.6"/></g>';
    },
    xf_infernale: function (P) {
      var fl = polar(18, 47, function (x, y, a, i) { var h = 14 + (i % 3) * 5; return '<path d="M-5 0 C-6 -6 0 -' + (h * .6) + ' 0 -' + h + ' C3 -' + (h * .6) + ' 6 -6 5 0z" fill="url(#' + P + (i % 2 ? 'a' : 'b') + ')" class="flick" style="animation-delay:' + (i * .09) + 's" transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + a.toFixed(0) + ')"/>'; });
      return '<defs>' + lin(P + 'a', '#ff4d6d', '#c026d3', '#4c1d95', 1) + lin(P + 'b', '#fb923c', '#e11d48', '#7e22ce', 1) + '</defs>' + frameBase(P, '#7e22ce', '#be123c', '#1a0420', 6) + fl + ring(47, 1.2, '#fde68a', ' opacity=".7"');
    },
    xf_siderale: function (P) {
      var pl = polar(5, 47, function (x, y, a, i) { var cols = ['#f97316', '#38bdf8', '#a78bfa', '#facc15', '#34d399']; return '<circle cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" r="' + (3 + (i % 3)) + '" fill="' + cols[i] + '" stroke="#fff" stroke-width=".8"/>'; });
      var st = ''; for (var i = 0; i < 20; i++) { var a = rnd(i) * 6.28; st += star(60 + Math.cos(a) * (46 + rnd(i + 1) * 7), 60 + Math.sin(a) * (46 + rnd(i + 1) * 7), 1.2 + rnd(i + 2) * 1.4, '#fff', 'tw', (rnd(i + 3) * 2).toFixed(2)); }
      return '<defs>' + rad(P + 'g', '#818cf8', '#312e81') + '</defs><circle cx="60" cy="60" r="58" fill="url(#' + P + 'g)" opacity=".5" class="pulse"/>' + frameBase(P, '#6366f1', '#1e1b4b', '#020617', 8) + ring(47, 1, '#c7d2fe', ' stroke-dasharray="1 4" opacity=".9"') + '<g class="spin" style="animation-duration:30s">' + pl + '</g>' + st;
    },
    xf_vuoto: function (P) {
      var cr = '<path d="M60 6 L56 18 L63 24 L57 34" fill="none" stroke="#e9d5ff" stroke-width="1.6" class="flick"/><path d="M114 60 L102 56 L96 63 L86 57" fill="none" stroke="#e9d5ff" stroke-width="1.6" class="flick" style="animation-delay:.4s"/><path d="M60 114 L64 102 L57 96 L63 86" fill="none" stroke="#e9d5ff" stroke-width="1.6" class="flick" style="animation-delay:.8s"/><path d="M6 60 L18 64 L24 57 L34 63" fill="none" stroke="#e9d5ff" stroke-width="1.6" class="flick" style="animation-delay:1.2s"/>';
      return '<defs>' + rad(P + 'g', '#a21caf', '#4a044e') + lin(P + 'f', '#c026d3', '#3b0764', '#000') + '</defs><circle cx="60" cy="60" r="60" fill="url(#' + P + 'g)" opacity=".6" class="pulse"/><g class="spin" style="animation-duration:40s"><circle cx="60" cy="60" r="46" fill="none" stroke="url(#' + P + 'f)" stroke-width="10" stroke-dasharray="40 6 14 6"/></g><circle cx="60" cy="60" r="52" fill="none" stroke="#e879f9" stroke-width="1" stroke-dasharray="2 5" opacity=".8" class="spinr"/>' + cr;
    },
    xf_eclissi: function (P) {
      var rays = ''; for (var i = 0; i < 28; i++) { var a = i * 2 * Math.PI / 28, l = i % 2 ? 56 : 60; rays += '<path d="M' + (60 + Math.cos(a) * 49).toFixed(1) + ' ' + (60 + Math.sin(a) * 49).toFixed(1) + 'L' + (60 + Math.cos(a) * l).toFixed(1) + ' ' + (60 + Math.sin(a) * l).toFixed(1) + '" stroke="#ffd36b" stroke-width="' + (i % 2 ? 1.2 : 2.2) + '" stroke-linecap="round"/>'; }
      return '<defs>' + rad(P + 'g', '#fff7d1', '#f59e0b') + lin(P + 'f', '#fff7d1', '#f59e0b', '#3b0764') + '</defs><circle cx="60" cy="60" r="60" fill="url(#' + P + 'g)" opacity=".5" class="pulse"/><g class="spin" style="animation-duration:50s">' + rays + '</g><circle cx="60" cy="60" r="46" fill="none" stroke="#0a0212" stroke-width="12"/><circle cx="60" cy="60" r="46" fill="none" stroke="url(#' + P + 'f)" stroke-width="2.6"/><circle cx="60" cy="60" r="52" fill="none" stroke="#fff7d1" stroke-width="1.6" opacity=".9"/>' + star(60, 8, 6, '#fff', 'tw', 0) + star(112, 60, 4, '#fff', 'tw', .6) + star(60, 112, 6, '#fff', 'tw', 1.2) + star(8, 60, 4, '#fff', 'tw', 1.8);
    }
  };
  Object.keys(frameFns).forEach(function (k) { ART[k] = frameFns[k]; });

  /* ======================= AURE ======================= */
  function glow(P, a, b, op) { return '<defs>' + rad(P + 'g', a, b) + '</defs><circle cx="60" cy="60" r="58" fill="url(#' + P + 'g)" opacity="' + (op || .6) + '" class="pulse"/>'; }
  function motes(n, fill, cls, rmin, rmax, size) { var s = ''; for (var i = 0; i < n; i++) { var a = rnd(i * 3) * 6.28, r = rmin + rnd(i * 3 + 1) * (rmax - rmin); s += '<circle cx="' + (60 + Math.cos(a) * r).toFixed(1) + '" cy="' + (60 + Math.sin(a) * r).toFixed(1) + '" r="' + ((size || 1.6) * (.6 + rnd(i + 8))).toFixed(1) + '" fill="' + fill + '" class="' + cls + '" style="transform-box:fill-box;transform-origin:center;animation-delay:' + (rnd(i + 20) * 3).toFixed(2) + 's"/>'; } return s; }
  var auraFns = {
    xa_braci: function (P) { return glow(P, '#fb923c', '#ea580c', .35) + motes(18, '#fdba74', 'tw', 40, 58, 2); },
    xa_druidica: function (P) {
      var lv = polar(10, 50, function (x, y, a, i) { return '<path d="M0 0C-4-5-4-11 0-14C4-11 4-5 0 0z" fill="#4ade80" stroke="#14532d" stroke-width=".6" transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + (a + i * 30).toFixed(0) + ')"/>'; });
      return glow(P, '#86efac', '#16a34a', .4) + '<g class="spin" style="animation-duration:40s">' + lv + '</g>' + motes(14, '#bbf7d0', 'tw', 38, 58, 1.8);
    },
    xa_gelida: function (P) {
      var cr = polar(8, 52, function (x, y, a) { return '<path d="M0 -8L3 0 0 8-3 0z" fill="#e0f7ff" stroke="#38bdf8" stroke-width=".8" transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + a.toFixed(0) + ')"/>'; });
      return glow(P, '#a5f3fc', '#0ea5e9', .45) + '<g class="spin">' + cr + '</g>' + ring(56, 1, '#bae6fd', ' stroke-dasharray="2 6" opacity=".8" class="spinr"') + motes(12, '#fff', 'tw', 36, 58, 1.6);
    },
    xa_tempesta: function (P) {
      var cl = '<g fill="#312e81" opacity=".85" class="drift"><ellipse cx="24" cy="22" rx="20" ry="9"/><ellipse cx="42" cy="14" rx="16" ry="9"/><ellipse cx="86" cy="18" rx="20" ry="9"/><ellipse cx="102" cy="30" rx="14" ry="8"/></g>';
      return glow(P, '#818cf8', '#4338ca', .4) + cl + '<path d="M30 28l-6 16 8-1-6 16 14-20-8 1 6-12z" fill="#e9d5ff" class="flick"/><path d="M92 30l-5 14 7-1-5 13 12-17-7 1 5-10z" fill="#fde047" class="flick" style="animation-delay:.6s"/>' + motes(10, '#c4b5fd', 'tw', 40, 58, 1.6);
    },
    xa_sacra: function (P) {
      var rays = ''; for (var i = 0; i < 16; i++) { var a = i * Math.PI / 8; rays += '<path d="M' + (60 + Math.cos(a) * 46).toFixed(1) + ' ' + (60 + Math.sin(a) * 46).toFixed(1) + 'L' + (60 + Math.cos(a) * (i % 2 ? 56 : 62)).toFixed(1) + ' ' + (60 + Math.sin(a) * (i % 2 ? 56 : 62)).toFixed(1) + '" stroke="#fde68a" stroke-width="' + (i % 2 ? 1.4 : 2.4) + '" stroke-linecap="round"/>'; }
      return glow(P, '#fff7d1', '#f59e0b', .5) + '<g class="spin" style="animation-duration:30s">' + rays + '</g><ellipse cx="60" cy="8" rx="20" ry="5" fill="none" stroke="#fde047" stroke-width="2.4" class="pulse"/>' + motes(12, '#fff7d1', 'tw', 38, 58, 1.8);
    },
    xa_infernale: function (P) {
      var fl = polar(22, 50, function (x, y, a, i) { var h = 14 + (i % 4) * 5; return '<path d="M-5 0C-6-6 0-' + (h * .6) + ' 0-' + h + 'C3-' + (h * .6) + ' 6-6 5 0z" fill="' + (i % 2 ? '#e11d48' : '#a21caf') + '" opacity=".85" class="flick" style="animation-delay:' + (i * .08) + 's" transform="translate(' + x.toFixed(1) + ' ' + y.toFixed(1) + ') rotate(' + a.toFixed(0) + ')"/>'; });
      return glow(P, '#e11d74', '#7e22ce', .5) + fl + motes(14, '#fb923c', 'tw', 38, 58, 1.8);
    },
    xa_astrale: function (P) {
      var st = ''; for (var i = 0; i < 6; i++) st += '<path d="M' + (10 + i * 20) + ' 6l-14 22" stroke="#fff" stroke-width="1.4" stroke-linecap="round" class="fall" style="animation-delay:' + (i * .55) + 's"/>';
      return '<defs>' + lin(P + 'a', '#22d3ee', '#a78bfa', '#f472b6') + '</defs><circle cx="60" cy="60" r="54" fill="none" stroke="url(#' + P + 'a)" stroke-width="10" opacity=".45" class="pulse"/><circle cx="60" cy="60" r="50" fill="none" stroke="url(#' + P + 'a)" stroke-width="3" stroke-dasharray="20 8" class="spin" opacity=".9"/>' + st + motes(16, '#fff', 'tw', 38, 58, 1.8);
    },
    xa_caos: function (P) {
      return '<defs>' + lin(P + 'a', '#f0abfc', '#d946ef', '#22d3ee') + '</defs><g class="spin" style="animation-duration:12s"><path d="M60 8C90 8 112 30 112 60C112 80 100 92 84 92" fill="none" stroke="url(#' + P + 'a)" stroke-width="6" stroke-linecap="round"/><path d="M60 112C30 112 8 90 8 60C8 40 20 28 36 28" fill="none" stroke="url(#' + P + 'a)" stroke-width="6" stroke-linecap="round"/></g><g class="spinr" style="animation-duration:18s"><path d="M60 18C84 18 102 36 102 60" fill="none" stroke="#22d3ee" stroke-width="3" stroke-linecap="round" opacity=".8"/><path d="M60 102C36 102 18 84 18 60" fill="none" stroke="#e879f9" stroke-width="3" stroke-linecap="round" opacity=".8"/></g>' + glow(P, '#d946ef', '#06b6d4', .25) + motes(14, '#fff', 'tw', 36, 58, 1.8);
    },
    xa_galattica: function (P) {
      var arms = ''; for (var k = 0; k < 2; k++) for (var i = 0; i < 30; i++) { var t = i / 30, a = t * 5 + k * Math.PI, r = 8 + t * 50; arms += '<circle cx="' + (60 + Math.cos(a) * r).toFixed(1) + '" cy="' + (60 + Math.sin(a) * r).toFixed(1) + '" r="' + (1 + (1 - t) * 1.6).toFixed(1) + '" fill="' + (k ? '#a5b4fc' : '#f0abfc') + '" opacity="' + (.95 - t * .5).toFixed(2) + '"/>'; }
      return glow(P, '#6366f1', '#1e1b4b', .55) + '<g class="spin" style="animation-duration:36s">' + arms + '</g><circle cx="60" cy="60" r="7" fill="#fff7d1" class="pulse"/>' + motes(10, '#fff', 'tw', 20, 58, 1.4);
    },
    xa_singolarita: function (P) {
      return '<defs>' + lin(P + 'd', '#fff7d1', '#fb923c', '#7c2d12') + rad(P + 'c', '#000', '#000') + '</defs>' + glow(P, '#f59e0b', '#7e22ce', .45) + '<g class="spin" style="animation-duration:18s"><ellipse cx="60" cy="60" rx="58" ry="16" fill="none" stroke="url(#' + P + 'd)" stroke-width="5" opacity=".9"/><ellipse cx="60" cy="60" rx="46" ry="11" fill="none" stroke="#fde68a" stroke-width="2" opacity=".9"/></g><g class="spinr" style="animation-duration:24s" transform="rotate(60 60 60)"><ellipse cx="60" cy="60" rx="58" ry="14" fill="none" stroke="#c4b5fd" stroke-width="2" stroke-dasharray="3 6" opacity=".8"/></g>' + motes(14, '#fff', 'tw', 36, 58, 1.6);
    }
  };
  Object.keys(auraFns).forEach(function (k) { ART[k] = auraFns[k]; });

  /* ======================= EMBLEMI ======================= */
  function badge(P, shape, c1, c2, c3, inner) {
    var sh = { shield: 'M60 8 L102 22 V62 C102 88 82 106 60 114 C38 106 18 88 18 62 V22Z', hex: 'M60 6 L104 31 V89 L60 114 L16 89 V31Z', circle: 'M60 8 a52 52 0 1 0 .01 0Z', diamond: 'M60 4 L112 60 L60 116 L8 60Z' }[shape];
    return '<defs>' + lin(P + 'e', c1, c2, c3) + rad(P + 'n', '#1e293b', '#020617') + '</defs><path d="' + sh + '" fill="url(#' + P + 'e)" stroke="rgba(0,0,0,.6)" stroke-width="2"/><path d="' + sh + '" fill="#0b1326" transform="translate(60 60) scale(.84) translate(-60 -60)"/><path d="' + sh + '" fill="none" stroke="url(#' + P + 'e)" stroke-width="1.4" opacity=".7" transform="translate(60 60) scale(.76) translate(-60 -60)"/><g class="float">' + inner + '</g>';
  }
  var emFns = {
    xe_guardiano: function (P) { return badge(P, 'shield', '#d4a373', '#8c5a2b', '#3d2410', '<g fill="none" stroke="#f6d49c" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="M44 42l16 12 16-12M60 54v30M46 70h28"/><path d="M46 88l14-8 14 8" stroke-width="2.6"/></g><circle cx="60" cy="54" r="2.4" fill="#fde68a" class="flick"/>'); },
    xe_mago: function (P) { return badge(P, 'circle', '#e2e8f0', '#94a3b8', '#475569', '<g fill="none" stroke="#cbd5e1" stroke-width="2.6" stroke-linejoin="round"><path d="M60 26l26 45H34z"/><path d="M60 94L34 49h52z"/></g><circle cx="60" cy="60" r="8" fill="#a78bfa" stroke="#ede9fe" stroke-width="1.6" class="flick"/>'); },
    xe_spada: function (P) { return badge(P, 'shield', '#cbd5e1', '#64748b', '#1e293b', '<path d="M60 22l5 6v40l-5 6-5-6V28z" fill="#e2e8f0" stroke="#0f172a" stroke-width="1.6" transform="rotate(30 60 60)"/><path d="M44 66h32M60 66v14" stroke="#b45309" stroke-width="3.4" stroke-linecap="round" transform="rotate(30 60 60)"/><path d="M34 52C34 44 46 42 52 48L52 82C52 90 40 94 34 84Z" fill="#1d4ed8" stroke="#e2e8f0" stroke-width="2"/><path d="M43 50v38" stroke="#e2e8f0" stroke-width="1.4"/>'); },
    xe_occhio: function (P) { return badge(P, 'hex', '#fde68a', '#d4a017', '#6b4a05', '<path d="M60 26L96 88H24z" fill="none" stroke="#fbbf24" stroke-width="3" stroke-linejoin="round"/><path d="M38 64C48 54 72 54 82 64C72 74 48 74 38 64Z" fill="#0f172a" stroke="#fde68a" stroke-width="2"/><circle cx="60" cy="64" r="6" fill="#38bdf8" class="flick"/><circle cx="60" cy="64" r="2.6" fill="#020617"/><path d="M60 36v6M46 48l4 4M74 48l-4 4" stroke="#fde68a" stroke-width="2" stroke-linecap="round"/>'); },
    xe_stella: function (P) { return badge(P, 'circle', '#93c5fd', '#3b82f6', '#1e3a8a', star(60, 60, 34, '#e0f2fe', '', 0).replace('<path ', '<path stroke="#1e3a8a" stroke-width="1.4" ') + '<circle cx="60" cy="60" r="9" fill="#2563eb" stroke="#e0f2fe" stroke-width="2" class="flick"/>'); },
    xe_corona: function (P) { return badge(P, 'hex', '#fde68a', '#eab308', '#713f12', '<path d="M30 84L26 44l20 18 14-28 14 28 20-18-4 40z" fill="#fbbf24" stroke="#713f12" stroke-width="2.2" stroke-linejoin="round"/><path d="M62 38l-4 16 6 10-6 12" fill="none" stroke="#0f172a" stroke-width="2.2" stroke-linejoin="round"/><circle cx="60" cy="34" r="3.4" fill="#ef4444"/><circle cx="26" cy="42" r="3" fill="#38bdf8"/><circle cx="94" cy="42" r="3" fill="#38bdf8"/><path d="M30 88h60" stroke="#713f12" stroke-width="3"/>'); },
    xe_ali: function (P) { return badge(P, 'diamond', '#fef9c3', '#fcd34d', '#a16207', '<path d="M56 50C40 36 24 40 14 30c4 18 14 30 30 34-8 2-16 0-22-2 8 12 22 16 34 12z" fill="#fff" stroke="#a16207" stroke-width="1.6"/><path d="M64 50C80 36 96 40 106 30c-4 18-14 30-30 34 8 2 16 0 22-2-8 12-22 16-34 12z" fill="#fff" stroke="#a16207" stroke-width="1.6"/><path d="M60 40l10 16-10 20-10-20z" fill="#38bdf8" stroke="#e0f7ff" stroke-width="2" class="flick"/>'); },
    xe_teschio: function (P) { return badge(P, 'shield', '#e5e7eb', '#9ca3af', '#374151', '<path d="M40 40l6-14 8 10 6-14 6 14 8-10 6 14z" fill="#fbbf24" stroke="#713f12" stroke-width="1.6" stroke-linejoin="round"/><path d="M60 40C42 40 36 52 38 66C39 74 44 78 46 80V92H74V80C76 78 81 74 82 66C84 52 78 40 60 40Z" fill="#f3f4f6" stroke="#111827" stroke-width="2"/><circle cx="50" cy="64" r="6.4" fill="#111827"/><circle cx="70" cy="64" r="6.4" fill="#111827"/><circle cx="50" cy="64" r="2.6" fill="#f97316" class="flick"/><circle cx="70" cy="64" r="2.6" fill="#f97316" class="flick"/><path d="M60 72l-3 7h6zM52 92v-8M60 92v-8M68 92v-8" stroke="#111827" stroke-width="2"/>'); },
    xe_drago: function (P) { return badge(P, 'circle', '#fcd34d', '#d97706', '#431407', '<g class="spin" style="animation-duration:40s"><circle cx="60" cy="60" r="40" fill="none" stroke="#fbbf24" stroke-width="1.4" stroke-dasharray="2 6"/></g><path d="M30 80C26 60 36 42 54 38L58 22 66 36C82 36 94 44 92 56L102 60 90 66C86 72 76 74 70 72C64 84 48 88 30 80Z" fill="#f97316" stroke="#431407" stroke-width="2.2" stroke-linejoin="round"/><path d="M54 38L42 20 62 30z" fill="#fde68a" stroke="#431407" stroke-width="1.4"/><path d="M70 40L78 24 80 42z" fill="#fde68a" stroke="#431407" stroke-width="1.4"/><path d="M76 62l4 6 4-6 4 5" fill="none" stroke="#fff7d1" stroke-width="2" stroke-linejoin="round"/><circle cx="76" cy="50" r="3.4" fill="#fde047"/><circle cx="76" cy="50" r="1.4" fill="#7f1d1d" class="flick"/><path d="M100 60c6-2 10 2 12 6-5 0-9-2-12-6z" fill="#ef4444" class="flick"/><path d="M36 74C44 70 52 62 56 52" fill="none" stroke="#7c2d12" stroke-width="1.6" stroke-dasharray="2 4"/>'); },
    xe_infinito: function (P) { return badge(P, 'hex', '#c7d2fe', '#6366f1', '#1e1b4b', '<defs>' + lin(P + 'i', '#22d3ee', '#a78bfa', '#f472b6') + '</defs><path d="M60 60C50 44 30 44 30 60C30 76 50 76 60 60C70 44 90 44 90 60C90 76 70 76 60 60Z" fill="none" stroke="url(#' + P + 'i)" stroke-width="7" stroke-linecap="round" class="pulse"/>' + star(26, 34, 5, '#fff', 'tw', 0) + star(96, 88, 4, '#fff', 'tw', 1) + star(92, 32, 3, '#fff', 'tw', .5)); }
  };
  Object.keys(emFns).forEach(function (k) { ART[k] = emFns[k]; });

  /* ======================= EFFETTI (overlay sul profilo) ======================= */
  function falling(n, make) { var s = ''; for (var i = 0; i < n; i++) s += '<g class="fall" style="animation-delay:' + (rnd(i * 5) * 3.4).toFixed(2) + 's;animation-duration:' + (2.6 + rnd(i * 5 + 1) * 2).toFixed(2) + 's"><g transform="translate(' + (6 + rnd(i * 5 + 2) * 108).toFixed(0) + ' 0)">' + make(i) + '</g></g>'; return s; }
  var fxFns = {
    xx_scintille: function () { var s = ''; for (var i = 0; i < 14; i++) { var a = rnd(i) * 6.28, r = 38 + rnd(i + 3) * 20; s += star(60 + Math.cos(a) * r, 60 + Math.sin(a) * r, 3 + rnd(i + 6) * 4, '#fde047', 'tw', (rnd(i + 9) * 2.4).toFixed(2)); } return s; },
    xx_piume: function () { return falling(7, function (i) { return '<path d="M0 0C-5 6-5 14 0 22C5 14 5 6 0 0z" fill="' + (i % 2 ? '#fb923c' : '#ef4444') + '" transform="rotate(' + (rnd(i) * 60 - 30).toFixed(0) + ')"/><path d="M0 2v18" stroke="#fde68a" stroke-width=".8"/>'; }); },
    xx_fulmini: function () { return '<path d="M12 10l-8 22 10-2-8 24 18-28-10 2 8-16z" fill="#c4b5fd" stroke="#7c3aed" stroke-width=".8" class="flick"/><path d="M108 40l-8 20 10-2-8 22 17-26-10 2 7-14z" fill="#e9d5ff" stroke="#7c3aed" stroke-width=".8" class="flick" style="animation-delay:.5s"/><path d="M104 6l-5 14 7-1-5 14 12-17-7 1 5-9z" fill="#a78bfa" class="flick" style="animation-delay:.9s"/><path d="M8 80l-5 14 7-1-5 14 12-17-7 1 5-9z" fill="#a78bfa" class="flick" style="animation-delay:.2s"/>'; },
    xx_neve: function () { return falling(14, function (i) { var r = 2 + rnd(i) * 2.4; return '<g stroke="#e0f7ff" stroke-width="1" stroke-linecap="round"><path d="M0 -' + r * 1.6 + 'V' + r * 1.6 + 'M-' + r * 1.4 + ' -' + r * .8 + 'L' + r * 1.4 + ' ' + r * .8 + 'M-' + r * 1.4 + ' ' + r * .8 + 'L' + r * 1.4 + ' -' + r * .8 + '"/></g>'; }); },
    xx_meteore: function () { var s = ''; for (var i = 0; i < 5; i++) s += '<g class="fall" style="animation-delay:' + (i * .7).toFixed(2) + 's;animation-duration:2.2s"><g transform="translate(' + (20 + i * 22) + ' 0) rotate(-25)"><path d="M0 0L-4 -28" stroke="url(#__M)" stroke-width="3" stroke-linecap="round" opacity=".8"/><circle r="3.6" fill="#fff7d1"/><circle r="6" fill="#fb923c" opacity=".5"/></g></g>'; return '<defs>' + lin('__M', '#fff7d1', '#fb923c') + '</defs>' + s; },
    xx_anime: function (P) { var s = ''; for (var i = 0; i < 6; i++) { var a = i * 60; s += '<g class="spin" style="animation-duration:' + (9 + i * 2) + 's;animation-direction:' + (i % 2 ? 'reverse' : 'normal') + '"><g transform="rotate(' + a + ' 60 60) translate(60 ' + (8 + (i % 3) * 5) + ')"><path d="M0 0C-6 0-7 8-6 14C-4 12-3 15 0 14C3 15 4 12 6 14C7 8 6 0 0 0z" fill="#e0f2fe" opacity=".85" class="flick" style="animation-delay:' + (i * .2) + 's"/><circle cx="-2" cy="5" r="1.1" fill="#0f172a"/><circle cx="2" cy="5" r="1.1" fill="#0f172a"/></g></g>'; } return s; }
  };
  Object.keys(fxFns).forEach(function (k) { ART[k] = fxFns[k]; });

  /* ---------- API ---------- */
  var BYKEY = {}; I.forEach(function (it) { BYKEY[it.key] = it; });
  function svg(key, o) {
    o = o || {}; var f = ART[key]; if (!f) return '';
    var P = 'xa' + (++N) + '_';
    var inner = f(P).replace(/__M/g, P + 'M');
    return '<svg class="xa' + (o.anim === false ? ' st' : '') + '" viewBox="0 0 120 120" role="img" aria-label="' + esc((BYKEY[key] || {}).name || key) + '" xmlns="http://www.w3.org/2000/svg">' + inner + '</svg>';
  }
  function title(key, text) {
    var it = BYKEY[key]; if (!it || !it.title) return esc(text || '');
    var t = it.title, bg = 'linear-gradient(90deg,' + t.a + ',' + (t.c ? t.b + ',' + t.c : t.b) + ',' + t.a + ')';
    return '<span class="xt' + (t.s ? ' sh' : '') + '" style="background-image:' + bg + ';filter:drop-shadow(0 0 6px ' + t.g + ')">' + esc(text || it.name) + '</span>';
  }
  window.SHOP_EXTRA = { items: I, svg: svg, title: title, init: init, count: I.length };
})();
