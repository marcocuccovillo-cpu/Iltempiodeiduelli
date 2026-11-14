/* tempio.js — navigazione globale e registrazione del service worker. Tutti i percorsi sono relativi alla cartella della pagina.
   Computer e tablet larghi: menu a colonna a sinistra.
   Smartphone: barra in alto con il nome della pagina + BARRA IN BASSO come nelle app (Home, Black Market, Eroi, Strumenti, FAQ);
   «Strumenti» apre un foglio dal basso con Duel Simulator, Gestisci torneo, Match Pro, Deck Analyzer e Installa app.
   Il Sentiero e Invita amici non sono più nel menu globale: stanno tra le sezioni del Black Market. */
(function () {
  var NAV = [
    ['Home', 'index.html', '⌂', ''],
    ['Black Market', 'black-market.html', '◈', 'bm'],
    ['La guerra degli Eroi', 'eroi.html', '⚜', ''],
    ['Duel Simulator', 'duel-simulator.html', '♠', ''],
    ['Gestisci torneo', 'gestisci-torneo.html', '♜', ''],
    ['Match Pro', 'match-pro.html', '⏱', ''],
    ['Deck Analyzer', 'deck-analyzer.html', '▤', ''],
    ['FAQ', 'faq.html', '?', 'faq']
  ];
  /* il Sentiero vive nel Black Market: lì si accende la voce Black Market */
  var ALIAS = { 'sentiero.html': 'black-market.html' };
  var TOOLS = ['duel-simulator.html', 'gestisci-torneo.html', 'match-pro.html', 'deck-analyzer.html'];
  var TAB = [['Home', 'index.html', '⌂'], ['Black Market', 'black-market.html', '◈'], ['Eroi', 'eroi.html', '⚜'], ['Strumenti', '#strumenti', '🧰'], ['FAQ', 'faq.html', '?']];
  var TITLE = { 'index.html': 'Il Tempio Dei Duelli', 'black-market.html': 'Black Market', 'sentiero.html': 'Il Sentiero', 'eroi.html': 'La guerra degli Eroi', 'duel-simulator.html': 'Duel Simulator', 'gestisci-torneo.html': 'Gestisci torneo', 'match-pro.html': 'Match Pro', 'deck-analyzer.html': 'Deck Analyzer', 'faq.html': 'Domande frequenti' };
  /* ---- link d'invito: index.html?invito=CODICE → si ricorda il codice (lo usa il Black Market alla registrazione) e si pulisce l'indirizzo ---- */
  try {
    var inv = /[?&]invito=([A-Za-z0-9]{6})(?:&|$)/.exec(location.search);
    if (inv) {
      localStorage.setItem('tempio.invito', inv[1].toUpperCase());
      var qs = location.search.replace(/([?&])invito=[^&]*&?/, '$1').replace(/[?&]$/, '');
      history.replaceState(null, '', location.pathname + qs + location.hash);
    }
  } catch (e) {}
  /* ---- condivisione su WhatsApp (tempio-condividi.js), caricata su tutte le pagine ---- */
  if (!window.TempioShare && !document.getElementById('tmShareJs')) {
    var sj = document.createElement('script'); sj.id = 'tmShareJs'; sj.src = 'tempio-condividi.js?v=1'; sj.defer = true; document.head.appendChild(sj);
  }
  /* ---- installazione sulla schermata Home ---- */
  var deferred = null;
  var standalone = function () { return (window.matchMedia && matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true; };
  addEventListener('beforeinstallprompt', function (e) { e.preventDefault(); deferred = e; refreshInstall(); });
  addEventListener('appinstalled', function () { deferred = null; refreshInstall(); });
  function refreshInstall() { var b = document.getElementById('tmI'); if (b) b.hidden = standalone(); }
  function howTo() {
    var ua = navigator.userAgent, ios = /iphone|ipad|ipod/i.test(ua) || (/Mac/.test(ua) && navigator.maxTouchPoints > 1);
    if (ios) return ['Su iPhone e iPad', 'Apri questa pagina in <b>Safari</b>, tocca il pulsante <b>Condividi</b> (quadrato con la freccia) e scegli <b>Aggiungi alla schermata Home</b>.'];
    if (/android/i.test(ua)) return ['Su Android', 'Apri il menu <b>⋮</b> di Chrome (in alto a destra) e tocca <b>Installa app</b> oppure <b>Aggiungi a schermata Home</b>. Se non compare, ricarica la pagina e riprova.'];
    return ['Su computer e Chromebook', 'In Chrome o Edge cerca l\'icona <b>Installa</b> a destra della barra dell\'indirizzo, oppure apri il menu <b>⋮</b> › <b>Installa Il Tempio Dei Duelli</b> (o <b>Salva e condividi › Installa</b>).'];
  }
  function install() {
    if (deferred) {
      var d = deferred; deferred = null;
      d.prompt();
      d.userChoice.then(function (c) { if (c && c.outcome === 'accepted') refreshInstall(); }).catch(function () {});
      return;
    }
    var h = howTo(), m = document.createElement('div');
    m.className = 'tm-m'; m.setAttribute('role', 'dialog'); m.setAttribute('aria-modal', 'true'); m.setAttribute('aria-label', 'Installa l\'app');
    m.innerHTML = '<div class="tm-mb"><h2>Installa l\'app sulla Home</h2><p><b>' + h[0] + '</b></p><p>' + h[1] + '</p><p class="tm-mn">Il browser decide quando offrire l\'installazione automatica: se il pulsante non la avvia, queste istruzioni funzionano sempre.</p><button type="button" class="tm-mc">Ho capito</button></div>';
    document.body.appendChild(m);
    var c = m.querySelector('.tm-mc'); c.focus();
    function close() { m.remove(); document.removeEventListener('keydown', k); }
    function k(e) { if (e.key === 'Escape') close(); }
    c.onclick = close; m.onclick = function (e) { if (e.target === m) close(); }; document.addEventListener('keydown', k);
  }
  function page() { return location.pathname.split('/').pop() || 'index.html'; }
  function here() { var p = page(); return ALIAS[p] || p; }
  function mount() {
    if (document.getElementById('tmCol')) return;
    var cur = here();
    /* una voce con #… (es. Ladder) è la pagina corrente solo se l'indirizzo comincia con quel #; la voce senza # lo è negli altri casi */
    function isCur(n) {
      var f = n[1].split('#')[0], h = n[1].split('#')[1];
      if (f !== cur) return false;
      if (h) return location.hash.indexOf('#' + h) === 0;
      return !NAV.some(function (m) { var mh = m[1].split('#')[1]; return m !== n && m[1].split('#')[0] === f && mh && location.hash.indexOf('#' + mh) === 0; });
    }
    var links = NAV.map(function (n) {
      return '<a class="' + n[3] + '" href="' + n[1] + '"' + (isCur(n) ? ' aria-current="page"' : '') + '><i aria-hidden="true">' + n[2] + '</i>' + n[0] + '</a>';
    }).join('');
    var col = document.createElement('aside');
    col.className = 'tm'; col.id = 'tmCol'; col.setAttribute('aria-label', 'Navigazione');
    col.innerHTML = '<div class="tm-h"><a class="tm-b" href="index.html"><img src="tempio-logo.svg?v=1" alt="" width="512" height="512"><span class="tm-t">Il Tempio<br>Dei Duelli</span></a><button class="tm-x" id="tmX" type="button">Chiudi menu</button></div>' +
      '<nav class="tm-n">' + links + '<button type="button" class="tm-i" id="tmI"><i aria-hidden="true">⤓</i>Installa app</button></nav><div class="tm-f">Community Yu-Gi-Oh! · Bologna · v10</div>';
    var bar = document.createElement('div');
    bar.className = 'tm-bar';
    bar.innerHTML = '<a class="tm-home" href="index.html" aria-label="Home"><img src="tempio-mark.png" alt=""></a><span>' + (TITLE[page()] || document.title.split('—')[0].trim() || 'Il Tempio Dei Duelli') + '</span>';
    /* barra in basso (smartphone) */
    var isTool = TOOLS.indexOf(cur) >= 0;
    var tb = document.createElement('nav');
    tb.className = 'tm-tb'; tb.id = 'tmTb'; tb.setAttribute('aria-label', 'Navigazione principale');
    tb.innerHTML = TAB.map(function (n) {
      var on = n[1] === '#strumenti' ? isTool : n[1] === cur;
      if (n[1] === '#strumenti') return '<button type="button" id="tmTools" aria-haspopup="dialog" aria-expanded="false"' + (on ? ' aria-current="page"' : '') + '><i aria-hidden="true">' + n[2] + '</i><span>' + n[0] + '</span></button>';
      return '<a href="' + n[1] + '"' + (on ? ' aria-current="page"' : '') + '><i aria-hidden="true">' + n[2] + '</i><span>' + n[0] + '</span></a>';
    }).join('');
    /* foglio «Strumenti» */
    var sh = document.createElement('div');
    sh.className = 'tm-sh'; sh.id = 'tmSh'; sh.setAttribute('role', 'dialog'); sh.setAttribute('aria-modal', 'true'); sh.setAttribute('aria-label', 'Strumenti'); sh.hidden = true;
    sh.innerHTML = '<div class="tm-shb"><div class="tm-grab" aria-hidden="true"></div><h2>Strumenti</h2><div class="tm-shg">' +
      [['duel-simulator.html', '♠', 'Duel Simulator', 'Duelli 1 contro 1'], ['gestisci-torneo.html', '♜', 'Gestisci torneo', 'Swiss, tavoli, classifica'], ['match-pro.html', '⏱', 'Match Pro', 'Life Points e timer'], ['deck-analyzer.html', '▤', 'Deck Analyzer', 'Probabilità e mani']].map(function (n) {
        return '<a href="' + n[0] + '"' + (n[0] === cur ? ' aria-current="page"' : '') + '><i aria-hidden="true">' + n[1] + '</i><b>' + n[2] + '</b><small>' + n[3] + '</small></a>';
      }).join('') + '</div><button type="button" class="tm-shi" id="tmI2"><i aria-hidden="true">⤓</i>Installa l\'app sul telefono</button><button type="button" class="tm-shx" id="tmShX">Chiudi</button></div>';
    var s = document.createElement('div');
    s.className = 'tm-s';
    document.body.append(col, bar, tb, sh, s);
    document.documentElement.classList.add('tm-has-tb');
    var x = document.getElementById('tmX'), tt = document.getElementById('tmTools');
    function set(v) { col.classList.toggle('open', v); s.classList.toggle('on', v); if (v) x.focus(); }
    function sheet(v) {
      if (v) { sh.hidden = false; requestAnimationFrame(function () { sh.classList.add('open'); }); s.classList.add('on'); tt.setAttribute('aria-expanded', 'true'); var f = sh.querySelector('a'); if (f) f.focus(); }
      else { sh.classList.remove('open'); s.classList.remove('on'); tt.setAttribute('aria-expanded', 'false'); setTimeout(function () { if (!sh.classList.contains('open')) sh.hidden = true; }, 220); }
    }
    tt.onclick = function () { sheet(sh.hidden || !sh.classList.contains('open')); };
    document.getElementById('tmShX').onclick = function () { sheet(false); tt.focus(); };
    document.getElementById('tmI2').onclick = function () { sheet(false); install(); };
    var i2 = document.getElementById('tmI2'); if (standalone()) i2.hidden = true;
    addEventListener('hashchange', function () {
      var as = col.querySelectorAll('.tm-n a');
      NAV.forEach(function (n, i) { if (isCur(n)) as[i].setAttribute('aria-current', 'page'); else as[i].removeAttribute('aria-current'); });
    });
    document.getElementById('tmI').onclick = function () { set(false); install(); };
    refreshInstall();
    x.onclick = function () { set(false); };
    s.onclick = function () { set(false); sheet(false); };
    document.addEventListener('keydown', function (e) { if (e.key !== 'Escape') return; if (col.classList.contains('open')) set(false); if (!sh.hidden) { sheet(false); tt.focus(); } });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();
  if ('serviceWorker' in navigator) addEventListener('load', function () { navigator.serviceWorker.register('sw.js').catch(function () {}); });
})();
