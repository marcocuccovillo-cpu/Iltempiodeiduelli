-- =====================================================================
-- SHOP: 60 NUOVI PREMI + RARITÀ «DIVINO» (si esegue DOPO black-market-shop.sql; si può rieseguire senza danni)
--
-- Cosa fa:
--   * aggiunge una sesta rarità, «divine» (Divino), sopra il Mitico, con fascia di prezzo 1001–5000 BC
--     (le altre fasce non cambiano: Comune 2–49, Raro 50–149, Epico 150–349, Leggendario 350–699, Mitico 700–1000);
--   * inserisce 60 premi permanenti nuovi (14 pet, 10 cornici, 10 aure, 10 emblemi, 10 titoli, 6 effetti), tutti con
--     prezzi e nomi diversi da quelli già presenti. 4 sono Divini (Ouroboros Cosmico, Cornice dell'Eclissi Divina,
--     Aura della Singolarità, Eterno Sovrano del Tempio).
-- Cosa NON fa: non tocca i premi esistenti, i prezzi già pagati, gli acquisti, i saldi, il registro dei movimenti né le
-- funzioni (shop_buy, shop_equip, ... restano identiche: valgono anche per i nuovi premi). Non crea BC.
-- I premi si possono poi modificare, disattivare o aggiungere dalla scheda «Gestione catalogo» dello Shop.
-- Annullamento: black-market-shop-extra-down.sql (disattiva i 60 premi senza cancellare nulla).
-- =====================================================================
begin;

do $$ begin
  if to_regclass('public.shop_items') is null then
    raise exception 'Manca lo Shop: esegui prima black-market-shop.sql';
  end if;
end $$;

-- ---------- Rarità «Divino» ----------
alter table public.shop_items drop constraint if exists shop_items_rarity_check;
alter table public.shop_items add constraint shop_items_rarity_check
  check (rarity in ('common','rare','epic','legendary','mythic','divine'));
alter table public.shop_items drop constraint if exists shop_items_price_by_rarity;
alter table public.shop_items add constraint shop_items_price_by_rarity check (
     (rarity = 'common'    and price between 2 and 49)
  or (rarity = 'rare'      and price between 50 and 149)
  or (rarity = 'epic'      and price between 150 and 349)
  or (rarity = 'legendary' and price between 350 and 699)
  or (rarity = 'mythic'    and price between 700 and 1000)
  or (rarity = 'divine'    and price between 1001 and 5000));

-- controllo di sicurezza: non deve restare nessun altro vincolo sulla rarità (altrimenti il Divino verrebbe rifiutato)
do $$
declare n integer;
begin
  select count(*) into n from pg_constraint
   where conrelid = 'public.shop_items'::regclass and contype = 'c' and pg_get_constraintdef(oid) ~ 'rarity';
  if n <> 2 then
    raise exception 'La tabella shop_items ha % vincoli sulla rarità (ne attesi 2): controlla prima di procedere', n;
  end if;
end $$;

