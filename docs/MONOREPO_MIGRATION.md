# Monorepo Migration Runbook: lumi-admin → lumi_reading_tracker

> **For Claude (or any future session):** This is a stateful runbook. Read the **STATUS** block first. Then read the phase that matches `current_phase`. Verify state with `git status` and `git log` *before* acting — the on-disk reality wins over what this doc says. Update STATUS after every completed step.

---

## STATUS

```yaml
current_phase: 1
current_phase_name: "Ready for subtree import (awaiting layout confirmation)"
last_completed_step: "0.4"
last_action_at: "2026-05-05"
last_action_summary: "Phase 0 complete — pre-monorepo-merge tags pushed on both repos; monorepo-migration branch created and pushed."
blockers:
  - "Open question: confirm flat vs apps-prefixed layout before Phase 1.2 subtree import."
chosen_layout: "flat"   # see "Layout decision" below — options: "flat" | "apps-prefixed"
notes_for_resumer: |
  Phase 0 done. Tags pre-monorepo-merge exist on both nicplev/Lumi_Reading_Diary and nicplev/lumi-admin.
  Working branch: monorepo-migration (tracking origin/monorepo-migration).
  lumi-admin default branch confirmed: main.
  DO NOT begin Phase 1.2 (the subtree add) until the user has confirmed the chosen layout.
```

### Decisions log
*(append-only — never rewrite history here, just add new entries)*

- **2026-05-05** — Runbook created. Recommendation: keep Flutter at repo root (`flat` layout) rather than relocating to `apps/mobile/`, because relocating breaks `firebase.json`, `ios/`, `android/`, and IDE config. Subject to user confirmation before Phase 1.
- **2026-05-05** — Use `git subtree` (not submodules) to import lumi-admin so history is preserved as real commits in this repo and there's no second clone step for collaborators.
- **2026-05-05** — Phase 0 executed. Tag `pre-monorepo-merge` pushed to both repos. Branch `monorepo-migration` created and pushed on the main repo. lumi-admin default branch confirmed as `main` (relevant for Phase 1.2 subtree command).

### Open questions for the user
*(resolve before the indicated phase)*

- [ ] **Before Phase 1:** confirm `flat` layout (admin lives at `./admin/`) vs `apps-prefixed` (mobile relocates to `./apps/mobile/`, admin to `./apps/admin/`). Default = `flat`.
- [ ] **Before Phase 4:** confirm migration of admin auth from `ADMIN_EMAILS` env allowlist to `/superAdmins` Firestore collection. This is recommended but is a behavior change.
- [ ] **Before Phase 6:** which CI provider for the admin app? (GitHub Actions assumed unless stated otherwise.)

---

## Resumption checklist (read this every session)

1. Read **STATUS** block above.
2. Run from `/Users/nicplev/lumi_reading_tracker`:
   - `git status` — must be clean (or you must understand the diff)
   - `git log --oneline -10` — confirm nothing unexpected
   - `git branch -a | grep -i monorepo` — see what migration branches/tags exist
3. Run from `/Users/nicplev/lumi-admin`:
   - `git status` — must be clean
   - `git log --oneline -5` — confirm head
4. Read the phase named in `current_phase_name`. Do **only the next unchecked step**, then update STATUS.
5. If anything looks off (unexpected files, branches, conflicts), **stop and ask the user** rather than improvising. There is a memory note that destructive git ops have caused lost work before.

---

## Goal & non-goals

**Goal:** consolidate `lumi-admin` (Next.js super-admin portal) into the `lumi_reading_tracker` repo so that:
- Firestore schema, security rules, and Cloud Functions live in one place and one PR can change all consumers atomically.
- Admin auth uses the same source of truth as the mobile app (`/superAdmins` collection) instead of an env allowlist.
- TypeScript types for Firestore documents are shared, not duplicated.
- lumi-admin's git history is preserved as real commits in this repo.

**Non-goals (explicitly out of scope):**
- Rewriting the admin UI.
- Migrating the Flutter codebase to TypeScript or vice-versa.
- Changing deployment targets for either app (admin still deploys independently from Flutter).
- Combining build pipelines into one (each app keeps its own CI job).

