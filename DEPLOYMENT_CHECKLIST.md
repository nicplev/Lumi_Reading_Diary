# 🚀 Deployment Checklist - Lumi Reading Diary

## Current Status
- **Project**: lumi-kakakids
- **Branch**: claude/analyze-lumi-structure-01MbavyAxisLuhAHxPVNsSCd
- **Features Ready**: ✅ All 6 enhancements implemented and committed

---

## 📋 Pre-Deployment Checklist

### ✅ Completed
- [x] Critical race condition fix (atomic transactions)
- [x] Security vulnerability fix (Firestore rules)
- [x] Cloud function field mismatch fix
- [x] Custom exception classes
- [x] Registration idempotency
- [x] Server-side code verification (Cloud Function)
- [x] Bulk linking for siblings (Cloud Function)
- [x] Parent self-unlinking (Cloud Function)
- [x] Comprehensive documentation

### ⏳ To Do
- [ ] Run data migration script
- [ ] Deploy Cloud Functions
- [ ] Deploy Firestore Rules
- [ ] Test in development environment
- [ ] Deploy to production

---

## 🔧 Step-by-Step Deployment

### **STEP 1: Data Migration** (Critical - Do First!)

This fixes the field name mismatch in existing link codes.

#### Option A: Run Locally (Recommended for Development)

```bash
# 1. Ensure you have Firebase Admin SDK credentials
# Download from: Firebase Console → Project Settings → Service Accounts → Generate New Private Key

# 2. Set environment variable
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/lumi-kakakids-service-account.json"

# 3. Run migration script
cd /home/user/Lumi_Reading_Diary
dart run scripts/migrate_link_code_fields.dart
```

#### Option B: Run via Cloud Function (Production)

Create a one-time Cloud Function:

```typescript
// Add to functions/src/index.ts temporarily
export const migrateFieldNames = functions.https.onRequest(async (req, res) => {
  // Require admin authentication
  const authHeader = req.headers.authorization;
  if (!authHeader || authHeader !== 'Bearer YOUR_ADMIN_SECRET') {
    res.status(403).send('Unauthorized');
    return;
  }

  const snapshot = await db.collection('studentLinkCodes').get();
  const batch = db.batch();
  let count = 0;

  snapshot.docs.forEach((doc) => {
    const data = doc.data();
    if (data.expiryDate && !data.expiresAt) {
      batch.update(doc.ref, { expiresAt: data.expiryDate });
      count++;
    }
  });

  await batch.commit();
  res.send(`Migrated ${count} documents`);
});
```

Then deploy and call once:
```bash
firebase deploy --only functions:migrateFieldNames
curl -H "Authorization: Bearer YOUR_ADMIN_SECRET" https://us-central1-lumi-kakakids.cloudfunctions.net/migrateFieldNames
```

#### Expected Output:
```
🔄 Starting link code field migration...

📦 Fetching all link code documents...
Found 15 documents

  ➡️  Migrating document doc1: expiryDate -> expiresAt (ABC12345)
  ➡️  Migrating document doc2: expiryDate -> expiresAt (XYZ67890)
  ...

⚡ Committing batch 1...
✅ Batch 1 committed successfully

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Migration Summary:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total documents scanned: 15
  Documents migrated: 12
  Documents already correct: 3
  Documents with issues: 0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Migration complete!
```

---

### **STEP 2: Deploy Cloud Functions**

```bash
cd functions

# Install dependencies (if not already done)
npm install

# Option A: Deploy only the new functions
firebase deploy --only functions:verifyParentLinkCode,functions:createBulkLinkCode,functions:unlinkParentFromStudent

# Option B: Deploy ALL functions (includes existing + new)
firebase deploy --only functions

# View deployment logs
firebase functions:log --tail
```

