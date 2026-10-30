# Stato del progetto (30/10/2026)

## Completato e verificato in CI (analyze 0 errori, test unitari, 18 gruppi di test SQL)
- HACCP: A1 temperature, A2 pulizie, A3 merci/lotti/ritiri, A4 allergeni/menu, A5 infestanti
- Sicurezza: B1 DVR (emissione con snapshot+SHA-256), B2 DUVRI/appaltatori, B3 DPI, B4 formazione e scadenze, B5 infortuni/near-miss (denuncia INAIL, chiusura controllata)
- Core: ruoli (admin/operatore/consulente), PIN operatore su tablet condiviso, firma digitale, centro avvisi unificato, export PDF (merci, allergeni, infortuni, scadenze) con impronta SHA-256
- DB: Supabase/Postgres, RLS multi-azienda, registri append-only con catena di hash, audit

## Non ancora fatto / da verificare
- L'app non e' mai stata eseguita su dispositivo o emulatore (solo analisi statica e test in CI)
- Salvataggio solo online: manca coda offline
- Nessuna notifica push/locale (gli avvisi sono visibili solo in app)
- Report PDF: mancano temperature, pulizie, infestanti, DVR/DUVRI emessi
- PIN operatore senza limite di tentativi lato server
- Onboarding (creazione azienda, inviti) non verificato
- Documenti allegati solo come immagini (niente selettore PDF)
- Roadmap: sensori IoT per le temperature

## Per provarla
1. Creare un progetto Supabase e applicare `supabase/migrations/*` (o `supabase db push`)
2. `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
