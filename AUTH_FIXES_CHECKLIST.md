# Authentication Security Fixes Checklist

## Critical Fixes

- [x] 1. Firestore rules: Prevent role field modification (privilege escalation)
- [x] 2. Router: Stop trusting client-side UserModel from state.extra
- [x] 3. Login: Use generic error message to prevent user enumeration
- [x] 4. Registration: Enforce stronger password policy (8+ chars, mixed case, number)
- [x] 5. Registration: Remove debug print statements with sensitive data

## Warning Fixes

- [x] 6. Auth: Implement email verification requirement
- [x] 7. Logout: Clear local Hive cache on sign out
- [x] 8. Logout: Revoke FCM tokens on sign out
- [x] 9. Auth screens: Normalize email input (trim + lowercase)
- [x] 10. Admin/Teacher screens: Add role validation guards

## Skipped (Intentionally)

- [ ] Dev admin button — kept for testing (user request)