#### Expected Output:
```
✔ functions[verifyParentLinkCode(us-central1)] Successful create operation.
✔ functions[createBulkLinkCode(us-central1)] Successful create operation.
✔ functions[unlinkParentFromStudent(us-central1)] Successful create operation.
✔ functions[cleanupExpiredLinkCodes(us-central1)] Successful update operation.

✔ Deploy complete!

Functions URLs:
• verifyParentLinkCode: https://us-central1-lumi-kakakids.cloudfunctions.net/verifyParentLinkCode
• createBulkLinkCode: https://us-central1-lumi-kakakids.cloudfunctions.net/createBulkLinkCode
• unlinkParentFromStudent: https://us-central1-lumi-kakakids.cloudfunctions.net/unlinkParentFromStudent
```

---

### **STEP 3: Deploy Firestore Rules** (Optional if using server-side verification)

```bash
# Deploy updated security rules
firebase deploy --only firestore:rules

# Monitor for errors in next 24 hours
firebase firestore:rules --tail
```

⚠️ **IMPORTANT**: The current rules still allow limited unauthenticated reads for backward compatibility. If you want to fully lock down after implementing server-side verification, update rules to remove the unauthenticated list query.

---

### **STEP 4: Test Cloud Functions**

#### Test 1: Server-Side Code Verification

```bash
# Test with valid code
curl -X POST \
  https://us-central1-lumi-kakakids.cloudfunctions.net/verifyParentLinkCode \
  -H "Content-Type: application/json" \
  -d '{"data": {"code": "ABC12345"}}'

# Expected success response:
{
  "result": {
    "success": true,
    "codeData": {
      "id": "doc_id",
      "code": "ABC12345",
      "studentId": "student123",
      "schoolId": "school456",
      "status": "active",
      "metadata": {...}
    }
  }
}

# Test with invalid code (should fail)
curl -X POST \
  https://us-central1-lumi-kakakids.cloudfunctions.net/verifyParentLinkCode \
  -H "Content-Type: application/json" \
  -d '{"data": {"code": "INVALID1"}}'

# Expected error response:
{
  "error": {
    "code": "not-found",
    "message": "Invalid or expired code. Please check with your school."
  }
}

# Test rate limiting (run 11 times rapidly)
for i in {1..11}; do
  curl -X POST https://us-central1-lumi-kakakids.cloudfunctions.net/verifyParentLinkCode \
    -H "Content-Type: application/json" \
    -d '{"data": {"code": "TEST1234"}}'
  echo ""
done

# 11th request should return:
{
  "error": {
    "code": "resource-exhausted",
    "message": "Too many attempts. Please wait a minute and try again."
  }
}
```

#### Test 2: Bulk Link Code Creation

You'll need an authentication token for this. Get it from Firebase Auth:

```bash
# In your Flutter app or Firebase Console
# Get the ID token for an admin/teacher user

# Then test:
curl -X POST \
  https://us-central1-lumi-kakakids.cloudfunctions.net/createBulkLinkCode \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ID_TOKEN" \
  -d '{
    "data": {
      "studentIds": ["student1", "student2", "student3"],
      "schoolId": "school123"
    }
  }'

# Expected response:
{
  "result": {
    "success": true,
    "code": "XYZ789AB",
    "studentCount": 3,
    "students": [...]
  }
}
```

#### Test 3: Parent Self-Unlinking

```bash
curl -X POST \
  https://us-central1-lumi-kakakids.cloudfunctions.net/unlinkParentFromStudent \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer PARENT_ID_TOKEN" \
  -d '{
    "data": {
      "studentId": "student123",
      "schoolId": "school456"
    }
  }'

# Expected response:
{
  "result": {
    "success": true,
    "message": "Successfully unlinked from student."
  }
}
```

---

### **STEP 5: Verify in Firebase Console**

1. **Check Firestore Collections**:
   - Go to Firestore → `studentLinkCodes`
   - Verify `expiresAt` field exists on all documents
   - Check for new `auditLogs` collection (created after first verification)
   - Check for new `rateLimits` collection (created after first verification)

2. **Check Cloud Functions Logs**:
   ```bash
   firebase functions:log --only verifyParentLinkCode
   ```

3. **Monitor Metrics**:
   - Firebase Console → Functions → Click each function
   - Check invocation count, error rate, execution time

---

### **STEP 6: Integration Testing**

