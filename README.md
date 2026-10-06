# AutoWave

Flutter app (Android, iOS, web) on Supabase. All seven phases in one project:

1. Sign-in with phone (country picker), email or Google; driver and mechanic roles
2. Driver search bar → "Search for mechanics" → nearby mechanics by budget, with ratings and reviews
3. Separate mechanic dashboard: online switch, accept (with price and arrival time) or decline
4. Live tracking: the mechanic's position on a map, route line and ETA
5. Wallet with Paystack top-ups and **escrow**: the driver pays, the mechanic sees the money is secured but can't touch it until the driver confirms the job is done
6. Recycling: car batteries, tyres, used oil, scrap, whole vehicles; pickup or drop-off, with estimated payment and CO₂ impact
7. AutoLearn: AI tutor (Gemini) for ages 7–18 and drivers, 11 languages, topics and quizzes

## Try it in 1 minute (no setup)

Demo mode runs the whole app on sample Lagos data. A simulated mechanic accepts, drives to you and finishes the job; escrow, wallet and recycling all work with fake money.

```bash
flutter pub get
flutter run --dart-define=DEMO=true            # phone or emulator
flutter run -d chrome --dart-define=DEMO=true  # browser
```

Sign in with any option (nothing is checked in demo), then pick **I drive** or **I'm a mechanic**. Screenshots are in `docs/screenshots/`.

## Go live: step by step

You need the [Supabase CLI](https://supabase.com/docs/guides/cli) and Flutter 3.x.

### 1. Database (5 min)
Supabase dashboard → **SQL Editor** → paste all of `supabase/migrations/20261003000000_autowave.sql` → **Run**.

It creates every table, rule and function, plus sample recycling prices and three sample drop-off centres (edit those to your real partners in **Table Editor → recycling_centres / recycling_rates**).

### 2. Sign-in settings
**Authentication → URL Configuration → Redirect URLs**: add `io.autowave.app://login-callback`

- **Google**: already switched on in your project. Your Google client secret belongs only there, never in the app.
- **Email**: works now. Supabase's built-in sender only allows a few emails an hour; add your own SMTP (Authentication → Emails → SMTP) before launch.
- **Phone**: currently off. Authentication → Sign In / Providers → Phone → enable and connect an SMS provider (Twilio, Vonage, MessageBird or Twilio Verify). Until then the app tells people to use email or Google.

### 3. Server secrets
```bash
supabase login
supabase link --project-ref yvhcakjqsjtvueltwpxv
supabase secrets set GOOGLE_MAPS_API_KEY=your-google-key   # address search + live ETA
supabase secrets set GEMINI_API_KEY=your-gemini-key        # AutoLearn
supabase secrets set PAYSTACK_SECRET_KEY=sk_test_...       # when you have it
```
The Google key needs **Places API (New)** and **Routes API** (both already work on your key). Optional: `GEMINI_MODEL` to pin a model.

### 4. Deploy the server functions
```bash
supabase functions deploy places eta autolearn paystack-init paystack-verify paystack-payout
supabase functions deploy paystack-webhook --no-verify-jwt
```

### 5. Paystack (when your account is ready)
- Dashboard → Settings → API Keys & Webhooks → Webhook URL:
  `https://yvhcakjqsjtvueltwpxv.supabase.co/functions/v1/paystack-webhook`
- For mechanic withdrawals: enable Transfers and turn off "OTP for transfers".
- Start with `sk_test_` keys and Paystack's test cards, then switch to `sk_live_`.

Until Paystack is connected, the wallet shows **Add test money** so you can test escrow end to end.

### 6. Scheduled jobs (recommended)
Database → Extensions → enable **pg_cron**, then in the SQL Editor:
```sql
select cron.schedule('autowave-expire', '* * * * *', 'select public.expire_stale_requests()');
select cron.schedule('autowave-auto-release', '*/30 * * * *', 'select public.auto_release_escrow()');
```
The second one pays mechanics automatically if a driver neither confirms nor disputes within 48 hours.

### 7. Run against your project
```bash
flutter run
```
The Supabase URL and publishable key are already set in `lib/core/env.dart`. They're public by design; the database rules protect the data. Test with two accounts, one driver and one mechanic, on two phones (or a phone plus the web build).

## Before-launch checklist
- [ ] `update public.app_config set allow_test_topups = false;` (removes "Add test money")
- [ ] Platform commission: `update public.app_config set platform_fee_bps = 1000;` (1000 = 10%; default is 0)
- [ ] Map tiles: the free OpenStreetMap server is for development only. Get a key from MapTiler or Stadia and build with
      `--dart-define=MAP_TILE_URL=https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=YOUR_KEY`
- [ ] Restrict your Google key to Places API (New) + Routes API in Google Cloud
- [ ] Rotate the Google client secret and Gemini key that were shared in chat
- [ ] Replace the sample recycling centres and prices with real ones
- [ ] Custom SMTP for email, SMS provider for phone sign-in

## Handling money issues (no admin screen yet)
Use the Supabase SQL Editor:
- **Disputes**: `select * from escrow_holds where status = 'disputed';` then pay the mechanic with
  `select public._escrow_release('<request_id>', 'Resolved by support');` or refund the driver with
  `select public._escrow_refund('<request_id>', 'Resolved by support');`
- **Recycling payments** after collection: `select public.pay_recycling('<recycling_request_id>', 650000);` (amount in kobo)
- **Withdrawals** waiting for manual payout: `select * from withdrawals where status = 'pending';`

## How it's built
- `lib/data/backend.dart`: everything the screens can ask the server. `supabase/` is the real implementation, `demo/` the simulation.
- `lib/features/`: `auth`, `driver`, `mechanic`, `wallet`, `recycling`, `learn`, `profile`
- `supabase/migrations/`: the whole database. All money moves in kobo inside database functions that check who is calling; the apps cannot change balances, statuses or ratings directly.
- `supabase/functions/`: Places search, ETA (Google Routes), Paystack (top-up, verify, webhook, payouts) and AutoLearn (Gemini). Secret keys live only here.
- `supabase/tests/db_test.mjs`: runs the migration in an in-memory Postgres and checks 52 rules (escrow, refunds, disputes, privacy, search):
  `cd supabase/tests && npm i @electric-sql/pglite@0.3 && node db_test.mjs`

## Known limits
- **No push notifications yet.** Updates are live while the app is open; a closed app won't alert a mechanic to a new request. Firebase Cloud Messaging is the natural next step.
- "Use my current location" shows coordinates rather than a street name (Google's reverse geocoding needs billing on your Google project).
- Location sharing stops if the mechanic force-quits mid-trip; the driver's map keeps the last position.
- No admin dashboard; see "Handling money issues" above.
- Compiles cleanly for all platforms and the full flows were tested in the web build, but it hasn't been run on a physical Android or iOS phone yet. Expect small device-specific fixes on first run.
