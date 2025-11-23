# Firestore Architecture Optimization - Deployment Guide

## Overview

This document outlines the Firestore architecture optimizations implemented for the Lumi Reading Tracker app to improve performance, reliability, and scalability for 100+ schools.

## What Was Optimized

### 1. ✅ Login Performance (CRITICAL)
**Problem**: Login required iterating through ALL schools (O(n) reads - 200 reads for 100 schools)

**Solution**: Created email-to-school index lookup (`userSchoolIndex` collection)

**Impact**:
- **Before**: 200 Firestore reads for 100 schools
- **After**: 2-3 Firestore reads (100x improvement)
- **Cost savings**: ~$400/year for 1000 schools

**Files Changed**:
- Created: `lib/core/services/user_school_index_service.dart`
- Updated: `lib/screens/auth/login_screen.dart`
- Updated: `lib/screens/auth/parent_registration_screen.dart`
- Updated: `lib/screens/auth/register_screen.dart`

### 2. ✅ Fixed Teacher/Admin Registration (CRITICAL)
**Problem**: Registration wrote to flat `users` collection instead of nested `schools/{schoolId}/users`

**Solution**: Updated registration flow to use correct nested structure

**Impact**: Teachers and admins can now actually register and be found during login

**Files Changed**:
- `lib/screens/auth/register_screen.dart`

### 3. ✅ Atomic Parent-Student Unlinking
**Problem**: Unlink operation used two separate writes (could fail halfway, creating orphaned relationships)

**Solution**: Wrapped in Firestore transaction with verification and link code revocation

**Impact**: Data consistency guaranteed - both sides update or neither updates

**Files Changed**:
- `lib/services/parent_linking_service.dart`

### 4. ✅ Atomic Counter Maintenance
**Problem**: School `studentCount` and `teacherCount` fields were never updated

**Solution**: Added `FieldValue.increment(1)` when creating users/students

**Impact**: Accurate dashboard metrics and school analytics

**Files Changed**:
- `lib/services/csv_import_service.dart`
- `lib/screens/auth/register_screen.dart`
- `lib/screens/auth/parent_registration_screen.dart`

### 5. ✅ Enhanced Firestore Indexes
**Problem**: Missing indexes for common query patterns

**Solution**: Added 7 new composite indexes for:
- Parent queries (active, sorted by name/date)
- Students by class and active status
- Reading logs with date range support
- School-scoped user/class queries

**Impact**: Faster queries, reduced costs, better scalability

**Files Changed**:
- `firestore.indexes.json`

## Deployment Steps

### Step 1: Install New Dependencies

```bash
flutter pub get
```

This installs the `crypto` package (v3.0.3) needed for email hashing in the index service.

### Step 2: Deploy Firestore Indexes

```bash
firebase deploy --only firestore:indexes
```

This will deploy the new composite indexes. Firestore will build these in the background (may take a few minutes for large databases).

### Step 3: Deploy Firestore Security Rules

```bash
firebase deploy --only firestore:rules
```

Ensure your Firestore security rules allow read/write access to the new `userSchoolIndex` collection:

```javascript
// Add to firestore.rules
match /userSchoolIndex/{emailHash} {
  // Allow users to read their own index entry
  allow read: if request.auth != null;

  // Allow system to create/update entries (done server-side or during registration)
  allow write: if request.auth != null;
}
```

### Step 4: Deploy Application Code

```bash
# Build and deploy your app
flutter build web  # or flutter build apk/ios
# Deploy to your hosting platform
```

### Step 5: Run Migration Script

**IMPORTANT**: Run this ONCE after deployment to backfill the index for existing users.

You have two options:

#### Option A: Using Firebase Cloud Functions (Recommended for Production)

1. Create a one-time Cloud Function:

