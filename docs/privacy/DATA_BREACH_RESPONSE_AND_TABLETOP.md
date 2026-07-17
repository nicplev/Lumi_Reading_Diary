# Lumi Data Breach Response Plan and Tabletop Record

**Version:** 0.9 · **Prepared:** 17 July 2026
**Scope:** Suspected or confirmed loss, unauthorised access, disclosure or
modification of Lumi personal information.
**Emergency security contacts:** primary `nic@lumi-reading.com`; backup
`nicxplev@gmail.com`.
**Privacy/support intake:** `support@lumi-reading.com` (monitoring confirmation
pending).

This plan must be available outside the production systems. It is not legal
advice. The incident lead should obtain Australian privacy/legal advice when a
breach may cause serious harm or a notification decision is uncertain.

The structure follows the OAIC's preparation and response guidance:

- https://www.oaic.gov.au/privacy/notifiable-data-breaches/preventing-preparing-for-and-responding-to-data-breaches/data-breach-preparation-and-response
- https://www.oaic.gov.au/about-the-OAIC/our-corporate-information/plans-policies-and-procedures/data-breach-response-plan

## 1. Roles and authority

One person may hold several roles while Lumi is small, but each action must be
recorded.

| Role | Responsibility | Current assignee |
| --- | --- | --- |
| Incident lead | Declare severity, coordinate, preserve timeline and approve containment | Founder/technical lead — confirm name |
| Privacy/legal lead | NDB assessment, school/individual notice and regulator liaison | External Australian privacy counsel — appoint |
| Technical lead | Containment, evidence, eradication, recovery and verification | Founder/technical lead |
| School liaison | Verify school authority and coordinate affected-school communication | Founder/customer lead — confirm |
| Communications | Clear, child-safe notices; no speculation | Founder/customer lead — confirm |
| Scribe | Time-stamped decisions, evidence chain and action list | Incident lead until delegated |

The incident lead is authorised to disable a feature, revoke credentials or
sessions, block a deployment, enforce maintenance mode, suspend a school, or
temporarily stop processing when necessary to protect people. Destructive
evidence deletion is not authorised.

## 2. Severity

| Severity | Example | Initial response target |
| --- | --- | --- |
| SEV-1 Critical | Confirmed cross-school/child exposure, stolen privileged credential, public Storage, destructive compromise | Begin immediately; notify backup lead within 15 minutes |
| SEV-2 High | Likely unauthorised access with limited scope, deletion failure leaving accessible data, suspicious impersonation | Begin within 30 minutes |
| SEV-3 Medium | Blocked attack, contained non-production leak, incorrect adult-only email | Same business day |
| SEV-4 Low | No personal data or control impact | Track in normal security work |

Severity may rise as scope or sensitivity becomes clearer.

## 3. First-response checklist

### A. Contain

- [ ] Record UTC and local time, reporter, observable symptoms and incident ID.
- [ ] Protect people first: stop the affected feature or tenant if ongoing.
- [ ] Revoke exposed API/service-account keys, sessions, tokens, signed URLs and
  developer access without destroying evidence.
- [ ] Preserve relevant Cloud Audit, Cloud Run, Firebase, GitHub/deployment and
  application audit records with restricted access.
- [ ] Snapshot only the minimum evidence necessary; redact child content from
  tickets, chat and email.
- [ ] Do not use a child's audio, notes or reading record to demonstrate the
  breach when synthetic evidence will work.

### B. Assess

- [ ] What happened: loss, access, disclosure, modification or availability?
- [ ] Which schools, children, adults, records, recordings and time window?
- [ ] Was information encrypted or otherwise unintelligible?
- [ ] Who likely received it and can it be retrieved or made inaccessible?
- [ ] Could remedial action prevent likely serious harm?
- [ ] Consider identity fraud, physical safety, humiliation, discrimination,
  educational harm, family conflict and risks created by child voice/location.
- [ ] Start an NDB assessment promptly and obtain counsel. Record facts,
  assumptions, evidence and the decision; do not silently let the assessment
  drift beyond the statutory assessment period.

### C. Notify

- [ ] Notify affected schools through a separately verified emergency contact;
  do not rely on a possibly compromised in-app account.
- [ ] If there are reasonable grounds to believe an eligible data breach has
  occurred, prepare the OAIC statement and notify affected individuals in the
  legally appropriate way.
- [ ] Notices should say what happened, what information was involved, the
  practical risks, containment already taken, what people should do, and how to
  get support. Use plain, child-safe language.
- [ ] Coordinate timing with law enforcement, cyber insurer and providers only
  where relevant; document any delay and its authority.

Under the NDB scheme, the OAIC describes an eligible breach as unauthorised
access/disclosure or likely loss, likely serious harm, and inability to prevent
that likely harm through remedial action. This is a legal assessment, not a
simple record-count threshold.

### D. Review and recover

- [ ] Fix the root cause and add a regression test before restoring service.
- [ ] Verify deployed rules/config/code hashes, runtime IAM, App Check, API keys,
  Storage access and affected data integrity.
- [ ] Monitor for recurrence and confirm alerts reach both recipients.
- [ ] Offer practical support and access/correction/deletion routes.
- [ ] Record lessons, owners and deadlines. Update this PIA, vendor register,
  threat model and school FAQ.
