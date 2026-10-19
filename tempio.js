/* tempio.js — menu a colonna sinistra (su smartphone: barra in alto + colonna che scorre da sinistra)
   e registrazione del service worker. Tutti i percorsi sono relativi alla cartella della pagina. */
(function () {
  var NAV = [
    ['Home', 'index.html', '⌂', ''],
    ['Il Sentiero', 'sentiero.html', '✦', ''],
    ['Black Market', 'black-market.html', '◈', 'bm'],
    ['Gestisci torneo', 'gestisci-torneo.html', '♜', ''],
    ['Match Pro', 'match-pro.html', '⏱', ''],
    ['Deck Analyzer', 'deck-analyzer.html', '▤', '']
  ];
  function here() {
    var p = location.pathname.split('/').pop();
    return p || 'index.html';
  }
  function mount() {
    if (document.getElementById('tmCol')) return;
    var cur = here();
    var links = NAV.map(function (n) {
      return '<a class="' + n[3] + '" href="' + n[1] + '"' + (n[1] === cur ? ' aria-current="page"' : '') + '><i aria-hidden="true">' + n[2] + '</i>' + n[0] + '</a>';
    }).join('');
    var col = document.createElement('aside');
    col.className = 'tm'; col.id = 'tmCol'; col.setAttribute('aria-label', 'Navigazione');
    col.innerHTML = '<div class="tm-h"><a class="tm-b" href="index.html"><img src="logo1.png" alt="Il Tempio Dei Duelli"></a><button class="tm-x" id="tmX" type="button">Chiudi menu</button></div>' +
      '<nav class="tm-n">' + links + '</nav><div class="tm-f">Community Yu-Gi-Oh! · Bologna</div>';
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
    t.onclick = function () { set(true); };
    x.onclick = function () { set(false); };
    s.onclick = function () { set(false); };
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && col.classList.contains('open')) set(false); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount); else mount();
  if ('serviceWorker' in navigator) addEventListener('load', function () { navigator.serviceWorker.register('sw.js').catch(function () {}); });
})();
