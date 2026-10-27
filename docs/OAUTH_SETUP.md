# Google/Facebook OAuth setup

This implementation supports Flutter **web** in the same browser that starts login,
and Google sign-in on **Android** through Credential Manager.
It uses Node.js + Express + TypeScript and the existing SignVoice JWT/AuthSession database.
Live Google/Meta account sign-in still requires verification on the target device.
Android sends a Google ID token to the server for verification and receives normal SignVoice
sessions. The Android flow does not use browser cookies or a Conveyor callback.

## Android Google configuration

- Create a Web OAuth client and an Android OAuth client in the **same Google Cloud project**.
- Set the Web client ID/secret in the backend environment below. Never package its secret in the APK.
- Android client: package `com.example.sign_voice`, SHA-1 of the certificate signing the installed APK.
  Rebuilding with the same key or changing Conveyor does not change this SHA-1. A different signing
  key (including Play App Signing) requires its matching Android client configuration.
- Keep Google Play Services enabled; add test users while the consent screen is in Testing.
- Existing email accounts: log in by email, open **Cá nhân → Chỉnh sửa hồ sơ → Liên kết Google**, choose the same
  verified email. This preserves the account ID, password, learning data and assigned role.
  Matching email alone never silently merges accounts.
- `/auth/google/native/challenge` issues a five-minute, one-use nonce challenge. Native login/link
  verify Google's signature, Web audience, issuer, expiry, nonce and verified email on the server.
- Conveyor changes still require updating the APK API/AI endpoints. The web login callback must
  also be updated in Google Cloud; Android Credential Manager has no Conveyor redirect URI.

## Environment variables

Put these only in `backend/.env`, then restart the backend. Never put secrets in Flutter
`--dart-define`, source control, URLs, screenshots or client builds.

| Variable | Value / rule |
|---|---|
| `OAUTH_BACKEND_ORIGIN` | Exact backend origin, no path/query/fragment/trailing slash; local `http://localhost:3000`, public `https://YOUR-HOST.conveyor.cloud` |
| `OAUTH_FRONTEND_ORIGIN` | Exact browser frontend origin; local `http://localhost:8080`, public same HTTPS origin as backend |
| `GOOGLE_CLIENT_ID` | Web application OAuth client ID from Google Cloud |
| `GOOGLE_CLIENT_SECRET` | That web client's secret, server only |
| `FACEBOOK_APP_ID` | Meta app ID |
| `FACEBOOK_APP_SECRET` | Meta app secret, server only |
| `FACEBOOK_GRAPH_API_VERSION` | Explicit supported version from your Meta app dashboard (for example `v25.0`; verify availability in your app) |
| `GOOGLE_CALLBACK_URL` | Optional; otherwise backend origin + `/api/v1/auth/oauth/google/callback` |
| `FACEBOOK_CALLBACK_URL` | Optional; otherwise backend origin + `/api/v1/auth/oauth/facebook/callback` |
| `OAUTH_STATE_TTL_SECONDS` | Optional integer 60–900; default `600` |
| `WEB_ORIGIN` | Browser origin for normal app configuration |
| `CORS_ALLOWED_ORIGINS` | Comma-separated exact allowed browser origins; include `OAUTH_FRONTEND_ORIGIN` |
| `PUBLIC_ORIGIN` | Public Conveyor HTTPS origin when serving public web; blank for local development |

Existing `MONGODB_URI`, distinct strong `JWT_ACCESS_SECRET`/`JWT_REFRESH_SECRET`, `PORT`,
`NODE_ENV` and optional `SERVE_WEB` remain required by the normal backend. Provider credentials
may all be blank: backend starts and email/password, password reset and guest still work.
An incomplete provider is disabled; unsafe configured URLs produce `OAUTH_CONFIGURATION_INVALID`
on its start endpoint. Availability returns only `google`/`facebook` booleans.

