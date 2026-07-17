## Change

Describe the outcome and how it was verified.

## Privacy and security impact

- [ ] No auth, child/adult data, Firestore, Storage, analytics, vendor, secret,
      retention or deletion impact.
- [ ] Impact exists and I completed the applicable gate in
      `docs/privacy/RELEASE_PRIVACY_SECURITY_REVIEW.md`.
- [ ] Cross-tenant and negative tests were added or the reason they are not
      applicable is explained below.
- [ ] New queries/listeners are scoped and bounded; cleanup/disposal is covered.
- [ ] New data is included in retention and account/student deletion workflows.
- [ ] No secret or privileged credential is present in source, logs or artifacts.

## Deployment and rollback

State deployment order, live canary and safe rollback for backend/rules changes.