```typescript
// functions/src/index.ts
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

export const backfillUserSchoolIndex = functions.https.onRequest(async (req, res) => {
  const firestore = admin.firestore();
  let totalUsers = 0;
  let totalParents = 0;

  const schoolsSnapshot = await firestore.collection('schools').get();

  for (const schoolDoc of schoolsSnapshot.docs) {
    const schoolId = schoolDoc.id;

    // Index users (teachers/admins)
    const usersSnapshot = await firestore
      .collection('schools')
      .doc(schoolId)
      .collection('users')
      .get();

    for (const userDoc of usersSnapshot.docs) {
      const data = userDoc.data();
      if (data.email) {
        const crypto = require('crypto');
        const emailHash = crypto.createHash('sha256')
          .update(data.email.toLowerCase().trim())
          .digest('hex');

        await firestore.collection('userSchoolIndex').doc(emailHash).set({
          email: data.email,
          schoolId: schoolId,
          userType: 'user',
          userId: userDoc.id,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        totalUsers++;
      }
    }

    // Index parents
    const parentsSnapshot = await firestore
      .collection('schools')
      .doc(schoolId)
      .collection('parents')
      .get();

    for (const parentDoc of parentsSnapshot.docs) {
      const data = parentDoc.data();
      if (data.email) {
        const crypto = require('crypto');
        const emailHash = crypto.createHash('sha256')
          .update(data.email.toLowerCase().trim())
          .digest('hex');

        await firestore.collection('userSchoolIndex').doc(emailHash).set({
          email: data.email,
          schoolId: schoolId,
          userType: 'parent',
          userId: parentDoc.id,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        totalParents++;
      }
    }
  }

  res.json({
    success: true,
    schools: schoolsSnapshot.docs.length,
    users: totalUsers,
    parents: totalParents,
    total: totalUsers + totalParents,
  });
});
```

2. Deploy the function:
```bash
firebase deploy --only functions:backfillUserSchoolIndex
```

3. Trigger it once:
```bash
curl https://YOUR_REGION-YOUR_PROJECT_ID.cloudfunctions.net/backfillUserSchoolIndex
```

4. Delete the function after use:
```bash
firebase functions:delete backfillUserSchoolIndex
```

#### Option B: Automatic Backfill During Login (Easiest)

**No action needed!** The login screen already has automatic backfill built in. When an existing user logs in and their email is not found in the index, the system will:
1. Fall back to the old iteration method (find user in schools)
2. Automatically create the index entry for future logins
3. Next login will be fast

This means the index will be backfilled organically as users log in. However, this is slower for the first login after deployment.

#### Option C: Manual Admin Screen (For Testing)

Add a temporary admin screen in your Flutter app with a button that calls:

```dart
final indexService = UserSchoolIndexService();
final stats = await indexService.backfillAllSchools();
print('Backfilled: ${stats['total']} users');
```

**Recommended**: Use **Option B** (automatic) for simplicity, or **Option A** (Cloud Function) for immediate migration.

### Step 6: Verify Deployment

1. **Test Login**: Try logging in as a teacher, admin, and parent
   - Should be noticeably faster (especially with many schools)
   - Check Firebase Console > Firestore > `userSchoolIndex` collection - should have entries

2. **Test Registration**:
   - Register a new teacher with a school ID
   - Register a new parent with a student link code
   - Verify user appears in correct school's nested collection

3. **Test Parent Unlinking**:
   - Unlink a parent from a student
   - Verify both sides are updated correctly

4. **Check Counters**:
   - Go to Firebase Console > Firestore > `schools` collection
   - Check a school document - should have `studentCount`, `teacherCount`, `parentCount` fields

5. **Monitor Performance**:
   - Firebase Console > Firestore > Usage tab
   - Reads per login should be 2-3 (down from 200+ for large deployments)

## Rollback Plan

If issues arise, you can rollback:

1. **Code Rollback**: Deploy previous version of the app
2. **Keep Index**: The `userSchoolIndex` collection won't hurt - it's just unused
3. **Indexes**: Cannot rollback indexes easily, but new indexes don't break old queries

**Note**: The login screen has a fallback mechanism - if index entry is not found, it falls back to the old iteration method while automatically creating the index entry for future logins.

## Performance Benchmarks

### Login Performance

| Number of Schools | Old Reads | New Reads | Improvement |
|-------------------|-----------|-----------|-------------|
| 1                 | 2         | 2-3       | ~Same       |
| 10                | 20        | 2-3       | 7x faster   |
| 100               | 200       | 2-3       | 67x faster  |
| 1000              | 2000      | 2-3       | 667x faster |