HTTP is permitted only for loopback hosts (`localhost`, `127.0.0.1`, `[::1]`) outside production.
Use the same hostname/scheme for local FE and BE, with different ports permitted. For public
web, serve FE and API from the **same HTTPS origin** so refresh cookies remain first-party.
Explicit callback overrides must have the backend origin and exact provider callback path;
they cannot redirect to another host. Host, X-Forwarded-Host and redirect query parameters
never supply OAuth callback destinations.

Local development example (Google; actual credentials are intentionally omitted):

```dotenv
NODE_ENV=development
PORT=3000
SERVE_WEB=false
PUBLIC_ORIGIN=
WEB_ORIGIN=http://localhost:8080
CORS_ALLOWED_ORIGINS=http://localhost:8080,http://localhost:3000
OAUTH_BACKEND_ORIGIN=http://localhost:3000
OAUTH_FRONTEND_ORIGIN=http://localhost:8080
OAUTH_STATE_TTL_SECONDS=600
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
FACEBOOK_APP_ID=
FACEBOOK_APP_SECRET=
FACEBOOK_GRAPH_API_VERSION=
GOOGLE_CALLBACK_URL=
FACEBOOK_CALLBACK_URL=
```

Run `npm install` then `npm run dev` in `backend`; run
`flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1`
in the project directory. Browser OAuth callback route is `/#/oauth-complete`.

For Conveyor, build Flutter with `flutter build web --dart-define=API_BASE_URL=/api/v1`;
serve that build using `SERVE_WEB=true`, point Conveyor at the backend port, and set
`PUBLIC_ORIGIN`, `WEB_ORIGIN`, `OAUTH_BACKEND_ORIGIN`, `OAUTH_FRONTEND_ORIGIN` and
`CORS_ALLOWED_ORIGINS` to the exact same current `https://YOUR-HOST.conveyor.cloud` origin.
Use `NODE_ENV=production` for public deployment. Secure cookies are also used whenever the
configured backend/public origin is HTTPS, even during development. If Conveyor changes its
hostname, update environment variables **and both provider consoles**, then restart the backend.

## Provider consoles

Google: create OAuth consent/branding settings and a **Web application** client. Request only
`openid email profile`. While the consent screen is in testing, add your Google account to
the test-user allowlist. Register exact redirect URI(s):

```text
http://localhost:3000/api/v1/auth/oauth/google/callback
https://YOUR-HOST.conveyor.cloud/api/v1/auth/oauth/google/callback
```

Use your actual backend port/host. Do not register `/#/oauth-complete` as the provider callback.
Google permits localhost HTTP for development. Use separate development/production clients
if you want independent consent/configuration. This server redirect flow does not use a
browser Google SDK or client-side secret.

Meta: create an app with Facebook Login for web, configure app domains/site URL, and add the
exact **Valid OAuth Redirect URI**:

```text
https://YOUR-HOST.conveyor.cloud/api/v1/auth/oauth/facebook/callback
```

Keep the app in development mode initially and use an accepted app administrator/developer/
tester role or an app test user when Meta offers test users for your app type. Ordinary
non-role users may be blocked until the app is live and the required business/app review,
privacy policy and deletion requirements are met. Request only `public_profile,email`.
Some accounts decline or have no email: identity uses Meta's validated app-scoped user ID,
and the SignVoice account may have no email. Never invent an email address.
The backend permits HTTP localhost in development; Meta's app type/dashboard may still
require HTTPS/strict redirect settings. Use the Conveyor HTTPS callback to test Meta when
localhost is rejected. Do not disable HTTPS or redirect validation to work around provider policy.

## Flow and safety

