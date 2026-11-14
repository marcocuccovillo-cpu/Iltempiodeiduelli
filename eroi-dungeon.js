/* La guerra degli Eroi — Dungeon: grafica.
   1) nuovi sprite pixel art (si aggiungono a quelli della Torre, stesso stile);
   2) DungeonArt: per ognuno dei 100 dungeon sceglie ambiente (14 ambienti, con piccole variazioni per dungeon),
      nemici delle stanze e boss partendo da nome ed emoji che arrivano dal database; disegna i banner delle schede;
   3) DungeonScena: la spedizione animata. Il gruppo avanza stanza dopo stanza, combatte e affronta il boss.
      Usa il risultato che arriva dal server (stanze, round, danni, KO): non decide nulla.
   Tutto su <canvas>, nessuna immagine esterna. Richiede eroi-torre.js (TorreArt). */
(function (g) {
  'use strict';
  var TA = g.TorreArt; if (!TA || !TA.ART || !TA.Px) return;
  var ART = TA.ART, Px = TA.Px, OUT = '#160c2c', N = 24, F = { flat: true };

  /* ================= 1. nuovi sprite (24×24, i boss 40×40) ================= */
  ART.zombi = function () { var p = new Px(N, N), s = '#7fae6a', c = '#5b4a6e';
    p.rect(8, 12, 8, 7, c); p.rect(8, 19, 3, 4, '#3d3350'); p.rect(13, 19, 3, 4, '#3d3350'); p.rect(3, 12, 6, 3, s); p.rect(16, 13, 5, 3, s);
    p.ell(11.5, 7, 5, 4.6, s); p.rect(9, 6, 2, 2, '#f4ffd0', F); p.rect(13, 6, 2, 2, '#f4ffd0', F); p.px(10, 7, '#200'); p.px(13, 6, '#200'); p.rect(10, 10, 4, 1, '#2a3a22', F); p.px(8, 3, '#4a6a3a'); p.px(14, 2, '#4a6a3a'); p.px(15, 9, '#b0302a');
    return p.outline(OUT); };
  ART.mummia = function () { var p = new Px(N, N), b = '#e6dcc0', d = '#b8a888';
    p.rect(8, 11, 8, 8, b); p.rect(8, 19, 3, 4, b); p.rect(13, 19, 3, 4, b); p.rect(4, 11, 5, 3, b); p.rect(15, 12, 5, 3, b); p.ell(11.5, 6.5, 5, 4.8, b);
    for (var y = 4; y < 22; y += 3) p.line(7, y, 16, y + 1, d, 1); p.rect(8, 6, 7, 2, '#241a2e', F); p.px(10, 6, '#ffd23f'); p.px(13, 6, '#ffd23f'); p.line(16, 14, 19, 20, d, 1);
    return p.outline(OUT); };
  ART.fungo = function () { var p = new Px(N, N), c = '#d9534f';
    p.rect(8, 13, 8, 8, '#f0e2c4'); p.ell(11.5, 9, 10, 6.5, c); p.rect(2, 11, 20, 3, '#f0e2c4', F); p.ell(6, 7, 1.6, 1.4, '#fff', F); p.ell(13, 5, 2, 1.5, '#fff', F); p.ell(18, 8, 1.4, 1.2, '#fff', F);
    p.rect(9, 15, 2, 3, '#1e1420', F); p.rect(13, 15, 2, 3, '#1e1420', F); p.px(9, 15, '#fff'); p.px(13, 15, '#fff'); p.rect(11, 19, 2, 1, '#8a4a3a', F); p.rect(7, 21, 3, 2, '#d8c8a8'); p.rect(14, 21, 3, 2, '#d8c8a8');
    return p.outline(OUT); };
  ART.serpente = function () { var p = new Px(N, N), c = '#3fae7a', d = '#2a7a58';
    p.ell(12, 19, 9, 3.4, c); p.ell(10, 15, 6, 3, d); p.ell(13, 11.5, 4.5, 3, c); p.ell(11, 6.5, 5.5, 4.2, c); p.poly([[5, 4], [2, 9], [6, 9]], d); p.poly([[17, 4], [20, 9], [16, 9]], d);
    p.rect(8, 5, 2, 2, '#ffe66b', F); p.rect(12, 5, 2, 2, '#ffe66b', F); p.px(9, 5, '#200'); p.px(13, 5, '#200'); p.line(11, 10, 11, 13, '#e0394a', 1); p.px(10, 14, '#e0394a'); p.px(12, 14, '#e0394a'); p.px(6, 18, '#e8f5c8'); p.px(12, 20, '#e8f5c8'); p.px(17, 18, '#e8f5c8');
    return p.outline(OUT); };
  ART.teschio = function () { var p = new Px(N, N), b = '#efe9d6';
    p.ell(11.5, 10, 8, 7.5, b); p.rect(7, 15, 9, 5, b); p.ell(8, 10, 2.4, 2.6, '#1c1226', F); p.ell(15, 10, 2.4, 2.6, '#1c1226', F); p.px(8, 10, '#7cf0e0'); p.px(15, 10, '#7cf0e0'); p.poly([[11, 13], [12.5, 13], [11.8, 15.5]], '#1c1226', F);
    for (var x = 8; x < 16; x += 2) p.rect(x, 17, 1, 3, '#1c1226', F); p.poly([[3, 3], [1, 9], [5, 7]], '#7cf0e0', F); p.poly([[20, 3], [22, 9], [18, 7]], '#7cf0e0', F); p.px(11, 22, '#7cf0e0'); p.px(13, 23, '#7cf0e0');
    return p.outline(OUT); };
  ART.automa = function () { var p = new Px(N, N), m = '#8fa3b8', d = '#566a80';
    p.rect(7, 10, 10, 9, m); p.rect(8, 3, 8, 6, m); p.rect(11, 1, 2, 2, d); p.px(11.5, 0, '#ff6b5c'); p.rect(3, 11, 4, 6, d); p.rect(17, 11, 4, 6, d); p.rect(8, 19, 3, 4, d); p.rect(13, 19, 3, 4, d);
    p.rect(9, 5, 2, 2, '#ffd23f', F); p.rect(13, 5, 2, 2, '#ffd23f', F); p.rect(10, 8, 4, 1, '#263238', F); p.ell(11.5, 14, 2.4, 2.4, '#7cf0e0', F); p.px(11, 14, '#fff'); p.px(8, 11, '#263238'); p.px(15, 11, '#263238'); p.px(8, 17, '#263238'); p.px(15, 17, '#263238');
    return p.outline(OUT); };
  ART.ninja = function () { var p = new Px(N, N), c = '#2b2d42', r = '#d7263d';
    p.rect(8, 11, 8, 7, c); p.rect(8, 18, 3, 5, c); p.rect(13, 18, 3, 5, c); p.rect(4, 11, 5, 3, c); p.rect(15, 11, 5, 3, c); p.ell(11.5, 6.5, 5, 4.6, c);
    p.rect(8, 5, 8, 2, '#f1c9a5', F); p.px(10, 6, '#111'); p.px(13, 6, '#111'); p.rect(7, 3, 10, 1, r, F); p.line(17, 3, 21, 1, r, 1); p.line(17, 4, 21, 5, r, 1); p.rect(8, 14, 8, 1, r, F); p.line(19, 6, 22, 18, '#cfd8dc', 1); p.rect(19, 12, 2, 1, '#8d6e63', F);
    return p.outline(OUT); };
  ART.carta = function () { var p = new Px(N, N), b = '#f4efe0';
    p.rect(6, 2, 13, 18, b); p.rect(8, 4, 9, 14, '#7b3fa0'); p.poly([[12.5, 6], [16, 11], [12.5, 16], [9, 11]], '#ffd23f'); p.px(12, 11, '#fff'); p.rect(10, 9, 2, 2, '#1c1226', F); p.rect(13, 9, 2, 2, '#1c1226', F);
    p.rect(3, 9, 3, 2, b); p.rect(19, 9, 3, 2, b); p.rect(8, 20, 2, 3, b); p.rect(15, 20, 2, 3, b);
    return p.outline(OUT); };
  ART.fiamma = function () { var p = new Px(N, N);
    p.poly([[12, 0], [19, 9], [21, 16], [16, 22], [8, 22], [3, 16], [6, 9], [8, 12]], '#ff6b2c'); p.poly([[12, 6], [16, 13], [17, 18], [14, 21], [10, 21], [7, 17], [9, 12]], '#ffb02e', F); p.poly([[12, 12], [14.5, 17], [13, 20], [11, 20], [9.5, 17]], '#fff3a0', F);
    p.rect(9, 14, 2, 2, '#3a1206', F); p.rect(13, 14, 2, 2, '#3a1206', F); p.px(4, 6, '#ffb02e'); p.px(20, 4, '#ffb02e'); p.px(2, 12, '#ff6b2c');
    return p.outline(OUT); };
  ART.cristallo = function () { var p = new Px(N, N), c = '#7fd6ff';
    p.poly([[12, 0], [18, 8], [16, 21], [8, 21], [6, 8]], c); p.poly([[5, 9], [8, 12], [7, 21], [2, 21], [2, 14]], '#5bb0e8'); p.poly([[19, 10], [22, 14], [22, 21], [17, 21], [16, 13]], '#5bb0e8'); p.line(12, 1, 12, 20, '#e8f8ff', 1); p.line(8, 8, 12, 12, '#c8eeff', 1);
    p.rect(9, 11, 2, 2, '#123a5a', F); p.rect(13, 11, 2, 2, '#123a5a', F); p.px(9, 11, '#fff'); p.px(13, 11, '#fff'); p.rect(10, 15, 4, 1, '#123a5a', F);
    return p.outline(OUT); };
  ART.maschera = function () { var p = new Px(N, N), b = '#f6f1e6';
    p.ell(11.5, 10, 7.5, 9, b); p.rect(4, 2, 8, 9, '#c8344a', F); p.ell(11.5, 10, 7.5, 9, b, { flat: false }); p.poly([[4, 6], [11.5, 1], [11.5, 19], [6, 16]], '#c8344a');
    p.poly([[6, 8], [10, 7], [9, 11], [6, 10]], '#1c1226', F); p.poly([[13, 7], [17, 8], [17, 10], [14, 11]], '#1c1226', F); p.px(8, 9, '#ffd23f'); p.px(15, 9, '#ffd23f'); p.poly([[8, 14], [15, 14], [13, 17], [10, 17]], '#1c1226', F); p.rect(10, 14, 3, 1, '#fff', F);
    p.poly([[3, 2], [0, 0], [4, 5]], '#ffd23f', F); p.poly([[20, 2], [23, 0], [19, 5]], '#ffd23f', F); p.px(0, 0, '#fff'); p.px(23, 0, '#fff'); p.line(11, 20, 9, 23, '#c8344a', 1); p.line(12, 20, 14, 23, '#ffd23f', 1);
    return p.outline(OUT); };
  ART.libro = function () { var p = new Px(N, N), c = '#6a3fa0';
    p.poly([[1, 6], [11, 9], [11, 21], [1, 18]], c); p.poly([[22, 6], [12, 9], [12, 21], [22, 18]], c); p.poly([[3, 7], [11, 10], [11, 19], [3, 16]], '#f4efe0', F); p.poly([[20, 7], [12, 10], [12, 19], [20, 16]], '#f4efe0', F);
    p.rect(5, 11, 3, 3, '#1c1226', F); p.rect(15, 11, 3, 3, '#1c1226', F); p.px(6, 12, '#ff5c7a'); p.px(16, 12, '#ff5c7a'); for (var x = 5; x < 19; x += 2) if (x !== 11) p.poly([[x, 16.5], [x + 1.6, 16.5], [x + .8, 18.6]], '#fff', F);
    p.px(4, 2, '#ffd23f'); p.px(18, 1, '#ffd23f'); p.px(11, 3, '#c9a7ff'); p.line(11, 9, 11, 21, '#3a2060', 1);
    return p.outline(OUT); };
  ART.medusa = function () { var p = new Px(N, N), c = '#c58bff';
    p.ell(11.5, 8, 9, 6.5, c); p.rect(3, 9, 18, 3, '#a56be0'); p.ell(8, 5, 2.4, 1.4, '#f0dcff', F);
    for (var i = 0; i < 5; i++) { var x = 4 + i * 4; p.line(x, 12, x + (i % 2 ? 1 : -1), 17, '#a56be0', 1); p.line(x + (i % 2 ? 1 : -1), 17, x, 22, c, 1); }
    p.rect(8, 8, 2, 2, '#2a1048', F); p.rect(13, 8, 2, 2, '#2a1048', F); p.px(8, 8, '#fff'); p.px(13, 8, '#fff'); p.px(2, 3, '#7cf0e0'); p.px(21, 5, '#7cf0e0');
    return p.outline(OUT); };
  ART.pianta = function () { var p = new Px(N, N), gC = '#3f9a4a';
    p.line(11, 14, 11, 22, '#2a6a34', 2); p.poly([[11, 18], [3, 15], [5, 20]], gC); p.poly([[12, 19], [20, 16], [18, 21]], gC); p.ell(11.5, 8, 8, 7, '#d6336c'); p.poly([[4, 8], [19, 8], [15, 13], [8, 13]], '#3a0a1e', F);
    for (var x = 5; x < 19; x += 3) { p.poly([[x, 8], [x + 2, 8], [x + 1, 10.4]], '#fff', F); p.poly([[x + 1, 13], [x + 3, 13], [x + 2, 10.8]], '#fff', F); }
    p.px(7, 4, '#ffb3cf'); p.px(14, 3, '#ffb3cf'); p.px(17, 5, '#ffb3cf'); p.rect(8, 22, 7, 1, '#6a4a2a', F);
    return p.outline(OUT); };
  ART.scorpione = function () { var p = new Px(N, N), c = '#c0762e', d = '#8a4f1c';
    p.ell(11.5, 17, 7, 4, c); p.ell(11.5, 13, 4, 3, c); p.line(17, 15, 21, 10, d, 2); p.line(21, 10, 19, 4, d, 2); p.line(19, 4, 15, 3, d, 2); p.poly([[15, 1], [12, 3], [15, 5]], '#e0394a', F);
    p.line(6, 13, 2, 9, d, 2); p.ell(2.5, 7, 2.2, 2.2, c); p.line(8, 12, 7, 7, d, 2); p.ell(7, 5.5, 2, 2, c);
    for (var i = 0; i < 3; i++) { p.line(6 + i * 2, 20, 4 + i * 2, 23, d, 1); p.line(14 + i * 2, 20, 16 + i * 2, 23, d, 1); } p.px(10, 12, '#200'); p.px(13, 12, '#200');
    return p.outline(OUT); };
  ART.orologio = function () { var p = new Px(N, N), o = '#d9a441';
    p.ell(11.5, 11, 9, 9, o); p.ell(11.5, 11, 7, 7, '#f6f1e6', F); p.line(11.5, 11, 11.5, 6, '#1c1226', 1); p.line(11.5, 11, 15, 12, '#c8344a', 1); p.px(11, 4, '#1c1226'); p.px(18, 11, '#1c1226'); p.px(5, 11, '#1c1226'); p.px(11, 17, '#1c1226');
    p.rect(8, 9, 2, 2, '#1c1226', F); p.rect(13, 8, 2, 2, '#1c1226', F); p.rect(10, 14, 4, 1, '#1c1226', F); p.rect(10, 0, 4, 2, o); p.rect(7, 20, 3, 3, '#8a6420'); p.rect(14, 20, 3, 3, '#8a6420'); p.rect(1, 10, 2, 3, '#8a6420'); p.rect(21, 10, 2, 3, '#8a6420');
    return p.outline(OUT); };
  ART.lich = function () { var p = new Px(40, 40), r = '#3a1d5c', b = '#efe9d6', gC = '#7cf0e0';
    p.poly([[8, 38], [12, 16], [28, 16], [32, 38]], r); p.poly([[14, 38], [16, 20], [24, 20], [26, 38]], '#22103a'); p.ell(19.5, 11, 7, 6.5, b); p.rect(15, 15, 9, 4, b);
    p.ell(16.5, 11, 2.2, 2.4, '#12081e', F); p.ell(22.5, 11, 2.2, 2.4, '#12081e', F); p.px(16, 11, gC); p.px(22, 11, gC); for (var x = 16; x < 24; x += 2) p.rect(x, 16, 1, 3, '#12081e', F);
    p.poly([[13, 5], [13, 0], [16, 3], [19.5, -1], [23, 3], [26, 0], [26, 5]], '#ffd23f'); p.px(19, 2, '#e0394a'); p.px(14, 3, '#7cf0e0'); p.px(25, 3, '#7cf0e0');
    p.rect(4, 18, 9, 4, r); p.rect(27, 18, 9, 4, r); p.rect(2, 20, 3, 3, b); p.rect(35, 18, 3, 3, b); p.line(36, 4, 36, 38, '#8a6420', 2); p.ell(36, 4, 3, 3, gC); p.px(35, 3, '#fff'); p.poly([[10, 38], [6, 39], [34, 39], [30, 38]], '#22103a', F);
    return p.outline(OUT); };
  ART.colosso = function () { var p = new Px(40, 40), m = '#8fa3b8', d = '#566a80', gC = '#ffb02e';
    p.rect(11, 12, 18, 16, m); p.rect(14, 3, 12, 9, m); p.rect(2, 12, 8, 14, d); p.rect(30, 12, 8, 14, d); p.rect(1, 26, 10, 6, m); p.rect(29, 26, 10, 6, m); p.rect(12, 28, 6, 11, d); p.rect(22, 28, 6, 11, d); p.rect(10, 37, 9, 3, m); p.rect(21, 37, 9, 3, m);
    p.rect(16, 6, 8, 3, '#1c2630', F); p.rect(17, 7, 2, 1, gC, F); p.rect(21, 7, 2, 1, gC, F); p.ell(19.5, 19, 4.5, 4.5, '#1c2630', F); p.ell(19.5, 19, 3, 3, gC, F); p.px(18, 18, '#fff');
    p.rect(19, 0, 2, 3, d); p.px(19, 0, '#ff6b5c'); for (var i = 0; i < 4; i++) { p.px(12 + i * 5, 13, '#263238'); p.px(12 + i * 5, 26, '#263238'); } p.line(4, 14, 4, 24, '#3a4a5a', 1); p.line(35, 14, 35, 24, '#3a4a5a', 1);
    return p.outline(OUT); };

  /* ================= 2. ambienti, nemici, banner ================= */
  function h2r(h) { h = h.replace('#', ''); return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]; }
  function rgba(h, a) { var c = h2r(h); return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }
  function shade(h, f) { var c = h2r(h); return 'rgb(' + c.map(function (v) { return Math.round(f < 0 ? v * (1 + f) : v + (255 - v) * f); }).join(',') + ')'; }
  function hue(hex, deg) { var c = h2r(hex), r = c[0] / 255, gg = c[1] / 255, b = c[2] / 255, mx = Math.max(r, gg, b), mn = Math.min(r, gg, b), l = (mx + mn) / 2, s = 0, h = 0, d = mx - mn;
    if (d) { s = l > .5 ? d / (2 - mx - mn) : d / (mx + mn); h = mx === r ? ((gg - b) / d + (gg < b ? 6 : 0)) : mx === gg ? (b - r) / d + 2 : (r - gg) / d + 4; h /= 6; }
    h = ((h + deg / 360) % 1 + 1) % 1; var q = l < .5 ? l * (1 + s) : l + s - l * s, pp = 2 * l - q, f = function (t) { t = (t % 1 + 1) % 1; return t < 1 / 6 ? pp + (q - pp) * 6 * t : t < .5 ? q : t < 2 / 3 ? pp + (q - pp) * (2 / 3 - t) * 6 : pp; };
    var o = s ? [f(h + 1 / 3), f(h), f(h - 1 / 3)] : [l, l, l]; return '#' + o.map(function (v) { return ('0' + Math.round(v * 255).toString(16)).slice(-2); }).join(''); }
  function rnd(s) { var x = (s * 2654435761) >>> 0 || 1; return function () { x ^= x << 13; x >>>= 0; x ^= x >> 17; x ^= x << 5; x >>>= 0; return x / 4294967296; }; }
  function fmt(n) { return Number(n || 0).toLocaleString('it-IT'); }

  /* ambiente: cielo (alto, basso), sagome lontane, sagome vicine, terreno, luce, tipo di scenografia, particelle */
  var TH = {
    forest: { n: 'Foresta', sky: ['#0f2a1e', '#2f6a48'], far: '#1c4a34', near: '#12331f', ground: '#3a5a2c', glow: '#b8f07a', decor: 'trees', part: 'leaf' },
    swamp: { n: 'Palude', sky: ['#141f1a', '#3a4f3a'], far: '#26382c', near: '#16241c', ground: '#34402a', glow: '#9be15d', decor: 'graves', part: 'fog' },
    cave: { n: 'Caverna', sky: ['#120f1c', '#2a2438'], far: '#231d30', near: '#17131f', ground: '#3d3548', glow: '#7fd6ff', decor: 'stalact', part: 'dust' },
    volcano: { n: 'Vulcano', sky: ['#1e0806', '#7a2410'], far: '#4a160c', near: '#2a0c08', ground: '#3a1a14', glow: '#ff7a2c', decor: 'lava', part: 'ember' },
    ice: { n: 'Ghiacci', sky: ['#0e2238', '#5a9ac8'], far: '#8fc4e4', near: '#4a82ac', ground: '#cfe8f6', glow: '#e8f8ff', decor: 'ice', part: 'snow' },
    desert: { n: 'Deserto', sky: ['#3a1e3a', '#e89a4a'], far: '#b8743a', near: '#8a5228', ground: '#d8a85a', glow: '#ffe08a', decor: 'dunes', part: 'dust' },
    sea: { n: 'Mare', sky: ['#0a1e3a', '#2a6a9a'], far: '#1e4a7a', near: '#143460', ground: '#6a5a44', glow: '#7cf0e0', decor: 'waves', part: 'bubble' },
    storm: { n: 'Tempesta', sky: ['#12141f', '#3a4058'], far: '#2a2e42', near: '#1a1c2a', ground: '#3a3a4a', glow: '#ffe66b', decor: 'clouds', part: 'rain' },
    cosmos: { n: 'Oltre il cielo', sky: ['#070418', '#2a1458'], far: '#3a1e6a', near: '#1a0e38', ground: '#2a2048', glow: '#c9a7ff', decor: 'stars', part: 'star' },
    castle: { n: 'Castello', sky: ['#14152a', '#3a3c68'], far: '#2a2c4a', near: '#1c1d34', ground: '#4a4a5c', glow: '#ffb86b', decor: 'towers', part: 'dust' },
    temple: { n: 'Tempio', sky: ['#2a1410', '#8a4a2a'], far: '#5a3020', near: '#3a1e16', ground: '#6a4a3a', glow: '#ffd23f', decor: 'pillars', part: 'petal' },
    machine: { n: 'Officina', sky: ['#14181c', '#3a4650'], far: '#2a343c', near: '#1a2228', ground: '#4a4238', glow: '#ffb02e', decor: 'gears', part: 'ember' },
    arcane: { n: 'Biblioteca', sky: ['#160e2a', '#3a2460'], far: '#2a1a48', near: '#1c1232', ground: '#4a3a34', glow: '#c9a7ff', decor: 'books', part: 'star' },
    carnival: { n: 'Carnevale', sky: ['#1e0e2a', '#6a2a5a'], far: '#4a1e48', near: '#2a1230', ground: '#4a2a3a', glow: '#ff7ac8', decor: 'tents', part: 'petal' }
  };
  var EMO = { forest: '🌲🌺🧚🏞🐛🦅', swamp: '🧟🌫💧🪦⚰🥀', cave: '⛏🪨🕳🗿🔨🔺', volcano: '🌋🔥☄🐉🐲😈', ice: '❄🧊🏔', desert: '🏜🏺☀🦖', sea: '🌊🏝⛵🏴🛶', storm: '⚡⛈🌪🌀',
    cosmos: '🌌🌑🌘🌙🔭✨👁💭💤', castle: '🏰🏯⚔👑♟🏟', temple: '🏛⛩⛪🥋🥷🏮', machine: '⚙🤖🚂🕰⏰⏳🧬⚗', arcane: '📖📚🧙🗝🪞', carnival: '🃏🎭🎰🧸🏪' };
  var ORDER = Object.keys(TH);
  function strip(e) { return String(e || '').replace(/[️‍]/g, ''); }
  function theme(d) {
    var e = Array.from(strip(d && d.emoji))[0] || '', id = null, no = (d && d.no) || 1;
    if (e) for (var k in EMO) if (EMO[k].indexOf(e) >= 0) { id = k; break; }
    if (!id) id = ORDER[no % ORDER.length];
    var b = TH[id], sh = ((no * 37) % 5 - 2) * 9, t = { id: id, name: b.n, decor: b.decor, part: b.part, seed: no * 7 + 3 };       // piccola variazione di tinta per dungeon
    t.sky = [hue(b.sky[0], sh), hue(b.sky[1], sh)]; t.far = hue(b.far, sh); t.near = hue(b.near, sh); t.ground = hue(b.ground, sh * .5); t.glow = b.glow;
    return t;
  }
  /* nemici: prima il nome (italiano), poi l'emoji, poi un ripiego stabile */
  var WORDS = [['zomb|non.?mort|cadaver', 'zombi'], ['mumm|bend|farao', 'mummia'], ['schelet|ossa|teschi|cranio', 'scheletro'], ['kuriboh|cuccioli|fung|spor', 'fungo'], ['pipistrell|vampir', 'pipistrello'],
    ['lup|bestia|belv|mastin|felin|tigr|leon|gatt', 'lupo'], ['ragn|tessit|aracn', 'ragno'], ['golem|statu|gargo|pietra|roccia|idol', 'golem'], ['goblin|ladr|predon|bandit|pirat|ciurm|minator|contrabband', 'goblin'],
    ['spettr|fantasm|ombr|anim[ae] |spirit|eco |incub|sogn', 'spettro'], ['elemental|tempest|fulmin|tuon|vento|nub', 'elementale'], ['melm|slime|gelatin|fang|blob', 'melma'], ['serp|viper|cobra|naga|basilisc', 'serpente'],
    ['autom|robot|ingranagg|macchin|meccan|drone|locomot', 'automa'], ['ninja|assassin|shinobi|samurai|ronin|monac', 'ninja'], ['cart[ae]|mazz|duellant|jolly|tarocc', 'carta'], ['fiamm|fuoc|lava|magma|brac|cener|incendi', 'fiamma'],
    ['cristall|ghiacc|gel[oi]|quarz|prism|gemm|diamant|brina', 'cristallo'], ['mascher|giullar|clown|pagliacc|burattin|bambol|marionett|pupazz|giocattol|mimo', 'maschera'], ['libr|tomo|pergamen|grimori|scrib|inchiostr|bibliotec', 'libro'],
    ['medus|polp|tentac|abiss|sirena|pesc|squal|coral', 'medusa'], ['piant|rov[io]|radic|fior|liana|ros[ae]|spin', 'pianta'], ['scorpion|scarab|insett|larv|verm|bruc|formic|sciam', 'scorpione'], ['orolog|tempo|clessidr|lancett|ore ', 'orologio'],
    ['cavalier|guardi|soldat|sentinell|templar|campion|general|gladiator|paladin|legionar', 'cavaliere'], ['streg|mag[oh]|sciaman|sacerdot|cultist|necromant|alchim|oracol|evocator', 'strega'], ['drag|vivern|dinosaur|rettil|tirann', 'drago'],
    ['demon|diavol|infern|succub', 'demone'], ['occhi|veggent|sguard', 'occhio'], ['angel|arcont|celest|custod|serafin', 'arconte'], ['titan|gigant', 'titano'], ['coloss|mech|fortezza semovente', 'colosso'], ['kraken|leviatan', 'kraken'], ['idra', 'idra'],
    ['fenic|uccell|aquil|corv|arpi|grifon|falc', 'fenice'], ['lich|re zombi|re degli|signore dei morti', 'lich'], ['\\bre\\b|regina|sovran|imperat|princip|duca|conte|signor', 'sovrano']].map(function (w) { return [new RegExp(w[0], 'i'), w[1]]; });
  var EM2 = { '🧟': 'zombi', '💀': 'scheletro', '☠': 'teschio', '👻': 'spettro', '🦇': 'pipistrello', '🕸': 'ragno', '🕷': 'ragno', '🐍': 'serpente', '🤖': 'automa', '⚙': 'automa', '🛠': 'automa', '⚒': 'automa', '🥷': 'ninja', '🃏': 'carta', '🎴': 'carta', '🎫': 'carta',
    '🔥': 'fiamma', '❄': 'cristallo', '💎': 'cristallo', '🥶': 'cristallo', '🎭': 'maschera', '🤡': 'maschera', '🪆': 'maschera', '🎪': 'maschera', '📜': 'libro', '📖': 'libro', '🐙': 'medusa', '🦑': 'kraken', '🌹': 'pianta', '🥀': 'pianta', '🦋': 'pianta',
    '⌛': 'orologio', '⏳': 'orologio', '🐉': 'drago', '🐲': 'drago', '🦖': 'drago', '👿': 'demone', '😈': 'demone', '👁': 'occhio', '🔮': 'occhio', '😇': 'arconte', '🏛': 'arconte', '🤍': 'arconte', '🗿': 'golem', '🛡': 'cavaliere', '🗡': 'cavaliere', '⚔': 'cavaliere', '🏆': 'cavaliere',
    '👑': 'sovrano', '🧙': 'strega', '🧪': 'strega', '🧞': 'strega', '⚡': 'elementale', '🌩': 'elementale', '🌬': 'elementale', '☁': 'elementale', '🐾': 'fungo', '🐱': 'lupo', '🌑': 'spettro', '🌒': 'spettro', '🖤': 'spettro', '⚫': 'occhio', '🌌': 'arconte', '🪐': 'titano', '🫀': 'demone', '🔱': 'kraken', '⚓': 'kraken', '🚣': 'medusa' };
  var MINI = ['melma', 'pipistrello', 'scheletro', 'goblin', 'lupo', 'spettro', 'ragno', 'elementale', 'zombi', 'teschio', 'serpente', 'fiamma', 'cristallo', 'scorpione', 'fungo', 'maschera'];
  var BOSS = ['golem', 'drago', 'strega', 'cavaliere', 'idra', 'fenice', 'sovrano', 'occhio', 'titano', 'kraken', 'demone', 'arconte', 'lich', 'colosso'];
  var BIG = { golem: 1, drago: 1, strega: 1, cavaliere: 1, idra: 1, fenice: 1, sovrano: 1, occhio: 1, titano: 1, kraken: 1, demone: 1, arconte: 1, lich: 1, colosso: 1 };
  function foe(name, emoji, boss, seed) {
    var k = null, i; name = String(name || '');
    for (i = 0; i < WORDS.length && !k; i++) if (WORDS[i][0].test(name)) k = WORDS[i][1];
    if (!k) k = EM2[Array.from(strip(emoji))[0] || ''];
    if (!k || !ART[k]) { var L = boss ? BOSS : MINI, h = seed || 0; for (i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0; k = L[h % L.length]; }
    if (boss && !BIG[k]) { var e2 = EM2[Array.from(strip(emoji))[0] || ''], hh = (seed || 0) + name.length;             // i boss «fantasma» o «non morto» diventano veri boss
      if (e2 && BIG[e2]) k = e2; else if (k === 'spettro') k = ['lich', 'occhio', 'demone', 'arconte', 'strega', 'spettro'][hh % 6]; else if (k === 'scheletro' || k === 'zombi' || k === 'teschio') k = 'lich'; }
    return k;
  }
  var HUES = [0, 0, 35, -40, 150, 200, 0, 280];
  function tintOf(key, boss, seed) { var h = boss && BIG[key] ? HUES[(seed || 0) % HUES.length] : 0; return h ? 'hue-rotate(' + h + 'deg)' : null; }
  function fl(a, b) { return a && b ? a + ' ' + b : a || b || null; }
  var IMG = {};
  function img(key, look) { var d = TA.uri(key, look); if (!d) return null; var ck = d.url; if (!IMG[ck]) { var i = new Image(); i.src = d.url; IMG[ck] = { i: i, w: d.w, h: d.h }; } return IMG[ck]; }

  /* scenografia: disegna l'ambiente su un contesto (w × h), con scorrimento sx e tempo t */
  function scenery(c, T, w, h, gy, sx, t, still) {
    var gr = c.createLinearGradient(0, 0, 0, gy); gr.addColorStop(0, T.sky[0]); gr.addColorStop(1, T.sky[1]); c.fillStyle = gr; c.fillRect(0, 0, w, h);
    var R = rnd(T.seed), i, x, k, D = T.decor, per = 900;
    function wrap(v, par, pad) { return ((v - sx * par) % (per + pad) + per + pad) % (per + pad) - pad; }
    if (D === 'stars' || D === 'books' || D === 'towers' || D === 'tents') for (i = 0; i < 40; i++) { x = wrap(R() * per, .05, 0); c.fillStyle = 'rgba(255,255,255,' + (still ? .7 : .35 + .5 * Math.abs(Math.sin(t * 1.4 + i))) + ')'; c.fillRect(x % w, R() * gy * .7, 1.5, 1.5); }
    if (D === 'stars') { c.fillStyle = rgba(T.glow, .25); c.beginPath(); c.arc(wrap(600, .05, 80) % w, gy * .28, 34, 0, 6.3); c.fill(); c.fillStyle = rgba(T.glow, .9); c.beginPath(); c.arc(wrap(600, .05, 80) % w, gy * .28, 20, 0, 6.3); c.fill(); }
    if (D === 'dunes' || D === 'lava') { c.fillStyle = rgba(D === 'lava' ? '#ff7a2c' : '#fff0b0', .9); c.beginPath(); c.arc(w * .76, gy * .34, 22, 0, 6.3); c.fill(); }
    /* piano lontano */
    for (i = 0; i < 9; i++) { x = wrap(i * 110 + R() * 60, .25, 140); k = .55 + R() * .6; c.fillStyle = T.far;
      if (D === 'trees') { c.beginPath(); c.moveTo(x, gy); c.lineTo(x + 34 * k, gy - 150 * k); c.lineTo(x + 68 * k, gy); c.fill(); }
      else if (D === 'graves' || D === 'clouds') { c.beginPath(); c.ellipse(x + 50, D === 'clouds' ? gy * (.2 + R() * .3) : gy - 10, 70 * k, 26 * k, 0, 0, 6.3); c.fill(); }
      else if (D === 'stalact') { c.beginPath(); c.moveTo(x, 0); c.lineTo(x + 22 * k, 120 * k); c.lineTo(x + 44 * k, 0); c.fill(); c.beginPath(); c.moveTo(x + 60, gy); c.lineTo(x + 76, gy - 70 * k); c.lineTo(x + 92, gy); c.fill(); }
      else if (D === 'lava' || D === 'ice' || D === 'dunes') { c.beginPath(); c.moveTo(x - 40, gy); c.lineTo(x + 50 * k, gy - (D === 'dunes' ? 60 : 170) * k); c.lineTo(x + 150 * k, gy); c.fill(); if (D === 'ice') { c.fillStyle = '#fff'; c.beginPath(); c.moveTo(x + 50 * k, gy - 170 * k); c.lineTo(x + 34 * k, gy - 130 * k); c.lineTo(x + 70 * k, gy - 132 * k); c.fill(); } }
      else if (D === 'waves') { c.beginPath(); c.ellipse(x + 40, gy - 4, 90 * k, 34 * k, 0, Math.PI, 0); c.fill(); }
      else if (D === 'towers') { c.fillRect(x, gy - 150 * k, 34, 150 * k); c.fillRect(x - 5, gy - 150 * k - 10, 44, 12); c.fillStyle = rgba(T.glow, .8); c.fillRect(x + 13, gy - 120 * k, 7, 12); }
      else if (D === 'pillars') { c.fillRect(x, gy - 170, 22, 170); c.fillRect(x - 6, gy - 176, 34, 10); c.fillRect(x - 6, gy - 12, 34, 12); }
      else if (D === 'gears') { var gx = x + 40, gyy = gy * (.25 + R() * .45), rr = 26 * k + 10, a0 = still ? 0 : t * (i % 2 ? .5 : -.5); c.save(); c.translate(gx, gyy); c.rotate(a0); for (var q = 0; q < 8; q++) { c.rotate(Math.PI / 4); c.fillRect(-5, -rr - 7, 10, 10); } c.beginPath(); c.arc(0, 0, rr, 0, 6.3); c.fill(); c.fillStyle = T.sky[0]; c.beginPath(); c.arc(0, 0, rr * .35, 0, 6.3); c.fill(); c.restore(); }
      else if (D === 'books') { c.fillRect(x, gy - 190, 70, 190); for (var b = 0; b < 5; b++) { c.fillStyle = shade(T.far, .12); c.fillRect(x + 4, gy - 182 + b * 36, 62, 3); for (var bb = 0; bb < 7; bb++) { c.fillStyle = ['#8a3a4a', '#3a5a8a', '#6a8a3a', '#8a6a2a'][(i + b + bb) % 4]; c.fillRect(x + 6 + bb * 8.5, gy - 208 + b * 36 + (bb % 3) * 3, 6, 26 - (bb % 3) * 3); } c.fillStyle = T.far; } }
      else if (D === 'tents') { c.beginPath(); c.moveTo(x, gy); c.lineTo(x + 50, gy - 120 * k); c.lineTo(x + 100, gy); c.fill(); c.fillStyle = rgba(T.glow, .5); c.beginPath(); c.moveTo(x + 34, gy); c.lineTo(x + 50, gy - 120 * k); c.lineTo(x + 66, gy); c.fill(); }
      else if (D === 'stars') { c.beginPath(); c.moveTo(x, gy); c.lineTo(x + 20, gy - 60 * k); c.lineTo(x + 50, gy - 20); c.lineTo(x + 70, gy - 90 * k); c.lineTo(x + 100, gy); c.fill(); }
    }
    if (D === 'lava') { c.fillStyle = rgba('#ff7a2c', still ? .5 : .35 + .2 * Math.sin(t * 2)); c.fillRect(0, gy - 6, w, 6); }
    /* piano vicino */
    for (i = 0; i < 7; i++) { x = wrap(i * 150 + R() * 80, .6, 120); k = .7 + R() * .5; c.fillStyle = T.near;
      if (D === 'trees') { c.fillRect(x + 20, gy - 70 * k, 10, 70 * k); c.beginPath(); c.arc(x + 25, gy - 80 * k, 34 * k, 0, 6.3); c.fill(); }
      else if (D === 'graves') { c.fillRect(x, gy - 30 * k, 20, 30 * k); c.beginPath(); c.arc(x + 10, gy - 30 * k, 10, Math.PI, 0); c.fill(); }
      else if (D === 'pillars' || D === 'towers') { c.fillRect(x, gy - 60, 6, 60); c.fillStyle = rgba(T.glow, .25); c.beginPath(); c.arc(x + 3, gy - 66, 26, 0, 6.3); c.fill(); c.fillStyle = '#ff9a3a'; c.beginPath(); c.ellipse(x + 3, gy - 68, 4, 8, 0, 0, 6.3); c.fill(); }
      else if (D === 'waves') { c.beginPath(); c.ellipse(x + 30, gy, 44, 12 + (still ? 0 : 3 * Math.sin(t * 2 + i)), 0, Math.PI, 0); c.fill(); }
      else if (D === 'ice' || D === 'stalact' || D === 'stars') { c.fillStyle = rgba(T.glow, .55); c.beginPath(); c.moveTo(x, gy); c.lineTo(x + 9, gy - 44 * k); c.lineTo(x + 18, gy); c.fill(); c.beginPath(); c.moveTo(x + 14, gy); c.lineTo(x + 20, gy - 24 * k); c.lineTo(x + 28, gy); c.fill(); }
      else { c.beginPath(); c.ellipse(x + 30, gy, 40 * k, 14 * k, 0, Math.PI, 0); c.fill(); }
    }
    /* terreno */
    c.fillStyle = T.ground; c.fillRect(0, gy, w, h - gy); c.fillStyle = shade(T.ground, .25); c.fillRect(0, gy, w, 3); c.fillStyle = 'rgba(0,0,0,.28)';
    for (i = 0; i < 16; i++) { x = wrap(i * 60 + R() * 40, 1, 40); c.fillRect(x, gy + 8 + R() * (h - gy - 14), 14 + R() * 20, 3); }
  }
  function spr(c, S, x, y, hpx, dir, o) { if (!S || !S.i.complete || !S.i.naturalWidth) return; o = o || {}; var w = S.w / S.h * hpx; c.save(); c.translate(x, y); if (o.rot) c.rotate(o.rot); c.scale(dir, 1); c.globalAlpha = o.alpha == null ? 1 : o.alpha;
    if (o.filter && 'filter' in c) c.filter = o.filter; c.imageSmoothingEnabled = false; c.drawImage(S.i, -w / 2, -hpx, w, hpx); c.filter = 'none'; c.restore(); }
  function cast(d) { var rooms = (d && d.rooms) || [], out = rooms.map(function (r, i) { var k = foe(r.name, r.emoji, !!r.boss, (d.no || 1) * 13 + i); return { key: k, boss: !!r.boss, name: r.name, tint: tintOf(k, !!r.boss, d.no || 1) }; });
    if (!out.length || !out[out.length - 1].boss) { var bk = foe(d && d.boss_name, d && d.boss_emoji, true, (d && d.no) || 1); out.push({ key: bk, boss: true, name: (d && d.boss_name) || 'Boss', tint: tintOf(bk, true, (d && d.no) || 1) }); } return out; }
  /* banner della scheda: ambiente + boss + due nemici */
  function banner(cv, d, locked) {
    var c = cv.getContext('2d'), w = cv.width, h = cv.height, T = theme(d), C = cast(d), B = C[C.length - 1], gy = h * .8, tries = 0;
    var S = [img(B.key)].concat(C.slice(0, 2).filter(function (x) { return !x.boss; }).map(function (x) { return img(x.key); }));
    (function paint() {
      if (S.some(function (s) { return s && !s.i.complete; }) && tries++ < 40) return setTimeout(paint, 60);
      c.setTransform(1, 0, 0, 1, 0, 0); c.save(); c.scale(h / 200, h / 200); scenery(c, T, w * 200 / h, 200, 160, (d.no || 1) * 53, 0, true); c.restore();
      var f = locked ? 'brightness(0)' : null, fb = locked ? f : B.tint, bh = h * (BIG[B.key] ? .92 : .8);
      if (S[2]) spr(c, S[2], w * .5, gy + 4, h * .42, -1, { filter: f, alpha: locked ? .75 : 1 }); if (S[1]) spr(c, S[1], w * .62, gy + 6, h * .46, -1, { filter: f, alpha: locked ? .75 : 1 });
      c.fillStyle = rgba('#ff3c50', locked ? 0 : .22); c.beginPath(); c.arc(w * .82, gy - bh * .45, bh * .55, 0, 6.3); c.fill();
      spr(c, S[0], w * .82, gy + 8, bh, -1, { filter: fb, alpha: locked ? .8 : 1 });
      var gl = c.createLinearGradient(0, 0, w * .7, 0); gl.addColorStop(0, 'rgba(6,4,14,.82)'); gl.addColorStop(1, 'rgba(6,4,14,0)'); c.fillStyle = gl; c.fillRect(0, 0, w, h);
      if (locked) { c.fillStyle = 'rgba(6,4,14,.45)'; c.fillRect(0, 0, w, h); }
    })();
  }
  g.DungeonArt = { theme: theme, foe: foe, cast: cast, banner: banner, themes: TH };

  /* ================= 3. la spedizione animata ================= */
  /* il palco: ambiente + gruppo. Lo usano sia la spedizione automatica (play) sia quella a scelte, dal vivo (live) */
  function stage(host, o) {
    var d = o.dungeon || {}, res = o.res || {}, T = theme(d), rooms = o.dots || [], reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    var cv = document.createElement('canvas'), c = cv.getContext('2d'); cv.className = 'dg-cv'; cv.setAttribute('aria-hidden', 'true'); host.appendChild(cv);
    var DPR = Math.min(2, g.devicePixelRatio || 1), W = 360, H = 520, GY = 400;
    function size() { if (!host || !host.isConnected) return; var r = host.getBoundingClientRect(); if (r.width < 10 || r.height < 10) return; W = Math.max(280, Math.round(r.width)); H = Math.max(240, Math.round(r.height)); GY = Math.round(H * (o.ground || .72)); cv.width = W * DPR; cv.height = H * DPR; cv.style.width = W + 'px'; cv.style.height = H + 'px'; }
    size(); addEventListener('resize', size);
    var ord = { tank: 0, dps: 1, support: 2 }, mem = (o.members || res.members || []).slice().sort(function (a, b) { return (ord[a.role] == null ? 1 : ord[a.role]) - (ord[b.role] == null ? 1 : ord[b.role]); }).slice(0, 4);
    var P = mem.map(function (m, i) { var hp = m.max_hp ? Math.max(0, Math.min(1, m.hp / m.max_hp)) : 1; return { id: m.user_id, n: String(m.nickname || '').slice(0, 10), S: img('eroe', (o.looks || {})[m.user_id] || {}), me: m.user_id === o.me, role: m.role, x: 0, down: o.members && hp <= 0 ? 1 : 0, hp: hp, lunge: 0, hit: 0 }; });
    var pet = o.pet && g.PetArt && g.PetArt.uri ? (function () { var u = g.PetArt.uri(o.pet.sprite, o.pet.tier || 0); if (!u) return null; var i = new Image(); i.src = u.url; return { i: i, w: u.w, h: u.h }; })() : null;
    var st = { sx: 0, walk: 0, room: -1, foeA: 0, foeHp: 1, foeHit: 0, foeLunge: 0, foeDead: 0, plaque: '', sub: '', banner: null, shake: 0, flash: 0, dark: 1, cap: null, tintc: null }, FX = [], tw = [], alive = true, skipping = reduce, cur = null;
    function tween(ms, f) { return new Promise(function (ok) { if (skipping || !alive) { f(1); return ok(); } tw.push({ t0: performance.now(), d: ms, f: f, ok: ok }); }); }
    function wait(ms) { return tween(ms, function () { }); }
    function fx(f) { f.t0 = performance.now(); f.d = f.d || 900; FX.push(f); }
    function burst(x, y, cols, n) { var p = [], r = rnd(Math.floor(performance.now())); for (var i = 0; i < n; i++) { var a = r() * 6.283, s = .3 + r() * .9; p.push([Math.cos(a) * s, Math.sin(a) * s - .5, cols[i % cols.length], 2 + r() * 3]); } fx({ k: 'part', x: x, y: y, p: p, d: 1000 }); }
    function px(i) { return W * .12 + (P.length - 1 - i) * Math.min(52, W * .11); }                 // il tank sta davanti
    var FX0 = function () { return W * (cur && cur.boss ? .72 : .66); };
    function pill(txt, x, y, col, bg, font) { c.font = font || '700 12px Cinzel, Georgia, serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; var w = Math.min(W - 16, c.measureText(txt).width + 22); c.fillStyle = bg || 'rgba(10,8,20,.82)'; c.strokeStyle = col; c.lineWidth = 1.5;
      c.beginPath(); if (c.roundRect) c.roundRect(x - w / 2, y - 12, w, 24, 8); else c.rect(x - w / 2, y - 12, w, 24); c.fill(); c.stroke(); c.fillStyle = '#ffe7a8'; c.fillText(txt, x, y + 1, W - 30); }
    function bar(x, y, w, v, col, hh) { hh = hh || 6; c.fillStyle = 'rgba(0,0,0,.65)'; c.fillRect(x - w / 2 - 2, y - 2, w + 4, hh + 4); c.fillStyle = '#3a1a1a'; c.fillRect(x - w / 2, y, w, hh); c.fillStyle = col; c.fillRect(x - w / 2, y, w * Math.max(0, Math.min(1, v)), hh); }
    function draw(ts) {
      var t = ts / 1000, i; c.setTransform(DPR, 0, 0, DPR, 0, 0);
      var shx = st.shake > 0 ? (Math.random() - .5) * st.shake : 0; c.save(); c.translate(shx, 0);
      var SK = Math.max(1, GY / 300); c.save(); c.scale(SK, SK); scenery(c, T, W / SK, H / SK, GY / SK, st.sx / SK, t, reduce); c.restore();     // scenografia ingrandita sugli schermi alti
      /* particelle d'ambiente */
      if (!reduce) { var R = rnd(T.seed + 9); for (i = 0; i < 22; i++) { var bx = R() * W, by = R() * GY, sp = .4 + R(), yy, xx = bx;
        if (T.part === 'ember' || T.part === 'bubble' || T.part === 'star') { yy = ((by - t * 26 * sp) % GY + GY) % GY; xx = bx + Math.sin(t + i) * 8; c.fillStyle = rgba(T.glow, .5 * sp); }
        else if (T.part === 'rain') { yy = (by + t * 420 * sp) % GY; xx = (bx - t * 60) % W; if (xx < 0) xx += W; c.fillStyle = 'rgba(200,220,255,.45)'; c.fillRect(xx, yy, 1.5, 10); continue; }
        else if (T.part === 'fog') { c.fillStyle = 'rgba(200,230,200,.05)'; c.beginPath(); c.ellipse((bx + t * 12 * sp) % (W + 160) - 80, GY - 20 - R() * 60, 90, 18, 0, 0, 6.3); c.fill(); continue; }
        else { yy = (by + t * 30 * sp) % GY; xx = bx + Math.sin(t * 1.5 + i) * 14; c.fillStyle = T.part === 'snow' ? 'rgba(255,255,255,.8)' : T.part === 'dust' ? rgba(T.glow, .22) : rgba(T.glow, .7); }
        c.fillRect(xx, yy, T.part === 'leaf' || T.part === 'petal' ? 4 : 2, 2); } }
      /* nemici della stanza */
      if (cur && st.foeA > 0) { var fxp = FX0() - st.foeLunge * 34 + st.foeHit * 6, bob = reduce ? 0 : Math.sin(t * 2.4) * 2, al = st.foeA * (1 - st.foeDead), flt = fl(cur.tint, st.foeHit > .5 ? 'brightness(2.2)' : null);
        if (cur.boss) { var bh = Math.min(GY * .46, W * .62, BIG[cur.key] ? 250 : 200); c.fillStyle = 'rgba(255,60,80,' + (.2 + .1 * Math.sin(t * 3)) * al + ')'; c.beginPath(); c.arc(fxp, GY - bh * .5, bh * .7, 0, 6.3); c.fill();
          c.fillStyle = 'rgba(0,0,0,.35)'; c.beginPath(); c.ellipse(fxp, GY + 3, bh * .34, 9, 0, 0, 6.3); c.fill(); spr(c, cur.S, fxp, GY + bob - st.foeDead * 12, bh, -1, { alpha: al, filter: flt }); }
        else for (i = 2; i >= 0; i--) { var mx = fxp + (i - 1) * W * .13 + (i === 1 ? -14 : 8), mh = Math.min(W * .3, BIG[cur.key] ? 120 : 100) * (i === 1 ? 1.08 : .92), mb = reduce ? 0 : Math.sin(t * 2.4 + i * 1.9) * 2;
          c.fillStyle = 'rgba(0,0,0,.35)'; c.beginPath(); c.ellipse(mx, GY + 3, mh * .3, 6, 0, 0, 6.3); c.fill(); spr(c, cur.S, mx, GY + mb - st.foeDead * 10, mh, -1, { alpha: al * (st.foeHp * 3 > 2 - i ? 1 : 0), filter: flt }); } }
      /* compagno e gruppo */
      var lead = P.filter(function (p) { return p.me; })[0];
      P.forEach(function (p, i) { var x = px(i) + p.lunge * 34 - p.hit * 7, wb = st.walk && !p.down ? Math.abs(Math.sin(t * 9 + i * 1.4)) * 5 : (reduce ? 0 : Math.abs(Math.sin(t * 2 + i)) * 1.2), hh = HH();
        if (pet && p === lead && pet.i.complete) spr(c, pet, x - 26, GY - wb * .6, hh * .46, 1, { alpha: p.down ? .5 : 1 });
        c.fillStyle = 'rgba(0,0,0,.35)'; c.beginPath(); c.ellipse(x, GY + 3, hh * .26, 6, 0, 0, 6.3); c.fill();
        spr(c, p.S, x + p.down * 14, GY - wb - p.down * 4, hh, 1, { rot: p.down * 1.45, alpha: 1 - p.down * .45, filter: p.hit > .5 ? 'brightness(2)' : null });
        if (!p.down || p.down < 1) { bar(x, GY - hh - 12, 34, p.hp, p.me ? '#4ade9b' : '#7fd6ff', 4); }
        c.font = (p.me ? '800' : '600') + ' 10px Inter, system-ui, sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.lineWidth = 3; c.strokeStyle = 'rgba(0,0,0,.8)'; c.strokeText(p.n, x, GY + 16 + (i % 2) * 12); c.fillStyle = p.me ? '#ffd36b' : '#e8e4f5'; c.fillText(p.n, x, GY + 16 + (i % 2) * 12); });
      /* effetti */
      for (i = FX.length - 1; i >= 0; i--) { var f = FX[i], k = (ts - f.t0) / f.d; if (k >= 1) { FX.splice(i, 1); continue; }
        if (f.k === 'slash') { c.strokeStyle = 'rgba(255,255,255,' + (1 - k) + ')'; c.lineWidth = 4 * (1 - k) + 1; c.beginPath(); c.arc(f.x, f.y, 26 + k * 12, f.a - 1.1 + k * .8, f.a + .4 + k * .8); c.stroke(); }
        else if (f.k === 'num') { c.save(); c.globalAlpha = 1 - Math.max(0, k - .6) / .4; c.font = '800 ' + (f.big ? 22 : 16) + 'px Inter, system-ui, sans-serif'; c.textAlign = 'center'; c.lineWidth = 4; c.strokeStyle = 'rgba(0,0,0,.85)'; c.strokeText(f.txt, f.x, f.y - k * 44); c.fillStyle = f.col; c.fillText(f.txt, f.x, f.y - k * 44); c.restore(); }
        else f.p.forEach(function (p) { c.globalAlpha = 1 - k; c.fillStyle = p[2]; c.fillRect(f.x + p[0] * k * 90, f.y + p[1] * k * 90 + k * k * 90, p[3], p[3]); }), c.globalAlpha = 1; }
      c.restore();
      /* vignetta, testata, barra del nemico */
      var vg = c.createRadialGradient(W / 2, H / 2, H * .3, W / 2, H / 2, H * .8); vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.55)'); c.fillStyle = vg; c.fillRect(0, 0, W, H);
      var TOP = o.hud === false ? 54 : 88;
      if (o.hud !== false) {
      var tg = c.createLinearGradient(0, 0, 0, 96); tg.addColorStop(0, 'rgba(0,0,0,.75)'); tg.addColorStop(1, 'rgba(0,0,0,0)'); c.fillStyle = tg; c.fillRect(0, 0, W, 96);
      c.font = '700 15px Cinzel, Georgia, serif'; c.textAlign = 'left'; c.textBaseline = 'middle'; c.fillStyle = '#ffe7a8'; c.fillText((d.name || 'Dungeon'), 12, 20, W - 110);
      c.font = '600 11px Inter, system-ui, sans-serif'; c.fillStyle = 'rgba(255,255,255,.8)'; c.fillText(T.name + (st.sub ? ' · ' + st.sub : ''), 12, 39, W - 24);
      if (rooms.length) for (i = 0; i < rooms.length; i++) { var dx = 14 + i * 16; c.fillStyle = i < st.room ? (rooms[i].cleared ? '#4ade9b' : '#ff6b7a') : i === st.room ? '#ffd36b' : 'rgba(255,255,255,.25)'; c.beginPath(); if (rooms[i].boss) { c.moveTo(dx, 52); c.lineTo(dx + 6, 58); c.lineTo(dx, 64); c.lineTo(dx - 6, 58); } else c.arc(dx, 58, 4.5, 0, 6.3); c.fill(); }
      }
      if (cur && st.foeA > 0 && !st.foeDead) { pill((cur.boss ? '👑 ' : '') + st.plaque, W / 2, TOP, cur.boss ? '#ff6b7a' : rgba(T.glow, .9)); bar(W / 2, TOP + 18, Math.min(W - 60, 240), st.foeHp, cur.boss ? '#ff4d6a' : '#ff8a5c', 8); }
      if (st.tintc) { c.fillStyle = st.tintc; c.fillRect(0, 0, W, H); }
      if (st.cap) { var ck = (ts - st.cap.t0) / st.cap.d; if (ck >= 1) st.cap = null; else { c.save(); c.globalAlpha = Math.min(1, ck * 8, (1 - ck) * 5); var L = wrapTxt(st.cap.txt, W - 44), ly = Math.max(TOP + 40, GY * .34) - (L.length - 1) * 9;
        c.font = '600 13px Inter, system-ui, sans-serif'; var cw = 0; L.forEach(function (x) { cw = Math.max(cw, c.measureText(x).width); }); cw = Math.min(W - 16, cw + 26); c.fillStyle = 'rgba(8,6,18,.86)'; c.strokeStyle = st.cap.col || rgba(T.glow, .9); c.lineWidth = 1.5;
        c.beginPath(); if (c.roundRect) c.roundRect(W / 2 - cw / 2, ly - 14, cw, L.length * 18 + 12, 10); else c.rect(W / 2 - cw / 2, ly - 14, cw, L.length * 18 + 12); c.fill(); c.stroke();
        c.fillStyle = st.cap.fg || '#fff'; c.textAlign = 'center'; c.textBaseline = 'middle'; L.forEach(function (x, i) { c.fillText(x, W / 2, ly + 1 + i * 18, W - 30); }); c.restore(); } }
      if (st.flash > 0) { c.fillStyle = 'rgba(255,255,255,' + st.flash + ')'; c.fillRect(0, 0, W, H); }
      if (st.dark > 0) { c.fillStyle = 'rgba(0,0,0,' + st.dark + ')'; c.fillRect(0, 0, W, H); }
      if (st.banner) { var bk = Math.min(1, (ts - st.banner.t0) / 400); c.save(); c.globalAlpha = bk; c.translate(W / 2, H * .36); c.scale(.8 + .2 * bk, .8 + .2 * bk); c.font = '700 22px Cinzel, Georgia, serif'; c.textAlign = 'center'; c.textBaseline = 'middle';
        var bw = Math.min(W - 16, c.measureText(st.banner.txt).width + 40); c.fillStyle = st.banner.win ? 'rgba(40,26,6,.92)' : 'rgba(40,6,10,.92)'; c.strokeStyle = st.banner.win ? '#ffd36b' : '#ff6b7a'; c.lineWidth = 2; c.beginPath(); if (c.roundRect) c.roundRect(-bw / 2, -24, bw, 48, 12); else c.rect(-bw / 2, -24, bw, 48); c.fill(); c.stroke();
        c.fillStyle = st.banner.win ? '#ffe7a8' : '#ffb4bc'; c.fillText(st.banner.txt, 0, 1, bw - 20); if (st.banner.sub) { c.font = '600 13px Inter, sans-serif'; c.fillStyle = '#f3ead2'; c.fillText(st.banner.sub, 0, 40, W - 30); } c.restore(); }
    }
    var raf = null;
    function loop(ts) { raf = null; if (!alive || !cv.isConnected) return; for (var i = tw.length - 1; i >= 0; i--) { var a = tw[i], k = Math.min(1, (ts - a.t0) / a.d); a.f(k); if (k >= 1) { tw.splice(i, 1); a.ok(); } }
      if (st.shake > 0) st.shake = Math.max(0, st.shake - .8); if (st.flash > 0) st.flash = Math.max(0, st.flash - .06); draw(ts); raf = requestAnimationFrame(loop); }
    raf = requestAnimationFrame(loop);
    function wrapTxt(txt, mw) { c.font = '600 13px Inter, system-ui, sans-serif'; var out = [], line = ''; String(txt).split(/\s+/).forEach(function (w) { var t = line ? line + ' ' + w : w; if (c.measureText(t).width > mw && line) { out.push(line); line = w; } else line = t; }); if (line) out.push(line); return out.slice(0, 4); }
    function caption(txt, col, fg, ms) { st.cap = { txt: txt, col: col, fg: fg, t0: performance.now(), d: ms || Math.min(5200, 1800 + String(txt).length * 38) }; }
    async function walk(ms, fadeFoe) { st.walk = 1; var s0 = st.sx; await tween(ms || 800, function (k) { st.sx = s0 + (ms || 800) * .26 * k; if (fadeFoe) st.foeA = Math.max(0, (k - .45) / .55); }); st.walk = 0; }
    /* uno scontro: r = {name, emoji, boss, cleared, rounds, members?} */
    async function fight(r, ri, tot, seedNo) { var rm = r.members || [];
      var key = foe(r.name, r.emoji, !!r.boss, (d.no || 1) * 13 + (seedNo == null ? ri : seedNo)); cur = { key: key, boss: !!r.boss, S: img(key), tint: tintOf(key, !!r.boss, d.no || 1) };
      st.room = ri; st.plaque = r.name || 'Nemici'; st.sub = tot ? (o.path ? 'Scontro ' : 'Stanza ') + (ri + 1) + ' di ' + tot : ''; st.foeHp = 1; st.foeDead = 0; st.foeA = 0;
      P.forEach(function (p) { if (p.down) { var m = byName(rm, p); if (m && !m.ko) p.down = 0; } });
      await walk(ri ? 1100 : 800, true);
      if (cur.boss) { st.shake = 8; fx({ k: 'num', x: W / 2, y: H * .5, txt: 'BOSS!', col: '#ff6b7a', big: true, d: 900 }); await wait(500); } else await wait(180);
      var n = Math.max(2, Math.min(cur.boss ? 7 : 5, Math.ceil((r.rounds || 4) / 2))), dealt = 0, taken = 0; rm.forEach(function (m) { dealt += Number(m.dealt || 0); taken += Number(m.taken || 0); });
      var endHp = r.cleared ? 0 : .12 + .5 * rnd(ri + 5)(), stand = P.filter(function (p) { return !p.down; });
      for (var e = 0; e < n && !skipping && alive; e++) { var last = e === n - 1;
        await tween(170, function (k) { stand.forEach(function (p, i) { p.lunge = Math.sin(k * Math.PI) * (i % 2 ? .7 : 1); }); });
        var fxx = FX0(), fy = GY - (cur.boss ? 110 : 55) * Math.min(1, GY / 400); fx({ k: 'slash', x: fxx, y: fy, a: 0, d: 340 }); if (dealt) fx({ k: 'num', x: fxx + (Math.random() - .5) * 40, y: fy - 30, txt: '−' + fmt(Math.round(dealt / n * (.8 + Math.random() * .4))), col: '#ffffff', big: last, d: 900 });
        burst(fxx, fy, ['#cfeaff', '#ffffff', T.glow], last ? 16 : 8); st.shake = last ? 7 : 3; var h0 = st.foeHp, h1 = 1 - (1 - endHp) * (e + 1) / n; await tween(200, function (k) { st.foeHit = 1 - k; st.foeHp = h0 + (h1 - h0) * k; });
        if (h1 <= 0) break;
        await tween(170, function (k) { st.foeLunge = Math.sin(k * Math.PI); });
        var tg = stand[Math.floor(Math.random() * stand.length)] || P[0], ti = P.indexOf(tg); fx({ k: 'slash', x: px(ti), y: GY - HH() * .5, a: Math.PI, d: 340 });
        if (taken) fx({ k: 'num', x: px(ti), y: GY - HH() - 26, txt: '−' + fmt(Math.round(taken / n * (.8 + Math.random() * .4))), col: '#ff8a8a', d: 900 });
        P.forEach(function (p) { var m = byName(rm, p); if (m && m.max_hp) { var target = m.ko ? 0 : m.hp / m.max_hp; p.hp += (target - p.hp) * (e + 1) / n; } });
        await tween(200, function (k) { if (tg) tg.hit = 1 - k; });
      }
      st.foeHit = st.foeLunge = 0; P.forEach(function (p) { p.lunge = p.hit = 0; var m = byName(rm, p); if (m && m.max_hp) p.hp = m.ko ? 0 : m.hp / m.max_hp; });
      var fallen = P.filter(function (p) { var m = byName(rm, p); return !p.down && (m ? m.ko : (!r.cleared && r.members)); });
      if (fallen.length) await tween(380, function (k) { fallen.forEach(function (p) { p.down = k; }); });
      if (r.cleared) { st.foeHp = 0; burst(FX0(), GY - 50, [T.glow, '#ffffff', '#ffe66b'], cur.boss ? 46 : 24); if (cur.boss) st.flash = .4; await tween(cur.boss ? 800 : 480, function (k) { st.foeDead = k; }); st.foeA = 0; cur = null; await wait(160); return true; }
      if (r.members) { var rest = P.filter(function (p) { return !p.down; }); await tween(420, function (k) { rest.forEach(function (p) { p.down = k; }); }); }
      else { await tween(300, function (k) { st.tintc = 'rgba(160,20,40,' + .3 * Math.sin(k * Math.PI) + ')'; }); st.tintc = null; await tween(400, function (k) { st.foeA = 1 - k; }); cur = null; }
      return false;
    }
    async function finale(win, sub) { skipping = reduce; st.sub = ''; cur = null; st.foeA = 0;
      if (win) { for (var q = 0; q < 3; q++) burst(W * (.25 + q * .25), H * .3, ['#ffd23f', '#ffe66b', '#fff3a0', T.glow], 30);
        st.banner = { t0: performance.now(), win: true, txt: o.path ? '🏆 Spedizione riuscita!' : '🏆 Dungeon superato!', sub: sub || '' };
        await tween(700, function (k) { P.forEach(function (p, i) { if (!p.down) p.lunge = -Math.abs(Math.sin(k * Math.PI * 2 + i)) * .12; }); }); }
      else { st.banner = { t0: performance.now(), win: false, txt: o.path ? '💀 Spedizione fallita' : '💀 Il gruppo è caduto', sub: sub || '' }; var rest = P.filter(function (p) { return !p.down; }); await tween(420, function (k) { rest.forEach(function (p) { p.down = k; }); }); }
      await wait(1500); }
    /* prova di abilità: i dadi girano, poi l'esito */
    async function dice(stat, pct, ok) { var t0 = performance.now(); await tween(750, function (k) { st.cap = { txt: '🎲 ' + stat + ' · ' + pct + '%  →  ' + Math.floor(1 + Math.random() * 100), col: '#ffd36b', t0: t0, d: 99999 }; });
      caption((ok ? '✔ Prova riuscita! ' : '✖ Prova fallita. ') + '(' + stat + ' ' + pct + '%)', ok ? '#4ade9b' : '#ff6b7a', ok ? '#b9f5d6' : '#ffb4bc', 2200); if (ok) burst(W * .3, GY - HH(), ['#4ade9b', '#ffffff'], 18); else st.shake = 7;
      await tween(500, function (k) { st.tintc = (ok ? 'rgba(74,222,155,' : 'rgba(255,80,100,') + .22 * Math.sin(k * Math.PI) + ')'; }); st.tintc = null; await wait(500); }
    function party(members) { (members || []).forEach(function (m) { P.forEach(function (p) { if (p.id === m.user_id && m.max_hp) { var v = Math.max(0, Math.min(1, m.hp / m.max_hp)); if (v < p.hp - .005) { fx({ k: 'num', x: px(P.indexOf(p)), y: GY - HH() - 20, txt: '−' + fmt(Math.round((p.hp - v) * m.max_hp)), col: '#ff8a8a', d: 1100 }); p.hit = 1; tween(300, function (k) { p.hit = 1 - k; }); }
      else if (v > p.hp + .005) fx({ k: 'num', x: px(P.indexOf(p)), y: GY - HH() - 20, txt: '+' + fmt(Math.round((v - p.hp) * m.max_hp)), col: '#4ade9b', d: 1100 }); p.hp = v; p.down = v <= 0 ? 1 : 0; } }); }); }
    function HH() { return Math.min(128, W * .3, GY * .28); }
    function byName(rm, p) { for (var i = 0; i < rm.length; i++) if (rm[i].user_id === p.id || String(rm[i].nickname || '').slice(0, 10) === p.n) return rm[i]; return null; }
    function stop() { alive = false; if (raf) cancelAnimationFrame(raf); removeEventListener('resize', size); try { if (RO) RO.disconnect(); } catch (e) { } }
    var RO = null; try { RO = new ResizeObserver(size); RO.observe(host); } catch (e) { }
    tween(500, function (k) { st.dark = 1 - k; });
    return { canvas: cv, fight: fight, walk: walk, finale: finale, dice: dice, caption: caption, party: party, wait: wait, stop: stop, alive: function () { return alive; },
      attach: function (h) { if (h && h !== cv.parentNode) { try { if (RO) { RO.disconnect(); RO.observe(h); } } catch (e) { } host = h; h.appendChild(cv); size(); } },
      skip: function (on) { skipping = on !== false; var L = tw.slice(); tw.length = 0; L.forEach(function (a) { a.f(1); a.ok(); }); }, noskip: function () { skipping = reduce; } };
  }
  /* spedizione automatica: tutte le stanze di fila, poi l'esito. o.from = stanze già viste (dungeon a scelte) */
  function play(host, o) {
    var res = o.res || {}, rooms = (res.rooms || []).slice(o.from || 0), S = stage(host, { dungeon: o.dungeon, res: res, dots: rooms, me: o.me, looks: o.looks, pet: o.pet, path: !!res.path });
    var me = (res.members || []).filter(function (m) { return m.user_id === o.me; })[0];
    var done = (async function () { await S.wait(450); for (var i = 0; i < rooms.length && S.alive(); i++) { var ok = await S.fight(rooms[i], i, rooms.length); if (!ok) break; }
      S.noskip(); await S.finale(!!res.win, me ? (res.win ? '+' + fmt(me.bc) + ' BC · +' + fmt(me.xp) + ' XP' : '+' + fmt(me.xp) + ' XP di consolazione') : ''); })().catch(function (e) { if (g.console) console.error(e); }).then(function () { S.stop(); });
    return { done: done, skip: function () { S.skip(); } };
  }
  /* spedizione a scelte, dal vivo: il palco resta acceso tra una scelta e l'altra */
  function live(host, o) { return stage(host, { dungeon: o.dungeon, members: o.members, me: o.me, looks: o.looks, pet: o.pet, path: true, hud: false, ground: o.ground || .8 }); }
  g.DungeonScena = { play: play, live: live };
})(window);
