# Lumi Reading Diary - School Onboarding & Parent Linking Guide

## 📋 Table of Contents
1. [Overview](#overview)
2. [School Onboarding System](#school-onboarding-system)
3. [Parent-Student Linking Protocol](#parent-student-linking-protocol)
4. [Implementation Details](#implementation-details)
5. [User Flows](#user-flows)
6. [Security & Privacy](#security--privacy)
7. [Admin Guide](#admin-guide)
8. [Troubleshooting](#troubleshooting)

---

## Overview

This guide covers the comprehensive onboarding system and parent-student linking protocol implemented for Lumi Reading Diary. The system is designed to provide a professional, seamless experience for schools, teachers, and parents.

### Key Features

✅ **Professional School Onboarding**
- Interactive demo presentation
- Step-by-step registration wizard
- Automated school and admin account creation
- 15-minute setup process

✅ **Seamless Parent Linking**
- Unique 8-character linking codes per student
- Secure parent registration and verification
- Automatic student-parent relationship creation
- Teacher notifications on parent linking

✅ **Admin Management Tools**
- Bulk code generation for all students
- Code management and tracking
- Export capabilities (CSV format)
- Visual status indicators

---

## School Onboarding System

### 1. Demo Presentation Screen

**Location:** `lib/screens/onboarding/school_demo_screen.dart`

**Purpose:** Professional presentation of Lumi features to schools

**Features:**
- 6 interactive slides covering:
  - Welcome & overview
  - Teacher features
  - Parent features
  - School admin features
  - Parent linking system
  - Key benefits
- Progress indicators
- Skip to registration option
- Beautiful animations

**Access:** From login screen → "School? Request a Demo" button

---

### 2. Demo Request Screen

**Location:** `lib/screens/onboarding/demo_request_screen.dart`

**Purpose:** Capture school information and create demo request

**Information Collected:**
- School name
- Contact person name
- Email address
- Phone number (optional)
- Estimated student count
- Estimated teacher count
- Referral source

**Process:**
1. User fills out demo request form
2. Creates `SchoolOnboardingModel` in Firestore
3. Status: `demo` → `interested` → `registered`
4. Automatically redirects to registration wizard

---

### 3. School Registration Wizard

**Location:** `lib/screens/onboarding/school_registration_wizard.dart`

**Purpose:** Complete 4-step school setup process

#### Step 1: School Information
- School name
- Physical address
- Contact email
- Contact phone

#### Step 2: Admin Account Creation
- Admin full name
- Admin email (becomes login)
- Password (minimum 8 characters)
- Password confirmation

**Backend Action:** Creates:
- Firebase Auth user account
- School document in `schools` collection
- Admin user document in `schools/{schoolId}/users`

#### Step 3: Reading Level System
- Choose from:
  - A-Z Levels (A through Z)
  - PM Benchmark (1-30)
  - Lexile (BR to 1400L)
  - Custom levels

#### Step 4: Completion
- Welcome message with Lumi mascot
- Direct navigation to admin dashboard

---

## Parent-Student Linking Protocol

### Overview

The parent-student linking system uses unique, secure codes to connect parent accounts with student profiles. This ensures:
- Only authorized parents can access student data
- Teachers maintain control over who links
- Multiple parents can link to one student
- Audit trail of all linking activities

---

### 1. Generating Student Link Codes

**Location:** `lib/screens/admin/parent_linking_management_screen.dart`

**Access:** Admin Dashboard → Quick Actions → "Parent Links"

**Features:**

#### Individual Code Generation
- Navigate to parent linking management screen
- Expand student card
- Click "Generate Code"
- System creates unique 8-character code

#### Bulk Code Generation
- Click "Generate All Missing Codes"
- System generates codes for all students without active codes
- Shows progress and confirmation

**Code Properties:**
- **Format:** 8 uppercase alphanumeric characters (excluding similar chars: O/0, I/1)
- **Example:** `ABCD1234`
- **Validity:** 365 days by default
- **Status:** Active → Used / Expired / Revoked

#### Code Management Features
- Copy to clipboard
- Share dialog with instructions
- Export all codes as CSV
- Visual status indicators
- Creation date tracking

---

### 2. Parent Registration Flow

**Location:** `lib/screens/auth/parent_registration_screen.dart`

**Access:** Login screen → "Parent? Register with Student Code" button

#### Step 1: Code Entry
Parent enters their unique 8-character code

**Validation Process:**
1. Code format check (8 characters)
2. Database lookup in `studentLinkCodes` collection
3. Status verification (must be `active`)
4. Expiry check
5. Student information retrieval

**On Success:** Shows student name and proceeds to registration

**On Failure:** Error message with guidance to contact school

#### Step 2: Account Creation
Parent creates their account:
- Full name
- Email address (becomes login)
- Password (minimum 8 characters)
- Password confirmation

**Backend Actions:**
1. Creates Firebase Auth account
2. Creates parent document in `schools/{schoolId}/parents`
3. Links parent ID to student's `parentIds` array
4. Adds student ID to parent's `linkedChildren` array
5. Marks code as `used` with timestamp
6. Creates notification for teacher

#### Step 3: Success
- Welcome message
- Direct navigation to parent home screen
- Immediate access to student's reading logs

---

### 3. Parent Linking Service

**Location:** `lib/services/parent_linking_service.dart`

**Key Functions:**

```dart
// Generate unique code for student
createLinkCode({
  required String studentId,
  required String schoolId,
  required String createdBy,
  int validityDays = 365,
})

// Generate codes for multiple students
generateBulkCodes({
  required List<String> studentIds,
  required String schoolId,
  required String createdBy,
})

// Verify code during parent registration
verifyCode(String code)

// Link parent to student
linkParentToStudent({
  required String code,
  required String parentUserId,
  required String parentEmail,
})

// Get active code for student
getActiveCodeForStudent(String studentId)

// Revoke code
revokeCode({
  required String codeId,
  required String revokedBy,
  String? reason,
})

// Unlink parent from student
unlinkParentFromStudent({
  required String schoolId,
  required String studentId,
  required String parentUserId,
})
```

---

## Implementation Details

### Data Models

#### 1. SchoolOnboardingModel
**Location:** `lib/data/models/school_onboarding_model.dart`

```dart
enum OnboardingStatus {
  demo,           // Initial request
  interested,     // Demo scheduled
  registered,     // Account created
  setupInProgress,// Completing wizard
  active,         // Fully operational
  suspended,      // Temporarily inactive
}

enum OnboardingStep {
  schoolInfo,     // Step 1
  adminAccount,   // Step 2
  readingLevels,  // Step 3
  importData,     // Step 4 (future)
  inviteTeachers, // Step 5 (future)
  completed,      // All done
}
```

**Key Fields:**
- `schoolName`, `contactEmail`, `contactPhone`
- `status`, `currentStep`, `completedSteps`
- `schoolId`, `adminUserId` (set during creation)
- `estimatedStudentCount`, `estimatedTeacherCount`
- `demoScheduledAt`, `registrationCompletedAt`

---

#### 2. StudentLinkCodeModel
**Location:** `lib/data/models/student_link_code_model.dart`

```dart
enum LinkCodeStatus {
  active,   // Ready to use
  used,     // Parent registered
  expired,  // Past expiry date
  revoked,  // Manually cancelled
}
```

**Key Fields:**
- `studentId`, `schoolId`, `code`
- `status`, `createdAt`, `expiresAt`
- `createdBy` (teacher/admin who created)
- `usedBy`, `usedAt` (parent who used it)
- `revokedBy`, `revokedAt`, `revokeReason`

---

### Firestore Structure

```
firestore/
├── schoolOnboarding/           # Top-level collection
│   └── {onboardingId}/
│       ├── schoolName
│       ├── contactEmail
│       ├── status
│       ├── currentStep
│       └── ...
│
├── studentLinkCodes/           # Top-level collection
│   └── {codeId}/
│       ├── code: "ABCD1234"
│       ├── studentId
│       ├── schoolId
│       ├── status
│       ├── createdBy
│       ├── usedBy
│       └── ...
│
├── notifications/              # Top-level collection
│   └── {notificationId}/
│       ├── type: "parent_linked"
│       ├── schoolId
│       ├── studentId
│       ├── parentUserId
│       └── ...
│
└── schools/
    └── {schoolId}/
        ├── name, settings, etc.
        ├── users/              # Teachers, admins
        ├── parents/            # Parent accounts
        ├── students/           # Student profiles
        │   └── {studentId}/
        │       ├── firstName, lastName
        │       ├── parentIds: ["parent1", "parent2"]
        │       └── ...
        ├── classes/
        ├── readingLogs/
        └── allocations/
```

---

### Security Rules

**Location:** `firestore.rules`

Key security implementations:

```javascript
// School onboarding - anyone can create demo requests
match /schoolOnboarding/{onboardingId} {
  allow create: if true;
  allow read, update: if isOwner();
}

// Student link codes - readable by anyone for verification
match /studentLinkCodes/{codeId} {
  allow read: if true;  // For parent registration
  allow create: if isSchoolAdminOrTeacher();
  allow update: if isSchoolAdminOrTeacher() || isCodeUser();
  allow delete: if isSchoolAdmin();
}

// Notifications
match /notifications/{notificationId} {
  allow read: if isRecipient();
  allow create: if isSignedIn();
  allow update: if isRecipient();
}
```

---

## User Flows

### Flow 1: School Onboarding (Complete Journey)

1. **Discovery**
   - School learns about Lumi
   - Visits app login screen
   - Clicks "School? Request a Demo"

2. **Demo Presentation**
   - Views 6-slide interactive demo
   - Learns about features
   - Can skip directly to registration

3. **Demo Request**
   - Fills out school information
   - Submits request
   - Creates `schoolOnboarding` document

4. **Registration Wizard**
   - **Step 1:** School details (name, address, contact)
   - **Step 2:** Admin account (creates Firebase Auth + user document)
   - **Step 3:** Reading level system selection
   - **Step 4:** Completion and welcome

5. **First Login**
   - Admin logs in with created credentials
   - Lands on admin dashboard
   - Sees quick actions including "Parent Links"

---

### Flow 2: Parent Registration & Linking

1. **Code Receipt**
   - Teacher/admin generates code for student
   - School sends code to parent (email, letter, etc.)
   - Parent receives code like `ABCD1234`

2. **Registration Start**
   - Parent opens Lumi app
   - Clicks "Parent? Register with Student Code"

3. **Code Verification**
   - Enters 8-character code
   - System validates:
     - Code exists
     - Code is active (not used/expired/revoked)
     - Student exists
   - Shows student name for confirmation

4. **Account Creation**
   - Parent enters:
     - Full name
     - Email address
     - Password (2x for confirmation)
   - System creates:
     - Firebase Auth account
     - Parent document in database
     - Links parent to student
     - Marks code as used
     - Sends notification to teacher

5. **Success & Access**
   - Welcome screen with celebration
   - Immediate access to student's dashboard
   - Can start logging reading

---

### Flow 3: Admin Managing Parent Links

1. **Access Management Screen**
   - Admin logs in
   - Dashboard → Quick Actions → "Parent Links"

2. **View Dashboard**
   - See statistics:
     - Total students
     - Codes generated
     - Parents linked
   - View list of all students

3. **Generate Codes**

   **Option A: Individual**
   - Expand student card
   - Click "Generate Code"
   - Copy code
   - Share with parent

   **Option B: Bulk**
   - Click "Generate All Missing Codes"
   - System creates codes for all students without codes
   - Export CSV with all codes

4. **Manage Codes**
   - View code status
   - Copy to clipboard
   - Share via dialog
   - Export for distribution
   - Track which students have parents linked

---

## Security & Privacy

### Code Security

**Code Generation:**
- Cryptographically random
- 8 characters (36^8 = 2.8 trillion combinations)
- Excludes similar characters (O/0, I/1, etc.)
- Unique across entire system

**Code Validation:**
- Must be active status
- Must not be expired
- Must not be already used
- Student must exist and be active

**Code Lifecycle:**
- Created: Status = `active`
- Used: Status = `used`, `usedBy` and `usedAt` recorded
- Expired: Automatic after validity period
- Revoked: Manual by admin with reason

---

### Data Privacy

**Parent Access:**
- Parents can ONLY access data for their linked students
- Cannot see other students or classes
- Cannot modify school settings

**Audit Trail:**
- All code creation logged with creator ID
- All code usage logged with parent ID and timestamp
- Linking events create notifications
- Firestore security rules enforce access

**GDPR Compliance Ready:**
- Minimal data collection
- Clear consent in registration
- Ability to unlink parent
- Data export capabilities

---

## Admin Guide

### Setting Up Parent Access

#### Step 1: Import Students
Use the CSV import feature to bulk-import students:
```csv
firstName,lastName,studentId,classId,dateOfBirth
John,Doe,12345,class1,2010-05-15
Jane,Smith,12346,class1,2011-03-20
```

#### Step 2: Generate Link Codes
1. Navigate to Admin Dashboard → "Parent Links"
2. Click "Generate All Missing Codes"
3. Wait for bulk generation to complete
4. Export codes as CSV

#### Step 3: Distribute Codes to Parents
Create welcome letters including:
- Student name
- Unique 8-character code
- Registration instructions
- App download links
- Support contact

**Example Letter Template:**
```
Dear Parent/Guardian,

Welcome to Lumi Reading Diary!

Your child: [Student Name]
Your link code: [ABCD1234]

To get started:
1. Download Lumi Reading Diary from [App Store/Play Store]
2. Open the app and click "Parent? Register with Student Code"
3. Enter your code: [ABCD1234]
4. Create your account
5. Start logging reading!

Questions? Contact [school@email.com]

Happy Reading!
[School Name]
```

#### Step 4: Monitor Registrations
- Check linking management screen regularly
- Green checkmark = parent linked
- Yellow pending = code generated but not used
- Follow up with parents who haven't registered

---

### Managing Codes

#### Generate Code for Single Student
```
1. Open Parent Linking Management
2. Find student in list
3. Expand student card
4. Click "Generate Code"
5. Copy or share code
```

#### Bulk Operations
```
1. Click "Generate All Missing Codes"
2. Click "Export All Codes" (top-right download icon)
3. Paste into Excel/Google Sheets
4. Use for mail merge or bulk communication
```

#### Revoke Code
```
1. Find student in list
2. Expand card
3. View code details
4. Click "Revoke" (if available)
5. Enter reason
6. Confirm
```

**When to Revoke:**
- Code was sent to wrong parent
- Security concern
- Need to generate new code
- Parent no longer has custody

#### Unlink Parent
```
1. Navigate to student profile
2. View linked parents
3. Select parent to unlink
4. Confirm action
```

**When to Unlink:**
- Parent request
- Custody change
- Student graduated/transferred
- Data correction needed

---

## Troubleshooting

### Common Issues

#### Issue: "Code not found or invalid"
**Causes:**
- Code mistyped (check O/0, I/1)
- Code expired
- Code already used
- Code revoked

**Solution:**
1. Verify code spelling
2. Check code status in admin panel
3. Generate new code if needed
4. Resend to parent

---

#### Issue: Parent can't see their child
**Causes:**
- Registration not complete
- Code not properly linked
- Student marked inactive
- Database sync issue

**Solution:**
1. Check `students/{studentId}/parentIds` array
2. Check `parents/{parentId}/linkedChildren` array
3. Verify both contain correct IDs
4. Re-link if necessary

---

#### Issue: Bulk code generation fails
**Causes:**
- Too many students (timeout)
- Network issues
- Insufficient permissions

**Solution:**
1. Generate codes in batches (by class)
2. Check internet connection
3. Verify admin permissions
4. Check Firestore quotas

---

#### Issue: Parent registered but code still shows "active"
**Causes:**
- Link process incomplete
- Error during registration
- Database update failed

**Solution:**
1. Check code status in Firestore
2. Verify parent document exists
3. Check student's `parentIds` array
4. Manually update code status if needed

---

### Support Contacts

**For Schools:**
- Technical support: [support email]
- Onboarding assistance: [onboarding email]

**For Parents:**
- Direct parents to school administrator
- School provides first-line support
- Escalate to Lumi support if needed

---

## Appendix

### File Structure

```
lib/
├── data/models/
│   ├── school_onboarding_model.dart
│   └── student_link_code_model.dart
│
├── services/
│   ├── onboarding_service.dart
│   └── parent_linking_service.dart
│
└── screens/
    ├── onboarding/
    │   ├── school_demo_screen.dart
    │   ├── demo_request_screen.dart
    │   └── school_registration_wizard.dart
    ├── auth/
    │   ├── login_screen.dart          (updated)
    │   └── parent_registration_screen.dart
    └── admin/
        ├── admin_home_screen.dart     (updated)
        └── parent_linking_management_screen.dart
```

### Database Collections

| Collection | Purpose | Security |
|------------|---------|----------|
| `schoolOnboarding` | Track school registration progress | Owner + admins |
| `studentLinkCodes` | Store parent linking codes | Public read, admin write |
| `notifications` | Parent linking notifications | Recipient only |
| `schools/{schoolId}/students` | Student profiles | School members |
| `schools/{schoolId}/parents` | Parent accounts | School members |
| `schools/{schoolId}/users` | Staff accounts | School members |

### API Reference

#### OnboardingService

```dart
// Create demo request
Future<String> createDemoRequest({...})

// Create school and admin
Future<Map<String, String>> createSchoolAndAdmin({...})

// Complete onboarding step
Future<void> completeStep(String onboardingId, OnboardingStep step)

// Complete entire onboarding
Future<void> completeOnboarding(String onboardingId)
```

#### ParentLinkingService

```dart
// Generate single code
Future<StudentLinkCodeModel> createLinkCode({...})

// Generate bulk codes
Future<Map<String, StudentLinkCodeModel>> generateBulkCodes({...})

// Verify code
Future<StudentLinkCodeModel?> verifyCode(String code)

// Link parent
Future<bool> linkParentToStudent({...})

// Manage codes
Future<void> revokeCode({...})
Future<void> unlinkParentFromStudent({...})
```

---

## Conclusion

This onboarding and linking system provides:

✅ Professional school onboarding experience
✅ Secure, simple parent linking process
✅ Comprehensive admin management tools
✅ Audit trails and security measures
✅ Scalable architecture for growth

**Estimated Setup Times:**
- School onboarding: 15 minutes
- Parent registration: 3-5 minutes
- Bulk code generation: 1-2 minutes for 100+ students

For questions or support, refer to the main README.md or contact the development team.

---

**Version:** 1.0.0
**Last Updated:** 2025-11-05
**Author:** Lumi Development Team
