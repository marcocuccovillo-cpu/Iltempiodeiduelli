# Il Tempio dei Duelli — Guida di pubblicazione

## 1. Database (Supabase)
1. Crea un progetto su supabase.com.
2. SQL Editor: esegui in ordine tutti i file di `supabase/migrations/` (da `…0001` a `…0005`).
3. Collaudo: esegui `supabase/tests/scenarios.sql` e `supabase/tests/admin.sql` (finiscono con ROLLBACK, non lasciano dati).
4. Authentication > URL Configuration: Site URL = indirizzo dell'app; Redirect URLs = `…/auth/callback` (locale e Vercel).
   Authentication > Providers > Email: in produzione lascia attiva "Confirm email".

## 2. Variabili d'ambiente
Copia `.env.example` in `.env.local` e compila (Supabase > Project Settings > API):
`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (chiave anon/publishable), `NEXT_PUBLIC_SITE_URL`.
Non usare mai la chiave `service_role` nel progetto.

## 3. Esecuzione in locale (Node.js 20+)
```bash
npm install
npm run dev          # http://localhost:3000
npm run typecheck
```

## 4. Primo amministratore
Registrati dall'app, poi nel SQL Editor:
```sql
update profiles set role = 'admin' where lower(nickname) = lower('IlTuoNickname');
```
Da lì promuovi gli organizzatori dal pannello Admin > Utenti.

## 5. GitHub e Vercel
1. Carica il contenuto della cartella su un repository GitHub (`.env.local` è escluso da `.gitignore`).
2. vercel.com > Add New > Project > importa il repository (Next.js rilevato in automatico).
3. Imposta le tre variabili d'ambiente, poi Deploy.
4. Aggiorna Site URL e Redirect URLs su Supabase con l'URL Vercel definitivo.

## 6. Primo collaudo con la community
- Usa un progetto Supabase di prova prima di quello reale: il ledger è immutabile, quindi i dati di test non si cancellano.
- Prova il flusso completo con 3 account: due utenti, un organizzatore. Evento WPA, iscrizione, abbinamento, taglie, verifica del risultato.
- Controlla Admin > Anomalie: deve dire che i saldi coincidono con il ledger.

## Funzionalità completate
Auth e ruoli (utente, organizzatore, admin); wallet con ledger append-only; taglie (bozza, pubblicazione, annullamento bozza);
Bounty Value; liquidazione atomica e idempotente con rimborso della quota del vincitore; eventi, partecipanti, abbinamenti,
verifica risultati e ricompense di partecipazione; contestazioni; pannello admin (utenti e ruoli, sospensioni, taglie in revisione,
riscossioni, contestazioni, limiti economici, rettifiche tracciate, audit, controllo saldi); Home, Most Wanted, Profilo, Crea taglia,
Registro, Wallet, in dark mode e responsive.

## Limiti noti / ancora da fare
- Il codice dell'app non è stato compilato né provato in questo ambiente: i test automatici coprono solo il database.
- Nessun test end-to-end del frontend e nessun dato demo (scelta voluta: il ledger non si può cancellare).
- Le pagine con dati richiedono l'accesso; le pagine pubbliche per non iscritti non sono implementate.
- Avatar solo come iniziali; nessun caricamento immagini.
- Una contestazione risolta non annulla una liquidazione già avvenuta: le correzioni passano da rettifiche tracciate.
- Nessuna notifica (email o push) e nessun limite di frequenza sulle richieste oltre a quelli del database.
- Backup e monitoraggio dipendono dal piano Supabase scelto.
