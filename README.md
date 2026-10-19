# Il Tempio Dei Duelli

Sito/PWA della community Yu-Gi-Oh! di Bologna. Funziona su GitHub Pages: **tutti i file stanno nella stessa cartella, nessuna sottocartella**.

## Cosa c'è
| File | A cosa serve |
|---|---|
| `index.html` | Home con il calendario Google degli eventi e l'elenco degli strumenti |
| `sentiero.html` | Il Sentiero dei Sigilli + Campionato del Tempio (libretto duelli, sigilli, classifica) |
| `black-market.html` | Black Market (taglie con i Black Credits, serve Supabase) |
| `gestisci-torneo.html` | Gestione torneo: Swiss senza rematch, bye, doppia sconfitta, drop, OMW%, Top 4/8 |
| `match-pro.html` | Life Points, timer, cronologia, salvataggio nel Libretto |
| `deck-analyzer.html` | Import .ydk, ruoli, probabilità d'apertura, mani simulate |
| `tempio.css`, `tempio.js` | Stile e menu condivisi da tutte le pagine |
| `logo1.png`, `tempio-mark.png`, `icon-*.png`, `apple-touch-icon.png` | Logo originale e icone dell'app |
| `manifest.webmanifest`, `sw.js` | Installazione come app e uso offline |
| `.nojekyll` | Dice a GitHub Pages di non elaborare i file |
| `black-market-setup.sql`, `black-market-test.sql` | Database del Black Market e i suoi 10 scenari di test |
| `workflow-keepalive.yml` | Promemoria anti-pausa per Supabase (vedi sotto) |

## Pubblicare (da telefono)
1. Nel repository GitHub: **Add file › Upload files**, seleziona **tutti** i file di questa cartella (compreso `.nojekyll`, se il telefono lo mostra) e fai commit.
2. **Settings › Pages**: *Deploy from a branch*, branch `main`, cartella `/ (root)`.
3. Apri l'indirizzo del sito. Se vedi una versione vecchia, ricarica due volte (il service worker aggiorna la cache in automatico, `tempio-v4`).

Se manca `tempio.css` o `tempio.js` le pagine appaiono senza stile e senza menu: controlla che siano stati caricati.

## Black Market: configurazione
1. Crea un progetto gratuito su supabase.com.
2. **SQL Editor › New query**: incolla tutto `black-market-setup.sql` › Run (una volta sola).
3. (Consigliato) incolla `black-market-test.sql` › Run: gira in una transazione annullata alla fine e mostra una riga "OK" per ognuno dei 10 scenari.
4. **Authentication › Providers › Email**: per le prove disattiva *Confirm email*. In *URL Configuration* metti l'indirizzo del sito.
5. **Project Settings › API**: copia *Project URL* e la chiave *anon public*, apri `black-market.html` su GitHub (matita) e incollali in `SUPABASE_URL` e `SUPABASE_ANON_KEY`. **Mai** la chiave `service_role`.
6. Il PRIMO account che si registra diventa amministratore: registrati subito tu. Poi dal pannello Admin assegna il ruolo *Organizzatore* a chi gestirà eventi e match.
7. **Anti-pausa**: in *Settings › Secrets and variables › Actions* crea `SUPABASE_URL` e `SUPABASE_ANON_KEY`. Poi **Add file › Create new file**, scrivi come nome `.github/workflows/keepalive.yml` (digitando le barre si creano le cartelle) e incolla il contenuto di `workflow-keepalive.yml`.
8. **Backup**: pannello Admin › *Esporta storico completo (JSON)*. Il piano gratuito non ha backup automatici.

### Regole economiche
- 300 BC di benvenuto, 30 BC per la partecipazione a un evento; taglia da 50 a 500 BC, massimo 5 taglie attive per utente; si riceve una taglia solo se si è dato il consenso ("Accetto taglie su di me").
- Riscossione solo dal vincitore di un match verificato da un organizzatore. Premio = quote di altri utenti; le proprie quote tornano al vincitore senza guadagno. Contano solo le quote create prima della verifica.
- Il registro contabile (`ledger_entries`) non si può modificare né cancellare; ogni intervento admin richiede una motivazione ed è in `audit_logs`.
- I BC sono solo virtuali: nessun acquisto, nessuna conversione in denaro, niente XP o missioni.

## Stato verificato (19 ottobre 2026)
**Provato davvero**
- Tutte le pagine si caricano senza errori, senza scorrimento orizzontale a 390 px e a 1280 px (Chromium, test automatici).
- Match Pro, Gestisci torneo (torneo completo con Top 4, doppia sconfitta, drop, codice per il Sentiero), Deck Analyzer (con le API delle carte simulate) e Sentiero (compreso l'import del codice torneo e del duello salvato da Match Pro) provati con test automatici a 390 px.
- `black-market-setup.sql` e i 10 scenari di `black-market-test.sql` eseguiti su **PostgreSQL 16 locale**: tutti OK. Anche 6 richieste di riscossione simultanee sullo stesso match, da sessioni separate, hanno pagato una sola volta e i saldi quadrano con il registro.
- Black Market (schermate e stile) provato nel browser con un Supabase **simulato**.

**Non provato**
- Lo schema non è stato eseguito su un progetto Supabase vero: in locale il modulo `auth` di Supabase è stato imitato con un piccolo adattatore (tabella `auth.users` e funzione `auth.uid()`). Alla prima esecuzione sul tuo progetto, se compare un errore, mandalo.
- Registrazione/login reali, invio email, e collegamento del browser a un database vero.
- Calendario Google, font Google e API YGOPRODeck: richiedono Internet e nel sandbox di test erano bloccati o simulati.
- Nessun push su GitHub e nessun deploy: i file vanno caricati da te.

**Non fatto**
- Collegamento automatico tra *Gestisci torneo* e il Black Market: eventi e match si registrano nella scheda *Eventi* del Black Market.
- Verifica email personalizzata, recupero password personalizzato, moderazione dei messaggi oltre al limite di 140 caratteri.

## Nota sui rischi
Le taglie possono essere usate per prendere di mira qualcuno: per questo si ricevono solo con consenso. Nomina almeno due admin e leggi le contestazioni. Due amici possono accordarsi per far riscuotere una taglia a uno dei due: il tetto di 500 BC e la revisione admin la limitano, non la eliminano.
