# School Code Setup & Testing Guide

## Overview

This guide explains how to set up and test the school code feature for teacher registration in the Lumi Reading Tracker app.

## What is a School Code?

School codes are unique codes that school admins create and share with teachers to allow them to register and join their school. This ensures that only authorized teachers can create accounts associated with a specific school.

## Test School Code for Beaumaris Primary School

For testing purposes, we'll use the following school code:

- **School Code**: `BPS74383`
- **School**: Beaumaris Primary School (BPS)
- **School ID**: (Your school ID from Firestore)

## Setting Up Test Data in Firestore

### Step 1: Find Your School ID

1. Open Firebase Console
2. Navigate to Firestore Database
3. Go to the `schools` collection
4. Find the Beaumaris Primary School document
5. Copy the document ID - this is your `schoolId`

### Step 2: Create the School Code Document

Add a new document to the `schoolCodes` collection with the following data:

**Collection**: `schoolCodes`

**Document Data**:
```json
{
  "code": "BPS74383",
  "schoolId": "YOUR_SCHOOL_ID_HERE",
  "schoolName": "Beaumaris Primary School",
  "isActive": true,
  "createdAt": "2025-11-23T00:00:00.000Z",
  "createdBy": "admin_user_id",
  "usageCount": 0,
  "maxUsages": null,
  "expiresAt": null
}
```

**Field Descriptions**:
- `code`: The school code teachers will enter (uppercase, e.g., "BPS74383")
- `schoolId`: The ID of the school document in the `schools` collection
- `schoolName`: Display name of the school
- `isActive`: Whether the code is currently active (true/false)
- `createdAt`: Timestamp when the code was created
- `createdBy`: UID of the admin who created the code (optional)
- `usageCount`: Number of times the code has been used (starts at 0)
- `maxUsages`: Maximum number of uses allowed (null = unlimited)
- `expiresAt`: Expiration date (null = never expires)

### Step 3: Using Firebase Console to Create the Code

