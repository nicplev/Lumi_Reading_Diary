# Beta Day-1 Provisioning Checklist (per school)

Run this **before** the first family opens the app. The access model is
fail-closed: a student without a live `access` map means every parent hits
"access lapsed — contact your school office" on night one. Nothing on this
list is optional.

Legend: 🧑‍💻 = you (console/portal/terminal) · ✅ = verify before moving on.

## 1. Platform prerequisites (once, not per school)

- [ ] 🧑‍💻 `config/academicYear` exists with the current `currentAcademicYear`.
      Without it, parent-link auto-grants **silently no-op** and the January
      rollover aborts. (The backfill script in §3 creates it if missing.)
- [ ] ✅ Firebase console → Firestore → `config/academicYear` shows the right year.

## 2. School setup

- [ ] 🧑‍💻 Create the school (super-admin portal) **and** its
      `schoolSubscriptions/{schoolId}_{year}` row with status `active`
      (or let §3 seed a `comp` row for beta).
- [ ] 🧑‍💻 School portal → **Settings**:
      - [ ] `Timezone` set (e.g. `Australia/Sydney`) — drives streaks,
            reminders, dashboards, Top Reader week.
      - [ ] **Term Dates** entered for the year — drives holiday-proof streaks,
            the Top Reader holiday pause, and analytics term periods.
      - [ ] Quiet hours, reading levels, parent-comment settings as the school
            wants them.
- [ ] 🧑‍💻 Import students (portal → Students → CSV import) and assign classes +
      teachers.

## 3. Access entitlement (THE landmine)

```bash
npm --prefix functions run build          # once, so lib/access.js exists
gcloud auth application-default login     # once per machine

# Preview, then apply — idempotent, grant-only (never suspends):
node functions/scripts/backfill-access.cjs --school <schoolId> --dry-run
node functions/scripts/backfill-access.cjs --school <schoolId>
```

- [ ] ✅ Spot-check 2–3 `schools/{id}/students/{id}` docs: `access.status ==
      'active'`, `academicYear` current, `expiresAt` ≈ next 31 Jan.
- [ ] ✅ `school.access.status == 'active'`.
- [ ] Students imported **later** get access when their parent links (auto
      `book_pack_assumed` grant) — but only because §1 + the subscription row
      exist. Re-run the backfill after any bulk mid-year import.

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