#### Test Full Parent Registration Flow:

1. **Create a test student** (or use existing)
2. **Generate bulk link code** for test siblings:
   ```dart
   final result = await FirebaseFunctions.instance
       .httpsCallable('createBulkLinkCode')
       .call({
         'studentIds': ['test_sibling1', 'test_sibling2'],
         'schoolId': 'test_school',
       });
   print('Bulk code: ${result.data['code']}');
   ```

3. **Test parent registration** with bulk code:
   - Open parent registration screen
   - Enter the bulk code
   - Complete registration
   - Verify all siblings are linked

4. **Test self-unlinking**:
   - Go to parent home screen
   - Select a student
   - Click "Unlink" (you may need to add UI for this)
   - Verify student is removed from parent's linked children

---

### **STEP 7: Monitoring & Analytics**

#### Set up Firebase Alerts:

1. **Function Errors**:
   ```bash
   # Monitor for errors
   firebase functions:log --only verifyParentLinkCode | grep ERROR
   ```

2. **Rate Limit Violations**:
   ```javascript
   // Query in Firestore Console
   rateLimits
     .where('attempts', '>=', 10)
     .orderBy('lastAttempt', 'desc')
   ```

3. **Audit Log Analysis**:
   ```javascript
   // Failed verifications
   auditLogs
     .where('type', '==', 'code_verification_failed')
     .orderBy('timestamp', 'desc')
     .limit(100)

   // Success rate
   auditLogs
     .where('type', 'in', ['code_verification_success', 'code_verification_failed'])
     .orderBy('timestamp', 'desc')
   ```

---

## 🚨 Rollback Plan

If something goes wrong:

### Rollback Cloud Functions:
```bash
# List recent deployments
firebase functions:list

# Rollback to previous version
firebase deploy --only functions --force
```

### Rollback Firestore Rules:
```bash
# Revert to previous rules
git revert HEAD
firebase deploy --only firestore:rules
```

### Rollback App Code:
```bash
# Revert commits
git revert HEAD~3..HEAD
git push -f origin your-branch
```

---

## 📊 Success Metrics

After deployment, monitor these for 48 hours:

- [ ] **Zero** race condition errors in logs
- [ ] **Zero** unauthorized code access attempts
- [ ] **Cloud function success rate** > 99%
- [ ] **Average function execution time** < 500ms
- [ ] **Parent registration completion rate** improved
- [ ] **Support tickets** for linking issues reduced

---

## ✅ Post-Deployment Checklist

- [ ] All Cloud Functions deployed and responding
- [ ] Firestore rules deployed (if applicable)
- [ ] Migration script completed successfully
- [ ] Test parent registration flow works
- [ ] Test bulk linking works
- [ ] Test self-unlinking works
- [ ] Monitoring/alerts configured
- [ ] Team notified of new features
- [ ] Documentation shared with admins/teachers

---

## 🎯 Quick Reference Commands

```bash
# Deploy everything
firebase deploy

# Deploy only functions
firebase deploy --only functions

# Deploy only rules
firebase deploy --only firestore:rules

# View logs
firebase functions:log --tail

# View specific function logs
firebase functions:log --only verifyParentLinkCode

# Test a function locally
firebase emulators:start --only functions
```

---

## 📞 Support

If you encounter issues:

1. **Check logs first**:
   ```bash
   firebase functions:log --only verifyParentLinkCode
   ```

2. **Check Firestore rules**:
   ```bash
   firebase firestore:rules
   ```

3. **Review documentation**:
   - `PARENT_LINKING_ENHANCEMENTS.md`
   - Cloud Function comments in `functions/src/index.ts`

4. **Common issues**:
   - **"Permission denied"**: Check Firestore rules
   - **"Rate limit exceeded"**: Check `rateLimits` collection
   - **"Function timeout"**: Increase timeout in function config
   - **"Invalid code"**: Check code status in Firestore

---

## 🎉 You're Ready to Deploy!

Start with Step 1 (data migration) and work through each step carefully. Monitor logs at each stage before proceeding to the next.

Good luck! 🚀
