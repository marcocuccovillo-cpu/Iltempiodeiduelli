/* Il Tempio Dei Duelli — service worker: shell offline. */
const CACHE="tempio-v2";
const CORE=["index.html","sfida.html","gestisci-torneo.html","match-pro.html","deck-analyzer.html","assets/app.css","assets/menu.js","icons/logo.svg","manifest.webmanifest"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>Promise.all(CORE.map(u=>c.add(u).catch(()=>{})))));self.skipWaiting()});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==CACHE).map(x=>caches.delete(x)))));self.clients.claim()});
self.addEventListener("fetch",e=>{const r=e.request;if(r.method!=="GET"||new URL(r.url).origin!==location.origin)return;
 if(r.mode==="navigate"){e.respondWith(fetch(r).catch(()=>caches.match(r).then(h=>h||caches.match("index.html"))));return}
 e.respondWith(caches.match(r).then(h=>{const n=fetch(r).then(x=>{if(x.ok)caches.open(CACHE).then(c=>c.put(r,x.clone()));return x}).catch(()=>h);return h||n}))});