---

## Layout decision

### Option A — `flat` (RECOMMENDED, default)

```
lumi_reading_tracker/
├── lib/                 # Flutter app (unchanged)
├── ios/  android/  web/ # Flutter platforms (unchanged)
├── pubspec.yaml         # Flutter manifest (unchanged)
├── functions/           # existing Cloud Functions (unchanged)
├── firestore.rules      # existing (unchanged)
├── firestore.indexes.json
├── firebase.json
├── admin/               # NEW — lumi-admin Next.js app, full history preserved
│   ├── src/
│   ├── package.json
│   └── ...
├── packages/
│   └── types/           # NEW — shared TS types, consumed by admin/
└── docs/MONOREPO_MIGRATION.md
```

**Pros:** zero change to Flutter paths; firebase.json unchanged; iOS/Android build configs unchanged; CI for Flutter unchanged.
**Cons:** asymmetric (mobile at root, admin in subdir).

### Option B — `apps-prefixed`

```
lumi_reading_tracker/
├── apps/
│   ├── mobile/          # Flutter relocates here
│   └── admin/           # lumi-admin
├── packages/types/
├── functions/
└── firestore.rules
```

**Pros:** symmetric, scales if a third app appears.
**Cons:** every Flutter path reference in `firebase.json`, IDE configs, iOS/Android build scripts, GitHub Actions, and any docs has to change. Higher risk of breakage. The git move alone is mechanical, but the cleanup ripples through the codebase.

**Recommendation: Option A unless the user wants the symmetry.** This runbook assumes Option A unless `chosen_layout` in STATUS is changed to `apps-prefixed`.

---

# Phase 0 — Backups & tags (DO THIS FIRST, ALWAYS)

**Goal:** create immutable rollback points on GitHub before any structural change.

**Pre-flight:**
- Both repos clean: `git status` in each shows nothing.
- Both repos pushed to origin: `git status` shows "up to date with origin/main" (or equivalent).

**Steps:**

- [ ] **0.1** Tag the main repo's current state.
  ```bash
  cd /Users/nicplev/lumi_reading_tracker
  git tag -a pre-monorepo-merge -m "Snapshot before lumi-admin monorepo merge"
  git push origin pre-monorepo-merge
  ```

- [ ] **0.2** Tag the lumi-admin repo's current state.
  ```bash
  cd /Users/nicplev/lumi-admin
  git tag -a pre-monorepo-merge -m "Snapshot before being merged into lumi_reading_tracker"
  git push origin pre-monorepo-merge
  ```

- [ ] **0.3** Push current `main` of both repos (if not already) so the rollback target is on GitHub, not just local.
  ```bash
  cd /Users/nicplev/lumi_reading_tracker && git push origin main
  cd /Users/nicplev/lumi-admin && git push origin main   # or `master` — verify branch name first
  ```

- [ ] **0.4** Create a long-lived backup branch on the main repo so the migration work is isolated:
  ```bash
  cd /Users/nicplev/lumi_reading_tracker
  git checkout -b monorepo-migration
  git push -u origin monorepo-migration
  ```
  All subsequent migration commits go on `monorepo-migration`. `main` stays untouched until Phase 7.

**Verify:**
- `git tag -l pre-monorepo-merge` returns the tag in both repos.
- GitHub shows the tag under each repo's "tags" page.
- `git branch --show-current` returns `monorepo-migration` in the main repo.

**Rollback:** N/A — this phase is only additive (creating tags/branches).

**Update STATUS:** set `current_phase: 1`, `last_completed_step: "0.4"`, log decisions/notes.

---

# Phase 1 — Import lumi-admin via git subtree

**Goal:** bring lumi-admin into this repo at `./admin/` (Option A) **with full history preserved**, as one merge commit on `monorepo-migration`.

**Pre-flight:**
- Phase 0 complete.
- On branch `monorepo-migration`.
- `./admin/` does NOT exist in the main repo.
- lumi-admin remote URL noted: `https://github.com/nicplev/lumi-admin.git`.
- lumi-admin's default branch confirmed (run `cd /Users/nicplev/lumi-admin && git remote show origin | grep "HEAD branch"`).

