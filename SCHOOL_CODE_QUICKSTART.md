# School Code Feature - Quick Start Guide

## ✅ What's Been Completed

All the code implementation for the school code feature is complete:

1. ✅ **Data Model** - [SchoolCodeModel](lib/data/models/school_code_model.dart)
2. ✅ **Validation Service** - [SchoolCodeService](lib/services/school_code_service.dart)
3. ✅ **Registration UI** - Updated [RegisterScreen](lib/screens/auth/register_screen.dart)
4. ✅ **Firestore Indexes** - [firestore.indexes.json](firestore.indexes.json)
5. ✅ **Security Rules** - [firestore.rules](firestore.rules)
6. ✅ **Setup Script** - [setup_test_school_code.dart](scripts/setup_test_school_code.dart)
7. ✅ **Documentation** - [SCHOOL_CODE_SETUP.md](SCHOOL_CODE_SETUP.md)

## 🚀 Deploy & Test (3 Steps)

### Step 1: Deploy Firestore Configuration

Deploy the indexes and security rules:

```bash
# Deploy both indexes and rules together
firebase deploy --only firestore

# Or deploy separately:
firebase deploy --only firestore:indexes
firebase deploy --only firestore:rules
```

**Wait Time**: Firestore will build the indexes in the background (usually 1-2 minutes).

### Step 2: Create Test School Code

Run the automated setup script:

```bash
dart run scripts/setup_test_school_code.dart
```

This script will:
- ✅ Find Beaumaris Primary School in your Firestore
- ✅ Create the test code `BPS74383`
- ✅ Verify the code was created correctly

**Alternative**: If you prefer, you can create the code manually in Firebase Console following the instructions in [SCHOOL_CODE_SETUP.md](SCHOOL_CODE_SETUP.md).

### Step 3: Test Teacher Registration

Run your app and test the new feature:

```bash
flutter run
```

Then:
1. Navigate to registration screen
2. Select **"Teacher"** role
3. Fill in the form:
   - **School Code**: `BPS74383` (or lowercase `bps74383`)
   - **Email**: `teacher@test.com`
   - **Password**: `Test123!`
   - **Full Name**: `Test Teacher`
4. Click "Register"

**Expected Result**: ✅ Registration succeeds and teacher is created in the correct school!

## 🔍 Verify It Worked

After successful registration, check in Firebase Console:

### 1. User Created
**Path**: `schools/{schoolId}/users/{uid}`

Should see the new teacher account.

### 2. Code Usage Incremented
**Path**: `schoolCodes/{codeId}`

The `usageCount` should be `1` (incremented from `0`).

### 3. School Counter Updated
**Path**: `schools/{schoolId}`

The `teacherCount` should have incremented by 1.

### 4. Login Index Created
**Path**: `userSchoolIndex/{emailHash}`

Should have an entry for fast login lookups.

## 🧪 Test Cases

Run through these test scenarios from [SCHOOL_CODE_SETUP.md](SCHOOL_CODE_SETUP.md):

- ✅ **Test 1**: Valid code registration (should succeed)
- ✅ **Test 2**: Invalid code (should fail with error message)
- ✅ **Test 3**: Case insensitivity (lowercase `bps74383` should work)
- ✅ **Test 4**: Inactive code (set `isActive: false` and try)
- ✅ **Test 5**: Expired code (set `expiresAt` to past date and try)
- ✅ **Test 6**: Max usage limit (set `maxUsages: 1`, `usageCount: 1` and try)

## 🔐 Security Features

The security rules ensure:
- ✅ Only authenticated users can read school codes
- ✅ Only school admins can create/delete codes
- ✅ Anyone can increment usage count (but only by 1, and only that field)
- ✅ No enumeration attacks (can't list all codes)
- ✅ Email hashing for privacy in login index

## 📊 What Happens During Teacher Registration

```
1. User fills in registration form with school code
   ↓
2. App validates school code via SchoolCodeService
   ↓
3. If valid: Get schoolId from code
   ↓
4. Create Firebase Auth account
   ↓
5. Create user document in schools/{schoolId}/users/{uid}
   ↓
6. Increment school's teacherCount
   ↓
7. Create user-school index entry (for fast login)
   ↓
8. Increment school code's usageCount
   ↓
9. Registration complete! ✅
```

## 🛠️ Creating Additional School Codes

### Option 1: Programmatically (Future Admin Dashboard)

```dart
final schoolCodeService = SchoolCodeService();

await schoolCodeService.createSchoolCode(
  code: 'NEWCODE123',
  schoolId: 'school_id_here',
  schoolName: 'School Name',
  createdBy: 'admin_uid',
  expiresAt: DateTime.now().add(Duration(days: 365)), // Optional
  maxUsages: 50, // Optional
);
```

### Option 2: Firebase Console (Manual)

1. Go to Firebase Console → Firestore Database
2. Navigate to `schoolCodes` collection
3. Click "Add document"
4. Fill in the fields as described in [SCHOOL_CODE_SETUP.md](SCHOOL_CODE_SETUP.md)

## 📈 Next Steps (Future Enhancements)

1. **Admin Dashboard** - UI for school admins to generate and manage codes
2. **Email Integration** - Send codes to teachers via email
3. **Code Analytics** - Track code usage and statistics
4. **Bulk Code Generation** - Create multiple codes at once

## ❓ Troubleshooting

### Script fails to find school
- **Solution**: Check that school name in Firestore is exactly "Beaumaris Primary School"

### Code validation is slow
- **Solution**: Ensure indexes are deployed: `firebase deploy --only firestore:indexes`

### Permission denied errors
- **Solution**: Ensure security rules are deployed: `firebase deploy --only firestore:rules`

### Teacher registration fails
- **Solution**: Check Firebase Console logs for specific error message

## 📚 Full Documentation

See [SCHOOL_CODE_SETUP.md](SCHOOL_CODE_SETUP.md) for complete details on:
- Field descriptions
- All test scenarios
- Security rules explanation
- Creating codes for other schools
- Troubleshooting guide

---

**Status**: ✅ Ready to Deploy and Test
**Test Code**: BPS74383
**School**: Beaumaris Primary School

