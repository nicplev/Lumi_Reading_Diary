# Mandatory authenticator MFA for school administrators

School administrators must complete TOTP MFA before the portal issues its
server session cookie. Teachers retain the existing password/SMS behaviour.

## Deployment order

1. Confirm there are at least two active school administrators or a documented
   support owner who can perform account recovery.
2. Inspect the Identity Platform project (dry run):

   ```bash
   cd school-admin-web
   GOOGLE_APPLICATION_CREDENTIALS=/secure/path/to/lumi-ninc-au-admin.json \
     FIREBASE_PROJECT_ID=lumi-ninc-au node scripts/configure-totp-mfa.mjs
   ```

3. Enable TOTP before deploying the portal:

   ```bash
   GOOGLE_APPLICATION_CREDENTIALS=/secure/path/to/lumi-ninc-au-admin.json \
     FIREBASE_PROJECT_ID=lumi-ninc-au node scripts/configure-totp-mfa.mjs --apply
   ```

4. Deploy `school-admin-web`. Mandatory enforcement is on by default. Set
   `ADMIN_TOTP_ENFORCED=false` only as a short-lived emergency rollback.
5. Test one administrator in a private browser window before announcing the
   rollout.

Do not deploy the mandatory portal gate before TOTP is enabled in Identity
Platform; administrators without a factor would be unable to complete setup.

## Expected flows

- Admin without TOTP: password → verified-email check → QR/setup key → current
  authenticator code → portal.
- Admin with SMS only: password → SMS challenge → mandatory TOTP enrollment →
  portal. Future portal logins use TOTP.
- Admin with TOTP: password → authenticator code → portal.
- Teacher: existing password/SMS login remains unchanged.
- Seeded demo parent/teacher: password-only login remains unchanged; the seed
  removes any accidentally enrolled factors on every refresh.
- Seeded demo admin: password-only login is allowed only when Admin-SDK custom
  claims and the synthetic tenant marker agree. Its portal session is read-only.
- Any admin cookie minted before this rollout is rejected and must be replaced
  by a new MFA-verified login.

## Lost-device recovery

Password reset does not remove MFA. Recovery must be performed by a separately
authenticated support operator using the Firebase Admin SDK, and the action
should be recorded in the security audit log. Remove the lost TOTP factor (or
all factors only when identity has been independently verified), revoke refresh
tokens, and require the administrator to sign in and enroll a new authenticator.

Never let an administrator disable their own final factor from an active portal
session. Keep two active administrator accounts so recovery does not depend on
the locked-out person.

## Manual test checklist

- Wrong/expired TOTP is rejected without creating `__session`.
- A password-only admin ID token is rejected by `/api/auth/session`.
- A phone-MFA admin ID token is rejected until TOTP enrollment finishes.
- A valid TOTP login creates an HttpOnly, Secure (production), SameSite=Lax
  session cookie.
- Deactivated admins remain blocked before MFA/session issuance.
- Unverified admins receive an email verification step before the QR code.
- Cancelling setup signs out the temporary Firebase user.
- Lost-device recovery is rehearsed with a non-production account.

References:

- https://firebase.google.com/docs/auth/web/totp-mfa
- https://cloud.google.com/identity-platform/docs/admin/manage-mfa-users
