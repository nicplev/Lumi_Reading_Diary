# Lumi Reading Diary - Enhanced Parent Linking Features

This document describes three major enhancements to the parent-student linking system implemented in the Lumi Reading Diary app.

---

## 📋 **Table of Contents**

1. [Server-Side Code Verification](#1-server-side-code-verification)
2. [Bulk Linking for Siblings](#2-bulk-linking-for-siblings)
3. [Parent Self-Unlinking](#3-parent-self-unlinking)
4. [Deployment Guide](#deployment-guide)
5. [Testing Guide](#testing-guide)

---

## 1. **Server-Side Code Verification**

### **Overview**
Replaces client-side Firestore queries with a secure Cloud Function for code verification during parent registration.

### **Why This Matters**

**Security Improvements:**
- ✅ Eliminates unauthenticated Firestore access
- ✅ Rate limiting prevents brute-force attacks (max 10 attempts/minute per IP)
- ✅ Comprehensive audit logging of all verification attempts
- ✅ Centralized validation logic
- ✅ IP-based rate limiting

**Before (Vulnerable)**:
```dart
// Client can query Firestore directly
final linkCode = await firestore
    .collection('studentLinkCodes')
    .where('code', '==', userInput)
    .get();
// Anyone can enumerate codes!
```

**After (Secure)**:
```typescript
// Cloud Function with rate limiting
export const verifyParentLinkCode = functions.https.onCall(...)
// - Rate limited by IP
// - Audit logged
// - No direct Firestore access
```

### **Cloud Function: `verifyParentLinkCode`**

**Location**: `functions/src/index.ts` (lines 469-652)

**Features**:
1. **Rate Limiting**: Max 10 attempts per IP per minute
2. **Audit Logging**: Tracks all verification attempts (success/failure)
3. **Comprehensive Validation**: Checks code format, status, expiration
4. **Security**: No direct client access to Firestore
5. **Error Handling**: User-friendly error messages

**Request**:
```typescript
{
  code: "ABC12345"
}
```

**Response (Success)**:
```typescript
{
  success: true,
  codeData: {
    id: "doc_id",
    code: "ABC12345",
    studentId: "student123",
    schoolId: "school456",
    status: "active",
    expiresAt: Timestamp,
    metadata: {
      studentFirstName: "John",
      studentLastName: "Doe",
      studentFullName: "John Doe"
    }
  }
}
```

**Response (Error)**:
```typescript
// Rate limit exceeded
{
  code: "resource-exhausted",
  message: "Too many attempts. Please wait a minute and try again."
}

// Invalid code
{
  code: "not-found",
  message: "Invalid or expired code. Please check with your school."
}

// Code already used
{
  code: "failed-precondition",
  message: "This code has already been used by another parent."
}
```

### **Audit Logging**

All verification attempts are logged to the `auditLogs` collection:

**Failed Attempt**:
```json
{
  "type": "code_verification_failed",
  "code": "ABC12345",
  "reason": "code_not_found | code_already_used | code_expired | code_revoked",
  "ip": "192.168.1.1",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

**Successful Attempt**:
```json
{
  "type": "code_verification_success",
  "code": "ABC12345",
  "codeId": "doc_id",
  "studentId": "student123",
  "schoolId": "school456",
  "ip": "192.168.1.1",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### **Implementation Cost**

| Aspect | Details |
|--------|---------|
| **Development Time** | ~4 hours (Cloud Function + client integration) |
| **Cloud Function Invocations** | Free tier: 2M/month, then $0.40/million |
| **Firestore Reads** | Reduced (no direct client queries) |
| **Maintenance** | Low (standard pattern) |
| **Security Improvement** | Very High |

### **Recommendation**
⭐⭐⭐⭐⭐ **HIGHLY RECOMMENDED** for production deployment

---

## 2. **Bulk Linking for Siblings**

### **Overview**
Allows teachers/admins to generate a single link code that parents can use to link multiple children (siblings) at once.

### **Use Cases**
- Parents with multiple children in the same school
- Reduces registration friction (one code instead of multiple)
- Better user experience for families

### **Cloud Function: `createBulkLinkCode`**

**Location**: `functions/src/index.ts` (lines 654-810)

**Features**:
1. **Multi-Student Linking**: Link up to 10 students with one code
2. **Permission Checking**: Only admins/teachers can create bulk codes
3. **Student Validation**: Verifies all students exist before creating code
4. **Comprehensive Metadata**: Stores all student names for display
5. **Unique Code Generation**: Same collision detection as single codes

**Request**:
```typescript
{
  studentIds: ["student1", "student2", "student3"],
  schoolId: "school123",
  validityDays: 365  // optional, defaults to 365
}
```

**Response**:
```typescript
{
  success: true,
  codeId: "bulk_code_doc_id",
  code: "XYZ789AB",
  studentCount: 3,
  students: [
    {
      studentId: "student1",
      firstName: "John",
      lastName: "Doe",
      fullName: "John Doe"
    },
    {
      studentId: "student2",
      firstName: "Jane",
      lastName: "Doe",
      fullName: "Jane Doe"
    },
    {
      studentId: "student3",
      firstName: "Jack",
      lastName: "Doe",
      fullName: "Jack Doe"
    }
  ],
  expiresAt: Timestamp
}
```

### **Firestore Document Structure**

**Bulk Link Code Document** (`studentLinkCodes/{codeId}`):
```json
{
  "code": "XYZ789AB",
  "type": "bulk",  // ← Differentiates from single codes
  "studentIds": ["student1", "student2", "student3"],
  "schoolId": "school123",
  "status": "active",
  "createdAt": "2025-01-15T10:00:00Z",
  "expiresAt": "2026-01-15T10:00:00Z",
  "createdBy": "teacher_user_id",
  "metadata": {
    "students": [
      {
        "studentId": "student1",
        "firstName": "John",
        "lastName": "Doe",
        "fullName": "John Doe"
      },
      ...
    ],
    "studentCount": 3
  }
}
```

### **Client-Side Integration**

**Updated `linkParentToStudent` Method** (`lib/services/parent_linking_service.dart`):
- Detects bulk codes automatically via `type` field
- Processes multiple students in a single transaction
- Skips already-linked students gracefully
- Creates bulk notification for teachers

**Key Logic**:
```dart
// Check if this is a bulk code
final isBulkCode = linkCodeData['type'] == 'bulk';
final studentIds = isBulkCode
    ? List<String>.from(linkCodeData['studentIds'] ?? [])
    : [linkCodeData['studentId'] as String];

// Link all students atomically
for (final studentId in studentIds) {
  // Update student with parent ID
  transaction.update(studentRef, {
    'parentIds': FieldValue.arrayUnion([parentUserId]),
  });
  linkedStudentIds.add(studentId);
}

// Update parent with all children
transaction.update(parentRef, {
  'linkedChildren': FieldValue.arrayUnion(linkedStudentIds),
});
```

### **User Flow**

```
Teacher/Admin:
1. Select multiple students (siblings)
2. Click "Generate Bulk Code"
3. Share single code with parent

Parent:
4. Enter the bulk code during registration
5. System automatically links all children
6. Parent home shows all linked children
```

### **Benefits**
- ✅ **Convenience**: One code for entire family
- ✅ **Reduced Errors**: No need to manage multiple codes
- ✅ **Better UX**: Faster onboarding for multi-child families
- ✅ **Atomic**: All students linked together or none

---

## 3. **Parent Self-Unlinking**

### **Overview**
Allows parents to remove themselves from a student's account without contacting administrators.

### **Use Cases**
- Incorrect linking during registration
- Separated/divorced parents removing access
- Account cleanup
- Self-service reduces admin support burden

### **Cloud Function: `unlinkParentFromStudent`**

**Location**: `functions/src/index.ts` (lines 812-932)

**Features**:
1. **Atomic Transaction**: Ensures parent and student are updated together
2. **Validation**: Checks parent is actually linked before unlinking
3. **Audit Logging**: Tracks all unlink events
4. **Self-Service**: No admin intervention required

**Request**:
```typescript
{
  studentId: "student123",
  schoolId: "school456"
}
```

**Response (Success)**:
```typescript
{
  success: true,
  message: "Successfully unlinked from student."
}
```

**Response (Error)**:
```typescript
// Not linked
{
  code: "failed-precondition",
  message: "You are not linked to this student."
}

// Student not found
{
  code: "not-found",
  message: "Student not found."
}
```

### **Transaction Logic**

```typescript
await db.runTransaction(async (transaction) => {
  // 1. Verify parent is linked
  const linkedChildren = parentData.linkedChildren || [];
  if (!linkedChildren.includes(studentId)) {
    throw new Error("Not linked");
  }

  // 2. Remove parent from student's parentIds
  const updatedParentIds = studentData.parentIds.filter(
    id => id !== parentUserId
  );

  // 3. Remove student from parent's linkedChildren
  const updatedLinkedChildren = linkedChildren.filter(
    id => id !== studentId
  );

  // 4. Update both documents atomically
  transaction.update(studentRef, { parentIds: updatedParentIds });
  transaction.update(parentRef, { linkedChildren: updatedLinkedChildren });

  // 5. Create audit log
  transaction.set(auditLogRef, {
    type: "parent_self_unlink",
    parentUserId,
    studentId,
    schoolId,
    timestamp
  });
});
```

### **Audit Logging**

**Unlink Event** (`auditLogs/{logId}`):
```json
{
  "type": "parent_self_unlink",
  "parentUserId": "parent123",
  "studentId": "student456",
  "schoolId": "school789",
  "timestamp": "2025-01-15T11:30:00Z"
}
```

### **Security Considerations**
- ✅ Requires authentication (only logged-in parents)
- ✅ Parents can only unlink themselves (not other parents)
- ✅ Validation prevents unlinking non-existent links
- ✅ Atomic transaction prevents partial unlinking
- ✅ Audit trail for compliance

### **Benefits**
- ✅ **Self-Service**: Reduces admin workload
- ✅ **Privacy**: Parents control their own access
- ✅ **Compliance**: Audit trail for legal requirements
- ✅ **User Empowerment**: Parents have control

---

## **Deployment Guide**

### **Prerequisites**
1. Firebase project configured
2. Cloud Functions enabled
3. Firestore initialized
4. Flutter app connected to Firebase

### **Step 1: Deploy Cloud Functions**

```bash
cd functions

# Install dependencies (if needed)
npm install

# Deploy all new functions
firebase deploy --only functions:verifyParentLinkCode,functions:createBulkLinkCode,functions:unlinkParentFromStudent

# Or deploy all functions
firebase deploy --only functions
```

### **Step 2: Update Firestore Security Rules** (Optional)

If implementing server-side verification, you can tighten rules:

```javascript
// Remove unauthenticated access since we're using Cloud Functions
match /studentLinkCodes/{codeId} {
  // Remove: allow list: if request.query.limit == 1...

  // Keep authenticated access for admins/teachers
  allow read: if isSignedIn() &&
                 (isSchoolAdmin(resource.data.schoolId) ||
                  isTeacher(resource.data.schoolId));

  // Rest remains the same...
}
```

### **Step 3: Test Cloud Functions**

```bash
# Test code verification
curl -X POST \
  https://us-central1-YOUR_PROJECT.cloudfunctions.net/verifyParentLinkCode \
  -H "Content-Type: application/json" \
  -d '{"data": {"code": "ABC12345"}}'

# Test bulk code creation (requires auth token)
curl -X POST \
  https://us-central1-YOUR_PROJECT.cloudfunctions.net/createBulkLinkCode \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"data": {"studentIds": ["student1", "student2"], "schoolId": "school123"}}'
```

### **Step 4: Monitor Logs**

```bash
# View function logs
firebase functions:log

# View specific function
firebase functions:log --only verifyParentLinkCode

# Real-time logs
firebase functions:log --tail
```

---

## **Testing Guide**

### **Test 1: Server-Side Code Verification**

#### Test Rate Limiting:
```dart
// Attempt code verification 11 times rapidly
for (int i = 0; i < 11; i++) {
  try {
    await FirebaseFunctions.instance
        .httpsCallable('verifyParentLinkCode')
        .call({'code': 'ABC12345'});
  } catch (e) {
    if (i == 10) {
      // Should get rate limit error
      expect(e.code, 'resource-exhausted');
    }
  }
}
```

#### Test Audit Logging:
```dart
// Check auditLogs collection after verification
final logs = await FirebaseFirestore.instance
    .collection('auditLogs')
    .where('type', isEqualTo: 'code_verification_success')
    .orderBy('timestamp', descending: true)
    .limit(1)
    .get();

expect(logs.docs.first.data()['code'], 'ABC12345');
```

### **Test 2: Bulk Linking for Siblings**

#### Create Bulk Code:
```dart
final result = await FirebaseFunctions.instance
    .httpsCallable('createBulkLinkCode')
    .call({
      'studentIds': ['student1', 'student2', 'student3'],
      'schoolId': 'school123',
    });

expect(result.data['studentCount'], 3);
expect(result.data['students'].length, 3);
```

#### Test Parent Registration with Bulk Code:
```dart
// Register parent with bulk code
await parentRegistrationScreen.verifyCode('BULKCODE');

// Complete registration
await parentRegistrationScreen.completeRegistration(
  email: 'parent@example.com',
  password: 'password123',
  fullName: 'Parent Name',
);

// Verify all children are linked
final parent = await FirebaseFirestore.instance
    .collection('schools/school123/parents/${parentId}')
    .get();

expect(parent.data()['linkedChildren'].length, 3);
```

### **Test 3: Parent Self-Unlinking**

#### Test Unlinking:
```dart
// Link parent first
await linkingService.linkParentToStudent(
  code: 'TESTCODE',
  parentUserId: 'parent123',
  parentEmail: 'parent@example.com',
);

// Verify link exists
final parentBefore = await FirebaseFirestore.instance
    .collection('schools/school123/parents/parent123')
    .get();
expect(parentBefore.data()['linkedChildren'].contains('student456'), true);

// Unlink
final result = await FirebaseFunctions.instance
    .httpsCallable('unlinkParentFromStudent')
    .call({
      'studentId': 'student456',
      'schoolId': 'school123',
    });

expect(result.data['success'], true);

// Verify link removed
final parentAfter = await FirebaseFirestore.instance
    .collection('schools/school123/parents/parent123')
    .get();
expect(parentAfter.data()['linkedChildren'].contains('student456'), false);

// Verify audit log created
final auditLog = await FirebaseFirestore.instance
    .collection('auditLogs')
    .where('type', isEqualTo: 'parent_self_unlink')
    .where('parentUserId', isEqualTo: 'parent123')
    .limit(1)
    .get();
expect(auditLog.docs.isNotEmpty, true);
```

---

## **Monitoring & Analytics**

### **Key Metrics to Track**

1. **Code Verification**:
   - Success rate
   - Failure reasons (not found, expired, used, etc.)
   - Rate limit hits
   - Average response time

2. **Bulk Linking**:
   - Number of bulk codes created
   - Average students per bulk code
   - Success rate

3. **Self-Unlinking**:
   - Unlinking frequency
   - Re-linking patterns
   - Common reasons (via user feedback)

### **Firestore Queries for Analytics**

```dart
// Failed verifications by reason
final failedByReason = await FirebaseFirestore.instance
    .collection('auditLogs')
    .where('type', isEqualTo: 'code_verification_failed')
    .get();

final reasonCounts = <String, int>{};
for (final doc in failedByReason.docs) {
  final reason = doc.data()['reason'];
  reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
}

// Rate limit violations
final rateLimitHits = await FirebaseFirestore.instance
    .collection('auditLogs')
    .where('type', isEqualTo: 'code_verification_failed')
    .where('reason', isEqualTo: 'rate_limit')
    .get();

print('Rate limit hits: ${rateLimitHits.docs.length}');

// Bulk code usage
final bulkCodes = await FirebaseFirestore.instance
    .collection('studentLinkCodes')
    .where('type', isEqualTo: 'bulk')
    .where('status', isEqualTo: 'used')
    .get();

final totalStudents = bulkCodes.docs.fold<int>(
  0,
  (sum, doc) => sum + (doc.data()['studentIds']?.length ?? 0),
);

print('Total students linked via bulk codes: $totalStudents');
```

---

## **Cost Analysis**

### **Cloud Functions Pricing** (US-Central1)

| Function | Invocations/Month | Cost (Free Tier) | Cost (Paid) |
|----------|-------------------|------------------|-------------|
| `verifyParentLinkCode` | ~10,000 | Free | $0.004 |
| `createBulkLinkCode` | ~100 | Free | $0.00004 |
| `unlinkParentFromStudent` | ~500 | Free | $0.0002 |
| **Total** | ~10,600 | **Free** | **~$0.0042** |

**Note**: Free tier includes 2M invocations/month. Most schools will stay within free tier.

### **Firestore Costs**

- **Reads**: Reduced (server-side verification eliminates client queries)
- **Writes**: Same as before
- **Storage**: Minimal increase (audit logs)

**Estimated monthly savings**: $5-10 in reduced reads

---

## **Best Practices**

### **For Administrators**

1. **Bulk Codes**:
   - Only create for actual siblings (same family)
   - Verify student IDs before generation
   - Communicate code to parents securely

2. **Monitoring**:
   - Review audit logs weekly
   - Monitor rate limit violations
   - Track unlinking patterns for policy insights

3. **Security**:
   - Regularly review and rotate codes if needed
   - Investigate suspicious rate limit violations
   - Monitor failed verification attempts

### **For Developers**

1. **Error Handling**:
   - Always catch and display user-friendly messages
   - Log errors for debugging
   - Implement retry logic for network failures

2. **Testing**:
   - Test bulk codes with max students (10)
   - Test concurrent parent registrations
   - Test rate limiting thresholds

3. **Performance**:
   - Monitor Cloud Function execution time
   - Optimize Firestore queries
   - Use appropriate indexes

---

## **Troubleshooting**

### **Issue**: Rate limit errors during normal use

**Solution**:
- Check for automated scripts hitting the API
- Review IP addresses in audit logs
- Adjust rate limit threshold if needed (currently 10/minute)

### **Issue**: Bulk code linking fails midway

**Solution**:
- Check Cloud Function logs for specific error
- Verify all student IDs exist
- Ensure parent has proper permissions

### **Issue**: Self-unlinking not working

**Solution**:
- Verify parent is authenticated
- Check parent is actually linked to student
- Review transaction errors in logs

---

## **Future Enhancements**

1. **Server-Side Verification**:
   - Add CAPTCHA for additional bot protection
   - Implement per-user (not just per-IP) rate limiting
   - Add webhook notifications for admins on suspicious activity

2. **Bulk Linking**:
   - Support cross-school bulk codes (for district-level)
   - Add QR code generation for bulk codes
   - Email/SMS distribution of bulk codes

3. **Self-Unlinking**:
   - Add confirmation step with reason dropdown
   - Implement "undo" feature (within 24 hours)
   - Send notification to remaining parent when one unlinks

---

## **Support & Contact**

For questions or issues:
- **GitHub Issues**: https://github.com/nicplev/Lumi_Reading_Diary/issues
- **Documentation**: Check this file and code comments
- **Logs**: Use Firebase Console for Cloud Function logs

---

## **License**

All features are part of the Lumi Reading Diary project and follow the same license.
