-- Annulla black-market-shop-extra.sql: toglie dalla vendita i 60 premi nuovi.
-- Nessun premio viene cancellato (la tabella non lo permette) e chi li ha già acquistati li conserva, con i prezzi pagati.
-- La rarità «Divino» resta valida nel database (se esistono premi Divini non si può togliere): non ha effetti senza premi attivi.
begin;
update public.shop_items set active = false, updated_at = now()
 where id in ('xe_guardiano', 'xf_rovi', 'xx_scintille', 'xe_mago', 'xt_cacciatore', 'xp_pipistrello', 'xa_braci', 'xp_golem', 'xe_spada', 'xt_custode', 'xf_rune', 'xx_piume', 'xa_druidica', 'xt_stregone', 'xp_volpe', 'xe_occhio', 'xf_ghiaccio', 'xp_cavaliere', 'xa_gelida', 'xp_lupo', 'xe_stella', 'xt_signore', 'xa_tempesta', 'xf_drago', 'xx_fulmini', 'xp_grifone', 'xe_corona', 'xt_eroe', 'xp_sfinge', 'xf_fulmini', 'xx_neve', 'xa_sacra', 'xp_idra', 'xe_ali', 'xa_infernale', 'xt_caos', 'xf_millennio', 'xp_drago_cremisi', 'xe_teschio', 'xp_cerbero', 'xx_meteore', 'xf_infernale', 'xt_re', 'xp_leviatano', 'xa_astrale', 'xe_drago', 'xa_caos', 'xt_imperatore', 'xp_arcidemone', 'xf_siderale', 'xe_infinito', 'xx_anime', 'xp_drago_cosmico', 'xt_dio', 'xf_vuoto', 'xa_galattica', 'xf_eclissi', 'xa_singolarita', 'xp_ouroboros', 'xt_sovrano') and active;
commit;
