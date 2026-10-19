# Il Tempio Dei Duelli

Sito/PWA della community Yu-Gi-Oh! di Bologna. Funziona su GitHub Pages: **tutti i file stanno nella stessa cartella, nessuna sottocartella**.

## Cosa c'è
| File | A cosa serve |
|---|---|
| `index.html` | Home con il calendario Google degli eventi e l'elenco degli strumenti |
| `sentiero.html` | Il Sentiero dei Sigilli + Campionato del Tempio (libretto duelli, sigilli, classifica) |
| `black-market.html` | Black Market (taglie con i Black Credits, serve Supabase) |
| `black-market-moduli.js` | Interfaccia dei moduli opzionali Hall of Fame, Faction Wars, Underground Challenges (vedi sotto) |
| `gestisci-torneo.html` | Gestione torneo: Swiss senza rematch, bye, doppia sconfitta, drop, OMW%, Top 4/8 |
| `match-pro.html` | Life Points, timer, cronologia, salvataggio nel Libretto |
| `deck-analyzer.html` | Import .ydk, ruoli, probabilità d'apertura, mani simulate |
| `tempio.css`, `tempio.js` | Stile e menu condivisi da tutte le pagine |
| `logo1.png`, `tempio-mark.png`, `icon-*.png`, `apple-touch-icon.png` | Logo originale e icone dell'app |
| `manifest.webmanifest`, `sw.js` | Installazione come app e uso offline |
| `.nojekyll` | Dice a GitHub Pages di non elaborare i file |
| `black-market-setup.sql`, `black-market-test.sql` | Database del Black Market (migrazione 001) e i suoi 10 scenari di test |
| `black-market-ladder.sql`, `black-market-ladder-test.sql`, `black-market-ladder-down.sql` | Migrazione 003: Ladder Elo e immagine avatar, relativi test e annullamento |
| `black-market-moduli.sql`, `black-market-moduli-test.sql`, `black-market-moduli-down.sql` | Migrazione 002 dei tre moduli, relativi test e annullamento |
| `workflow-keepalive.yml` | Promemoria anti-pausa per Supabase (vedi sotto) |

## Pubblicare (da telefono)
1. Nel repository GitHub: **Add file › Upload files**, seleziona **tutti** i file di questa cartella (compreso `.nojekyll`, se il telefono lo mostra) e fai commit.
2. **Settings › Pages**: *Deploy from a branch*, branch `main`, cartella `/ (root)`.
3. Apri l'indirizzo del sito. Se vedi una versione vecchia, ricarica due volte (il service worker aggiorna la cache in automatico, `tempio-v7`).

Se manca `tempio.css` o `tempio.js` le pagine appaiono senza stile e senza menu: controlla che siano stati caricati.

## Black Market: configurazione
1. Crea un progetto gratuito su supabase.com.
2. **SQL Editor › New query**: incolla tutto `black-market-setup.sql` › Run (una volta sola).
3. (Facoltativo, **solo su un progetto Supabase di prova ancora vuoto**: si rifiuta di partire se trova già utenti) incolla `black-market-test.sql` › Run: gira in una transazione annullata alla fine e mostra una riga "OK" per ognuno dei 10 scenari.
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

## Moduli opzionali: Hall of Fame, Faction Wars, Underground Challenges
Tre moduli nuovi, **spenti per impostazione iniziale**. Most Wanted, taglie, wallet e registro contabile non sono stati ricreati né modificati.

**Cosa fanno (tutto letto dai dati ufficiali, nessuna copia)**
- **Hall of Fame** (`#/hof`): classifica per vittorie/% vittorie/eventi/BC riscossi, record permanenti, traguardi, archivio eventi con i match verificati, rivalità (almeno 3 match ufficiali tra gli stessi due), riscossioni registrate, statistiche per stagione, scheda del singolo duellante. Dove non c'è un dato compare "n/d" o "nessun…": niente numeri inventati.
- **Faction Wars** (`#/factions`): fondazione e gestione fazioni (nome, descrizione, simbolo), adesione/uscita (una sola fazione, attesa dopo l'uscita, massimo membri), classifica complessiva e per stagione, storico. Il punteggio è **calcolato dai match verificati** (3 punti a vittoria su un avversario di un'altra fazione, valore modificabile da Admin): ogni match conta una volta sola, chi cambia fazione non riscrive il passato, nessun legame con i BC e nessun premio automatico. L'admin può rinominare/sciogliere, spostare un membro ed escludere/reintegrare un match con motivazione.
- **Underground Challenges** (`#/challenges`): sfida a un duellante; stati in attesa, accettata, rifiutata, annullata, scaduta, in corso, completata. Scade dopo 7 giorni se non accettata. Un organizzatore/admin collega il match giocato e, **solo dopo la verifica ufficiale** del match (processo già esistente), conferma la sfida. Accettare non genera vittorie, punti fazione, riscossioni o BC; nessuna scommessa, nessun trasferimento di BC.

