# Admin Parent Linking Runbook (Beta)

## Scope
Operational sequence for school admins:
1. Import students
2. Generate parent link codes
3. Export CSV
4. Distribute to families
5. Track and follow up
6. Revoke/unlink when required

## Preconditions
- Admin account is active and can access `/admin/parent-linking`.
- Classes and students exist in `schools/{schoolId}/classes` and `schools/{schoolId}/students`.
- School onboarding status is `active`.

## Standard Flow
1. **Import students**
   - Use Admin student import flow.
   - Verify each student has:
     - `id`
     - `studentId` (school identifier)
     - `classId`
     - `firstName` and `lastName`

2. **Generate link codes**
   - Open **Parent Linking Codes** screen.
   - Click **Generate All Missing Codes**.
   - Confirm modal.
   - Wait for completion snackbar.

3. **Export CSV**
   - Use snackbar action **Export CSV** or top-right download icon.
   - Output columns:
     - `Student Name`
     - `Student ID`
     - `Class`
     - `Link Code`
     - `Code Status`
     - `Created At`
     - `Expires At`
     - `Linked Parent Count`
   - Platform behavior:
     - Mobile: share sheet with `.csv`
     - Desktop/Web: downloaded/saved `.csv`

4. **Distribute to families**
   - Send one code per student via approved school channels.
   - Include parent registration path: `/auth/parent-register`.
   - Enforce secure handling (no public posting of CSV/code lists).

5. **Follow-up and tracking**
   - Monitor linked count per student.
   - Re-export CSV for updated status snapshots.
   - Follow up with families where `Code Status=active` and `Linked Parent Count=0`.

## Exception Handling
1. **Wrong recipient / compromised code**
   - Open student card.
   - Click **Revoke**.
   - Enter reason (recommended).
   - Generate a new code and redistribute.

2. **Parent relationship change**
   - Open student card.
   - Click **Unlink Parent**.
   - Select `Parent ID`.
   - Enter reason (recommended).
   - Confirm unlink.

## Security and Audit Expectations
- One active code per student by default.
- Code lifecycle:
  - `active` -> `used`
  - `active` -> `revoked`
  - `active` -> `expired` (time-based)
- Parent verification queries are bounded and cannot bulk-enumerate unrestricted data.
- Rules validation command:
  - `cd functions && npm run test:rules`

## Beta Release Checks (Admin Ops)
- [ ] Student import completed and verified
- [ ] Bulk generation succeeds without manual retries
- [ ] CSV export succeeds on target platform(s)
- [ ] Parent registration path confirmed end-to-end with test family
- [ ] Revoke and unlink actions verified with confirmation dialogs
