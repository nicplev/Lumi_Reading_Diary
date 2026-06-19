# Password AutoFill — domain association setup

Lets a Lumi password saved on the website auto-suggest in the iOS/Android
app (and vice-versa), on top of the in-field `autofillHints` already wired
into `LumiInput`. The SMS one-time-code autofill needs **none** of this — it
already works from the `oneTimeCode` hint.

## What's in the repo

| File | Purpose |
| --- | --- |
| `ios/Runner/Runner.entitlements` | `com.apple.developer.associated-domains` → `webcredentials:lumi-ninc-au.web.app` (+ `.firebaseapp.com`) |
| `web/aasa.json` | Apple App Site Association payload (`webcredentials.apps` = `C2BSJNTRU5.com.lumi.lumiReadingTracker`) |
| `web/assetlinks.json` | Android Digital Asset Links (`get_login_creds`) — **fingerprint placeholder, must be filled** |
| `firebase.json` | `appAssociation: NONE` + rewrites mapping `/.well-known/...` → the two files above |

Files in `web/` are copied into `build/web/` by `flutter build web`. They're
served via Firebase **rewrites** (not a `.well-known/` folder) because the
deploy `ignore` drops dotfiles.

## Manual steps still required

### 1. Apple Developer — enable the capability (REQUIRED, or signed builds fail)
Adding the entitlement key is not enough: the App ID must carry the
capability or code-signing breaks.
- Xcode → Runner target → **Signing & Capabilities** → **+ Capability** →
  **Associated Domains** (it picks up the entitlement entries).
- Or in the Apple Developer portal: App ID `com.lumi.lumiReadingTracker` →
  enable **Associated Domains** → regenerate provisioning profiles.

### 2. Deploy hosting so the AASA is live
```
./scripts/flutter-build.sh web      # or: flutter build web
firebase deploy --only hosting:default
```
Must be reachable over HTTPS, `Content-Type: application/json`, **no redirect**:
```
curl -sI https://lumi-ninc-au.web.app/.well-known/apple-app-site-association
curl -s  https://lumi-ninc-au.web.app/.well-known/apple-app-site-association | python3 -m json.tool
```
Apple's CDN (what devices actually fetch; may lag a few hours after deploy):
`https://app-site-association.cdn-apple.com/a/v1/lumi-ninc-au.web.app`

### 3. Android — fill in the signing fingerprint
Replace `REPLACE_WITH_RELEASE_SHA256_FINGERPRINT` in `web/assetlinks.json`
with the **release** cert SHA-256 (colon-separated hex). If using Play App
Signing, use the **App signing key** fingerprint from
Play Console → Test and release → App integrity. List multiple entries if you
also want the upload key / debug key to match.
```
keytool -list -v -keystore <release.jks> -alias <alias>   # local keystore
curl -s https://lumi-ninc-au.web.app/.well-known/assetlinks.json
```
Until this is filled, Android credential association is inactive (harmless —
in-field autofill still works).

### 4. Custom domain (if one is ever added)
If the web app moves to a custom domain (e.g. `app.golumi.com`), add
`webcredentials:<that-domain>` to the entitlement and confirm the AASA is
served there too (same Firebase hosting, so the rewrite already covers it).

## Verifying on device
- Build a signed app **with** the capability (step 1) and install it.
- Save a Lumi login in Safari/Chrome on `lumi-ninc-au.web.app`.
- Reopen the app login screen → the keyboard QuickType bar offers the saved
  credential; after a successful login the OS offers to save/update it.
- iOS caches the AASA at install/update — reinstall after the file goes live.
