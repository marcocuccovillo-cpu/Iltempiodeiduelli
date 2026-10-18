/* menu.js — colonna di navigazione fissa a sinistra. Percorsi relativi: funziona su qualsiasi repository GitHub Pages. */
(function(){
  const BASE=new URL('../',document.currentScript.src).href;
  const NAV=[["Home","index.html",1],["Il Sentiero","sfida.html",1],["Deck Analyzer","deck-analyzer.html",0],["Match Pro","match-pro.html",0],["Gestisci torneo","gestisci-torneo.html",0]];
  const CSS=`:root{--tm-w:230px}
  @media(min-width:720px){html{padding-left:var(--tm-w)}}
  .tm{position:fixed;inset:0 auto 0 0;width:var(--tm-w);z-index:1000;display:flex;flex-direction:column;background:#0f0b18;border-right:1px solid rgba(244,236,220,.14);font-family:"Instrument Sans",system-ui,sans-serif;color:#f4ecdc}
  .tm-h{padding:18px 16px 14px;border-bottom:1px solid rgba(244,236,220,.14)}
  .tm-b{display:flex;align-items:center;gap:10px;color:#f4ecdc;text-decoration:none;font:600 1.12rem/1.1 Fraunces,Georgia,serif}
  .tm-b img{width:46px;height:46px;border-radius:12px;flex:none}
  .tm-n{flex:1;overflow-y:auto;padding:10px 0}
  .tm-n a,.tm-n span{position:relative;display:flex;align-items:center;justify-content:space-between;gap:8px;min-height:46px;padding:0 16px 0 22px;color:#f4ecdc;text-decoration:none;font-weight:600}
  .tm-n a:hover{background:#2a2040}
  .tm-n a[aria-current]{background:#2a2040;color:#ff6b7f}
  .tm-n a[aria-current]::before{content:"";position:absolute;left:0;top:8px;bottom:8px;width:4px;border-radius:0 4px 4px 0;background:#ff6b7f}
  .tm-n span{color:#a99fbf;cursor:default}
  .tm-n small{font-size:.68rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;border:1px solid rgba(244,236,220,.25);border-radius:99px;padding:2px 8px}
  .tm-f{padding:14px 16px calc(14px + env(safe-area-inset-bottom,0px));border-top:1px solid rgba(244,236,220,.14);font-size:.8rem;color:#a99fbf}
  .tm-x,.tm-t,.tm-s{display:none}
  @media(max-width:719px){
   html{padding-left:34px}
   .tm{width:min(80vw,300px);transform:translateX(-100%);visibility:hidden;transition:transform .22s,visibility .22s}
   .tm.open{transform:none;visibility:visible}
   .tm-x{display:block;margin-top:10px;min-height:40px;padding:0 14px;border-radius:10px;border:2px solid rgba(244,236,220,.3);background:none;color:#f4ecdc;font:700 .95rem "Instrument Sans",sans-serif}
   .tm-t{display:flex;align-items:center;position:fixed;left:0;top:50%;transform:translateY(-50%);z-index:999;writing-mode:vertical-rl;padding:16px 9px;background:#c42a41;color:#f4ecdc;border:0;border-radius:0 10px 10px 0;font:700 .85rem "Instrument Sans",sans-serif;letter-spacing:.12em;cursor:pointer}
   .tm-s{display:block;position:fixed;inset:0;background:rgba(8,5,14,.65);opacity:0;pointer-events:none;transition:opacity .2s;z-index:999}
   .tm-s.on{opacity:1;pointer-events:auto}}`;
  function mount(){
    if(document.getElementById('tm-css'))return;
    const st=document.createElement('style');st.id='tm-css';st.textContent=CSS;document.head.appendChild(st);
    const here=location.pathname.replace(/\/$/,'/index.html');
    const links=NAV.map(([n,f,ok])=>{const u=new URL(f,BASE);return ok?`<a href="${u.href}"${u.pathname===here?' aria-current="page"':''}>${n}</a>`:`<span aria-disabled="true">${n}<small>presto</small></span>`}).join('');
    const col=document.createElement('aside');col.className='tm';col.id='tmCol';col.setAttribute('aria-label','Navigazione');
    col.innerHTML=`<div class="tm-h"><a class="tm-b" href="${BASE}index.html"><img src="${BASE}icons/logo.svg" alt=""><span>Il Tempio Dei Duelli</span></a><button class="tm-x" id="tmX">Chiudi</button></div><nav class="tm-n">${links}</nav><div class="tm-f">Yu-Gi-Oh! · Bologna</div>`;
    const t=document.createElement('button');t.className='tm-t';t.textContent='MENU';t.setAttribute('aria-expanded','false');t.setAttribute('aria-controls','tmCol');
    const s=document.createElement('div');s.className='tm-s';
    document.body.append(col,t,s);
    const set=v=>{col.classList.toggle('open',v);s.classList.toggle('on',v);t.setAttribute('aria-expanded',v);(v?document.getElementById('tmX'):t).focus()};
    t.onclick=()=>set(true);document.getElementById('tmX').onclick=()=>set(false);s.onclick=()=>set(false);
    document.addEventListener('keydown',e=>{if(e.key==='Escape'&&col.classList.contains('open'))set(false)});
  }
  window.TM={mount};
})();
