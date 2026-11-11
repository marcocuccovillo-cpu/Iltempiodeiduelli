/* La guerra degli Eroi — Lo stagno: grafica dei 45 pet companion (30 originali + 15 dei gradi 10–14).
   Tutti gli sprite sono disegnati qui dentro, in codice (pixel art originale, nessuna immagine esterna): sono creature inventate,
   ispirate ai tipi di mostro (Drago, Incantatore, Guerriero, Bestia alata, Macchina…), non personaggi esistenti.
   Uso: PetArt.sprite('gatto', {tier:1, size:96, alt:'Gatto'}) → <img> pronto (data URI, ingrandito senza sfocare). */
(function (g) {
  'use strict';
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
  /* ---------- pet (32×32): creature originali, nessun personaggio esistente ---------- */
  var ART = {}, N = 32, CX = 15.5, K = '#1a1030', W = '#ffffff';
  function eyes(p, y, dx, c, tall) { var l = Math.round(CX - dx - .5), r = Math.round(CX + dx - .5), h = tall ? 3 : 2; [l, r].forEach(function (x) { p.rect(x, y, 2, h, c || K, { flat: true }); p.put(x, y, W); }); }
  function blush(p, y, dx, c) { var l = Math.round(CX - dx - .5), r = Math.round(CX + dx - .5); p.rect(l, y, 2, 1, c || '#ff9aa8', { flat: true }); p.rect(r, y, 2, 1, c || '#ff9aa8', { flat: true }); }
  function smile(p, y, c) { c = c || K; p.put(14, y, c); p.put(17, y, c); p.put(15, y + 1, c); p.put(16, y + 1, c); }
  function mouth(p, y, c) { p.rect(15, y, 2, 1, c || K, { flat: true }); }
  function ears(p, c, inn, y, dx, h, w) { w = w || 4; var x0 = CX - dx - w / 2; p.poly2([[x0, y], [x0 + w / 2, y - h], [x0 + w, y]], c); p.poly2([[x0 + 1, y], [x0 + w / 2, y - h + 2.5], [x0 + w - 1, y]], inn, { flat: true }); }
  function spark(p, x, y, c) { p.put(x, y, c); p.put(x - 1, y, c); p.put(x + 1, y, c); p.put(x, y - 1, c); p.put(x, y + 1, c); }
  function wings(p, y, c, tip, big) { var s = big ? 1.25 : 1; p.poly2([[10, y], [10 - 8 * s, y - 9 * s], [10 - 6 * s, y - 3 * s], [10 - 10 * s, y + 1 * s], [10 - 5 * s, y + 3 * s], [9, y + 6]], c); if (tip) { p.line(9, y + 1, 10 - 8 * s, y - 8 * s, tip); p.line(23, y + 1, 22 + 8 * s, y - 8 * s, tip); } }

  ART.ranocchio = function () {
    var p = new Px(N, N), g = '#8ed04a', dk = '#5ea02e', bl = '#f5efb0';
    p.ell2(9.5, 26.5, 4.5, 3, dk); p.ell(15.5, 21, 8.5, 6.5, g); p.ell(15.5, 23, 5.5, 4, bl);
    p.ell2(5.5, 28.5, 3, 1.8, g);
    p.ell(15.5, 15, 10, 6.5, g);
    p.ell2(6.2, 9.2, 3.8, 3.8, g); p.ell2(6.2, 9.4, 2.6, 2.6, W, { flat: true }); p.rect2(6, 9, 2, 3, K, { flat: true });
    p.rect(8, 17, 16, 1, dk, { flat: true }); p.put(7, 16, dk); p.put(24, 16, dk);
    p.rect2(7.5, 14, 2, 1, '#ff9aa8', { flat: true });
    p.poly([[14, 5], [17, 5], [16, 7.5], [18, 7.5], [14.5, 12], [15.5, 8.5], [13.5, 8.5]], '#ffe14d', { flat: true });
    return p;
  };
  ART.tartaruga = function () {
    var p = new Px(N, N), sh = '#4f9a5a', hd = '#9bd07a';
    p.ell2(10.5, 27.5, 3, 2.2, hd);
    p.ell(15.5, 15.5, 11.5, 9, sh); p.ell(15.5, 15.5, 8.4, 6.2, '#3e7e4a');
    [[15.5, 11], [10, 16], [21, 16], [15.5, 19.5]].forEach(function (c) { p.poly([[c[0] - 3, c[1]], [c[0] - 1.5, c[1] - 2.4], [c[0] + 1.5, c[1] - 2.4], [c[0] + 3, c[1]], [c[0] + 1.5, c[1] + 2.4], [c[0] - 1.5, c[1] + 2.4]], '#6cc07a'); });
    [[8, 9], [12, 8], [19, 8], [24, 11], [7, 13], [25, 16], [13, 7]].forEach(function (c) { p.put(c[0], c[1], '#a5f08c'); p.put(c[0] + 1, c[1], '#7fe08a'); });
    p.ell(15.5, 25.5, 5.2, 4.2, hd); p.eye2(2.6, 24, K); p.rect(15, 27, 2, 1, '#5d7d44', { flat: true }); blush(p, 26, 4.4);
    return p;
  };
  ART.libellula = function () {
    var p = new Px(N, N), wg = '#cfe9ff', vn = '#6fb3e8', bd = '#2fb3a8';
    p.poly2([[14, 12], [3, 5], [2, 9], [13, 15]], wg); p.poly2([[14, 15], [2, 14], [3, 18], [13, 18]], wg);
    p.line2(14, 13, 4, 7, vn); p.line2(13, 16, 4, 16, vn);
    p.tube([[15.5, 14, 2.6], [15.5, 19, 2], [15.5, 24, 1.6], [15.5, 29, 1.4]], bd);
    [17, 20, 23, 26].forEach(function (y) { p.rect(14, y, 4, 1, '#1a7a72', { flat: true }); });
    p.ell(15.5, 29.5, 1.6, 1.2, '#ffe14d', { flat: true });
    p.ell(15.5, 10, 4.8, 4.2, '#26b0a6'); p.ell2(3.2, 9, 2.6, 3, '#17415a'); p.put(11, 8, '#9be7ff'); p.put(20, 8, '#9be7ff');
    p.line(15.5, 5, 13, 2, '#1a7a72'); p.line(16, 5, 18, 2, '#1a7a72');
    return p;
  };
  ART.gatto = function () {
    var p = new Px(N, N), b = '#38355a', dk = '#25233f';
    p.tube([[22, 25, 1.7], [27, 22, 1.7], [28, 17, 1.7]], b); p.ell(28, 15.5, 1.8, 1.8, '#a56bff', { flat: true });
    p.ell(15.5, 24, 7, 5.5, b); p.ell(15.5, 25, 3.6, 3, '#ece6ff');
    p.ell2(4.5, 28.5, 2.8, 1.6, '#ece6ff');
    ears(p, b, '#ff9ac0', 8, 6.2, 6, 5);
    p.ell(15.5, 14, 9.5, 7.5, b);
    eyes(p, 12, 3.8, '#ffd23f', true); p.rect(Math.round(CX - 3.8 - .5) + 1, 13, 1, 2, K, { flat: true }); p.rect(Math.round(CX + 3.8 - .5), 13, 1, 2, K, { flat: true });
    p.put(15, 16, '#ff9ac0'); p.put(16, 16, '#ff9ac0'); p.put(14, 17, K); p.put(17, 17, K);
    p.line(5, 15, 1, 14, '#ece6ff'); p.line(5, 17, 1, 18, '#ece6ff'); p.line(26, 15, 30, 14, '#ece6ff'); p.line(26, 17, 30, 18, '#ece6ff');
    [[5, 30], [26, 30], [2, 26]].forEach(function (c) { p.put(c[0], c[1], '#a56bff'); p.put(c[0], c[1] + 1, '#7a4bd0'); });
    return p;
  };
  ART.lumaca = function () {
    var p = new Px(N, N), bd = '#d9a86f', mt = '#8d99ae';
    p.ell(14, 26, 12, 3.6, bd); p.ell(25, 22, 3.4, 4.6, bd); p.line(24, 19, 22, 14, bd, 1); p.line(27, 19, 29, 14, bd, 1);
    p.ell(22, 13.5, 1.6, 1.6, W, { flat: true }); p.ell(29, 13.5, 1.6, 1.6, W, { flat: true }); p.put(22, 13, K); p.put(29, 13, K);
    p.put(25, 23, K); p.put(27, 23, K); p.line(25, 25, 27, 25, '#9a6a3a');
    p.ell(12, 16, 9.5, 9.5, mt); p.ell(12, 16, 7, 7, '#c1cbdc'); p.ell(12, 16, 5, 5, mt); p.ell(12, 16, 3, 3, '#c1cbdc'); p.ell(12, 16, 1.2, 1.2, mt, { flat: true }); p.line(12, 7, 21, 16, '#6a7488'); p.line(3, 16, 12, 25, '#6a7488');
    for (var a = 0; a < 6; a++) { var r = a * 1.05; p.put(12 + Math.cos(r) * 8.6, 16 + Math.sin(r) * 8.6, '#ffe14d'); }
    p.line(3, 18, 4, 24, '#6a7488');
    return p;
  };
  ART.fatina = function () {
    var p = new Px(N, N);
    p.poly2([[13, 12], [3, 5], [3, 12], [12, 17]], '#e9f6ff'); p.poly2([[13, 16], [5, 19], [7, 25], [13, 20]], '#cfeaff');
    p.line2(12, 12, 4, 7, '#9bd7ff'); p.line2(12, 17, 7, 21, '#9bd7ff');
    p.line(14, 23, 13, 29, '#ffd9b5', 1); p.line(17, 23, 18, 29, '#ffd9b5', 1); p.rect(11, 29, 3, 1, '#ff8fd0', { flat: true }); p.rect(17, 29, 3, 1, '#ff8fd0', { flat: true });
    p.poly([[12, 15], [19, 15], [22, 24], [9, 24]], '#7fe3d0');
    p.rect(11, 18, 10, 1, '#4cb8a8', { flat: true });
    p.ell(15.5, 9.5, 6, 5.6, '#ff8fd0'); p.ell(15.5, 11, 4.4, 4.2, '#ffe0c2');
    p.rect(11, 8, 10, 2, '#ff8fd0', { flat: true }); eyes(p, 11, 2.2, K); blush(p, 13, 3.4); mouth(p, 14, '#c0506a');
    p.line(22, 18, 26, 21, '#ffd9b5'); p.rect(25, 21, 3, 5, '#ffe38a', { flat: true }); p.rect(25, 20, 3, 1, '#b08a30', { flat: true }); p.put(26, 22, W); spark(p, 28, 18, '#fff3a0'); spark(p, 4, 25, '#fff3a0');
    return p;
  };
  ART.volpe = function () {
    var p = new Px(N, N), o = '#f08a2a', w = '#fff3e0';
    p.tube([[21, 26, 2.8], [26, 22, 3.6], [27, 15, 3.2], [24, 9, 2]], o); p.ell(24, 8.5, 2, 2.4, '#ffe14d', { flat: true }); p.ell(27.5, 12, 1.6, 2.2, '#ff5a1f'); p.put(26, 19, '#ffe14d');
    p.ell(15.5, 24.5, 6.8, 5.2, o); p.ell(15.5, 25.5, 3.4, 3.2, w); p.ell2(4.5, 28.7, 2.8, 1.5, '#5a3a22');
    ears(p, o, '#ffd9b0', 8, 5.8, 7, 5); p.poly2([[7.6, 8], [8.8, 3], [10, 8]], '#3a2418', { flat: true });
    p.ell(15.5, 14.5, 9.5, 7.2, o); p.poly([[6, 17], [12, 14], [15.5, 19], [19, 14], [25, 17], [20, 22], [11, 22]], w);
    eyes(p, 12, 3.6, K, true); p.rect(14, 17, 4, 2, '#3a2418', { flat: true }); p.put(15, 19, '#3a2418'); p.put(16, 19, '#3a2418');
    return p;
  };
  ART.granchio = function () {
    var p = new Px(N, N), b = '#4fb5e8', lt = '#b9ecff';
    [[7, 24, 3, 29], [9, 26, 6, 30], [24, 26, 26, 30], [26, 24, 29, 29]].forEach(function (l) { p.line(l[0], l[1], l[2], l[3], '#2f7fb0'); });
    p.line(11, 14, 9, 9, '#2f7fb0'); p.line(21, 14, 23, 9, '#2f7fb0'); p.ell(9, 8, 2, 2, W, { flat: true }); p.ell(23, 8, 2, 2, W, { flat: true }); p.put(9, 8, K); p.put(23, 8, K);
    p.ell(15.5, 21, 10.5, 6.5, b); p.poly([[8, 22], [15.5, 14], [23, 22], [15.5, 27]], lt); p.poly([[11, 22], [15.5, 17], [20, 22], [15.5, 25]], '#7fd3f5');
    p.tube([[6, 18, 1.4], [3, 13, 1.6]], '#2f7fb0'); p.tube([[25, 18, 1.4], [28, 13, 1.6]], '#2f7fb0');
    p.ell(3.5, 9, 3.6, 4.2, b); p.poly([[3.5, 6], [5, 3], [6.5, 6]], lt); p.poly([[0.5, 6], [2, 3], [3.5, 6]], lt);
    p.ell(28.5, 9, 3.6, 4.2, b); p.poly([[28.5, 6], [27, 3], [25.5, 6]], lt); p.poly([[31.5, 6], [30, 3], [28.5, 6]], lt);
    eyes(p, 18, 3, K); mouth(p, 22, '#1f5f80'); spark(p, 12, 20, W); spark(p, 21, 24, W);
    return p;
  };
  ART.gufo = function () {
    var p = new Px(N, N), b = '#8b6a4a', dk = '#5f4630', bl = '#e9d4a8';
    p.ell(15.5, 20, 10, 10, b); p.ell(15.5, 22, 6.4, 7, bl);
    for (var y = 19; y < 28; y += 2) for (var x = 12; x < 20; x += 3) p.put(x + (y % 4 ? 1 : 0), y, '#c9a86a');
    p.poly2([[7, 14], [3, 20], [5, 28], [9, 27]], dk); p.line2(8, 17, 6, 25, '#3f2e1e');
    p.poly2([[8, 8], [6, 3], [12, 7]], b); p.poly2([[9, 8], [8, 5], [11, 7.5]], dk, { flat: true });
    p.ell2(4.2, 14, 4.4, 4.4, '#fff7c0'); p.ell2(4.2, 14, 2.4, 2.4, '#ffb13b', { flat: true }); p.ell2(4.2, 14, 1.2, 1.2, K, { flat: true });
    p.poly([[14, 17], [17, 17], [15.5, 20.5]], '#ff9f43', { flat: true });
    p.line(9, 14, 12, 14, '#3a2a1c'); p.line(19, 14, 22, 14, '#3a2a1c');
    p.rect2(3.5, 29, 3, 1, '#ff9f43', { flat: true });
    return p;
  };
  ART.lupo = function () {
    var p = new Px(N, N), f = '#7b8ca8', dk = '#4d5f80', w = '#eef3fb';
    p.tube([[22, 26, 2.4], [27, 22, 3], [28, 16, 2]], f); p.ell(28, 15, 1.8, 2.2, w, { flat: true });
    p.ell(15.5, 24.5, 7, 5.4, f); p.ell(15.5, 25, 3.6, 3.4, w); p.poly([[15.5, 20], [13, 25], [16, 24], [14.5, 28]], '#ffe14d', { flat: true });
    p.ell2(4.5, 28.6, 2.8, 1.6, dk);
    ears(p, dk, '#c0cde0', 8, 5.6, 8, 5);
    p.poly([[5, 17], [3, 12], [8, 14]], w); p.poly([[26, 17], [28, 12], [23, 14]], w);
    p.ell(15.5, 14.5, 9.6, 7.4, f); p.poly([[9, 17], [15.5, 13], [22, 17], [20, 22], [11, 22]], w);
    eyes(p, 11, 3.6, '#7fdcff', true); p.rect(Math.round(CX - 3.6 - .5) + 1, 12, 1, 2, K, { flat: true }); p.rect(Math.round(CX + 3.6 - .5), 12, 1, 2, K, { flat: true });
    p.rect(14, 17, 4, 2, K, { flat: true }); p.put(15, 20, '#ff7a8a'); p.put(16, 20, '#ff7a8a');
    spark(p, 4, 6, '#fff3a0'); spark(p, 28, 5, '#fff3a0');
    return p;
  };
  ART.sasso = function () {
    var p = new Px(N, N), r = '#8d8a99';
    p.poly([[6, 28], [4, 18], [8, 10], [14, 6], [20, 7], [26, 12], [28, 20], [26, 28]], r);
    p.poly([[10, 12], [15, 8], [20, 9], [17, 14]], '#a9a7b8'); p.poly([[8, 26], [6, 20], [10, 19], [12, 26]], '#6f6d7d');
    p.line(21, 12, 23, 18, '#5f5d6d'); p.line(23, 18, 20, 22, '#5f5d6d'); p.line(9, 14, 12, 18, '#6f6d7d');
    p.rect(9, 5, 5, 2, '#5fb86a', { flat: true }); p.put(10, 4, '#8fe07a'); p.put(13, 4, '#8fe07a'); p.rect(21, 7, 4, 2, '#5fb86a', { flat: true });
    eyes(p, 15, 3.6, '#ffb13b', true); p.rect(Math.round(CX - 3.6 - .5), 15, 2, 1, '#ffe29a', { flat: true }); p.rect(Math.round(CX + 3.6 - .5), 15, 2, 1, '#ffe29a', { flat: true });
    p.rect(12, 21, 8, 1, '#4a4858', { flat: true }); p.put(13, 22, '#4a4858'); p.put(18, 22, '#4a4858');
    p.poly([[3, 25], [1, 21], [4, 20]], '#7fd0ff'); p.poly([[29, 24], [31, 19], [27, 20]], '#7fd0ff');
    return p;
  };
  ART.mago = function () {
    var p = new Px(N, N);
    p.line(5, 7, 5, 29, '#8a5a2b', 2); p.ell(5, 5.5, 3.2, 3.2, '#7fe3ff'); p.ell(5, 5.5, 1.4, 1.4, W, { flat: true }); spark(p, 1, 3, '#cfeaff');
    p.poly([[10, 26], [21, 26], [24, 30], [8, 30]], '#3f55c8'); p.poly([[11, 17], [20, 17], [22, 28], [9, 28]], '#4a63e0'); p.rect(11, 22, 10, 1, '#ffd23f', { flat: true });
    p.ell2(8.4, 22, 2.2, 3.2, '#4a63e0'); p.ell2(8.4, 25, 1.7, 1.7, '#ffe0c2');
    p.ell(15.5, 13.5, 6.8, 6.2, '#ffe0c2'); p.poly([[10, 16], [21, 16], [19, 22], [12, 22]], '#e8e8f2');
    p.poly([[5, 10], [26, 10], [24, 12], [7, 12]], '#6a3bd0'); p.poly([[9, 11], [15.5, -2], [22, 11]], '#6a3bd0'); p.rect(9, 8, 14, 2, '#ffd23f', { flat: true });
    spark(p, 14, 5, '#ffe14d'); p.put(18, 7, '#ffe14d');
    eyes(p, 13, 2.6, K); blush(p, 15, 4); p.rect(14, 17, 4, 1, '#c0c0d6', { flat: true });
    return p;
  };
  function dragon(o) {
    var p = new Px(N, N), b = o.b, dk = o.dk, bl = o.bl, big = o.big;
    if (o.wing) { wings(p, big ? 16 : 18, o.wing, o.wingLine, big); }
    p.tube([[21, 26, 2.8], [26, 24, 2.4], [29, 19, 1.6]], b); p.poly([[28, 19], [31, 16], [30, 21]], o.spike || dk, { flat: true });
    p.ell(15.5, 24, 7, 5.6, b); p.ell(15.5, 25, 4, 3.8, bl); for (var y = 22; y < 29; y += 2) p.rect(12, y, 8, 1, mix(bl, b, .35), { flat: true });
    p.ell2(5, 28.6, 3, 1.7, dk);
    if (o.spines) { for (var i = 0; i < 4; i++) p.poly([[14.5, 6 + i * 0], [15.5, 3], [16.5, 6]], o.spike || dk, { flat: true }); }
    p.poly2([[9, 8], [6, 2], [12, 6]], o.horn || '#f2e3b3');
    p.ell(15.5, 14.5, 9.4, 7.6, b); p.ell(15.5, 18.4, 5.4, 3.6, bl);
    p.put(14, 18, dk); p.put(17, 18, dk); p.rect(13, 20, 6, 1, dk, { flat: true });
    p.poly2([[6.5, 14], [3, 12], [6.5, 17]], b);
    eyes(p, 11, 3.8, o.eye, true); p.rect(Math.round(CX - 3.8 - .5) + 1, 12, 1, 2, K, { flat: true }); p.rect(Math.round(CX + 3.8 - .5), 12, 1, 2, K, { flat: true });
    if (o.mark) { o.mark(p); }
    return p;
  }
  ART.draghetto = function () { return dragon({ b: '#e2574c', dk: '#a8352f', bl: '#ffd9a0', eye: '#ffe14d', wing: '#c0392b', wingLine: '#ff9a7a', spines: true }); };
  ART.cavaliere = function () {
    var p = new Px(N, N), s = '#b8c4d6', dk = '#7e8aa3';
    p.poly([[22, 17], [30, 17], [30, 25], [26, 29], [22, 25]], '#2f4fb0'); p.poly([[23, 18], [29, 18], [29, 24], [26, 27.5], [23, 24]], '#3d63d0'); p.rect(25, 19, 2, 7, '#ffd23f', { flat: true }); p.rect(23, 21, 6, 2, '#ffd23f', { flat: true });
    p.ell(15.5, 24, 6.6, 5.4, s); p.rect(11, 21, 10, 1, dk, { flat: true }); p.rect(14, 22, 4, 5, '#d63a4a', { flat: true });
    p.ell2(4.8, 28.6, 3, 1.7, dk);
    p.line(3, 28, 3, 15, '#dfe7f3', 2); p.rect(1, 22, 5, 1, '#ffd23f', { flat: true }); p.rect(2, 28, 3, 2, '#8a5a2b', { flat: true });
    p.tube([[15.5, 6, 1.6], [15.5, 3, 1.6], [20, 2, 1.6], [24, 5, 1.6], [25, 10, 1.4]], '#d63a4a');
    p.ell(15.5, 13.5, 8.6, 8, s); p.rect(8, 12, 16, 5, '#232a3d', { flat: true }); p.rect(8, 11, 16, 1, dk, { flat: true }); p.rect(15, 5, 2, 7, dk, { flat: true });
    p.rect(11, 13, 3, 2, '#7fe3ff', { flat: true }); p.rect(18, 13, 3, 2, '#7fe3ff', { flat: true }); p.put(11, 13, W); p.put(18, 13, W);
    for (var i = 0; i < 4; i++) p.put(13 + i * 2, 17, dk);
    return p;
  };
  ART.spettro = function () {
    var p = new Px(N, N), c = '#d9d4ff';
    p.poly([[6, 28], [5, 14], [9, 6], [15.5, 3], [22, 6], [26, 14], [25, 28], [22, 25], [19, 29], [16, 25], [13, 29], [10, 25]], c);
    p.poly([[9, 10], [15, 5], [20, 8], [13, 12]], '#f2eeff');
    p.tube([[5, 18, 1.6], [2, 22, 1.6], [3, 27, 1.2]], c); p.tube([[26, 18, 1.6], [29, 22, 1.6], [28, 27, 1.2]], c);
    p.ell2(3.6, 15, 3.2, 3.8, '#2a2250', { flat: true }); p.ell2(3.6, 15.5, 1.2, 1.6, '#ffe66b', { flat: true });
    p.ell(15.5, 21, 2, 2.6, '#2a2250', { flat: true });
    p.ell(15.5, 7.8, 2.6, 2.6, '#ffe66b', { flat: true }); p.ell(16.6, 7.5, 2.2, 2.4, '#f2eeff', { flat: true });
    p.line(3, 8, 3, 10, '#b9a8ff'); spark(p, 28, 6, '#ffe66b'); spark(p, 4, 29, '#b9a8ff');
    return p;
  };
  ART.grifone = function () {
    var p = new Px(N, N), g = '#d9a441', br = '#8a5a2b';
    p.poly2([[11, 18], [1, 6], [2, 14], [0, 18], [4, 21], [2, 25], [10, 27]], '#b9803a'); p.line2(10, 18, 2, 8, '#ffe29a'); p.line2(10, 21, 3, 18, '#ffe29a'); p.line2(10, 24, 4, 23, '#ffe29a');
    p.tube([[21, 26, 2], [26, 24, 2], [29, 20, 1.6]], g); p.poly([[27, 19], [31, 17], [30, 22]], br, { flat: true });
    p.ell(15.5, 24, 7, 5.4, g); p.ell(15.5, 25, 3.6, 3, '#ffe29a'); p.ell2(4.6, 28.5, 3, 1.8, '#f2b134'); p.rect2(5, 29, 1, 1, br, { flat: true });
    p.poly2([[9, 8], [8, 3], [12, 6]], '#f4f1de');
    p.ell(15.5, 13.5, 8.6, 7.4, '#f4f1de'); p.ell(15.5, 20, 5, 3.5, '#f4f1de');
    p.poly([[11, 14], [20, 14], [17.5, 22], [13.5, 22]], '#f2b134'); p.line(12, 16, 19, 16, '#b97a14'); p.put(14, 18, '#7a4a0a'); p.put(17, 18, '#7a4a0a');
    eyes(p, 11, 3.8, '#ff9f1c'); p.rect(Math.round(CX - 3.8 - .5) + 1, 11, 1, 2, K, { flat: true }); p.rect(Math.round(CX + 3.8 - .5), 11, 1, 2, K, { flat: true });
    p.line(8, 10, 12, 12, '#8a5a2b'); p.line(23, 10, 19, 12, '#8a5a2b');
    return p;
  };
  ART.leviatano = function () {
    var p = new Px(N, N), b = '#3b82d6', lt = '#9fd3ff';
    p.poly([[4, 26], [7, 20], [12, 26]], '#2b5fa8', { flat: true }); p.poly([[19, 22], [26, 19], [24, 25]], '#2b5fa8', { flat: true });
    p.tube([[10, 28, 3.4], [21, 26, 3.4], [24, 21, 3.4], [15, 17, 3.2], [9, 15, 3]], b); p.tube([[10, 28, 1.6], [21, 26, 1.6], [24, 21, 1.6]], lt, { flat: true });
    p.tube([[9, 15, 3], [11, 10, 3.2], [15, 6.5, 3.4]], b);
    p.poly([[10, 11], [8, 6], [13, 8]], '#2b5fa8'); p.poly([[18, 4], [21, 0], [22, 5]], '#ff7a3d', { flat: true });
    p.ell(18, 8.5, 6.2, 5.2, b); p.ell(19, 11, 4.2, 2.6, lt); p.put(21, 10, '#1f3f7a'); p.put(22, 11, '#1f3f7a');
    p.eye(17, 6, '#ffe14d'); p.put(17, 6, K); p.line(8, 17, 14, 19, '#7fd0ff'); p.line(12, 24, 18, 24, '#7fd0ff');
    spark(p, 27, 8, '#cfeaff'); spark(p, 4, 12, '#cfeaff');
    return p;
  };
  ART.fenice = function () {
    var p = new Px(N, N), o = '#ff6b35', y = '#ffd23f';
    p.poly2([[10, 18], [2, 8], [3, 14], [1, 18], [5, 20], [3, 24], [10, 24]], '#ff8a3d'); p.line2(9, 19, 3, 10, y); p.line2(9, 22, 4, 21, y);
    p.poly([[11, 24], [8, 30], [13, 27], [15.5, 31], [18, 27], [23, 30], [20, 24]], y, { flat: true }); p.poly([[13, 25], [12, 29], [15.5, 27]], '#ff4b1f', { flat: true });
    p.ell(15.5, 20.5, 8, 7.5, o); p.ell(15.5, 22, 5.2, 5.4, y);
    p.poly([[12, 8], [11, 2], [14, 6], [15.5, 0], [17, 6], [20, 2], [19, 8]], '#ff8a3d', { flat: true }); p.poly([[14, 8], [15.5, 3], [17, 8]], y, { flat: true });
    p.ell(15.5, 12.5, 6.8, 6, o); eyes(p, 11, 2.8, K, true); blush(p, 15, 4.4, '#ff3b52');
    p.poly([[14, 14], [17, 14], [15.5, 17.5]], '#ffd23f', { flat: true });
    p.put(4, 5, y); p.put(27, 6, y); p.put(2, 28, '#ff8a3d'); p.put(29, 25, '#ff8a3d');
    return p;
  };
  ART.drago_oscuro = function () {
    return dragon({ b: '#4b2f7a', dk: '#2d1a52', bl: '#8a5fc0', eye: '#ff3be0', wing: '#2d1a52', wingLine: '#b46bff', spines: true, spike: '#ff3be0', horn: '#d9c0ff', big: true });
  };
  ART.automa = function () {
    var p = new Px(N, N), br = '#c8a24a', dk = '#8a6a22', lt = '#f0d27a';
    p.line(15.5, 1, 15.5, 5, '#8a6a22'); p.ell(15.5, 1.5, 1.6, 1.6, '#ff5a5a', { flat: true });
    p.rect(9, 19, 14, 9, br); p.rect(9, 19, 14, 1, lt); p.rect(11, 28, 4, 2, dk); p.rect(17, 28, 4, 2, dk);
    p.rect(5, 19, 4, 8, dk); p.rect(23, 19, 4, 8, dk); p.rect(4, 27, 6, 3, br); p.rect(22, 27, 6, 3, br);
    p.ell(15.5, 24, 3.2, 3.2, dk); p.ell(15.5, 24, 1.6, 1.6, '#7fe3ff', { flat: true }); for (var a = 0; a < 6; a++) p.put(15.5 + Math.cos(a * 1.047) * 3.6, 24 + Math.sin(a * 1.047) * 3.6, lt);
    p.rect(12, 18, 8, 2, dk);
    p.rect(8, 5, 16, 13, br); p.rect(8, 5, 16, 1, lt); p.rect(6, 9, 2, 5, dk); p.rect(24, 9, 2, 5, dk);
    p.rect(10, 9, 12, 5, '#1a2a3a', { flat: true }); p.rect(11, 10, 4, 3, '#7fe3ff', { flat: true }); p.rect(17, 10, 4, 3, '#7fe3ff', { flat: true }); p.put(11, 10, W); p.put(17, 10, W);
    for (var i = 0; i < 5; i++) p.put(11 + i * 2, 16, dk);
    p.put(9, 6, '#6a5a2a'); p.put(22, 6, '#6a5a2a'); p.put(9, 16, '#6a5a2a'); p.put(22, 16, '#6a5a2a');
    return p;
  };
  ART.unicorno = function () {
    var p = new Px(N, N), w = '#ece6ff';
    p.tube([[21, 26, 2.6], [26, 24, 3], [28, 18, 2.4], [27, 12, 1.6]], '#7ee8d6'); p.tube([[27, 24, 1.4], [29, 18, 1.2]], '#ff9be0');
    p.ell(15.5, 24, 7, 5.4, w); p.ell(15.5, 25.4, 3.6, 3, '#fff'); p.ell2(4.6, 28.6, 2.8, 1.6, '#c8bfe8');
    p.poly2([[10, 9], [8, 3], [13, 7]], w); p.poly2([[10.5, 8.5], [9.2, 5], [12, 7.5]], '#ff9be0', { flat: true });
    p.poly2([[7, 18], [4, 14], [8, 9], [11, 12]], '#7ee8d6'); p.line2(7, 15, 9, 11, '#ff9be0');
    p.ell(15.5, 14.5, 8.6, 7.4, w);
    p.poly([[9, 8], [22, 8], [24, 12], [20, 12], [15.5, 9.5], [11, 12], [7, 12]], '#ff9be0');
    p.poly([[13.5, 9], [15.5, 0], [17.5, 9]], '#ffd23f'); p.line(14, 7, 17, 6, '#b08a30'); p.line(14, 4, 16.5, 3, '#b08a30');
    p.ell(15.5, 19, 4.6, 3, '#fff'); p.put(14, 19, '#c8bfe8'); p.put(17, 19, '#c8bfe8');
    eyes(p, 13, 3.8, '#6a3bd0', true); blush(p, 17, 6.2);
    spark(p, 4, 6, '#fff3a0'); spark(p, 28, 4, '#cfeaff'); spark(p, 3, 24, '#ff9be0');
    return p;
  };
  ART.idra = function () {
    var p = new Px(N, N), g = '#5dbb63', dk = '#357a3d', y = '#e8f08a';
    p.ell(15.5, 25, 9, 5.8, g); p.ell(15.5, 26.4, 5.4, 3.8, y); for (var x = 12; x < 20; x += 2) p.rect(x, 25, 1, 4, mix(y, g, .4), { flat: true }); p.ell2(7, 28.6, 3, 1.7, dk);
    p.tube([[15.5, 22, 2.4], [15.5, 15, 2.4], [15.5, 9, 2.4]], g); p.tube([[11, 23, 2.1], [7, 17, 2.1], [6, 11, 2.1]], g); p.tube([[20, 23, 2.1], [24, 17, 2.1], [25, 11, 2.1]], g);
    function head(x, y2, r, c) { p.ell(x, y2, r + 1, r, c); p.ell(x, y2 + r * .5, r * .7, r * .5, y); p.put(x - 1.5, y2 - 1, K); p.put(x + 1.5, y2 - 1, K); p.put(x - 1.5, y2 - 2, W); p.put(x + 1.5, y2 - 2, W); p.poly([[x - 2, y2 - r], [x - 3, y2 - r - 2], [x - 1, y2 - r + .5]], '#f2e3b3', { flat: true }); p.poly([[x + 2, y2 - r], [x + 3, y2 - r - 2], [x + 1, y2 - r + .5]], '#f2e3b3', { flat: true }); }
    head(15.5, 7, 4.2, g); head(6, 9.5, 3.4, '#4aa856'); head(25, 9.5, 3.4, '#4aa856');
    p.line(15.5, 12, 15.5, 11, '#ff7a8a'); spark(p, 2, 3, '#e8f08a'); spark(p, 29, 3, '#e8f08a');
    return p;
  };
  ART.guardiano = function () {
    var p = new Px(N, N), j = '#4ec9a0', dk = '#2a8f72', gd = '#ffd23f';
    p.tube([[22, 26, 2], [27, 22, 2.4]], j); p.ell(27.5, 19.5, 3, 3.4, '#7fe9c8');
    p.ell(15.5, 24, 7, 5.4, j); p.ell(15.5, 25, 3.6, 3, '#9ff5da'); p.ell2(4.6, 28.6, 3, 1.7, dk); p.rect2(4.6, 28, 3, 1, gd, { flat: true });
    [[6, 11], [10, 6], [15.5, 4.5], [21, 6], [25, 11], [6, 18], [25, 18]].forEach(function (c) { p.ell(c[0], c[1], 3.4, 3.4, '#7fe9c8'); p.put(c[0] - 1, c[1] - 1, '#cffff0'); });
    p.ell(15.5, 13.5, 8.4, 7.4, j); p.poly([[14, 5], [15.5, 1], [17, 5]], gd, { flat: true });
    p.ell2(4, 10, 3.2, 3, '#7fe9c8'); p.rect2(3.4, 9, 2, 2, dk, { flat: true });
    p.poly([[11, 14], [20, 14], [19, 21], [12, 21]], '#9ff5da'); p.rect(13, 19, 6, 2, '#1a3a30', { flat: true }); p.put(13, 21, W); p.put(18, 21, W); p.put(14, 17, dk); p.put(17, 17, dk);
    eyes(p, 10, 3.4, '#ffd23f', true); p.rect(Math.round(CX - 3.4 - .5) + 1, 11, 1, 1, K, { flat: true }); p.rect(Math.round(CX + 3.4 - .5), 11, 1, 1, K, { flat: true });
    return p;
  };
  ART.serafino = function () {
    var p = new Px(N, N), w = '#fffaf0';
    p.poly2([[12, 14], [2, 6], [4, 14], [1, 18], [6, 20], [11, 20]], w); p.poly2([[12, 18], [3, 20], [5, 26], [12, 24]], '#e6efff'); p.poly2([[12, 11], [5, 3], [8, 9], [11, 13]], '#cfe3ff');
    p.line2(11, 14, 3, 8, '#9bc0f5'); p.line2(11, 19, 5, 21, '#9bc0f5');
    p.poly([[11, 19], [20, 19], [23, 30], [8, 30]], '#eaf2ff'); p.rect(10, 23, 12, 1, '#ffd23f', { flat: true }); p.ell2(5.4, 24, 2, 2.4, '#fffaf0');
    p.ell(15.5, 12, 6.8, 6.4, '#ffe9d2'); p.ell(15.5, 7.4, 6.4, 3.6, '#ffe66b'); p.rect(10, 9, 3, 4, '#ffe66b', { flat: true }); p.rect(19, 9, 3, 4, '#ffe66b', { flat: true });
    [[12, 12], [19, 12]].forEach(function (c) { p.put(c[0], c[1], K); p.put(c[0] + 1, c[1] + 1, K); p.put(c[0] - 1, c[1] + 1, K); }); blush(p, 14, 3.8); smile(p, 15, '#c0506a');
    p.ell(15.5, 2.6, 6, 1.7, '#ffd23f', { flat: true }); p.ell(15.5, 2.6, 4, .9, '#fff3a0', { flat: true });
    spark(p, 3, 28, '#ffe66b'); spark(p, 28, 27, '#ffe66b');
    return p;
  };
  ART.drago_tuono = function () {
    return dragon({ b: '#3b6fe0', dk: '#22418f', bl: '#cfe2ff', eye: '#ffe14d', wing: '#1d3aa0', wingLine: '#ffe14d', spines: true, spike: '#ffe14d', horn: '#ffe14d', big: true, mark: function (p) { p.poly([[14, 3], [18, 3], [16, 6.5], [18.5, 6.5], [13, 12], [14.8, 7.5], [12.5, 7.5]], '#ffe14d', { flat: true }); } });
  };
  ART.cerbero = function () {
    var p = new Px(N, N), b = '#3d2b33', dk = '#241a20';
    p.tube([[22, 28, 1.6], [27, 25, 1.4], [29, 20, 1.2]], '#8a8a96'); p.ell(29, 18.5, 2, 2.4, '#ff5a1f');
    p.ell(15.5, 25, 8.4, 5.4, b); p.ell(15.5, 26, 4, 3.4, '#6a4a54'); p.ell2(5.4, 28.7, 3, 1.7, dk);
    function head(x, y, r) { p.poly([[x - r + .5, y - r + 1], [x - r - 1, y - r - 3], [x - 1, y - r]], dk); p.poly([[x + r - .5, y - r + 1], [x + r + 1, y - r - 3], [x + 1, y - r]], dk); p.ell(x, y, r + 1.2, r, b); p.ell(x, y + r * .55, r * .65, r * .4, '#6a4a54'); p.rect(x - 2, y - 1, 1, 2, '#ff3b52', { flat: true }); p.rect(x + 1, y - 1, 1, 2, '#ff3b52', { flat: true }); p.put(x, y + r * .6, '#1a1020'); p.put(x - 1, y + r * .6 + 1.5, W); p.put(x + 1, y + r * .6 + 1.5, W); }
    p.rect(5, 18, 22, 2, '#8a8a96', { flat: true }); [7, 11, 15, 19, 23].forEach(function (x) { p.put(x, 17, '#cfd3dd'); });
    head(6, 14, 4); head(25, 14, 4); head(15.5, 10, 5);
    p.poly([[13, 3], [15.5, 0], [18, 3]], '#ff7a1f', { flat: true }); p.put(15, 2, '#ffd23f');
    return p;
  };
  ART.sfinge = function () {
    var p = new Px(N, N), g = '#d9a441', bl = '#2f6fd0';
    p.poly2([[10, 19], [3, 12], [2, 20], [9, 24]], '#f4e3b0'); p.line2(9, 19, 4, 14, '#c9a86a');
    p.ell(15.5, 25, 9, 4.6, g); p.rect(6, 28, 4, 2, '#f2b134'); p.rect(22, 28, 4, 2, '#f2b134'); p.rect(11, 27, 4, 3, '#f2b134'); p.rect(17, 27, 4, 3, '#f2b134');
    p.poly([[5, 28], [9, 12], [15.5, 6], [22, 12], [26, 28], [22, 24], [9, 24]], bl); for (var y = 12; y < 26; y += 3) { p.line(7, y + 1, 12, y, '#ffd23f'); p.line(25, y + 1, 19, y, '#ffd23f'); }
    p.poly([[11, 9], [15.5, 4], [20, 9], [19, 12], [12, 12]], '#ffd23f'); p.ell(15.5, 6.6, 1.4, 1.4, '#ff3b52', { flat: true });
    p.ell(15.5, 15.5, 6.6, 6.4, '#e6b25a'); p.ell(15.5, 19, 3.4, 2.4, '#f5d9a0');
    p.rect(9, 13, 14, 1, '#ffd23f', { flat: true }); eyes(p, 14, 2.8, '#7fe3ff'); p.line(10, 15, 8, 17, '#1a1030'); p.line(21, 15, 23, 17, '#1a1030'); p.put(15, 18, '#7a4a1a'); p.put(16, 18, '#7a4a1a'); smile(p, 20, '#7a4a1a');
    p.poly([[13, 21], [18, 21], [17, 28], [14, 28]], '#ffd23f', { flat: true }); spark(p, 28, 4, '#cfeaff'); spark(p, 3, 5, '#cfeaff');
    return p;
  };
  ART.drago_celeste = function () {
    return dragon({ b: '#f4f1ff', dk: '#b9b4e0', bl: '#fff3c8', eye: '#4fb8ff', wing: '#fff3c8', wingLine: '#ffd23f', spines: true, spike: '#ffd23f', horn: '#ffd23f', big: true, mark: function (p) { spark(p, 15.5, 4.6, '#4fb8ff'); } });
  };
  ART.tartaruga_cosmica = function () {
    var p = new Px(N, N);
    p.ell2(9.5, 27.5, 3.4, 2.4, '#7a8be0'); p.ell(15.5, 26, 4.8, 4, '#9aa9f0'); p.eye2(2.4, 24, K); p.rect(15, 27, 2, 1, '#4a56a8', { flat: true });
    p.ell(15.5, 17.5, 12.5, 10, '#ffd23f'); p.ell(15.5, 17.5, 11, 8.8, '#2a2a7a'); p.ell(15.5, 17.5, 8, 6, '#3d3ba8'); p.ell(15.5, 17.5, 4.5, 3.4, '#5a52d0');
    [[8, 12], [22, 12], [6, 19], [25, 20], [12, 23], [19, 23], [15, 10], [10, 16], [21, 16]].forEach(function (c) { p.put(c[0], c[1], W); });
    spark(p, 9, 14, '#ffe66b'); spark(p, 22, 21, '#ffe66b'); p.put(17, 17, '#ff9be0'); p.put(14, 19, '#7fe3ff');
    p.ell(15.5, 5.5, 4.6, 1.6, '#7fd06a'); p.rect(15, 2, 1, 4, '#8a5a2b', { flat: true }); p.ell(15.5, 2, 2.6, 2.2, '#5fb86a'); p.put(14, 1, '#8fe07a'); p.put(17, 2, '#8fe07a');
    p.line(3, 8, 8, 5, '#ffe66b'); p.line(28, 8, 23, 5, '#ffe66b');
    return p;
  };
  ART.spirito = function () {
    var p = new Px(N, N), gd = '#ffd23f';
    for (var a = 0; a < 8; a++) { var r = a * .7854; p.line(15.5 + Math.cos(r) * 8, 16 + Math.sin(r) * 8, 15.5 + Math.cos(r) * 14.5, 16 + Math.sin(r) * 14.5, '#fff3a0'); }
    p.ell(15.5, 16, 12.4, 12.4, '#4a3a9a'); p.ell(15.5, 16, 11, 11, '#6a55c8'); p.ell(15.5, 16, 8.6, 8.6, '#8a78e8');
    p.poly([[7, 12], [15.5, 3], [24, 12]], '#fff3c8'); p.rect(8, 12, 16, 2, gd, { flat: true });
    [9, 13, 18, 22].forEach(function (x) { p.rect(x, 14, 2, 10, '#fffaf0'); p.rect(x - 1, 14, 4, 1, gd, { flat: true }); p.rect(x - 1, 23, 4, 1, gd, { flat: true }); });
    p.rect(8, 24, 16, 2, gd, { flat: true }); p.rect(7, 26, 18, 2, '#fff3c8');
    p.rect(14, 17, 4, 7, '#2a1a5a', { flat: true }); p.rect(14, 18, 1, 1, '#ffe66b', { flat: true }); p.rect(17, 18, 1, 1, '#ffe66b', { flat: true });
    eyes(p, 9, 2.6, '#ffe66b'); p.ell(15.5, 7.3, 1.2, 1.2, gd, { flat: true });
    spark(p, 3, 4, W); spark(p, 28, 5, W); spark(p, 2, 27, '#ffe66b'); spark(p, 29, 28, '#ffe66b');
    return p;
  };
  /* ---------- gradi 10–14 (livelli 420–600): 15 compagni nuovi, sempre creature originali ---------- */
  ART.chimera = function () {            /* leone alato con criniera di fiamma e coda di serpente */
    var p = new Px(N, N), b = '#e0a03a', dk = '#a8661c', mn = '#ff5a2a';
    wings(p, 17, '#7a3a8a', '#d9a3ff');
    p.tube([[22, 26, 1.6], [27, 26, 1.4], [29, 22, 1.4], [27, 19, 1.6]], '#4fae5a'); p.ell(26.5, 18.5, 2, 1.6, '#4fae5a'); p.put(26, 18, '#ffe14d');
    p.ell(15.5, 24, 7.4, 5.4, b); p.ell(15.5, 25.4, 4, 3.2, '#ffd9a0'); p.ell2(5, 28.6, 3, 1.7, dk); p.rect2(4, 29, 1, 1, '#fff3cf', { flat: true });
    for (var a = 0; a < 12; a++) { var r = a * .5236; p.poly([[15.5 + Math.cos(r) * 6, 14 + Math.sin(r) * 6], [15.5 + Math.cos(r + .26) * 11.5, 14 + Math.sin(r + .26) * 10.5], [15.5 + Math.cos(r + .52) * 6, 14 + Math.sin(r + .52) * 6]], a % 2 ? mn : '#ffb03a', { flat: true }); }
    p.ell(15.5, 14, 7.4, 6.8, b); p.ell(15.5, 17.6, 4, 2.6, '#ffd9a0');
    eyes(p, 12, 3, '#ff3b2a', true); p.rect(15, 16, 2, 1, '#6a2a14', { flat: true }); smile(p, 18, '#6a2a14');
    p.poly2([[10, 8], [9, 4], [12, 7]], '#f2e3b3');
    return p;
  };
  ART.golem_ossidiana = function () {    /* golem di vetro vulcanico con nucleo di lava */
    var p = new Px(N, N), b = '#2c2440', lt = '#5a4a80', lv = '#ff6a1f';
    p.rect(9, 25, 5, 5, b); p.rect(18, 25, 5, 5, b);
    p.poly([[6, 13], [10, 9], [22, 9], [26, 13], [25, 25], [7, 25]], b); p.poly([[9, 11], [15, 9], [13, 16], [8, 18]], lt, { flat: true });
    p.tube([[6, 14, 2.6], [3, 20, 2.8], [3, 25, 3]], b); p.tube([[26, 14, 2.6], [29, 20, 2.8], [29, 25, 3]], b);
    p.ell(15.5, 18.5, 3.4, 3.4, '#ffb03a', { flat: true }); p.ell(15.5, 18.5, 2, 2, '#ffe66b', { flat: true });
    p.line(15, 22, 13, 25, lv); p.line(17, 22, 20, 25, lv); p.line(12, 18, 8, 20, lv); p.line(19, 17, 23, 15, lv);
    p.poly([[10, 9], [12, 3], [15.5, 6], [19, 3], [21, 9]], b); p.poly([[12, 4], [14, 6], [12, 8]], lt, { flat: true });
    p.rect(11, 11, 3, 2, lv, { flat: true }); p.rect(18, 11, 3, 2, lv, { flat: true }); p.put(11, 11, '#ffe66b'); p.put(18, 11, '#ffe66b');
    spark(p, 4, 6, '#ff9a3a'); spark(p, 28, 9, '#ff9a3a');
    return p;
  };
  ART.medusa = function () {             /* medusa abissale luminosa */
    var p = new Px(N, N), b = '#5ad1e8', dk = '#2a8fb8', gl = '#d6fbff';
    [[8, 2], [12, 1], [16, 0], [20, 1], [24, 2]].forEach(function (c, i) { p.tube([[c[0], 17, 1.3], [c[0] + (i % 2 ? 2 : -2), 22, 1.1], [c[0], 26, 1], [c[0] + (i % 2 ? -1 : 1), 30, .7]], i % 2 ? '#ff8ad8' : '#9fe8ff'); });
    p.ell(15.5, 12.5, 11.5, 9, b); p.rect(4, 13, 24, 6, b); p.ell(15.5, 18.5, 11.6, 2.4, dk);
    p.ell(15.5, 10, 7.5, 5.4, '#8ae6f5'); p.ell(12, 7, 3, 2, gl, { flat: true });
    for (var x = 5; x < 27; x += 3) p.put(x, 19, '#ff8ad8');
    eyes(p, 13, 3.2, '#1a1030', true); blush(p, 15, 5, '#ff8ad8'); smile(p, 16, '#1a1030');
    spark(p, 3, 4, gl); spark(p, 29, 8, gl); p.put(27, 28, gl); p.put(4, 26, gl);
    return p;
  };
  ART.kirin = function () {              /* cavallo sacro con corno e criniera di fulmini */
    var p = new Px(N, N), b = '#f2efe6', sc = '#6cc0b8', mn = '#4fb8ff';
    p.rect(8, 23, 3, 7, b); p.rect(13, 24, 3, 6, b); p.rect(19, 24, 3, 6, b); p.rect(24, 23, 3, 7, b);
    [8, 13, 19, 24].forEach(function (x) { p.rect(x, 29, 3, 1, '#ffd23f', { flat: true }); });
    p.ell(17, 20, 10, 5.6, b); for (var x = 10; x < 26; x += 3) p.ell(x, 20, 1.4, 1, sc, { flat: true });
    p.tube([[27, 18, 1.6], [30, 21, 1.4], [29, 26, 1.2]], mn);
    p.tube([[10, 18, 3], [8, 12, 3]], b); p.ell(7.5, 9, 4.6, 3.8, b); p.ell(4.5, 10.5, 2.6, 2.2, b);
    p.poly([[9, 6], [12, 0], [11, 6]], '#ffd23f', { flat: true }); p.put(11, 2, W);
    p.poly([[10, 6], [15, 7], [12, 10], [16, 12], [12, 14], [14, 17], [10, 16]], mn, { flat: true }); p.line(12, 9, 15, 12, '#cfeaff');
    p.eye(6, 8, '#4fb8ff'); p.put(3, 11, '#5a5a6a');
    spark(p, 22, 6, '#4fb8ff'); spark(p, 28, 12, '#cfeaff');
    return p;
  };
  ART.scarabeo = function () {           /* scarabeo d'ambra corazzato */
    var p = new Px(N, N), b = '#c87a14', dk = '#8a4a0a', am = '#ffb83a';
    [[8, 18, 2, 14], [7, 23, 1, 20], [8, 27, 2, 26]].forEach(function (l) { p.line(l[0], l[1], l[2], l[3] + 2, '#3a2410'); p.line(31 - l[0], l[1], 29 - l[2], l[3] + 2, '#3a2410'); });
    p.ell(15.5, 20, 9.5, 9, b); p.line(15, 12, 15, 29, dk); p.line(16, 12, 16, 29, dk);
    p.ell(11.5, 18, 3, 4, am, { flat: true }); p.ell(20.5, 18, 3, 4, am, { flat: true }); p.ell(10.5, 16.5, 1, 1.6, '#fff0b8', { flat: true }); p.ell(19.5, 16.5, 1, 1.6, '#fff0b8', { flat: true });
    p.put(11, 19, '#6a3a0a'); p.put(21, 19, '#6a3a0a');
    p.ell(15.5, 10, 6.4, 4.4, '#5a3410'); p.poly([[13, 7], [15.5, 0], [18, 7]], '#5a3410'); p.poly([[15, 2], [15.5, 0], [16.5, 3]], am, { flat: true });
    p.line(11, 7, 8, 3, '#3a2410'); p.line(20, 7, 23, 3, '#3a2410');
    eyes(p, 9, 2.8, '#ffe14d'); smile(p, 12, '#ffb83a');
    return p;
  };
  ART.kitsune = function () {            /* volpe spirito a nove code, lunare */
    var p = new Px(N, N), b = '#f4f1ff', in_ = '#b9a8ff', tip = '#7fd0ff';
    for (var i = 0; i < 5; i++) { var a = -2.95 + i * .64, ex = 15.5 + Math.cos(a) * 14, ey = 22 + Math.sin(a) * 12; p.tube([[15.5 + Math.cos(a) * 3, 23, 1.8], [15.5 + Math.cos(a) * 9, 22 + Math.sin(a) * 8, 2.6], [ex, ey, 1.6]], b); p.ell(ex, ey, 1.8, 1.8, tip, { flat: true }); }
    p.ell(15.5, 24.5, 6.6, 5.2, b); p.ell(15.5, 25.5, 3.4, 3, '#ffffff'); p.ell2(4, 28.7, 2.6, 1.6, in_);
    ears(p, b, in_, 9, 6, 7, 5);
    p.ell(15.5, 14, 7.6, 6.4, b); p.ell(15.5, 17.6, 3.6, 2.4, '#ffffff');
    p.poly([[12, 12], [10, 11], [12, 10]], '#ff5aa0', { flat: true }); p.poly([[19, 12], [21, 11], [19, 10]], '#ff5aa0', { flat: true });
    eyes(p, 13, 2.6, '#7a5ad8'); p.put(15, 16, K); p.put(16, 16, K); smile(p, 17);
    p.ell(15.5, 9.5, 1.2, 1.2, '#7fd0ff', { flat: true }); spark(p, 26, 4, '#cfeaff'); spark(p, 4, 5, '#cfeaff');
    return p;
  };
  ART.wyrm_magma = function () {
    return dragon({ b: '#3a2220', dk: '#1f1210', bl: '#ff9a3a', eye: '#ffe14d', wing: '#5a1e10', wingLine: '#ff6a1f', spines: true, spike: '#ff6a1f', horn: '#ffb03a', big: true,
      mark: function (p) { p.line(9, 15, 12, 17, '#ff6a1f'); p.line(22, 15, 19, 17, '#ff6a1f'); p.line(11, 23, 13, 27, '#ff6a1f'); p.line(20, 23, 18, 27, '#ff6a1f'); spark(p, 15.5, 4, '#ffb03a'); } });
  };
  ART.kraken = function () {             /* piovra delle profondità */
    var p = new Px(N, N), b = '#a03a8a', dk = '#6a1e5a', sk = '#ffb8e8';
    [[-11, 1], [-7, -1], [-3, 1], [3, -1], [7, 1], [11, -1]].forEach(function (t) { var x = 15.5 + t[0]; p.tube([[15.5 + t[0] * .4, 20, 2.2], [x, 24, 1.8], [x + t[1] * 3, 28, 1.3], [x + t[1] * 5, 26, .9]], b); p.put(Math.round(x), 26, sk); });
    p.ell(15.5, 12, 10, 9.4, b); p.ell(15.5, 19, 8, 3.4, b); p.ell(12, 7, 3.6, 2.6, '#d06ab8', { flat: true });
    [[8, 12], [23, 12], [11, 6], [20, 5], [15, 3]].forEach(function (c) { p.ell(c[0], c[1], 1, 1, sk, { flat: true }); });
    p.ell2(4, 14, 3, 3, '#fff3cf', { flat: true }); p.ell2(4, 14.5, 1.4, 1.8, '#1a1030', { flat: true }); p.px2(4.5, 13, W);
    p.rect(14, 18, 4, 1, dk, { flat: true });
    spark(p, 3, 4, '#9fe8ff'); p.put(28, 5, '#9fe8ff'); p.put(27, 4, '#9fe8ff');
    return p;
  };
  ART.gatto_nebulosa = function () {     /* gatto con il pelo fatto di galassia */
    var p = new Px(N, N), b = '#2a2a7a', b2 = '#5a3ab8', st = '#ffffff';
    p.tube([[22, 27, 2], [27, 25, 2], [29, 19, 1.8], [27, 15, 1.6]], b2); p.ell(27, 14.5, 2, 2, '#ff7ad8', { flat: true });
    p.ell(15.5, 24, 7.6, 5.8, b); p.ell(14, 23, 4, 3, b2, { flat: true }); p.ell2(5, 28.6, 3, 1.8, b);
    ears(p, b, '#ff7ad8', 10, 5.5, 7, 5);
    p.ell(15.5, 14.5, 8.6, 7, b); p.ell(12.5, 12.5, 4, 3, b2, { flat: true }); p.ell(19.5, 17, 3, 2, '#7a3ab8', { flat: true });
    [[9, 13], [20, 11], [13, 18], [22, 16], [17, 9], [8, 22], [21, 24], [13, 26], [18, 22]].forEach(function (c) { p.put(c[0], c[1], st); });
    spark(p, 11, 21, '#ffe66b'); spark(p, 20, 27, '#9fe8ff');
    eyes(p, 13, 3, '#ffe66b', true); p.put(15, 16, '#ff7ad8'); p.put(16, 16, '#ff7ad8'); smile(p, 17, '#ff7ad8');
    p.line(5, 15, 9, 16, '#9fa8ff'); p.line(26, 15, 22, 16, '#9fa8ff');
    return p;
  };
  ART.drago_vuoto = function () {
    return dragon({ b: '#24123f', dk: '#12091f', bl: '#7a4ae0', eye: '#ff5aa0', wing: '#3a1a6a', wingLine: '#c9a8ff', spines: true, spike: '#c9a8ff', horn: '#c9a8ff', big: true,
      mark: function (p) { [[10, 13], [21, 16], [14, 24], [18, 26], [12, 18]].forEach(function (c) { p.put(c[0], c[1], '#ffffff'); }); spark(p, 15.5, 4.6, '#ff5aa0'); p.ell(15.5, 1.6, 2.4, 1, '#c9a8ff', { flat: true }); } });
  };
  ART.behemoth = function () {           /* bestione corazzato a quattro corna */
    var p = new Px(N, N), b = '#6a5a4a', dk = '#463a30', pl = '#b8a888', hn = '#f2e3c0';
    p.rect(6, 24, 5, 6, dk); p.rect(21, 24, 5, 6, dk); p.rect(12, 25, 3, 5, dk); p.rect(17, 25, 3, 5, dk);
    p.ell(16.5, 19.5, 12.5, 7.4, b); for (var i = 0; i < 5; i++) p.poly([[8 + i * 4.4, 13.5], [10 + i * 4.4, 9], [12 + i * 4.4, 13.5]], pl);
    p.rect(7, 19, 20, 1, dk, { flat: true });
    p.ell(8, 18, 6.4, 5.6, b); p.ell(5, 21, 3.6, 2.6, pl);
    p.poly([[4, 14], [0, 8], [6, 12]], hn); p.poly([[10, 13], [13, 6], [12, 14]], hn); p.poly([[3, 22], [0, 24], [4, 24]], hn);
    p.eye(5, 16, '#ff3b2a'); p.eye(9, 16, '#ff3b2a'); p.put(4, 21, dk); p.put(6, 21, dk);
    p.tube([[29, 18, 1.6], [31, 22, 1.2]], dk);
    return p;
  };
  ART.arcangelo = function () {          /* spirito di luce alato con aureola */
    var p = new Px(N, N), b = '#fff8e6', gd = '#ffd23f', wg = '#ffffff';
    p.poly2([[12, 16], [1, 5], [2, 12], [0, 15], [3, 18], [1, 22], [11, 22]], wg); p.line2(11, 16, 3, 8, '#e0e8ff'); p.line2(11, 19, 2, 15, '#e0e8ff'); p.line2(11, 21, 3, 20, '#e0e8ff');
    p.poly([[10, 30], [12, 18], [20, 18], [22, 30]], b); p.rect(12, 21, 8, 1, gd, { flat: true }); p.poly([[14, 22], [18, 22], [16, 30]], '#ffe9a8', { flat: true });
    p.ell(15.5, 12.5, 6, 6, '#ffe0c2'); p.poly([[9, 11], [15.5, 5], [22, 11], [21, 8], [15.5, 4], [10, 8]], '#ffe14d');
    p.ell(15.5, 2.5, 5.5, 1.6, gd); p.ell(15.5, 2.5, 3.8, .6, '#fffbe0', { flat: true });
    eyes(p, 12, 2.4, '#4fb8ff'); blush(p, 14, 3.6); smile(p, 15, '#c06a4a');
    spark(p, 3, 26, gd); spark(p, 28, 26, gd); spark(p, 27, 2, '#cfeaff');
    return p;
  };
  ART.drago_primordiale = function () {
    return dragon({ b: '#ffd23f', dk: '#c08a14', bl: '#fff3c8', eye: '#ff3b52', wing: '#ff6ad5', wingLine: '#7fe3ff', spines: true, spike: '#7fe3ff', horn: '#ffffff', big: true,
      mark: function (p) { p.ell(15.5, 1.6, 4, 1.2, '#fffbe0', { flat: true }); spark(p, 15.5, 4.6, '#7fe3ff'); [[9, 23], [22, 23], [15, 27]].forEach(function (c) { p.put(c[0], c[1], '#ff6ad5'); }); } });
  };
  ART.eclissi = function () {            /* guardiano dell'eclissi: sole e luna in armatura */
    var p = new Px(N, N), ar = '#3a3a5a', lt = '#6a6a9a', gd = '#ffd23f';
    for (var a = 0; a < 12; a++) { var r = a * .5236; p.line(15.5 + Math.cos(r) * 10, 13 + Math.sin(r) * 10, 15.5 + Math.cos(r) * 14.5, 13 + Math.sin(r) * 14.5, a % 2 ? '#ffb03a' : gd); }
    p.ell(15.5, 13, 10, 10, gd); p.ell(17.5, 12, 8.4, 8.4, '#1a1030', { flat: true }); p.ell(13, 9, 2, 2, '#fff3a0', { flat: true });
    p.poly([[8, 30], [9, 20], [22, 20], [23, 30]], ar); p.poly([[10, 21], [15, 21], [12, 29]], lt, { flat: true });
    p.rect2(9, 19, 4, 3, lt); p.rect(14, 22, 4, 4, gd, { flat: true }); p.put(15, 23, W);
    p.ell(15.5, 13.5, 5, 5, ar); p.rect(11, 12, 10, 3, '#12091f', { flat: true }); p.rect(12, 13, 2, 1, '#7fe3ff', { flat: true }); p.rect(18, 13, 2, 1, '#7fe3ff', { flat: true });
    p.rect(15, 7, 2, 4, gd, { flat: true });
    return p;
  };
  ART.albero_mondo = function () {       /* piccolo albero del mondo con un volto gentile */
    var p = new Px(N, N), tr = '#8a5a2b', dk = '#5a3a1a', lf = '#4fae5a', lf2 = '#7fe07a';
    p.poly([[5, 30], [10, 25], [12, 18], [20, 18], [22, 25], [27, 30]], tr); p.line(9, 29, 3, 31, dk); p.line(23, 29, 29, 31, dk); p.line(14, 20, 13, 29, dk);
    p.ell(15.5, 10, 13, 8.4, lf); p.ell(9, 8, 5, 4, lf2, { flat: true }); p.ell(22, 12, 5, 3.6, '#3a8a4a', { flat: true }); p.ell(15.5, 4, 6, 3, lf2);
    [[7, 12, '#ff7ad8'], [24, 7, '#ffe14d'], [12, 5, '#9fe8ff'], [20, 14, '#ff7ad8'], [5, 7, '#ffe14d']].forEach(function (c) { p.ell(c[0], c[1], 1, 1, c[2], { flat: true }); });
    eyes(p, 21, 2.6, '#ffe66b'); smile(p, 24, '#3a2410'); blush(p, 23, 4.2, '#d98a6a');
    p.ell(26.5, 22, 2.2, 1.6, '#ffffff'); p.put(28, 21, '#ffd23f');
    spark(p, 2, 2, '#ffe66b'); spark(p, 29, 2, '#cfeaff');
    return p;
  };

  /* ---------- decorazioni per rarità: più il pet è raro, più brilla ---------- */
  function finish(p, tier) {
    if (tier >= 6) { /* ombra luminosa a terra */ }
    var sp = [[3, 3], [28, 2], [2, 15], [29, 14], [4, 28], [27, 29]];
    var n = tier >= 9 ? 6 : tier >= 7 ? 4 : tier >= 5 ? 2 : tier >= 3 ? 1 : 0;
    for (var i = 0; i < n; i++) { var s = sp[i], c = tier >= 12 ? (i % 2 ? '#ff9be0' : '#7fe3ff') : tier >= 9 ? '#ffe66b' : tier >= 7 ? '#cfeaff' : '#ffffff'; if (!p.get(s[0], s[1])) spark(p, s[0], s[1], c); }
    if (tier >= 10) { /* gradi 10+: piccole stelle in più agli angoli */ [[1, 8], [30, 8], [1, 22], [30, 22]].forEach(function (s, i) { if (!p.get(s[0], s[1])) p.put(s[0], s[1], tier >= 13 ? '#ffe66b' : i % 2 ? '#cfeaff' : '#ff9be0'); }); }
    return p;
  }
  var CACHE = {};
  function uri(key, tier) {
    var ck = key + '|' + (tier || 0); if (CACHE[ck]) return CACHE[ck];
    var f = ART[key]; if (!f) return null;
    var p = finish(f(), tier || 0).outline(OUT), cv = p.canvas(4);
    return (CACHE[ck] = { url: cv.toDataURL('image/png'), w: p.w, h: p.h });
  }
  function sprite(key, o) {
    o = o || {}; var d = uri(key, o.tier || 0); if (!d) return '';
    var size = o.size || 96;
    return '<img class="pet-sprite ' + (o.cls || '') + '" alt="' + (o.alt || '').replace(/"/g, '') + '" draggable="false" style="width:' + size + 'px;height:' + size + 'px;image-rendering:pixelated" src="' + d.url + '">';
  }
  g.PetArt = { sprite: sprite, uri: uri, keys: Object.keys(ART), ART: ART };
})(window);
