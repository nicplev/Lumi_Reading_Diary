# Password AutoFill and verified App Links

Lumi uses the permanent marketing domain, `lumi-reading.com`, as the trust
boundary between the website and the native iOS/Android apps. The former
Flutter placeholder (`lumi-ninc-au.web.app`) is disabled and intentionally has
no deployable Hosting target in `firebase.json`.

This association adds cross-platform website/app credential sharing on top of
the in-field `autofillHints` already wired into `LumiInput`. SMS one-time-code
autofill is independent and continues to use the `oneTimeCode` hint.

## Repository configuration

| File | Purpose |
| --- | --- |
| `ios/Runner/Runner.entitlements` | Trusts `lumi-reading.com` for `webcredentials` and `applinks` |
| `android/app/src/main/AndroidManifest.xml` | Verifies only `https://lumi-reading.com/app` |
| `marketing-site/public/aasa.json` | Apple AASA payload for credentials and the exact `/app` path |
| `marketing-site/public/assetlinks.json` | Android credentials/App Links statement and signing fingerprints |
| `firebase.json` | Disables Firebase's generated association files and rewrites the two explicit JSON documents |
| `lib/core/routing/app_router.dart` | Converts the verified `/app` URL to `/splash` without trusting query parameters |

The marketing site provides a browser fallback at `/app`. If the native app is
installed and verified, the OS opens Lumi instead. Existing `lumi://` widget
links are separate and unchanged.

## Apple release requirements

The application identifier in AASA is
`C2BSJNTRU5.com.lumi.lumiReadingTracker`.

1. The Apple Developer App ID must have **Associated Domains** enabled.
2. Regenerate the distribution provisioning profile after enabling it.
3. Ship a signed build containing the updated entitlements. Existing installs
   cannot learn a new associated domain remotely.
4. Expect Apple CDN propagation and device caching. Reinstall the test build
   after the AASA file is live when validating a new association.

## Android signing requirements

The checked-in fingerprint is the certificate currently used by local Android
builds:

`D9:DF:9B:B3:CE:7D:B2:3D:78:5C:F3:B7:E7:1B:B4:9D:FF:CA:63:60:2E:08:1E:40:2A:DF:E5:B0:F0:DC:A2:EC`

Before the first Play release, add the **App signing key certificate** SHA-256
from Play Console → Test and release → App integrity to
`marketing-site/public/assetlinks.json`. Keep the local fingerprint as a second
entry only if sideloaded local builds should continue verifying.

The repository currently has no Play signing certificate registered in
Firebase and Android release builds still use the local debug signing config.
Do not treat the Android production association as complete until production
signing is configured and its fingerprint is deployed.

## Build, deploy and verify

```sh
pnpm test:domain-associations
flutter test test/core/routing/app_router_test.dart
pnpm --dir marketing-site build
firebase deploy --only hosting:marketing --project lumi-ninc-au
```

Both association URLs must return HTTP 200, JSON content, and no redirect:

```sh
curl -i https://lumi-reading.com/.well-known/apple-app-site-association
curl -i https://lumi-reading.com/.well-known/assetlinks.json
```

Also verify the retired placeholder remains unavailable:

```sh
curl -o /dev/null -w '%{http_code}\n' https://lumi-ninc-au.web.app/
```

Run `pnpm test:domain-associations` whenever the domain, bundle/package ID,
paths, signing certificates, or Firebase Hosting configuration changes.
