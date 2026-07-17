import {setGlobalOptions} from "firebase-functions/v2";

// Global defaults for EVERY v2 (Gen2) function, in every source file, as they
// are migrated off the v1 `fns` builder (Phase 6).
//
// This module is imported FIRST in index.ts (the deploy entrypoint) so this
// call runs before any function — in any file — is defined. That guarantees
// every migrated function inherits these defaults regardless of import order
// (a plain `setGlobalOptions(...)` in the index.ts body would run AFTER the
// top-of-file imports that define other files' functions, so cross-file
// functions could silently fall back to Gen2's us-central1 default region).
//
// - region: matches the v1 functions (australia-southeast1 / Sydney).
// - serviceAccount: a dedicated keyless runtime identity. Its narrow project
//   and resource-level grants are documented under infra/iam. Never fall back
//   to an Editor-bearing default service account. Cloud Build separately uses
//   the Compute default identity with Cloud Build Builder only.
setGlobalOptions({
  region: "australia-southeast1",
  serviceAccount:
    "lumi-functions-runtime@lumi-ninc-au.iam.gserviceaccount.com",
});
