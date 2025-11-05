# Firebase Setup Guide for Lumi Reading Diary

## Prerequisites

1. Install Firebase CLI:
```bash
npm install -g firebase-tools
```

2. Install FlutterFire CLI:
```bash
dart pub global activate flutterfire_cli
```

## Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Create a project"
3. Enter project name: `lumi-reading-tracker`
4. Enable Google Analytics (optional)
5. Click "Create project"

## Step 2: Configure Firebase for Flutter

Run the following command in your project directory:

```bash
flutterfire configure
```

Select:
- Project: `lumi-reading-tracker`
- Platforms: iOS and Android
- Bundle ID for iOS: `com.lumi.lumiReadingTracker`
- Package name for Android: `com.lumi.lumi_reading_tracker`

This will automatically generate:
- `lib/firebase_options.dart`
- iOS configuration files
- Android configuration files

## Step 3: Enable Firebase Services

In Firebase Console, enable the following services:

### Authentication
1. Go to Authentication > Sign-in method
2. Enable:
   - Email/Password
   - Google Sign-In (optional)

### Firestore Database
1. Go to Firestore Database
2. Click "Create database"
3. Select "Start in production mode"
4. Choose your region
5. Click "Enable"

### Cloud Storage
1. Go to Storage
2. Click "Get started"
3. Choose security rules (start with default)
4. Select your region
5. Click "Done"

### Cloud Messaging (for notifications)
1. Go to Cloud Messaging
2. Note your Server Key and Sender ID

## Step 4: Set Up Firestore Security Rules

Replace the default rules in Firestore with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Helper functions
    function isSignedIn() {
      return request.auth != null;
    }

    function isParent() {
      return isSignedIn() &&
        resource.data.role == 'parent';
    }

    function isTeacher() {
      return isSignedIn() &&
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'teacher';
    }

    function isSchoolAdmin() {
      return isSignedIn() &&
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'schoolAdmin';
    }

    function belongsToSchool(schoolId) {
      return isSignedIn() &&
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.schoolId == schoolId;
    }

    // Users collection
    match /users/{userId} {
      allow read: if isSignedIn() && request.auth.uid == userId;
      allow write: if isSignedIn() &&
        (request.auth.uid == userId || isSchoolAdmin());
    }

    // Schools collection
    match /schools/{schoolId} {
      allow read: if belongsToSchool(schoolId);
      allow write: if isSchoolAdmin() && belongsToSchool(schoolId);
    }

    // Classes collection
    match /classes/{classId} {
      allow read: if isSignedIn() &&
        (isTeacher() || isSchoolAdmin() ||
         get(/databases/$(database)/documents/classes/$(classId)).data.studentIds.hasAny(
           get(/databases/$(database)/documents/users/$(request.auth.uid)).data.linkedChildren
         ));
      allow write: if (isTeacher() || isSchoolAdmin()) &&
        belongsToSchool(resource.data.schoolId);
    }

    // Students collection
    match /students/{studentId} {
      allow read: if isSignedIn() &&
        (isTeacher() || isSchoolAdmin() ||
         studentId in get(/databases/$(database)/documents/users/$(request.auth.uid)).data.linkedChildren);
      allow write: if (isTeacher() || isSchoolAdmin()) &&
        belongsToSchool(resource.data.schoolId);
    }

    // Reading logs collection
    match /readingLogs/{logId} {
      allow read: if isSignedIn() &&
        (request.auth.uid == resource.data.parentId ||
         isTeacher() || isSchoolAdmin());
      allow create: if isSignedIn() &&
        request.auth.uid == request.resource.data.parentId;
      allow update: if isSignedIn() &&
        (request.auth.uid == resource.data.parentId || isTeacher());
      allow delete: if isSchoolAdmin();
    }

    // Allocations collection
    match /allocations/{allocationId} {
      allow read: if isSignedIn();
      allow write: if isTeacher() || isSchoolAdmin();
    }
  }
}
```

## Step 5: Set Up Cloud Storage Security Rules

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Profile images
    match /profiles/{userId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    // School logos
    match /schools/{schoolId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
        request.auth.token.role == 'schoolAdmin';
    }

    // Reading log photos
    match /readingLogs/{logId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
  }
}
```

## Step 6: Initialize Firebase in Your App

The Firebase initialization code is already set up in `lib/main.dart`.

## Step 7: Environment Configuration

Create `.env` file in project root (for sensitive keys):

```env
# Firebase Configuration (optional - for additional security)
FIREBASE_WEB_API_KEY=your_web_api_key
FIREBASE_MESSAGING_SENDER_ID=your_sender_id

# Other API Keys
GOOGLE_MAPS_API_KEY=your_google_maps_key (if needed)
```

## Step 8: iOS Specific Setup

1. Open `ios/Runner.xcworkspace` in Xcode
2. Add Push Notifications capability
3. Add Background Modes capability (for background fetch)
4. Update `Info.plist` with necessary permissions

## Step 9: Android Specific Setup

1. Update `android/app/build.gradle`:
   - Set `minSdkVersion` to 21 or higher
   - Add Google Services plugin

2. Update `android/build.gradle`:
   - Add Google Services classpath

## Step 10: Test Firebase Connection

Run the following command to test:

```bash
flutter run
```

Check Firebase Console to verify:
- Authentication users appear
- Firestore data is being written
- Storage uploads work

## Troubleshooting

### Common Issues:

1. **iOS Build Errors**:
   - Run `cd ios && pod install`
   - Clean build folder in Xcode

2. **Android Build Errors**:
   - Ensure `google-services.json` is in `android/app/`
   - Check Gradle versions compatibility

3. **Authentication Errors**:
   - Verify SHA-1 fingerprint for Android
   - Check bundle ID for iOS

## Next Steps

1. Set up Cloud Functions for:
   - Scheduled notifications
   - Data aggregation
   - Report generation

2. Configure Firebase Analytics events

3. Set up Firebase Crashlytics for error monitoring

4. Configure Firebase Performance Monitoring

## Support

For issues, check:
- [FlutterFire Documentation](https://firebase.flutter.dev/)
- [Firebase Documentation](https://firebase.google.com/docs)
- [Flutter Community](https://flutter.dev/community)