- [ ] Hold a blameless review within five business days of containment.

## 4. Evidence handling

- Store incident evidence in a dedicated access-restricted location, not the
  source repository or ordinary support inbox.
- Hash exported files; record collector, source, UTC time and every transfer.
- Never print tokens, passwords, API keys, raw session cookies or recordings in
  a terminal transcript.
- Prefer aggregate counts and synthetic reproductions. If real data is strictly
  necessary, minimise, encrypt, restrict, set a deletion date and record why.
- Do not promise that a Firestore document deletion instantly removes PITR
  versions. Record when inaccessible backup/PITR data will age out or be put
  beyond use.

## 5. Technical containment map

| Event | Immediate safe actions |
| --- | --- |
| Firestore Rules regression | Roll back to last reviewed ruleset; suspend affected client version; compare active rules hash; query access metrics/logs; add negative test |
| Storage exposure/signed URL leak | Restore Storage Rules/IAM; revoke signer capability if compromised; delete or replace exposed object generations; inspect egress; rotate affected content |
| Service-account/API key leak | Disable first, verify healthy ADC/WIF path, delete key, restrict API key, inspect Cloud Audit Logs and artifacts |
| Compromised user/session | Disable Auth user, revoke refresh tokens, remove sessions/impersonation, verify memberships and indexes |
| Audio/AI vendor incident | Set feature kill switch off, stop queue/worker, preserve minimum job metadata, request provider containment/deletion evidence, notify enabled schools |
| Deletion workflow failure | Keep job resumable, stop repeated destructive retries if unsafe, inventory every expected record/object, repair and rerun idempotently |
| Malicious/risky release | Activate force-update/support mode, halt rollout, revert backend compatibility if needed, notify schools of safe version |

## 6. Tabletop exercise — 17 July 2026

**Type:** Desk-based technical walkthrough.
**Scenario:** A broad Firestore Rules change accidentally allows a signed-in
teacher from School A to query reading logs in School B. The error is live for
two hours. A security researcher reports seeing 500 records, including child
names, book titles, minutes and optional comments. No audio download is proven.

### Walkthrough and decisions

| Simulated time | Decision/action | Evidence/control used |
| --- | --- | --- |
| 00:00 | Treat as SEV-1 and open a UTC timeline | Child and cross-school exposure makes impact high |
| 00:05 | Roll back Firestore Rules to the reviewed ruleset and disable the faulty release path | Rules source/ruleset hashes and Firebase release history |
| 00:10 | Preserve rules release, deployment identity, Cloud Audit/Run logs and read metrics | Keyless WIF deployment and Monitoring dashboard |
| 00:20 | Verify parent/teacher cross-tenant negative tests against the restored rules | Firestore Emulator matrix plus production synthetic denial probe |
| 00:30 | Establish exposed fields, schools, query window and whether comments/audio were reachable | Scoped data inventory; no copying unrelated child content |
| 01:00 | Contact affected school leads through verified contract contacts; begin legal/NDB assessment | School emergency-contact register is required |
| 04:00 | Prepare plain-language holding notice without claiming scope is final | Communications template below |
| Day 1 | Add exact regression test, review matching-rule OR paths and require approval on Rules deploy | Release privacy/security gate |
| Day 5 | Complete post-incident review and track remediation | PIA/vendor/register updates |

### Tabletop findings

1. **Passed:** Rules rollback, source hashes, extensive negative tests, WIF deploy
   audit, least-privilege runtime IAM, alerts and PITR are available.
2. **Closed technically:** A successful extraction of 500 reads may stay below
   the current 20,000/hour cost threshold, so Firestore `DATA_READ` and
   `DATA_WRITE` audit logging is now enabled through the project IAM audit
   configuration. Review its volume/cost after one week and retain high-value
   access evidence. A post-enable production probe verified read and write
   entries in the Data Access log without displaying document paths or payloads.
3. **Gap:** Verified emergency contacts for each school are not in this
   repository. Add them to the contract/CRM without storing them in app code.
4. **Gap:** External Australian privacy counsel and incident roles are not yet
   formally appointed.
5. **Gap:** Monitoring of `support@lumi-reading.com` and both security alert
   messages still needs human confirmation.
6. **Gap:** Store-attested App Check is not yet enforceable; it would reduce
   scripted exploitation but would not correct broken authorisation.

**Exercise result:** Process is technically executable, with four governance
actions open and the logging decision closed. The tabletop does not prove that an NDB
notification decision has been legally reviewed.

## 7. Holding notice template

> Lumi is investigating unauthorised access to information associated with
> your school. We have contained the affected access path and are determining
> exactly what information and people were involved. Please preserve this
> message and direct questions to [verified contact]. We will provide practical
> next steps and a further update by [time]. Do not forward child information
> in ordinary email while we investigate.

## 8. Exercise schedule

- Repeat every six months, before broad school launch, and after a material
  change to authentication, Storage, audio/AI, deletion or vendors.
- Alternate scenarios: stolen deploy identity; public audio object; malicious
  school admin; vendor transcript breach; deletion job partial failure.
- Retain date, participants, scenario, decisions, gaps, owners and closure
  evidence.
