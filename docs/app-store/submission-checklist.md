# App Store submission checklist — Lumi

Maps each Apple requirement to where it is satisfied in this repo / App Store
Connect. App: **Lumi** (`com.lumi.lumiReadingTracker`), v1.0.0.

## 1. Privacy
| Requirement | Where | Status |
|---|---|---|
| Privacy Policy URL (live, public) | https://lumi-school-admin-au.web.app/legal/privacy → `school-admin-web/src/app/legal/privacy/page.tsx` | Built; **deploy portal to go live** |
| App Privacy labels (App Store Connect questionnaire) | `docs/app-store/app-privacy-labels.md` | Answers ready to paste |
| Privacy Manifest in the build | `ios/Runner/PrivacyInfo.xcprivacy` (wired into the Runner target) | Done |

## 2. Terms / EULA
| Requirement | Where | Status |
|---|---|---|
| EULA (custom Terms of Use) | https://lumi-school-admin-au.web.app/legal/terms → `school-admin-web/src/app/legal/terms/page.tsx`; paste URL/text into App Store Connect EULA field | Built; **deploy + paste URL** |

## 3. Support & contact
| Requirement | Where | Status |
|---|---|---|
| Support URL (public) | https://lumi-school-admin-au.web.app/support → `school-admin-web/src/app/support/page.tsx` | Built; **deploy portal** |
| Contact email | support@lumi-reading.com (on Support page + App Store Connect) | Done |
| In-app access to the above | Privacy / Terms / Support links in the parent + teacher "About Lumi" dialogs | Done |

## 4. App Review access
| Requirement | Where | Status |
|---|---|---|
| Working demo credentials (login-gated app) | `docs/app-store/app-review-notes.md` + `scripts/seed_demo_review_account.js` | Script ready; **run seed + verify logins** |
| App Review notes / walkthrough | `docs/app-store/app-review-notes.md` | Ready to paste |

## Pre-submission steps (in order)
1. **Deploy the school portal** so the legal/support pages are live:
   `firebase deploy --only hosting:school` — then open all three URLs in a
   browser (and confirm they load **without** signing in).
2. **Deploy Firestore rules** (includes the teacher-proxy logging fix, PR #179):
   `firebase deploy --only firestore:rules` — required for the teacher demo
   walkthrough to work.
3. **Seed the demo accounts:** run `scripts/seed_demo_review_account.js`, then
   sign in to the built app as both the teacher and the parent to confirm.
4. **Build & archive** the app (bump build number if needed) via
   `./scripts/flutter-build.sh` + Xcode archive; confirm the Xcode **Privacy
   Report** lists Lumi's manifest with no missing required-reason APIs.
5. In **App Store Connect**: set Privacy Policy URL, Support URL, EULA (Terms
   URL/text), App Privacy labels (from `app-privacy-labels.md`), and App Review
   Information (credentials + notes from `app-review-notes.md`).

## Known follow-ups (not blockers, but watch for review feedback)
- **In-app account deletion** (Guideline 5.1.1(v)): currently a documented
  request flow on the Support page; may need an in-app "Request account
  deletion" entry point in Settings if review pushes back.
- **Sign in with Apple** (Guideline 4.8): required only if Google/third-party
  sign-in is offered to end users — confirm before submitting.