1. Open Firebase Console → Firestore Database
2. Click "Start collection" or navigate to existing collections
3. Collection ID: `schoolCodes`
4. Click "Add document"
5. Use "Auto-ID" or set a custom document ID
6. Add each field shown above with the correct type:
   - `code`: string
   - `schoolId`: string (your school's document ID)
   - `schoolName`: string
   - `isActive`: boolean (true)
   - `createdAt`: timestamp (current date)
   - `createdBy`: string (optional)
   - `usageCount`: number (0)
   - `maxUsages`: null or number
   - `expiresAt`: null or timestamp

7. Click "Save"

## Testing the School Code Feature

### Test 1: Teacher Registration with Valid Code

1. Open the Lumi app
2. Navigate to the registration screen
3. Select "Teacher" as the role
4. Fill in the form fields:
   - Email: `teacher@test.com`
   - Password: `Test123!`
   - Full Name: `Test Teacher`
   - School Code: `BPS74383`
5. Click "Register"

**Expected Result**:
- ✅ Registration succeeds
- ✅ Teacher account created in `schools/{schoolId}/users/{uid}`
- ✅ Teacher can log in successfully
- ✅ School code's `usageCount` increments to 1

### Test 2: Teacher Registration with Invalid Code

1. Navigate to registration screen
2. Select "Teacher" as the role
3. Enter an invalid code (e.g., `INVALID123`)
4. Fill in other fields
5. Click "Register"

**Expected Result**:
- ❌ Registration fails
- ❌ Error message: "Invalid school code. Please check the code and try again."
- ✅ No user account created

### Test 3: School Code Case Insensitivity

1. Navigate to registration screen
2. Select "Teacher" as the role
3. Enter the code in lowercase: `bps74383`
4. Fill in other fields
5. Click "Register"

**Expected Result**:
- ✅ Registration succeeds (code is normalized to uppercase)
- ✅ Teacher account created successfully

### Test 4: Inactive School Code

1. In Firebase Console, set the code's `isActive` to `false`
2. Try registering with the code
3. Click "Register"

**Expected Result**:
- ❌ Registration fails
- ❌ Error message: "This school code has been deactivated"

### Test 5: Expired School Code

1. In Firebase Console, set `expiresAt` to a past date
2. Try registering with the code
3. Click "Register"

**Expected Result**:
- ❌ Registration fails
- ❌ Error message: "This school code has expired"

### Test 6: Maximum Usage Limit

1. In Firebase Console, set `maxUsages` to `1`
2. Set `usageCount` to `1`
3. Try registering with the code
4. Click "Register"

**Expected Result**:
- ❌ Registration fails
- ❌ Error message: "This school code has reached its maximum usage limit"

## Verification After Successful Registration

After a successful teacher registration, verify the following in Firebase Console:

### 1. User Document Created
**Path**: `schools/{schoolId}/users/{uid}`

Should contain:
```json
{
  "email": "teacher@test.com",
  "fullName": "Test Teacher",
  "role": "teacher",
  "isActive": true,
  "createdAt": "timestamp",
  "schoolId": "YOUR_SCHOOL_ID"
}
```

### 2. User School Index Created
**Path**: `userSchoolIndex/{emailHash}`

Should contain:
```json
{
  "email": "teacher@test.com",
  "schoolId": "YOUR_SCHOOL_ID",
  "userType": "user",
  "userId": "uid",
  "updatedAt": "timestamp"
}
```

### 3. School Code Usage Incremented
**Path**: `schoolCodes/{codeId}`

The `usageCount` field should increment by 1 each time a teacher successfully registers with the code.

### 4. School Teacher Count Incremented
**Path**: `schools/{schoolId}`

The `teacherCount` field should increment by 1.

## Creating Additional School Codes

School admins can create new codes programmatically or through an admin interface. Here's how codes can be created:

### Option 1: Using SchoolCodeService (Programmatic)

```dart
final schoolCodeService = SchoolCodeService();

final codeId = await schoolCodeService.createSchoolCode(
  code: 'BPS74383',
  schoolId: 'your_school_id',
  schoolName: 'Beaumaris Primary School',
  createdBy: 'admin_uid',
  expiresAt: DateTime.now().add(Duration(days: 365)), // Optional: expires in 1 year
  maxUsages: 50, // Optional: max 50 teachers
);

print('School code created with ID: $codeId');
```

### Option 2: Manually in Firebase Console

Follow the steps in "Step 3: Using Firebase Console to Create the Code" above.

## Security Rules

Ensure your Firestore security rules allow reading school codes during registration:

```javascript
// In firestore.rules
match /schoolCodes/{codeId} {
  // Allow anyone to read (for validation during registration)
  allow read: if request.auth != null;

  // Only school admins can create/update codes
  allow create, update: if request.auth != null &&
    get(/databases/$(database)/documents/schools/$(request.resource.data.schoolId)/users/$(request.auth.uid)).data.role == 'schoolAdmin';

  // Only school admins can delete codes
  allow delete: if request.auth != null &&
    get(/databases/$(database)/documents/schools/$(resource.data.schoolId)/users/$(request.auth.uid)).data.role == 'schoolAdmin';
}
```

## Troubleshooting

### Error: "School code cannot be empty"
- **Cause**: User didn't enter a code
- **Solution**: Ensure the school code field is filled in

### Error: "School code must be at least 6 characters"
- **Cause**: Code is too short
- **Solution**: Enter a code with at least 6 characters

### Error: "Invalid school code"
- **Cause**: Code doesn't exist in database or is misspelled
- **Solution**: Double-check the code spelling and verify it exists in Firestore

### Error: "This school code has been deactivated"
- **Cause**: The code's `isActive` field is set to false
- **Solution**: Have the school admin reactivate the code or create a new one

### Code validation is slow
- **Cause**: Missing Firestore index
- **Solution**: Run `firebase deploy --only firestore:indexes` to deploy the indexes

## Deployment Checklist

Before deploying the school code feature to production:

- [ ] Deploy Firestore indexes: `firebase deploy --only firestore:indexes`
- [ ] Update Firestore security rules for `schoolCodes` collection
- [ ] Create initial school codes for all existing schools
- [ ] Test registration flow with valid codes
- [ ] Test registration flow with invalid codes
- [ ] Verify usage count increments correctly
- [ ] Verify teacher count increments correctly
- [ ] Verify user school index is created
- [ ] Test code validation edge cases (expired, inactive, max usage)
- [ ] Document code creation process for school admins

## Next Steps

1. **Admin Interface**: Create an admin dashboard where school admins can:
   - Generate new school codes
   - View existing codes and their usage statistics
   - Deactivate or reactivate codes
   - Set expiration dates and usage limits

2. **Email Integration**: Add functionality to email school codes to teachers directly from the admin interface

3. **Code Analytics**: Track which codes are most used and when teachers typically register

---

**Created**: November 23, 2025
**Last Updated**: November 23, 2025
