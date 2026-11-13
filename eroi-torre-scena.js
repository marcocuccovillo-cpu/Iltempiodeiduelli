/* La guerra degli Eroi — Torre Infinita: la scena dentro la Torre.
   Spaccato della Torre con le scale a zig-zag: l'eroe aspetta sul suo piano, il nemico del piano dopo lo aspetta sopra.
   Premendo «Sali» l'eroe sale le scale (la telecamera lo segue), affronta il nemico colpo per colpo seguendo il registro del
   combattimento che arriva dal server (danni, critici, schivate, barre dei PV) e alla fine o conquista il piano o ruzzola giù.
   Tutto disegnato su <canvas> con gli sprite pixel art di TorreArt (e PetArt per il compagno). Nessuna immagine esterna.
   Uso: const S = TorreScena.make(host, {floor, enemy, zone, hero:{name, pet}});  await S.play(risultato); S.skip(); S.destroy(); */
(function (g) {
  'use strict';
  var FH = 210, SLAB = 16, IMG = {};
  function img(url) { if (IMG[url]) return IMG[url]; var i = new Image(); i.src = url; IMG[url] = i; return i; }
  function ease(k) { return k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2; }
  function rnd(s) { var x = (s * 2654435761) >>> 0 || 1; return function () { x ^= x << 13; x >>>= 0; x ^= x >> 17; x ^= x << 5; x >>>= 0; return x / 4294967296; }; }
  function h2r(h) { h = h.replace('#', ''); return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]; }
  function rgba(h, a) { var c = h2r(h); return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; }
  function shade(h, f) { var c = h2r(h); return 'rgb(' + c.map(function (v) { return Math.round(f < 0 ? v * (1 + f) : v + (255 - v) * f); }).join(',') + ')'; }
  function fmt(n) { return Number(n || 0).toLocaleString('it-IT'); }

  function make(host, o) {
    var TA = g.TorreArt, PA = g.PetArt;
    var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    var cv = document.createElement('canvas'), c = cv.getContext('2d'); cv.className = 'tw-cv'; cv.setAttribute('aria-hidden', 'true');
    host.appendChild(cv);
    var DPR = Math.min(2, window.devicePixelRatio || 1), W = 360, H = 460;
    var n0 = o.floor;                                  // piano dove sta l'eroe (0 = ingresso)
    var zone = o.zone, en = o.enemy, isBoss = !!(en && en.boss);
    var tint = (TA.tints || [])[Math.min(4, Math.max(0, (en && en.tier) || 0))] || { h: 0, s: 1, b: 1 };
    var heroD = TA.uri('eroe'), enD = en ? TA.uri(en.sprite) : null;
    var petD = o.hero && o.hero.pet && PA && PA.uri ? PA.uri(o.hero.pet.sprite, o.hero.pet.tier || 0) : null;
    var heroI = img(heroD.url), enI = enD ? img(enD.url) : null, petI = petD ? img(petD.url) : null;
    [heroI, enI, petI].forEach(function (i) { if (i && !i.complete) i.addEventListener('load', function () { dirty = true; kick(); }); });
    var R = rnd(n0 * 31 + 7), dust = []; for (var i = 0; i < 26; i++) dust.push([R(), R(), R() * 6.3, .3 + R() * .7]);

    /* geometria: piano n ha il pavimento a y = -n*FH; le scale dal piano n salgono verso il lato opposto */
    var yOf = function (n) { return -n * FH; };
    var dirOf = function (n) { return n % 2 === 0 ? 1 : -1; };          // 1: le scale del piano n partono da sinistra e arrivano a destra
    var stairA = function (n) { return dirOf(n) > 0 ? 54 : W - 54; };   // partenza (sul piano n)
    var stairB = function (n) { return dirOf(n) > 0 ? W - 54 : 54; };   // arrivo (sul piano n+1)
    /* stato animato */
    var hero = { x: 0, y: 0, dir: 1, bob: 0, rot: 0, alpha: 1, lunge: 0, hit: 0 };
    var foe = { x: 0, y: 0, dir: -1, alpha: en ? 1 : 0, lunge: 0, hit: 0, flash: 0, dead: 0 };
    var cam = { y: 0, s: 1, shake: 0 }, hp = { show: 0, a: 1, b: 1, ta: 1, tb: 1, ma: 1, mb: 1 }, FX = [], banner = null, flash = 0;
    function place() {
      hero.x = stairA(n0) + dirOf(n0) * 26; hero.y = yOf(n0); hero.dir = dirOf(n0); hero.rot = 0; hero.alpha = 1;
      var top = n0 + 1, arrive = stairB(n0);
      foe.x = W / 2 - dirOf(n0) * 28; foe.y = yOf(top); foe.dir = arrive > W / 2 ? 1 : -1; foe.alpha = en ? 1 : 0; foe.dead = 0;
      cam.y = yOf(n0) - FH / 2 - 26; cam.s = 1;
    }
    place();

    function resize() {
      var r = host.getBoundingClientRect(); W = Math.max(280, Math.round(r.width)); H = Math.round(Math.min(520, Math.max(400, W * 1.2)));
      cv.width = Math.round(W * DPR); cv.height = Math.round(H * DPR); cv.style.width = W + 'px'; cv.style.height = H + 'px';
      if (!busy) place(); dirty = true; kick();
    }

    /* ---------- disegno ---------- */
    function sky(y0, y1) { var gr = c.createLinearGradient(0, y0, 0, y1); gr.addColorStop(0, zone.sky[0]); gr.addColorStop(.6, zone.sky[1]); gr.addColorStop(1, zone.sky[2]); return gr; }
    function drawFloor(n, t) {
      var y = yOf(n), st = zone.stone, boss = o.bossFloor && n === o.bossFloor;
      /* muro di fondo: mattoni */
      c.fillStyle = shade(st, -.35); c.fillRect(0, y - FH, W, FH);
      c.strokeStyle = rgba('#000000', .22); c.lineWidth = 1;
      for (var row = 0; row < FH / 18; row++) { var yy = y - FH + row * 18; c.beginPath(); c.moveTo(0, yy); c.lineTo(W, yy); c.stroke();
        for (var bx = (row % 2) * 22; bx < W; bx += 44) { c.beginPath(); c.moveTo(bx, yy); c.lineTo(bx, yy + 18); c.stroke(); } }
      /* finestra ad arco con il cielo della zona */
      var wx = dirOf(n) > 0 ? W * .72 : W * .28, wy = y - FH + 34, ww = 46, wh = 74;
      c.save(); c.beginPath(); c.moveTo(wx - ww / 2, wy + wh); c.lineTo(wx - ww / 2, wy + ww / 2); c.arc(wx, wy + ww / 2, ww / 2, Math.PI, 0); c.lineTo(wx + ww / 2, wy + wh); c.closePath();
      c.fillStyle = sky(wy, wy + wh); c.fill(); c.clip();
      var sr = rnd(n * 13 + 5); for (var s = 0; s < 8; s++) { var a = .4 + .6 * Math.abs(Math.sin(t * 1.3 + s * 2 + n)); c.fillStyle = 'rgba(255,255,255,' + (reduce ? .8 : a) + ')'; c.fillRect(wx - ww / 2 + sr() * ww, wy + sr() * wh * .7, 1.5, 1.5); }
      c.restore();
      c.strokeStyle = shade(st, .25); c.lineWidth = 4; c.beginPath(); c.moveTo(wx - ww / 2, wy + wh); c.lineTo(wx - ww / 2, wy + ww / 2); c.arc(wx, wy + ww / 2, ww / 2, Math.PI, 0); c.lineTo(wx + ww / 2, wy + wh); c.stroke();
      c.strokeStyle = shade(st, -.2); c.lineWidth = 2; c.beginPath(); c.moveTo(wx, wy); c.lineTo(wx, wy + wh); c.moveTo(wx - ww / 2, wy + wh * .55); c.lineTo(wx + ww / 2, wy + wh * .55); c.stroke();
      /* stendardi dei boss */
      if (boss || (n > 0 && n % 10 === 0)) { [W * .2, W * .8].forEach(function (bx, i) { var sw = reduce ? 0 : Math.sin(t * 2 + i) * 2;
        c.fillStyle = '#8a1e2e'; c.beginPath(); c.moveTo(bx - 12, y - FH + 20); c.lineTo(bx + 12, y - FH + 20); c.lineTo(bx + 12 + sw, y - FH + 82); c.lineTo(bx + sw, y - FH + 70); c.lineTo(bx - 12 + sw, y - FH + 82); c.closePath(); c.fill();
        c.fillStyle = '#ffd36b'; c.font = '14px serif'; c.textAlign = 'center'; c.fillText('👑', bx + sw / 2, y - FH + 50); }); }
      /* torce che tremolano */
      [W * .1, W * .9].forEach(function (tx, i) { var ty = y - 120, f = reduce ? 1 : .8 + .2 * Math.sin(t * 13 + i * 3 + n) + .1 * Math.sin(t * 29 + i);
        var gl = c.createRadialGradient(tx, ty - 8, 0, tx, ty - 8, 46 * f); gl.addColorStop(0, rgba(zone.glow, .38)); gl.addColorStop(1, rgba(zone.glow, 0)); c.fillStyle = gl; c.beginPath(); c.arc(tx, ty - 8, 46 * f, 0, 6.3); c.fill();
        c.fillStyle = '#5a3a1e'; c.fillRect(tx - 2, ty - 2, 4, 16); c.fillStyle = '#3a2410'; c.fillRect(tx - 5, ty - 4, 10, 4);
        c.fillStyle = '#ff9a3a'; c.beginPath(); c.ellipse(tx, ty - 10, 4 * f, 8 * f, 0, 0, 6.3); c.fill(); c.fillStyle = '#ffe66b'; c.beginPath(); c.ellipse(tx, ty - 8, 2, 4 * f, 0, 0, 6.3); c.fill(); });
      /* scale dal piano n al piano n+1 */
      var a = stairA(n), b = stairB(n), steps = 12, d = (b - a) / steps, h = FH / steps;
      c.fillStyle = shade(st, -.18); c.beginPath(); c.moveTo(a, y); c.lineTo(b, y - FH); c.lineTo(b, y - FH + 26); c.lineTo(a + d * 1.5, y); c.closePath(); c.fill();
      for (var k = 0; k < steps; k++) { var sx = a + d * k, sy = y - h * (k + 1);
        c.fillStyle = shade(st, .05); c.fillRect(Math.min(sx, sx + d), sy, Math.abs(d) + 1, h + 2);
        c.fillStyle = shade(st, .35); c.fillRect(Math.min(sx, sx + d), sy, Math.abs(d) + 1, 3); }
      c.strokeStyle = shade(st, .45); c.lineWidth = 2; c.beginPath(); c.moveTo(a, y - 28); c.lineTo(b, y - FH - 28); c.stroke();
      for (k = 1; k < steps; k += 2) { c.beginPath(); c.moveTo(a + d * k, y - h * k - 28); c.lineTo(a + d * k, y - h * k); c.stroke(); }
      /* pavimento del piano */
      c.fillStyle = shade(st, .12); c.fillRect(0, y, W, SLAB); c.fillStyle = shade(st, .4); c.fillRect(0, y, W, 3); c.fillStyle = shade(st, -.4); c.fillRect(0, y + SLAB - 3, W, 3);
      /* targa del piano */
      var label = n === 0 ? 'Ingresso' : 'Piano ' + fmt(n), lx = W / 2;
      c.font = '700 12px Cinzel, Georgia, serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; var lw = c.measureText(label).width + 18;
      c.fillStyle = 'rgba(20,12,4,.85)'; c.strokeStyle = boss || (n > 0 && n % 10 === 0) ? '#ff6b7a' : rgba(zone.glow, .9); c.lineWidth = 1.5;
      var py = y - 1; c.beginPath(); if (c.roundRect) c.roundRect(lx - lw / 2, py, lw, 18, 6); else c.rect(lx - lw / 2, py, lw, 18); c.fill(); c.stroke();
      c.fillStyle = '#ffe7a8'; c.fillText(label, lx, py + 9.5);
    }
    function drawSprite(I, D, x, y, hpx, dir, opt) {
      if (!I || !I.complete || !D) return; opt = opt || {};
      var w = D.w / D.h * hpx; c.save(); c.translate(x, y); if (opt.rot) c.rotate(opt.rot); c.scale(dir, 1); c.globalAlpha = opt.alpha == null ? 1 : opt.alpha;
      if (opt.filter && 'filter' in c) c.filter = opt.filter;
      c.imageSmoothingEnabled = false; c.drawImage(I, -w / 2, -hpx, w, hpx); c.filter = 'none';
      if (opt.white) { c.globalCompositeOperation = 'source-atop'; c.globalAlpha = opt.white * (opt.alpha == null ? 1 : opt.alpha); c.fillStyle = '#ffffff'; c.fillRect(-w / 2, -hpx, w, hpx); }
      c.restore();
    }
    function shadow(x, y, r) { c.fillStyle = 'rgba(0,0,0,.35)'; c.beginPath(); c.ellipse(x, y + 2, r, r * .28, 0, 0, 6.3); c.fill(); }
    function bar(x, y, w, v, col) { c.fillStyle = 'rgba(0,0,0,.65)'; c.fillRect(x - w / 2 - 2, y - 2, w + 4, 10); c.fillStyle = '#3a1a1a'; c.fillRect(x - w / 2, y, w, 6);
      c.fillStyle = col; c.fillRect(x - w / 2, y, w * Math.max(0, v), 6); c.fillStyle = 'rgba(255,255,255,.35)'; c.fillRect(x - w / 2, y, w * Math.max(0, v), 2); }
    var EH = en ? (isBoss ? 150 : 108) : 0, HH = 84;
    function draw(ts) {
      var t = ts / 1000; c.setTransform(DPR, 0, 0, DPR, 0, 0); c.fillStyle = zone.sky[0]; c.fillRect(0, 0, W, H);
      var sh = cam.shake > 0 && !reduce ? (Math.random() - .5) * cam.shake : 0, sh2 = cam.shake > 0 && !reduce ? (Math.random() - .5) * cam.shake : 0;
      c.setTransform(DPR * cam.s, 0, 0, DPR * cam.s, DPR * (W / 2 - W / 2 * cam.s + sh), DPR * (H / 2 - cam.y * cam.s + sh2));
      /* piani visibili */
      var top = Math.floor(-(cam.y - H / 2 / cam.s) / FH) + 1, bot = Math.floor(-(cam.y + H / 2 / cam.s) / FH);
      for (var n = Math.max(0, bot - 1); n <= top + 1; n++) drawFloor(n, t);
      if (bot < 0) { c.fillStyle = shade(zone.stone, -.55); c.fillRect(0, SLAB, W, 400); }
      /* polvere nella luce */
      if (!reduce) dust.forEach(function (d) { var x = d[0] * W + Math.sin(t * .4 + d[2]) * 14, y = cam.y - H / 2 + ((d[1] * H - t * 9 * d[3]) % H + H) % H; c.fillStyle = rgba(zone.glow, .25 * d[3]); c.fillRect(x, y, 2, 2); });
      /* nemico */
      if (en && foe.alpha > 0) {
        var fx = foe.x + foe.lunge * foe.dir * 30, fy = foe.y, bob = reduce ? 0 : Math.sin(t * 2.2) * 2;
        if (isBoss && !foe.dead) { var ag = c.createRadialGradient(fx, fy - EH / 2, 4, fx, fy - EH / 2, EH * .75); ag.addColorStop(0, 'rgba(255,60,80,' + (.28 + .12 * Math.sin(t * 3)) + ')'); ag.addColorStop(1, 'rgba(255,60,80,0)'); c.fillStyle = ag; c.beginPath(); c.arc(fx, fy - EH / 2, EH * .75, 0, 6.3); c.fill(); }
        shadow(fx, fy, EH * .3);
        drawSprite(enI, enD, fx + foe.hit * -foe.dir * 6, fy + bob - foe.dead * 10, EH, foe.dir, { alpha: foe.alpha, white: Math.max(foe.flash, foe.dead), filter: tint.h ? 'hue-rotate(' + tint.h + 'deg) saturate(' + tint.s + ') brightness(' + tint.b + ')' : null });
        if (hp.show > 0) { c.globalAlpha = hp.show; bar(fx, fy - EH - 18, 74, hp.b, isBoss ? '#ff4d6a' : '#ff8a5c'); c.globalAlpha = 1; }
      }
      /* compagno che segue l'eroe */
      if (petI && petI.complete && hero.alpha > 0) { var pdx = -hero.dir * 30, pb = reduce ? 0 : Math.abs(Math.sin(t * 5)) * 4; drawSprite(petI, petD, hero.x + pdx, hero.y - pb - (hero.bob * .6), 40, hero.dir, { alpha: hero.alpha, rot: hero.rot * .5 }); }
      /* eroe */
      var hx = hero.x + hero.lunge * hero.dir * 34 - hero.hit * hero.dir * 6, hb = reduce ? 0 : hero.bob;
      shadow(hx, hero.y, 22); drawSprite(heroI, heroD, hx, hero.y - hb, HH, hero.dir, { alpha: hero.alpha, rot: hero.rot, white: hero.hit * .7 });
      if (hp.show > 0) { c.globalAlpha = hp.show; bar(hx, hero.y - HH - 18, 64, hp.a, '#4ade9b'); c.globalAlpha = 1; }
      /* effetti: fendenti, numeri, scintille */
      for (var i = FX.length - 1; i >= 0; i--) { var f = FX[i], k = (ts - f.t0) / f.d; if (k >= 1) { FX.splice(i, 1); continue; }
        if (f.k === 'slash') { c.strokeStyle = 'rgba(255,255,255,' + (1 - k) + ')'; c.lineWidth = 4 * (1 - k) + 1; c.beginPath(); c.arc(f.x, f.y, 24 + k * 10, f.a - 1.1 + k * .8, f.a + .4 + k * .8); c.stroke();
          c.strokeStyle = rgba(f.col || '#ffe66b', (1 - k) * .8); c.lineWidth = 2; c.beginPath(); c.arc(f.x, f.y, 30 + k * 12, f.a - .9 + k * .8, f.a + .3 + k * .8); c.stroke(); }
        else if (f.k === 'num') { var yy = f.y - k * 46, sc = f.big ? 1 + .4 * Math.max(0, .3 - k) * 3 : 1; c.save(); c.translate(f.x, yy); c.scale(sc, sc); c.font = '800 ' + (f.big ? 24 : 17) + 'px Inter, system-ui, sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle';
          c.globalAlpha = 1 - Math.max(0, k - .6) / .4; c.lineWidth = 4; c.strokeStyle = 'rgba(0,0,0,.85)'; c.strokeText(f.txt, 0, 0); c.fillStyle = f.col; c.fillText(f.txt, 0, 0); c.restore(); }
        else if (f.k === 'part') { f.p.forEach(function (p) { var px = f.x + p[0] * k * 90, py = f.y + p[1] * k * 90 + (f.g || 0) * k * k * 120; c.globalAlpha = 1 - k; c.fillStyle = p[2]; c.fillRect(px, py, p[3], p[3]); }); c.globalAlpha = 1; }
      }
      c.setTransform(DPR, 0, 0, DPR, 0, 0);
      /* vignetta e lampo dei critici */
      var vg = c.createRadialGradient(W / 2, H / 2, H * .3, W / 2, H / 2, H * .75); vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.5)'); c.fillStyle = vg; c.fillRect(0, 0, W, H);
      if (flash > 0) { c.fillStyle = 'rgba(255,255,255,' + flash + ')'; c.fillRect(0, 0, W, H); }
      if (banner) { var bk = Math.min(1, (ts - banner.t0) / 400), by = H * .2; c.save(); c.globalAlpha = bk; c.translate(W / 2, by); c.scale(.8 + .2 * bk, .8 + .2 * bk);
        c.font = '700 22px Cinzel, Georgia, serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; var bw = Math.min(W - 20, c.measureText(banner.txt).width + 40);
        c.fillStyle = banner.win ? 'rgba(40,26,6,.9)' : 'rgba(40,6,10,.9)'; c.strokeStyle = banner.win ? '#ffd36b' : '#ff6b7a'; c.lineWidth = 2; c.beginPath(); if (c.roundRect) c.roundRect(-bw / 2, -22, bw, 44, 12); else c.rect(-bw / 2, -22, bw, 44); c.fill(); c.stroke();
        c.fillStyle = banner.win ? '#ffe7a8' : '#ffb4bc'; c.fillText(banner.txt, 0, 1); if (banner.sub) { c.font = '600 13px Inter, sans-serif'; c.fillStyle = '#f3ead2'; c.fillText(banner.sub, 0, 36); } c.restore(); }
      dirty = false;
    }
    /* ---------- ciclo ---------- */
    var raf = null, dirty = true, busy = false, visible = true, last = 0, alive = true, tweens = [];
    function loop(ts) {
      raf = null; if (!alive || !cv.isConnected) return;
      for (var i = tweens.length - 1; i >= 0; i--) { var tw = tweens[i], k = Math.min(1, (ts - tw.t0) / tw.d); tw.f(tw.e ? ease(k) : k); if (k >= 1) { tweens.splice(i, 1); tw.done(); } }
      if (cam.shake > 0) cam.shake = Math.max(0, cam.shake - .8); if (flash > 0) flash = Math.max(0, flash - .06);
      if (!busy && !reduce) hero.bob = Math.abs(Math.sin(ts / 520)) * 1.5;
      var live = !reduce && visible && !document.hidden;
      if (dirty || busy || tweens.length || FX.length || (live && ts - last > 33)) { last = ts; draw(ts); }
      if (busy || tweens.length || FX.length || live) raf = requestAnimationFrame(loop);
    }
    function kick() { if (!raf && alive) raf = requestAnimationFrame(loop); }
    function tween(d, f, e) { return new Promise(function (res) { if (skipping) { f(1); return res(); } tweens.push({ t0: performance.now(), d: d, f: f, e: e !== false, done: res }); kick(); }); }
    function wait(ms) { return tween(ms, function () { }, false); }
    function fx(f) { f.t0 = performance.now(); f.d = f.d || 900; FX.push(f); kick(); }
    function burst(x, y, cols, n, gr) { var p = [], r = rnd(Math.floor(performance.now())); for (var i = 0; i < n; i++) { var a = r() * 6.283, s = .3 + r() * .9; p.push([Math.cos(a) * s, Math.sin(a) * s - .4, cols[i % cols.length], 2 + r() * 3]); } fx({ k: 'part', x: x, y: y, p: p, g: gr == null ? 1 : gr, d: 1100 }); }
    var io = null; try { io = new IntersectionObserver(function (es) { visible = es[0].isIntersecting; kick(); }); io.observe(cv); } catch (e) { }
    var ro = null; try { ro = new ResizeObserver(function () { resize(); }); ro.observe(host); } catch (e) { addEventListener('resize', resize); }
    resize();

    /* ---------- la salita e il combattimento ---------- */
    var skipping = false;
    async function play(r) {
      if (busy) return; busy = true; skipping = reduce; banner = null;
      var n = n0, a = stairA(n), b = stairB(n), y0 = yOf(n), y1 = yOf(n + 1), dir = dirOf(n);
      /* 1) all'inizio delle scale */
      hero.dir = dir; var sx = hero.x; await tween(380, function (k) { hero.x = sx + (a - sx) * k; hero.bob = Math.abs(Math.sin(k * Math.PI * 2)) * 4; });
      /* 2) su per le scale, la telecamera segue */
      var cy0 = cam.y, cy1 = y1 - 90;
      await tween(1500, function (k) { hero.x = a + (b - a) * k; hero.y = y0 + (y1 - y0) * k; hero.bob = Math.abs(Math.sin(k * Math.PI * 12)) * 4; cam.y = cy0 + (cy1 - cy0) * k; }, false);
      /* 3) verso il nemico, zoom sulla sfida */
      hero.dir = -dir; var fxp = foe.x + dir * (isBoss ? 92 : 78), hx0 = hero.x;
      await tween(520, function (k) { hero.x = hx0 + (fxp - hx0) * k; hero.bob = Math.abs(Math.sin(k * Math.PI * 3)) * 3; cam.s = 1 + .22 * k; cam.y = cy1 + (y1 - 70 - cy1) * k; hp.show = k; });
      hero.bob = 0; hp.ma = r.max_a; hp.mb = r.max_b; hp.a = 1; hp.b = 1;
      await wait(260);
      /* 4) colpo su colpo, dal registro del server */
      var L = r.log || [], step = L.length > 24 ? 260 : L.length > 14 ? 360 : 480;
      for (var i = 0; i < L.length && !skipping; i++) { var s = L[i], me = s.w === 'a';
        var att = me ? hero : foe, def = me ? foe : hero, dx = me ? foe.x : hero.x, dy = (me ? foe.y - EH * .55 : hero.y - HH * .55);
        await tween(step * .35, function (k) { att.lunge = Math.sin(k * Math.PI); });
        if (s.x) { fx({ k: 'num', x: dx, y: dy - 20, txt: 'Schivata!', col: '#9fd3ff', d: 800 }); var ox = def.x; await tween(step * .3, function (k) { def.x = ox - Math.sin(k * Math.PI) * 18 * def.dir; }); def.x = ox; }
        else { fx({ k: 'slash', x: dx, y: dy, a: me ? 0 : Math.PI, col: s.c ? '#ffe66b' : (me ? '#7fe3ff' : '#ff6b6b'), d: 360 });
          fx({ k: 'num', x: dx + (Math.random() - .5) * 20, y: dy - 26, txt: '−' + fmt(s.d) + (s.c ? '!' : ''), col: s.c ? '#ffe66b' : (me ? '#ffffff' : '#ff8a8a'), big: !!s.c, d: 950 });
          burst(dx, dy, s.c ? ['#ffe66b', '#ffffff'] : [me ? '#cfeaff' : '#ff9a8c', '#ffffff'], s.c ? 18 : 8, .6);
          if (s.c) { cam.shake = 9; flash = .35; } else cam.shake = 3;
          if (me) foe.flash = 1; await tween(step * .3, function (k) { def.hit = 1 - k; if (me) foe.flash = 1 - k; }); }
        hp.a = Math.max(0, s.ha / Math.max(1, r.max_a)); hp.b = Math.max(0, s.hb / Math.max(1, r.max_b));
        await wait(step * .35);
      }
      hero.lunge = foe.lunge = hero.hit = foe.hit = foe.flash = 0;
      hp.a = Math.max(0, r.hp_a / Math.max(1, r.max_a)); hp.b = Math.max(0, r.hp_b / Math.max(1, r.max_b));
      skipping = reduce;
      /* 5) fine */
      if (r.won) {
        burst(foe.x, foe.y - EH * .5, [zone.glow, '#ffffff', '#ffe66b'], 40, -.2);
        await tween(900, function (k) { foe.dead = k; foe.alpha = 1 - k; hp.show = 1 - k; });
        burst(hero.x, hero.y - HH, ['#ffd23f', '#ffe66b', '#fff3a0'], 30, 1.2);
        fx({ k: 'num', x: hero.x, y: hero.y - HH - 30, txt: '+' + fmt(r.bc) + ' BC', col: '#ffd36b', big: true, d: 1500 });
        banner = { t0: performance.now(), win: true, txt: (r.enemy && r.enemy.boss ? '👑 ' : '🏆 ') + 'Piano ' + fmt(r.floor) + ' conquistato!', sub: '+' + fmt(r.xp) + ' XP' + (r.levels > 0 ? ' · livello ' + fmt(r.level) + '!' : '') };
        var jy = hero.y; await tween(520, function (k) { hero.y = jy - Math.sin(k * Math.PI) * 26; cam.s = 1.22 - .22 * k; });
      } else {
        banner = { t0: performance.now(), win: false, txt: '💥 Sconfitto al piano ' + fmt(r.floor), sub: 'Rafforza l’eroe e riprova' };
        await tween(300, function (k) { hero.rot = -hero.dir * k * .5; hp.show = 1 - k * .5; });
        /* ruzzola giù per le scale */
        var hx1 = hero.x, cyA = cam.y, sA = cam.s;
        await tween(420, function (k) { hero.x = hx1 + (b - hx1) * k; });
        await tween(1100, function (k) { hero.x = b + (a - b) * k; hero.y = y1 + (y0 - y1) * k; hero.rot = -dir * (k * 6.28 * 2); cam.y = cyA + (yOf(n) - FH / 2 - 26 - cyA) * k; cam.s = sA + (1 - sA) * k; hp.show = .5 * (1 - k); }, false);
        hero.rot = 0; hero.dir = dir; cam.shake = 6;
      }
      busy = false; skipping = false; kick();
    }
    return {
      canvas: cv, play: play,
      skip: function () { skipping = true; var L = tweens.slice(); tweens.length = 0; L.forEach(function (tw) { tw.f(1); tw.done(); }); },
      busy: function () { return busy; },
      destroy: function () { alive = false; if (io) io.disconnect(); if (ro) ro.disconnect(); if (cv.parentNode) cv.parentNode.removeChild(cv); }
    };
  }
  g.TorreScena = { make: make };
})(window);
