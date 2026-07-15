# Firestore security-rule testing

Firestore and Storage security tests must run only against the Firebase Local
Emulator Suite. Never weaken or replace the deployed rules to make a test pass.

## Run the rule suites

From `functions/`:

```sh
npm install
npm run test:rules
npm run test:rules:storage
```

The scripts start isolated emulators, load the checked-in `firestore.rules` and
`storage.rules`, run both positive and negative cases, then stop the emulators.
They do not deploy anything.

## Add a regression test

- Firestore: `functions/test/firestore.rules.test.js`
- Storage: `functions/test/storage.rules.test.js`

Every new allow rule needs a matching denial test for the nearest other role,
class, family and school. Use `withSecurityRulesDisabled` only to seed emulator
fixtures; all assertions must use authenticated or unauthenticated test
contexts with rules enabled.

## Deployment safety

Only the reviewed rules referenced by `firebase.json` may be deployed. Before
deploying, run both suites and inspect the diff. There is intentionally no
"temporary permissive production rules" procedure: a broad authenticated-user
allow exposes children's data to every account in the project.
