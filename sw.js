/* Il Tempio Dei Duelli — service worker: guscio offline. Rete per prima (gli aggiornamenti arrivano subito), cache solo se si è offline. Tutti i file stanno nella stessa cartella. */
const CACHE="tempio-v20";
const CORE=["index.html","sentiero.html","black-market.html","black-market-moduli.js?v=15","badge.js?v=12","shop-art.js?v=12","black-market-shop.js?v=12","black-market-notifiche.js?v=16","black-market-caccia.js?v=14","gestisci-torneo.html","match-pro.html","deck-analyzer.html","tempio.css?v=10","tempio.js?v=10","tempio.js?v=11","eroi.html","tempio-notifiche.js?v=2","tempio-logo.svg?v=1","tempio-mark.png","manifest.webmanifest"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>Promise.all(CORE.map(u=>c.add(u).catch(()=>{})))));self.skipWaiting()});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==CACHE).map(x=>caches.delete(x)))));self.clients.claim()});
self.addEventListener("fetch",e=>{const r=e.request;if(r.method!=="GET"||new URL(r.url).origin!==location.origin)return;
 if(r.mode==="navigate"){e.respondWith(fetch(r).then(x=>{if(x.ok)caches.open(CACHE).then(c=>c.put(r,x.clone()));return x}).catch(()=>caches.match(r).then(h=>h||caches.match("index.html"))));return}
 e.respondWith(fetch(r).then(x=>{if(x.ok)caches.open(CACHE).then(c=>c.put(r,x.clone()));return x}).catch(()=>caches.match(r)))});

/* Notifiche push (migrazione 009): la Edge Function send-push invia un messaggio cifrato {title, body, url, tag}. */
self.addEventListener("push",e=>{let d={};try{d=e.data?e.data.json():{}}catch(_){d={body:e.data?e.data.text():""}}
 e.waitUntil(self.registration.showNotification(d.title||"Il Tempio Dei Duelli",{body:d.body||"",icon:"icon-192.png?v=2",badge:"icon-192.png?v=2",tag:d.tag||undefined,data:{url:d.url||"black-market.html#/notifiche"}}))});
self.addEventListener("notificationclick",e=>{e.notification.close();
 const raw=(e.notification.data&&e.notification.data.url)||"black-market.html#/notifiche";let u;try{u=new URL(raw,self.registration.scope)}catch(_){u=new URL("black-market.html#/notifiche",self.registration.scope)}
 if(u.origin!==self.location.origin)u=new URL("black-market.html#/notifiche",self.registration.scope);   // si aprono solo pagine del sito
 e.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(l=>{for(const c of l){if(c.url.split("#")[0]===u.href.split("#")[0]){return (c.navigate?c.navigate(u.href).catch(()=>null):Promise.resolve()).then(()=>c.focus())}}return clients.openWindow(u.href)}))});