**Steps:**

- [ ] **1.1** Add lumi-admin as a remote on the main repo.
  ```bash
  cd /Users/nicplev/lumi_reading_tracker
  git remote add lumi-admin-src https://github.com/nicplev/lumi-admin.git
  git fetch lumi-admin-src
  ```

- [ ] **1.2** Import via subtree into `admin/` (replace `<branch>` with the actual default branch from pre-flight).
  ```bash
  git subtree add --prefix=admin lumi-admin-src <branch>
  ```
  This creates a single merge commit; the lumi-admin history becomes part of `git log -- admin/`.

- [ ] **1.3** Sanity check the import.
  ```bash
  ls admin/                              # should show src/, package.json, etc.
  git log --oneline -- admin/ | head -5  # should show real lumi-admin commits, not one squash
  ```

- [ ] **1.4** **Do not** push yet. Read the next step first — there's a `.gitignore` reconciliation to do.

- [ ] **1.5** Reconcile `.gitignore`. The Flutter `.gitignore` will ignore some things the Next.js app needs (or vice versa). Specifically check:
  - `admin/node_modules/` — must be ignored (likely already is by lumi-admin's own `admin/.gitignore`).
  - `admin/.next/` — must be ignored.
  - `admin/.env.local` — must be ignored. **CRITICAL: this file contains the service account key.** Run `git ls-files admin/ | grep -i env` and confirm no env file is tracked.
  - Any Flutter-specific patterns in root `.gitignore` that might accidentally match admin paths.

- [ ] **1.6** Verify no secrets were imported. lumi-admin's history may contain accidentally-committed env files even if they're now gitignored.
  ```bash
  git log --all --full-history --source -- 'admin/.env*' 'admin/**/serviceAccount*.json'
  ```
  If anything shows up: STOP. Talk to the user. Do not push the `monorepo-migration` branch until secrets are scrubbed (likely via `git filter-repo` on lumi-admin's history *before* re-importing).

- [ ] **1.7** If clean, push the migration branch.
  ```bash
  git push origin monorepo-migration
  ```

**Verify:**
- `admin/` exists and contains the Next.js codebase.
- `git log --oneline | head -20` shows a merge commit + lumi-admin's commits.
- `git log -- admin/package.json` shows lumi-admin's history, not just one commit.
- No env files / service account keys are tracked.
- GitHub PR view of `monorepo-migration` vs `main` shows ~208 files added under `admin/`.

**Rollback:**
- The import is a single commit/merge. To undo *before pushing*: `git reset --hard origin/monorepo-migration` (back to the state at Phase 0.4).
- After pushing: revert the merge with `git revert -m 1 <merge-sha>` (non-destructive — keeps history).
- **Never** force-push to overwrite the import; use revert.

**Update STATUS:** set `current_phase: 2`, log the merge SHA and any reconciliation done.

---

# Phase 2 — Inventory & schema overlap audit

**Goal:** before changing any code, document what overlaps. This phase produces an artifact (`docs/MONOREPO_OVERLAP.md`) used as input for Phases 3–5.

**Pre-flight:**
- Phase 1 complete.
- Admin code present at `admin/`.

**Steps:**

- [ ] **2.1** List all Firestore collections written or read by `admin/src/app/api/**`.
  ```
  Grep target paths: admin/src/app/api/
  Search for: getFirestore, .collection(, .doc(, getAdminDb
  ```
  Record: collection path → admin route → operation (read/write/delete).

- [ ] **2.2** List all TypeScript types in `admin/src/lib/types/` and map each to the corresponding Dart class in `lib/models/` (or wherever Flutter models live).
  Record mismatches: fields present in one but not the other, type differences (e.g., `Timestamp` vs `DateTime`).

- [ ] **2.3** List all admin API routes that perform "business logic" (not pure CRUD): anything that does multi-document writes, computes derived fields, sends notifications, or updates audit trails. These are Phase 5 candidates for migration into Cloud Functions.

- [ ] **2.4** Diff the auth model:
  - lumi-admin: `admin/src/lib/auth/**` (uses `ADMIN_EMAILS` env).
  - main app: `functions/src/**` `isSuperAdmin()` (uses `/superAdmins/{uid}` collection + `SUPER_ADMIN_UIDS` env fallback).
  Record both code locations.

- [ ] **2.5** Write `docs/MONOREPO_OVERLAP.md` with three sections:
  - **Schema overlap** — table of collections and which TS/Dart types describe them.
  - **Logic to migrate** — list of admin API routes that should become Cloud Functions.
  - **Auth unification plan** — concrete diff of how `ADMIN_EMAILS` callers will be replaced.

**Verify:**
- `docs/MONOREPO_OVERLAP.md` exists, is committed, and is reviewed by the user.

**Rollback:** N/A — read-only phase except for the new doc.

**Update STATUS:** set `current_phase: 3`. Note the overlap doc as the source of truth for the next two phases.

---

# Phase 3 — Extract shared types into `packages/types`

**Goal:** single TypeScript source of truth for Firestore document shapes, consumed by `admin/`. (The Flutter app continues to use Dart classes; we keep them in sync via the overlap doc, not codegen, unless the user wants to add codegen later.)

**Pre-flight:**
- Phase 2 complete and `docs/MONOREPO_OVERLAP.md` exists.
- The user has approved the type-extraction approach.

**Steps:**

- [ ] **3.1** Create the package skeleton.
  ```bash
  mkdir -p packages/types/src
  ```
  Add `packages/types/package.json` with name `@lumi/types`, `private: true`, `main: "src/index.ts"`. No build step needed if admin imports `.ts` directly via Next.js's TS support.

- [ ] **3.2** Set up workspace resolution. Add to root `package.json` (create if missing — keep minimal, do NOT introduce a root build):
  ```json
  {
    "private": true,
    "workspaces": ["admin", "packages/*"]
  }
  ```
  Use the same package manager lumi-admin already uses (check `admin/package-lock.json` vs `pnpm-lock.yaml` vs `yarn.lock`).

- [ ] **3.3** Move the 18 type definitions from `admin/src/lib/types/` into `packages/types/src/`. Re-export them from `packages/types/src/index.ts`.

- [ ] **3.4** Update `admin/` imports from `@/lib/types/...` to `@lumi/types`.

- [ ] **3.5** Add `@lumi/types` as a dependency in `admin/package.json`.
  ```json
  "dependencies": {
    "@lumi/types": "workspace:*"
  }
  ```

- [ ] **3.6** Reinstall and typecheck.
  ```bash
  cd admin && <pkg-manager> install && <pkg-manager> run typecheck
  ```

- [ ] **3.7** Commit as one logical change: `chore(types): extract shared @lumi/types package`.

**Verify:**
- `admin/` builds (`<pkg-manager> run build` from `admin/`).
- No `import` of types from `@/lib/types/...` remains in `admin/src/`.
- `packages/types/src/index.ts` re-exports all types.

**Rollback:**
- Single commit — `git revert <sha>` if needed.

**Update STATUS:** `current_phase: 4`.

---

# Phase 4 — Unify admin auth onto `/superAdmins` collection

**Goal:** stop using `ADMIN_EMAILS` env var; use the existing `isSuperAdmin()` mechanism so admin access is managed in one place (Firestore, not env vars).

**Pre-flight:**
- Phase 3 complete.
- The user has confirmed the open question about auth migration in STATUS.
- A test/dev superadmin already exists in `/superAdmins/{uid}` for the user's own account (otherwise they'll lock themselves out).

**Steps:**

- [ ] **4.1** Locate the admin auth gate (likely `admin/src/lib/auth/...` per Phase 2.4).

- [ ] **4.2** Replace the email allowlist check with a `/superAdmins/{uid}` lookup using the Admin SDK. The check should:
  1. `verifyIdToken()` to get the UID (existing behavior — keep).
  2. Read `/superAdmins/{uid}` — if it exists, allow; else 403.
  3. Keep the `auth_time` freshness check (existing behavior — keep).

- [ ] **4.3** Make the `ADMIN_EMAILS` fallback opt-in via a clearly-named env (e.g. `ADMIN_EMAILS_LEGACY_FALLBACK=true`) for emergency lock-out recovery, OR remove it entirely if the user has confirmed they have a Firestore `/superAdmins` entry.

- [ ] **4.4** Test from a logged-in browser session: confirm a known superadmin can still load `/admin/...`. Confirm a non-admin gets 403.

- [ ] **4.5** Commit: `feat(admin): unify auth on /superAdmins collection`.

**Verify:**
- Manual auth test passes for both an admin and a non-admin.
- Cloud Functions logs show no auth regressions for the same user (i.e., the user can still hit Cloud Functions that gate on `isSuperAdmin`).

**Rollback:**
- Revert the auth commit. The `ADMIN_EMAILS` env path is restored. **If the user gets locked out:** they re-enable the legacy fallback (4.3) or temporarily add their UID to `SUPER_ADMIN_UIDS` env in Cloud Functions config.

**Update STATUS:** `current_phase: 5`.

---

# Phase 5 — Migrate business-logic admin routes to Cloud Functions (selective)

**Goal:** for each admin route flagged in Phase 2.3 as "business logic" (not pure CRUD), move the logic into a callable Cloud Function in `functions/`. The admin UI then calls the function instead of writing Firestore directly via Admin SDK.

**Why:** keeps the write path identical between mobile app and admin, so validation, transactions, and audit trails happen in one place.

**Scope guard:** *do not* migrate every admin route — that's busywork. Only migrate routes that:
- Write to multiple documents in one logical operation.
- Compute derived state (e.g., re-calculating reading levels).
- Touch user-sensitive data (impersonation, deletions, role changes).
- Need an audit trail.

Pure list/get/edit-one-field CRUD stays as direct Admin SDK calls.

**Pre-flight:**
- Phase 4 complete.
- `docs/MONOREPO_OVERLAP.md` Phase 2.3 list reviewed and prioritized with the user.

**Steps:** *(repeat per route)*

- [ ] **5.x.1** Pick one route from the prioritized list. Update STATUS `last_action_summary` with which one.
- [ ] **5.x.2** Implement the equivalent callable Cloud Function in `functions/src/`. Reuse `isSuperAdmin()` for auth.
- [ ] **5.x.3** Add a thin admin-side client that calls the function. Keep the admin UI unchanged — just swap the API route's body.
- [ ] **5.x.4** Test in dev. Compare before/after Firestore state.
- [ ] **5.x.5** Commit per-route, e.g. `refactor(admin): route school deletion through deleteSchool callable`.

**Verify (per route):**
- Old behavior unchanged from the admin UI's perspective.
- Cloud Functions logs show the call.
- Firestore state matches what the old direct-write produced.

**Rollback:**
- Per-commit revert. The admin UI still has the old path until the Cloud Function is wired in.

**Update STATUS:** `current_phase: 6` only when all prioritized routes are migrated. Lower-priority routes can be left as direct Admin SDK calls.

---

# Phase 6 — CI/CD for the admin app

**Goal:** add a GitHub Actions workflow (or whatever CI the user picks) that builds and deploys `admin/` independently of the Flutter app, scoped to `paths: ['admin/**', 'packages/types/**']` so it doesn't run on Flutter-only changes.

**Pre-flight:**
- Phase 5 complete (or paused with user's blessing).
- User has confirmed CI provider and admin deployment target (Vercel, Cloud Run, Firebase Hosting, etc.).

**Steps:**

- [ ] **6.1** Add `.github/workflows/admin-ci.yml` with `paths` filter and steps: install, typecheck, lint, build.
- [ ] **6.2** Add `.github/workflows/admin-deploy.yml` for the deploy target. Use repo secrets for the service account / deploy key (same one currently used by lumi-admin's existing deploy, if any).
- [ ] **6.3** Verify the existing Flutter CI (if any) is *not* triggered by changes under `admin/**`.
- [ ] **6.4** Open a no-op PR touching only `admin/` to confirm only admin CI runs.
- [ ] **6.5** Open a no-op PR touching only Flutter files to confirm only Flutter CI runs.

**Verify:**
- Both PRs from 6.4/6.5 show only the expected workflow runs.
- Admin deploy succeeds against a staging environment, not prod, on first run.

**Rollback:**
- Disable workflows by deleting the YAML files.

**Update STATUS:** `current_phase: 7`.

---

# Phase 7 — Merge to `main` and decommission lumi-admin standalone repo

**Goal:** ship the migration; archive the standalone lumi-admin repo so future commits all happen in the monorepo.

**Pre-flight:**
- Phases 0–6 complete.
- User has confirmed they're ready for the cutover.
- Admin app is deployed from the monorepo (Phase 6) and verified in prod.

**Steps:**

- [ ] **7.1** Open PR `monorepo-migration` → `main` on GitHub. Title: "feat(monorepo): merge lumi-admin under ./admin/". Body: link this runbook, summarize phases.
- [ ] **7.2** Squash? **No.** Use a regular merge commit so subtree history is preserved. Confirm GitHub merge setting before clicking.
- [ ] **7.3** After merge, delete the local `lumi-admin-src` remote: `git remote remove lumi-admin-src`.
- [ ] **7.4** Archive the standalone `nicplev/lumi-admin` GitHub repo (Settings → Archive). Add a README pointer to `nicplev/Lumi_Reading_Diary` in the archived repo before archiving.
- [ ] **7.5** Update any external references (docs, deploy dashboards, Linear, Notion) pointing at the old repo.
- [ ] **7.6** Tag the post-merge state on the monorepo:
  ```bash
  git checkout main && git pull
  git tag -a post-monorepo-merge -m "lumi-admin merged under ./admin/"
  git push origin post-monorepo-merge
  ```

**Verify:**
- `main` contains `admin/` with full history.
- Old lumi-admin repo is archived (read-only).
- Production admin app deploys from the monorepo.

**Rollback:**
- The pre-merge state is captured by the `pre-monorepo-merge` tag and the `monorepo-migration` branch. To roll back: revert the merge commit on `main` (non-destructive). The standalone lumi-admin repo can be un-archived via GitHub settings if needed.

**Update STATUS:** `current_phase: done`. Add a final entry to the decisions log.

---

## Appendix A — Common pitfalls

- **Workspace package manager mismatch.** If lumi-admin uses pnpm and you initialize the workspace with npm, lockfiles fight. Match what's in `admin/`.
- **Next.js + monorepo path resolution.** `next.config.js` may need `transpilePackages: ['@lumi/types']` if Next complains about ESM/TS imports from outside `admin/`.
- **Firebase emulator config.** If the admin app expects to talk to emulators in dev, the `firebase.json` `emulators` block needs ports that don't collide with the Flutter web app.
- **Service account keys.** Never commit the `.env.local` from lumi-admin. Phase 1.6 enforces this.
- **iOS/Android paths.** If `chosen_layout: apps-prefixed` is selected later, every relative path in `ios/Runner.xcworkspace` / `android/app/build.gradle` may need attention. This is why `flat` is the default.

## Appendix B — Useful commands

```bash
# See what changed under admin/ since the import
git log --oneline -- admin/

# See lumi-admin's original commits in the merged history
git log --oneline --no-merges -- admin/ | head -20

# Pull future updates from a still-active lumi-admin remote (if you keep it temporarily)
git fetch lumi-admin-src
git subtree pull --prefix=admin lumi-admin-src <branch> --squash

# Find tracked secrets accidentally
git ls-files | grep -E '\.env|serviceAccount.*\.json|credentials' || echo "none tracked"
```

## Appendix C — When things go wrong

- **You forgot to update STATUS and don't know where you are:**
  1. `git log --oneline origin/monorepo-migration..HEAD` — see what local commits exist.
  2. `git log --oneline -20 monorepo-migration` — match commit messages to phase steps.
  3. Update STATUS based on what's actually committed, then proceed.
- **A phase commit broke something and you can't tell which:**
  1. `git bisect start && git bisect bad HEAD && git bisect good pre-monorepo-merge`
  2. Bisect through to find the breaking commit. Revert it (don't reset).
- **You're not sure if the user wants you to continue:** stop and ask. Auto mode is not a license to push through ambiguous decisions in a multi-day migration.