-- ---------- I 60 premi ----------
insert into public.shop_items (id, name, description, category, rarity, price, asset, sort) values
 ('xe_guardiano', 'Rune del Guardiano', 'Lo scudo con tre rune: il simbolo di chi difende il Tempio.', 'emblem', 'common', 19, 'xe_guardiano', 400),
 ('xf_rovi', 'Cornice di Rovi e Spine', 'Rovi neri con spine e boccioli cremisi attorno al tuo avatar.', 'frame', 'common', 29, 'xf_rovi', 410),
 ('xx_scintille', 'Scintille Dorate', 'Stelline d’oro che si accendono e si spengono sul profilo.', 'effect', 'common', 31, 'xx_scintille', 420),
 ('xe_mago', 'Sigillo del Mago', 'Un esagramma d’argento con una gemma al centro.', 'emblem', 'common', 33, 'xe_mago', 430),
 ('xt_cacciatore', 'Cacciatore di Draghi', 'Il titolo di chi ha già affrontato qualcosa di più grosso di lui.', 'title', 'common', 36, 'xt_cacciatore', 440),
 ('xp_pipistrello', 'Pipistrello Runico', 'Un pipistrello notturno con una runa che pulsa sul petto: ti segue ovunque sul profilo.', 'pet', 'common', 39, 'xp_pipistrello', 450),
 ('xa_braci', 'Aura di Braci', 'Piccole braci calde che salgono lente attorno al profilo.', 'aura', 'common', 44, 'xa_braci', 460),
 ('xp_golem', 'Golem di Cristallo', 'Un piccolo golem di cristallo azzurro, testardo e brillante. Non cade mai.', 'pet', 'common', 47, 'xp_golem', 470),
 ('xe_spada', 'Spada e Scudo', 'Una spada incrociata a uno scudo: l’emblema di chi non arretra.', 'emblem', 'rare', 69, 'xe_spada', 480),
 ('xt_custode', 'Custode delle Rune', 'Per chi conosce i segni antichi e li protegge.', 'title', 'rare', 79, 'xt_custode', 490),
 ('xf_rune', 'Cornice delle Rune Antiche', 'Un anello di rune d’argento che si accendono una dopo l’altra.', 'frame', 'rare', 89, 'xf_rune', 500),
 ('xx_piume', 'Piume di Fenice', 'Piume incandescenti che cadono piano e si spengono prima di toccare terra.', 'effect', 'rare', 97, 'xx_piume', 510),
 ('xa_druidica', 'Aura Druidica', 'Foglie e luci verdi che danzano come in una foresta antica.', 'aura', 'rare', 99, 'xa_druidica', 520),
 ('xt_stregone', 'Stregone Errante', 'Nessuna dimora, mille incantesimi.', 'title', 'rare', 109, 'xt_stregone', 530),
 ('xp_volpe', 'Volpe delle Nove Code', 'Nove code di fuoco fatuo e un sorriso furbo: la compagna dei duellanti più astuti.', 'pet', 'rare', 117, 'xp_volpe', 540),
 ('xe_occhio', 'Occhio Ierofante', 'Un occhio dorato in un triangolo, simbolo dei veggenti.', 'emblem', 'rare', 119, 'xe_occhio', 550),
 ('xf_ghiaccio', 'Cornice di Ghiaccio Eterno', 'Cristalli di ghiaccio azzurro che non si sciolgono mai.', 'frame', 'rare', 129, 'xf_ghiaccio', 560),
 ('xp_cavaliere', 'Cavaliere d’Argento', 'Un minuscolo cavaliere in armatura d’argento che veglia sul tuo profilo con la spada sguainata.', 'pet', 'rare', 131, 'xp_cavaliere', 570),
 ('xa_gelida', 'Aura Gelida', 'Un respiro di gelo azzurro con cristalli che ruotano piano.', 'aura', 'rare', 139, 'xa_gelida', 580),
 ('xp_lupo', 'Lupo delle Tempeste', 'Il pelo carico di elettricità e gli occhi di ghiaccio: ulula quando arriva il temporale.', 'pet', 'rare', 143, 'xp_lupo', 590),
 ('xe_stella', 'Stella del Duellante', 'Una stella a quattro punte incisa nel metallo blu.', 'emblem', 'epic', 169, 'xe_stella', 600),
 ('xt_signore', 'Signore del Mazzo', 'Ogni carta al suo posto, ogni mano sotto controllo.', 'title', 'epic', 179, 'xt_signore', 610),
 ('xa_tempesta', 'Aura Tempestosa', 'Nubi scure e lampi viola attorno a te: la tempesta ti appartiene.', 'aura', 'epic', 189, 'xa_tempesta', 620),
 ('xf_drago', 'Cornice Draconica', 'Scaglie di drago bronzo con quattro artigli che stringono l’avatar.', 'frame', 'epic', 199, 'xf_drago', 630),
 ('xx_fulmini', 'Fulmini Viola', 'Saette viola che guizzano ai lati del profilo.', 'effect', 'epic', 209, 'xx_fulmini', 640),
 ('xp_grifone', 'Grifone d’Oro', 'Testa d’aquila, corpo di leone e ali di luce dorata. Un guardiano fiero e leale.', 'pet', 'epic', 227, 'xp_grifone', 650),
 ('xe_corona', 'Corona Spezzata', 'Una corona d’oro crepata: chi la porta ha perso un regno e ne ha conquistato un altro.', 'emblem', 'epic', 239, 'xe_corona', 660),
 ('xt_eroe', 'Eroe della Leggenda', 'Il suo nome sarà cantato nelle taverne del Tempio.', 'title', 'epic', 259, 'xt_eroe', 670),
 ('xp_sfinge', 'Sfinge del Deserto Eterno', 'Custodisce enigmi vecchi di mille anni: chi non li risolve resta fuori dal tempio.', 'pet', 'epic', 263, 'xp_sfinge', 680),
 ('xf_fulmini', 'Cornice di Fulmini', 'Un anello di archi elettrici che scoccano lungo il bordo.', 'frame', 'epic', 279, 'xf_fulmini', 690),
 ('xx_neve', 'Neve Mistica', 'Fiocchi di neve azzurra che scendono come una magia.', 'effect', 'epic', 289, 'xx_neve', 700),
 ('xa_sacra', 'Aura Sacra', 'Un alone dorato con raggi di luce che ruotano come un’aureola.', 'aura', 'epic', 299, 'xa_sacra', 710),
 ('xp_idra', 'Idra a Tre Teste', 'Tre teste, tre sguardi, nessuna pietà. Tagliane una e il tuo profilo ne guadagna altre due.', 'pet', 'epic', 319, 'xp_idra', 720),
 ('xe_ali', 'Ali dell’Araldo', 'Due grandi ali bianche attorno a una gemma celeste.', 'emblem', 'legendary', 389, 'xe_ali', 730),
 ('xa_infernale', 'Aura Infernale', 'Un anello di fiamme rosso-viola che ruggisce attorno al profilo.', 'aura', 'legendary', 419, 'xa_infernale', 740),
 ('xt_caos', 'Maestro del Caos', 'Perde il controllo solo quando vuole.', 'title', 'legendary', 449, 'xt_caos', 750),
 ('xf_millennio', 'Cornice del Millennio Dorato', 'Oro massiccio, gemme e un occhio ornamentale in alto: la cornice dei collezionisti.', 'frame', 'legendary', 459, 'xf_millennio', 760),
 ('xp_drago_cremisi', 'Drago dell’Alba Cremisi', 'Un drago rosso come il cielo prima della battaglia, con ali di brace e artigli d’ossidiana.', 'pet', 'legendary', 489, 'xp_drago_cremisi', 770),
 ('xe_teschio', 'Teschio Coronato', 'Un teschio con corona e occhi di brace: il re dei morti non dimentica.', 'emblem', 'legendary', 529, 'xe_teschio', 780),
 ('xp_cerbero', 'Cerbero degli Inferi', 'Tre teste e tre criniere di fiamma viola: sorveglia le porte del Tempio più oscuro.', 'pet', 'legendary', 566, 'xp_cerbero', 790),
 ('xx_meteore', 'Pioggia di Meteore', 'Meteore che solcano il cielo del tuo profilo, una dopo l’altra.', 'effect', 'legendary', 569, 'xx_meteore', 800),
 ('xf_infernale', 'Cornice delle Fiamme Infere', 'Fiamme rosso-viola che salgono lungo l’anello e non si spengono.', 'frame', 'legendary', 599, 'xf_infernale', 810),
 ('xt_re', 'Re dei Duellanti', 'Il trono è vuoto solo finché non arriva lui.', 'title', 'legendary', 619, 'xt_re', 820),
 ('xp_leviatano', 'Leviatano Etereo', 'Un serpente marino di luce e nebbia che nuota nell’aria sopra il tuo nome.', 'pet', 'legendary', 649, 'xp_leviatano', 830),
 ('xa_astrale', 'Aura Astrale', 'Un velo di aurora boreale e stelle cadenti, in tutti i colori della notte.', 'aura', 'legendary', 679, 'xa_astrale', 840),
 ('xe_drago', 'Sigillo del Drago Antico', 'Un drago che si avvolge su sé stesso dentro un cerchio di rune.', 'emblem', 'mythic', 719, 'xe_drago', 850),
 ('xa_caos', 'Aura del Caos', 'Vortici magenta e turchesi che si inseguono senza regole.', 'aura', 'mythic', 739, 'xa_caos', 860),
 ('xt_imperatore', 'Imperatore dell’Abisso', 'Regna dove la luce non arriva.', 'title', 'mythic', 769, 'xt_imperatore', 870),
 ('xp_arcidemone', 'Arcidemone Cornuto', 'Corna d’ebano, ali di pipistrello e occhi d’oro fuso: un signore del caos in miniatura.', 'pet', 'mythic', 799, 'xp_arcidemone', 880),
 ('xf_siderale', 'Cornice Siderale', 'Un anello di stelle e pianeti in orbita attorno al tuo avatar.', 'frame', 'mythic', 849, 'xf_siderale', 890),
 ('xe_infinito', 'Emblema dell’Infinito', 'Il segno dell’infinito, luminoso e senza fine, su un disco di notte.', 'emblem', 'mythic', 899, 'xe_infinito', 900),
 ('xx_anime', 'Tempesta di Anime', 'Spiriti luminosi che girano in cerchio attorno a te, sussurrando.', 'effect', 'mythic', 929, 'xx_anime', 910),
 ('xp_drago_cosmico', 'Drago Cosmico del Vuoto', 'Il suo corpo è un pezzo di notte stellata. Dove passa, le costellazioni si spostano.', 'pet', 'mythic', 949, 'xp_drago_cosmico', 920),
 ('xt_dio', 'Dio dei Duelli', 'Non gioca le carte: le scrive.', 'title', 'mythic', 969, 'xt_dio', 930),
 ('xf_vuoto', 'Cornice del Vuoto', 'Una crepa nello spazio: il bordo del tuo avatar si piega verso il nulla.', 'frame', 'mythic', 979, 'xf_vuoto', 940),
 ('xa_galattica', 'Aura Galattica', 'Una piccola galassia a spirale ruota attorno al tuo profilo.', 'aura', 'mythic', 989, 'xa_galattica', 950),
 ('xf_eclissi', 'Cornice dell’Eclissi Divina', 'Un’eclissi totale con corona di luce e raggi dorati: la cornice più prestigiosa del Tempio.', 'frame', 'divine', 1800, 'xf_eclissi', 960),
 ('xa_singolarita', 'Aura della Singolarità', 'Un buco nero con disco di accrescimento e luce piegata: l’aura definitiva.', 'aura', 'divine', 2200, 'xa_singolarita', 970),
 ('xp_ouroboros', 'Ouroboros Cosmico', 'Il drago che morde la propria coda: un anello infinito di stelle, il companion più raro del Tempio.', 'pet', 'divine', 2500, 'xp_ouroboros', 980),
 ('xt_sovrano', 'Eterno Sovrano del Tempio', 'Il titolo che nessuno ha mai davvero tolto a chi lo porta.', 'title', 'divine', 3000, 'xt_sovrano', 990)
on conflict (id) do nothing;

commit;
