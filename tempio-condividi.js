/* =====================================================================
   TEMPIO — CONDIVIDI SU WHATSAPP
   Disegna una «card» quadrata (1080×1080) con logo, titolo e risultato e la passa al menu di condivisione del telefono
   (WhatsApp, Telegram, Instagram…). Dove il browser non sa condividere immagini mostra l'anteprima con «Scarica» e «Apri WhatsApp».
   Il link nel messaggio porta alla Home con il codice invito di chi condivide (se ha un profilo): ogni condivisione è un invito.
   Uso: TempioShare.share({ kind, title, sub, text, svg | emoji | big, stats: [[etichetta, valore]…], msg, tone: 'gold'|'red'|'violet' })
        TempioShare.text(messaggio)   → solo testo + link
        TempioShare.link()            → il link con il mio codice invito
   Nessuna dipendenza esterna, nessun dato inviato a server: l'immagine nasce e resta nel telefono.
   ===================================================================== */
(function () {
  'use strict';
  var TONE = { violet: ['#a78bfa', '124,58,237'], gold: ['#e8b84a', '232,184,74'], red: ['#ff5468', '156,31,49'] };
  var base = function () { return location.origin + location.pathname.replace(/[^/]*$/, ''); };
  var myCode = function () { try { return localStorage.getItem('tempio.mycode') || ''; } catch (e) { return ''; } };
  function link() { var c = myCode(); return base() + 'index.html' + (c ? '?invito=' + encodeURIComponent(c) : ''); }
  function waText(msg) { return msg + '\n\n👉 ' + link() + (myCode() ? '\n(con il mio invito: +100 BC extra al tuo primo match)' : ''); }

  function loadImg(src) {
    return new Promise(function (ok) { var i = new Image(); i.onload = function () { ok(i); }; i.onerror = function () { ok(null); }; i.src = src; });
  }
  function svgImg(svg) {
    var u = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
    return loadImg(u).then(function (i) { URL.revokeObjectURL(u); return i; });
  }
  /* a capo automatico, al massimo maxL righe (l'ultima con «…») */
  function wrap(ctx, s, maxW, maxL) {
    var words = String(s || '').split(/\s+/), lines = [], cur = '';
    words.forEach(function (w) { var t = cur ? cur + ' ' + w : w; if (ctx.measureText(t).width > maxW && cur) { lines.push(cur); cur = w; } else cur = t; });
    if (cur) lines.push(cur);
    if (lines.length > maxL) { lines = lines.slice(0, maxL); var l = lines[maxL - 1]; while (ctx.measureText(l + '…').width > maxW && l.length) l = l.slice(0, -1); lines[maxL - 1] = l + '…'; }
    return lines;
  }
  function fit(ctx, s, font, size, maxW, min) { do { ctx.font = font.replace('#', size); size -= 2; } while (ctx.measureText(s).width > maxW && size > min); }

  function draw(o) {
    var W = 1080, c = document.createElement('canvas'), x = c.getContext('2d'), tn = TONE[o.tone] || TONE.violet;
    c.width = W; c.height = W;
    var fontsReady = document.fonts && document.fonts.load ? Promise.all([document.fonts.load('700 60px Cinzel'), document.fonts.load('700 30px Inter'), document.fonts.load('400 30px Inter')]).catch(function () {}) : Promise.resolve();
    return Promise.all([fontsReady, loadImg('tempio-logo.svg?v=1'), o.svg ? svgImg(o.svg) : null, o.img ? loadImg(o.img) : null]).then(function (r) {
      var logo = r[1], vis = r[2] || r[3];
      /* fondo */
      x.fillStyle = '#05030c'; x.fillRect(0, 0, W, W);
      var g = x.createRadialGradient(540, 470, 40, 540, 470, 620); g.addColorStop(0, 'rgba(' + tn[1] + ',.42)'); g.addColorStop(1, 'rgba(0,0,0,0)'); x.fillStyle = g; x.fillRect(0, 0, W, W);
      g = x.createRadialGradient(980, 60, 10, 980, 60, 420); g.addColorStop(0, 'rgba(124,58,237,.35)'); g.addColorStop(1, 'rgba(0,0,0,0)'); x.fillStyle = g; x.fillRect(0, 0, W, W);
      x.strokeStyle = 'rgba(167,139,250,.4)'; x.lineWidth = 3; x.beginPath(); if (x.roundRect) x.roundRect(26, 26, W - 52, W - 52, 34); else x.rect(26, 26, W - 52, W - 52); x.stroke();
      /* intestazione */
      if (logo) x.drawImage(logo, 70, 62, 104, 104);
      x.fillStyle = '#ece8f8'; x.font = '700 40px Cinzel, Georgia, serif'; x.textBaseline = 'middle'; x.textAlign = 'left';
      x.fillText('Il Tempio Dei Duelli', 192, 100); x.fillStyle = '#a39db8'; x.font = '600 24px Inter, sans-serif'; x.fillText('YU-GI-OH! · BOLOGNA', 194, 140);
      /* etichetta */
      x.textAlign = 'center'; x.fillStyle = tn[0]; x.font = '700 30px Inter, sans-serif';
      var k = String(o.kind || '').toUpperCase().split('').join(String.fromCharCode(8202)); x.fillText(k, 540, 232);
      /* visuale centrale */
      var y = 270;
      if (vis) { var s = 340; x.save(); x.shadowColor = 'rgba(' + tn[1] + ',.8)'; x.shadowBlur = 60; x.drawImage(vis, 540 - s / 2, y, s, s); x.restore(); y += s + 30; }
      else if (o.emoji) { x.font = '200px "Noto Color Emoji", "Apple Color Emoji", "Segoe UI Emoji", sans-serif'; x.textBaseline = 'top'; x.fillText(o.emoji, 540, y + 10); x.textBaseline = 'middle'; y += 260; }
      else if (o.big) { fit(x, o.big, '700 #px Cinzel, Georgia, serif', 170, 900, 70); var gg = x.createLinearGradient(0, y, 0, y + 170); gg.addColorStop(0, '#fff'); gg.addColorStop(1, tn[0]); x.fillStyle = gg; x.fillText(o.big, 540, y + 95); y += 210; }
      /* titolo, sottotitolo, testo */
      x.fillStyle = '#ffffff'; fit(x, o.title || '', '700 #px Cinzel, Georgia, serif', 74, 940, 40);
      var tl = wrap(x, o.title || '', 940, 2); tl.forEach(function (l, i) { x.fillText(l, 540, y + 40 + i * 80); }); y += 40 + tl.length * 80;
      if (o.sub) { x.fillStyle = tn[0]; x.font = '700 34px Inter, sans-serif'; wrap(x, o.sub, 940, 1).forEach(function (l) { x.fillText(l, 540, y + 6); }); y += 56; }
      if (o.text) { x.fillStyle = '#cfc9e2'; x.font = '400 30px Inter, sans-serif'; wrap(x, o.text, 900, 2).forEach(function (l, i) { x.fillText(l, 540, y + 10 + i * 42); }); }
      /* numeri */
      if (o.stats && o.stats.length) {
        var n = Math.min(o.stats.length, 3), bw = 280, gap = 22, sx = 540 - (n * bw + (n - 1) * gap) / 2, by = 852;
        o.stats.slice(0, 3).forEach(function (st, i) {
          var bx = sx + i * (bw + gap);
          x.fillStyle = 'rgba(255,255,255,.06)'; x.strokeStyle = 'rgba(' + tn[1] + ',.55)'; x.lineWidth = 2;
          x.beginPath(); if (x.roundRect) x.roundRect(bx, by, bw, 104, 18); else x.rect(bx, by, bw, 104); x.fill(); x.stroke();
          x.fillStyle = '#fff'; fit(x, String(st[1]), '700 #px Inter, sans-serif', 40, bw - 30, 22); x.fillText(String(st[1]), bx + bw / 2, by + 40);
          x.fillStyle = '#a39db8'; x.font = '600 22px Inter, sans-serif'; x.fillText(String(st[0]), bx + bw / 2, by + 80);
        });
      }
      /* piè di pagina */
      x.fillStyle = '#e8b84a'; x.font = '700 28px Inter, sans-serif'; x.fillText('Entra gratis: 1000 BC di benvenuto', 540, 1000);
      x.fillStyle = '#a39db8'; x.font = '500 22px Inter, sans-serif'; x.fillText(base().replace(/^https?:\/\//, '').replace(/\/$/, ''), 540, 1036);
      return new Promise(function (ok) { c.toBlob(function (b) { ok(b); }, 'image/png'); });
    });
  }

  function fallback(blob, msg) {
    var u = URL.createObjectURL(blob), m = document.createElement('div');
    m.className = 'tm-m'; m.setAttribute('role', 'dialog'); m.setAttribute('aria-modal', 'true'); m.setAttribute('aria-label', 'Condividi');
    m.innerHTML = '<div class="tm-mb" style="max-width:420px"><h2>Condividi</h2><img src="' + u + '" alt="Anteprima dell\'immagine da condividere" style="width:100%;border-radius:12px;margin:8px 0 12px">' +
      '<div class="row" style="justify-content:center"><a class="btn" download="tempio-dei-duelli.png" href="' + u + '">1. Scarica immagine</a>' +
      '<a class="btn gold" target="_blank" rel="noopener" href="https://wa.me/?text=' + encodeURIComponent(waText(msg)) + '">2. Apri WhatsApp</a></div>' +
      '<p class="tm-mn">Su questo browser l\'immagine non si allega da sola: scaricala e allegala al messaggio.</p><button type="button" class="tm-mc">Chiudi</button></div>';
    document.body.appendChild(m);
    function close() { m.remove(); URL.revokeObjectURL(u); }
    m.querySelector('.tm-mc').onclick = close; m.onclick = function (e) { if (e.target === m) close(); };
  }

  var busy = false;
  function share(o) {
    if (busy) return Promise.resolve(); busy = true;
    var msg = o.msg || o.title || 'Il Tempio Dei Duelli';
    return draw(o).then(function (blob) {
      var file = new File([blob], 'tempio-dei-duelli.png', { type: 'image/png' });
      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        return navigator.share({ files: [file], text: waText(msg) }).catch(function (e) { if (e && e.name !== 'AbortError') fallback(blob, msg); });
      }
      fallback(blob, msg);
    }).catch(function () { text(msg); }).then(function () { busy = false; });
  }
  function text(msg) {
    var t = waText(msg);
    if (navigator.share) return navigator.share({ text: t }).catch(function () {});
    window.open('https://wa.me/?text=' + encodeURIComponent(t), '_blank', 'noopener');
    return Promise.resolve();
  }
  window.TempioShare = { share: share, text: text, link: link, draw: draw, waText: waText };
})();
