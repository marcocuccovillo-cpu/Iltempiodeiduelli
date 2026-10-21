# Il Tempio Dei Duelli

Sito/PWA della community Yu-Gi-Oh! di Bologna. Funziona su GitHub Pages: **tutti i file stanno nella stessa cartella, nessuna sottocartella**.

## Cosa c'è
| File | A cosa serve |
|---|---|
| `index.html` | Home: spiega come funziona il sito, il Black Market (1000 BC di benvenuto), la Ladder (premi in BC e match WPA) e i badge, poi l'elenco degli strumenti. Il calendario Google è stato tolto |
| `sentiero.html` | Il Sentiero: badge e traguardi del Black Market e della Ladder, con accesso unico dal Black Market. Restano il Libretto duelli e il Campionato del Tempio |
| `badge.js` | Grafica (medaglie SVG), nomi e schede dei badge, condivisa da Sentiero e Black Market |
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
| `black-market-ladder-rewards.sql`, `black-market-ladder-rewards-test.sql`, `black-market-ladder-rewards-down.sql` | Migrazione 004: bonus 1000 BC, premi della Ladder in BC, vittorie Ladder come match WPA ufficiali, relativi test e annullamento |
| `black-market-moderatore.sql`, `black-market-moderatore-test.sql`, `black-market-moderatore-down.sql` | Migrazione 005: ruolo Moderatore e sezione Funzioni Mod, relativi test e annullamento |
| `black-market-moderatore-taglie.sql`, `black-market-moderatore-taglie-test.sql`, `black-market-moderatore-taglie-down.sql` | Migrazione 006: i moderatori gestiscono anche le taglie, relativi test e annullamento |
| `black-market-badge.sql`, `black-market-badge-test.sql`, `black-market-badge-down.sql` | Migrazione 007: catalogo dei 48 traguardi e funzione di lettura dei badge, relativi test e annullamento |
| `black-market-shop.js`, `shop-art.js` | Pagina Black Market Shop (catalogo, collezione, conferma d'acquisto, gestione catalogo per gli admin) e grafica dei premi: pet, cornici, aure, emblemi, effetti, titoli, tutti in SVG/CSS |
| `black-market-shop.sql`, `black-market-shop-test.sql`, `black-market-shop-down.sql` | Migrazione 008: catalogo, acquisti, equipaggiamento, 39 premi iniziali, relativi test e annullamento |
| `black-market-caccia.js` | Caccia alle taglie: pulsante «Sfida» su Most Wanted, dashboard e profilo, pagina `#/hunt` (ricercati e taglie da riscuotere) e `#/hunt/<duellante>` (lancio della sfida in Ladder) |
| `tempio-notifiche.js` | Campanella delle notifiche (con il numero delle non lette) in alto a destra su Home, Sentiero, Gestisci torneo, Match Pro e Deck Analyzer; non fa nulla se non c'è un accesso salvato |
| `black-market-notifiche.js` | Pagina Notifiche (`#/notifiche`): elenco, preferenze, attivazione delle push su questo dispositivo, notifica di prova, chiave VAPID per l'admin |
| `black-market-notifiche.sql`, `black-market-notifiche-test.sql`, `black-market-notifiche-down.sql` | Migrazione 009: notifiche (taglia ricevuta, sfida in Ladder, sfida per la taglia), preferenze, dispositivi push, relativi test e annullamento |
| `black-market-notifiche-elimina.sql`, `black-market-notifiche-elimina-test.sql`, `black-market-notifiche-elimina-down.sql` | Migrazione 010: cancellare le proprie notifiche già lette, relativi test e annullamento |
| `send-push.ts` | Edge Function di Supabase che invia le push. **Non è una pagina del sito**: si incolla in Supabase (vedi sotto) |
| `black-market-moduli.sql`, `black-market-moduli-test.sql`, `black-market-moduli-down.sql` | Migrazione 002 dei tre moduli, relativi test e annullamento |
| `workflow-keepalive.yml` | Promemoria anti-pausa per Supabase (vedi sotto) |

## Pubblicare (da telefono)
1. Nel repository GitHub: **Add file › Upload files**, seleziona **tutti** i file di questa cartella (compreso `.nojekyll`, se il telefono lo mostra) e fai commit.
2. **Settings › Pages**: *Deploy from a branch*, branch `main`, cartella `/ (root)`.
3. Apri l'indirizzo del sito. Se vedi una versione vecchia, ricarica due volte (il service worker aggiorna la cache in automatico, `tempio-v10`).

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
- 1000 BC di benvenuto per i nuovi iscritti (300 BC fino alla migrazione 004), 30 BC per la partecipazione a un evento; taglia da 50 a 500 BC, massimo 5 taglie attive per utente; si riceve una taglia solo se si è dato il consenso ("Accetto taglie su di me").
- Riscossione solo dal vincitore di un match ufficiale: verificato da un organizzatore oppure nato da una vittoria Ladder confermata (in quel caso dopo 24 ore, vedi migrazione 004). Premio = quote di altri utenti; le proprie quote tornano al vincitore senza guadagno. Contano solo le quote create prima della verifica.
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

- **Ladder** (menu ☰ › *Ladder*, oppure Black Market › *Ladder*): classifica Elo (si parte da 1000, K=32). Si sfida un duellante scegliendo il formato (**Advanced** o **Edison**: vedi la migrazione 011); l'avversario accetta; dopo il duello **uno invia il risultato e l'altro lo conferma** (chi invia non può confermare da solo: era il difetto della vecchia ladder). Pareggi inclusi. Se l'avversario non è d'accordo può contestare e decide un amministratore (Admin › *Ladder: match da gestire*). Le sfide non accettate scadono dopo 7 giorni; massimo 5 sfide aperte a testa e 3 match al giorno tra gli stessi due. Un match concluso non si modifica più. Con la sola migrazione 003 la Ladder è separata dal Black Market; dalla migrazione 004 le vittorie danno BC e match WPA (vedi sotto).
- **Profilo in dashboard**: nome, ruolo, foto (si sceglie dalla galleria o dalla fotocamera; viene ritagliata e ridotta a 128 px prima dell'invio, circa 5-10 KB, e salvata nel profilo) e statistiche personali: saldo, match ufficiali vinti/persi e %, eventi giocati, taglie su di te, lanciate e riscosse, Elo e posizione in Ladder. Dove non ci sono dati compare "n/d".
- Il collegamento al database (`SUPABASE_URL` e chiave *anon public*) è già inserito in `black-market.html`. L'indirizzo deve essere solo `https://xxxx.supabase.co` (la barra finale va bene). Se un giorno sostituisci quel file, controlla che le due righe siano ancora compilate.

**Come si applica**: Supabase › SQL Editor › incolla `black-market-ladder.sql` › Run (dopo aver fatto il backup da Admin). Poi carica su GitHub **tutti** i file dello zip. Senza la migrazione il Black Market funziona come prima, ma Ladder e foto profilo non sono disponibili (la Ladder resta nascosta e caricare la foto dà il messaggio di eseguire la migrazione).
**Annullare**: `black-market-ladder-down.sql` (cancella la Ladder e le foto; eseguilo *prima* di `black-market-moduli-down.sql`, se mai userai anche quello).
**Provato davvero**: i 9 gruppi di `black-market-ladder-test.sql` (calcolo Elo a mano, conferma solo dell'altro giocatore, mai contato due volte, contestazioni, limiti, scadenze, visibilità, interruttore lato database, nessun effetto su BC/match ufficiali/taglie) più i test 001 e 002 con la 003 applicata, su PostgreSQL 16 locale; prima/dopo la 003 l'impronta di tutte le tabelle del Black Market è identica; annullamento e riapplicazione riusciti. Interfaccia provata con Playwright e Supabase simulato (390 px). **Non provato**: su Supabase reale con più utenti; il ritaglio della foto con una vera foto del telefono.

## Home, premi Ladder e match WPA (migrazione 004)
Nuova migrazione **004** (`black-market-ladder-rewards.sql`): si applica dopo 001, 002 e 003, una volta sola, "tutto o niente". Non cancella e non modifica dati esistenti (verificato con le impronte md5 delle tabelle prima/dopo: l'unica differenza è una riga in più nell'audit).

- **Home**: il calendario è stato sostituito da tre spiegazioni (come funziona il sito, Black Market, Ladder) con i valori attuali.
- **Bonus iniziale 1000 BC**: l'impostazione `initial_bonus` passa da 300 a 1000 **solo se è ancora 300** (se l'avevi cambiata a mano resta com'è). Vale per i **nuovi** iscritti; chi è già dentro mantiene il suo saldo. Per dargli la differenza (700 BC) usa Admin › *Rettifica saldo*: resta nel registro con motivazione.
- **Premio Ladder**: ogni **vittoria** confermata (non pareggio, non sconfitta) **genera 20 BC** per il vincitore. I BC li crea il sistema, non sono tolti allo sconfitto: nessun trasferimento tra utenti. Limiti: massimo **3 vittorie premiate in 24 ore** per giocatore e **1 per avversario**. Registro contabile, idempotenza (un solo premio per match) e audit come per ogni altro movimento. Nessun effetto retroattivo sulle partite già concluse.
- **Match WPA**: ogni vittoria Ladder confermata (o decisa dall'admin) diventa anche un **match ufficiale verificato** nell'evento automatico «Ladder WPA AAAA-MM-GG» (creato a nome del primo amministratore, senza partecipanti, quindi senza premi di partecipazione). Conta per le taglie e per Hall of Fame e Faction Wars quando attivi. I pareggi restano solo Elo. Per la stessa coppia conta **un solo match ufficiale ogni 24 ore**.
- **Protezione anti-accordi (modifica a `claim_bounty`)**: una taglia basata su un match Ladder si riscuote **24 ore dopo la conferma**; in questo tempo l'admin può mettere la taglia in revisione (funzione già esistente). Per i match degli organizzatori non cambia nulla. È l'unica modifica alla logica economica del Black Market, introdotta perché senza arbitro due amici potrebbero accordarsi (A mette una taglia su B, B "perde" contro C, C incassa: sarebbe un trasferimento di BC). La funzione è identica alla 001 con un solo controllo in più.
- **Impostazioni** (Admin › Impostazioni, tutte con motivazione e audit): `ladder_reward_enabled` (1/0), `ladder_reward_bc` (20), `ladder_reward_max_day` (3), `ladder_reward_pair_day` (1), `ladder_wpa_matches` (1/0), `ladder_wpa_pair_day` (1), `ladder_claim_hold_hours` (24, con 0 nessuna attesa). Con premi e match ufficiali spenti la Ladder si comporta esattamente come con la sola 003.
- **Interfaccia**: la pagina Ladder mostra premi, limiti e quante vittorie premiate hai nelle ultime 24 ore; i risultati indicano «+20 BC» e «match WPA»; il wallet ha la voce «Vittoria in Ladder»; la dashboard ha la tessera «Guadagnati in Ladder»; Eventi elenca a parte gli eventi automatici della Ladder.

**Come si applica**: Supabase › SQL Editor › incolla `black-market-ladder-rewards.sql` › Run (dopo il backup da Admin), poi carica **tutti** i file dello zip. Senza la migrazione il sito funziona come prima, ma il bonus resta 300 BC e la Ladder non dà BC né match WPA, mentre la home dice il contrario: applicala prima di caricare i file.
**Annullare**: `black-market-ladder-rewards-down.sql` (prima del down della 003). Lo storico non si cancella: i premi già scritti nel registro, i match ufficiali nati dalla Ladder e i saldi restano.
**Test**: ogni file di test va eseguito su un database di prova **vuoto**, subito dopo la propria migrazione (il test 003 afferma che la Ladder non muove BC, vero solo prima della 004, oppure con premi e match ufficiali spenti).
**Provato davvero** (PostgreSQL 16 locale): 9 scenari di `black-market-ladder-rewards-test.sql` (bonus, premio e registro, idempotenza, limiti 24 ore, match ufficiale, Hall of Fame, punti fazione, blocco e revisione delle taglie, interruttori, decisioni admin, contabilità, permessi); i test 001, 002 e 003 con la 004 applicata e premi spenti; annullamento e riapplicazione; prova di aggiornamento su dati reali; un test deliberatamente rotto (limite 3 al giorno) viene scoperto. Interfaccia e home provate con Playwright e Supabase simulato (390 e 1280 px). **Non provato**: Supabase reale con più utenti, e il comportamento dell'economia con tanti giocatori (20 BC a vittoria creano BC nuovi: tieni d'occhio i totali e, se serve, abbassa `ladder_reward_bc`).
**Limiti noti**: più account della stessa persona possono accumulare i premi e il bonus di benvenuto (i limiti li rallentano, non li impediscono); un match ufficiale nato dalla Ladder non può essere "annullato" dopo la conferma (si interviene sulle taglie con la revisione, sui punti fazione con l'esclusione del match e sui BC con una rettifica motivata).

## Ruolo Moderatore e Funzioni Mod (migrazione 005)
Nuova migrazione **005** (`black-market-moderatore.sql`): si applica dopo 001–004, una volta sola. Aggiunge il ruolo **Moderatore**, che **assegni solo tu** da Admin › Utenti (menu del ruolo, con motivazione). Nessuno può nominarsi o promuoversi, nemmeno un moderatore.

**Cosa può fare un moderatore** (sempre con audit; la sezione è nel menu del Black Market: **Funzioni Mod**, visibile solo a te e ai moderatori):
- **Verificare i match ufficiali** in attesa, di qualsiasi evento (`mod_verify_match`). La verifica non si modifica più e sblocca la riscossione delle taglie.
- **Gestire la Ladder**: decidere i match contestati o fermi e annullare le sfide abbandonate. Il risultato deciso chiude il match come una conferma normale: Elo, premio di 20 BC e match WPA seguono le regole della 004.
- **Rimuovere un duellante**: "rimuovere" significa **sospendere** l'account (non può più agire e non si può sfidare), con possibilità di riattivarlo. Match, saldi e registro restano intatti. Non può sospendere amministratori o altri moderatori.
- **Gestire le taglie** (migrazione 006, vedi sotto): vedere tutte le taglie, metterle in revisione e annullarle.
- È anche un **duellante normale**: ha wallet, mette e riceve taglie, gioca in Ladder.

**Cosa non può fare**: gestire i moduli, cambiare impostazioni (compresi premi e bonus), assegnare o rettificare crediti, premi di partecipazione, creare eventi o match, chiudere le contestazioni generiche, esportare i dati, leggere l'audit e i saldi altrui, cambiare ruoli. **Un moderatore non può verificare né decidere un match in cui gioca lui.** Un moderatore sospeso perde subito tutti i poteri.
Tu (admin) conservi tutto. Se vuoi dare ai moderatori anche la chiusura delle contestazioni generiche, è un cambio di una riga: dimmelo.

**Come si applica**: Supabase › SQL Editor › incolla `black-market-moderatore.sql` › Run, poi carica i file. Senza la migrazione il sito funziona come prima e la sezione Funzioni Mod avvisa di eseguirla. **Annullare**: `black-market-moderatore-down.sql` (i moderatori tornano duellanti, con una riga di audit per ciascuno; la voce "moderator" resta nell'elenco dei ruoli, inerte, perché PostgreSQL non permette di toglierla).
**Provato davvero** (PostgreSQL 16 locale): 7 scenari di `black-market-moderatore-test.sql` (nomina, poteri e divieti, verifica match, decisioni Ladder, sospensioni, regressione dei ruoli e dei permessi); test 001–004 ancora tutti verdi con la 005 applicata; applicazione come unica transazione (come l'editor SQL); annullamento e riapplicazione; un'alterazione volontaria della protezione degli admin viene scoperta dal test. Interfaccia provata con Playwright (390 px) per moderatore, admin, organizzatore e duellante. **Non provato**: Supabase reale con più utenti.
**Limite noto**: decidendo un match Ladder un moderatore fa scattare il premio automatico di 20 BC e il match WPA previsti dalle regole (non assegna crediti a piacere, ma può favorire un amico): ogni decisione è nell'audit, che leggi tu.

### Gestione delle taglie per i moderatori (migrazione 006)
`black-market-moderatore-taglie.sql`, da eseguire dopo la 005. Il moderatore vede tutte le taglie (prima solo creatore e admin) e, con motivazione e audit, può **metterle in revisione** (sospende la riscossione sul bersaglio) e **annullarle**: l'annullamento restituisce al creatore **solo i BC che aveva versato**, una volta sola, senza creare crediti. Non può gestire una taglia che ha creato o in cui è il bersaglio (le decide un collega o l'admin). La logica è quella della 001 con ruolo e un controllo in più.
**Annullare**: `black-market-moderatore-taglie-down.sql` (revisioni e annullamenti già fatti restano nello storico). **Provato**: 2 scenari in `black-market-moderatore-taglie-test.sql` (rimborso corretto e una sola volta, riscossione sospesa in revisione, taglie proprie vietate, nessun credito assegnabile) e tutti i test 001–006 verdi insieme, annullamento e riapplicazione compresi. Nota: con la 006 due controlli del test 005 (divieto di annullare/congelare taglie) non esistono più, per scelta.

## Badge, traguardi e Sentiero con accesso unico (migrazione 007)
**Un solo profilo.** Il Sentiero non ha più un nickname proprio: usa il profilo del Black Market (nickname, foto, ruolo, saldo ed Elo della Ladder). L'unico accesso è quello del Black Market: chi non è entrato vede l'invito ad accedere e l'anteprima dei traguardi. Il libretto duelli e il campionato locali restano, ma giocano con il nickname del profilo. I vecchi «Sigilli» sono sostituiti dai badge (la tessera del campionato ora porta solo i punti dei tornei).

**I badge** sono 48 traguardi in 4 livelli (Bronzo, Argento, Oro, Leggenda) più 3 speciali, in 4 aree:
- *Black Market*: taglie lanciate (1/5/15/40), taglie riscosse (1/5/15/30), taglie ricevute (1/5/15/30), bottino più grosso (100/300/600 BC in una riscossione).
- *Match ufficiali*: vittorie verificate (1/5/15/40), serie di vittorie (3/5/8), eventi giocati (1/5/15/30).
- *Ladder*: vittorie (1/10/30/75), Elo massimo (1100/1200/1350/1500), serie di vittorie (3/5/8), avversari diversi battuti (3/8/15), Ammazzagiganti (vittoria su chi aveva 100+ Elo più di te: 1/3/10), rivincite (1/5).
- *Speciali*: Iniziato (tutti), Doppia Anima (vittoria in Ladder + taglia riscossa), Custode del Tempio (admin, moderatori, organizzatori).
I punti Tempio (Bronzo 1, Argento 3, Oro 6, Leggenda 10, speciali 5) fanno salire il **grado**: Novizio, Duellante, Veterano, Maestro, Campione, Leggenda del Tempio.

**Come funziona (sicurezza).** `black-market-badge.sql` aggiunge solo il catalogo `badge_defs` (sola lettura) e la funzione `badge_progress(utente)`, che calcola ogni badge **al momento** dai dati ufficiali (match verificati, partecipazioni, taglie, riscossioni, partite di Ladder concluse). Nessun badge è scritto da nessuna parte: non si possono assegnare a mano né barare dal browser, non danno Black Credits e **nessuna funzione economica è stata toccata**. Le soglie si cambiano solo con una nuova migrazione. Privacy: se l'amministrazione nasconde gli autori delle taglie, «taglie lanciate» resta visibile solo al diretto interessato e allo staff; con il modulo Ladder spento i badge della Ladder spariscono e tornano identici alla riaccensione. Un badge di ruolo (Custode) segue il ruolo attuale.

**Dove si vedono**: nel Sentiero (muro dei traguardi con filtri e «I più vicini»), nella dashboard e nel profilo di ogni duellante del Black Market (vetrina con i badge più alti). Toccando una medaglia si apre la scheda con data di sblocco o progresso.

**Ordine**: esegui `black-market-badge.sql` dopo la 006. **Annullare**: `black-market-badge-down.sql` (non perde nulla: i badge sono derivati; il Sentiero e i profili mostrano un avviso al posto dei badge). **Provato**: 7 scenari in `black-market-badge-test.sql` (catalogo e permessi, nuovo iscritto, vittorie/serie/eventi con date, taglie e privacy, Ladder completa, ruoli e modulo spento/acceso, sicurezza) con controlli di mutazione, tutti i test 001–007 verdi, annullamento e riapplicazione compresi; pagine provate in Chromium a 390 e 1100 px con un Supabase simulato. **Limiti**: le prestazioni su un database con molti utenti non sono misurate (il calcolo avviene per singolo giocatore a ogni apertura del profilo); non è stato provato su un Supabase vero.

## Black Market Shop (migrazione 008)
**Cos'è.** Una nuova pagina del Black Market (menu «Black Market Shop», `black-market.html#/shop`) dove si spendono i Black Credits in premi permanenti da esporre sul profilo. Nessun denaro reale, nessuno scambio tra utenti, nessun BC regalato: lo Shop può solo **addebitare**.

**Premi.** 39 premi da 2 a 1000 BC in 6 categorie (Pet, Titoli, Cornici, Aure, Emblemi, Effetti), 5 rarità con fasce di prezzo imposte dal database: Comune 2–49, Raro 50–149, Epico 150–349, Leggendario 350–699, Mitico 700–1000. I 12 pet sono creature originali disegnate in SVG (Gelatina Cucciola, Fantasmino Curioso, Draghetto d'Ebano, Apprendista Ombra, Sentinella Millenaria, Drago Spettrale, Fenice Oscura, Drago degli Abissi, Drago Astrale, Fenice Celestiale, Drago delle Ombre Eterne) e il premio finale, **Drago Apocalittico (1000 BC)**: armatura nera, quattro corna, occhi incandescenti, ali enormi e fiamme rosso-viola, più grande di ogni altro pet. Animazioni leggere; il pulsante «Animazioni» dello Shop (e l'impostazione «riduci movimento» del dispositivo) le spegne per una versione statica.

**Profilo.** Per ogni categoria si equipaggia un solo premio, si può sostituire o togliere senza perderlo. Cornice, titolo, emblema, aura, effetto e pet equipaggiati compaiono nel profilo pubblico di ogni duellante e nella tua dashboard del Black Market. «La mia collezione» mostra rarità, data d'acquisto, prezzo pagato e cosa è equipaggiato.

**Sicurezza.** Tutto passa da funzioni del database (`shop_buy`, `shop_equip`, `shop_unequip`, `admin_shop_save_item`): il browser non scrive mai nelle tabelle. L'acquisto blocca il wallet, controlla prezzo, saldo e proprietà **sul server**, registra l'acquisto e addebita con la stessa funzione contabile del Black Market (`_ledger_move`, tipo `shop_purchase`) **nella stessa transazione**: o riescono entrambi o nessuno. Il saldo non può diventare negativo; ogni apertura della conferma ha un codice richiesta, quindi un doppio clic o un invio ripetuto non addebita due volte; un premio si compra una volta sola. Gli acquisti sono un registro immutabile (non si modificano né si cancellano) e i premi non si cancellano mai: disattivarli li toglie dalla vendita ma restano in tutti gli inventari.

**Prezzi senza toccare il codice.** Gli admin, dalla scheda «Gestione catalogo» dello Shop, creano e disattivano premi e modificano prezzo, descrizione, rarità, grafica e ordine; vedono gli acquisti e lo storico delle modifiche (valori prima/dopo, chi, quando, perché). Ogni modifica chiede una motivazione ed entra nell'audit (`shop_item_create/update/activate/deactivate`). Cambiare un prezzo vale solo per i nuovi acquisti. L'impostazione `shop_enabled` (anche dal pulsante «Chiudi gli acquisti») chiude gli acquisti senza impedire di equipaggiare.

**Ordine**: esegui `black-market-shop.sql` dopo la 007 (si può rieseguire senza danni). **Annullare**: `black-market-shop-down.sql` toglie funzioni e vista ma **conserva** tabelle, acquisti e movimenti contabili: nulla di ciò che gli utenti hanno pagato va perso. **Provato**: 8 scenari in `black-market-shop-test.sql` (catalogo, acquisto, saldo insufficiente e atomicità, duplicati/Shop chiuso/premio disattivato, manomissioni dal client, equipaggiamento e visibilità pubblica, permessi admin e audit, compatibilità con taglie, riscossioni e Ladder), 6 varianti sbagliate delle funzioni individuate dai test, 8 acquisti simultanei del premio da 1000 BC da sessioni separate (uno solo andato a buon fine, saldo mai negativo, registro = saldi), 6 acquisti diversi simultanei con saldo insufficiente per tutti (saldo mai negativo), e il flusso della pagina (filtri, conferma, doppio clic, equipaggia, profilo pubblico, admin, smartphone) in Chromium con un Supabase simulato.

## Caccia alle taglie (nessuna migrazione)
**Cos'è.** Come si sfida chi ha una taglia addosso. Accanto a ogni ricercato (Most Wanted, dashboard, profilo) c'è il pulsante **Sfida**: porta alla pagina `#/hunt/<duellante>`, che mostra Bounty Value, quanto si potrebbe incassare (le proprie quote tornano indietro) e il modulo per lanciare una **normale sfida in Ladder**. La pagina `#/hunt` (menu Most Wanted → «Caccia alle taglie») elenca tutti i ricercati e le **taglie pronte da riscuotere**.

**Regole: nessuna nuova.** La sfida è una sfida Ladder; lo sfidato può accettare, rifiutare o lasciarla scadere (la taglia resta dov'è). Se si vince, il match Ladder verificato è un match WPA ufficiale e, dopo l'attesa anti-accordi (`ladder_claim_hold_hours`, 24 ore), la taglia si riscuote con la normale `claim_bounty`. Il browser non calcola né scrive importi. Serve il modulo Ladder acceso (altrimenti la pagina lo spiega).

## Notifiche push (migrazione 009)
**Cosa arriva.** Una notifica quando qualcuno: (1) mette una **taglia** su di te, (2) ti **sfida in Ladder**, (3) ti sfida **per riscuotere la taglia** che hai addosso. La notifica della taglia non dice mai chi l'ha messa. In alto a destra, su **tutte le pagine del sito** (Home, Sentiero, Gestisci torneo, Match Pro, Deck Analyzer e Black Market), c'è la **campanella** con il numero delle notifiche non lette: toccandola si apre la pagina Notifiche del Black Market, dove ognuno sceglie cosa ricevere. Le notifiche **dentro l'app** (elenco + contatore nel menu) funzionano appena esegui la migrazione; le **push ad app chiusa** richiedono la configurazione qui sotto (una volta sola).

**Come funziona.** Trigger del database → riga in `notifications` → Database Webhook → Edge Function `send-push` → Web Push (VAPID). Fuori dal Black Market la campanella compare solo se sul dispositivo c'è già un accesso (lo stesso account del Black Market e del Sentiero); senza accesso non contatta nessuno. Un errore nelle notifiche non blocca mai una taglia o una sfida. Nessuna notifica muove BC.

**Configurazione push (una volta, dall'admin):**
1. Esegui `black-market-notifiche.sql` in Supabase (SQL Editor), dopo la 008.
2. Genera le chiavi VAPID (sul computer, con Node): `npx web-push generate-vapid-keys`. Ottieni una chiave pubblica e una privata.
3. Accedi come admin, apri Black Market → **Notifiche** e incolla la chiave **pubblica** nel riquadro «Amministratore».
4. Supabase → Edge Functions → *Create a new function* → nome `send-push` → incolla `send-push.ts` → Deploy. Se il webhook dovesse ricevere errore 401 dall'infrastruttura, disattiva «Verify JWT» per questa funzione: il controllo vero lo fa il segreto `x-webhook-secret`.
5. Edge Functions → `send-push` → Secrets: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` (la **privata** non va mai nel sito né nel database), `VAPID_SUBJECT` (es. `mailto:tuo@indirizzo.it`), `PUSH_WEBHOOK_SECRET` (una stringa lunga a caso).
6. Database → Webhooks → *Create*: tabella `notifications`, evento **Insert**, tipo *Supabase Edge Functions* → `send-push`, con intestazione `x-webhook-secret` uguale a `PUSH_WEBHOOK_SECRET`.
7. Ogni giocatore apre Notifiche → **Attiva le notifiche su questo dispositivo** (e può usare «Invia una notifica di prova»). Su iPhone/iPad il Tempio va prima installato sulla schermata Home.

**Pagina Notifiche.** In alto la lista delle notifiche ricevute, con «Segna tutte come lette». Una notifica **già letta** si può eliminare (pulsante «Elimina» accanto ad «Apri», oppure «Elimina le lette» per tutte insieme); quelle non lette no, così non si perde un avviso mai visto. Più in basso le **Impostazioni notifiche**, chiuse di default: lì si scelgono i tipi di avviso da ricevere e, una volta attivate le push su questo dispositivo, anche lo stato, la notifica di prova e «Disattiva». Finché le push non sono attive, il pulsante «Attiva le notifiche su questo dispositivo» resta ben visibile sotto la lista.

**Migrazione 010 (eliminare le notifiche lette).** Esegui `black-market-notifiche-elimina.sql` dopo la 009 (si può rieseguire). Aggiunge solo la funzione `notif_delete`: ognuno cancella soltanto le **proprie** notifiche **già lette**; il browser continua a non poter cancellare direttamente dalla tabella. Non tocca BC, wallet, registro, taglie o sfide. Senza la 010 la pagina funziona, ma «Elimina» avvisa che serve la migrazione. **Annullare**: `black-market-notifiche-elimina-down.sql` (toglie solo la funzione). **Provato**: 7 scenari in `black-market-notifiche-elimina-test.sql` (permessi, non lette intoccabili, notifiche altrui intoccabili anche per l'admin, «elimina tutte le lette», nessuna cancellazione diretta, economia invariata) e 5 varianti sbagliate della funzione individuate dai test.

**Annullare le notifiche (009)**: `black-market-notifiche-down.sql` toglie trigger e funzioni ma **conserva** tabelle e notifiche. **Provato**: 9 scenari SQL in `black-market-notifiche-test.sql` (destinatari corretti, anonimato di chi mette la taglia, preferenze, permessi e RLS, invarianza di BC/registro, resistenza agli errori), 10 varianti sbagliate individuate dai test, annullamento e riapplicazione senza perdere dati; interfaccia (caccia, notifiche, attivazione/disattivazione push, stati negato/non supportato/senza chiave/migrazione assente, smartphone) in Chromium con Supabase e push simulati; logica di `send-push.ts` con web-push simulato. **Non provato**: l'invio push reale (servono le tue chiavi VAPID e un progetto Supabase vero) e il pacchetto `web-push` (non installabile nel mio ambiente di test).

## Ladder: formati, Elo separati, tipo di sfida e accettazione (migrazione 011)
Esegui `black-market-ladder-formati.sql` in Supabase (SQL Editor) **dopo la 010**. Senza la 011 il sito funziona come prima (la pagina Ladder lo segnala); con la 011 attiva:

- **Formati**: si può sfidare **solo in Advanced o in Edison** (controllo nel database, anche per gli inserimenti diretti). Le partite già giocate in Traditional o GOAT restano nello storico e non vengono toccate.
- **Classifiche Elo separate**: ogni giocatore ha un Elo Advanced e un Elo Edison, entrambi da 1000, con le sue vittorie/pareggi/sconfitte e la sua posizione. La pagina Ladder ha un selettore **Advanced | Edison** per classifica e ultimi risultati; dashboard e Sentiero mostrano i due Elo. **Come sono stati ricostruiti i dati esistenti**: la migrazione rigioca in ordine tutte le partite già concluse in Advanced ed Edison con la stessa formula (K=32) e scrive le due classifiche; il vecchio Elo unico non viene cancellato (tabella `ladder_ratings_legacy`, non esposta al browser). Provato su un database con partite già giocate: i risultati coincidono con un calcolo indipendente.
- **Tipo di sfida** (obbligatorio, si sceglie al momento di sfidare, sia dalla Ladder sia da «Caccia alle taglie»):
  | Tipo | Elo del formato | +20 BC Ladder | Match WPA ufficiale | Taglia sull'avversario |
  |---|---|---|---|---|
  | **Ladder normale** | sì | sì | sì | **non** riscuotibile con questo match |
  | **Per la taglia** | no | no | sì | riscuotibile (dopo l'attesa di 24 ore) |
  | **Ladder + taglia** | sì | sì | sì | riscuotibile (dopo l'attesa di 24 ore) |

  «Per la taglia» e «Ladder + taglia» si possono scegliere solo se l'avversario ha taglie che lo sfidante può davvero incassare (le proprie quote ti tornano indietro e non contano): lo controlla il database. Lo sfidato **vede il tipo prima di accettare**, con scritto cosa c'è in gioco. Il tipo non si cambia dopo. Le partite precedenti alla 011 valgono come «Ladder + taglia» (è come funzionavano).
- **Accettare o rifiutare una sfida** (c'era già, ma stava in fondo alla pagina): ora la sfida da accettare compare **in cima alla pagina Ladder, in dashboard e nella pagina Notifiche**, con i pulsanti Accetta e Rifiuta e la spiegazione di cosa c'è in gioco. Solo lo sfidato può rispondere; lo sfidante riceve una notifica («Sfida accettata» / «Sfida rifiutata», segue la preferenza «sfida in Ladder»). Una sfida non accettata scade da sola dopo 7 giorni.
- **Riscossione**: `claim_bounty` è quella di prima più un controllo: un match nato come Ladder normale non fa riscuotere nulla. Eventi degli organizzatori e match precedenti restano riscuotibili. Il limite di un match WPA ufficiale al giorno per coppia vale separatamente per i match «normali» e per quelli «per la taglia», così un match normale non toglie la possibilità di riscuotere con uno per la taglia.
- **Badge**: una sfida «per la taglia» (senza Elo) vale come match ufficiale ma non come partita di Ladder.
- **Provato**: 12 scenari SQL in `black-market-ladder-formati-test.sql` (formati, Elo separati, i tre tipi di sfida con riscossione, avvisi di accettazione/rifiuto, attesa di 24 ore, saldi = registro, permessi) e 13 versioni sbagliate del codice, tutte individuate dai test. Annullamento: `black-market-ladder-formati-down.sql` (perde il tipo delle sfide e rigioca l'Elo unico da tutte le partite). I test di una migrazione girano sul database com'era **subito dopo** quella migrazione: eseguiti dopo la 011 alcuni dei test più vecchi cambiano di proposito (per esempio ora all'accettazione arriva una notifica in più).
- **Provato nel browser (21 ottobre 2026)**: 53 controlli con Chromium (Playwright) sulle pagine vere, collegate a un PostgreSQL locale con le migrazioni 001–011 applicate tramite un finto client Supabase: pagina Ladder (solo Advanced/Edison, due classifiche, selettore del tipo di sfida con le sue regole), dashboard con riquadro «sfide da accettare» e due tile Elo, accetta/rifiuta da Ladder e da Notifiche, gioco/conferma/riscossione, Caccia alle taglie con tipo obbligatorio, Sentiero, testo della home, nessuno scroll orizzontale a 390 e 1280 px, nessun errore JavaScript. **Non** provato su un Supabase reale (login vero, RLS reale), né con le notifiche push vere.

## Stato verificato (20 ottobre 2026)
**Provato davvero**
- Tutte le pagine si caricano senza errori, senza scorrimento orizzontale a 390 px e a 1280 px (Chromium, test automatici).
- Match Pro, Gestisci torneo (torneo completo con Top 4, doppia sconfitta, drop, codice per il Sentiero), Deck Analyzer (con le API delle carte simulate) e Sentiero (compreso l'import del codice torneo e del duello salvato da Match Pro) provati con test automatici a 390 px.
- `black-market-setup.sql` e i 10 scenari di `black-market-test.sql` eseguiti su **PostgreSQL 16 locale**: tutti OK. Anche 6 richieste di riscossione simultanee sullo stesso match, da sessioni separate, hanno pagato una sola volta e i saldi quadrano con il registro.
- Black Market (schermate e stile) provato nel browser con un Supabase **simulato**.

**Non provato**
- Lo schema non è stato eseguito su un progetto Supabase vero: in locale il modulo `auth` di Supabase è stato imitato con un piccolo adattatore (tabella `auth.users` e funzione `auth.uid()`). Alla prima esecuzione sul tuo progetto, se compare un errore, mandalo.
- Registrazione/login reali, invio email, e collegamento del browser a un database vero.
- Font Google e API YGOPRODeck: richiedono Internet e nel sandbox di test erano bloccati o simulati.
- Nessun push su GitHub e nessun deploy: i file vanno caricati da te.

**Non fatto**
- Collegamento automatico tra *Gestisci torneo* e il Black Market: eventi e match si registrano nella scheda *Eventi* del Black Market.
- Verifica email personalizzata, recupero password personalizzato, moderazione dei messaggi oltre al limite di 140 caratteri.

## Nota sui rischi
Le taglie possono essere usate per prendere di mira qualcuno: per questo si ricevono solo con consenso. Nomina almeno due admin e leggi le contestazioni. Due amici possono accordarsi per far riscuotere una taglia a uno dei due: il tetto di 500 BC, la revisione admin e (per i match Ladder) l'attesa di 24 ore la limitano, non la eliminano.
