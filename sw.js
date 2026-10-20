/* Il Tempio Dei Duelli — service worker: guscio offline. Rete per prima (gli aggiornamenti arrivano subito), cache solo se si è offline. Tutti i file stanno nella stessa cartella. */
const CACHE="tempio-v12";
const CORE=["index.html","sentiero.html","black-market.html","black-market-moduli.js?v=12","badge.js?v=11","shop-art.js?v=12","black-market-shop.js?v=12","gestisci-torneo.html","match-pro.html","deck-analyzer.html","tempio.css?v=8","tempio.js?v=8","tempio.js?v=9","logo1.png","tempio-mark.png","manifest.webmanifest"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>Promise.all(CORE.map(u=>c.add(u).catch(()=>{})))));self.skipWaiting()});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==CACHE).map(x=>caches.delete(x)))));self.clients.claim()});
self.addEventListener("fetch",e=>{const r=e.request;if(r.method!=="GET"||new URL(r.url).origin!==location.origin)return;
 if(r.mode==="navigate"){e.respondWith(fetch(r).then(x=>{if(x.ok)caches.open(CACHE).then(c=>c.put(r,x.clone()));return x}).catch(()=>caches.match(r).then(h=>h||caches.match("index.html"))));return}
 e.respondWith(fetch(r).then(x=>{if(x.ok)caches.open(CACHE).then(c=>c.put(r,x.clone()));return x}).catch(()=>caches.match(r)))});
