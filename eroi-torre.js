/* La guerra degli Eroi — Torre Infinita: grafica.
   Tutti gli sprite sono disegnati qui dentro, in codice (pixel art originale, nessuna immagine esterna): boss, nemici, eroe, zone della Torre.
   Uso: TorreArt.sprite('golem', {tier:0}) → <img> pronto (data URI, ingrandito senza sfocare); TorreArt.zone(piano) → informazioni sulla zona. */
(function (g) {
  'use strict';
  /* ---------- colori ---------- */
  function h2r(h) { h = h.replace('#', ''); if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]; return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]; }
  function r2h(a) { return '#' + a.map(function (v) { v = Math.max(0, Math.min(255, Math.round(v))); return (v < 16 ? '0' : '') + v.toString(16); }).join(''); }
  function mix(a, b, t) { var x = h2r(a), y = h2r(b); return r2h([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t]); }
  var TONES = {};
  function shade(c, k) {
    var key = c + k; if (TONES[key]) return TONES[key];
    var r = c;
    if (k === -2) r = mix(c, '#12092a', .66); else if (k === -1) r = mix(mix(c, '#2a1a5a', .34), '#000000', .06);
    else if (k === 1) r = mix(c, '#fff3cf', .30); else if (k === 2) r = mix(c, '#ffffff', .58);
    TONES[key] = r; return r;
  }

  /* ---------- griglia di pixel ---------- */
  function Px(w, h) { this.w = w; this.h = h; this.d = new Array(w * h).fill(null); this.cx = (w - 1) / 2; }
  var P = Px.prototype;
  P.put = function (x, y, c) { x = Math.round(x); y = Math.round(y); if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.d[y * this.w + x] = c; return this; };
  P.get = function (x, y) { return (x < 0 || y < 0 || x >= this.w || y >= this.h) ? null : this.d[y * this.w + x]; };
  function tone(l, o) { return l > .5 ? 1 : l < -.78 ? -2 : l < -.28 ? -1 : 0; }
  // ellisse con luce da in alto a sinistra
  P.ell = function (cx, cy, rx, ry, c, o) {
    o = o || {};
    for (var y = Math.floor(cy - ry - 1); y <= Math.ceil(cy + ry + 1); y++) for (var x = Math.floor(cx - rx - 1); x <= Math.ceil(cx + rx + 1); x++) {
      var nx = (x - cx) / rx, ny = (y - cy) / ry;
      if (nx * nx + ny * ny <= 1.0) { var l = -(nx * .55 + ny * .8); this.put(x, y, o.flat ? c : shade(c, tone(l))); }
    }
    return this;
  };
  P.ell2 = function (dx, cy, rx, ry, c, o) { this.ell(this.cx - dx, cy, rx, ry, c, o); this.ell(this.cx + dx, cy, rx, ry, c, o); return this; };
  // rettangolo: bordo alto/sinistro chiaro, basso/destro scuro
  P.rect = function (x, y, w, h, c, o) {
    o = o || {};
    for (var j = 0; j < h; j++) for (var i = 0; i < w; i++) {
      var k = 0;
      if (!o.flat) { if (j === 0 || i === 0) k = 1; if (j === h - 1 || i === w - 1) k = -1; if (h > 5 && j >= h - 2) k = -1; if (w <= 2) k = 0; }
      this.put(x + i, y + j, shade(c, k));
    }
    return this;
  };
  P.rect2 = function (dx, y, w, h, c, o) { this.rect(Math.round(this.cx - dx - w + 1), y, w, h, c, o); this.rect(Math.round(this.cx + dx), y, w, h, c, o); return this; };
  // poligono pieno (scanline), ombreggiato in base alla posizione
  P.poly = function (pts, c, o) {
    o = o || {};
    var ys = pts.map(function (p) { return p[1]; }), xs = pts.map(function (p) { return p[0]; });
    var y0 = Math.floor(Math.min.apply(null, ys)), y1 = Math.ceil(Math.max.apply(null, ys)), x0 = Math.min.apply(null, xs), x1 = Math.max.apply(null, xs);
    for (var y = y0; y <= y1; y++) {
      var cuts = [];
      for (var i = 0; i < pts.length; i++) {
        var a = pts[i], b = pts[(i + 1) % pts.length];
        if ((a[1] <= y + .5 && b[1] > y + .5) || (b[1] <= y + .5 && a[1] > y + .5)) cuts.push(a[0] + (y + .5 - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
      }
      cuts.sort(function (p, q) { return p - q; });
      for (var j = 0; j + 1 < cuts.length; j += 2) for (var x = Math.round(cuts[j]); x < Math.round(cuts[j + 1]); x++) {
        var l = o.flat ? 0 : -(((x - x0) / Math.max(1, x1 - x0) - .5) * .9 + ((y - y0) / Math.max(1, y1 - y0) - .5) * 1.1);
        this.put(x, y, o.flat ? c : shade(c, tone(l)));
      }
    }
    return this;
  };
  P.poly2 = function (pts, c, o) { this.poly(pts, c, o); this.poly(pts.map(function (p) { return [this.w - 1 - p[0], p[1]]; }, this), c, o); return this; };
  P.line = function (x0, y0, x1, y1, c, t) {
    t = t || 1; var n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0), 1);
    for (var i = 0; i <= n; i++) { var x = x0 + (x1 - x0) * i / n, y = y0 + (y1 - y0) * i / n; if (t <= 1) this.put(x, y, c); else this.ell(x, y, t / 2, t / 2, c, { flat: true }); }
    return this;
  };
  P.line2 = function (x0, y0, x1, y1, c, t) { this.line(x0, y0, x1, y1, c, t); this.line(this.w - 1 - x0, y0, this.w - 1 - x1, y1, c, t); return this; };
  // tubo curvo con raggio variabile (tentacoli, colli, code): punti [x,y,r]
  P.tube = function (pts, c, o) {
    o = o || {};
    for (var s = 0; s + 1 < pts.length; s++) {
      var a = pts[s], b = pts[s + 1], n = Math.max(2, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) * 1.5));
      for (var i = 0; i <= n; i++) { var t = i / n; this.ell(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[2] + (b[2] - a[2]) * t, c, o); }
    }
    return this;
  };
  P.px = function (x, y, c) { return this.put(x, y, c); };
  P.px2 = function (dx, y, c) { this.put(Math.round(this.cx - dx), y, c); this.put(Math.round(this.cx + dx), y, c); return this; };
  // occhio luminoso (2×2 con riflesso)
  P.eye = function (x, y, c, big) { this.put(x, y, c); this.put(x + 1, y, c); this.put(x, y + 1, shade(c, -1)); this.put(x + 1, y + 1, shade(c, -1)); if (big) { this.put(x - 1, y, shade(c, -1)); this.put(x + 2, y, shade(c, -1)); } this.put(x, y, '#ffffff'); return this; };
  P.eye2 = function (dx, y, c, big) { var l = Math.round(this.cx - dx - .5), r = Math.round(this.cx + dx - .5); this.eye(l, y, c, big); this.eye(r, y, c, big); return this; };
  // contorno scuro intorno a tutto
  P.outline = function (c) {
    var add = [];
    for (var y = 0; y < this.h; y++) for (var x = 0; x < this.w; x++) if (!this.get(x, y)) {
      if (this.get(x - 1, y) || this.get(x + 1, y) || this.get(x, y - 1) || this.get(x, y + 1)) add.push([x, y]);
    }
    for (var i = 0; i < add.length; i++) this.put(add[i][0], add[i][1], c);
    return this;
  };
  // bagliore: pixel semitrasparenti intorno alle parti chiare (non usato per le sagome)
  P.canvas = function (scale) {
    var cv = document.createElement('canvas'); cv.width = this.w * scale; cv.height = this.h * scale; var cx = cv.getContext('2d');
    for (var y = 0; y < this.h; y++) for (var x = 0; x < this.w; x++) { var c = this.d[y * this.w + x]; if (c) { cx.fillStyle = c; cx.fillRect(x * scale, y * scale, scale, scale); } }
    return cv;
  };

  var OUT = '#160c2c';

  /* ---------- sprite dei boss (40×40) ---------- */
  var ART = {};
  var BOSSPX = 40;

  ART.golem = function () {
    var p = new Px(BOSSPX, BOSSPX), paper = '#e6d5a8', dk = '#b79a62', rune = '#ff9f43';
    p.rect(12, 28, 7, 9, dk); p.rect(21, 28, 7, 9, dk); p.rect(11, 35, 9, 3, '#a8895a'); p.rect(20, 35, 9, 3, '#a8895a');       // gambe e piedi
    p.rect(8, 12, 24, 18, paper);                                                                                               // torso
    p.ell2(11.5, 14, 4.5, 4.5, '#efe0b8');                                                                                      // spalle
    p.rect(2, 15, 7, 15, paper); p.rect(31, 15, 7, 15, paper); p.rect(1, 29, 9, 8, '#d9c592'); p.rect(30, 29, 9, 8, '#d9c592');    // braccia e pugni
    p.rect(12, 1, 16, 12, '#efe0b8');                                                                                           // testa
    for (var y = 14; y < 29; y += 5) p.line(9, y, 30, y, dk);                                                                    // pieghe orizzontali
    p.line(19, 13, 19, 29, dk); p.line(14, 14, 14, 29, mix(dk, paper, .5)); p.line(25, 14, 25, 29, mix(dk, paper, .5));          // pieghe verticali
    for (var y2 = 18; y2 < 30; y2 += 5) { p.line(3, y2, 7, y2, dk); p.line(32, y2, 36, y2, dk); }
    p.rect(15, 4, 4, 4, '#2a1a0c', { flat: true }); p.rect(21, 4, 4, 4, '#2a1a0c', { flat: true });                             // occhiaie
    p.eye(16, 5, rune); p.eye(22, 5, rune);
    p.rect(17, 10, 6, 1, dk, { flat: true });                                                                                    // bocca
    p.poly([[19.5, 17], [23, 21], [19.5, 25], [16, 21]], rune, { flat: true }); p.poly([[19.5, 19], [21, 21], [19.5, 23], [18, 21]], '#ffe29a', { flat: true }); // runa sul petto
    p.poly([[6, 10], [9, 7], [10, 12]], '#f6e9c6'); p.poly([[33, 9], [30, 6], [29, 12]], '#f6e9c6'); p.poly([[3, 36], [1, 39], [6, 38]], '#e6d5a8', { flat: true }); // pagine che spuntano
    return p.outline(OUT);
  };

  ART.drago = function () {
    var p = new Px(BOSSPX, BOSSPX), sc = '#2fa7a0', dk = '#1d6f7a', belly = '#f2e3b3';
    p.poly2([[16, 20], [3, 4], [8, 14], [4, 16], [10, 22], [6, 27], [13, 28]], '#3a6fc0');                                          // ali
    p.line(16, 20, 4, 6, '#9cc1f5'); p.line(14, 22, 6, 17, '#9cc1f5'); p.line(14, 24, 8, 26, '#9cc1f5');
    p.line(23, 20, 35, 6, '#9cc1f5'); p.line(25, 22, 33, 17, '#9cc1f5'); p.line(25, 24, 31, 26, '#9cc1f5');
    p.tube([[19.5, 12, 3], [19.5, 18, 4.5]], sc);                                                                                // collo
    p.ell(19.5, 26, 8.5, 9.5, sc); p.ell(19.5, 28, 5.2, 7.5, belly);
    for (var y = 21; y < 35; y += 3) p.line(15.5, y, 23.5, y, '#d6c28c');                                                        // scaglie del ventre
    p.ell2(9, 34, 3, 3.2, dk); p.rect2(8, 34, 5, 4, '#e8d9a0');                                                                  // zampe e artigli
    p.tube([[27, 32, 2.5], [32, 33, 2], [35, 29, 1.4], [33, 25, 1]], dk);                                                        // coda
    p.ell(19.5, 9, 6, 5, sc);                                                                                                    // testa
    p.rect(16, 11, 8, 5, sc); p.rect(17, 14, 6, 2, dk);                                                                          // muso
    p.poly([[14, 6], [10, 0], [16, 4]], '#f2e3b3', { flat: true }); p.poly([[25, 6], [29, 0], [23, 4]], '#f2e3b3', { flat: true });  // corna
    p.eye2(3.5, 7, '#ffd23f'); p.px2(1.5, 13, '#14343d'); p.px2(2.5, 14, '#fff');
    p.line(19, 3, 19, 6, '#f2e3b3');
    return p.outline(OUT);
  };

  ART.strega = function () {
    var p = new Px(BOSSPX, BOSSPX);
    p.poly([[19.5, 17], [31, 38], [8, 38]], '#5a2d91'); p.poly([[19.5, 22], [27, 38], [12, 38]], '#7a43bd');                      // mantello
    p.line(14, 38, 19, 26, '#3c1a68'); p.line(25, 38, 20, 26, '#3c1a68');
    p.ell(19.5, 17, 5, 5.5, '#f1c9a1'); p.rect(15, 12, 10, 3, '#3a2a55', { flat: true });                                         // volto
    p.eye2(2, 16, '#8bffb4');
    p.rect(18, 19, 3, 1, '#a24b5a', { flat: true });
    p.ell(19.5, 12, 11, 2.4, '#3b1d68'); p.poly([[19.5, -1], [26, 12], [13, 12]], '#4a2380'); p.rect(14, 10, 12, 2, '#e8b84a', { flat: true }); // cappello
    p.poly([[19.5, 0], [21, 4], [18, 4]], '#6d3bb0', { flat: true });
    p.px(23, 8, '#ffd86b'); p.px(24, 7, '#ffd86b'); p.px(22, 7, '#ffd86b');
    p.line(7, 16, 12, 24, '#3c1a68', 2); p.line(32, 16, 27, 24, '#3c1a68', 2);                                                    // braccia
    p.line(7, 12, 7, 16, '#c9a45a'); p.line(32, 12, 32, 16, '#c9a45a');                                                           // catenelle
    p.ell2(12.5, 21, 4, 4.5, '#ff9f43'); p.ell2(12.5, 21, 2.2, 2.6, '#ffe29a', { flat: true }); p.rect2(12, 16, 3, 2, '#5a4a3a');   // lanterne
    p.px2(6, 21, '#fff7d0');
    p.px(10, 34, '#ffd86b'); p.px(29, 30, '#ffd86b'); p.px(17, 36, '#ffd86b');
    return p.outline(OUT);
  };

  ART.cavaliere = function () {
    var p = new Px(BOSSPX, BOSSPX), st = '#59607a', dk = '#2f3347';
    p.ell(19.5, 13, 13.5, 13.5, '#ffb347', { flat: true }); p.ell(19.5, 13, 11.2, 11.2, '#0e0820', { flat: true }); p.ell(19.5, 13, 12.6, 12.6, '#ffe29a', { flat: true }); p.ell(19.5, 13, 11, 11, '#0e0820', { flat: true }); // eclissi
    p.rect(12, 30, 6, 8, st); p.rect(22, 30, 6, 8, st); p.rect(11, 36, 8, 2, dk); p.rect(21, 36, 8, 2, dk);                       // gambe
    p.rect(11, 15, 18, 16, st); p.rect(13, 17, 14, 10, '#6c7494'); p.rect(11, 27, 18, 3, '#8b6d2c');                              // corazza
    p.line(19, 17, 19, 27, dk); p.px2(3, 20, '#9a7ad6'); p.px2(3, 23, '#9a7ad6');
    p.ell2(11, 16, 5, 4, '#6c7494'); p.rect2(14, 18, 5, 12, st);                                                                   // spalline e braccia
    p.rect(13, 3, 14, 13, st); p.rect(14, 3, 12, 3, '#6c7494'); p.rect(15, 8, 10, 3, '#12091f', { flat: true }); p.eye2(2.7, 8, '#b66dff');   // elmo e visiera
    p.poly([[19.5, -1], [22, 3], [17, 3]], '#c0392b', { flat: true }); p.rect(19, 2, 2, 5, '#c0392b', { flat: true });              // cresta
    p.ell(8, 27, 5, 7, '#40475f'); p.ell(8, 27, 2.6, 4.2, '#8b6d2c', { flat: true });                                              // scudo
    p.rect(29, 6, 3, 27, '#cfd5e6'); p.rect(30, 6, 1, 27, '#ffffff', { flat: true }); p.poly([[29, 6], [30.5, 1], [32, 6]], '#ffffff'); p.rect(26, 31, 9, 2, '#8b6d2c'); p.rect(29, 33, 3, 5, '#5b3d1f'); // spada
    return p.outline(OUT);
  };

  ART.idra = function () {
    var p = new Px(BOSSPX, BOSSPX), g = '#4aa86b', dk = '#2c6d47';
    p.tube([[12, 31, 3.8], [6, 27, 3.2], [4.5, 21, 2.8]], g); p.tube([[27, 31, 3.8], [33, 27, 3.2], [34.5, 21, 2.8]], g);        // colli laterali
    p.tube([[19.5, 32, 5], [19.5, 22, 4.2], [19.5, 14, 3.6]], g);                                                                  // collo centrale
    p.ell(19.5, 33, 13, 6, dk); p.ell(19.5, 33, 9.5, 4, '#e8d9a0');                                                                // corpo e ventre
    p.rect2(11, 36, 5, 2, '#d9c592');
    p.ell(19.5, 8, 6.6, 5.6, g); p.rect(16, 10, 8, 5, g); p.eye2(3.6, 6, '#ff5252'); p.px2(1.4, 12, '#10261a'); p.px2(2.6, 13, '#fff');   // testa centrale
    p.poly([[14, 4], [12, -1], [17, 3]], '#e8d9a0', { flat: true }); p.poly([[25, 4], [27, -1], [22, 3]], '#e8d9a0', { flat: true });
    [[5, 17], [34, 17]].forEach(function (h, i) { var hx = h[0], hy = h[1]; p.ell(hx, hy, 4.8, 4.2, g); p.rect(hx - 2.5, hy + 2, 5, 3, g); p.eye(hx - 1 + (i ? 1 : 0), hy - 2, '#ffd23f'); p.px(hx - 1, hy + 4, '#fff'); p.px(hx + 1, hy + 4, '#fff'); });
    p.line(19, 20, 19, 27, '#7ac596'); p.line(7, 27, 8, 31, '#7ac596'); p.line(32, 27, 31, 31, '#7ac596');
    return p.outline(OUT);
  };

  ART.fenice = function () {
    var p = new Px(BOSSPX, BOSSPX);
    p.poly([[16, 18], [1, 6], [4, 14], [0, 18], [5, 22], [3, 28], [10, 27], [15, 26]], '#e8541c'); p.poly([[14, 20], [4, 12], [7, 20], [5, 25], [12, 24]], '#ff9f2e', { flat: true });                      // ala sinistra
    p.poly([[23, 18], [38, 6], [35, 14], [39, 18], [34, 22], [36, 28], [29, 27], [24, 26]], '#e8541c'); p.poly([[25, 20], [35, 12], [32, 20], [34, 25], [27, 24]], '#ff9f2e', { flat: true });  // ala destra
    p.line(15, 20, 3, 8, '#ffd86b'); p.line(24, 20, 36, 8, '#ffd86b');
    p.poly([[19.5, 26], [14, 38], [17, 33], [19.5, 39], [22, 33], [25, 38]], '#c93a14');                                           // coda
    p.line(16, 33, 14, 38, '#ff9f2e'); p.line(23, 33, 25, 38, '#ff9f2e');
    p.ell(19.5, 21, 6, 9, '#f0701f'); p.ell(19.5, 24, 3.8, 5.6, '#ffd86b');                                                         // corpo
    p.ell(19.5, 11, 4.6, 4.4, '#f0701f'); p.poly([[19.5, 14], [22, 17], [17, 17]], '#ffb703', { flat: true });                      // testa e becco
    p.poly([[19.5, 1], [22, 6], [17, 6]], '#ffd86b', { flat: true }); p.poly([[24, 3], [24, 8], [21, 6]], '#ff9f2e', { flat: true }); p.poly([[15, 3], [15, 8], [18, 6]], '#ff9f2e', { flat: true });  // cresta di fiamme
    p.eye2(2.2, 10, '#fff7a0');
    p.px(10, 31, '#ffd86b'); p.px(30, 30, '#ffd86b'); p.px(6, 33, '#ff9f2e'); p.px(33, 34, '#ff9f2e'); p.px(26, 37, '#ffd86b');   // braci
    return p.outline(OUT);
  };

  ART.sovrano = function () {
    var p = new Px(BOSSPX, BOSSPX), bone = '#e9e4d3';
    p.poly([[11, 14], [3, 38], [36, 38], [28, 14]], '#7a1d3a'); p.poly([[14, 16], [9, 38], [30, 38], [25, 16]], '#a02c52');     // mantello
    p.ell2(9, 16, 5, 3.6, '#f3efe0'); p.line(19.5 - 8, 18, 19.5 - 6, 24, bone); p.line(19.5 + 8, 18, 19.5 + 6, 24, bone);
    p.rect(18, 17, 3, 18, bone);                                                                                                  // colonna
    for (var y = 19; y < 32; y += 3) { p.rect(12, y, 15, 2, bone); }                                                              // costole
    p.rect2(12, 17, 3, 15, '#d8d2bd'); p.ell2(12, 33, 2.4, 2.4, bone);                                                           // braccia
    p.ell(19.5, 10, 8, 7.4, bone); p.rect(14, 14, 12, 4, '#d8d2bd');                                                              // cranio e mascella
    p.rect(15, 16, 10, 2, '#12091f', { flat: true }); for (var x = 15; x < 25; x += 2) p.px(x, 16, bone);                         // denti
    p.ell2(3.4, 9, 2.8, 3.2, '#12091f', { flat: true }); p.eye2(3.4, 9, '#5ef0ff'); p.px(19, 12, '#12091f'); p.px(20, 12, '#12091f');
    p.poly([[12, 5], [13, -1], [16, 3], [19.5, -3], [23, 3], [26, -1], [27, 5]], '#e8b84a'); p.rect(12, 4, 16, 2, '#c99a2e', { flat: true });   // corona
    p.px(16, 3, '#ff4d6d'); p.px(23, 3, '#4dd0ff'); p.px(19, 1, '#7dffb0');
    p.line(33, 34, 33, 8, '#8b6d2c', 2); p.ell(33, 7, 2.6, 2.6, '#5ef0ff');                                                      // scettro
    return p.outline(OUT);
  };

  ART.occhio = function () {
    var p = new Px(BOSSPX, BOSSPX);
    p.tube([[9, 28, 1.8], [5, 33, 1.6], [7, 37, 1]], '#6b3a8c'); p.tube([[30, 28, 1.8], [34, 33, 1.6], [32, 37, 1]], '#6b3a8c');
    p.tube([[14, 31, 2], [12, 36, 1.5], [15, 39, 1]], '#6b3a8c'); p.tube([[25, 31, 2], [27, 36, 1.5], [24, 39, 1]], '#6b3a8c'); p.tube([[19.5, 32, 2], [19.5, 37, 1.4]], '#6b3a8c');
    p.ell(19.5, 19, 14, 13, '#6b3a8c');                                                                                           // involucro
    p.ell(19.5, 19, 12, 11, '#f4efe6');                                                                                           // bulbo
    p.line(10, 12, 15, 15, '#e07a8a'); p.line(29, 12, 24, 15, '#e07a8a'); p.line(9, 22, 14, 21, '#e07a8a'); p.line(30, 22, 25, 21, '#e07a8a'); p.line(12, 28, 16, 25, '#e07a8a'); p.line(27, 28, 23, 25, '#e07a8a');
    p.ell(19.5, 19, 7, 7, '#7b5cff'); p.ell(19.5, 19, 4.6, 4.6, '#2a1560', { flat: true }); p.ell(19.5, 19, 2.6, 2.6, '#0a0518', { flat: true });
    p.px(16, 15, '#ffffff'); p.px(17, 15, '#ffffff'); p.px(16, 16, '#ffffff'); p.px(23, 23, '#b9a8ff');
    p.poly([[8, 17], [19.5, 3], [31, 17], [26, 14], [19.5, 8], [13, 14]], '#4b2468');                                              // palpebra superiore
    p.px(19, 1, '#b9a8ff'); p.px(8, 5, '#b9a8ff'); p.px(31, 5, '#b9a8ff'); p.px(4, 24, '#b9a8ff'); p.px(35, 24, '#b9a8ff');        // scintille
    return p.outline(OUT);
  };

  ART.titano = function () {
    var p = new Px(BOSSPX, BOSSPX), c1 = '#58c8e8', c2 = '#3a8fd6', c3 = '#2a5fb0';
    p.poly([[12, 38], [13, 28], [18, 28], [19, 38]], c3); p.poly([[21, 38], [22, 28], [27, 28], [28, 38]], c3);                 // gambe
    p.poly([[9, 14], [30, 14], [27, 30], [12, 30]], c2);                                                                          // torso
    p.poly([[9, 14], [19.5, 14], [19.5, 30], [12, 30]], c1); p.poly([[19.5, 14], [30, 14], [27, 30], [19.5, 30]], c3);
    p.poly([[2, 10], [9, 9], [11, 20], [5, 24]], c1); p.poly([[37, 10], [30, 9], [28, 20], [34, 24]], c3);                         // spalle
    p.poly([[2, 22], [6, 21], [6, 33], [1, 36]], c2); p.poly([[37, 22], [33, 21], [33, 33], [38, 36]], c3);                       // avambracci
    p.poly([[0, 34], [6, 33], [7, 39], [0, 38]], c1, { flat: true }); p.poly([[39, 34], [33, 33], [32, 39], [39, 38]], c3, { flat: true });
    p.poly([[19.5, 0], [26, 5], [24, 14], [15, 14], [13, 5]], c1); p.poly([[19.5, 0], [26, 5], [24, 14], [19.5, 14]], c3);         // testa
    p.poly([[19.5, 16], [24, 22], [19.5, 28], [15, 22]], '#fff1a8', { flat: true }); p.poly([[19.5, 18], [22, 22], [19.5, 26], [17, 22]], '#ffffff', { flat: true });     // nucleo
    p.eye2(3, 7, '#fff1a8');
    p.poly([[10, 4], [7, -1], [13, 3]], c1, { flat: true }); p.poly([[29, 4], [32, -1], [26, 3]], c3, { flat: true });             // schegge sul capo
    p.line(12, 15, 16, 28, '#dff6ff'); p.line(26, 16, 24, 28, '#1f3f8a');
    return p.outline(OUT);
  };

  ART.kraken = function () {
    var p = new Px(BOSSPX, BOSSPX), b = '#2c7f8f';
    p.tube([[10, 21, 3.2], [5, 27, 2.8], [8, 33, 2.4], [4, 37, 1.6]], b); p.tube([[29, 21, 3.2], [34, 27, 2.8], [31, 33, 2.4], [35, 37, 1.6]], b);
    p.tube([[13, 23, 3], [12, 31, 2.6], [17, 36, 2], [14, 39, 1.2]], b); p.tube([[26, 23, 3], [27, 31, 2.6], [22, 36, 2], [25, 39, 1.2]], b); p.tube([[19.5, 25, 3], [19.5, 33, 2.4], [19.5, 38, 1.4]], b);
    var suck = [[6, 28], [8, 33], [5, 36], [33, 28], [31, 33], [34, 36], [13, 32], [26, 32], [19, 34], [20, 34]];
    suck.forEach(function (s) { p.px(s[0], s[1], '#d7f2e8'); });
    p.ell(19.5, 13, 12, 12, b); p.ell(19.5, 20, 10, 6, b);                                                                         // testa a cupola
    p.ell(19.5, 9, 7, 5, '#3b9aa8', { flat: true }); p.poly([[9, 12], [12, 4], [14, 12]], '#3b9aa8', { flat: true });
    p.ell2(5.2, 15, 3, 3.2, '#fff6b0', { flat: true }); p.ell2(5.2, 15.4, 1.5, 2, '#1a1030', { flat: true }); p.px2(5.8, 14, '#ffffff'); p.rect(17, 21, 5, 1, '#10303a', { flat: true });
    p.px(8, 7, '#a8e6ec'); p.px(10, 5, '#a8e6ec'); p.px(30, 8, '#a8e6ec'); p.px(13, 9, '#a8e6ec');
    return p.outline(OUT);
  };

  ART.demone = function () {
    var p = new Px(BOSSPX, BOSSPX), r = '#d63a2b', dk = '#8f1d1d';
    p.poly2([[15, 18], [1, 2], [8, 14], [2, 22], [10, 22], [12, 29]], '#7a1a3a'); p.line(14, 19, 3, 5, '#d63a6b'); p.line(25, 19, 36, 5, '#d63a6b'); p.line(12, 22, 6, 20, '#d63a6b'); p.line(27, 22, 33, 20, '#d63a6b');   // ali
    p.rect(13, 29, 6, 8, dk); p.rect(21, 29, 6, 8, dk); p.rect(12, 36, 8, 2, '#2b1010'); p.rect(20, 36, 8, 2, '#2b1010');      // gambe
    p.ell(19.5, 22, 9.5, 9, r); p.ell(19.5, 24, 5.6, 6, '#f08a5d');                                                               // busto
    p.ell2(11.5, 16, 4.4, 4.4, r); p.rect2(14, 17, 4, 11, r); p.ell2(14.5, 29, 3.4, 3.4, dk); p.ell2(14.5, 31.5, 2, 2.6, '#ffb703', { flat: true }); // braccia e pugni
    p.ell(19.5, 10, 6.6, 6, r); p.rect(15, 13, 10, 4, dk);
    p.poly([[13, 6], [8, -1], [16, 4]], '#f3e7c4'); p.poly([[26, 6], [31, -1], [23, 4]], '#f3e7c4');                              // corna
    p.eye2(3.4, 8, '#ffe66b'); p.rect(15, 13, 10, 2, '#2b0d0d', { flat: true }); for (var x = 15; x < 25; x += 2) p.px(x, 13, '#fff');   // bocca e denti
    p.line(30, 33, 36, 30, dk, 2); p.poly([[35, 28], [39, 31], [35, 33]], dk, { flat: true });                                   // coda
    return p.outline(OUT);
  };

  ART.arconte = function () {
    var p = new Px(BOSSPX, BOSSPX), gold = '#e8b84a';
    p.poly2([[16, 16], [1, 4], [4, 14], [0, 20], [6, 22], [4, 30], [12, 28], [15, 30]], '#f4f1ff'); p.poly2([[16, 20], [5, 12], [7, 20], [6, 26], [13, 26]], '#c9d3ff');   // ali
    p.line(15, 18, 3, 6, gold); p.line(24, 18, 36, 6, gold);
    p.poly([[13, 30], [26, 30], [28, 39], [11, 39]], '#eef0ff');                                                                  // veste
    p.rect(13, 16, 13, 15, '#f4f1ff'); p.rect(13, 16, 13, 2, gold); p.rect(13, 28, 13, 2, gold); p.poly([[19.5, 19], [22, 22], [19.5, 26], [17, 22]], '#6ec3ff', { flat: true });
    p.ell2(9.5, 18, 3.6, 3.6, gold); p.rect2(12, 19, 3, 9, '#f4f1ff'); p.ell2(12, 29, 2.4, 2.4, '#ffe29a');
    p.ell(19.5, 10, 5.6, 6, '#f1d8b0'); p.rect(14, 5, 12, 6, '#eef0ff'); p.rect(14, 5, 12, 1, gold, { flat: true }); p.eye2(2.2, 9, '#6ec3ff'); p.rect(17, 12, 5, 1, '#c98d62', { flat: true });  // volto con elmo
    p.poly([[13, 6], [11, 1], [16, 4]], '#ffffff', { flat: true }); p.poly([[26, 6], [28, 1], [23, 4]], '#ffffff', { flat: true });
    p.ell(19.5, 1.6, 8, 1.8, '#ffe29a', { flat: true }); p.ell(19.5, 1.6, 6, 0.9, '#fff9d0', { flat: true });                      // aureola
    p.line(34, 34, 34, 12, '#cfe6ff', 2); p.rect(31, 28, 7, 2, gold); p.poly([[33, 12], [34, 7], [35, 12]], '#ffffff', { flat: true });  // lama di luce
    return p.outline('#2a2250');
  };

  /* ---------- nemici comuni (24×24) ---------- */
  var MIN = 24;
  ART.melma = function () {
    var p = new Px(MIN, MIN), c = '#63d36a';
    p.ell(11.5, 16, 10, 6.5, c); p.ell(11.5, 11, 7, 6, c);
    p.ell(8, 8, 2, 1.4, '#d9ffd4', { flat: true });
    p.rect(8, 12, 3, 3, '#0e2a14', { flat: true }); p.rect(14, 12, 3, 3, '#0e2a14', { flat: true }); p.px(8, 12, '#fff'); p.px(14, 12, '#fff');
    p.rect(10, 17, 5, 1, '#0e2a14', { flat: true });
    p.px(19, 5, '#b9f5b9'); p.px(20, 7, '#b9f5b9'); p.px(3, 6, '#b9f5b9');
    return p.outline(OUT);
  };
  ART.pipistrello = function () {
    var p = new Px(MIN, MIN), c = '#6b4aa0';
    p.poly2([[10, 9], [0, 4], [3, 10], [1, 15], [6, 13], [9, 17]], '#4a3278'); p.line2(9, 10, 2, 6, '#8e6bc8'); p.line2(9, 12, 3, 13, '#8e6bc8');
    p.ell(11.5, 12, 4.2, 5.6, c); p.ell(11.5, 7, 3.6, 3.4, c);
    p.poly([[8, 5], [7, 0], [10, 4]], c, { flat: true }); p.poly([[15, 5], [16, 0], [13, 4]], c, { flat: true });
    p.eye2(1.6, 7, '#ff5a5a'); p.px(10, 10, '#fff'); p.px(13, 10, '#fff');
    return p.outline(OUT);
  };
  ART.scheletro = function () {
    var p = new Px(MIN, MIN), b = '#ece7d6';
    p.rect2(2, 17, 2, 6, b); p.rect(9, 16, 6, 1, b);
    p.rect(11, 9, 2, 8, b); for (var y = 10; y < 15; y += 2) p.rect(8, y, 8, 1, '#d8d2bd');
    p.rect2(5, 9, 2, 7, '#d8d2bd'); p.ell(11.5, 5, 4.4, 4.2, b); p.rect(9, 8, 5, 2, '#d8d2bd'); p.rect(9, 9, 5, 1, '#12091f', { flat: true });
    p.eye2(1.6, 4, '#ff6a3d'); p.px(11, 7, '#12091f'); p.px(12, 7, '#12091f');
    p.line(20, 20, 20, 7, '#9aa3b5', 2); p.rect(18, 14, 5, 1, '#8b6d2c', { flat: true });
    return p.outline(OUT);
  };
  ART.goblin = function () {
    var p = new Px(MIN, MIN), c = '#7fb83a';
    p.poly2([[8, 6], [0, 3], [5, 9]], c, { flat: true });
    p.rect2(3, 16, 3, 6, '#5d8a2b'); p.ell(11.5, 13, 5.5, 5.4, '#8a5a2b'); p.rect2(6, 12, 2, 5, c);
    p.ell(11.5, 7, 5, 4.6, c); p.eye2(2.4, 6, '#ffe14d'); p.px(11, 8, '#3b5a1a'); p.rect(9, 10, 6, 1, '#2a3a12', { flat: true }); p.px(10, 10, '#fff'); p.px(13, 10, '#fff');
    p.line(21, 21, 21, 6, '#b8a07a', 2); p.poly([[19, 7], [21, 2], [23, 7]], '#dfe3ee', { flat: true });
    return p.outline(OUT);
  };
  ART.lupo = function () {
    var p = new Px(MIN, MIN), c = '#8a8fa3';
    p.poly([[5, 11], [3, 1], [9, 6]], c); p.poly([[18, 11], [20, 1], [14, 6]], c); p.poly([[5, 9], [4, 3], [8, 6]], '#e8a3b0', { flat: true }); p.poly([[18, 9], [19, 3], [15, 6]], '#e8a3b0', { flat: true });
    p.ell(11.5, 12, 8, 7.4, c); p.ell(11.5, 17, 4.4, 4.2, '#c3c8d8'); p.px(11, 15, '#12091f'); p.px(12, 15, '#12091f'); p.rect(11, 16, 2, 2, '#12091f', { flat: true });
    p.eye2(3.8, 9, '#ffd23f'); p.px(9, 20, '#fff'); p.px(14, 20, '#fff');
    p.rect(2, 16, 4, 6, c); p.rect(18, 16, 4, 6, c);
    return p.outline(OUT);
  };
  ART.spettro = function () {
    var p = new Px(MIN, MIN), c = '#cfd8ff';
    p.ell(11.5, 10, 8, 8, c); p.rect(3, 10, 17, 10, c);
    p.poly([[3, 20], [5, 23], [7, 20], [9, 23], [11, 20], [13, 23], [15, 20], [17, 23], [19, 20], [20, 22]], c, { flat: true });
    p.ell2(3, 9, 2, 2.6, '#1a1040', { flat: true }); p.px(8, 8, '#8be9ff'); p.px(15, 8, '#8be9ff'); p.ell(11.5, 15, 2, 2.4, '#1a1040', { flat: true });
    p.line(3, 13, 0, 17, '#aab6ee', 2); p.line(20, 13, 23, 17, '#aab6ee', 2);
    return p.outline('#2a2a6a');
  };
  ART.ragno = function () {
    var p = new Px(MIN, MIN), c = '#4a3a5e';
    var L = [[7, 9, 1, 3, 2, 8], [7, 12, 0, 12, 1, 18], [8, 14, 2, 17, 3, 22]];
    for (var i = 0; i < 3; i++) { p.line2(9, 11 + i * 2, 5 - i, 7 + i * 4, '#2f2540'); p.line2(5 - i, 7 + i * 4, 1, 12 + i * 3, '#2f2540'); }
    p.line2(9, 9, 5, 4, '#2f2540'); p.line2(5, 4, 1, 8, '#2f2540');
    p.ell(11.5, 15, 5.5, 6, c); p.ell(11.5, 8, 4, 3.6, '#5d4a78'); p.eye2(1.5, 6, '#ff4d4d'); p.eye2(3.2, 8, '#ff4d4d');
    p.poly([[10, 15], [11.5, 19], [13, 15]], '#d63a2b', { flat: true });
    return p.outline(OUT);
  };
  ART.elementale = function () {
    var p = new Px(MIN, MIN), c = '#8a8578';
    p.rect2(3, 17, 5, 5, '#6d695f'); p.ell(11.5, 12, 8, 7.4, c);
    p.rect2(9, 9, 3, 9, '#79746a'); p.ell2(8.6, 9, 3, 3.2, '#9a9588');
    p.ell(11.5, 6, 4.2, 3.8, '#9a9588'); p.eye2(1.7, 5, '#ff8a2b'); p.poly([[10, 12], [11.5, 17], [13, 12]], '#ff8a2b', { flat: true }); p.poly([[10.8, 14], [11.5, 16], [12.2, 14]], '#ffe29a', { flat: true });
    p.px(6, 10, '#bdb8aa'); p.px(16, 12, '#5b574e'); p.px(8, 15, '#5b574e');
    return p.outline(OUT);
  };

  /* ---------- l'eroe (28×32) ---------- */
  ART.eroe = function () {
    var p = new Px(28, 32);
    p.poly([[6, 14], [2, 30], [11, 29], [12, 16]], '#a02c52');                                                                    // mantello
    p.rect(10, 22, 4, 8, '#3d4a6b'); p.rect(15, 22, 4, 8, '#3d4a6b'); p.rect(9, 29, 6, 2, '#5b3d1f'); p.rect(15, 29, 6, 2, '#5b3d1f');
    p.rect(9, 12, 11, 11, '#4f78c4'); p.rect(9, 20, 11, 2, '#8b6d2c'); p.rect(11, 13, 7, 3, '#7ea2e6');
    p.rect(6, 13, 3, 8, '#4f78c4'); p.rect(20, 13, 3, 8, '#4f78c4');
    p.ell(14.5, 8, 5, 5, '#f1c9a1'); p.rect(10, 3, 10, 4, '#7a4a2a'); p.rect(9, 5, 2, 5, '#7a4a2a'); p.rect(18, 5, 2, 4, '#7a4a2a');
    p.px(12, 8, '#1a1030'); p.px(17, 8, '#1a1030'); p.rect(13, 11, 3, 1, '#b5604a', { flat: true });
    p.rect(24, 4, 2, 20, '#d8deee'); p.px(25, 4, '#fff'); p.rect(22, 22, 6, 2, '#8b6d2c'); p.rect(24, 24, 2, 4, '#5b3d1f');            // spada
    p.ell(5, 19, 4, 5.5, '#c9a45a'); p.ell(5, 19, 2, 3.2, '#8b6d2c', { flat: true });                                              // scudo
    return p.outline(OUT);
  };

  /* ---------- registro, cache e rendering ---------- */
  var CACHE = {};
  function uri(key) {
    if (CACHE[key]) return CACHE[key];
    var fn = ART[key]; if (!fn) return '';
    var px = fn(), cv = px.canvas(4);
    CACHE[key] = { url: cv.toDataURL('image/png'), w: px.w, h: px.h };
    return CACHE[key];
  }
  // tinta del sprite in base al "giro" (boss) o al "livello" (nemici): rotazione dell'ombra colore
  var TINTS = [{ h: 0, s: 1, b: 1 }, { h: 38, s: 1.05, b: 1.04 }, { h: 150, s: 1.1, b: 1.02 }, { h: 255, s: 1.18, b: 1.06 }, { h: 320, s: 1.25, b: 1.08 }];
  function sprite(key, o) {
    o = o || {}; var d = uri(key); if (!d) return '';
    var t = TINTS[Math.min(TINTS.length - 1, Math.max(0, o.tier || 0))];
    var size = o.size || 160, sc = size / Math.max(d.w, d.h);
    var st = 'width:' + Math.round(d.w * sc) + 'px;height:' + Math.round(d.h * sc) + 'px;image-rendering:pixelated;' + (t.h ? 'filter:hue-rotate(' + t.h + 'deg) saturate(' + t.s + ') brightness(' + t.b + ');' : '');
    return '<img class="tw-sprite ' + (o.cls || '') + '" alt="' + (o.alt || '') + '" draggable="false" style="' + st + '" src="' + d.url + '">';
  }

  /* ---------- zone della Torre ---------- */
  var ZONES = [
    { from: 1, name: 'Le Cantine', sky: ['#1a1030', '#2d1b4e', '#4a2a6e'], glow: '#9d6bff', stone: '#3a2a55', star: 0 },
    { from: 50, name: 'La Sala dei Mazzi', sky: ['#14213d', '#27406e', '#3b5f9a'], glow: '#6ec3ff', stone: '#2f4568', star: 1 },
    { from: 100, name: 'Il Giardino di Cenere', sky: ['#2a1210', '#5a2a1c', '#8c4a26'], glow: '#ff9f43', stone: '#5a3322', star: 1 },
    { from: 150, name: 'La Galleria degli Specchi', sky: ['#10262a', '#1d4b52', '#2f7c86'], glow: '#7cf0e0', stone: '#285a62', star: 2 },
    { from: 200, name: 'Il Cielo di Tempesta', sky: ['#0b1020', '#1b2a52', '#3a4a8a'], glow: '#ffe66b', stone: '#2b3a66', star: 3 },
    { from: 300, name: 'La Sfera di Cristallo', sky: ['#1a0f36', '#3a1d6e', '#6a3bb0'], glow: '#ff7ad9', stone: '#4a2a80', star: 3 },
    { from: 450, name: 'Il Vuoto Stellato', sky: ['#04040e', '#0a0a24', '#16164a'], glow: '#ffffff', stone: '#1c1c40', star: 4 },
    { from: 700, name: 'Oltre il Tempo', sky: ['#0a0210', '#2a0a3a', '#5a1a5a'], glow: '#ffb86b', stone: '#3a1a4a', star: 4 }
  ];
  function zone(floor) { var z = ZONES[0]; for (var i = 0; i < ZONES.length; i++) if (floor >= ZONES[i].from) z = ZONES[i]; return z; }
  var RANKS = [[1, 'Novizio della Torre'], [10, 'Scalatore'], [30, 'Esploratore'], [60, 'Veterano della Torre'], [100, 'Cavaliere della Torre'], [150, 'Campione'], [250, 'Maestro della Torre'], [400, 'Leggenda'], [600, 'Mito'], [900, 'Semidio'], [1300, 'Eterno']];
  function rank(best) { var r = 'Ai piedi della Torre'; for (var i = 0; i < RANKS.length; i++) if (best >= RANKS[i][0]) r = RANKS[i][1]; return r; }


  /* ---------- stile della scheda Torre e dell'arena dei combattimenti ---------- */
  var CSS = [
  '.tw-top{display:flex;align-items:flex-end;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-bottom:10px}',
  '.tw-top h2{font-size:1.35rem}.tw-top small{display:block;color:var(--mu)}',
  '.tw-best{text-align:right}.tw-best b{display:block;font:700 1.9rem/1 var(--disp);color:var(--gold);font-variant-numeric:tabular-nums}.tw-best span{font-size:.8rem;color:var(--mu)}',
  '.tw-stage{position:relative;border:1px solid var(--line);border-radius:16px;overflow:hidden;background:linear-gradient(180deg,var(--z1),var(--z2) 55%,var(--z3));isolation:isolate;--z1:#1a1030;--z2:#2d1b4e;--z3:#4a2a6e;--zg:#9d6bff;--zs:#3a2a55;--zst:.4}',
  '.tw-stage::before{content:"";position:absolute;inset:0;z-index:-1;opacity:var(--zst);animation:twTw 5s ease-in-out infinite alternate;',
  ' background-image:radial-gradient(1.6px 1.6px at 12% 14%,#fff,transparent),radial-gradient(1.2px 1.2px at 28% 32%,#cfe3ff,transparent),radial-gradient(1.8px 1.8px at 47% 9%,#fff,transparent),radial-gradient(1.2px 1.2px at 63% 26%,#ffe9b0,transparent),radial-gradient(1.6px 1.6px at 81% 12%,#fff,transparent),radial-gradient(1.2px 1.2px at 92% 34%,#cfe3ff,transparent),radial-gradient(1.4px 1.4px at 70% 46%,#fff,transparent),radial-gradient(1.2px 1.2px at 38% 52%,#fff,transparent),radial-gradient(1.4px 1.4px at 8% 60%,#ffe9b0,transparent),radial-gradient(1.2px 1.2px at 55% 70%,#cfe3ff,transparent)}',
  '.tw-stage::after{content:"";position:absolute;left:0;right:0;bottom:0;height:42%;z-index:-1;background:linear-gradient(0deg,rgba(0,0,0,.45),transparent);pointer-events:none}',
  '.tw-zn{display:flex;justify-content:space-between;gap:8px;align-items:center;padding:10px 12px 0;font-size:.8rem;color:rgba(255,255,255,.82);text-shadow:0 1px 3px #000;flex-wrap:wrap}.tw-zn b{font-family:var(--disp);letter-spacing:.02em}',
  '.tw-grid{display:grid;grid-template-columns:104px minmax(0,1fr);gap:8px;padding:12px 12px 14px;align-items:stretch}',
  /* la torre a righe */
  '.tw-lad{display:flex;flex-direction:column;justify-content:flex-end;gap:3px;min-width:0}',
  '.tw-roof{height:30px;margin:0 14px;background:linear-gradient(180deg,#5b3a9a,#3a2470);clip-path:polygon(50% 0,100% 100%,0 100%);position:relative}',
  '.tw-flag{position:relative;height:16px;margin:0 0 -4px 52px;width:3px;background:#c9a45a}.tw-flag::after{content:"";position:absolute;left:3px;top:0;width:14px;height:9px;background:var(--bad);clip-path:polygon(0 0,100% 50%,0 100%);animation:twWave 1.4s ease-in-out infinite alternate}',
  '.tw-fl{display:flex;align-items:center;justify-content:space-between;gap:4px;height:36px;margin:0 8px;padding:0 8px;border:1px solid rgba(0,0,0,.5);border-radius:3px;position:relative;font:700 .78rem var(--disp);color:#efeaff;',
  ' background:repeating-linear-gradient(90deg,transparent 0 22px,rgba(0,0,0,.18) 22px 23px),linear-gradient(180deg,rgba(255,255,255,.16),rgba(0,0,0,.2)),var(--zs);text-shadow:0 1px 2px #000;overflow:hidden}',
  '.tw-fl i{font-style:normal;font-size:.95rem}',
  '.tw-fl.done{opacity:.62}.tw-fl.done i{color:var(--good)}',
  '.tw-fl.cur{border-color:var(--zg);box-shadow:0 0 0 1px var(--zg),0 0 16px var(--zg);animation:twGlow 1.8s ease-in-out infinite alternate;opacity:1;color:#fff}',
  '.tw-fl.boss{border-color:#b4233a;background:repeating-linear-gradient(90deg,transparent 0 22px,rgba(0,0,0,.2) 22px 23px),linear-gradient(180deg,rgba(255,120,120,.22),rgba(60,0,10,.35)),#4a1a2a;height:42px}',
  '.tw-fl.boss.cur{border-color:#ff6b7a;box-shadow:0 0 0 1px #ff6b7a,0 0 18px #ff3b52}',
  '.tw-fl.gap{height:14px;background:none;border:0;box-shadow:none;justify-content:center;opacity:.7;font-size:.9rem}',
  '.tw-base{height:22px;margin:0 2px;border-radius:4px 4px 0 0;background:linear-gradient(180deg,#2b2142,#161028);position:relative}.tw-base::after{content:"";position:absolute;left:50%;bottom:0;width:20px;height:16px;margin-left:-10px;border-radius:10px 10px 0 0;background:#07050f;box-shadow:inset 0 0 0 2px #5b3d1f}',
  /* il nemico */
  '.tw-foe{display:grid;align-content:end;justify-items:center;text-align:center;min-width:0}',
  '.tw-pl{position:relative;display:grid;place-items:end center;min-height:190px;width:100%}',
  '.tw-pl .tw-sh{position:absolute;bottom:2px;left:50%;width:62%;height:16px;margin-left:-31%;border-radius:50%;background:radial-gradient(ellipse,rgba(0,0,0,.6),transparent 70%)}',
  '.tw-pl .tw-sprite{position:relative;animation:twFloat 3.4s ease-in-out infinite;filter:drop-shadow(0 6px 10px rgba(0,0,0,.55))}',
  '.tw-pl .tw-aura{position:absolute;left:50%;top:48%;width:190px;height:190px;margin:-95px 0 0 -95px;border-radius:50%;background:radial-gradient(circle,var(--zg),transparent 62%);opacity:.32;animation:twPulse 3.4s ease-in-out infinite}',
  '.tw-pl.boss .tw-aura{background:radial-gradient(circle,#ff3b52,transparent 62%);opacity:.4}',
  '.tw-fn{font:700 1.15rem/1.15 var(--disp);color:#fff;text-shadow:0 2px 6px #000;margin-top:6px;overflow-wrap:anywhere}',
  '.tw-tags{display:flex;flex-wrap:wrap;gap:5px;justify-content:center;margin-top:6px}',
  '.tw-tag{font:700 .7rem var(--ui);padding:2px 9px;border-radius:99px;border:1px solid rgba(255,255,255,.28);background:rgba(0,0,0,.4);color:#fff;text-shadow:none;letter-spacing:.03em}',
  '.tw-tag.b{background:#b4233a;border-color:#ff6b7a}.tw-tag.a{border-color:var(--warn);color:var(--warn)}',
  '.tw-lore{margin:6px 0 0;font-size:.82rem;color:rgba(255,255,255,.78);font-style:italic}',
  /* stima di vittoria e premi */
  '.tw-info{margin-top:12px;padding:12px;border:1px solid var(--line);border-radius:14px;background:var(--surf)}',
  '.tw-chrow{display:flex;justify-content:space-between;align-items:baseline;gap:10px;flex-wrap:wrap}.tw-chrow b{font:700 1.1rem var(--disp)}',
  '.tw-ch{height:12px;border-radius:99px;background:var(--inp);border:1px solid var(--line);overflow:hidden;margin-top:6px}.tw-ch i{display:block;height:100%;border-radius:99px;transition:width .5s}',
  '.tw-rw{display:flex;flex-wrap:wrap;gap:6px;margin-top:10px}.tw-rw span{font:700 .82rem var(--ui);padding:3px 10px;border-radius:99px;border:1px solid var(--line);background:rgba(var(--ac-rgb),.08);color:var(--ac2)}.tw-rw span.g{color:var(--gold);border-color:rgba(232,184,74,.45);background:rgba(232,184,74,.08)}',
  '.tw-go{width:100%;min-height:56px;margin-top:12px;font-size:1.1rem}',
  '.tw-go small{font-weight:600;opacity:.85;margin-left:4px}',
  '.tw-st{display:flex;flex-wrap:wrap;gap:6px;justify-content:center;margin-top:8px}.tw-st span{font:600 .72rem var(--ui);padding:1px 8px;border-radius:8px;background:rgba(0,0,0,.45);color:#e9e4ff}.tw-st b{color:#fff}',
  /* anteprima dei prossimi piani */
  '.tw-up{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;margin-top:10px}',
  '.tw-uc{padding:8px 4px 6px;border:1px solid var(--line);border-radius:12px;background:var(--surf);text-align:center;min-width:0}.tw-uc small{display:block;color:var(--mu);font-size:.7rem;line-height:1.2;overflow-wrap:anywhere}.tw-uc b{display:block;font:700 .78rem var(--disp);color:var(--ac2)}',
  '.tw-uc .tw-sprite{display:block;margin:2px auto}.tw-uc.boss{border-color:#b4233a;background:rgba(180,35,58,.12)}',
  '.tw-boss{display:flex;gap:12px;align-items:center;margin-top:12px;padding:10px 12px;border:1px solid #b4233a;border-radius:14px;background:linear-gradient(90deg,rgba(180,35,58,.2),var(--surf))}',
  '.tw-boss .tw-sprite{flex:none;filter:brightness(0) opacity(.85)}.tw-boss.near .tw-sprite{filter:drop-shadow(0 0 6px #ff3b52)}.tw-boss b{font-family:var(--disp)}.tw-boss small{display:block;color:var(--mu)}',
  /* arena del combattimento */
  '.tw-ar{--z1:#1a1030;--z2:#2d1b4e;--z3:#4a2a6e;--zg:#9d6bff}',
  '.tw-ar h2{margin:0 0 8px;display:flex;align-items:center;gap:8px;flex-wrap:wrap}',
  '.tw-field{position:relative;border-radius:14px;overflow:hidden;background:linear-gradient(180deg,var(--z1),var(--z2) 60%,var(--z3));border:1px solid var(--line);padding:10px 8px 6px}',
  '.tw-field::after{content:"";position:absolute;left:0;right:0;bottom:0;height:34%;background:linear-gradient(0deg,#0b0716,rgba(11,7,22,.2));pointer-events:none}',
  '.tw-field.shake{animation:twShake .35s}',
  '.tw-duel{position:relative;z-index:1;display:grid;grid-template-columns:1fr 1fr;gap:6px;align-items:end;min-height:230px}',
  '.tw-side{position:relative;display:grid;align-content:end;justify-items:center;gap:3px;min-width:0}',
  '.tw-side .nm{font:700 .84rem var(--ui);color:#fff;text-shadow:0 1px 3px #000;text-align:center;overflow-wrap:anywhere;line-height:1.2}',
  '.tw-hpb{width:100%;height:12px;border-radius:99px;background:rgba(0,0,0,.55);border:1px solid rgba(255,255,255,.22);overflow:hidden;position:relative}.tw-hpb i{display:block;height:100%;background:linear-gradient(90deg,#b4233a,#ff5468);transition:width .35s}.tw-side.me .tw-hpb i{background:linear-gradient(90deg,#1f9d63,#4ade9b)}',
  '.tw-hpt{font:700 .68rem var(--ui);color:#fff;text-shadow:0 1px 2px #000;font-variant-numeric:tabular-nums}',
  '.tw-body{position:relative;display:grid;place-items:end center;min-height:150px;width:100%}.tw-body .tw-sprite{position:relative}',
  '.tw-body.me .tw-sprite{transform:scaleX(1)}',
  '.tw-av{position:absolute;top:10px;left:-2px;width:34px;height:34px;border-radius:50%;overflow:hidden;border:2px solid var(--ac);background:var(--raise);display:grid;place-items:center;font:700 .9rem var(--disp);color:var(--ac2);z-index:2}.tw-av img{width:100%;height:100%;object-fit:cover}',
  '.tw-body.atk-l{animation:twAtkL .36s ease-out}.tw-body.atk-r{animation:twAtkR .36s ease-out}',
  '.tw-body.hit .tw-sprite{animation:twHit .34s}.tw-body.dodge{animation:twDodge .38s}',
  '.tw-body.ko .tw-sprite{animation:twKo .9s forwards}',
  '.tw-num{position:absolute;left:50%;top:18%;z-index:3;font:700 1.35rem var(--disp);color:#fff;text-shadow:0 2px 0 #000,0 0 8px #000;pointer-events:none;animation:twNum .95s ease-out forwards;white-space:nowrap}',
  '.tw-num.c{color:#ffd23f;font-size:1.7rem}.tw-num.x{color:#cfe3ff;font-size:1rem}',
  '.tw-spark{position:absolute;left:50%;top:40%;width:60px;height:60px;margin:-30px 0 0 -30px;z-index:3;pointer-events:none;background:radial-gradient(circle,#fff,#ffd86b 30%,transparent 62%);animation:twSpark .3s ease-out forwards}',
  '.tw-log{position:relative;z-index:1;min-height:40px;margin-top:6px;font-size:.82rem;color:#e9e4ff;text-shadow:0 1px 2px #000;display:grid;gap:1px;align-content:end}.tw-log b{color:#fff}',
  '.tw-res{margin-top:12px;animation:twPop .45s ease-out}',
  '.tw-res h3{font:700 1.3rem var(--disp);text-align:center;margin:0 0 8px}.tw-res h3.w{color:var(--gold)}.tw-res h3.l{color:var(--bad)}',
  '.tw-first{margin:8px 0;padding:9px 12px;border-radius:12px;border:1px solid var(--gold);background:linear-gradient(90deg,rgba(232,184,74,.22),rgba(232,184,74,.06));text-align:center;font-weight:700;color:var(--gold);animation:twGlowG 1.4s ease-in-out infinite alternate}',
  '.tw-drop{margin:8px 0;padding:10px;border:1px solid var(--line);border-radius:12px;background:var(--surf);display:grid;grid-template-columns:44px 1fr;gap:10px;align-items:center;animation:twPop .5s ease-out}',
  '.tw-hist{display:flex;gap:6px;flex-wrap:wrap}.tw-hist span{font:700 .72rem var(--ui);padding:2px 8px;border-radius:99px;border:1px solid var(--line)}.tw-hist .w{color:var(--good);border-color:rgba(74,222,155,.4)}.tw-hist .l{color:var(--bad);border-color:rgba(255,84,104,.4)}',
  /* animazioni */
  '@keyframes twFloat{50%{transform:translateY(-7px)}}@keyframes twPulse{50%{transform:scale(1.12);opacity:.5}}@keyframes twTw{from{opacity:calc(var(--zst)*.6)}to{opacity:var(--zst)}}',
  '@keyframes twGlow{from{box-shadow:0 0 0 1px var(--zg),0 0 8px var(--zg)}to{box-shadow:0 0 0 1px var(--zg),0 0 20px var(--zg)}}@keyframes twGlowG{from{box-shadow:0 0 6px rgba(232,184,74,.3)}to{box-shadow:0 0 18px rgba(232,184,74,.7)}}',
  '@keyframes twWave{from{transform:skewY(-8deg)}to{transform:skewY(8deg)}}',
  '@keyframes twAtkL{40%{transform:translateX(34px) scale(1.06)}}@keyframes twAtkR{40%{transform:translateX(-34px) scale(1.06)}}',
  '@keyframes twHit{0%{filter:brightness(3) saturate(0)}30%{transform:translateX(7px)}60%{transform:translateX(-5px)}100%{filter:none}}',
  '@keyframes twDodge{35%{transform:translateX(26px) rotate(6deg);opacity:.55}}',
  '@keyframes twKo{to{transform:translateY(24px) rotate(14deg);opacity:.15;filter:grayscale(1)}}',
  '@keyframes twNum{0%{transform:translate(-50%,0) scale(.6);opacity:0}15%{transform:translate(-50%,-10px) scale(1.15);opacity:1}100%{transform:translate(-50%,-58px) scale(1);opacity:0}}',
  '@keyframes twSpark{from{transform:scale(.4);opacity:1}to{transform:scale(1.5);opacity:0}}',
  '@keyframes twShake{20%{transform:translate(-4px,2px)}40%{transform:translate(4px,-2px)}60%{transform:translate(-3px,1px)}80%{transform:translate(3px,-1px)}}',
  '@keyframes twPop{from{transform:scale(.92);opacity:0}to{transform:none;opacity:1}}',
  '@media (prefers-reduced-motion:reduce){.tw-stage *,.tw-stage::before,.tw-ar *,.tw-res,.tw-drop,.tw-first{animation:none!important}.tw-hpb i{transition:none}}',
  '@media(max-width:380px){.tw-grid{grid-template-columns:92px minmax(0,1fr)}.tw-fl{margin:0 4px;padding:0 6px}}'
  ].join('\n');
  (function () { try { var s = document.createElement('style'); s.id = 'tw-css'; s.textContent = CSS; document.head.appendChild(s); } catch (_) {} })();

  /* torre a righe: il piano da affrontare è quello acceso; sopra c'è il prossimo boss; sotto i piani già vinti */
  function ladder(best, nb, zn) {
    var cur = best + 1, rows = [], i;
    function row(f, cls, icon) { return '<div class="tw-fl ' + cls + '"><span>' + f + '</span><i aria-hidden="true">' + icon + '</i></div>'; }
    if (nb > cur + 2) { rows.push(row(nb, 'boss', '💀')); if (nb > cur + 3) rows.push('<div class="tw-fl gap" aria-hidden="true">⋮</div>'); }
    for (i = Math.max(cur + 2, 1); i >= Math.max(1, cur - 2); i--) {
      var b = i % 10 === 0, cls = (i === cur ? 'cur ' : i < cur ? 'done ' : '') + (b ? 'boss' : '');
      rows.push(row(i, cls.trim(), i === cur ? '⚔️' : i < cur ? '✓' : (b ? '💀' : '·')));
    }
    if (cur - 2 > 1) rows.push('<div class="tw-fl gap" aria-hidden="true">⋮</div>');
    return '<div class="tw-lad" aria-hidden="true"><div class="tw-flag"></div><div class="tw-roof"></div>' + rows.join('') + '<div class="tw-base"></div></div>';
  }
  function zoneVars(z) { return '--z1:' + z.sky[0] + ';--z2:' + z.sky[1] + ';--z3:' + z.sky[2] + ';--zg:' + z.glow + ';--zs:' + z.stone + ';--zst:' + [.25, .5, .65, .8, 1][z.star] + ';'; }

  g.TorreArt = { ladder: ladder, zoneVars: zoneVars,  sprite: sprite, uri: uri, zone: zone, zones: ZONES, rank: rank, keys: Object.keys(ART), Px: Px, ART: ART, h2r: h2r, mix: mix };
})(window);
