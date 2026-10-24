/* =====================================================================
   SHOP DEL TEMPIO — grafica dei premi (pet, cornici, aure, emblemi, effetti, titoli) e intestazione del profilo.
   Tutto è disegnato qui in SVG e CSS: nessun file immagine, nessuna emoji, nessuna dipendenza.
   Le creature sono originali. Le animazioni sono leggere e si spengono da sole con "riduci movimento"
   o con il pulsante «Animazioni» dello Shop (versione statica per i dispositivi meno potenti).
   I prezzi, i nomi e la proprietà dei premi NON stanno qui: arrivano dal database (migrazione 008).
   I 60 premi aggiuntivi (chiavi xp_/xf_/xa_/xe_/xt_/xx_) si disegnano con shop-art-extra.js, che qui viene solo richiamato.
   ===================================================================== */
(function () {
  'use strict';
  const RAR = { common: ['Comune', '#9aa4b2'], rare: ['Raro', '#4aa3ff'], epic: ['Epico', '#b46bff'], legendary: ['Leggendario', '#ffb02e'], mythic: ['Mitico', '#ff3d6e'], divine: ['Divino', '#5eead4'] };
  const RARS = ['common', 'rare', 'epic', 'legendary', 'mythic', 'divine'];
  const CATS = [['pet', 'Pet'], ['title', 'Titoli'], ['frame', 'Cornici'], ['aura', 'Aure'], ['emblem', 'Emblemi'], ['effect', 'Effetti']];
  const CATN = { pet: 'Pet', title: 'Titolo', frame: 'Cornice', aura: 'Aura', emblem: 'Emblema', effect: 'Effetto' };
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  let K = 0;

  /* ---------- premi aggiuntivi (shop-art-extra.js) ---------- */
  const X = () => window.SHOP_EXTRA || null;
  const isX = a => !!X() && /^x[pfaetx]_[a-z0-9_]+$/.test(a || '');
  const xsvg = a => { try { return X().svg(a, { anim: fxOn() }) } catch (e) { return '' } };
  /* colore dominante di ogni aura aggiuntiva (R,G,B): tinge lo sfondo dell'intestazione attorno al disegno */
  const AUR = { xa_braci: '251,146,60', xa_druidica: '74,222,128', xa_gelida: '103,232,249', xa_tempesta: '129,140,248', xa_sacra: '253,224,120', xa_infernale: '225,29,116', xa_astrale: '147,130,255', xa_caos: '217,70,239', xa_galattica: '99,102,241', xa_singolarita: '245,158,11' };

  /* ---------- piccoli attrezzi SVG ---------- */
  const stops = a => a.map(([o, c, op]) => `<stop offset="${o}" stop-color="${c}"${op != null ? ` stop-opacity="${op}"` : ''}/>`).join('');
  const lin = (id, a, x1 = 0, y1 = 0, x2 = 0, y2 = 1) => `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stops(a)}</linearGradient>`;
  const rad = (id, a, cx = .5, cy = .5, r = .5) => `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}">${stops(a)}</radialGradient>`;
  const blur = (id, s) => `<filter id="${id}" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="${s}"/></filter>`;
  const svg = (inner, cls, vb) => `<svg class="tdp ${cls || ''}" viewBox="${vb || '0 0 200 200'}" role="img" aria-hidden="true" focusable="false">${inner}</svg>`;
  const flame = (c, t, s) => `<path d="M0 0C8-9 20-9 34-2 22 0 20 4 34 10 18 12 8 8 0 0Z" fill="${c}" transform="${t || ''} scale(${s || 1})"/>`;

  /* =============================== PET PICCOLI =============================== */
  function slime() {
    const g = 'g' + ++K;
    return svg(`<defs>${lin(g + 'a', [[0, '#a5f3d0'], [.55, '#4fd1a5'], [1, '#1c8f78']])}${rad(g + 'b', [[0, '#fff', .9], [1, '#fff', 0]])}</defs>
<ellipse cx="100" cy="168" rx="52" ry="8" fill="#000" opacity=".35"/>
<g class="sa-bounce" style="transform-origin:100px 166px">
 <path d="M38 150C30 108 60 66 100 66s70 42 62 84c-2 12-12 16-22 16H60c-10 0-20-4-22-16Z" fill="url(#${g}a)" stroke="#0f6b5a" stroke-width="2.5"/>
 <path d="M64 48c8-8 16-6 22 2-8 0-16 2-22-2Z" fill="#2fb98a" stroke="#0f6b5a" stroke-width="2"/><path d="M96 66c-4-14 0-24 6-30 2 12 0 22-6 30Z" fill="#4fd1a5" stroke="#0f6b5a" stroke-width="2"/>
 <ellipse cx="78" cy="96" rx="20" ry="12" fill="url(#${g}b)"/>
 <ellipse cx="80" cy="118" rx="9" ry="12" fill="#10222a"/><ellipse cx="120" cy="118" rx="9" ry="12" fill="#10222a"/>
 <circle cx="83" cy="113" r="3.6" fill="#fff"/><circle cx="123" cy="113" r="3.6" fill="#fff"/>
 <path d="M90 136q10 9 20 0" fill="none" stroke="#10222a" stroke-width="3" stroke-linecap="round"/>
 <ellipse cx="66" cy="136" rx="7" ry="4" fill="#ff9db4" opacity=".7"/><ellipse cx="134" cy="136" rx="7" ry="4" fill="#ff9db4" opacity=".7"/>
 <path d="M52 160c-4 8 0 12 4 8M148 162c4 8 0 12-4 8" fill="none" stroke="#9af0cf" stroke-width="5" stroke-linecap="round" opacity=".8"/>
</g>`, 'sa-small');
  }
  function ghost() {
    const g = 'g' + ++K;
    return svg(`<defs>${lin(g + 'a', [[0, '#ffffff'], [.6, '#e1d9ff'], [1, '#a99bf0']])}${blur(g + 'f', 6)}</defs>
<ellipse cx="100" cy="176" rx="34" ry="6" fill="#000" opacity=".3" class="sa-shadow"/>
<g class="sa-float">
 <ellipse cx="100" cy="94" rx="58" ry="62" fill="#c9bcff" opacity=".55" filter="url(#${g}f)" class="sa-glow"/>
 <path d="M58 156V96C58 62 78 42 100 42s42 20 42 54v60l-13-11-14 13-15-12-15 12-14-13z" fill="url(#${g}a)" stroke="#7d6ad6" stroke-width="2.5" stroke-linejoin="round"/>
 <path d="M58 112c-14 4-20 14-16 22M142 112c14 4 20 14 16 22" fill="none" stroke="#c4b8ff" stroke-width="9" stroke-linecap="round"/>
 <ellipse cx="82" cy="98" rx="9" ry="13" fill="#251a52"/><ellipse cx="118" cy="98" rx="9" ry="13" fill="#251a52"/>
 <circle cx="85" cy="92" r="3.8" fill="#fff"/><circle cx="121" cy="92" r="3.8" fill="#fff"/>
 <ellipse cx="70" cy="120" rx="8" ry="4.5" fill="#ff9db4" opacity=".65"/><ellipse cx="130" cy="120" rx="8" ry="4.5" fill="#ff9db4" opacity=".65"/>
 <ellipse cx="100" cy="122" rx="6" ry="7" fill="#251a52"/>
</g>`, 'sa-small');
  }
  function mage() {
    const g = 'g' + ++K;
    return svg(`<defs>${lin(g + 'a', [[0, '#1e6a86'], [1, '#0a2438']])}${lin(g + 'b', [[0, '#2f8fb0'], [1, '#124a66']])}${rad(g + 'c', [[0, '#fff6c0'], [.4, '#ffd34d', .9], [1, '#ffb300', 0]])}${blur(g + 'f', 4)}</defs>
<ellipse cx="100" cy="178" rx="46" ry="7" fill="#000" opacity=".35"/>
<g class="sa-float" style="animation-duration:4.2s">
 <path d="M64 172 78 104c4-22 40-22 44 0l14 68Z" fill="url(#${g}a)" stroke="#06151f" stroke-width="2.5" stroke-linejoin="round"/>
 <path d="M64 172h72" stroke="#e5b64a" stroke-width="5"/><path d="M92 106l-6 66M108 106l6 66" stroke="#e5b64a" stroke-width="2.5" opacity=".8"/>
 <path d="M66 98c-6-52 62-52 68 0-10-12-58-12-68 0Z" fill="url(#${g}b)" stroke="#06151f" stroke-width="2.5" stroke-linejoin="round"/>
 <ellipse cx="100" cy="90" rx="23" ry="17" fill="#06101a"/>
 <ellipse cx="91" cy="90" rx="4" ry="2.6" fill="#9ff6ff" class="sa-eye"/><ellipse cx="109" cy="90" rx="4" ry="2.6" fill="#9ff6ff" class="sa-eye"/>
 <path d="M136 176 144 70" stroke="#6b4423" stroke-width="5.5" stroke-linecap="round"/><path d="M134 140l8-2M136 124l8-2" stroke="#e5b64a" stroke-width="3"/>
 <circle cx="145" cy="58" r="20" fill="url(#${g}c)" class="sa-glow"/>
 <path d="M145 44l4 9 10 1-7 7 2 10-9-5-9 5 2-10-7-7 10-1Z" fill="#ffe27a" stroke="#a86b00" stroke-width="1.6" stroke-linejoin="round"/>
 <path d="M120 120c10 6 18 2 22-6" fill="none" stroke="#124a66" stroke-width="9" stroke-linecap="round"/><circle cx="142" cy="112" r="6" fill="#d9a979"/>
 <path d="M84 132l3 6 6 1-5 4 1 6-5-3-5 3 1-6-5-4 6-1ZM112 148l2 4 4 1-3 3 1 4-4-2-3 2 1-4-3-3 4-1Z" fill="#ffe27a" opacity=".85"/>
</g>`, 'sa-small');
  }
  function sentinel() {
    const g = 'g' + ++K;
    return svg(`<defs>${lin(g + 'a', [[0, '#cdbf9f'], [1, '#7a6a4d']])}${lin(g + 'b', [[0, '#ffe08a'], [1, '#b8800f']])}${rad(g + 'c', [[0, '#fff'], [.35, '#ffd34d'], [1, '#ff8c00', 0]])}${blur(g + 'f', 5)}</defs>
<ellipse cx="100" cy="182" rx="40" ry="6" fill="#000" opacity=".35" class="sa-shadow"/>
<g class="sa-float" style="animation-duration:5s">
 <ellipse cx="100" cy="166" rx="26" ry="9" fill="#ffd34d" opacity=".45" filter="url(#${g}f)" class="sa-glow"/>
 <path d="M80 168 90 146h20l10 22Z" fill="url(#${g}a)" stroke="#3b3120" stroke-width="2.5" stroke-linejoin="round"/>
 <path d="M70 92h60l8 20-6 38H68l-6-38Z" fill="url(#${g}a)" stroke="#3b3120" stroke-width="2.5" stroke-linejoin="round"/>
 <path d="M66 146h68" stroke="url(#${g}b)" stroke-width="7"/><path d="M62 112h76" stroke="url(#${g}b)" stroke-width="5"/>
 <path d="M52 94c-6 6-6 18 0 24l12-4V98ZM148 94c6 6 6 18 0 24l-12-4V98Z" fill="url(#${g}b)" stroke="#3b3120" stroke-width="2.5" stroke-linejoin="round"/>
 <path d="M44 120c-6 12-4 26 2 32l8-4V118ZM156 120c6 12 4 26-2 32l-8-4V118Z" fill="url(#${g}a)" stroke="#3b3120" stroke-width="2.5" stroke-linejoin="round"/>
 <path d="M100 118v22M90 124h20M92 134h16" stroke="#ffd34d" stroke-width="3" stroke-linecap="round" class="sa-glow"/>
 <path d="M76 52h48l8 22-8 18H76l-8-18Z" fill="url(#${g}a)" stroke="#3b3120" stroke-width="2.5" stroke-linejoin="round"/>
 <path d="M84 44 100 24l16 20Z" fill="url(#${g}b)" stroke="#3b3120" stroke-width="2.5" stroke-linejoin="round"/>
 <rect x="80" y="62" width="40" height="22" rx="10" fill="#1d1608"/>
 <circle cx="100" cy="73" r="13" fill="url(#${g}c)" class="sa-eye"/><circle cx="100" cy="73" r="5" fill="#4a2a00"/>
</g>`, 'sa-small');
  }

  /* =============================== FENICI =============================== */
  function phoenix(o) {
    const g = 'g' + ++K, c = o;
    const wing = `<path d="M96 92C72 62 40 48 8 60c20 4 36 14 46 30-14-2-28 4-38 16 20-2 38 2 50 12-10 2-20 8-26 20 22-8 46-10 60-6Z" fill="url(#${g}w)" stroke="${c.edge}" stroke-width="2" stroke-linejoin="round"/>
 <path d="M92 96C74 76 54 68 34 70c14 6 24 14 30 24-10 0-20 4-26 12 14 0 26 4 34 10Z" fill="url(#${g}w2)" opacity=".92"/>
 <path d="M8 60l8-14 4 14ZM18 104l-6 14 12-4ZM34 132l-2 16 12-8Z" fill="${c.tip}" class="sa-flame" style="transform-origin:20px 100px"/>`;
    const tail = [-34, -17, 0, 17, 34].map((a, i) => `<path d="M100 128C92 148 92 166 100 178c8-12 8-30 0-50Z" fill="url(#${g}t)" stroke="${c.edge}" stroke-width="1.4" transform="rotate(${a} 100 128)" class="sa-flame" style="transform-origin:100px 128px;animation-delay:${i * .25}s"/>`).join('');
    return svg(`<defs>${lin(g + 'w', [[0, c.w1], [.6, c.w2], [1, c.w3]], 1, 0, 0, 1)}${lin(g + 'w2', [[0, c.i1], [1, c.i2]], 1, 0, 0, 1)}${lin(g + 't', [[0, c.t1], [.55, c.t2], [1, c.t3, .15]])}${lin(g + 'b', [[0, c.b1], [1, c.b2]])}${rad(g + 'a', [[0, c.glow, .75], [1, c.glow, 0]])}${blur(g + 'f', 3)}</defs>
<circle cx="100" cy="102" r="92" fill="url(#${g}a)" class="sa-glow"/>
${c.halo ? `<ellipse cx="100" cy="30" rx="24" ry="7" fill="none" stroke="#ffe27a" stroke-width="4" class="sa-glow"/><ellipse cx="100" cy="30" rx="24" ry="7" fill="none" stroke="#fff" stroke-width="1.5" opacity=".8"/>` : ''}
<g class="sa-float" style="animation-duration:4s">
 ${tail}
 <g class="sa-wingL" style="transform-origin:96px 92px">${wing}</g>
 <g class="sa-wingR" style="transform-origin:104px 92px"><g transform="translate(200 0) scale(-1 1)">${wing}</g></g>
 <path d="M100 66c-18 4-24 32-20 54 4 14 14 20 20 20s16-6 20-20c4-22-2-50-20-54Z" fill="url(#${g}b)" stroke="${c.edge}" stroke-width="2.2"/>
 <ellipse cx="100" cy="108" rx="11" ry="22" fill="${c.chest}" opacity=".85" class="sa-glow"/>
 <circle cx="100" cy="62" r="16" fill="url(#${g}b)" stroke="${c.edge}" stroke-width="2.2"/>
 <path d="M92 50C88 36 90 24 96 14c0 12 4 20 8 26 2-10 8-18 14-22-2 12-4 22-10 32Z" fill="${c.crest}" class="sa-flame" style="transform-origin:100px 50px"/>
 <path d="M96 66l4 14 4-14Z" fill="#ffc83d" stroke="#8a5a00" stroke-width="1.4" stroke-linejoin="round"/>
 <ellipse cx="93" cy="60" rx="3.6" ry="2.4" fill="${c.eye}" class="sa-eye"/><ellipse cx="107" cy="60" rx="3.6" ry="2.4" fill="${c.eye}" class="sa-eye"/>
 <path d="M90 140l-6 14M110 140l6 14M95 142l-2 16M105 142l2 16" stroke="#ffc83d" stroke-width="3" stroke-linecap="round"/>
</g>${c.sparks ? `<g fill="#fff"><circle class="sa-ember" cx="40" cy="120" r="2"/><circle class="sa-ember" style="animation-delay:.9s" cx="160" cy="110" r="2.4"/><circle class="sa-ember" style="animation-delay:1.7s" cx="120" cy="30" r="1.8"/><circle class="sa-ember" style="animation-delay:.4s" cx="70" cy="30" r="1.8"/></g>` : ''}`, 'sa-wide');
  }
  const phoenixDark = () => phoenix({ w1: '#2a0f4d', w2: '#6d28d9', w3: '#c026d3', i1: '#7e22ce', i2: '#f43f5e', edge: '#12061f', tip: '#f472b6', t1: '#4c1d95', t2: '#c026d3', t3: '#fb7185', b1: '#2e1065', b2: '#0f0420', glow: '#a21caf', chest: '#f472b6', crest: '#f0abfc', eye: '#ffe27a', sparks: true });
  const phoenixCeleste = () => phoenix({ w1: '#ffffff', w2: '#fde68a', w3: '#7dd3fc', i1: '#fff7d1', i2: '#bae6fd', edge: '#a77a14', tip: '#ffe27a', t1: '#fff', t2: '#fcd34d', t3: '#67e8f9', b1: '#fffbea', b2: '#fcd34d', glow: '#fde68a', chest: '#fff', crest: '#ffe27a', eye: '#0ea5e9', halo: true, sparks: true });

  /* =============================== DRAGHI (profilo, rivolti a destra) =============================== */
  function dragon(o) {
    const g = 'g' + ++K, spec = o.kind === 'ghost', ab = o.kind === 'abyss', as = o.kind === 'astral', sh = o.kind === 'shadow';
    const hs = o.headScale || 1;
    const wing = (dx, dy, op, fill) => `<g transform="translate(${dx} ${dy})" opacity="${op}"><path d="M96 102C80 70 60 40 30 20c10 22 10 38 4 52 12-6 20 0 24 12 8-6 18-2 24 8 6 4 10 8 14 10Z" fill="url(#${fill})" stroke="${o.wedge}" stroke-width="2" stroke-linejoin="round"/><path d="M96 102 30 20M96 102 34 72M96 102 58 84" stroke="${o.bone}" stroke-width="2.4" stroke-linecap="round"/></g>`;
    const spikes = [[62, 114, -4], [76, 102, -2], [92, 97, 0], [108, 98, 2], [120, 90, 4], [128, 76, 6]].map(([x, y, r]) => `<path d="M${x} ${y} l-5-12 11 6Z" fill="${o.spine}" stroke="${o.edge}" stroke-width="1.2" transform="rotate(${r} ${x} ${y})"/>`).join('');
    const deco = ab ? `<g class="sa-glow" fill="#7df9ff">${[[70, 128], [84, 120], [98, 118], [112, 120], [92, 136], [76, 140], [118, 100], [128, 84]].map(([x, y], i) => `<circle cx="${x}" cy="${y}" r="${i % 3 ? 2 : 3}" style="animation-delay:${i * .3}s"/>`).join('')}</g><g fill="none" stroke="#a5f3fc" stroke-width="1.6" opacity=".8"><circle class="sa-ember" cx="40" cy="60" r="4"/><circle class="sa-ember" style="animation-delay:1.1s" cx="22" cy="90" r="3"/><circle class="sa-ember" style="animation-delay:2s" cx="52" cy="40" r="2.6"/></g>`
      : as ? `<g fill="#fff">${[[70, 124], [88, 118], [104, 126], [118, 112], [96, 134], [80, 140], [128, 94], [60, 150]].map(([x, y], i) => `<circle class="sa-glow" cx="${x}" cy="${y}" r="${i % 2 ? 1.6 : 2.4}" style="animation-delay:${i * .25}s"/>`).join('')}</g><path d="M70 124 88 118 104 126 118 112M88 118 96 134 80 140" stroke="#c4b5fd" stroke-width="1.2" fill="none" opacity=".8"/><g fill="#fff"><circle class="sa-ember" cx="30" cy="40" r="2"/><circle class="sa-ember" style="animation-delay:1.3s" cx="48" cy="22" r="1.8"/><circle class="sa-ember" style="animation-delay:.6s" cx="20" cy="70" r="2.2"/></g>`
      : sh ? `<g class="sa-smoke" fill="none" stroke="#7c3aed" stroke-width="5" stroke-linecap="round" opacity=".55"><path d="M40 160c-14-12-4-26 8-30M60 168c-10-8-2-20 8-22M130 150c10 8 22 0 18-12"/></g>` : '';
    const wispy = spec ? `<g class="sa-smoke" fill="none" stroke="#bfe9ff" stroke-width="5" stroke-linecap="round" opacity=".5"><path d="M30 164c-12-8-6-22 6-26M48 172c-8-6 0-18 8-18"/></g>` : '';
    const fl = o.flame ? `<g transform="translate(186 64)" class="sa-flame" style="transform-origin:186px 64px">${flame(o.flame[0], 'rotate(-10)', 1.2)}${flame(o.flame[1], 'rotate(4)', .9)}${flame(o.flame[2], 'rotate(-2)', .5)}</g>` : '';
    return svg(`<defs>${lin(g + 'b', [[0, o.b1], [1, o.b2]])}${lin(g + 'w', [[0, o.w1], [1, o.w2]], 1, 0, 0, 1)}${lin(g + 'v', [[0, o.w2], [1, o.w1]], 1, 0, 0, 1)}${rad(g + 'a', [[0, o.glow, .6], [1, o.glow, 0]])}${blur(g + 'f', 4)}</defs>
<circle cx="104" cy="104" r="94" fill="url(#${g}a)" class="sa-glow"/>${deco.indexOf('sa-ember') < 0 ? '' : ''}
<g class="sa-float" style="animation-duration:4.6s">
 ${wispy}
 <g class="sa-wing" style="transform-origin:96px 102px">${wing(10, -8, .82, g + 'v')}</g>
 <path d="M64 126C38 128 20 142 14 166c-2 6 6 6 10 2 6-8 18-12 34-16Z" fill="url(#${g}b)" stroke="${o.edge}" stroke-width="2.2" stroke-linejoin="round" ${spec ? 'opacity=".72"' : ''}/>
 <path d="M14 166l-6 8 12-2Z" fill="${o.spine}" stroke="${o.edge}" stroke-width="1.4"/>
 <path d="M76 142 70 168h20l4-26ZM108 142l-4 26h20l2-26Z" fill="url(#${g}b)" stroke="${o.edge}" stroke-width="2.2" stroke-linejoin="round"/>
 <path d="M70 168l-2 5M76 168l-1 6M84 168l0 6M104 168l-1 6M112 168l0 6M120 168l1 5" stroke="${o.claw}" stroke-width="2.4" stroke-linecap="round"/>
 <ellipse cx="98" cy="124" rx="45" ry="29" fill="url(#${g}b)" stroke="${o.edge}" stroke-width="2.4" ${spec ? 'opacity=".78"' : ''}/>
 <path d="M64 134Q100 160 138 132Q100 148 64 134Z" fill="${o.belly}"/><path d="M76 140q24 8 48 0M82 146q18 5 36 0" stroke="${o.edge}" stroke-width="1.2" fill="none" opacity=".5"/>
 ${spikes}
 <path d="M108 114C126 100 126 80 134 64L156 72C150 88 156 104 140 126Z" fill="url(#${g}b)" stroke="${o.edge}" stroke-width="2.4" stroke-linejoin="round" ${spec ? 'opacity=".8"' : ''}/>
 <g transform="translate(150 60) scale(${hs}) translate(-150 -60)">
  <path d="M136 46C128 28 114 22 104 22c14 8 18 20 26 32Z" fill="${o.horn}" stroke="${o.edge}" stroke-width="1.8" stroke-linejoin="round"/>
  <path d="M146 42C142 28 132 20 124 18c8 10 10 20 16 30Z" fill="${o.horn}" stroke="${o.edge}" stroke-width="1.8" stroke-linejoin="round"/>
  <path d="M128 58C132 42 152 38 166 48L188 58c4 4 2 10-4 12l-16 2c-6 8-22 8-32 0Z" fill="url(#${g}b)" stroke="${o.edge}" stroke-width="2.4" stroke-linejoin="round" ${spec ? 'opacity=".85"' : ''}/>
  <path d="M150 74 184 68c-2 8-14 12-26 12Z" fill="${o.belly}" opacity=".7"/><path d="M168 70l3 6 3-6ZM176 68l2 5 3-5Z" fill="#fff" stroke="${o.edge}" stroke-width=".8"/>
  <circle cx="160" cy="56" r="10" fill="${o.eye}" opacity=".55" filter="url(#${g}f)" class="sa-eye"/><path d="M153 57q7-8 15-2-6 6-15 2Z" fill="${o.eye}" class="sa-eye"/><circle cx="162" cy="55" r="1.6" fill="#fff"/>
  <circle cx="183" cy="60" r="1.6" fill="${o.edge}"/>
 </g>
 ${fl}
 <g class="sa-wing" style="transform-origin:96px 102px;animation-delay:-1.4s">${wing(0, 0, 1, g + 'w')}</g>
 ${deco}
</g>`, 'sa-dragon');
  }

  const P = {
    ebano:   { kind: 'plain', headScale: 1.3, b1: '#34344a', b2: '#0d0d16', belly: '#7a1f2b', w1: '#b3202f', w2: '#3d0a12', wedge: '#12060a', bone: '#0d0d16', horn: '#c9c9d6', eye: '#ff3b3b', glow: '#e11d48', spine: '#7a1f2b', edge: '#08080e', claw: '#d8d8e6', flame: ['#ff9a3d', '#ff4d2e', '#ffd966'] },
    spettrale: { kind: 'ghost', b1: '#e8f8ff', b2: '#7fc4e8', belly: '#ffffff', w1: '#a5ddff', w2: '#e8f8ff', wedge: '#5a9cc0', bone: '#d6f1ff', horn: '#ffffff', eye: '#38bdf8', glow: '#7dd3fc', spine: '#bfe9ff', edge: '#4a8bb0', claw: '#ffffff', flame: ['#bfe9ff', '#7dd3fc', '#ffffff'] },
    abissi:  { kind: 'abyss', b1: '#0e5f86', b2: '#04182c', belly: '#3fd0d8', w1: '#0f8aa8', w2: '#04243e', wedge: '#02111f', bone: '#7df9ff', horn: '#7de8ff', eye: '#7df9ff', glow: '#06b6d4', spine: '#22d3ee', edge: '#02101c', claw: '#a5f3fc' },
    astrale: { kind: 'astral', b1: '#4a3fc2', b2: '#100c3a', belly: '#c4b5fd', w1: '#6d5be0', w2: '#1a1257', wedge: '#0c0830', bone: '#e9e3ff', horn: '#fde68a', eye: '#fff3b0', glow: '#a78bfa', spine: '#fde68a', edge: '#0a0728', claw: '#fde68a', flame: ['#fff3b0', '#c4b5fd', '#ffffff'] },
    ombre:   { kind: 'shadow', b1: '#2b1346', b2: '#07030f', belly: '#4c1d95', w1: '#3b0764', w2: '#0b0314', wedge: '#06020d', bone: '#8b5cf6', horn: '#241036', eye: '#e879f9', glow: '#7e22ce', spine: '#a855f7', edge: '#05020a', claw: '#c084fc', flame: ['#e879f9', '#7c3aed', '#fff'] }
  };

  /* =============================== DRAGO APOCALITTICO (premio finale) =============================== */
  function apocalypse() {
    const g = 'g' + ++K;
    const wing = (id, rim) => `<path d="M150 118L95 30Q56 24 18 14Q44 40 30 76Q60 80 52 118Q84 112 96 140Q126 128 150 118Z" fill="url(#${g}${id})" stroke="#05010c" stroke-width="2.6" stroke-linejoin="round"/>
   <path d="M95 30 18 14M95 30 30 76M95 30 52 118M95 30 96 140M150 118 95 30" stroke="#0c0416" stroke-width="5.5" stroke-linecap="round"/>
   <path d="M95 30 18 14M95 30 30 76M95 30 52 118M95 30 96 140M150 118 95 30" stroke="${rim}" stroke-width="1.5" stroke-linecap="round" opacity=".95"/>
   <path d="M95 30l-10-14 16 8Z" fill="#0c0416" stroke="${rim}" stroke-width="1.4"/>
   <path d="M18 14l-8-8 14 4ZM30 76l-10-4 12-4ZM52 118l-10 0 10-8ZM96 140l-6 8 10-4Z" fill="#0c0416" stroke="${rim}" stroke-width="1.2"/>`;
    const ridge = [[104, 106, -22], [122, 98, -14], [140, 94, -6], [158, 94, 4], [176, 98, 12], [194, 104, 20]].map(([x, y, r], i) => `<path d="M${x - 9} ${y + 6} L${x} ${y - 26 + i % 2 * 5} L${x + 9} ${y + 6}Z" fill="#0f0820" stroke="#c026d3" stroke-width="1.8" stroke-linejoin="round" transform="rotate(${r} ${x} ${y + 6})"/><path d="M${x} ${y - 20 + i % 2 * 5} L${x} ${y}" stroke="#ff2e63" stroke-width="1.5" opacity=".9" transform="rotate(${r} ${x} ${y + 6})"/>`).join('');
    const tailSp = [[82, 168, -30], [60, 176, -40], [42, 188, -52]].map(([x, y, r]) => `<path d="M${x - 6} ${y} L${x} ${y - 16} L${x + 6} ${y}Z" fill="#0f0820" stroke="#c026d3" stroke-width="1.5" transform="rotate(${r} ${x} ${y})"/>`).join('');
    const plates = [0, 1, 2, 3, 4, 5].map(i => `<path d="M${108 + i * 20} 184 Q${112 + i * 20} 160 ${124 + i * 20} 150" fill="none" stroke="#7c3aed" stroke-width="2.2" opacity=".9"/>`).join('');
    const embers = [[40, 150, 0], [300, 160, .8], [356, 120, 1.4], [26, 100, .3], [210, 18, 1.1], [120, 12, 1.9], [340, 40, .6], [70, 60, 2.2]].map(([x, y, d]) => `<circle class="sa-ember" cx="${x}" cy="${y}" r="2.6" fill="#ff7a59" style="animation-delay:${d}s"/>`).join('');
    return svg(`<defs>
${lin(g + 'b', [[0, '#35305a'], [.45, '#120e24'], [1, '#04030a']])}
${lin(g + 'm', [[0, '#d11a4a'], [.5, '#5a0f45'], [1, '#14041f']], 1, 0, 0, 1)}${lin(g + 'n', [[0, '#7c2bd9'], [.5, '#3a0b5c'], [1, '#0e0418']], 1, 0, 0, 1)}
${rad(g + 'a', [[0, '#ff2e63', .5], [.45, '#a21caf', .3], [1, '#4c1d95', 0]], .5, .5, .5)}${rad(g + 'e', [[0, '#fff', 1], [.3, '#ffb347', .95], [1, '#ff2e2e', 0]])}
${lin(g + 'f', [[0, '#fff3b0'], [.3, '#ff9a30'], [.62, '#e11d48'], [1, '#7e22ce']], 0, 0, 1, 0)}${lin(g + 'g', [[0, '#ff4d6d', .95], [1, '#7c3aed', .1]], 0, 0, 1, 0)}
${blur(g + 'f1', 6)}${blur(g + 'f2', 2.4)}
</defs>
<ellipse cx="190" cy="120" rx="190" ry="118" fill="url(#${g}a)" class="sa-glow"/>
<ellipse cx="170" cy="222" rx="110" ry="9" fill="#000" opacity=".5"/>
<g class="sa-float" style="animation-duration:5.4s">
 <g class="sa-wing" style="transform-origin:150px 118px;animation-delay:-1.6s"><g transform="translate(46 -16) scale(.92)" opacity=".95">${wing('n', '#a855f7')}</g></g>
 <g class="sa-wing" style="transform-origin:150px 118px">${wing('m', '#ff5a8a')}</g>
 <path d="M104 150C74 154 42 168 20 196c-6 8 2 12 8 8 22-16 46-20 78-20Z" fill="url(#${g}b)" stroke="#05010c" stroke-width="2.6" stroke-linejoin="round"/>
 <path d="M20 196 6 214l26-8Z" fill="#0f0820" stroke="#d946ef" stroke-width="2" stroke-linejoin="round"/>${tailSp}
 <path d="M132 188 126 218H162L166 190ZM176 188 176 218h36l-2-30Z" fill="url(#${g}b)" stroke="#05010c" stroke-width="2.6" stroke-linejoin="round"/>
 <path d="M126 218l-6 6 12-2ZM138 218l-3 7 9-4ZM152 218l0 7 8-5ZM178 218l-6 6 12-2ZM190 218l-2 7 9-4ZM204 218l1 7 8-5Z" fill="#d9ccff" stroke="#05010c" stroke-width="1.2" stroke-linejoin="round"/>
 <path d="M96 150C96 112 130 100 168 102C210 104 238 124 232 156C226 184 196 194 152 194C116 194 96 178 96 150Z" fill="url(#${g}b)" stroke="#05010c" stroke-width="2.8"/>
 <path d="M100 160C100 130 130 112 168 110C206 110 228 128 226 152" fill="none" stroke="#7c3aed" stroke-width="2" opacity=".75"/>
 ${plates}
 <path d="M104 170Q150 202 224 164" fill="none" stroke="#ff2e63" stroke-width="2.4" class="sa-glow"/><path d="M118 134l14 10-6 12M168 124l-6 16 16 8M196 138l12-8" stroke="#ff7a30" stroke-width="2.2" fill="none" class="sa-glow"/>
 <ellipse cx="128" cy="168" rx="32" ry="30" fill="url(#${g}b)" stroke="#05010c" stroke-width="2.6"/><path d="M104 160Q128 138 152 162" fill="none" stroke="#a855f7" stroke-width="2"/>
 ${ridge}
 <path d="M168 128 l8-18 8 14 12-14 4 20Z" fill="#0f0820" stroke="#c026d3" stroke-width="1.8" stroke-linejoin="round"/>
 <path d="M196 116C226 104 230 84 232 64L270 82C262 108 268 134 238 164Z" fill="url(#${g}b)" stroke="#05010c" stroke-width="2.8" stroke-linejoin="round"/>
 <path d="M222 118 246 108M226 102l24-12M230 86l24-12" stroke="#7c3aed" stroke-width="3" stroke-linecap="round"/>
 <path d="M232 66C220 36 192 14 160 8c24 14 36 34 48 62Z" fill="#150b26" stroke="#d946ef" stroke-width="2.4" stroke-linejoin="round"/><path d="M160 8c20 12 34 26 44 46" stroke="#ff2e63" stroke-width="2" fill="none"/>
 <path d="M250 56C242 24 220 4 190 -4c22 14 30 34 38 64Z" fill="#150b26" stroke="#d946ef" stroke-width="2.4" stroke-linejoin="round"/><path d="M190 -4c18 12 30 28 36 44" stroke="#ff2e63" stroke-width="1.8" fill="none"/>
 <path d="M296 52 316 24 314 58Z" fill="#150b26" stroke="#d946ef" stroke-width="2" stroke-linejoin="round"/>
 <path d="M236 82 214 92 240 92ZM244 94 224 108 250 100Z" fill="#150b26" stroke="#d946ef" stroke-width="1.8" stroke-linejoin="round"/>
 <path d="M246 100 316 94C312 112 278 116 254 108Z" fill="url(#${g}b)" stroke="#05010c" stroke-width="2.6" stroke-linejoin="round"/>
 <path d="M254 96 314 86 316 94 250 100Z" fill="#4a0a22"/><path d="M262 98l4 9 4-10ZM280 94l4 10 4-12ZM298 92l3 8 3-10Z" fill="#fff" stroke="#05010c" stroke-width=".9"/>
 <path d="M228 60C234 38 262 32 292 44L328 60C338 66 336 76 326 78L302 80C290 94 258 94 240 82Z" fill="url(#${g}b)" stroke="#05010c" stroke-width="2.8" stroke-linejoin="round"/>
 <path d="M244 50 L298 42l-2 8-46 10Z" fill="#0b0716" stroke="#a855f7" stroke-width="1.4" stroke-linejoin="round"/><path d="M262 70l36-2M246 72l8 6" stroke="#7c3aed" stroke-width="2" stroke-linecap="round"/>
 <path d="M300 70l4 10 5-9Z" fill="#fff" stroke="#05010c" stroke-width=".9"/><path d="M312 70l3 8 5-7Z" fill="#fff" stroke="#05010c" stroke-width=".9"/><circle cx="322" cy="62" r="2" fill="#05010c"/>
 <circle cx="262" cy="60" r="16" fill="url(#${g}e)" filter="url(#${g}f1)" class="sa-eye"/>
 <path d="M248 60Q262 46 282 56 268 70 248 60Z" fill="#ff6a1f" stroke="#fff3b0" stroke-width="1.5" class="sa-eye"/><path d="M262 52v14" stroke="#05010c" stroke-width="3.2" stroke-linecap="round"/>
 <g class="sa-flame" style="transform-origin:318px 84px"><g transform="translate(318 84) scale(1.3)">
   <path d="M0 -6C14 -30 44 -38 62 -30 54 -24 66 -18 60 -10 76 -8 70 4 82 10 68 14 70 22 58 28 40 34 12 22 0 6Z" fill="url(#${g}g)" filter="url(#${g}f2)"/>
   <path d="M0 -4C12 -22 36 -28 52 -20 44 -14 56 -8 50 -2 62 2 54 12 62 16 44 20 20 16 0 6Z" fill="url(#${g}f)"/>
   <path d="M0 -1C10 -10 26 -12 36 -8 30 -4 38 0 30 4 36 8 24 10 0 4Z" fill="#fff3b0"/>
 </g></g>
 <g class="sa-flame" style="transform-origin:318px 84px;animation-delay:-.6s"><path d="M388 70c-10-6-16-20-8-32 4 12 12 14 16 22Z" fill="#c026d3" opacity=".8" transform="translate(-24 16)"/><path d="M360 96c14-4 30-2 42 8-14-2-22 2-30 8Z" fill="#e11d48" opacity=".8"/><path d="M372 56c12-10 28-12 40-6-12 0-20 4-26 12Z" fill="#a855f7" opacity=".85"/></g>
</g>
${embers}`, 'sa-boss', '-10 -16 440 252');
  }

  /* =============================== EMBLEMI (40×40) =============================== */
  const EMB = {
    emblema_carta: ['#c8d0dc', '<rect x="9" y="5" width="22" height="30" rx="3"/><path d="M20 12l5 8-5 8-5-8Z" fill="currentColor" fill-opacity=".35"/>'],
    emblema_stella: ['#c8d0dc', '<path d="M20 5l4.6 10 10.4 1-8 7.2 2.4 10.6L20 28l-9.4 5.8L13 23.2 5 16l10.4-1Z" fill="currentColor" fill-opacity=".3"/>'],
    emblema_teschio: ['#6fb7ff', '<path d="M20 5c-8 0-13 5-13 12 0 4 2 7 5 9v7h4v-3h2v3h4v-3h2v3h4v-7c3-2 5-5 5-9 0-7-5-12-13-12Z"/><circle cx="14.5" cy="18" r="3" fill="currentColor"/><circle cx="25.5" cy="18" r="3" fill="currentColor"/><path d="M20 22l-2 4h4Z" fill="currentColor"/>'],
    emblema_occhio_arcano: ['#c58cff', '<path d="M20 4 37 33H3Z" fill="currentColor" fill-opacity=".18"/><path d="M8 22s5-7 12-7 12 7 12 7-5 7-12 7-12-7-12-7Z"/><circle cx="20" cy="22" r="3.6" fill="currentColor"/>'],
    emblema_corona: ['#ffbf3a', '<path d="M5 29l3-16 7 7 5-11 5 11 7-7 3 16Z" fill="currentColor" fill-opacity=".3"/><path d="M5 33h30"/><circle cx="8" cy="13" r="2" fill="currentColor"/><circle cx="20" cy="9" r="2" fill="currentColor"/><circle cx="32" cy="13" r="2" fill="currentColor"/>']
  };
  function emblem(asset, rar) {
    if (isX(asset)) return `<span class="tde xe ${rar || ''}" role="img" aria-hidden="true">${xsvg(asset)}</span>`;
    const e = EMB[asset] || ['#c8d0dc', '<circle cx="20" cy="20" r="10"/>'], g = 'g' + ++K;
    return `<svg class="tde ${rar || ''}" viewBox="0 0 40 40" role="img" aria-hidden="true" focusable="false"><defs>${lin(g, [[0, '#fff'], [1, e[0]]])}</defs><g color="${e[0]}" fill="none" stroke="url(#${g})" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">${e[1]}</g></svg>`;
  }

  /* =============================== ARTE PER CHIAVE =============================== */
  const ART = {
    pet_gelatina: slime, pet_fantasmino: ghost, pet_apprendista_ombra: mage, pet_sentinella_millenaria: sentinel,
    pet_draghetto_ebano: () => dragon(P.ebano), pet_drago_spettrale: () => dragon(P.spettrale), pet_drago_abissi: () => dragon(P.abissi),
    pet_drago_astrale: () => dragon(P.astrale), pet_drago_ombre_eterne: () => dragon(P.ombre),
    pet_fenice_oscura: phoenixDark, pet_fenice_celestiale: phoenixCeleste, pet_drago_apocalittico: apocalypse
  };
  const ASSETS = {
    pet: Object.keys(ART),
    title: ['titolo_novizio', 'titolo_notturno', 'titolo_collezionista', 'titolo_cacciatore', 'titolo_signore_ombre', 'titolo_leggenda', 'titolo_sovrano_apocalisse'],
    frame: ['cornice_pietra', 'cornice_bronzo', 'cornice_runica', 'cornice_neon', 'cornice_fiamma', 'cornice_aurea_regale', 'cornice_eclissi'],
    aura: ['aura_bagliore', 'aura_ciano', 'aura_vortice_viola', 'aura_sole_dorato', 'aura_eclissi'],
    emblem: Object.keys(EMB),
    effect: ['fx_scintille', 'fx_luce_pulsante', 'fx_braci']
  };
  const BIG = { pet_drago_apocalittico: 1 };
  const pet = (asset, px) => {
    const f = ART[asset];
    return `<span class="tds-petbox${BIG[asset] ? ' boss' : ''}" style="--ps:${px || 110}px">${f ? f() : isX(asset) ? xsvg(asset) : ''}</span>`;
  };

  /* =============================== CSS =============================== */
  const CSS = `
.tdp{width:100%;height:100%;display:block;overflow:visible}.tdp *{transform-box:view-box}
.tds-petbox{display:inline-block;width:var(--ps,110px);height:var(--ps,110px);flex:none;position:relative}.tds-petbox.boss{width:calc(var(--ps,110px)*2.1);height:calc(var(--ps,110px)*1.2)}
.tds-petbox.boss::after{content:"";position:absolute;inset:-4% -6%;background:radial-gradient(closest-side,rgba(255,46,99,.28),transparent 70%);z-index:-1;animation:sapulse 3s ease-in-out infinite}
@keyframes safloat{50%{transform:translateY(-5px)}}@keyframes sabounce{0%,100%{transform:scale(1,1)}45%{transform:scale(1.05,.93)}70%{transform:scale(.97,1.05)}}
@keyframes sapulse{50%{opacity:.55}}@keyframes saeye{0%,100%{opacity:.85}50%{opacity:1;filter:brightness(1.5)}}
@keyframes saflame{0%,100%{transform:scale(1,1)}33%{transform:scale(1.05,.92) skewX(2deg)}66%{transform:scale(.96,1.08) skewX(-2deg)}}
@keyframes sawing{0%,100%{transform:rotate(0)}50%{transform:rotate(-3.2deg)}}@keyframes sawingL{50%{transform:rotate(3deg)}}@keyframes sawingR{50%{transform:rotate(-3deg)}}
@keyframes saember{0%{transform:translateY(0);opacity:0}15%{opacity:1}100%{transform:translateY(-34px);opacity:0}}@keyframes sasmoke{50%{transform:translateY(-4px);opacity:.25}}
.sa-float{animation:safloat 3.6s ease-in-out infinite}.sa-bounce{animation:sabounce 2.2s ease-in-out infinite}.sa-eye{animation:saeye 2.4s ease-in-out infinite}.sa-glow{animation:sapulse 3.2s ease-in-out infinite}
.sa-flame{animation:saflame 1.3s ease-in-out infinite}.sa-wing{animation:sawing 2.6s ease-in-out infinite}.sa-wingL{animation:sawingL 2.4s ease-in-out infinite}.sa-wingR{animation:sawingR 2.4s ease-in-out infinite}
.sa-ember{animation:saember 3s ease-out infinite}.sa-smoke{animation:sasmoke 3.4s ease-in-out infinite}.sa-shadow{opacity:.3}
[data-fx=off] .tdp *,[data-fx=off] .tds-head *,[data-fx=off] .tds-head::before,[data-fx=off] .tds-head::after,[data-fx=off] .tds-av::before,[data-fx=off] .tds-av::after,[data-fx=off] .tds-petbox::after,[data-fx=off] .sh-fx *{animation:none!important}
@media(prefers-reduced-motion:reduce){.tdp *,.tds-head,.tds-head *,.tds-head::before,.tds-head::after,.tds-av::before,.tds-av::after,.tds-petbox::after,.sh-fx *{animation:none!important}}

/* intestazione del profilo */
.tds-head{display:flex;gap:16px;align-items:center;flex-wrap:wrap;position:relative;isolation:isolate;min-width:0}
.tds-head.has-au,.tds-head.has-fx{padding:16px;border-radius:16px}
.tds-av{position:relative;display:inline-block;flex:none;border-radius:50%;--rw:6px;margin:8px}
.tds-av::before{content:"";position:absolute;inset:calc(var(--rw)*-1 - 2px);border-radius:50%;pointer-events:none}
.tds-id{min-width:0;flex:1 1 180px}.tds-id h1,.tds-id h2{display:flex;align-items:center;gap:8px;flex-wrap:wrap;overflow-wrap:anywhere}
.tds-id .tde{width:30px;height:30px;flex:none;filter:drop-shadow(0 0 4px rgba(255,255,255,.25))}
.tds-tags{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:6px}
.tds-pet{margin-left:auto;display:grid;place-items:center;flex:none;max-width:100%}
@media(max-width:560px){.tds-pet{margin:0 auto}}
.tds-title{display:inline-block;margin-top:4px;font:700 .95rem var(--disp,serif);letter-spacing:.06em;text-transform:uppercase}
.tt-common{color:#b5bfcc}.tt-rare{color:#6fb7ff;text-shadow:0 0 10px rgba(74,163,255,.45)}.tt-epic{color:#c58cff;text-shadow:0 0 12px rgba(180,107,255,.55)}
.tt-legendary{background:linear-gradient(90deg,#ffe27a,#ff9d2e,#ffe27a);background-size:200% 100%;-webkit-background-clip:text;background-clip:text;color:transparent;animation:tdsshine 4s linear infinite;filter:drop-shadow(0 0 6px rgba(255,176,46,.5))}
.tt-mythic{background:linear-gradient(90deg,#ff3d6e,#c026d3,#ffb347,#ff3d6e);background-size:250% 100%;-webkit-background-clip:text;background-clip:text;color:transparent;animation:tdsshine 3s linear infinite;filter:drop-shadow(0 0 8px rgba(255,61,110,.6))}
@keyframes tdsshine{to{background-position:200% 0}}@keyframes tdsspin{to{transform:rotate(360deg)}}@keyframes tdsrise{to{background-position:0 -240px}}@keyframes tdsrise2{to{background-position:0 -320px}}@keyframes tdspulse{50%{opacity:.45}}
[data-fx=off] .tt-legendary,[data-fx=off] .tt-mythic{animation:none}

/* cornici dell'avatar */
.fr-cornice_pietra::before{background:repeating-conic-gradient(#8b8f96 0 14deg,#5d6168 14deg 28deg,#a1a5ab 28deg 40deg);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 2px),#000 calc(100% - var(--rw) - 1px));mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 2px),#000 calc(100% - var(--rw) - 1px));box-shadow:0 0 0 1px #2c2f35}
.fr-cornice_bronzo::before{background:conic-gradient(#f0b27a,#8a4b1f,#f6c797,#7a3f18,#f0b27a);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 2px),#000 calc(100% - var(--rw) - 1px));mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 2px),#000 calc(100% - var(--rw) - 1px));filter:drop-shadow(0 0 4px rgba(214,125,48,.5))}
.fr-cornice_runica::before{background:repeating-conic-gradient(#e8eef7 0 6deg,#55657c 6deg 12deg,#aebbd0 12deg 22deg);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 3px),#000 calc(100% - var(--rw) - 2px));mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 3px),#000 calc(100% - var(--rw) - 2px));filter:drop-shadow(0 0 5px rgba(190,205,225,.6))}
.fr-cornice_neon::before{border:3px solid #7df9ff;box-shadow:0 0 10px #00e5ff,0 0 24px rgba(0,229,255,.7),inset 0 0 10px rgba(0,229,255,.7);animation:tdspulse 2s ease-in-out infinite}
.fr-cornice_fiamma::before{inset:calc(var(--rw)*-1 - 5px);background:conic-gradient(#ffe27a,#ff7a1f,#e11d48,#ff7a1f,#ffe27a,#ff9d2e,#e11d48,#ffe27a);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 4px),#000 calc(100% - var(--rw) - 3px));mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 4px),#000 calc(100% - var(--rw) - 3px));animation:tdsspin 5s linear infinite;filter:drop-shadow(0 0 8px rgba(255,122,31,.9)) blur(.3px)}
.fr-cornice_aurea_regale::before{inset:calc(var(--rw)*-1 - 4px);background:conic-gradient(#fff3b0,#e0a21a,#fff3b0,#b8800f,#ffe27a,#d99a12,#fff3b0);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 4px),#000 calc(100% - var(--rw) - 3px));mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 4px),#000 calc(100% - var(--rw) - 3px));filter:drop-shadow(0 0 7px rgba(255,200,60,.8));animation:tdsspin 9s linear infinite}
.fr-cornice_aurea_regale::after{content:"";position:absolute;inset:-12px;border-radius:50%;pointer-events:none;background:conic-gradient(from 0deg,#e8302d 0 6deg,transparent 6deg 90deg,#3b82f6 90deg 96deg,transparent 96deg 180deg,#22c55e 180deg 186deg,transparent 186deg 270deg,#c026d3 270deg 276deg,transparent 276deg);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - 7px),#000 calc(100% - 6px));mask:radial-gradient(farthest-side,transparent calc(100% - 7px),#000 calc(100% - 6px))}
.fr-cornice_eclissi::before{inset:calc(var(--rw)*-1 - 7px);background:conic-gradient(#ff2e63,#7c3aed,#ff7a30,#c026d3,#ff2e63,#7c3aed,#ff2e63);-webkit-mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 6px),#000 calc(100% - var(--rw) - 5px));mask:radial-gradient(farthest-side,transparent calc(100% - var(--rw) - 6px),#000 calc(100% - var(--rw) - 5px));animation:tdsspin 7s linear infinite;filter:drop-shadow(0 0 10px rgba(255,46,99,.9)) drop-shadow(0 0 18px rgba(124,58,237,.7))}
.fr-cornice_eclissi::after{content:"";position:absolute;inset:calc(var(--rw)*-1 - 2px);border-radius:50%;border:4px solid #05010a;pointer-events:none}

/* aure del profilo */
.au-aura_bagliore{box-shadow:0 0 22px rgba(255,255,255,.22),inset 0 0 18px rgba(255,255,255,.07);background:radial-gradient(120% 120% at 20% 0%,rgba(255,255,255,.08),transparent 60%)}
.au-aura_ciano{box-shadow:0 0 26px rgba(0,229,255,.45),inset 0 0 26px rgba(0,229,255,.15);background:radial-gradient(120% 120% at 20% 0%,rgba(0,229,255,.16),transparent 60%);outline:1px solid rgba(125,249,255,.45)}
.au-aura_vortice_viola::before{content:"";position:absolute;inset:-3px;z-index:-1;border-radius:19px;background:conic-gradient(from 0deg,#7c3aed,#d946ef,#4c1d95,#a855f7,#7c3aed);animation:tdsspin 6s linear infinite;filter:blur(3px);opacity:.9}
.au-aura_vortice_viola::after{content:"";position:absolute;inset:1px;z-index:-1;border-radius:15px;background:#0d0818}
.au-aura_sole_dorato{background:radial-gradient(circle at 18% 30%,rgba(255,226,122,.28),transparent 55%),repeating-conic-gradient(from 0deg at 18% 30%,rgba(255,200,60,.14) 0 6deg,transparent 6deg 18deg);box-shadow:0 0 30px rgba(255,200,60,.45),inset 0 0 24px rgba(255,200,60,.18);outline:1px solid rgba(255,200,60,.6)}
.au-aura_eclissi{background:radial-gradient(circle at 18% 40%,#000 0 28%,rgba(255,46,99,.55) 34%,transparent 60%),radial-gradient(120% 100% at 100% 100%,rgba(124,58,237,.35),transparent 60%);box-shadow:0 0 34px rgba(255,46,99,.55),0 0 60px rgba(124,58,237,.4),inset 0 0 30px rgba(255,46,99,.25);outline:1px solid rgba(255,61,110,.7)}
.au-aura_eclissi::before{content:"";position:absolute;inset:0;border-radius:inherit;z-index:-1;box-shadow:inset 0 0 40px rgba(255,46,99,.35);animation:tdspulse 3.4s ease-in-out infinite}

/* effetti */
.fx-fx_scintille::after,.fx-fx_luce_pulsante::after,.fx-fx_braci::after{content:"";position:absolute;inset:0;border-radius:inherit;pointer-events:none;z-index:2}
.fx-fx_scintille::after{background-image:radial-gradient(2px 2px at 12% 90%,#ffe27a 50%,transparent 52%),radial-gradient(1.6px 1.6px at 34% 100%,#fff3b0 50%,transparent 52%),radial-gradient(2px 2px at 58% 96%,#ffd34d 50%,transparent 52%),radial-gradient(1.6px 1.6px at 78% 100%,#fff 50%,transparent 52%),radial-gradient(2px 2px at 92% 92%,#ffe27a 50%,transparent 52%);background-size:100% 120px;background-repeat:repeat-y;animation:tdsrise 5s linear infinite}
.fx-fx_luce_pulsante::after{background:radial-gradient(70% 90% at 50% 50%,rgba(125,249,255,.22),transparent 70%);animation:tdspulse 3.2s ease-in-out infinite;box-shadow:inset 0 0 30px rgba(0,229,255,.25)}
.fx-fx_braci::after{background-image:radial-gradient(2.4px 2.4px at 8% 96%,#ff7a30 50%,transparent 52%),radial-gradient(2px 2px at 24% 100%,#ffb347 50%,transparent 52%),radial-gradient(2.6px 2.6px at 44% 94%,#ff4d2e 50%,transparent 52%),radial-gradient(2px 2px at 62% 100%,#ffcf6a 50%,transparent 52%),radial-gradient(2.4px 2.4px at 80% 96%,#ff6a2a 50%,transparent 52%),radial-gradient(2px 2px at 94% 100%,#ffb347 50%,transparent 52%);background-size:100% 150px;background-repeat:repeat-y;animation:tdsrise2 4s linear infinite;filter:drop-shadow(0 0 4px rgba(255,90,40,.8))}

/* premi aggiuntivi: cornici, aure, effetti (disegni 120×120 posti sopra/sotto l'avatar o sull'intestazione) */
.tde.xe{display:inline-block}.tde.xe .xa{width:100%;height:100%}
.tds-av.fr-x{margin:26px}.tds-xf{position:absolute;inset:-21%;pointer-events:none;z-index:2}.tds-xa{position:absolute;inset:-85%;pointer-events:none;z-index:-1}
.sh-avw{position:relative;display:inline-block;flex:none}
.au-x{overflow:hidden;background:radial-gradient(120% 120% at 20% 0%,rgba(var(--aur,255,255,255),.15),transparent 60%);box-shadow:0 0 26px rgba(var(--aur,255,255,255),.38),inset 0 0 22px rgba(var(--aur,255,255,255),.12);outline:1px solid rgba(var(--aur,255,255,255),.4)}
.au-xa_singolarita{outline-color:rgba(245,158,11,.75);box-shadow:0 0 34px rgba(245,158,11,.5),0 0 60px rgba(126,34,206,.4),inset 0 0 26px rgba(126,34,206,.25)}
.tds-xfx{position:absolute;inset:0;z-index:2;overflow:hidden;border-radius:inherit;pointer-events:none;display:flex;justify-content:space-around}
.tds-xfx span{flex:0 0 auto;height:100%;aspect-ratio:1/1;display:block}.tds-xfx span:nth-child(even){transform:scaleX(-1)}
.tds-title.tds-xt{text-transform:none;letter-spacing:0}
.tt-divine{background:linear-gradient(90deg,#22d3ee,#a78bfa,#f472b6,#fde68a,#22d3ee);background-size:300% 100%;-webkit-background-clip:text;background-clip:text;color:transparent;animation:tdsshine 3s linear infinite;filter:drop-shadow(0 0 8px rgba(125,249,255,.6))}
[data-fx=off] .tt-divine,[data-fx=off] .xt{animation:none!important}
[data-fx=off] .xa,[data-fx=off] .xa *{animation:none!important}[data-fx=off] .xa .tw{opacity:.8;transform:none}
[data-fx=off] .xa .fall:nth-child(3n+1){transform:translateY(26px)}[data-fx=off] .xa .fall:nth-child(3n+2){transform:translateY(64px)}[data-fx=off] .xa .fall:nth-child(3n){transform:translateY(100px)}

/* emblemi e anteprime nello Shop */
.sh-pv{display:grid;place-items:center;min-height:150px;border-radius:12px;background:radial-gradient(90% 90% at 50% 30%,rgba(255,255,255,.07),rgba(0,0,0,.35));border:1px solid rgba(255,255,255,.06);position:relative;overflow:hidden;padding:12px}
.sh-pv .tds-petbox{--ps:118px}.sh-pv .tde{width:76px;height:76px}.sh-pv .tds-title{font-size:1.15rem;margin:0}
.sh-mini{position:relative;border-radius:14px;padding:14px;display:flex;align-items:center;gap:10px;isolation:isolate;min-width:150px}
.sh-av{width:54px;height:54px;border-radius:50%;display:grid;place-items:center;background:#1c1c22;border:1px solid #d4a843;font:600 1.4rem var(--disp,serif);color:#ece7db}
.sh-nick{font:700 1rem var(--disp,serif)}
`;

  function init() {
    if (document.getElementById('tdsCss')) return;
    const s = document.createElement('style'); s.id = 'tdsCss'; s.textContent = CSS; document.head.appendChild(s);
    if (X()) {
      try { X().init() } catch (e) { }
      X().items.forEach(it => { const a = ASSETS[it.cat]; if (a && a.indexOf(it.key) < 0) a.push(it.key) });
    }
    let fx = 'on'; try { fx = localStorage.getItem('tempio.fx') || 'on'; } catch (e) { }
    document.documentElement.setAttribute('data-fx', fx);
  }
  function setFx(on) { try { localStorage.setItem('tempio.fx', on ? 'on' : 'off'); } catch (e) { } document.documentElement.setAttribute('data-fx', on ? 'on' : 'off'); }
  const fxOn = () => document.documentElement.getAttribute('data-fx') !== 'off';

  /* equipaggiamento: da righe di shop_equipped_v a {categoria: riga} */
  const eqMap = rows => { const m = {}; (rows || []).forEach(r => { m[r.category] = r; }); return m; };

  /* Intestazione del profilo con tutto ciò che è equipaggiato.
     o: {avatar: html, tag: html, extra: html, h: 'h1'|'h2', hcls, petSize} */
  function head(p, eq, o) {
    o = o || {}; eq = eq || {};
    const h = o.h || 'h2', ps = o.petSize || 104;
    const ax = !!(eq.aura && isX(eq.aura.asset)), fx = !!(eq.effect && isX(eq.effect.asset)), frx = !!(eq.frame && isX(eq.frame.asset));
    const cls = ['tds-head', eq.aura ? 'has-au au-' + eq.aura.asset + (ax ? ' au-x' : '') : '', eq.effect ? 'has-fx fx-' + eq.effect.asset + (fx ? ' fx-x' : '') : ''].join(' ');
    const style = ax ? ` style="--aur:${AUR[eq.aura.asset] || '255,255,255'}"` : '';
    const title = eq.title ? (isX(eq.title.asset)
      ? `<div><span class="tds-title tds-xt" title="${esc(eq.title.name)}">${X().title(eq.title.asset, eq.title.name)}</span></div>`
      : `<div><span class="tds-title tt-${eq.title.rarity} tt-${eq.title.asset}" title="${esc(eq.title.name)}">${esc(eq.title.name)}</span></div>`) : '';
    const emb = eq.emblem ? emblem(eq.emblem.asset, eq.emblem.rarity) : '';
    const avIn = `${ax ? `<span class="tds-xa" aria-hidden="true">${xsvg(eq.aura.asset)}</span>` : ''}${o.avatar || ''}${frx ? `<span class="tds-xf" aria-hidden="true">${xsvg(eq.frame.asset)}</span>` : ''}`;
    return `<div class="${cls}"${style}><div class="tds-av ${eq.frame ? 'fr-' + eq.frame.asset : ''}${frx ? ' fr-x' : ''}">${avIn}</div>
<div class="tds-id"><${h} class="${o.hcls || ''}"><span>${esc(p.nickname)}</span>${emb}</${h}>${title}<div class="tds-tags">${o.tag || ''}</div>${o.extra || ''}</div>${eq.pet ? `<div class="tds-pet" title="${esc(eq.pet.name)}">${pet(eq.pet.asset, ps)}</div>` : ''}${fx ? fxLayer(eq.effect.asset) : ''}</div>`;
  }
  const fxLayer = a => `<div class="tds-xfx" aria-hidden="true">${[0, 1, 2, 3, 4].map(() => `<span>${xsvg(a)}</span>`).join('')}</div>`;

  /* Anteprima di un premio del catalogo */
  function preview(it) {
    const a = it.asset, c = it.category, x = isX(a);
    if (c === 'pet') return `<div class="sh-pv">${pet(a, 118)}</div>`;
    if (c === 'emblem') return `<div class="sh-pv">${emblem(a, it.rarity)}</div>`;
    if (c === 'title') return x ? `<div class="sh-pv"><span class="tds-title tds-xt">${X().title(a, it.name)}</span></div>` : `<div class="sh-pv"><span class="tds-title tt-${it.rarity} tt-${a}">${esc(it.name)}</span></div>`;
    const av = '<div class="sh-av">M</div>';
    if (c === 'frame') return `<div class="sh-pv"><div class="tds-av fr-${a}${x ? ' fr-x' : ''}" style="margin:${x ? 26 : 14}px">${av}${x ? `<span class="tds-xf" aria-hidden="true">${xsvg(a)}</span>` : ''}</div></div>`;
    if (c === 'aura') return x
      ? `<div class="sh-pv"><div class="sh-mini au-x au-${a}" style="--aur:${AUR[a] || '255,255,255'}"><span class="sh-avw"><span class="tds-xa" aria-hidden="true">${xsvg(a)}</span>${av}</span><span class="sh-nick">Marco</span></div></div>`
      : `<div class="sh-pv"><div class="sh-mini au-${a}">${av}<span class="sh-nick">Marco</span></div></div>`;
    return `<div class="sh-pv"><div class="sh-mini fx-${a}${x ? ' fx-x' : ''}" style="background:rgba(255,255,255,.03)">${av}<span class="sh-nick">Marco</span>${x ? fxLayer(a) : ''}</div></div>`;
  }

  window.TDS = { init, setFx, fxOn, RAR, RARS, CATS, CATN, ASSETS, pet, emblem, head, preview, eqMap };
})();
