# Il Tempio Dei Duelli
App (PWA) della community Yu-Gi-Oh! di Bologna: Black Market (BC, taglie, Ladder, Sentiero), La guerra degli Eroi, strumenti per i tornei e FAQ.
Sito statico su GitHub Pages (tutti i file nella cartella principale); dati e regole su Supabase.
Pagine: `index.html` (Home), `black-market.html`, `sentiero.html`, `eroi.html`, `faq.html`, `duel-simulator.html`, `gestisci-torneo.html`, `match-pro.html`, `deck-analyzer.html`.
Navigazione comune in `tempio.js` + `tempio.css` (barra in basso sul telefono, menu a sinistra su computer); cache offline in `sw.js`.
Database: i file `*.sql` si eseguono nell'SQL Editor di Supabase, nell'ordine indicato nell'intestazione di ognuno; si possono rieseguire.
Ogni migrazione ha `-test.sql` (solo su un progetto di prova vuoto, finisce con rollback) e `-down.sql` (annullamento).
Tutti i BC passano dal registro contabile; interruttori e valori del gioco in Black Market › Admin › Impostazioni.
Le regole spiegate agli utenti stanno solo in `faq.html`: aggiornala quando cambia un gioco.
Dopo ogni modifica alzare il numero `?v=` dei file cambiati e `CACHE` in `sw.js`, così i telefoni scaricano la versione nuova.
