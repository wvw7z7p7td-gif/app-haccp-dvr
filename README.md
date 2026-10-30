# app-haccp-dvr
App di gestione HACCP e DVR/DUVRI per attività commerciali


## Setup
1. `flutter create --org it.tuaazienda --project-name haccp_safety .`
   (genera android/ e ios/; non sovrascrive lib/ e pubspec.yaml: se lo fa, ripristinali)
2. `flutter pub get`
3. Crea un progetto Supabase (regione UE) ed esegui in ordine `supabase/migrations/0001_init.sql` e `0002_signatures_and_cleaning.sql`
   dallo SQL editor (oppure `supabase db push` con la CLI).
4. Avvio:
   `flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxxx`
5. Crea un utente da Supabase Auth, poi dallo SQL editor, per creare la prima azienda
   e associarla all'utente come admin (sostituisci <USER_UUID>):
   ```sql
   with c as (insert into companies (name) values ('Mia Azienda') returning id)
   insert into company_members (company_id, user_id, role)
   select id, '<USER_UUID>', 'admin' from c;
   ```
   (La funzione `create_company()` serve invece alle chiamate dall'app, con utente autenticato.)

## Note operative
- Controfirma pulizie: serve almeno un dipendente con `is_supervisor = true`, diverso da chi esegue.
  Imposta il flag con: `update employees set is_supervisor = true where id = '<EMPLOYEE_UUID>';`
- PIN operatore (tablet condiviso): `select set_employee_pin('<EMPLOYEE_UUID>', '1234');` da utente admin.
- Chi e' autenticato con un account collegato al proprio dipendente (`employees.user_id`) non digita il PIN.
