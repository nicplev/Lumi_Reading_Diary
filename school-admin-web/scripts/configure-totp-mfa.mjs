#!/usr/bin/env node

/**
 * Inspect or enable TOTP in the Firebase Identity Platform project used by the
 * school portal.
 *
 * Dry run (default):
 *   node scripts/configure-totp-mfa.mjs
 *
 * Apply:
 *   node scripts/configure-totp-mfa.mjs --apply
 *
 * Authentication follows the portal convention: set
 * FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH, GOOGLE_APPLICATION_CREDENTIALS, or use
 * Application Default Credentials. The credential project must match
 * FIREBASE_PROJECT_ID (defaults to lumi-ninc-au). No credential contents are
 * printed.
 */

import { readFileSync } from 'node:fs';
import { applicationDefault, cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const serviceAccountPath =
  process.env.FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH ||
  process.env.GOOGLE_APPLICATION_CREDENTIALS;
const serviceAccount = serviceAccountPath
  ? JSON.parse(readFileSync(serviceAccountPath, 'utf8'))
  : null;
const projectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  'lumi-ninc-au';

if (serviceAccount?.project_id && serviceAccount.project_id !== projectId) {
  throw new Error(
    `Refusing cross-project change: credential belongs to ${serviceAccount.project_id}, ` +
      `but the target is ${projectId}. Use the correct credential or set FIREBASE_PROJECT_ID.`,
  );
}

const app = initializeApp({
  credential: serviceAccount ? cert(serviceAccount) : applicationDefault(),
  projectId,
});
const manager = getAuth(app).projectConfigManager();
const current = await manager.getProjectConfig();
const providers = current.multiFactorConfig?.providerConfigs ?? [];
const currentTotp = providers.find((provider) => provider.totpProviderConfig);

console.log(
  JSON.stringify(
    {
      projectId,
      mfaState: current.multiFactorConfig?.state ?? 'DISABLED',
      totpState: currentTotp?.state ?? 'DISABLED',
      adjacentIntervals:
        currentTotp?.totpProviderConfig?.adjacentIntervals ?? null,
      mode: process.argv.includes('--apply') ? 'apply' : 'dry-run',
    },
    null,
    2,
  ),
);

if (!process.argv.includes('--apply')) {
  console.log('No changes made. Re-run with --apply to enable TOTP MFA.');
  process.exit(0);
}

const preservedProviders = JSON.parse(JSON.stringify(providers)).filter(
  (provider) => !provider.totpProviderConfig,
);
await manager.updateProjectConfig({
  multiFactorConfig: {
    state: 'ENABLED',
    providerConfigs: [
      ...preservedProviders,
      {
        state: 'ENABLED',
        // Accept the current interval plus one on either side (about ±30 s).
        // This tolerates modest device clock drift without Firebase's wider
        // default acceptance window.
        totpProviderConfig: { adjacentIntervals: 1 },
      },
    ],
  },
});

console.log('TOTP MFA is enabled. Run again without --apply to verify.');