```text
Login form: email/password (existing) | Google | Facebook | guest (existing)
  provider unavailable -> setup explanation, email/guest remain usable
  provider available -> same-tab browser redirect to backend /oauth/:provider/start
    -> HttpOnly SameSite=Lax cookie + random state/nonce + short-lived DB record
    -> provider consent -> fixed callback consumes browser/provider-bound state atomically
    -> exchange code server-side; verify Google signature/audience/issuer/expiry/nonce/email
       or Meta debug_token app/user/expiry + /me ID with appsecret_proof
    -> unique provider subject; matching local email yields explicit collision error
    -> active account + settings + real access/refresh AuthSession records
    -> HttpOnly refresh cookie -> configured /#/oauth-complete (no URL tokens)
    -> POST /oauth/complete (trusted Origin, cookie rotation)
    -> normal user/bootstrap metadata/access session -> home
```

State has a 10-minute default lifetime, binds the browser/provider/configured callback and
completion destination, and is consumed on denial and success. Google uses S256 PKCE.
Provider access/refresh tokens are never saved in User, logged, or returned to Flutter.
Suspended/deleted identities cannot authenticate. Existing email accounts are never linked
solely because a social email matches; authenticated linking is a separate future feature.
The login form keeps input on a failed attempt; callback errors show a safe explanation and
a return-to-login button. Desktop uses the existing centered card, mobile uses the full width.

Unique sparse indexes `oauth_google_subject_unique`, `oauth_facebook_subject_unique` and unique
email index enforce concurrent registration constraints. Existing MongoDB deployments must
have these indexes ready before enabling providers. MongoDB 5+ can retain older nonunique
subject indexes alongside these named unique indexes. If an old `email_1` index is nonunique,
or duplicate provider identities/emails exist, migrate after backup and a duplicate audit;
do not drop data or blindly run `syncIndexes()` in production. Missing/failed unique indexes
must be resolved before provider login is enabled.

## Verification

Without credentials, request `GET /api/v1/auth/oauth/providers` and expect both false;
`GET /api/v1/auth/oauth/google/start` returns 503 `OAUTH_DISABLED`. Verify email login and
guest creation still work. A plain `GET .../callback?code=test` cannot sign in: no valid
browser state/cookie exists. `POST .../oauth/complete` without trusted Origin returns 403;
with origin but no refresh cookie returns 401.

After filling credentials and restarting:

1. Open the matching frontend origin, choose Google or Facebook, and approve using a test user.
2. Confirm callback exact-match registration; successful login ends at the app home with the
   provider account, and reloading restores a normal rotating SignVoice session.
3. Check Network: callback redirects never contain app/provider tokens; state cookie is
   HttpOnly/Lax; refresh cookie is HttpOnly/Strict and Secure on HTTPS. Do not share tokens.
4. Cancel consent, start a new attempt after state expiry, replay an old callback, and test
   a matching existing local email. Each must display a safe error and offer email login.
5. Log out, reload and confirm authorization is gone. Suspend an identity using admin tools;
   login must be rejected. On a phone use the same public HTTPS origin, not localhost.

Automated `backend/tests/oauth.test.ts` replaces only provider fetch/Google verification
boundaries while using real routes, Mongo state/users/settings/sessions and JWT middleware.
It covers configuration, state/replay/denial, invalid identities, account collisions,
inactive users, cookie handoff/rotation, and email/guest compatibility.
Use `TEST_MONGODB_URI` pointing to a dedicated `signvoice_test_*` database and test JWT secrets,
then `npm test -- tests/oauth.test.ts tests/auth.test.ts tests/auth-security.test.ts`.
`test/oauth_test.dart` tests session bootstrap and callback error UI. These checks do not
replace a live provider consent test after you register your own apps.

Sources: [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect),
[Google ID token verification](https://developers.google.com/identity/sign-in/web/backend-auth),
[Meta manual login flow](https://developers.facebook.com/docs/facebook-login/guides/advanced/manual-flow/),
[Meta token debugging](https://developers.facebook.com/docs/facebook-login/guides/access-tokens/debugging-and-error-handling/),
[Meta securing Graph requests](https://developers.facebook.com/docs/graph-api/securing-requests/).
Meta pages returned access/rate-limit errors to the research tool during implementation;
recheck the current app dashboard and those official policies before live deployment.