**Come si applicano (in sicurezza)**
1. Fai prima un backup: Admin › *Esporta storico completo (JSON)*.
2. Supabase › SQL Editor: incolla `black-market-moduli.sql` › Run. Si applica **dopo** `black-market-setup.sql`, non cancella né modifica dati esistenti, ed è "tutto o niente" (se qualcosa fallisce non resta nulla a metà). Va eseguita una volta sola: se la rilanci a moduli già installati ti dà un errore e non cambia nulla.
3. (Facoltativo, **solo su un progetto Supabase di prova ancora vuoto**, con setup 001 + 002 applicati: si rifiuta di partire se trova già utenti o eventi, senza modificare nulla) `black-market-moduli-test.sql`: crea utenti di prova, mostra una riga OK per ciascun gruppo di controlli e annulla tutto. **Non eseguirlo sul database con i dati veri.**
4. Carica su GitHub i file aggiornati: `black-market.html`, `black-market-moduli.js`, `sw.js` (**attenzione**: sostituendo `black-market.html` vanno reincollati `SUPABASE_URL` e `SUPABASE_ANON_KEY`).

**Come si attivano dopo l'approvazione**: accedi come amministratore › Black Market › **Admin › Moduli aggiuntivi › Attiva** (un modulo alla volta, serve una motivazione). Compare subito nel menu. Per spegnerlo: **Disattiva**. A modulo spento il database rifiuta ogni operazione e nasconde i dati agli utenti, anche con richieste dirette; gli altri moduli restano attivi. In Admin si creano anche le stagioni.

**Annullare la migrazione**: `black-market-moduli-down.sql` rimuove i tre moduli. Cancella i dati creati dai moduli (fazioni, sfide, stagioni): esporta prima ciò che ti serve. Non tocca nulla del Black Market originale; le righe di audit restano.

**Provato davvero** (PostgreSQL 16 locale, adattatore `auth` simulato come sopra): i 10 gruppi di `black-market-moduli-test.sql` e i 10 scenari originali di `black-market-test.sql` con la migrazione 002 applicata; prima/dopo la 002 l'impronta (md5) di tutte le tabelle del Black Market è identica; `down` e nuova applicazione riusciti anche con dati nei moduli. Interfaccia provata con Playwright e Supabase simulato (moduli spenti: nascosti; accesi: pagine, azioni e pannello Admin chiamano le funzioni giuste; nessun errore, nessun scorrimento orizzontale a 390 px).
**Non provato**: su Supabase reale con login vero; con più utenti contemporanei sull'interfaccia (la concorrenza è stata verificata solo per le riscossioni, a livello database). Nessun branch, commit o deploy: non ho accesso a GitHub da qui.

## Ladder, foto profilo e statistiche (migrazione 003)
Nuova migrazione **003** (`black-market-ladder.sql`): si applica dopo la 001 e la 002, una sola volta, ed è "tutto o niente". Non modifica né cancella dati esistenti.

- **Ladder** (menu ☰ › *Ladder*, oppure Black Market › *Ladder*): classifica Elo (si parte da 1000, K=32). Si sfida un duellante scegliendo il formato (Advanced, Traditional, GOAT, Edison); l'avversario accetta; dopo il duello **uno invia il risultato e l'altro lo conferma** (chi invia non può confermare da solo: era il difetto della vecchia ladder). Pareggi inclusi. Se l'avversario non è d'accordo può contestare e decide un amministratore (Admin › *Ladder: match da gestire*). Le sfide non accettate scadono dopo 7 giorni; massimo 5 sfide aperte a testa e 3 match al giorno tra gli stessi due. Un match concluso non si modifica più. La Ladder è **separata** dal Black Market: non muove BC, non tocca taglie né match ufficiali WPA. Si può spegnere da Admin › *Moduli aggiuntivi* (è attiva per impostazione iniziale).
- **Profilo in dashboard**: nome, ruolo, foto (si sceglie dalla galleria o dalla fotocamera; viene ritagliata e ridotta a 128 px prima dell'invio, circa 5-10 KB, e salvata nel profilo) e statistiche personali: saldo, match ufficiali vinti/persi e %, eventi giocati, taglie su di te, lanciate e riscosse, Elo e posizione in Ladder. Dove non ci sono dati compare "n/d".
- Il collegamento al database (`SUPABASE_URL` e chiave *anon public*) è già inserito in `black-market.html`. L'indirizzo deve essere solo `https://xxxx.supabase.co` (la barra finale va bene). Se un giorno sostituisci quel file, controlla che le due righe siano ancora compilate.

**Come si applica**: Supabase › SQL Editor › incolla `black-market-ladder.sql` › Run (dopo aver fatto il backup da Admin). Poi carica su GitHub **tutti** i file dello zip. Senza la migrazione il Black Market funziona come prima, ma Ladder e foto profilo non sono disponibili (la Ladder resta nascosta e caricare la foto dà il messaggio di eseguire la migrazione).
**Annullare**: `black-market-ladder-down.sql` (cancella la Ladder e le foto; eseguilo *prima* di `black-market-moduli-down.sql`, se mai userai anche quello).
**Provato davvero**: i 9 gruppi di `black-market-ladder-test.sql` (calcolo Elo a mano, conferma solo dell'altro giocatore, mai contato due volte, contestazioni, limiti, scadenze, visibilità, interruttore lato database, nessun effetto su BC/match ufficiali/taglie) più i test 001 e 002 con la 003 applicata, su PostgreSQL 16 locale; prima/dopo la 003 l'impronta di tutte le tabelle del Black Market è identica; annullamento e riapplicazione riusciti. Interfaccia provata con Playwright e Supabase simulato (390 px). **Non provato**: su Supabase reale con più utenti; il ritaglio della foto con una vera foto del telefono.

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
