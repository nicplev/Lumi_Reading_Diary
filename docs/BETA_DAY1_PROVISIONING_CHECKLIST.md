# Beta Day-1 Provisioning Checklist (per school)

Run this **before** the first family opens the app. The access model is
fail-closed: a student without a live `access` map means every parent hits
"access lapsed — contact your school office" on night one. Nothing on this
list is optional.

Legend: 🧑‍💻 = you (console/portal/terminal) · ✅ = verify before moving on.

## 1. Platform prerequisites (once, not per school)

- [ ] 🧑‍💻 `config/academicYear` — **now self-healing.** Parent-link auto-grants
      derive the year from today when it's missing (no longer a silent no-op),
      and the portal "Activate access" button (§3) creates it. Still worth
      confirming it exists with the right `currentAcademicYear` for the annual
      rollover cron.
- [ ] ✅ Firebase console → Firestore → `config/academicYear` shows the right year.

## 2. School setup

- [ ] 🧑‍💻 Create the school (super-admin portal). Leave **"Activate School
      Access now"** ticked (default) to switch the school on with a free `comp`
      subscription for the current year in the same step — that's the master
      on-switch, so future parent-links auto-grant and §3 becomes a formality.
      Untick it only for a real prospect you'll bill deliberately later.
- [ ] 🧑‍💻 To turn a school on/off later (e.g. temp demo access), set its
      subscription status on the school's **Subscription tab** — `comp`/`paid`
      switches it on (and provisions any un-provisioned students); `unpaid`/
      `cancelled` suspends it.
- [ ] 🧑‍💻 School portal → **Settings**:
      - [ ] `Timezone` set (e.g. `Australia/Sydney`) — drives streaks,
            reminders, dashboards, Top Reader week.
      - [ ] **Term Dates** entered for the year — drives holiday-proof streaks,
            the Top Reader holiday pause, and analytics term periods.
      - [ ] Quiet hours, reading levels, parent-comment settings as the school
            wants them.
- [ ] 🧑‍💻 Import students (portal → Students → CSV import) and assign classes +
      teachers.

## 3. Access entitlement (was THE landmine — now self-serve)

**Primary path — the portal (no terminal):** the school subscription row
(§2) must be active, then on the **admin dashboard** a card appears —
*"N students can't log reading yet"* → **Activate reading for N students**.
One click grants every imported student access for the current year. It's
idempotent (re-click any time; already-active students are skipped) and also
fires automatically when you **Mark a student subscribed**.

- [ ] ✅ On the admin dashboard, confirm the access card is **gone** (or shows
      0) after activating — that means every active student can log reading.
- [ ] If the card says *"contact Lumi"* instead of showing a button, the
      school subscription for the year isn't active yet — fix §2 first.

**Fallback — the ops script** (bulk across many schools, or no portal access):

```bash
npm --prefix functions run build          # once, so lib/access.js exists
gcloud auth application-default login     # once per machine

# Preview, then apply — idempotent, grant-only (never suspends):
node functions/scripts/backfill-access.cjs --school <schoolId> --dry-run
node functions/scripts/backfill-access.cjs --school <schoolId>
```

- [ ] ✅ Spot-check 2–3 `schools/{id}/students/{id}` docs: `access.status ==
      'active'`, `academicYear` current, `expiresAt` ≈ next 31 Jan.
- [ ] Students imported **later** get access automatically when their parent
      links (the grant now derives the year even if config is missing) — or
      re-run the dashboard **Activate** after a bulk mid-year import.

## 4. Families

- [ ] 🧑‍💻 Generate parent link codes (portal → Parents/Guardians) and send the
      onboarding emails/QRs.
- [ ] ✅ **Dry-run one family end-to-end yourself**: redeem a link code on a
      test device → the child appears → log a reading session → it lands in
      Firestore and on the teacher dashboard. This single test exercises the
      whole entitlement chain.
- [ ] Note families with no smartphone/email — their teacher will use
      teacher-proxy logging; tell the teacher who they are.

## 5. Classroom devices

- [ ] 🧑‍💻 Each kiosk iPad: set the **Lumi exit PIN** + enable **Guided Access**
      — follow `docs/KIOSK_GUIDED_ACCESS_GUIDE.md`.
- [ ] 🧑‍💻 School IT: allowlist Firebase/Google endpoints
      (`*.googleapis.com`, `*.firebaseio.com`, `firestore.googleapis.com`) and
      note the app's connectivity probe also calls `https://1.1.1.1/cdn-cgi/trace`
      — if the filter blocks it, the app may show an "offline" banner on a
      working network.

## 6. Staff

- [ ] ✅ Every teacher can sign into the **app**; every admin can sign into the
      **portal** (if MFA-enrolled, verify the portal's SMS challenge works —
      first release carrying the MFA login flow needs one real test).
- [ ] Relief-teacher plan: only an admin can add cover to `teacherIds` (portal)
      — agree who does this on the day.

## 7. Monitoring & escalation

- [ ] ✅ Crashlytics + Analytics visible for the release build.
- [ ] Status worker ready (`scripts/status-message.sh`) — banner for outages,
      and `minAppVersion` in the payload now force-updates old builds.
- [ ] Agreed feedback channel for teachers + a named contact for "it's not
      working" moments (first week matters most).

## Known cliff to diary-note

**~25 Jan**: the rollover cron advances the year and access hard-expires
**31 Jan**. Renewals (portal → Renewals) must be completed before AU
back-to-school or every parent is locked out at the worst possible moment.
Put a calendar reminder on 15 Jan now.
