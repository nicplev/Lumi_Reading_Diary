# App Review notes — App Store Connect

Paste the relevant parts into **App Store Connect → Version → App Review
Information** (Sign-in required: **Yes**; plus the "Notes" field).

## Demo credentials (sign-in required)

Lumi is school-mediated: normal users join with a school/link code, and sign-in
can use a phone one-time code. To give reviewers friction-free access, run the
demo seed (see below), which creates **email + password** logins with **no SMS
step**.

| Role | Email | Password |
|---|---|---|
| Teacher | `review.teacher@lumi-reading.com` | `<set in App Store Connect; not stored in Git>` |
| Parent | `review.parent@lumi-reading.com` | `<set in App Store Connect; not stored in Git>` |

> Both accounts sign in with **email + password only** — no SMS / one-time code
> is required. (If you set `DEMO_PASSWORD` when seeding, use that value instead.)

### Seeding the demo data
From the repo root, with admin credentials for the `lumi-ninc-au` project:

```sh
FIREBASE_ADMIN_SERVICE_ACCOUNT_PATH=/abs/path/to/service-account.json \
  node scripts/seed_demo_review_account.js
```

This creates a demo school, class, one student ("Riley Reader") with live
access, the two logins above, and two sample reading logs. It is idempotent.
**Verify both logins yourself in the built app before submitting.**

## Notes field (suggested text)

> Lumi is a reading diary used by schools and families to track children's
> reading. Reviewer accounts are provided above and sign in with email and
> password (no SMS code needed).
>
> To see the core flow:
> 1. Sign in as the **teacher**. Open "Demo Class" → the student "Riley Reader".
>    Tap **Log** to record a reading session on the student's behalf (choose a
>    book, minutes, and save).
> 2. Sign in as the **parent** to see the family view of the same child and log
>    a reading session for them.
>
> The optional "comprehension" voice recording is a school-controlled feature
> and is off by default. The app contains no user-generated public content,
> advertising, or tracking.

## Other review-readiness reminders
- **Privacy Policy URL:** https://lumi-school-admin-au.web.app/legal/privacy
- **Support URL:** https://lumi-school-admin-au.web.app/support
- **EULA:** custom Terms of Use — paste
  https://lumi-school-admin-au.web.app/legal/terms into the EULA field (or its
  full text).
- **Contact email:** support@lumi-reading.com
- These pages must be **live** before submitting — deploy the school portal
  (`firebase deploy --only hosting:school`).
- **Account deletion (Guideline 5.1.1(v)):** the Support page documents how a
  user requests deletion via support@lumi-reading.com. If review asks for an
  in-app deletion entry point, add a "Request account deletion" link in Settings.
- **Sign in with Apple (Guideline 4.8):** only required if Google/third-party
  sign-in is offered to users. Confirm whether Google sign-in is user-facing
  before submitting.
