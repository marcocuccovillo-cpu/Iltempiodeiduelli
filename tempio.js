/* tempio.js — menu a colonna sinistra (su smartphone: barra in alto + colonna che scorre da sinistra)
   e registrazione del service worker. Tutti i percorsi sono relativi alla cartella della pagina. */
(function () {
  var NAV = [
    ['Home', 'index.html', '⌂', ''],
    ['Il Sentiero', 'sentiero.html', '✦', ''],
    ['Black Market', 'black-market.html', '◈', 'bm'],
    ['Ladder', 'black-market.html#/ladder', '⚔', 'bm'],
    ['Black Market Shop', 'black-market.html#/shop', '❖', 'bm'],
    ['La guerra degli Eroi', 'eroi.html', '⚜', ''],
    ['Gestisci torneo', 'gestisci-torneo.html', '♜', ''],
    ['Match Pro', 'match-pro.html', '⏱', ''],
    ['Deck Analyzer', 'deck-analyzer.html', '▤', '']
  ];
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
  function here() {
    var p = location.pathname.split('/').pop();
    return p || 'index.html';
  }
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
      '<nav class="tm-n">' + links + '<button type="button" class="tm-i" id="tmI"><i aria-hidden="true">⤓</i>Installa app</button></nav><div class="tm-f">Community Yu-Gi-Oh! · Bologna · v8</div>';
    var bar = document.createElement('div');
    bar.className = 'tm-bar';
    bar.innerHTML = '<button type="button" id="tmT" aria-label="Apri il menu" aria-expanded="false" aria-controls="tmCol">☰</button><img src="tempio-mark.png" alt=""><span>Il Tempio Dei Duelli</span>';
    var s = document.createElement('div');
    s.className = 'tm-s';
    document.body.append(col, bar, s);
    var t = document.getElementById('tmT'), x = document.getElementById('tmX');
    function set(v) {
      col.classList.toggle('open', v); s.classList.toggle('on', v);
      t.setAttribute('aria-expanded', v);
      (v ? x : t).focus();
    }
    addEventListener('hashchange', function () {
      var as = col.querySelectorAll('.tm-n a');
      NAV.forEach(function (n, i) { if (isCur(n)) as[i].setAttribute('aria-current', 'page'); else as[i].removeAttribute('aria-current'); });
    });
    document.getElementById('tmI').onclick = function () { set(false); install(); };
    refreshInstall();
    t.onclick = function () { set(true); };
    x.onclick = function () { set(false); };
    s.onclick = function () { set(false); };
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && col.classList.contains('open')) set(false); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();
  if ('serviceWorker' in navigator) addEventListener('load', function () { navigator.serviceWorker.register('sw.js').catch(function () {}); });
})();