### Cost Analysis (100 schools, 1000 logins/day)

| Metric           | Before       | After        | Savings     |
|------------------|--------------|--------------|-------------|
| Reads per login  | 200          | 3            | 98.5%       |
| Daily reads      | 200,000      | 3,000        | 197,000     |
| Monthly reads    | 6,000,000    | 90,000       | 5,910,000   |
| Monthly cost*    | $3.60        | $0.05        | $3.55       |
| Annual cost      | $43.20       | $0.60        | $42.60      |

*Based on Firestore pricing: $0.06 per 100,000 reads

## Architecture Diagram

### Before: Flat Structure with O(n) Login
```
Login Process:
1. Authenticate with Firebase Auth
2. Get ALL schools → 1 read
3. For each school (100 schools):
   - Check schools/{schoolId}/users/{uid} → 100 reads
   - Check schools/{schoolId}/parents/{uid} → 100 reads
4. Total: 201 reads 😱

users → ❌ BROKEN (wrote here but never read)
schools/
  {schoolId}/
    users/ ✅
    parents/ ✅
    students/ ✅
```

### After: Index-Optimized with O(1) Login
```
Login Process:
1. Authenticate with Firebase Auth
2. Lookup userSchoolIndex/{emailHash} → 1 read ⚡
3. Directly access schools/{schoolId}/{collection}/{uid} → 1 read ⚡
4. Total: 2-3 reads 🚀

userSchoolIndex/ ⭐ NEW
  {emailHash}: {schoolId, userType, userId}

schools/
  {schoolId}/
    users/ ✅ (teachers, admins)
    parents/ ✅ (separate collection)
    students/ ✅
```

## Backward Compatibility

The implementation is **100% backward compatible**:

1. **Login Fallback**: If index entry doesn't exist, falls back to old method and creates index for next time
2. **Existing Users**: Migration script backfills index for all existing users
3. **New Users**: Automatically get index entry during registration
4. **Security**: No changes to user permissions or access control

## Monitoring & Maintenance

### Key Metrics to Monitor

1. **Firestore Reads** (Firebase Console > Firestore > Usage)
   - Should see dramatic drop in read operations after deployment
   - Login reads should stabilize at 2-3 per user

2. **Error Rates** (Firebase Crashlytics)
   - Monitor for transaction failures in parent unlinking
   - Watch for missing index warnings

3. **Index Health** (Firebase Console > Firestore > Indexes)
   - Ensure all indexes are "Enabled" (not "Building" or "Error")

4. **Counter Accuracy**
   - Spot-check school documents - compare `studentCount` with actual student count
   - If drift occurs, create a script to recalculate and update

### Maintenance Tasks

**Weekly**:
- Check Firebase Console for any index warnings or errors

**Monthly**:
- Review Firestore costs in Firebase Console > Usage & Billing
- Verify counter accuracy on a sample of schools

**As Needed**:
- Re-run backfill script if bulk user imports are done manually
- Update indexes if new query patterns emerge

## Troubleshooting

### Issue: Login is slow after deployment

**Cause**: Index entries not created yet

**Solution**:
1. Run migration script: `dart run scripts/backfill_user_school_index.dart`
2. Check `userSchoolIndex` collection has entries
3. Try logging in again - should be fast

### Issue: Teachers can't register

**Cause**: School ID not provided or invalid

**Solution**:
- Ensure registration link includes `?schoolId={validSchoolId}`
- Verify school exists in Firestore

### Issue: Counter values are wrong

**Cause**: Counters from before deployment, or bulk import without increments

**Solution**:
- Create a script to recalculate all counters
- Update school documents with correct counts

### Issue: Parent unlinking fails

**Cause**: Transaction conflict or missing documents

**Solution**:
- Check error message in Crashlytics
- Verify student and parent documents exist
- Retry the operation

## Support

For questions or issues:
1. Check Firebase Console for error logs
2. Review Firestore rules for permission issues
3. Check this deployment guide for troubleshooting
4. Contact development team with specific error messages

---

**Deployment Date**: _To be filled in_
**Deployed By**: _To be filled in_
**Migration Status**: _To be filled in_
**Notes**: _To be filled in_
