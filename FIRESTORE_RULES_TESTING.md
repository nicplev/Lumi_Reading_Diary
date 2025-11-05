# Temporary Firestore Rules for Testing

## ⚠️ WARNING: TESTING ONLY - NOT FOR PRODUCTION ⚠️

These rules are for testing purposes only. They allow authenticated users to read and write most data.
**NEVER use these rules in a production environment!**

## Temporary Testing Rules

Copy and paste these rules into your Firebase Console:
1. Go to Firebase Console > Firestore Database > Rules
2. Replace the existing rules with these temporary ones
3. Click "Publish"

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow authenticated users to read/write everything for testing
    // ⚠️ TESTING ONLY - VERY PERMISSIVE ⚠️

    match /{document=**} {
      // Allow read/write access to all authenticated users
      allow read, write: if request.auth != null;
    }
  }
}
```

## Alternative: Slightly More Restrictive Testing Rules

If you want slightly more control while testing:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Helper functions
    function isSignedIn() {
      return request.auth != null;
    }

    // Allow authenticated users broader access for testing
    match /users/{userId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }

    match /schools/{schoolId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();  // Temporarily allow any authenticated user to create schools
    }

    match /classes/{classId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();  // Temporarily allow any authenticated user to manage classes
    }

    match /students/{studentId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }

    match /readingLogs/{logId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }

    match /allocations/{allocationId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn();
    }
  }
}
```

## How to Apply These Rules

1. **Open Firebase Console:**
   - Go to https://console.firebase.google.com
   - Select your project

2. **Navigate to Firestore Rules:**
   - Click on "Firestore Database" in the left sidebar
   - Click on the "Rules" tab

3. **Replace Rules:**
   - Copy one of the rule sets above
   - Replace the entire contents in the rules editor
   - Click "Publish"

4. **Test Your App:**
   - Now your app should be able to create test data
   - You can create schools, classes, and other data for testing

## ⚠️ IMPORTANT: Restore Production Rules

After testing, **IMMEDIATELY** restore your production rules:

1. Go back to Firebase Console > Firestore > Rules
2. Copy the original rules from your FIREBASE_SETUP.md file
3. Replace the testing rules with the production rules
4. Click "Publish"

## Original Production Rules Reference

Your original production rules are saved in: `/Users/nicplev/lumi_reading_tracker/FIREBASE_SETUP.md`

## Testing Checklist

- [ ] Applied temporary testing rules
- [ ] Completed testing
- [ ] Restored production rules
- [ ] Verified production rules are active

## Security Note

The temporary rules above allow ANY authenticated user to read and write data. This means:
- Any logged-in user can see all data
- Any logged-in user can modify all data
- There's no role-based access control

This is why these rules should ONLY be used for local development and testing, never in production.