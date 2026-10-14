# Fill these in before launch

`lib/screens/legal/privacy_policy_screen.dart` and
`terms_of_service_screen.dart` contain drafted Privacy Policy / Terms of
Service text, structured to be DPDP Act (India) aware, but with placeholder
values that only you can fill in correctly:

- `[COMPANY_LEGAL_NAME]` — your registered business name (or your own full
  name if operating as an individual/sole proprietor).
- `[SUPPORT_EMAIL]` — an email you actually monitor for user questions.
- `[GRIEVANCE_OFFICER_NAME]` / `[GRIEVANCE_OFFICER_EMAIL]` — required under
  the DPDP Act, 2023: a named person users can contact about their data.
  Can be you, but must be a real name/email.
- `[BUSINESS_ADDRESS]` — your registered or operating address.
- `[JURISDICTION]` — e.g. "India" or a specific state, for the governing-law
  clause.
- `[FILL IN BEFORE LAUNCH]` (both screens' "Last updated" date) — set to the
  actual date you finalize and ship this text.

These are drafted as a reasonable starting point, not reviewed by a lawyer.
For a hiring app handling PII (resumes, salary, phone numbers) at any real
scale, get the final text reviewed by someone qualified in Indian data
protection law before relying on it.
