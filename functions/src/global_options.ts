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
// - serviceAccount: PINNED to the App Engine default SA — the Gen1 runtime SA —
//   so every existing IAM grant carries over unchanged (notably the
//   getComprehensionAudioUrl signBlob grant + all Firestore/Storage perms),
//   instead of Gen2's Compute Engine default SA.
setGlobalOptions({
  region: "australia-southeast1",
  serviceAccount: "lumi-ninc-au@appspot.gserviceaccount.com",
});
